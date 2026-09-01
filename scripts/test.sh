#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
DESTINATION="${JAWATLAS_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"
xcodebuild -project JawAtlas.xcodeproj -scheme JawAtlas -destination "$DESTINATION" build
xcodebuild -project JawAtlas.xcodeproj -scheme JawAtlas -destination "$DESTINATION" test
