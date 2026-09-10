#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
ARCH=${SWIFT_BUILD_ARCH:-$(uname -m)}
ARTIFACT_DIR="$PROJECT_DIR/.build/artifacts"
DMG_ROOT="$PROJECT_DIR/.build/local-dmg-root"
DMG_PATH="$ARTIFACT_DIR/Codex-Account-Switcher-macos-${ARCH}.dmg"

APP_PATH=$("$PROJECT_DIR/scripts/package-local-app.sh" | tail -n 1)

rm -rf "$DMG_ROOT"
rm -f "$DMG_PATH" "$DMG_PATH.sha256"
mkdir -p "$DMG_ROOT" "$ARTIFACT_DIR"
ditto "$APP_PATH" "$DMG_ROOT/Codex Account Switcher.app"
cp "$PROJECT_DIR/LICENSE" "$DMG_ROOT/LICENSE.txt"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
  -volname "Codex Account Switcher" \
  -srcfolder "$DMG_ROOT" \
  -format UDZO \
  -ov \
  "$DMG_PATH" >/dev/null

(cd "$ARTIFACT_DIR" && shasum -a 256 "${DMG_PATH:t}" > "${DMG_PATH:t}.sha256")
echo "$DMG_PATH"
