#!/bin/bash
set -euo pipefail

# Kill any running instance
pkill -f WishperApp 2>/dev/null || true
sleep 0.5

echo "[wishper] Building and packaging..."
./script/package_app.sh debug 2>&1 | tail -5

echo "[wishper] Launching via open -a (required for Accessibility permission)..."
open -a "$(pwd)/dist/Wishper.app"

echo "[wishper] Wishper is running in your menu bar."
echo "[wishper] Hold Right Cmd to record, release to transcribe and paste."
