#!/bin/zsh
# Builds Screen Sharing Touch Bar (universal: Apple silicon + Intel) and installs it to ~/Applications.
# Pass --no-install to only build into ./build.
set -e
cd "$(dirname "$0")"
APP=build/ScreenSharingTouchBar.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/tmp

# App icon: render the 1024px artwork, then every size macOS asks for.
clang -fobjc-arc -Wall -framework Cocoa make_icon.m -o build/tmp/make_icon
build/tmp/make_icon assets/AppIcon-1024.png
ICONSET=build/tmp/AppIcon.iconset
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s assets/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) assets/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

clang -fobjc-arc -O2 -Wall -arch arm64 -arch x86_64 -mmacosx-version-min=12.0 \
  -framework Cocoa -framework ApplicationServices -framework ServiceManagement \
  main.m -o "$APP/Contents/MacOS/ScreenSharingTouchBar"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
rm -rf build/tmp
echo "Built: $APP"

if [[ "$1" != "--no-install" ]]; then
  pkill -x ScreenSharingTouchBar 2>/dev/null || true
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/ScreenSharingTouchBar.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "Installed: $HOME/Applications/ScreenSharingTouchBar.app"
fi
