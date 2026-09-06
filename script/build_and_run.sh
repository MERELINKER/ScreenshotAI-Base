#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="ScreenshotAIBase"
BUNDLE_ID="app.codex.ScreenshotAIBase"
APP_VERSION="0.1.0"
APP_BUILD="${SCREENSHOTAI_BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
MIN_SYSTEM_VERSION="14.0"
LOCAL_IDENTITY_NAME="ScreenshotAI Base Local Development"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRATCH_DIR="${SCREENSHOTAI_SCRATCH_PATH:-$ROOT_DIR/.build}"
BUILD_PACKAGE_DIR="${SCREENSHOTAI_PACKAGE_DIR:-$ROOT_DIR}"
DIST_DIR="$ROOT_DIR/dist"
APP_BUILD_DIR="${SCREENSHOTAI_APP_BUILD_DIR:-$ROOT_DIR/.build/app}"
APP_BUNDLE="$APP_BUILD_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
PKG_INFO="$APP_CONTENTS/PkgInfo"
ICON_FILE="$ROOT_DIR/Resources/AppIcon.icns"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ "$MODE" != "--build-only" && "$MODE" != "build-only" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

swift build --package-path "$BUILD_PACKAGE_DIR" --scratch-path "$BUILD_SCRATCH_DIR"
BUILD_BINARY="$(swift build --package-path "$BUILD_PACKAGE_DIR" --scratch-path "$BUILD_SCRATCH_DIR" --show-bin-path)/$APP_NAME"

mkdir -p "$APP_MACOS" "$APP_RESOURCES"
/bin/rm -f "$APP_BINARY" "$INFO_PLIST" "$PKG_INFO" "$APP_RESOURCES/AppIcon.icns"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -f "$ICON_FILE" ]]; then
  cp "$ICON_FILE" "$APP_RESOURCES/AppIcon.icns"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleSignature</key>
  <string>????</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
  </dict>
</dict>
</plist>
PLIST

printf 'APPL????' >"$PKG_INFO"

clean_bundle_metadata() {
  local bundle="${1:-$APP_BUNDLE}"
  [[ -d "$bundle" ]] || return

  /usr/bin/xattr -cr "$bundle" 2>/dev/null || true
  for attr in com.apple.FinderInfo "com.apple.fileprovider.fpfs#P" com.apple.provenance; do
    /usr/bin/xattr -d "$attr" "$bundle" 2>/dev/null || true
    /usr/bin/find "$bundle" -exec /usr/bin/xattr -d "$attr" {} \; 2>/dev/null || true
  done
}

find_signing_identity() {
  if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$CODE_SIGN_IDENTITY"
    return
  fi

  /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/awk -F '"' -v local="$LOCAL_IDENTITY_NAME" '
        $2 == local { print $2; exit }
        /Apple Development/ { print $2; exit }
      '
}

sign_app_bundle() {
  local identity
  identity="$(find_signing_identity)"

  if [[ -z "$identity" ]]; then
    identity="-"
    echo "warning: no Apple Development signing identity found; using ad-hoc signing." >&2
    echo "warning: macOS Screen Recording permission may need to be reset after rebuilds." >&2
  fi

  local tmp_dir signing_bundle
  tmp_dir="$(/usr/bin/mktemp -d /tmp/ScreenshotAI-sign.XXXXXX)"
  signing_bundle="$tmp_dir/$APP_NAME.app"

  clean_bundle_metadata "$APP_BUNDLE"
  /usr/bin/ditto --norsrc "$APP_BUNDLE" "$signing_bundle"
  clean_bundle_metadata "$signing_bundle"
  /usr/bin/codesign --force --deep --options runtime --sign "$identity" "$signing_bundle"
  clean_bundle_metadata "$signing_bundle"
  /bin/rm -rf "$APP_BUNDLE"
  /usr/bin/ditto --norsrc "$signing_bundle" "$APP_BUNDLE"
  clean_bundle_metadata "$APP_BUNDLE"
  /bin/rm -rf "$tmp_dir"
}

sign_app_bundle

register_launch_services() {
  [[ -x "$LSREGISTER" ]] || return

  local stale
  "$LSREGISTER" -u "$ROOT_DIR"/dist/"$APP_NAME.app" >/dev/null 2>&1 || true
  for stale in "$ROOT_DIR"/.worktrees/*/dist/"$APP_NAME.app"; do
    [[ -d "$stale" ]] || continue
    "$LSREGISTER" -u "$stale" >/dev/null 2>&1 || true
  done
}

register_launch_services

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --build-only|build-only)
    /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
    echo "built app: $APP_BUNDLE"
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
