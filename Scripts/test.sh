#!/bin/bash

set -o pipefail

xcodebuild test -project Imaxe.xcodeproj -scheme Imaxe -destination 'platform=macOS,arch=arm64' \
    -configuration Debug -quiet | xcbeautify
