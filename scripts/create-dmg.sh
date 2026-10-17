#!/bin/bash
# Package an existing app only. Requires macOS, Xcode command-line tools, and
# Python >=3.9 with venv/pip. PYTHON selects the venv's bootstrap interpreter.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == Darwin ]] || fail "DMG packaging requires macOS."
[[ -f "$ROOT/VERSION" ]] || fail "Missing VERSION file."
VERSION="$(<"$ROOT/VERSION")"
[[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] \
    || fail "VERSION must contain a stable semantic version (X.Y.Z)."

APP_PATH="${APP_PATH:-$ROOT/dist/Display Save.app}"
[[ "$APP_PATH" == /* ]] || APP_PATH="$ROOT/$APP_PATH"
[[ -d "$APP_PATH" ]] || fail "App bundle not found: $APP_PATH; build it first."
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PATH/Contents/Info.plist")"
[[ "$EXECUTABLE" != */* && -n "$EXECUTABLE" ]] || fail "Invalid CFBundleExecutable."
[[ -x "$APP_PATH/Contents/MacOS/$EXECUTABLE" ]] || fail "Missing app executable."

ARCHS="$(/usr/bin/lipo -archs "$APP_PATH/Contents/MacOS/$EXECUTABLE")"
HAS_ARM64=0
HAS_X86_64=0
for ARCH in $ARCHS; do
    case "$ARCH" in
        arm64) HAS_ARM64=1 ;;
        x86_64) HAS_X86_64=1 ;;
        *) fail "Unsupported executable architecture: $ARCH" ;;
    esac
done
if [[ "$HAS_ARM64" == 1 && "$HAS_X86_64" == 1 ]]; then
    DETECTED_ARCH=universal
elif [[ "$HAS_ARM64" == 1 ]]; then
    DETECTED_ARCH=arm64
elif [[ "$HAS_X86_64" == 1 ]]; then
    DETECTED_ARCH=x86_64
else
    fail "No supported executable architecture found."
fi
# An explicit label may assert the architecture, but must not mislabel a release.
ARCH_LABEL="${ARCH_LABEL:-$DETECTED_ARCH}"
[[ "$ARCH_LABEL" == "$DETECTED_ARCH" ]] || fail "ARCH_LABEL does not match lipo: $DETECTED_ARCH"

for RESOURCE in DMGBackground.png AppIcon.icns; do
    [[ -f "$ROOT/Resources/$RESOURCE" ]] || fail "Missing Resources/$RESOURCE."
done
for TOOL in /usr/bin/hdiutil /usr/bin/ditto /usr/bin/SetFile; do
    [[ -x "$TOOL" ]] || fail "Missing $TOOL; install Xcode command-line tools."
done

OUTPUT="$ROOT/dist/Display-Save-$VERSION-$ARCH_LABEL.dmg"
[[ ! -e "$OUTPUT" && ! -L "$OUTPUT" ]] || fail "Refusing to overwrite $OUTPUT"
PYTHON="${PYTHON:-python3}"
"$PYTHON" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else "Python >=3.9 is required; set PYTHON to a supported interpreter.")'
VENV="$ROOT/.build/dmg-tools"
if [[ ! -x "$VENV/bin/python3" ]]; then
    "$PYTHON" -m venv "$VENV"
fi
PYTHON="$VENV/bin/python3"
# Install only into the isolated venv, never the system/user Python environment.
PIP_REQUIRE_VIRTUALENV=true "$PYTHON" -m pip --isolated --disable-pip-version-check \
    install --require-hashes --only-binary=:all: -r "$ROOT/scripts/dmg-requirements.txt"

mkdir -p "$ROOT/.build" "$ROOT/dist"
STAGING="$(mktemp -d "$ROOT/.build/dmg-stage.XXXXXX")"
cleanup() {
    STATUS=$?
    trap - EXIT INT TERM
    # dmgbuild normally detaches on errors. Cover signals and failures outside
    # its try/finally too, selecting only images backed by our unique staging dir.
    if "$PYTHON" - "$STAGING" <<'PY'
from pathlib import Path
import plistlib
import subprocess
import sys

stage = Path(sys.argv[1]).resolve()
info = subprocess.run(["/usr/bin/hdiutil", "info", "-plist"], check=True, stdout=subprocess.PIPE)
for image in plistlib.loads(info.stdout).get("images", []):
    path = image.get("image-path")
    if not path or Path(path).resolve().parent != stage:
        continue
    for entity in reversed(image.get("system-entities", [])):
        if entity.get("mount-point"):
            subprocess.run(["/usr/bin/hdiutil", "detach", "-force", entity["dev-entry"]], check=True)
            break
PY
    then
        rm -rf -- "$STAGING"
    else
        printf 'error: Could not detach temporary image; staging retained: %s\n' "$STAGING" >&2
        STATUS=1
    fi
    exit "$STATUS"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

export DISPLAY_SAVE_DMG_APP="$APP_PATH"
export DISPLAY_SAVE_DMG_ROOT="$ROOT"
# Keep all library temporary files under the trap-cleaned staging directory.
export TMPDIR="$STAGING"
"$VENV/bin/dmgbuild" -s "$ROOT/scripts/dmg-settings.py" \
    "Display Save" "$STAGING/Display Save.dmg"
[[ -s "$STAGING/Display Save.dmg" ]] || fail "dmgbuild did not produce a disk image."
# Do not clobber an existing release, including one created concurrently.
mv -n "$STAGING/Display Save.dmg" "$OUTPUT"
[[ ! -e "$STAGING/Display Save.dmg" ]] || fail "Output already exists: $OUTPUT"
printf '\nPackaged %s\n' "$OUTPUT"
