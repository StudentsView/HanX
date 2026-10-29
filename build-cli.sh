#!/bin/zsh
# Builds the headless CLI harness (Core + Formats).
set -e
cd "$(dirname "$0")"
mkdir -p build
SRC=(Sources/Core/*.swift Sources/Formats/*.swift Sources/Sheet/*.swift Sources/Sheet/Functions/*.swift Sources/Slides/*.swift Sources/AgentCLI/*.swift Sources/CLI/main.swift)
if [[ "$1" == "--universal" ]]; then
  for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos13.0" -o "build/hanword-cli-$arch" "$SRC[@]"
  done
  lipo -create build/hanword-cli-arm64 build/hanword-cli-x86_64 -output build/hanword-cli
else
  swiftc -O -o build/hanword-cli "$SRC[@]"
fi
