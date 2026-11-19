#!/usr/bin/env bash
# Builds build/NextMeeting.app (release, signed). `--install` also copies it to /Applications.
#
#   SIGN_IDENTITY="NextMeeting Local Signing" scripts/build-app.sh --install
#
# SIGN_IDENTITY defaults to "-" (ad-hoc). See README for why a stable identity helps.
set -euo pipefail

cd "$(dirname "$0")/.."

INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

APP_NAME="NextMeeting"
APP="build/$APP_NAME.app"
IDENTITY="${SIGN_IDENTITY:--}"

echo "==> swift build -c release"
swift build -c release --product "$APP_NAME"
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> codesign (identity: $IDENTITY)"
codesign --force --options runtime --timestamp=none \
  --entitlements Resources/NextMeeting.entitlements \
  --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

if [[ "$INSTALL" == 1 ]]; then
  DEST="/Applications/$APP_NAME.app"
  echo "==> installing to $DEST"
  if pgrep -x "$APP_NAME" >/dev/null; then
    osascript -e "tell application id \"com.goelalex.NextMeeting\" to quit" >/dev/null 2>&1 || pkill -x "$APP_NAME" || true
    sleep 1
  fi
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  echo "Installed. Run: open $DEST"
else
  echo "Built $APP"
fi
