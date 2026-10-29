#!/bin/zsh
# Fast debug build (host arch, -Onone) into build/Dev.app for local testing.
set -e
cd "$(dirname "$0")"
APP=build/Dev.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SRC=(Sources/Core/*.swift Sources/Formats/*.swift Sources/Sheet/*.swift Sources/Sheet/Functions/*.swift Sources/Slides/*.swift Sources/Bridge/*.swift Sources/App/*.swift)
swiftc -Onone -module-name HanWord -o "$APP/Contents/MacOS/HanWord" "${SRC[@]}"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
