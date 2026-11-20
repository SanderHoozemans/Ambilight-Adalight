#!/bin/zsh
# Builds build/Ambilight.app (universal: Apple Silicon + Intel).
set -e
cd "$(dirname "$0")"
APP=build/Ambilight.app
rm -rf build; mkdir -p $APP/Contents/MacOS
cp Info.plist $APP/Contents/Info.plist
mkdir -p $APP/Contents/Library/LaunchAgents
cp Library/LaunchAgents/nl.local.ambilight.watcher.plist $APP/Contents/Library/LaunchAgents/
[ -f Resources/AppIcon.icns ] && { mkdir -p $APP/Contents/Resources; cp Resources/AppIcon.icns $APP/Contents/Resources/; }
for ARCH in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $ARCH-apple-macos14.0 Sources/main.swift -o build/Ambilight-$ARCH
done
lipo -create build/Ambilight-arm64 build/Ambilight-x86_64 -output $APP/Contents/MacOS/Ambilight
rm build/Ambilight-arm64 build/Ambilight-x86_64
codesign --force --deep -s - $APP
$APP/Contents/MacOS/Ambilight --refresh-agent || true   # keep the auto-start agent pointing at the new build
echo "OK: $PWD/$APP"
