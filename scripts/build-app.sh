#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
VERSION="$(<"$ROOT/VERSION")"
if [[ ! "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    printf 'error: VERSION must contain X.Y.Z.\n' >&2
    exit 1
fi
cd "$ROOT"
BUILD_ARGS=(--configuration "$CONFIGURATION"
    -Xswiftc -debug-prefix-map -Xswiftc "$ROOT=."
    -Xcc "-ffile-prefix-map=$ROOT=.")
if [[ "${UNIVERSAL:-0}" == 1 ]]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi
swift build "${BUILD_ARGS[@]}"
BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
mkdir -p "$ROOT/dist"
STAGING="$(mktemp -d "$ROOT/dist/.app-build.XXXXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Display Save.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Licenses"
cp "$BIN/DisplaySave" "$APP/Contents/MacOS/DisplaySave"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $VERSION" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/LICENSE" "$ROOT/NOTICE" "$APP/Contents/Resources/Licenses/"
RESOURCE_BUNDLE="$BIN/DisplaySave_DisplaySave.bundle"
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
    printf 'error: Missing SwiftPM resource bundle: %s\n' "$RESOURCE_BUNDLE" >&2
    exit 1
fi
/usr/bin/ditto "$RESOURCE_BUNDLE" "$APP/Contents/Resources/DisplaySave_DisplaySave.bundle"
# Distribution artifacts do not need local debug symbols or source paths.
if [[ "$CONFIGURATION" == release ]]; then
    /usr/bin/strip -S "$APP/Contents/MacOS/DisplaySave"
fi
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"
DESTINATION="$ROOT/dist/Display Save.app"
# Replace the generated bundle, not the inode of a possibly running executable.
rm -rf "$DESTINATION"
mv "$APP" "$DESTINATION"
printf '\nBuilt Display Save %s: %s\n' "$VERSION" "$DESTINATION"
