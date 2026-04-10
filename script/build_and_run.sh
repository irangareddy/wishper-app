#!/bin/bash
set -euo pipefail

APP_NAME="WishperApp"
BUILD_DIR=".build"

# Kill any running instance
pkill -f "$APP_NAME" 2>/dev/null || true
sleep 0.5

echo "[wishper] Building..."
swift build --configuration release 2>&1

# Find the built executable
EXECUTABLE=$(swift build --configuration release --show-bin-path)/"$APP_NAME"

if [ ! -f "$EXECUTABLE" ]; then
    echo "[wishper] Build failed — executable not found"
    exit 1
fi

echo "[wishper] Launching $APP_NAME..."
"$EXECUTABLE" &
APP_PID=$!
echo "[wishper] Running with PID $APP_PID"

# Stream logs
log stream --predicate "subsystem == 'com.wishper.app'" --level debug 2>/dev/null || wait $APP_PID
