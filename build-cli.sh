#!/bin/zsh
# Builds the headless CLI harness (Core + Formats).
set -e
cd "$(dirname "$0")"
mkdir -p build
SRC=(Sources/Core/*.swift Sources/Formats/*.swift Sources/Sheet/*.swift Sources/Sheet/Functions/*.swift Sources/Slides/*.swift Sources/Bridge/*.swift Sources/App/PageLayoutView.swift Sources/App/SheetGridView.swift Sources/App/ChartRenderer.swift Sources/App/SlideRenderer.swift Sources/AgentCLI/*.swift Sources/CLI/main.swift)
if [[ "$1" == "--universal" ]]; then
  for arch in arm64 x86_64; do
    swiftc -D HANX_CLI -O -target "$arch-apple-macos13.0" -o "build/hanx-cli-$arch" "$SRC[@]"
  done
  lipo -create build/hanx-cli-arm64 build/hanx-cli-x86_64 -output build/hanx-cli
else
  swiftc -D HANX_CLI -O -o build/hanx-cli "$SRC[@]"
fi
