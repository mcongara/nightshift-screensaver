#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/feed-check build/module-cache
cp tests/FeedRegression.swift build/feed-check/main.swift
swiftc -module-cache-path "$PWD/build/module-cache" -swift-version 5 \
  -framework AppKit Sources/Localization.swift Sources/Canvas.swift build/feed-check/main.swift -o build/feed-check/check
build/feed-check/check
