#!/bin/zsh
# Builds HanWord.app (universal: arm64 + x86_64) into build/, then installs to /Applications.
set -e
cd "$(dirname "$0")"
APP=build/HanWord.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SRC=(Sources/Core/*.swift Sources/Formats/*.swift Sources/Sheet/*.swift Sources/Sheet/Functions/*.swift Sources/Slides/*.swift Sources/Bridge/*.swift Sources/App/*.swift)
for arch in arm64 x86_64; do
  swiftc -O -module-name HanWord -target $arch-apple-macos13.0 -o build/HanWord-$arch "${SRC[@]}"
done
lipo -create build/HanWord-arm64 build/HanWord-x86_64 -output "$APP/Contents/MacOS/HanWord"
rm build/HanWord-arm64 build/HanWord-x86_64
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Resources/Credits.rtf LICENSE NOTICE "$APP/Contents/Resources/"
CLI_PATH="${HANWORD_CLI_PATH:-$PWD/build/hanword-cli}"
[[ -x "$CLI_PATH" ]] || { print -u2 'Build the standalone CLI first with ./build-cli.sh --universal'; exit 1; }
APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
CLI_VERSION=$("$CLI_PATH" --version | /usr/bin/plutil -extract data.version raw -o - -)
[[ "$APP_VERSION" == "$CLI_VERSION" ]] || { print -u2 "App/CLI versions differ: $APP_VERSION / $CLI_VERSION"; exit 1; }
mkdir -p "$APP/Contents/Resources/CLI"
cp -p "$CLI_PATH" "$APP/Contents/Resources/CLI/hanword"
cp docs/cli/README.md "$APP/Contents/Resources/CLI/README.md"
cp -R docs/cli/examples "$APP/Contents/Resources/CLI/examples"
cp LICENSE NOTICE "$APP/Contents/Resources/CLI/"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign - "$APP" >/dev/null
if [ "$1" = "--install" ]; then
  rm -rf /Applications/HanWord.app
  cp -R "$APP" /Applications/HanWord.app
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/HanWord.app
  echo "installed /Applications/HanWord.app"
fi
