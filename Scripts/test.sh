#!/bin/bash

set -euo pipefail

RESULTS_DIRECTORY="./Build/TestResults"
mkdir -p "${RESULTS_DIRECTORY}"
RESULT_BUNDLE="${RESULTS_DIRECTORY}/Imaxe-$(date '+%Y%m%d-%H%M%S').xcresult"

xcodebuild test -project Imaxe.xcodeproj -scheme Imaxe -destination 'platform=macOS,arch=arm64' \
    -configuration Debug -enableCodeCoverage YES -resultBundlePath "${RESULT_BUNDLE}" -quiet | xcbeautify

xcrun xccov view --report "${RESULT_BUNDLE}"
