#!/bin/bash
# Build the iOS app and run it on the simulator.
# Usage: npm run sim
set -e
cd "$(dirname "$0")/../ios"

echo "=== building ==="
xcodebuild -project PhotoRecipes.xcodeproj \
  -scheme PhotoRecipes \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
  -derivedDataPath /tmp/ao-dd \
  build 2>&1 | tail -5

APP=/tmp/ao-dd/Build/Products/Debug-iphonesimulator/PhotoRecipes.app
[ -d "$APP" ] || { echo "BUILD FAILED: $APP not found"; exit 1; }

echo "=== booting simulator ==="
xcrun simctl boot "iPhone 18 Pro Max" 2>/dev/null || true
open -a Simulator

echo "=== installing ==="
xcrun simctl install booted "$APP"

echo "=== launching ==="
xcrun simctl launch booted com.ragnus.mvp

echo "DONE — app should be on screen in the simulator"
