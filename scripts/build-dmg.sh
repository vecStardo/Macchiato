#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/Macchiato.xcodeproj"
SCHEME="Macchiato"
CONFIGURATION="Release"
BUILD_DIR="$ROOT_DIR/build"
RELEASE_DIR="$BUILD_DIR/$CONFIGURATION"
APP_PATH="$RELEASE_DIR/Macchiato.app"
HELPER_PATH="$APP_PATH/Contents/MacOS/app.macchiato.Macchiato.PowerHelper"
DIST_DIR="$ROOT_DIR/dist"
DMG_ROOT="$DIST_DIR/Macchiato-dmg-root"
DMG_PATH="$DIST_DIR/Macchiato.dmg"
VOLUME_NAME="Macchiato"

fail() {
  echo "error: $*" >&2
  exit 1
}

ensure_no_debug_entitlement() {
  local target="$1"
  local entitlements

  entitlements="$(codesign -d --entitlements :- "$target" 2>/dev/null || true)"
  if grep -q "com.apple.security.get-task-allow" <<<"$entitlements"; then
    fail "$target contains debug entitlement com.apple.security.get-task-allow"
  fi
}

echo "Building $SCHEME $CONFIGURATION..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  SYMROOT="$BUILD_DIR" \
  "$@" \
  build

[[ -d "$APP_PATH" ]] || fail "missing app at $APP_PATH"
[[ -x "$HELPER_PATH" ]] || fail "missing helper at $HELPER_PATH"

echo "Verifying release signing shape..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
ensure_no_debug_entitlement "$APP_PATH"
ensure_no_debug_entitlement "$HELPER_PATH"

echo "Creating DMG..."
rm -rf "$DMG_ROOT"
rm -f "$DMG_PATH"
mkdir -p "$DMG_ROOT" "$DIST_DIR"

ditto "$APP_PATH" "$DMG_ROOT/Macchiato.app"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

hdiutil verify "$DMG_PATH"

echo "Built $DMG_PATH"
