#!/bin/bash
# Builds dist/Notchu.app (release). Uses the private NotchuMotion package when it is
# checked out next to this repository, otherwise the open basic implementation.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
export CLANG_MODULE_CACHE_PATH=/tmp/notchu-clang
SWIFT="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
"$SWIFT" build -c release --scratch-path /tmp/notchu-release --disable-sandbox
BIN_DIR=$("$SWIFT" build -c release --scratch-path /tmp/notchu-release --show-bin-path)
APP="$PWD/dist/Notchu.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Notchu" "$APP/Contents/MacOS/Notchu"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string Notchu' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon' "$APP/Contents/Info.plist"
fi
# Ad-hoc signature: runs locally; a Developer ID signature and notarization are needed for
# Gatekeeper to open it without a warning on other Macs.
codesign --force --sign - "$APP"
echo "$APP"
