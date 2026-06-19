#!/bin/sh
set -e

APP_PATH="${1:-layout/Applications/TLinkauto.app}"
IDENTITY="${CODESIGN_IDENTITY:-}"
ENTITLEMENTS="${ENTITLEMENTS:-layout/entitlements.plist}"

if [ ! -d "$APP_PATH" ]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

if [ -z "$IDENTITY" ]; then
  echo "Set CODESIGN_IDENTITY first, for example:" >&2
  echo "  export CODESIGN_IDENTITY='Apple Development: Your Name (TEAMID)'" >&2
  exit 1
fi

if [ -d "$APP_PATH/PlugIns/shortcutext.appex" ]; then
  codesign --force --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_PATH/PlugIns/shortcutext.appex"
fi

codesign --force --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
