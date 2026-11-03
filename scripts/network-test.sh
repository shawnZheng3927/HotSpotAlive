#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
xcrun swiftc -swift-version 5 Sources/HotSpotAlive/Core.swift Sources/HotSpotAlive/NetworkSupport.swift \
  Tests/NetworkSmoke/main.swift -o build/tests/network-smoke
# Sends exactly one small DNS query on the active Wi-Fi interface.
build/tests/network-smoke
