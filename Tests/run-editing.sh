#!/bin/zsh
set -e
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -Onone -o build/editing-tests Sources/Core/*.swift Sources/Formats/*.swift Sources/Sheet/*.swift Sources/Sheet/Functions/*.swift Sources/Slides/*.swift Tests/Editing/main.swift
build/editing-tests "${1:-build/editing-fixture.pptx}"
