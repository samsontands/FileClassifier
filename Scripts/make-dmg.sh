#!/bin/zsh
# Packages build/FileClassifier.app into a drag-to-Applications .dmg so
# non-technical users can install with a single drag.
#
# Run AFTER ./build.sh:
#     ./Scripts/make-dmg.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT_DIR/build/FileClassifier.app"
DMG_PATH="$ROOT_DIR/build/FileClassifier.dmg"
VOLUME_NAME="FileClassifier"

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: $APP_PATH not found — run ./build.sh first" >&2
    exit 1
fi

# Stage the DMG contents in a clean temp dir:
#   FileClassifier.app
#   Applications -> /Applications (symlink drag target)
STAGING="$(mktemp -d /tmp/fileclassifier-dmg.XXXXXX)"
trap "rm -rf '$STAGING'" EXIT

cp -R "$APP_PATH" "$STAGING/FileClassifier.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

echo
echo "DMG created:"
echo "  $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1 | xargs))"
echo
echo "Install: open the .dmg, drag FileClassifier to Applications."
