#!/usr/bin/env bash
# Builds, signs, and (when configured) notarizes CPA Widget for distribution.
#
# Usage:
#   scripts/release.sh                 # build + sign + verify (+ notarize if NOTARY_PROFILE is set)
#
# Environment:
#   SIGN_IDENTITY   Codesign identity. Default: "Developer ID Application" (auto-selected).
#                   Use "-" for an ad-hoc signature (runs on this Mac only; not Gatekeeper-approved).
#   TEAM_ID         Apple team ID. Default: 832V4PV6C6 (from the project).
#   NOTARY_PROFILE  Keychain profile created with `xcrun notarytool store-credentials`.
#                   When unset, the app is signed but not notarized.
#   OUT_DIR         Output directory. Default: dist/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/CPA Widget.xcodeproj"
SCHEME="CPA Widget"
APP_NAME="CPA Widget"
TEAM_ID="${TEAM_ID:-832V4PV6C6}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
OUT_DIR="${OUT_DIR:-$ROOT/dist}"
DERIVED="$ROOT/build/release-derived"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# 1. Confirm the signing identity exists before spending time on a build.
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  if ! security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    die "no '$SIGN_IDENTITY' certificate in the keychain. Developer ID needs an Apple Developer Program membership; see the notes in this script's header, or set SIGN_IDENTITY=- for an ad-hoc build."
  fi
fi

# 2. Clean Release build with the project's own signing settings overridden to our identity.
log "Building $APP_NAME (Release)"
rm -rf "$DERIVED"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$DERIVED" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  build | tail -n 3

APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
[[ -d "$APP" ]] || die "build did not produce $APP"

# 3. Re-sign the bundle deeply with the hardened runtime and a secure timestamp.
#    Entitlements come from the built app so the sandbox and network grants match the project.
log "Signing with '$SIGN_IDENTITY'"
# The release entitlements omit get-task-allow (a debugging grant that must not ship).
ENTITLEMENTS="$ROOT/scripts/release-entitlements.plist"
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGN_IDENTITY" "$APP"

# 4. Verify the signature and, for a real identity, that Gatekeeper accepts it.
log "Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  spctl --assess --type execute --verbose=4 "$APP" || \
    echo "warning: Gatekeeper rejected the app until it is notarized (expected without NOTARY_PROFILE)."
fi

# 5. Package and, when a notary profile is configured, notarize and staple.
mkdir -p "$OUT_DIR"
ZIP="$OUT_DIR/$APP_NAME.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if [[ -n "$NOTARY_PROFILE" ]]; then
  log "Notarizing (this waits for Apple)"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose=4 "$APP"
  # Re-zip so the shared archive contains the stapled app.
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
else
  log "Skipping notarization (set NOTARY_PROFILE to enable)"
fi

rm -rf "$OUT_DIR/$APP_NAME.app"
ditto "$APP" "$OUT_DIR/$APP_NAME.app"
log "Done: $OUT_DIR/$APP_NAME.app and $ZIP"
