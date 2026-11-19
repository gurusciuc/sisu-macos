# Changelog

## Unreleased

- Redraw the Inner Citadel new-tab wallpaper as animated ordered-dither pixels. A light travels round the ring and the outer contours turn slowly. Animation runs only while the page is visible in the active app; Reduce Motion shows a still frame.
- Closing the last tab opens a new tab page instead of closing the window. Settings can restore the old behaviour. Add File → Close Window (⇧⌘W) and File → Print… (⌘P).
- Expand Settings with the public WebKit options: page zoom, minimum font size, pop-ups, JavaScript, full screen, text selection, site compatibility fixes, incremental rendering, print backgrounds, swipe, pinch zoom, Force Click previews, Tab-key links, autoplay, AirPlay, camera and microphone, inline predictions, fraudulent website warning, Lockdown Mode, Web Inspector, a custom user agent, downloads to ~/Downloads, and clearing cache or website data. Ordinary windows share changes immediately.
- Centre the icon and title of the blocking button so its padding is equal, and stop disabled buttons showing hover.

## 0.1.0-alpha.7 · 18 November 2026

- Lift the dark browser chrome and new-tab background to charcoal.
- Install compatible signed Chrome Web Store extensions from the Sisu toolbar on macOS 15.4 or later.
- Prefer HTTPS, mark unencrypted pages, and expose opt-in Web Inspector for the active tab.
- Confirm discarding detected edits when closing a tab, closing a window or quitting.

- Ship the first downloadable Apple Silicon alpha as a drag-to-Applications disk image.
- Include File → Import Site Shortcuts… from the local shortcuts build.
- Build a single Mac app named Sisu. Finder, the app menu and the About panel all use that name. The existing bundle identifier and browsing profile carry over from the WebKit Preview.

## 0.1.0-alpha.6 · 18 November 2026

- Pressing a tab highlights its full rounded shape in the tab bar and sidebar. The close button keeps its own target.

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
