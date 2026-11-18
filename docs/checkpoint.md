# macOS checkpoint · 18 November 2026

Version **0.1.0-alpha.2** brings the Sisu for Windows design to the native Mac shell. The Windows implementation lives in [gurusciuc/sisu](https://github.com/gurusciuc/sisu). The Mac build uses AppKit controls, system WebKit and the Rust tab and address model. The priority remains low measured memory with WebKit's extension limits.

## Verified on Apple Silicon

The build passed Rust formatting and all nine release tests. Swift compiled for arm64 and the packaged app passed strict signature verification.

- Mouse selection and the new tab button worked with the full tabs visible below the macOS title bar. Double-clicking the blank strip filled the screen and restored the original width.
- A draft typed into a local page survived creating a tab, changing to left tabs and switching back. Command-W offered to keep the tab and Command-Q prompted again before quitting. A prior build of this alpha also exited with status zero through Command-Q.
- The native Settings buttons changed appearance and search engine. A Google query submitted from the new tab page returned desktop results, with search filters and a side panel, in system WebKit 22625.2.8.11.9. The localhost test also matched the HTTP and JavaScript browser identities.
- The localhost runner verified same-document and draft preservation across layout and theme changes, background tab closing, ordinary cookie and local storage persistence across restart, fresh private sessions, and selected blocking and exception rules. The initial four launches exited with status zero. The final launch was held open for mouse and keyboard checks.

Run `tools/native-check.mjs` against an extracted bundle to reproduce the controlled runtime checks. The runner uses its own profile identifier. It does not open the ordinary profile.

## Remaining work

- Measure full application, WebContent, GPU and networking physical footprint in a process group isolated from the test host. Match the workload, viewport and profile before comparing with Safari.
- Verify HttpOnly scope, further blocking exceptions, downloads, popups, file upload, media prompts, real-site logins, accessibility, IME and mixed-DPI behavior.
- Handle general page-defined beforeunload, recover from crashes and validate WebKit extension hosting. Existing close protection applies to detected edits.
- Developer ID signing, notarization, installer and update security, and production release review.

## Primary platform references

- [AppKit and WebKit integration](https://developer.apple.com/documentation/webkit/webkit-for-appkit-and-uikit)
- [Persistent and private profile data stores](https://webkit.org/blog/14423/building-profiles-with-new-webkit-api/)
- [WebKit extension controller](https://developer.apple.com/documentation/webkit/wkwebextensioncontroller)
- [WebKit memory inspection](https://docs.webkit.org/Infrastructure/MemoryInspection.html)
