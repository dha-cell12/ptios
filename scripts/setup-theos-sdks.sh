#!/usr/bin/env bash
set -euo pipefail

: "${THEOS:?THEOS must point to the installed Theos directory}"
test -d "$THEOS"
mkdir -p "$THEOS/sdks"

# Git creates writable directories and checks out SDK symlinks directly. Avoid
# ZIP extraction permissions and keep the patched private-framework SDKs.
# Staging lives under the disposable runner temp directory, outside the checkout.
sdk_stage=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/tlink-sdks.XXXXXX")
git -c core.symlinks=true clone --quiet --depth=1 --single-branch --branch master \
  https://github.com/theos/sdks.git "$sdk_stage/source"

iphone_sdks=0
for sdk in "$sdk_stage/source/"*.sdk; do
  test -d "$sdk" || continue
  sdk_name=${sdk##*/}
  # Recursive copying preserves the relative framework/header symlinks.
  cp -R "$sdk" "$THEOS/sdks/"
  case "$sdk_name" in
    iPhoneOS*.sdk)
      test -f "$THEOS/sdks/$sdk_name/SDKSettings.plist"
      iphone_sdks=$((iphone_sdks + 1))
      ;;
  esac
  printf 'Installed SDK: %s\n' "$sdk_name"
done

if [ "$iphone_sdks" -eq 0 ]; then
  printf 'No usable iPhoneOS SDK found in the Theos SDK checkout\n' >&2
  exit 1
fi
printf 'Theos SDK revision: %s (%s iPhoneOS SDKs)\n' \
  "$(git -C "$sdk_stage/source" rev-parse HEAD)" "$iphone_sdks"
