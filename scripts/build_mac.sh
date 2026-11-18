#!/usr/bin/env bash
# Build the macOS app on a Mac, then wrap it in a drag-to-Applications disk image.
#
#   ./scripts/build_mac.sh              # release .app + .dmg in dist/
#   ./scripts/build_mac.sh --no-dmg     # .app only
#
# Requirements: Flutter SDK (3.24+), Xcode command line tools, macOS host.
set -euo pipefail

cd "$(dirname "$0")/.."

# pubspec carries "1.0.0+1" — keep the build number out of the artifact name.
RAW_VERSION="$(grep -m1 '^version:' pubspec.yaml | sed 's/version: //')"
VERSION="${RAW_VERSION%%+*}"
BUILD_NUMBER="${RAW_VERSION##*+}"
[[ "$BUILD_NUMBER" == "$RAW_VERSION" ]] && BUILD_NUMBER=1
APP_NAME="Pomodoro Clock"
BUILD_DIR="build/macos/Build/Products/Release"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DIST_DIR="dist"
ARTIFACT_PATH="$DIST_DIR/PomodoroClock-$VERSION-macos.zip"
STAGING="$DIST_DIR/staging"

make_dmg=1
for arg in "$@"; do
  case "$arg" in
    --no-dmg) make_dmg=0 ;;
    *) echo "unknown option: $arg" >&2 && exit 2 ;;
  esac
done

echo "==> Resolving dependencies"
flutter pub get

echo "==> Enabling macOS desktop"
flutter config --enable-macos-desktop >/dev/null

echo "==> Building release (this takes a few minutes the first time)"
flutter build macos --release --build-name "$VERSION" --build-number "$BUILD_NUMBER"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build reported success but $APP_PATH is missing." >&2
  exit 1
fi

# Ad-hoc signature keeps the app launchable on the machine that built it.
# Replace "-" with your Developer ID for distribution:
#   codesign --force --deep --options runtime --sign "Developer ID Application: You" "$APP_PATH"
echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP_PATH" >/dev/null 2>&1 || \
  echo "   (codesign skipped; app still runs locally)"

mkdir -p "$DIST_DIR"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

if [[ "$make_dmg" == "1" ]]; then
  echo "==> Creating disk image"
  hdiutil create \
    -volname "PomodoroClock" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DIST_DIR/PomodoroClock-$VERSION-macos.dmg" >/dev/null
  echo "    -> $DIST_DIR/PomodoroClock-$VERSION-macos.dmg"
else
  echo "==> Zipping .app"
  ditto -c -k --keepParent "$STAGING/$APP_NAME.app" "$ARTIFACT_PATH"
  echo "    -> $ARTIFACT_PATH"
fi

rm -rf "$STAGING"

echo
echo "Done. Install by opening the .dmg and dragging 'Pomodoro Clock' to Applications."
echo "Run it straight from the build folder with:"
echo "  open \"$APP_PATH\""
