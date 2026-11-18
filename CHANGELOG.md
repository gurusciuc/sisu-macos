# Changelog

## 0.1.0-alpha.2 · 18 November 2026

- Port the Windows design for tabs, navigation, new tab search and Settings to native AppKit controls.
- Move the browser controls below the macOS title bar so each tab is fully visible and clickable. The empty strip supports window dragging and double-click fill or restore.
- Keep open pages live when switching between top and left tabs. Add an adjustable sidebar width.
- Send Safari compatibility tokens with the Sisu browser identity so sites such as Google can serve their desktop layout.

## 0.1.0-alpha.1 · 17 November 2026

Initial independent Mac foundation: AppKit interface, system WebKit and Rust tab/address policy. The Windows project remains separate. This is a source alpha checkpoint with native runtime and memory acceptance still in progress; it is not a production browser release.
