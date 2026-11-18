# macOS checkpoint · 18 November 2026

Version **0.1.0-alpha.3** adds the Inner Citadel dotted wallpaper, short motion and double-click fill from the native title bar. The Mac build uses AppKit controls, system WebKit and the Rust tab and address model. The Windows implementation lives in [gurusciuc/sisu](https://github.com/gurusciuc/sisu).

## Verified on Apple Silicon

The alpha.3 build passed Rust formatting and all nine release tests. Swift compiled for arm64 and the packaged app passed strict signature verification. In the installed candidate's staged bundle, a native title bar double-click expanded the window from 1200 to 1470 points wide and a tab strip double-click restored it. Command-T displayed the wallpaper and left the address bar ready for input.

The alpha.2 acceptance run also verified the following.

- Mouse selection and the new tab button worked with the full tabs visible below the macOS title bar. Double-clicking the blank strip filled the screen and restored the original width.
- A draft typed into a local page survived creating a tab, changing to left tabs and switching back. Command-W offered to keep the tab and Command-Q prompted again before quitting. A prior build of this alpha also exited with status zero through Command-Q.
- The native Settings buttons changed appearance and search engine. A Google query submitted from the new tab page returned desktop results, with search filters and a side panel, in system WebKit 22625.2.8.11.9. The localhost test also matched the HTTP and JavaScript browser identities.
- The localhost runner verified same-document and draft preservation across layout and theme changes, background tab closing, ordinary cookie and local storage persistence across restart, fresh private sessions, and selected blocking and exception rules. The initial four launches exited with status zero. The final launch was held open for mouse and keyboard checks.

Run `tools/native-check.mjs` against an extracted bundle to reproduce the controlled runtime checks. The runner uses its own profile identifier. It does not open the ordinary profile.

## Chrome Web Store

The user now requires direct Store installation. Apple's WebKit extension API accepts compatible local folders and ZIPs and has different API coverage. The installed WebKit preview has no extension installer. [Apple's compatibility guide](https://developer.apple.com/documentation/safariservices/assessing-your-safari-web-extension-s-browser-compatibility)

A lab build of the existing Mac CEF reference shell (CEF 156.0.30, Chromium 156.0.8078.96) allowed extensions in a fresh persistent test profile. It loaded the Google Translate Store listing. After dismissing Google's browser recommendation, clicking Add to Chrome returned “Installation is not enabled.” The test did not install an extension. [Google Translate listing](https://chromewebstore.google.com/detail/google-translate/aapbdbdomjkkjkaonfhkkikfgjllcleb)

A replacement foundation must demonstrate a signed Store installation, permission consent, restart persistence, removal and updates before it replaces the WebKit preview. Check browser-level installation separately from extension popups and tab/window identity in the Sisu interface.

## Remaining work

- Measure full application, WebContent, GPU and networking physical footprint in a process group isolated from the test host. Match the workload, viewport and profile before comparing with Safari.
- Verify HttpOnly scope, further blocking exceptions, downloads, popups, file upload, media prompts, real-site logins, accessibility, IME and mixed-DPI behavior.
- Handle general page-defined beforeunload and recover from crashes. Existing close protection applies to detected edits.
- Add browser data import. The Mac preview currently has no import UI for the Windows cookie JSON and bookmark HTML formats.
- Developer ID signing, notarization, installer and update security, and production release review.

## Primary platform references

- [AppKit and WebKit integration](https://developer.apple.com/documentation/webkit/webkit-for-appkit-and-uikit)
- [Persistent and private profile data stores](https://webkit.org/blog/14423/building-profiles-with-new-webkit-api/)
- [WebKit extension controller](https://developer.apple.com/documentation/webkit/wkwebextensioncontroller)
- [WebKit memory inspection](https://docs.webkit.org/Infrastructure/MemoryInspection.html)
