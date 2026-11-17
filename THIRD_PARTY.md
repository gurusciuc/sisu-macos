# Third-party software and data

Original Sisu code is Apache-2.0. Shared Rust policy and parsers originate in [Sisu for Windows](https://github.com/gurusciuc/sisu), retaining the original contributors' attribution. The app includes LICENSE, NOTICE, this inventory and notices/. It ships no fonts.

| Component | Source | Attribution and terms |
| --- | --- | --- |
| AppKit and WebKit | Supplied by macOS; no engine framework is redistributed | Apple platform frameworks under the applicable macOS/SDK terms. |
| adblock-rust 0.13.5 | Unmodified upstream crate, used to export native WebKit content rules | Brave Software and contributors, MPL-2.0. Source: https://crates.io/crates/adblock/0.13.5. License in notices/adblock-MPL-2.0.txt. |
| EasyList and EasyPrivacy | Hash-pinned source files in rules/ | EasyList authors, CC BY-SA 3.0. Converted JSON retains those terms; its hash and conversion counts accompany the app. See notices/EasyList-CC-BY-SA-3.0.txt. |
| Rust dependencies | Cargo.lock | See notices/rust-dependencies.txt for package versions and licenses. Regenerate with node tools/cargo-notices.mjs. |

CEF and Chromium are not dependencies or packaged engines in this repository. CEF-related notice texts retained from the original project's notice directory are historical attribution, not a statement that those components are bundled.
