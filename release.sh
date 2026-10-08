#!/bin/zsh
# SPDX-License-Identifier: MIT
# Maintainer release: builds a universal app signed with a Developer ID, notarizes and staples it,
# packages a signed DMG and a zip, and publishes the GitHub release for the version in Info.plist.
#
# One-time setup on the release Mac:
#   1. A "Developer ID Application" certificate in the login keychain (Xcode > Settings > Accounts >
#      Manage Certificates > + > Developer ID Application).
#   2. A notarytool keychain profile:
#        xcrun notarytool store-credentials sstb-notary --apple-id <email> --team-id <TEAMID>
#
# Usage: TEAM_ID=<TEAMID> ./release.sh [--no-publish]
set -e
cd "$(dirname "$0")"
: "${TEAM_ID:?Set TEAM_ID to the Developer ID team, for example TEAM_ID=ABCDE12345}"
PROFILE="${NOTARY_PROFILE:-sstb-notary}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
TAG="v$VERSION"
NAME="ScreenSharingTouchBar-$VERSION"
APP=build/ScreenSharingTouchBar.app

# Pick the Developer ID certificate for exactly this team, so other teams on the Mac are never used.
IDENTITY_LINE=$(security find-identity -v -p codesigning | grep "Developer ID Application: .*(${TEAM_ID})" | head -1)
[[ -n "$IDENTITY_LINE" ]] || { echo "No Developer ID Application certificate for team $TEAM_ID in the keychain."; exit 1; }
export SIGN_HASH=$(echo "$IDENTITY_LINE" | awk '{print $2}')
export SIGN_OPTS="--options runtime --timestamp"
echo "Signing as: $(echo "$IDENTITY_LINE" | cut -d'"' -f2)"

if [[ "$1" != "--no-publish" ]] && gh release view "$TAG" >/dev/null 2>&1; then
  echo "Release $TAG already exists. Bump CFBundleShortVersionString in Info.plist first."; exit 1
fi

./build.sh --no-install
codesign --verify --strict --verbose=2 "$APP"

notarize() {  # $1 = file to submit
  xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait --timeout 30m | tee build/notary.log
  grep -q "status: Accepted" build/notary.log || { echo "Notarization failed for $1"; exit 1; }
}

# 1) Notarize the app itself and staple the ticket, so it works offline after being copied out.
rm -rf dist && mkdir -p dist/stage
ditto -c -k --keepParent "$APP" build/notarize-app.zip
notarize build/notarize-app.zip
xcrun stapler staple "$APP"

# 2) Package the stapled app, sign the DMG, notarize and staple it too.
cp -R "$APP" dist/stage/
ln -s /Applications dist/stage/Applications
cp README.md "dist/stage/Read Me.md"
for attempt in 1 2 3; do
  hdiutil create -volname "Screen Sharing Touch Bar" -srcfolder dist/stage -ov -format UDZO "dist/$NAME.dmg" >/dev/null && break
  [[ $attempt == 3 ]] && exit 1
  sleep 5
done
rm -rf dist/stage
codesign --force --timestamp --sign "$SIGN_HASH" "dist/$NAME.dmg"
notarize "dist/$NAME.dmg"
xcrun stapler staple "dist/$NAME.dmg"
(cd build && ditto -c -k --keepParent ScreenSharingTouchBar.app "../dist/$NAME.zip")

# 3) Check Gatekeeper accepts both.
spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "dist/$NAME.dmg"
ls -lh dist

if [[ "$1" != "--no-publish" ]]; then
  awk -v v="$VERSION" 'index($0, "## [" v "]") == 1 {f=1; next} /^## /{f=0} f' CHANGELOG.md > build/notes.md
  printf '\n### Install\nDownload the `.dmg` and drag the app to Applications. It is signed and notarized by Apple. Then allow it in System Settings > Privacy & Security > Accessibility and relaunch it.\n' >> build/notes.md
  git tag -a "$TAG" -m "Screen Sharing Touch Bar $VERSION"
  git push origin "$TAG"
  gh release create "$TAG" dist/* --title "Screen Sharing Touch Bar $VERSION" --notes-file build/notes.md
fi
