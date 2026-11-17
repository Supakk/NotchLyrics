#!/bin/bash
# Builds Notchu.app and packs it into dist/Notchu.dmg with an Applications shortcut,
# ready to attach to a GitHub release as the download the website links to.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=$(scripts/build-app.sh | tail -1)
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f dist/Notchu.dmg
hdiutil create -volname "Notchu $VERSION" -srcfolder "$STAGE" -ov -format UDZO dist/Notchu.dmg >/dev/null
rm -rf "$STAGE"
echo "$PWD/dist/Notchu.dmg"
