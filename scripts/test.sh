#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
xcrun swiftc -swift-version 5 Sources/HotSpotAlive/Core.swift Tests/main.swift -o build/tests/core-tests
build/tests/core-tests
