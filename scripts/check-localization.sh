#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/localization-check build/module-cache
cp tests/LocalizationChecks.swift build/localization-check/main.swift
for language in TURKISH ENGLISH; do
    swiftc -D "$language" -module-cache-path "$PWD/build/module-cache" -swift-version 5 \
      Sources/Localization.swift build/localization-check/main.swift -o build/localization-check/check
    build/localization-check/check
done
