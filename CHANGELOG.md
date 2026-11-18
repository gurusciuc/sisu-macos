# Changelog

## 0.1.0-alpha.5 · 18 November 2026

- Keep the current page open when a server returns HTTP 204 or 205.
- Dismiss cancelled navigations and downloads quietly, including the handoff from a page load to the save dialog. Genuine load and download failures still surface.

## 0.1.0-alpha.4 · 18 November 2026

- Import Windows-compatible JSON cookie exports into the ordinary WebKit profile from File or Settings.
- Validate cookie scope and security attributes before writes. Skip expired cookies and reject exports with partitioned cookies or domain cookies on public suffixes.

## 0.1.0-alpha.3 · 18 November 2026

- Add Inner Citadel, a Stoic dotted wallpaper that follows the new tab page's light or dark appearance.
- Add 120 ms button hover transitions, 150 ms tab selection transitions and a half-second wallpaper entrance. All three respect Reduce Motion.
- Double-click the empty macOS title bar or browser tab strip to fill the usable display and restore the previous size.

## 0.1.0-alpha.2 · 18 November 2026

- Port the Windows design for tabs, navigation, new tab search and Settings to native AppKit controls.
- Move the browser controls below the macOS title bar so each tab is fully visible and clickable. The empty strip supports window dragging and double-click fill or restore.
- Keep open pages live when switching between top and left tabs. Add an adjustable sidebar width.
- Send Safari compatibility tokens with the Sisu browser identity so sites such as Google can serve their desktop layout.

## 0.1.0-alpha.1 · 17 November 2026

Initial independent Mac foundation: AppKit interface, system WebKit and Rust tab/address policy. The Windows project remains separate. This is a source alpha checkpoint with native runtime and memory acceptance still in progress; it is not a production browser release.
