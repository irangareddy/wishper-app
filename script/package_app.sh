#!/bin/bash
set -euo pipefail

APP_NAME="Wishper"
BUNDLE_NAME="${APP_NAME}.app"
EXECUTABLE="WishperApp"
BUILD_CONFIG="${1:-release}"
OUTPUT_DIR="dist"
DERIVED_DATA=".xcodebuild"

echo "[wishper] Building with xcodebuild (${BUILD_CONFIG})..."
PATH="/usr/bin:$PATH" xcodebuild \
    -scheme WishperApp \
    -configuration "$([ "$BUILD_CONFIG" = "release" ] && echo Release || echo Debug)" \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    build 2>&1 | grep -E "BUILD|error:" | tail -5

BUILD_DIR="${DERIVED_DATA}/Build/Products/$([ "$BUILD_CONFIG" = "release" ] && echo Release || echo Debug)"
BINARY="${BUILD_DIR}/${EXECUTABLE}"

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

# Copy MLX metallib bundle (critical — without this, MLX can't compile Metal shaders)
if [ -d "${BUILD_DIR}/mlx-swift_Cmlx.bundle" ]; then
    cp -r "${BUILD_DIR}/mlx-swift_Cmlx.bundle" "${OUTPUT_DIR}/${BUNDLE_NAME}/Contents/Resources/"
    echo "[wishper] Copied MLX metallib bundle"
fi

# Copy other resource bundles
for bundle in "${BUILD_DIR}"/*.bundle; do
    [ -d "$bundle" ] || continue
    BNAME=$(basename "$bundle")
    [ "$BNAME" = "mlx-swift_Cmlx.bundle" ] && continue  # already copied
    cp -r "$bundle" "${OUTPUT_DIR}/${BUNDLE_NAME}/Contents/Resources/"
done

# Ad-hoc code sign with entitlements
echo "[wishper] Signing..."
codesign --force --deep --sign - \
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
