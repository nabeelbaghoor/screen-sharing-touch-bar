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

# Sign with the local identity from make_signing_identity.sh when it exists, so macOS keeps the
# Accessibility permission across rebuilds; otherwise fall back to ad-hoc signing (CI, new machines).
# release.sh passes SIGN_HASH (Developer ID) and SIGN_OPTS (hardened runtime + timestamp) for notarized builds.
SIGN_NAME="${SIGN_IDENTITY:-ScreenSharingTouchBar Local Signing}"
SIGN_HASH="${SIGN_HASH:-$(security find-identity -p codesigning 2>/dev/null | awk -v n="\"$SIGN_NAME\"" 'index($0, n) {print $2; exit}')}"
if [[ -n "$SIGN_HASH" ]]; then
  codesign --force ${=SIGN_OPTS} --sign "$SIGN_HASH" "$APP"
  echo "Signed with $(codesign -dvv "$APP" 2>&1 | awk -F= '/^Authority=/{print $2; exit}')"
else
  codesign --force --sign - "$APP"
  echo "Signed ad-hoc (run ./make_signing_identity.sh once to keep permissions across rebuilds)"
fi
rm -rf build/tmp
echo "Built: $APP"

if [[ "$1" != "--no-install" ]]; then
  pkill -x ScreenSharingTouchBar 2>/dev/null || true
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/ScreenSharingTouchBar.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "Installed: $HOME/Applications/ScreenSharingTouchBar.app"
fi
