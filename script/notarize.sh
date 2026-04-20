#!/bin/bash
#
# Notarize a signed .app via notarytool and staple the ticket.
#
# Usage:
#   NOTARY_PROFILE="wishper-notary" script/notarize.sh path/to/Wishper.app
#
# Prerequisite (one-time) — store App Store Connect API credentials in the
# Keychain under a named profile:
#
#   xcrun notarytool store-credentials "wishper-notary" \
#       --apple-id your@apple.id \
#       --team-id TEAMID \
#       --password <app-specific-password>
#
# Credentials live in the login Keychain; pass the profile name as
# NOTARY_PROFILE.

set -euo pipefail

APP="${1:-}"
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
    echo "usage: $0 path/to/Wishper.app" >&2
    exit 1
fi

if [ -z "${NOTARY_PROFILE:-}" ]; then
    echo "error: NOTARY_PROFILE env var not set" >&2
    echo "  store once: xcrun notarytool store-credentials <profile> --apple-id ... --team-id ... --password <app-specific>" >&2
    exit 1
fi

ZIP=$(mktemp -u -t wishper-notarize).zip
trap 'rm -f "$ZIP"' EXIT

echo "[notarize] zipping $APP → $ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "[notarize] submitting to Apple"
xcrun notarytool submit "$ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "[notarize] stapling ticket"
xcrun stapler staple "$APP"

echo "[notarize] verifying"
xcrun stapler validate "$APP"
spctl -a -t exec -vv "$APP"
echo "[notarize] ✓ done"
