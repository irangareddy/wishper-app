#!/bin/bash
#
# Sparkle-safe code signing for Wishper.
#
# Usage:
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
#     script/codesign.sh path/to/Wishper.app
#
# Signs Sparkle's internal helpers first (XPC services, Autoupdate), then the
# framework, then the app bundle — never using --deep, because --deep
# overwrites Sparkle's XPC signatures and silently breaks updates.
#
# Ref: https://sparkle-project.org/documentation/sandboxing/#update-process
#      https://steipete.me/posts/2025/code-signing-and-notarization-sparkle-and-tears

set -euo pipefail

APP="${1:-}"
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
    echo "usage: $0 path/to/Wishper.app" >&2
    exit 1
fi

if [ -z "${DEVELOPER_ID:-}" ]; then
    echo "error: DEVELOPER_ID env var not set" >&2
    echo "  example: DEVELOPER_ID=\"Developer ID Application: Your Name (TEAMID)\"" >&2
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENTITLEMENTS="$PROJECT_DIR/WishperApp/Wishper_App.entitlements"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSIONS="$SPARKLE/Versions/B"

sign() {
    # sign <target> [extra args...]
    local target="$1"; shift
    echo "  codesign $(basename "$target")"
    codesign --force --sign "$DEVELOPER_ID" --options runtime --timestamp "$@" "$target"
}

echo "[codesign] signing Sparkle helpers"
if [ -d "$SPARKLE_VERSIONS" ]; then
    # XPC services — sign individually, preserve Sparkle's embedded entitlements.
    for xpc in "$SPARKLE_VERSIONS/XPCServices"/*.xpc; do
        [ -d "$xpc" ] || continue
        sign "$xpc" --preserve-metadata=entitlements
    done

    # Autoupdate helper (no entitlements to preserve)
    if [ -f "$SPARKLE_VERSIONS/Autoupdate" ]; then
        sign "$SPARKLE_VERSIONS/Autoupdate"
    fi

    # Updater.app (Sparkle 2.x ships this in some builds)
    if [ -d "$SPARKLE_VERSIONS/Updater.app" ]; then
        sign "$SPARKLE_VERSIONS/Updater.app"
    fi

    echo "[codesign] signing Sparkle.framework"
    sign "$SPARKLE"
fi

echo "[codesign] signing other frameworks"
if [ -d "$APP/Contents/Frameworks" ]; then
    for fw in "$APP/Contents/Frameworks"/*.framework; do
        [ -d "$fw" ] || continue
        [ "$fw" = "$SPARKLE" ] && continue
        sign "$fw"
    done
    for dylib in "$APP/Contents/Frameworks"/*.dylib; do
        [ -f "$dylib" ] || continue
        sign "$dylib"
    done
fi

echo "[codesign] signing app bundle"
sign "$APP" --entitlements "$ENTITLEMENTS"

echo "[codesign] verifying"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "[codesign] ✓ done"
