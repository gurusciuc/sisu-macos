pub mod bookmarks;
pub mod cookies;
#[cfg(feature = "mac-core")]
mod native_core;
#[cfg(feature = "mac-core")]
mod store_package;
use adblock::{Engine, request::Request};

/// Only build-generated, hash-pinned list bytes enter the native deserializer.
pub struct Filter(Engine);
impl Filter {
    pub fn bundled() -> Result<Self, String> {
        let mut engine = Engine::default();
        engine
            .deserialize(include_bytes!(concat!(env!("OUT_DIR"), "/rules.bin")))
            .map_err(|e| e.to_string())?;
        Ok(Self(engine))
    }
    pub fn blocks(&self, url: &str, source: &str, kind: &str, method: &str) -> bool {
        Request::new(url, source, kind, method)
            .ok()
            .is_some_and(|r| self.0.check_network_request(&r).should_block())
    }
    pub fn css(&self, url: &str) -> String {
        let mut sheet = String::new();
        for selector in self.0.url_cosmetic_resources(url).hide_selectors {
            sheet.push_str(&selector);
            sheet.push_str(" { display: none !important; }\n");
        }
        sheet
    }
}

/// Resolve user-committed omnibox input. Typing alone never contacts a provider.
pub fn destination(input: &str) -> Option<String> {
    destination_for(input, false)
}
pub fn destination_for(input: &str, google: bool) -> Option<String> {
    let input = input.trim();
    if input.is_empty() || input.chars().any(char::is_control) {
        return None;
    }
    if !input.contains(char::is_whitespace) {
        let first = input.split('/').next()?;
        let with_scheme = input.contains("://");
        if with_scheme
            || first.contains('.')
            || first.starts_with('[')
            || first.split(':').next() == Some("localhost")
        {
            let url = if with_scheme {
                url::Url::parse(input)
            } else {
                url::Url::parse(&format!("https://{input}"))
            }
            .ok()?;
            return (matches!(url.scheme(), "https" | "http")
                && url.host().is_some()
                && url.username().is_empty()
                && url.password().is_none())
            .then(|| url.to_string());
        }
        if url::Url::parse(input).is_ok() {
            return None;
        }
    }
    let mut url = url::Url::parse(if google {
        "https://www.google.com/search"
    } else {
        "https://duckduckgo.com/"
    })
    .ok()?;
    url.query_pairs_mut().append_pair("q", input);
    Some(url.to_string())
}
