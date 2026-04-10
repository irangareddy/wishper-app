#!/bin/bash
set -euo pipefail

APP_NAME="Wishper"
BUNDLE_NAME="${APP_NAME}.app"
EXECUTABLE="WishperApp"
BUILD_CONFIG="${1:-debug}"
OUTPUT_DIR="dist"
DERIVED_DATA=".xcodebuild"

echo "[wishper] Building with xcodebuild (${BUILD_CONFIG})..."
CONFIG_NAME="$([ "$BUILD_CONFIG" = "release" ] && echo Release || echo Debug)"
PATH="/usr/bin:$PATH" xcodebuild \
    -scheme WishperApp \
    -configuration "$CONFIG_NAME" \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    build 2>&1 | grep -E "BUILD|error:" | tail -5

BUILD_DIR="${DERIVED_DATA}/Build/Products/${CONFIG_NAME}"
BINARY="${BUILD_DIR}/${EXECUTABLE}"

if [ ! -f "$BINARY" ]; then
    echo "[wishper] Error: Binary not found at ${BINARY}"
    exit 1
fi

echo "[wishper] Creating ${BUNDLE_NAME}..."
rm -rf "${OUTPUT_DIR}/${BUNDLE_NAME}"
mkdir -p "${OUTPUT_DIR}/${BUNDLE_NAME}/Contents/MacOS"
mkdir -p "${OUTPUT_DIR}/${BUNDLE_NAME}/Contents/Resources"

# Copy the REAL binary (not a wrapper script)
cp "$BINARY" "${OUTPUT_DIR}/${BUNDLE_NAME}/Contents/MacOS/${EXECUTABLE}"

# Copy Info.plist
cp "Sources/WishperApp/Info.plist" "${OUTPUT_DIR}/${BUNDLE_NAME}/Contents/Info.plist"

# Copy MLX metallib — MLX searches for "mlx.metallib" next to the binary first
METALLIB="${BUILD_DIR}/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
if [ -f "$METALLIB" ]; then
    cp "$METALLIB" "${OUTPUT_DIR}/${BUNDLE_NAME}/Contents/MacOS/mlx.metallib"
    echo "[wishper] Copied mlx.metallib next to binary"
fi
# Also copy the bundle for NSBundle-based lookup
if [ -d "${BUILD_DIR}/mlx-swift_Cmlx.bundle" ]; then
    cp -r "${BUILD_DIR}/mlx-swift_Cmlx.bundle" "${OUTPUT_DIR}/${BUNDLE_NAME}/Contents/MacOS/"
fi

# Copy other resource bundles next to binary
for bundle in "${BUILD_DIR}"/*.bundle; do
    [ -d "$bundle" ] || continue
    BNAME=$(basename "$bundle")
    [ -f "${OUTPUT_DIR}/${BUNDLE_NAME}/Contents/MacOS/${BNAME}" ] && continue
    [ -d "${OUTPUT_DIR}/${BUNDLE_NAME}/Contents/MacOS/${BNAME}" ] && continue
    cp -r "$bundle" "${OUTPUT_DIR}/${BUNDLE_NAME}/Contents/MacOS/"
done

# Sign metallib, nested bundles, binary, then app
echo "[wishper] Signing..."
find "${OUTPUT_DIR}/${BUNDLE_NAME}/Contents/MacOS" -name "*.metallib" -type f | while read -r ml; do
    codesign --force --sign - "$ml" 2>/dev/null || true
done
find "${OUTPUT_DIR}/${BUNDLE_NAME}/Contents/MacOS" -name "*.bundle" -type d | while read -r nested; do
    codesign --force --sign - "$nested" 2>/dev/null || true
done
codesign --force --sign - \
    --entitlements "Sources/WishperApp/Entitlements.plist" \
    "${OUTPUT_DIR}/${BUNDLE_NAME}/Contents/MacOS/${EXECUTABLE}"
codesign --force --sign - \
    --entitlements "Sources/WishperApp/Entitlements.plist" \
    "${OUTPUT_DIR}/${BUNDLE_NAME}"

echo "[wishper] Verifying..."
codesign --verify --verbose "${OUTPUT_DIR}/${BUNDLE_NAME}" 2>&1 || true

APP_SIZE=$(du -sh "${OUTPUT_DIR}/${BUNDLE_NAME}" | cut -f1)
echo ""
echo "[wishper] Done!"
echo "  App:  ${OUTPUT_DIR}/${BUNDLE_NAME}"
echo "  Size: ${APP_SIZE}"
echo ""
echo "  To run:     open ${OUTPUT_DIR}/${BUNDLE_NAME}"
echo "  To install: cp -r ${OUTPUT_DIR}/${BUNDLE_NAME} /Applications/"
