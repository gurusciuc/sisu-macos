# macOS checkpoint · 18 November 2026

Version **0.1.0-alpha.7** packages the latest WebKit build as `Sisu.app`. Its existing bundle identifier and profile location carry over. The Mac build uses AppKit controls, system WebKit and the Rust tab and address model. The Windows implementation lives in [gurusciuc/sisu](https://github.com/gurusciuc/sisu).

## Unreleased changes · 19 November 2026

`tools/build-macos.sh` passed with a fresh output directory: formatting, all nine Rust tests, the Swift build, strict signature verification and image verification. `tools/native-check.mjs` passed all seven checks across five launches against the packaged app. A test-profile run closed the only tab, then a Settings tab and a new tab. Each time Sisu kept the window and opened a new tab page.

The dithered wallpaper renders a 368 × 193 cell field in about 1 ms per frame on Apple Silicon, about 2% of one core at its 20 fps cap. It pauses when the page is hidden, the window is occluded or Sisu is not the active app. Offscreen renders checked both themes at 1200 and 760 points. Live animation in an on-screen window was not captured because the test host lacks screen-recording permission. JavaScript and Lockdown Mode now apply per navigation. Sisu never turns off a system-wide Lockdown Mode. Choosing Deny for camera and microphone stops active capture in open tabs.

## Verified on Apple Silicon

In alpha.6, a native AppKit check sampled the left edge, middle and right edge of pressed tabs in both themes. All three positions had the same fill, the corners stayed rounded and releasing the button restored its prior appearance. The check exercised selected and unselected tabs in the top bar and the narrowest sidebar. Hit-testing routed the icon, title and padding to tab selection and the visible close button to its own action.

All nine Rust tests passed. The first packaged run passed the tab checks but read an older local-storage marker after a quick restart. A fresh run passed all five launches, including ordinary and private profile checks. The intermittent storage result remains open.

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

On macOS 15.4 and later, alpha.7 installs compatible extensions in ordinary windows from the native **Add to Sisu** button or the manager in Settings. Sisu requires CRX3 signatures from the extension publisher and Chrome Web Store and verifies the package again when restoring it. Local testing installed Mini Calculator 1.0.0, opened its popup and confirmed it was available after quitting and relaunching.

The Store versions of Proton Pass 1.43.0 and Mars VPN 1.2.0 require APIs that Sisu’s WebKit implementation cannot supply. Proton Pass requires `chrome.offscreen` and Mars requires `chrome.proxy` and `chrome.offscreen`, among others. [Apple’s compatibility guide](https://developer.apple.com/documentation/safariservices/assessing-your-safari-web-extension-s-browser-compatibility)

## Profile, close protection and HTTPS

- The rapid-restart fixture writes a fresh marker, reads it in the renderer and quits immediately. On the original app one of eight launches read the previous persistent marker. The build that releases WebKit views during quit passed a subsequent eight-launch test, including two private launches. Public WKWebsiteDataStore has no localStorage flush guarantee. The intermittent persistence issue remains open.
- The public WKWebView API does not expose the native beforeunload close-confirmation hook. Sisu prompts for trusted form edits in tabs, windows and across windows when quitting. A page that relies only on a custom beforeunload handler may still close without a prompt.
- An HTTPS response that redirected to `http://example.com/` ended at `https://example.com/` under WebKit on the tested Mac. Explicit HTTP loopback pages loaded with the **Not Secure** label. Older-system checks at response time prevent displaying an insecure redirect, but may occur after a cleartext request has been sent.

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
