#!/bin/bash
#
# Version management for Wishper.
#
# Usage:
#   script/version.sh --show                  Print current <short>(<build>)
#   script/version.sh --bump-build            Increment CFBundleVersion
#   script/version.sh --set 0.5.2             Set short version, bump build
#   script/version.sh --patch                 0.5.1 → 0.5.2, bump build
#   script/version.sh --minor                 0.5.x → 0.6.0, bump build
#   script/version.sh --major                 0.x.y → 1.0.0, bump build
#
# Sparkle decides "update available" by comparing CFBundleVersion (build
# number), not CFBundleShortVersionString. Every release must bump the build.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="$PROJECT_DIR/WishperApp/Info.plist"
PBXPROJ="$PROJECT_DIR/WishperApp.xcodeproj/project.pbxproj"

if [ ! -f "$INFO_PLIST" ]; then
    echo "error: $INFO_PLIST not found" >&2
    exit 1
fi

current_short() { plutil -extract CFBundleShortVersionString raw -o - "$INFO_PLIST"; }
current_build() { plutil -extract CFBundleVersion raw -o - "$INFO_PLIST"; }

# Xcode's MARKETING_VERSION / CURRENT_PROJECT_VERSION build settings inject
# CFBundleShortVersionString / CFBundleVersion into the built bundle at
# archive time, overriding whatever we wrote in Info.plist. We update both
# locations so what you see in `version.sh --show` is what actually ships.
set_short() {
    plutil -replace CFBundleShortVersionString -string "$1" "$INFO_PLIST"
    if [ -f "$PBXPROJ" ]; then
        sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $1;/g" "$PBXPROJ"
    fi
}

set_build() {
    plutil -replace CFBundleVersion -string "$1" "$INFO_PLIST"
    if [ -f "$PBXPROJ" ]; then
        sed -i '' -E "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $1;/g" "$PBXPROJ"
    fi
}

bump_build() {
    local b
    b=$(current_build)
    set_build "$((b + 1))"
}

bump_semver() {
    # $1 = major|minor|patch
    local short major minor patch
    short=$(current_short)
    IFS='.' read -r major minor patch <<< "$short"
    case "$1" in
        major) major=$((major + 1)); minor=0; patch=0 ;;
        minor) minor=$((minor + 1)); patch=0 ;;
        patch) patch=$((patch + 1)) ;;
        *) echo "bump_semver: unknown component $1" >&2; exit 1 ;;
    esac
    set_short "${major}.${minor}.${patch}"
}

usage() {
    sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
}

case "${1:-}" in
    --show)       echo "$(current_short) ($(current_build))" ;;
    --bump-build) bump_build; echo "build → $(current_build)" ;;
    --set)
        [ -n "${2:-}" ] || usage
        set_short "$2"
        bump_build
        echo "$(current_short) ($(current_build))"
        ;;
    --patch|--minor|--major)
        bump_semver "${1#--}"
        bump_build
        echo "$(current_short) ($(current_build))"
        ;;
    *) usage ;;
esac
