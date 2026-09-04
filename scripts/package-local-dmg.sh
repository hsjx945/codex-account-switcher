#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
VERSION=${RELEASE_VERSION:-0.2.0}
APP_PATH="$PROJECT_DIR/.build/arm64-apple-macosx/release/Codex Account Switcher.app"
ARTIFACT_DIR="$PROJECT_DIR/.build/artifacts"
DMG_ROOT="$PROJECT_DIR/.build/local-dmg-root"
DMG_PATH="$ARTIFACT_DIR/Tiny-Codex-Switcher-${VERSION}-arm64.dmg"

"$PROJECT_DIR/scripts/package-local-app.sh"

rm -rf "$DMG_ROOT"
rm -f "$DMG_PATH" "$DMG_PATH.sha256"
mkdir -p "$DMG_ROOT" "$ARTIFACT_DIR"
ditto "$APP_PATH" "$DMG_ROOT/Codex Account Switcher.app"
cp "$PROJECT_DIR/LICENSE" "$DMG_ROOT/LICENSE.txt"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
  -volname "Tiny Codex Switcher" \
  -srcfolder "$DMG_ROOT" \
  -format UDZO \
  -ov \
  "$DMG_PATH" >/dev/null

shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
echo "$DMG_PATH"
