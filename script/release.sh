#!/bin/bash
#
# End-to-end release orchestrator for Wishper.
#
# Flow:
#   1. Preflight — clean git tree, on main, required env set
#   2. Bump build number (and optionally short version)
#   3. xcodebuild archive (Release config)
#   4. codesign.sh   — Sparkle-safe signing order
#   5. notarize.sh   — app bundle
#   6. dmg.sh        — wrap + sign + notarize + staple DMG
#   7. appcast.sh    — generate signed appcast.xml
#   8. git commit + tag v<version>
#   9. gh release create — upload DMG + appcast.xml
#  10. git push --follow-tags
#
# Usage:
#   script/release.sh                 # use current Info.plist version, bump build
#   script/release.sh --patch         # 0.5.1 → 0.5.2, bump build
#   script/release.sh --minor         # 0.5.x → 0.6.0, bump build
#   script/release.sh --set 0.5.2     # set short, bump build
#
# Required env:
#   DEVELOPER_ID   "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE name of notarytool keychain profile (see notarize.sh)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

SCHEME="WishperApp"
CONFIG="Release"
APP_NAME="Wishper"
RELEASE_DIR="$PROJECT_DIR/releases"
ARCHIVE_PATH="$RELEASE_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$RELEASE_DIR/export"

# ---------- preflight ----------

: "${DEVELOPER_ID:?DEVELOPER_ID not set}"
: "${NOTARY_PROFILE:?NOTARY_PROFILE not set}"

if ! command -v gh >/dev/null; then
    echo "error: gh (GitHub CLI) not installed. brew install gh" >&2
    exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "error: git tree is dirty. commit or stash first." >&2
    git status --short
    exit 1
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then
    echo "warning: releasing from '$BRANCH', not main" >&2
fi

# ---------- bump version ----------

case "${1:-}" in
    --patch|--minor|--major|--set|--bump-build)
        "$PROJECT_DIR/script/version.sh" "$@"
        ;;
    "")
        "$PROJECT_DIR/script/version.sh" --bump-build
        ;;
    *)
        echo "unknown arg: $1" >&2
        exit 1
        ;;
esac

VERSION=$("$PROJECT_DIR/script/version.sh" --show | awk '{print $1}')
BUILD=$("$PROJECT_DIR/script/version.sh" --show | awk -F'[()]' '{print $2}')
TAG="v${VERSION}"

echo "[release] building $APP_NAME $VERSION ($BUILD)"

# ---------- clean ----------

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# ---------- archive ----------

echo "[release] xcodebuild archive"
xcodebuild \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    archive \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    EXCLUDED_ARCHS=x86_64 \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID" \
    OTHER_CODE_SIGN_FLAGS="--timestamp"

APP_IN_ARCHIVE="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
if [ ! -d "$APP_IN_ARCHIVE" ]; then
    echo "error: $APP_IN_ARCHIVE not found after archive" >&2
    exit 1
fi

mkdir -p "$EXPORT_DIR"
cp -R "$APP_IN_ARCHIVE" "$EXPORT_DIR/"
APP_BUNDLE="$EXPORT_DIR/$APP_NAME.app"

# ---------- codesign (Sparkle-safe) ----------

echo "[release] codesigning"
"$PROJECT_DIR/script/codesign.sh" "$APP_BUNDLE"

# ---------- notarize app ----------

echo "[release] notarizing .app"
"$PROJECT_DIR/script/notarize.sh" "$APP_BUNDLE"

# ---------- DMG ----------

echo "[release] building DMG"
"$PROJECT_DIR/script/dmg.sh" "$APP_BUNDLE" "$RELEASE_DIR"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.dmg"

# ---------- appcast ----------

echo "[release] generating appcast"
"$PROJECT_DIR/script/appcast.sh" "$RELEASE_DIR"
APPCAST_PATH="$RELEASE_DIR/appcast.xml"

# ---------- git commit + tag ----------

echo "[release] committing version bump and tagging $TAG"
git add WishperApp/Info.plist
git commit -m "Release $VERSION ($BUILD)"
git tag -a "$TAG" -m "Wishper $VERSION"

# ---------- gh release ----------

echo "[release] creating GitHub release"
gh release create "$TAG" \
    --title "Wishper $VERSION" \
    --notes "Auto-generated release. See commit history for changes." \
    "$DMG_PATH" \
    "$APPCAST_PATH"

# ---------- push ----------

echo "[release] pushing to origin"
git push --follow-tags

echo ""
echo "[release] ✓ Wishper $VERSION ($BUILD) shipped"
echo "  DMG:     $DMG_PATH"
echo "  Appcast: $APPCAST_PATH"
echo "  Tag:     $TAG"
