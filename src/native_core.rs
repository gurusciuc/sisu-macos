//! Narrow, process-local C ABI for the AppKit shell. No web content bridge.
use serde::{Deserialize, Serialize};
use std::ffi::{CString, c_char};

#[derive(Default, Serialize)]
struct Tabs {
    tabs: Vec<u64>,
    selected: Option<u64>,
    #[serde(skip)]
    next: u64,
}

#[derive(Deserialize)]
#[serde(tag = "op", rename_all = "snake_case", deny_unknown_fields)]
enum Command {
    Snapshot,
    New,
    Select {
        id: u64,
    },
    Close {
        id: u64,
    },
    Move {
        id: u64,
        index: usize,
    },
    Resolve {
        input: String,
        #[serde(default)]
        google: bool,
    },
}

impl Tabs {
    fn command(&mut self, command: Command) -> Result<serde_json::Value, &'static str> {
        match command {
            Command::Snapshot => {}
            Command::New => {
                if self.tabs.len() >= 256 {
                    return Err("Tab limit reached");
                }
                self.next = self.next.checked_add(1).ok_or("Tab identifier exhausted")?;
                self.tabs.push(self.next);
                self.selected = Some(self.next);
            }
            Command::Select { id } => {
                if !self.tabs.contains(&id) {
                    return Err("Unknown tab");
                }
                self.selected = Some(id);
            }
            Command::Close { id } => {
                let index = self
                    .tabs
                    .iter()
                    .position(|tab| *tab == id)
                    .ok_or("Unknown tab")?;
                self.tabs.remove(index);
                if self.selected == Some(id) {
                    self.selected = self
                        .tabs
                        .get(index.min(self.tabs.len().saturating_sub(1)))
                        .copied();
                }
            }
            Command::Move { id, index } => {
                if index >= self.tabs.len() {
                    return Err("Invalid tab position");
                }
                let old = self
                    .tabs
                    .iter()
                    .position(|tab| *tab == id)
                    .ok_or("Unknown tab")?;
                self.tabs.remove(old);
                self.tabs.insert(index, id);
            }
            Command::Resolve { input, google } => {
                return Ok(
                    serde_json::json!({"destination":crate::destination_for(&input,google)}),
                );
            }
        }
        serde_json::to_value(self).map_err(|_| "State encoding failed")
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn sisu_core_create() -> *mut std::ffi::c_void {
    Box::into_raw(Box::new(Tabs::default())).cast()
}

/// # Safety
/// `core` must be a live pointer from sisu_core_create, used serially on the UI
/// thread. `bytes` must identify `length` readable bytes for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sisu_core_command(
    core: *mut std::ffi::c_void,
    bytes: *const u8,
    length: usize,
) -> *mut c_char {
    if core.is_null() || bytes.is_null() || length > 16_384 {
        return std::ptr::null_mut();
    }
    let input = unsafe { std::slice::from_raw_parts(bytes, length) };
    let result = serde_json::from_slice::<Command>(input)
        .map_err(|_| "Invalid command")
        .and_then(|command| unsafe { &mut *core.cast::<Tabs>() }.command(command));
    let value = match result {
        Ok(value) => value,
        Err(error) => serde_json::json!({"error":error}),
    };
    CString::new(value.to_string())
        .map(CString::into_raw)
        .unwrap_or(std::ptr::null_mut())
}

/// # Safety
/// Pass an unfreed response returned by sisu_core_command, or null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sisu_core_free(response: *mut c_char) {
    if !response.is_null() {
        drop(unsafe { CString::from_raw(response) });
    }
}

/// # Safety
/// Pass an unfreed pointer from sisu_core_create after its final command.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sisu_core_destroy(core: *mut std::ffi::c_void) {
    if !core.is_null() {
        drop(unsafe { Box::from_raw(core.cast::<Tabs>()) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn closing_background_and_selected_tabs_keeps_order_and_survivor() {
        let mut state = Tabs::default();
        for _ in 0..3 {
            state.command(Command::New).unwrap();
        }
        state.command(Command::Close { id: 1 }).unwrap();
        assert_eq!(state.tabs, vec![2, 3]);
        assert_eq!(state.selected, Some(3));
        state.command(Command::Close { id: 3 }).unwrap();
        assert_eq!(state.selected, Some(2));
        state.command(Command::Close { id: 2 }).unwrap();
        assert_eq!(state.selected, None);
        assert!(state.command(Command::Select { id: 2 }).is_err());
    }
    #[test]
    fn reordering_preserves_selection_and_invalid_commands_preserve_state() {
        let mut state = Tabs::default();
        for _ in 0..3 {
            state.command(Command::New).unwrap();
        }
        state.command(Command::Move { id: 3, index: 0 }).unwrap();
        assert_eq!(state.tabs, vec![3, 1, 2]);
        assert_eq!(state.selected, Some(3));
        assert!(state.command(Command::Move { id: 3, index: 9 }).is_err());
        assert_eq!(state.tabs, vec![3, 1, 2]);
    }
    #[test]
    fn ffi_rejects_oversized_and_untrusted_commands() {
        let core = sisu_core_create();
        let command = br#"{"op":"resolve","input":"javascript:alert(1)"}"#;
        let response = unsafe { sisu_core_command(core, command.as_ptr(), command.len()) };
        let text = unsafe { std::ffi::CStr::from_ptr(response) }
            .to_str()
            .unwrap();
        assert_eq!(text, r#"{"destination":null}"#);
        unsafe { sisu_core_free(response) };
        assert!(unsafe { sisu_core_command(core, command.as_ptr(), 16_385) }.is_null());
        unsafe { sisu_core_destroy(core) };
    }
}
