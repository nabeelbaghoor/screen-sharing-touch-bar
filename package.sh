#!/bin/zsh
# Builds the app and packages it for sharing: dist/ScreenSharingTouchBar-<version>.dmg and .zip
set -e
cd "$(dirname "$0")"
./build.sh --no-install
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
NAME="ScreenSharingTouchBar-$VERSION"
rm -rf dist && mkdir -p dist/stage
cp -R build/ScreenSharingTouchBar.app dist/stage/
ln -s /Applications dist/stage/Applications
cp README.md "dist/stage/Read Me.md"
# hdiutil occasionally fails with "Resource busy" on CI runners, so retry a few times.
for attempt in 1 2 3; do
  hdiutil create -volname "Screen Sharing Touch Bar" -srcfolder dist/stage -ov -format UDZO "dist/$NAME.dmg" >/dev/null && break
  [[ $attempt == 3 ]] && exit 1
  sleep 5
done
(cd build && ditto -c -k --keepParent ScreenSharingTouchBar.app "../dist/$NAME.zip")
rm -rf dist/stage
ls -lh dist
