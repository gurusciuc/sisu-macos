# macOS foundation checkpoint · 17 November 2026

Version **0.1.0-alpha.1**. The user authorized an independent Mac repository and a platform-specific foundation. The Mac priority is lowest practical measured memory with WebKit extension limits. Windows remains in https://github.com/gurusciuc/sisu.

## Implemented and compiled

The candidate has native AppKit controls, one Rust tab model, WebKit content views, top/left tab layouts, address policy, native new-tab and Settings, profile separation, converted blocking rules, edit-close protection and native file/download/permission routing. The CEF engine is not linked or packaged.

During development the Apple Silicon release compiled and locally ad-hoc signed. Three Rust model/FFI tests and six existing policy/import/cookie tests passed. These results do not establish runtime acceptance.

## Still requiring native acceptance

- Fresh and restarted ordinary cookies/local storage, HttpOnly scope and independent private launches.
- Native input, same-document/draft preservation across tabs, layouts and themes; close cancellation and keyboard/Command-Q behavior.
- Real compiled-rule enforcement, exception scope and known unsupported list conversion. No scriptlet or full adblock-rust parity claim.
- Downloads, popups, file upload, media prompts, real-site logins, accessibility, IME and mixed-DPI behavior.
- General page-defined beforeunload handling, crash recovery, complete extension hosting and provider workflows.
- Full attributable physical-footprint comparisons with matched workloads, including Safari. No memory advantage has been recorded yet.
- Developer ID signing, notarization, installer/update security and production release review.

## Primary platform references

- [AppKit and WebKit integration](https://developer.apple.com/documentation/webkit/webkit-for-appkit-and-uikit)
- [Persistent and private profile data stores](https://webkit.org/blog/14423/building-profiles-with-new-webkit-api/)
- [WebKit extension controller](https://developer.apple.com/documentation/webkit/wkwebextensioncontroller)
- [WebKit memory inspection](https://docs.webkit.org/Infrastructure/MemoryInspection.html)
