#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

MODE=install
if [[ "${1:-}" == "--release" ]]; then
  MODE=release
fi

BUNDLE_ID="local.aliyevom.TextSnipper"
DEPLOYMENT="14.0"

pick_sdk() {
  local candidate probe
  probe="$(mktemp)"
  try_sdk() {
    local path="$1"
    [[ -d "$path" ]] || return 1
    if printf 'print("")\n' | swiftc -swift-version 5 -sdk "$path" -o "$probe" - >/dev/null 2>&1; then
      rm -f "$probe"
      echo "$path"
      return 0
    fi
    return 1
  }
  if candidate="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)" && try_sdk "$candidate"; then
    return 0
  fi
  local found=""
  while IFS= read -r candidate; do
    found="$candidate"
  done < <(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX[0-9]*.sdk /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX[0-9]*.sdk 2>/dev/null | sort -V)
  if [[ -n "$found" ]] && try_sdk "$found"; then
    return 0
  fi
  rm -f "$probe"
  return 1
}

SDK="$(pick_sdk)"
echo "Using SDK: $SDK"
echo "Deployment target: macOS $DEPLOYMENT"

HOST="$(uname -m)"
MOD=".build/modules"
mkdir -p "$MOD"

compile_core() {
  local arch="$1"
  local dir="$2"
  mkdir -p "$dir"
  swiftc -swift-version 5 -wmo -c \
    -module-name TextSnipperCore \
    -emit-module -emit-module-path "$dir/TextSnipperCore.swiftmodule" \
    -sdk "$SDK" -target "${arch}-apple-macosx${DEPLOYMENT}" \
    -o "$dir/TextSnipperCore.o" \
    Sources/TextSnipperCore/*.swift
}

compile_app() {
  local arch="$1"
  local dir="$2"
  swiftc -swift-version 5 -O \
    -sdk "$SDK" -target "${arch}-apple-macosx${DEPLOYMENT}" \
    -I "$dir" \
    -framework AppKit -framework Vision -framework ScreenCaptureKit -framework Carbon \
    -o "$dir/TextSnipper" \
    Sources/TextSnipper/*.swift \
    "$dir/TextSnipperCore.o"
}

compile_core "$HOST" "$MOD"
swiftc -swift-version 5 \
  -sdk "$SDK" -target "${HOST}-apple-macosx${DEPLOYMENT}" \
  -I "$MOD" \
  -framework Vision -framework CoreText -framework CoreGraphics \
  -o "$MOD/TextSnipperSelfTest" \
  Tests/SelfTest/main.swift \
  "$MOD/TextSnipperCore.o"
"$MOD/TextSnipperSelfTest"

if [[ "$MODE" == "release" ]]; then
  for arch in arm64 x86_64; do
    compile_core "$arch" "$MOD/$arch"
    compile_app "$arch" "$MOD/$arch"
  done
  lipo -create \
    -output "$MOD/TextSnipper" \
    "$MOD/arm64/TextSnipper" \
    "$MOD/x86_64/TextSnipper"
  lipo -info "$MOD/TextSnipper"
else
  compile_app "$HOST" "$MOD"
fi

sign_app() {
  local target="$1"
  local style="$2"
  local staging identity=""
  # Sign outside the project folder. iCloud file-provider flags on this directory
  # make codesign reject the bundle as detritus.
  staging="$(mktemp -d /tmp/textsnipper-sign.XXXXXX)"
  ditto "$target" "$staging/TextSnipper.app"
  xattr -cr "$staging/TextSnipper.app"
  if [[ "$style" == "development" ]]; then
    identity="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)"/\1/p' | head -1 || true)"
  fi
  if [[ -n "$identity" ]]; then
    echo "Signing with $identity"
    codesign --force --sign "$identity" --identifier "$BUNDLE_ID" "$staging/TextSnipper.app"
  else
    echo "Signing ad-hoc for download"
    codesign --force --sign - --identifier "$BUNDLE_ID" "$staging/TextSnipper.app"
  fi
  codesign --verify --strict --verbose=2 "$staging/TextSnipper.app"
  rm -rf "$target"
  ditto "$staging/TextSnipper.app" "$target"
  rm -rf "$staging"
  xattr -cr "$target" || true
}

APP="dist/TextSnipper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$MOD/TextSnipper" "$APP/Contents/MacOS/TextSnipper"
cp Info.plist "$APP/Contents/Info.plist"

if [[ "$MODE" == "release" ]]; then
  sign_app "$APP" adhoc
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
  STAGE="$(mktemp -d /tmp/textsnipper-dmg.XXXXXX)"
  ditto "$APP" "$STAGE/TextSnipper.app"
  ln -s /Applications "$STAGE/Applications"
  DMG="dist/TextSnipper-${VERSION}-universal.dmg"
  rm -f "$DMG"
  diskutil image create from --format UDZO --volumeName "TextSnipper" "$STAGE" "$DMG" >/dev/null
  rm -rf "$STAGE"
  echo "Disk image: $DMG"
  exit 0
fi

sign_app "$APP" development
DEST="$HOME/Applications/TextSnipper.app"
osascript -e 'quit app "TextSnipper"' >/dev/null 2>&1 || true
sleep 0.3
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto "$APP" "$DEST"
sign_app "$DEST" development
open "$DEST"

echo "TextSnipper is in the menu bar. Press Command-Shift-2, drag around text, then paste."
