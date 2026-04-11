#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_FILE="$PROJECT_DIR/Wishper App.xcodeproj"
SCHEME="Wishper App"
DEFAULT_CONFIGURATION="Debug"
DESTINATION="platform=macOS"
APP_PROCESS_NAME="Wishper App"

CONFIGURATION="$DEFAULT_CONFIGURATION"
BUILD_ONLY=0
CLEAN_FIRST=0

usage() {
    cat <<'EOF'
Usage:
  script/build_and_run.sh [Debug|Release] [--build-only] [--clean]

Examples:
  script/build_and_run.sh
  script/build_and_run.sh Debug --build-only
  script/build_and_run.sh Release --clean
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        Debug|Release)
            CONFIGURATION="$1"
            ;;
        --build-only|--no-open)
            BUILD_ONLY=1
            ;;
        --clean)
            CLEAN_FIRST=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[wishper] Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

run_xcodebuild() {
    local action="$1"
    shift

    echo "[wishper] Running: xcodebuild -project \"$PROJECT_FILE\" -scheme \"$SCHEME\" -configuration \"$CONFIGURATION\" -destination \"$DESTINATION\" $action $*"
    xcodebuild \
        -project "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -destination "$DESTINATION" \
        "$action" \
        "$@"
}

cd "$PROJECT_DIR"

if [[ "$CLEAN_FIRST" -eq 1 ]]; then
    run_xcodebuild clean
fi

run_xcodebuild build

BUILD_SETTINGS="$(xcodebuild \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -showBuildSettings 2>/dev/null)"

BUILD_DIR="$(printf '%s\n' "$BUILD_SETTINGS" | awk -F' = ' '/ BUILT_PRODUCTS_DIR = / { print $2; exit }')"
FULL_PRODUCT_NAME="$(printf '%s\n' "$BUILD_SETTINGS" | awk -F' = ' '/ FULL_PRODUCT_NAME = / { print $2; exit }')"

if [[ -z "$BUILD_DIR" || -z "$FULL_PRODUCT_NAME" ]]; then
    echo "[wishper] Failed to resolve build output path." >&2
    exit 1
fi

APP_PATH="$BUILD_DIR/$FULL_PRODUCT_NAME"

if [[ ! -d "$APP_PATH" ]]; then
    echo "[wishper] Built app not found at: $APP_PATH" >&2
    exit 1
fi

echo "[wishper] Built app: $APP_PATH"

if [[ "$BUILD_ONLY" -eq 1 ]]; then
    echo "[wishper] Build-only mode enabled; skipping launch."
    exit 0
fi

pkill -f "$APP_PROCESS_NAME" 2>/dev/null || true
sleep 1

echo "[wishper] Running: open -na \"$APP_PATH\""
open -na "$APP_PATH"
