#!/bin/bash

set -o pipefail

xcodebuild test -project Imaxe.xcodeproj -scheme Imaxe -destination 'platform=macOS' \
    -enableCodeCoverage YES -quiet | xcbeautify
