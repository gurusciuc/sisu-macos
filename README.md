<p align="center"><strong>English</strong> · <a href="README.ro.md">Română</a></p>

<p align="center"><img src="resources/branding/sisu.png" alt="Sisu" width="88" height="88"></p>

<h1 align="center">Sisu</h1>

<p align="center">A native Mac browser with top or sidebar tabs, built with AppKit and system WebKit.</p>

<p align="center">
  <a href="https://github.com/gurusciuc/sisu-macos/releases/tag/v0.1.0-alpha.7"><img alt="0.1.0-alpha.7" src="https://img.shields.io/badge/release-0.1.0--alpha.7-46546A"></a>
  <a href="https://github.com/gurusciuc/sisu-macos/actions/workflows/check.yml"><img alt="macOS CI" src="https://github.com/gurusciuc/sisu-macos/actions/workflows/check.yml/badge.svg?branch=main"></a>
  <img alt="macOS 14+ · Apple Silicon" src="https://img.shields.io/badge/macOS-14%2B%20%7C%20Apple%20Silicon-30343B">
  <a href="LICENSE"><img alt="Apache 2.0" src="https://img.shields.io/badge/license-Apache%202.0-586A48"></a>
</p>

<p align="center"><strong><a href="https://github.com/gurusciuc/sisu-macos/releases/download/v0.1.0-alpha.7/Sisu-0.1.0-alpha.7-macOS-arm64.dmg">Download for Apple Silicon</a></strong> · <a href="https://github.com/gurusciuc/sisu-macos/releases/tag/v0.1.0-alpha.7">Release notes</a> · <a href="https://github.com/gurusciuc/sisu">Sisu for Windows</a></p>

## Install on Apple Silicon

Download the DMG from the [alpha.7 release](https://github.com/gurusciuc/sisu-macos/releases/tag/v0.1.0-alpha.7), open it, drag **Sisu** into **Applications** and eject the disk image. Requires macOS 14 or later. This alpha uses an ad-hoc signature and has no Apple notarization. Gatekeeper may block first launch. [Apple’s guide to opening apps](https://support.apple.com/en-us/102445)

## Build from source

Requires macOS 14+, Apple's Command Line Tools and the Rust toolchain pinned in `rust-toolchain.toml`. Full Xcode, CMake and Ninja are not required.

```sh
./tools/build-macos.sh dist/alpha7
```

The disk image targets the architecture of the Mac used to build it. It contains the native executable, converted blocking lists and license notices; WebKit comes from macOS. Local ad-hoc signatures are verified. Developer ID signing, notarization and distribution acceptance remain open.

## Current implementation

- Native top/left tabs, address/search, navigation, zoom, native new-tab view and Settings. One Rust tab model drives the same live content views.
- **File → Import Site Shortcuts…** adds links from a chosen JSON file to the ordinary new-tab page.
- The Inner Citadel wallpaper, drawn as animated dithered pixels, frames new tab search in both themes. Short transitions for dots, tabs and buttons respect macOS Reduce Motion.
- Persistent ordinary WebKit data stores and independent nonpersistent private stores. Private preferences remain in memory.
- **Settings → Browser data → Import cookies…** accepts a JSON array or an object with a `cookies` array, in the same format as Sisu for Windows. Importing may replace matching cookies in the ordinary Sisu profile. Expired records are skipped. Files with partitioned cookies or attributes that cannot be represented are rejected before changes are made.
- Compiled WebKit content rules exported from the hash-pinned EasyList/EasyPrivacy inputs. Conversion is partial; the bundled report records the counts and hash. Scriptlets and equivalent adblock-rust coverage are not promised.
- Sisu tries HTTPS for ordinary navigation and labels explicitly opened HTTP pages **Not Secure**. TLS validation and WebKit’s process sandbox stay enabled.
- Use **Browser menu → Allow Web Inspector** for the current tab. Open the tab’s inspector from Safari’s **Develop** menu. [WebKit guide](https://webkit.org/blog/13936/enabling-the-inspection-of-web-content-in-apps/)
- Sisu asks before closing tabs or windows with detected form edits, including when you quit. See the checkpoint for page-defined `beforeunload` limits.

Validation results and remaining work are recorded in [docs/checkpoint.md](docs/checkpoint.md).

## Validation

Use `BROWSER_TEST_HOME` for controlled tests; it creates an independent WebKit store identifier rather than using a personal store. `--private` uses a fresh nonpersistent store. `--url=http://localhost:PORT/` selects a controlled fixture.

An explicit `--test-control=stdio` launch additionally requires `BROWSER_TEST_HOME`. This process-local test transport has no socket or webpage command bridge. Its JavaScript evaluation is restricted to loopback fixture pages. Normal launches do not read test commands. Page inspection stays off until enabled for a tab from the browser menu.

After copying Sisu from the disk image, pass its executable to the localhost runner.

```sh
node tools/native-check.mjs "/path/to/Sisu.app/Contents/MacOS/sisu-webkit" dist/native-check
node tools/rapid-storage.mjs "/path/to/Sisu.app/Contents/MacOS/sisu-webkit"
```

On macOS 15.4 or later, open **Settings → Extensions → Manage Extensions** to browse the Chrome Web Store, or visit a listing and click **Add to Sisu** in the browser toolbar. Sisu verifies the Store and publisher signatures, shows the requested permissions and runs compatible extensions with WebKit. Chrome APIs such as `chrome.offscreen` and `chrome.proxy` are unavailable. [Store test results](docs/checkpoint.md#chrome-web-store)

## License

Apache-2.0 for original Sisu code. Preserve [NOTICE](NOTICE), [THIRD_PARTY.md](THIRD_PARTY.md) and upstream notices. Filter-list data retains its upstream license. This repository reuses the original Rust policy/parsers from [Sisu](https://github.com/gurusciuc/sisu).
