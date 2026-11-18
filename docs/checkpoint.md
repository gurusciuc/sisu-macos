# macOS checkpoint · 18 November 2026

Version **0.1.0-alpha.5** fixes the “Frame load interrupted” and “cancelled” dialogs during normal browsing and download cancellation. The Mac build uses AppKit controls, system WebKit and the Rust tab and address model. The Windows implementation lives in [gurusciuc/sisu](https://github.com/gurusciuc/sisu).

## Verified on Apple Silicon

In alpha.4, a local HTTP 204 response and a download handoff each produced the frame-interruption alert. Declining a download destination also produced the cancellation alert. The alpha.5 regression check verified that 204 and 205 responses (including a binary MIME type) preserve the current document and draft without opening a dialog. In the packaged build, cancelling the native save sheet returned to the fixture page, a deliberately dropped connection displayed a network error, and the signed-out YouTube homepage rendered with its search field. All nine Rust release tests and all five native test launches passed.

The alpha.4 build passed Rust formatting and all nine release tests. Swift compiled for arm64 and the packaged app passed strict signature verification. Settings opened the JSON chooser. A separate harness linked the app's importer and profile code and exercised it with synthetic records and a localhost server. The server received cookies only on the intended host and path. JavaScript could see the ordinary fixture cookie and could not see its HttpOnly companion. The persistent record survived restart, and the expired record and fresh private store sent no imported cookies.

In alpha.3, a native title bar double-click expanded the window from 1200 to 1470 points wide and a tab strip double-click restored it. Command-T displayed the wallpaper and left the address bar ready for input.

The alpha.2 acceptance run also verified the following.

- Mouse selection and the new tab button worked with the full tabs visible below the macOS title bar. Double-clicking the blank strip filled the screen and restored the original width.
- A draft typed into a local page survived creating a tab, changing to left tabs and switching back. Command-W offered to keep the tab and Command-Q prompted again before quitting. A prior build of this alpha also exited with status zero through Command-Q.
- The native Settings buttons changed appearance and search engine. A Google query submitted from the new tab page returned desktop results, with search filters and a side panel, in system WebKit 22625.2.8.11.9. The localhost test also matched the HTTP and JavaScript browser identities.
- The localhost runner verified same-document and draft preservation across layout and theme changes, background tab closing, ordinary cookie and local storage persistence across restart, fresh private sessions, and selected blocking and exception rules. The initial four launches exited with status zero. The final launch was held open for mouse and keyboard checks.

Run `tools/native-check.mjs` against an extracted bundle to reproduce the controlled runtime checks. The runner uses its own profile identifier. It does not open the ordinary profile.

## Chrome Web Store

The user now requires direct Store installation. Apple's WebKit extension API accepts compatible local folders and ZIPs and has different API coverage. The installed WebKit preview has no extension installer. [Apple's compatibility guide](https://developer.apple.com/documentation/safariservices/assessing-your-safari-web-extension-s-browser-compatibility)

Two lab builds of the Mac CEF reference shell (CEF 156.0.30, Chromium 156.0.8078.96) tested the same Store listing. The separately created persistent request context returned “Installation is not enabled.” Using CEF's global request context with a fresh dedicated persistent profile brought up Chromium's native permission prompt for Google Translate. The prompt requested access to all websites. Install completion remains unverified. [Google Translate listing](https://chromewebstore.google.com/detail/google-translate/aapbdbdomjkkjkaonfhkkikfgjllcleb)

A replacement foundation must demonstrate a signed Store installation, permission consent, restart persistence, removal and updates before it replaces the WebKit preview. Check browser-level installation separately from extension popups and tab/window identity in the Sisu interface.

## Remaining work

- Measure full application, WebContent, GPU and networking physical footprint in a process group isolated from the test host. Match the workload, viewport and profile before comparing with Safari.
- Verify further blocking exceptions, downloads, popups, file upload, media prompts, real-site logins, accessibility, IME and mixed-DPI behavior.
- Handle general page-defined beforeunload and recover from crashes. Existing close protection applies to detected edits.
- Add bookmark HTML import and the library interface.
- Developer ID signing, notarization, installer and update security, and production release review.

## Primary platform references

- [AppKit and WebKit integration](https://developer.apple.com/documentation/webkit/webkit-for-appkit-and-uikit)
- [Persistent and private profile data stores](https://webkit.org/blog/14423/building-profiles-with-new-webkit-api/)
- [WebKit extension controller](https://developer.apple.com/documentation/webkit/wkwebextensioncontroller)
- [WebKit memory inspection](https://docs.webkit.org/Infrastructure/MemoryInspection.html)
