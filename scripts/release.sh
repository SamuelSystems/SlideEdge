#!/bin/zsh
# Builds a release of SlideEdge into dist/: a universal SlideEdge.app, a .zip and a .dmg.
#
#   ./scripts/release.sh                  # build with the version in the project
#   ./scripts/release.sh --version 1.0    # set the version in the project, then build
#   ./scripts/release.sh --adhoc          # ad-hoc signature, e.g. for public GitHub releases
#
# Build number: a timestamp (YYYYMMDDHHMM), so every release build is unique.
# The binary is stripped: debug symbols stay in the .dSYM next to the build, so build paths
# from this machine do not ship.
#
# Signing: the project's signing (Config/Local.xcconfig, usually Apple Development) unless a
# "Developer ID Application" identity is in the keychain, in which case the app and the DMG are
# signed with it. --adhoc skips both: an Apple Development certificate carries the owner's
# e-mail address, which then ships inside every downloaded copy.
# Notarization: set NOTARY_PROFILE to a profile saved with
#   xcrun notarytool store-credentials <name> --apple-id <id> --team-id <team>
# and the DMG is notarized, then the ticket is stapled to the DMG and to the app.
set -euo pipefail
cd "${0:A:h}/.."

PROJECT=SlideEdge.xcodeproj
DIST=dist
BUILD=build/Release
APP_NAME=SlideEdge.app
ADHOC=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            [[ "${2:-}" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || { echo "error: --version needs X.Y or X.Y.Z" >&2; exit 1; }
            sed -i '' "s/MARKETING_VERSION = [0-9.]*;/MARKETING_VERSION = $2;/g" "$PROJECT/project.pbxproj"
            echo "==> Version set to $2"
            shift 2
            ;;
        --adhoc)
            ADHOC=1
            shift
            ;;
        *)
            echo "usage: $0 [--version X.Y[.Z]] [--adhoc]" >&2
            exit 1
            ;;
    esac
done

BUILD_NUMBER=$(date +%Y%m%d%H%M)
SIGNING_OVERRIDES=()
(( ADHOC )) && SIGNING_OVERRIDES=(CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)

echo "==> Tests"
swift test --package-path Packages/SlideEdgeKit 2>&1 | grep -E "Test run with|✘|error:" || true
swift test --package-path Packages/SlideEdgeKit >/dev/null 2>&1 || { echo "error: tests failed" >&2; exit 1; }

rm -rf "$DIST"
mkdir -p "$DIST"

echo "==> Build Release $BUILD_NUMBER (arm64 + x86_64)"
xcodebuild -quiet \
    -project "$PROJECT" \
    -scheme SlideEdge \
    -configuration Release \
    -derivedDataPath "$BUILD" \
    -destination 'generic/platform=macOS' \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES STRIP_STYLE=non-global \
    "${SIGNING_OVERRIDES[@]}" \
    build 2>&1 | grep -v -e appintentsmetadataprocessor -e IDERunDestination || true
[[ -d "$BUILD/Build/Products/Release/$APP_NAME" ]] || { echo "error: build failed" >&2; exit 1; }

ditto "$BUILD/Build/Products/Release/$APP_NAME" "$DIST/$APP_NAME"
APP="$DIST/$APP_NAME"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")

DEVELOPER_ID=""
if (( ! ADHOC )); then
    DEVELOPER_ID=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application[^"]*"' | head -1 | tr -d '"' || true)
fi
if [[ -n "$DEVELOPER_ID" ]]; then
    echo "==> Sign with $DEVELOPER_ID"
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
fi
codesign --verify --strict "$APP"

echo "==> DMG"
DMG="$DIST/SlideEdge-$VERSION.dmg"
STAGING=$(mktemp -d)
ditto "$APP" "$STAGING/$APP_NAME"
ln -s /Applications "$STAGING/Applications"
hdiutil create -quiet -volname "SlideEdge $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO "$DMG"
rm -rf "$STAGING"
[[ -n "$DEVELOPER_ID" ]] && codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"

if [[ -n "$DEVELOPER_ID" && -n "${NOTARY_PROFILE:-}" ]]; then
    echo "==> Notarize (this takes a few minutes)"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    # The DMG's ticket also covers the app inside it: staple the standalone app too.
    xcrun stapler staple "$APP"
fi

ditto -c -k --keepParent "$APP" "$DIST/SlideEdge-$VERSION.zip"

echo "==> SlideEdge $VERSION ($BUILD_NUMBER)"
echo "    archs: $(lipo -archs "$APP/Contents/MacOS/SlideEdge")"
SIGNER=$(codesign -dv --verbose=2 "$APP" 2>&1 | grep '^Authority=' | head -1 | cut -d= -f2 || true)
echo "    signed by: ${SIGNER:-ad-hoc}"
if spctl --assess --type execute "$APP" 2>/dev/null; then
    echo "    Gatekeeper: accepted"
else
    echo "    Gatekeeper: not notarized (other Macs: System Settings → Privacy & Security → Open Anyway)"
fi
ls -lh "$DIST" | tail -n +2
