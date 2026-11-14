#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Build build-macapp/wsdr-studio.app (macOS, this machine's architecture) from build/wsdr-studiod, web/dist
# and the Electron in desktop/node_modules: `just package` builds those first. Ad-hoc signed, so it runs
# on the machine that built it; another Mac needs it signed with a Developer ID (Gatekeeper).
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$R/build-macapp"
APP="$OUT/wsdr-studio.app"
ELECTRON="$R/desktop/node_modules/electron/dist/Electron.app"
EXE="$R/build/wsdr-studiod"

[ -x "$EXE" ] && [ -f "$R/web/dist/index.html" ] || { echo "backend or web UI missing: just build" >&2; exit 1; }
[ -d "$ELECTRON" ] || { echo "Electron missing: (cd desktop && npm ci)" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$OUT"
cp -R "$ELECTRON" "$APP"
RES="$APP/Contents/Resources"
rm -f "$RES/default_app.asar"
mkdir -p "$RES/app" "$RES/bin" "$RES/lib" "$RES/share/wsdr-studio"
cp "$R"/desktop/{main.js,preload.js,package.json,icon.png} "$RES/app/"
cp -R "$R/web/dist" "$RES/share/wsdr-studio/web" # the backend finds it at bin/../share/wsdr-studio/web
cp "$EXE" "$RES/bin/"
chmod u+w "$RES/bin/wsdr-studiod"

# Bundle the backend's non-system libraries (libusb, fftw: nix store paths) beside it.
otool -L "$EXE" | awk 'NR > 1 && $1 !~ /^(\/usr\/lib|\/System)\// { print $1 }' | while read -r lib; do
  name="$(basename "$lib")"
  cp "$lib" "$RES/lib/$name"
  chmod u+w "$RES/lib/$name"
  install_name_tool -id "@executable_path/../lib/$name" "$RES/lib/$name" 2>/dev/null
  install_name_tool -change "$lib" "@executable_path/../lib/$name" "$RES/bin/wsdr-studiod" 2>/dev/null
done
if otool -L "$RES/bin/wsdr-studiod" "$RES"/lib/* | grep -q /nix/store; then
  echo "a bundled binary still links the nix store:" >&2
  otool -L "$RES/bin/wsdr-studiod" "$RES"/lib/* | grep /nix/store >&2
  exit 1
fi

VERSION="$(sed -n 's/.*"version": "\(.*\)".*/\1/p' "$R/desktop/package.json")"
PLIST="$APP/Contents/Info.plist"
plutil -replace CFBundleName -string wsdr-studio "$PLIST"
plutil -replace CFBundleDisplayName -string wsdr-studio "$PLIST"
plutil -replace CFBundleIdentifier -string local.wsdr-studio "$PLIST"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$PLIST"
plutil -replace CFBundleVersion -string "$VERSION" "$PLIST"
sips -s format icns "$R/desktop/icon.png" --out "$RES/electron.icns" >/dev/null

# Our edits broke Electron's signature; Apple silicon refuses unsigned code, so sign it ad hoc.
codesign --force --deep --sign - "$APP" 2>/dev/null
codesign --verify --deep "$APP"
echo "built $APP"
