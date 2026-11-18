# Sisu for macOS

**0.1.0-alpha.5 — an experimental native Mac browser.** AppKit recreates Sisu for Windows' compact tabs, toolbar, new tab page and Settings. System WebKit renders websites, and Rust owns tab order, selection, address policy and blocking list conversion.

The Windows implementation is maintained separately in [gurusciuc/sisu](https://github.com/gurusciuc/sisu). The platforms can use different engines and native interfaces. The priority for this Mac candidate is lowest practical measured memory, with WebKit extension limitations accepted. No memory advantage over Safari has been established yet.

## Build

Requires macOS 14+, Apple's Command Line Tools and the Rust toolchain pinned in `rust-toolchain.toml`. Full Xcode, CMake and Ninja are not required.

```sh
./tools/build-macos.sh dist/alpha5
```

The archive targets the Mac used to build it. It is not universal. It contains the native executable, converted blocking lists and license notices; WebKit comes from macOS. Local ad-hoc signatures are verified. Developer ID signing, notarization and distribution acceptance remain open.

## Current implementation

- Native top/left tabs, address/search, navigation, zoom, native new-tab view and Settings. One Rust tab model drives the same live content views.
- The Inner Citadel wallpaper frames new tab search in both themes. Short transitions for dots, tabs and buttons respect macOS Reduce Motion.
- Persistent ordinary WebKit data stores and independent nonpersistent private stores. Private preferences remain in memory.
- **Settings → Browser data → Import cookies…** accepts a JSON array or an object with a `cookies` array, in the same format as Sisu for Windows. Importing may replace matching cookies in the ordinary Sisu profile. Expired records are skipped. Files with partitioned cookies or attributes that cannot be represented are rejected before changes are made.
- Compiled WebKit content rules exported from the hash-pinned EasyList/EasyPrivacy inputs. Conversion is partial; the bundled report records the counts and hash. Scriptlets and equivalent adblock-rust coverage are not promised.
- Native dialogs, file-picker, download destination and media-permission routing. TLS and WebKit's content-process sandbox are retained.
- Isolated-world edit monitoring asks before closing tabs with detected edits. No automatic tab discard is enabled. General page-defined beforeunload close handling is a release gate.

Validation results and remaining work are recorded in [docs/checkpoint.md](docs/checkpoint.md).

## Validation

Use `BROWSER_TEST_HOME` for controlled tests; it creates an independent WebKit store identifier rather than using a personal store. `--private` uses a fresh nonpersistent store. `--url=http://localhost:PORT/` selects a controlled fixture.

An explicit `--test-control=stdio` launch additionally requires `BROWSER_TEST_HOME`. This process-local test transport has no socket or webpage command bridge. Its JavaScript evaluation is restricted to loopback fixture pages. Normal launches do not read test commands. Remote debugging and inspectable web views are not enabled.

After extracting the archive to a temporary directory, pass the bundled executable to the localhost runner:

```sh
node tools/native-check.mjs "/path/to/Sisu WebKit Preview.app/Contents/MacOS/sisu-webkit" dist/native-check
```

The WebKit preview has no extension installer. Direct installation from the Chrome Web Store is a requirement for the next foundation evaluation. See the [Store test results](docs/checkpoint.md#chrome-web-store).

## License

Apache-2.0 for original Sisu code. Preserve [NOTICE](NOTICE), [THIRD_PARTY.md](THIRD_PARTY.md) and upstream notices. Filter-list data retains its upstream license. This repository reuses the original Rust policy/parsers from [Sisu](https://github.com/gurusciuc/sisu).
