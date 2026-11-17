# Sisu for macOS

**0.1.0-alpha.1 — an experimental native Mac browser.** AppKit owns the interface, system WebKit renders websites, and Rust owns tab order, selection, address policy and blocking-list conversion. There is no Chromium, CEF, Electron or web runtime for the controls.

The Windows implementation is maintained separately in [gurusciuc/sisu](https://github.com/gurusciuc/sisu). The platforms can use different engines and native interfaces. The priority for this Mac candidate is lowest practical measured memory, with WebKit extension limitations accepted. No memory advantage over Safari has been established yet.

## Build

Requires macOS 14+, Apple's Command Line Tools and the Rust toolchain pinned in `rust-toolchain.toml`. Full Xcode, CMake and Ninja are not required.

```sh
./tools/build-macos.sh dist/alpha1
ditto -x -k dist/alpha1/Sisu-WebKit-Preview-macos.zip /Applications
open '/Applications/Sisu WebKit Preview.app'
```

The archive targets the Mac used to build it. It is not universal. It contains the native executable, converted blocking lists and license notices; WebKit comes from macOS. Local ad-hoc signatures are verified. Developer ID signing, notarization and distribution acceptance remain open.

## Current implementation

- Native top/left tabs, address/search, navigation, zoom, native new-tab view and Settings. One Rust tab model drives the same live content views.
- Persistent ordinary WebKit data stores and independent nonpersistent private stores. Private preferences remain in memory.
- Compiled WebKit content rules exported from the hash-pinned EasyList/EasyPrivacy inputs. Conversion is partial; the bundled report records the counts and hash. Scriptlets and equivalent adblock-rust coverage are not promised.
- Native dialogs, file-picker, download destination and media-permission routing. TLS and WebKit's content-process sandbox are retained.
- Isolated-world edit monitoring asks before closing tabs with detected edits. No automatic tab discard is enabled. General page-defined beforeunload close handling is a release gate.

Rust release tests and native compilation passed during development. Runtime coverage, performance results and unresolved defects are recorded in [docs/checkpoint.md](docs/checkpoint.md). Compilation is not functional acceptance.

## Validation

Use `BROWSER_TEST_HOME` for controlled tests; it creates an independent WebKit store identifier rather than using a personal store. `--private` uses a fresh nonpersistent store. `--url=http://localhost:PORT/` selects a controlled fixture.

An explicit `--test-control=stdio` launch additionally requires `BROWSER_TEST_HOME`. This process-local test transport has no socket or webpage command bridge. Its JavaScript evaluation is restricted to loopback fixture pages. Normal launches do not read test commands. Remote debugging and inspectable web views are not enabled.

Chrome-extension parity is not a Mac goal for this candidate. WebKit has its own extension API; actual package installation, permissions and provider workflows are not implemented or accepted yet. No AI sidebar substitutes for an extension.

## License

Apache-2.0 for original Sisu code. Preserve [NOTICE](NOTICE), [THIRD_PARTY.md](THIRD_PARTY.md) and upstream notices. Filter-list data retains its upstream license. This repository reuses the original Rust policy/parsers from [Sisu](https://github.com/gurusciuc/sisu).
