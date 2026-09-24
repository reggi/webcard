#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=${1:-}

if ! printf '%s\n' "$VERSION" | grep -Eq '^v?[0-9]+\.[0-9]+\.[0-9]+$'; then
    printf 'Usage: %s <MAJOR.MINOR.PATCH>\n' "$0" >&2
    exit 1
fi

VERSION=${VERSION#v}
BUILD_ROOT="$ROOT/.build/release-package"
APP="$BUILD_ROOT/Release/Webcard.app"
ARTIFACT_BASE="$ROOT/dist/Webcard-$VERSION-macOS-universal"
ZIP="$ARTIFACT_BASE.zip"
CHECKSUM="$ZIP.sha256"

rm -rf "$BUILD_ROOT"
mkdir -p "$ROOT/dist"

GIT_CONFIG_COUNT=1 \
GIT_CONFIG_KEY_0=safe.bareRepository \
GIT_CONFIG_VALUE_0=all \
xcodebuild \
    -quiet \
    -project "$ROOT/Webcard.xcodeproj" \
    -target Webcard \
    -configuration Release \
    SYMROOT="$BUILD_ROOT" \
    OBJROOT="$BUILD_ROOT/obj" \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS="${ARCHS:-arm64 x86_64}" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="${BUILD_NUMBER:-1}" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGN_STYLE=Manual \
    build

if [ ! -d "$APP" ]; then
    printf 'Build succeeded but %s was not created.\n' "$APP" >&2
    exit 1
fi

rm -f "$ZIP" "$CHECKSUM"
ditto \
    -c \
    -k \
    --sequesterRsrc \
    --keepParent \
    "$APP" \
    "$ZIP"
(
    cd "$ROOT/dist"
    shasum -a 256 "$(basename "$ZIP")"
) > "$CHECKSUM"

printf 'Packaged %s\n' "$ZIP"
printf 'Checksum %s\n' "$CHECKSUM"
