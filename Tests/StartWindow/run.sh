#!/bin/zsh
set -e
cd "${0:A:h}/../.."
mkdir -p build
SRC=(Sources/Core/*.swift Sources/Formats/*.swift Sources/Sheet/*.swift Sources/Sheet/Functions/*.swift Sources/Slides/*.swift Sources/Bridge/*.swift Sources/App/*.swift)
SRC=("${(@)SRC:#Sources/App/main.swift}")
swiftc -Onone -module-name HanWordStartTests -o build/start-window-tests "${SRC[@]}" Tests/StartWindow/main.swift
build/start-window-tests "$@"
