#!/bin/bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: Scripts/test.sh [options]

Run the Imaxe test suite.

Options:
  --skip-ui                 Run only the unit-test target.
  --ui-only                 Run only the UI-test target.
  --suite <name>            Run a unit-test suite. Repeat to select multiple suites.
                            Accepted names: ImageLoadingTests, ImageViewTests,
                            RecentImagesTests, SessionAndNavigationTests, SharedUITests.
  --no-coverage             Disable code coverage collection.
  --coverage-report         Print the detailed code coverage report after testing.
  -h, --help                Show this help message.
EOF
}

require_value() {
  local option="$1"

  if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
    echo "error: ${option} requires a value" >&2
    usage >&2
    exit 2
  fi
}

test_mode="all"
coverage_enabled="YES"
coverage_report="NO"
suite_filters=()
suite_count=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-ui)
      if [[ "$test_mode" == "ui" ]]; then
        echo "error: --skip-ui cannot be used with --ui-only" >&2
        exit 2
      fi
      test_mode="unit"
      ;;
    --ui-only)
      if [[ "$test_mode" == "unit" ]]; then
        echo "error: --ui-only cannot be used with --skip-ui" >&2
        exit 2
      fi
      test_mode="ui"
      ;;
    --suite)
      require_value "$1" "${2:-}"
      suite_filters+=("$2")
      suite_count=$((suite_count + 1))
      shift
      ;;
    --no-coverage)
      coverage_enabled="NO"
      ;;
    --coverage-report)
      coverage_report="YES"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ "$test_mode" == "ui" && "$suite_count" -gt 0 ]]; then
  echo "error: --suite only selects suites in ImaxeTests and cannot be used with --ui-only" >&2
  exit 2
fi

if [[ "$coverage_enabled" == "NO" && "$coverage_report" == "YES" ]]; then
  echo "error: --coverage-report cannot be used with --no-coverage" >&2
  exit 2
fi

RESULTS_DIRECTORY="./Build/TestResults"
DERIVED_DATA_DIRECTORY="./Build/DerivedData/Tests"
mkdir -p "${RESULTS_DIRECTORY}"
RESULT_BUNDLE="${RESULTS_DIRECTORY}/Imaxe-$(date '+%Y%m%d-%H%M%S').xcresult"

xcodebuild_arguments=(
  test
  -project Imaxe.xcodeproj
  -scheme Imaxe
  -destination 'platform=macOS,arch=arm64'
  -configuration Debug
  -derivedDataPath "${DERIVED_DATA_DIRECTORY}"
  -enableCodeCoverage "${coverage_enabled}"
  -resultBundlePath "${RESULT_BUNDLE}"
  -quiet
)

case "$test_mode" in
  unit)
    xcodebuild_arguments+=("-skip-testing:ImaxeUITests")
    ;;
  ui)
    xcodebuild_arguments+=("-only-testing:ImaxeUITests")
    ;;
esac

if (( suite_count > 0 )); then
  for suite in "${suite_filters[@]}"; do
    xcodebuild_arguments+=("-only-testing:ImaxeTests/${suite}")
  done
fi

xcodebuild "${xcodebuild_arguments[@]}" | xcbeautify

if [[ "$coverage_report" == "YES" ]]; then
  xcrun xccov view --only-targets --report "${RESULT_BUNDLE}"
fi
