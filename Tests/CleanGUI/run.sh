#!/bin/zsh
set -e
cd "${0:A:h}/../.."
TASK_BUILD=$(mktemp -d "${TMPDIR:-/tmp}/hanx-clean-gui.XXXXXX")
trap 'rm -rf "$TASK_BUILD"' EXIT
SRC=(Sources/Core/*.swift Sources/Formats/*.swift Sources/Sheet/*.swift Sources/Sheet/Functions/*.swift Sources/Slides/*.swift Sources/Bridge/*.swift Sources/App/*.swift)
SRC=("${(@)SRC:#Sources/App/main.swift}")
swiftc -Onone -module-name HanXCleanTests -o "$TASK_BUILD/clean-gui-tests" "${SRC[@]}" Tests/CleanGUI/main.swift
"$TASK_BUILD/clean-gui-tests"
