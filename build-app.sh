#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/ns-train-monitor-clang-cache"
export SWIFT_MODULECACHE_PATH="${TMPDIR:-/tmp}/ns-train-monitor-swift-cache"
mkdir -p "NS Train Monitor.app/Contents/MacOS" "NS Train Monitor.app/Contents/Resources"
cp Info.plist "NS Train Monitor.app/Contents/Info.plist"
cp Vendor/ZeroMQ-LICENSE.txt "NS Train Monitor.app/Contents/Resources/ZeroMQ-LICENSE.txt"
xcrun clang -O2 -c Vendor/CNDOV/CNDOV.c \
  -I Vendor/CNDOV -I Vendor/zeromq-install/include \
  -o "${TMPDIR:-/tmp}/CNDOV.o"
xcrun swiftc -parse-as-library -O \
  -I Vendor/CNDOV \
  -framework SwiftUI -framework AppKit -framework Security \
  "${TMPDIR:-/tmp}/CNDOV.o" Vendor/zeromq-install/lib/libzmq.a -lc++ -lz \
  -o "NS Train Monitor.app/Contents/MacOS/NS-Train-Monitor" \
  NS-Train-Monitor.swift
xcrun actool Assets.xcassets --compile "NS Train Monitor.app/Contents/Resources" \
  --platform macosx --minimum-deployment-target 13.0 --app-icon AppIcon \
  --output-partial-info-plist "${TMPDIR:-/tmp}/ns-train-monitor-assets.plist" >/dev/null
chmod +x "NS Train Monitor.app/Contents/MacOS/NS-Train-Monitor"
echo "Built NS Train Monitor.app"
