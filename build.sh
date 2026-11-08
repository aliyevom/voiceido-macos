#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

pick_sdk() {
  local candidate probe
  probe="$(mktemp)"
  for candidate in \
    /Library/Developer/CommandLineTools/SDKs/MacOSX27.0.sdk \
    /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
    /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
  do
    if [[ -d "$candidate" ]] && printf 'print("")\n' | swiftc -swift-version 5 -sdk "$candidate" -o "$probe" - >/dev/null 2>&1; then
      rm -f "$probe"
      echo "$candidate"
      return 0
    fi
  done
  rm -f "$probe"
  return 1
}

SDK="$(pick_sdk)"
echo "Using SDK: $SDK"

MOD=".build/modules"
mkdir -p "$MOD"

swiftc -swift-version 5 -wmo -c \
  -module-name TextSnipperCore \
  -emit-module -emit-module-path "$MOD/TextSnipperCore.swiftmodule" \
  -sdk "$SDK" -target arm64-apple-macosx14.0 \
  -o "$MOD/TextSnipperCore.o" \
  Sources/TextSnipperCore/*.swift

swiftc -swift-version 5 \
  -sdk "$SDK" -target arm64-apple-macosx14.0 \
  -I "$MOD" \
  -framework Vision -framework CoreText -framework CoreGraphics \
  -o "$MOD/TextSnipperSelfTest" \
  Tests/SelfTest/main.swift \
  "$MOD/TextSnipperCore.o"

"$MOD/TextSnipperSelfTest"

swiftc -swift-version 5 -O \
  -sdk "$SDK" -target arm64-apple-macosx14.0 \
  -I "$MOD" \
  -framework AppKit -framework Vision -framework ScreenCaptureKit -framework Carbon \
  -o "$MOD/TextSnipper" \
  Sources/TextSnipper/*.swift \
  "$MOD/TextSnipperCore.o"

sign_app() {
  local target="$1"
  local staging identity
  # Sign outside the project folder. iCloud file-provider flags on this directory
  # make codesign reject the bundle as detritus.
  staging="$(mktemp -d /tmp/textsnipper-sign.XXXXXX)"
  ditto "$target" "$staging/TextSnipper.app"
  xattr -cr "$staging/TextSnipper.app"
  identity="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)"/\1/p' | head -1 || true)"
  if [[ -n "$identity" ]]; then
    echo "Signing with $identity"
    codesign --force --sign "$identity" --identifier "local.aliyevom.TextSnipper" "$staging/TextSnipper.app"
  else
    echo "Signing ad-hoc"
    codesign --force --sign - --identifier "local.aliyevom.TextSnipper" "$staging/TextSnipper.app"
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
sign_app "$APP"

DEST="$HOME/Applications/TextSnipper.app"
osascript -e 'quit app "TextSnipper"' >/dev/null 2>&1 || true
sleep 0.3
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto "$APP" "$DEST"
sign_app "$DEST"
open "$DEST"

echo "TextSnipper is in the menu bar. Press Command-Shift-2, drag around text, then paste."
