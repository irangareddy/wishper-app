#!/bin/bash
set -euo pipefail

APP_NAME="Wishper"
BUNDLE_NAME="${APP_NAME}.app"
EXECUTABLE="WishperApp"
BUILD_CONFIG="${1:-release}"
OUTPUT_DIR="dist"

echo "[wishper] Building ${BUILD_CONFIG}..."
PATH="/usr/bin:$PATH" swift build -c "${BUILD_CONFIG}"

BIN_PATH=$(PATH="/usr/bin:$PATH" swift build -c "${BUILD_CONFIG}" --show-bin-path)
BINARY="${BIN_PATH}/${EXECUTABLE}"

if [ ! -f "$BINARY" ]; then
    echo "[wishper] Error: Binary not found at ${BINARY}"
    exit 1
fi

echo "[wishper] Creating ${BUNDLE_NAME}..."
rm -rf "${OUTPUT_DIR}/${BUNDLE_NAME}"
mkdir -p "${OUTPUT_DIR}/${BUNDLE_NAME}/Contents/MacOS"
mkdir -p "${OUTPUT_DIR}/${BUNDLE_NAME}/Contents/Resources"

# Copy binary
cp "$BINARY" "${OUTPUT_DIR}/${BUNDLE_NAME}/Contents/MacOS/${EXECUTABLE}"

# Copy Info.plist
cp "Sources/WishperApp/Info.plist" "${OUTPUT_DIR}/${BUNDLE_NAME}/Contents/Info.plist"

# Copy metallib files (MLX Metal shaders)
find "$BIN_PATH" -name "*.metallib" -exec cp {} "${OUTPUT_DIR}/${BUNDLE_NAME}/Contents/Resources/" \; 2>/dev/null || true

# Ad-hoc code sign with entitlements
echo "[wishper] Signing..."
codesign --force --sign - \
    --entitlements "Sources/WishperApp/Entitlements.plist" \
    "${OUTPUT_DIR}/${BUNDLE_NAME}"

echo "[wishper] Verifying..."
codesign --verify --verbose "${OUTPUT_DIR}/${BUNDLE_NAME}" 2>&1 || true

# Show result
APP_SIZE=$(du -sh "${OUTPUT_DIR}/${BUNDLE_NAME}" | cut -f1)
echo ""
echo "[wishper] Done!"
echo "  App:  ${OUTPUT_DIR}/${BUNDLE_NAME}"
echo "  Size: ${APP_SIZE}"
echo ""
echo "  To run:  open ${OUTPUT_DIR}/${BUNDLE_NAME}"
echo "  To install: cp -r ${OUTPUT_DIR}/${BUNDLE_NAME} /Applications/"
