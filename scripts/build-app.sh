#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH=/tmp/notchlyrics-clang
SWIFT="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
"$SWIFT" build -c release --scratch-path /tmp/notchlyrics-release --disable-sandbox
BIN_DIR=$("$SWIFT" build -c release --scratch-path /tmp/notchlyrics-release --show-bin-path)
APP="$PWD/dist/NotchLyrics.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/NotchLyrics" "$APP/Contents/MacOS/NotchLyrics"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string NotchLyrics' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "$APP"
