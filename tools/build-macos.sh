#!/bin/sh
# Native macOS candidate; one system WebKit engine, shared Rust policy/model.
set -eu
cd "$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
out=${1:-dist/webkit-macos}
target=${CARGO_TARGET_DIR:-target}
if [ -e "$out/Sisu-WebKit-Preview-macos.zip" ]; then echo 'Choose a fresh output directory.' >&2;exit 1;fi
cargo fmt --all -- --check
cargo test --release --locked --no-default-features --features mac-core --lib --test policy --test import --test cookies
cargo rustc --release --locked --no-default-features --features mac-core --lib --crate-type staticlib
cargo build --release --locked --no-default-features --features mac-core --bin webkit-rules
stage=$(mktemp -d /private/tmp/sisu-webkit.XXXXXX)
trap 'rm -rf "$stage"' EXIT HUP INT TERM
app="$stage/Sisu WebKit Preview.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
"$target/release/webkit-rules" "$app/Contents/Resources"
sdk=$(xcrun --sdk macosx --show-sdk-path)
xcrun swiftc -O -whole-module-optimization -swift-version 5 -sdk "$sdk" -target "$(uname -m)-apple-macos14.0" -module-cache-path "$target/swift-modules" -import-objc-header native/macos/Core.h -framework AppKit -framework WebKit -framework Security -framework SystemConfiguration -framework CoreFoundation -lresolv -Xlinker -dead_strip native/macos/*.swift "$target/release/libsisu_core.a" -o "$app/Contents/MacOS/sisu-webkit"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Sisu WebKit Preview</string>
<key>CFBundleDisplayName</key><string>Sisu WebKit Preview</string>
<key>CFBundleIdentifier</key><string>org.sisu.webkit.preview</string>
<key>CFBundleExecutable</key><string>sisu-webkit</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>0.1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSCameraUsageDescription</key><string>Allow a website you choose to use your camera.</string>
<key>NSMicrophoneUsageDescription</key><string>Allow a website you choose to use your microphone.</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoadsInWebContent</key><true/></dict>
</dict></plist>
PLIST
version=$(sed -n 's/^version = "\([^"]*\)"/\1/p' Cargo.toml | head -1)
/usr/libexec/PlistBuddy -c "Add :SisuVersion string $version" "$app/Contents/Info.plist"
cp LICENSE NOTICE THIRD_PARTY.md "$app/Contents/Resources/"
cp -R notices "$app/Contents/Resources/"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
mkdir -p "$out"
ditto -c -k --norsrc --noextattr --keepParent "$app" "$out/Sisu-WebKit-Preview-macos.zip"
echo "Local WebKit candidate: $out/Sisu-WebKit-Preview-macos.zip ($(uname -m))"
echo 'Ad-hoc signed local preview. Extension packages and general beforeunload close handling remain acceptance gates.'
