#!/bin/zsh
set -e
cd "${0:A:h}/.."
APP=build/Interaction.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SRC=(Sources/Core/*.swift Sources/Formats/*.swift Sources/Sheet/*.swift Sources/Sheet/Functions/*.swift Sources/Slides/*.swift Sources/Bridge/*.swift Sources/App/*.swift)
SRC=("${(@)SRC:#Sources/App/main.swift}")
swiftc -Onone -module-name HanXInteraction -o "$APP/Contents/MacOS/HanX" "${SRC[@]}" Tests/Interaction/main.swift
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ ! -f Resources/AppIcon.icns ] || cp Resources/AppIcon.icns "$APP/Contents/Resources/"
swiftc -o build/pasteboard-guard Tests/PasteboardGuard/main.swift
build/pasteboard-guard "$APP/Contents/MacOS/HanX" "$@"
