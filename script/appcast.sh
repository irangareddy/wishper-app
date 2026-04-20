#!/bin/bash
#
# Generate the Sparkle appcast.xml for a release.
#
# Usage:
#   script/appcast.sh <release-dir>
#
# <release-dir> must contain the current DMG (and optionally prior ones so
# Sparkle can build delta updates). The script produces appcast.xml beside
# the DMGs — upload both as GitHub Release assets so
# https://github.com/irangareddy/wishper-app/releases/latest/download/appcast.xml
# resolves to the newest one.
#
# Requires the Sparkle toolbelt at /tmp/bin (run once:
#   curl -L -o /tmp/sparkle.tar.xz \
#     https://github.com/sparkle-project/Sparkle/releases/download/2.9.1/Sparkle-2.9.1.tar.xz
#   tar -xf /tmp/sparkle.tar.xz -C /tmp
# ). The EdDSA private key must be in the current user's login Keychain.

set -euo pipefail

RELEASE_DIR="${1:-}"

if [ -z "$RELEASE_DIR" ] || [ ! -d "$RELEASE_DIR" ]; then
    echo "usage: $0 <release-dir>" >&2
    echo "  <release-dir> must contain one or more .dmg files" >&2
    exit 1
fi

GENERATE_APPCAST="/tmp/bin/generate_appcast"
if [ ! -x "$GENERATE_APPCAST" ]; then
    echo "error: $GENERATE_APPCAST not found." >&2
    echo "  download Sparkle 2.9.1 first:" >&2
    echo "    curl -L -o /tmp/sparkle.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/2.9.1/Sparkle-2.9.1.tar.xz" >&2
    echo "    tar -xf /tmp/sparkle.tar.xz -C /tmp" >&2
    exit 1
fi

echo "[appcast] scanning $RELEASE_DIR"
"$GENERATE_APPCAST" "$RELEASE_DIR"

echo "[appcast] wrote $RELEASE_DIR/appcast.xml"
echo "[appcast] upload alongside the DMG so the SUFeedURL resolves to it."
