#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Xinlong Liu.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/test.sh [options]

Run the Imaxe test suite.

Options:
  --skip-ui                 Run only the unit-test target.
  --ui-only                 Run only the UI-test target.
  --ui-test <name>           Run a UI-test method. Repeat to select multiple methods.
  --suite <name>            Run a unit-test suite. Repeat to select multiple suites.
                            Accepted names: ImageLoadingTests, ImageViewTests,
                            RecentImagesTests, SessionAndNavigationTests, SharedUITests,
                            ImageFidelityTests, ImageCompatibilityTests, ImagePerformanceTests,
                            AdaptiveToolbarTests,
                            UpdateSettingsTests, ReleaseValidationTests, ReleaseLockTests.
  --skip-suite <name>       Exclude a unit-test suite. Repeat to exclude multiple suites.
  --build-only              Build all test products without running tests.
  --test-without-building   Run existing test products from build/DerivedData/Tests.
  --no-coverage             Disable code coverage collection.
  --coverage-report         Print the detailed code coverage report after testing.
  -h, --help                Show this help message.
EOF
}

require_value() {
  local option="$1"

  if [[ $# -lt 2 || -z $2 || $2 == --* ]]; then
    echo "error: ${option} requires a value" >&2
    usage >&2
    exit 2
  fi
}

test_mode="all"
coverage_enabled="YES"
coverage_report="NO"
build_action="test"
suite_filters=()
suite_count=0
skipped_suites=()
skipped_suite_count=0
ui_test_filters=()
ui_test_count=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --skip-ui)
    if [[ $test_mode == "ui" ]]; then
      echo "error: --skip-ui cannot be used with --ui-only" >&2
      exit 2
    fi
    test_mode="unit"
    ;;
  --ui-only)
    if [[ $test_mode == "unit" ]]; then
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
  --ui-test)
    require_value "$1" "${2:-}"
    if [[ $test_mode == "unit" ]]; then
      echo "error: --ui-test cannot be used with --skip-ui" >&2
      exit 2
    fi
    test_mode="ui"
    ui_test_filters+=("$2")
    ui_test_count=$((ui_test_count + 1))
    shift
    ;;
  --skip-suite)
    require_value "$1" "${2:-}"
    skipped_suites+=("$2")
    skipped_suite_count=$((skipped_suite_count + 1))
    shift
    ;;
  --build-only | --test-without-building)
    if [[ $build_action != "test" ]]; then
      echo "error: --build-only and --test-without-building are mutually exclusive" >&2
      exit 2
    fi
    if [[ $1 == "--build-only" ]]; then
      build_action="build-for-testing"
    else
      build_action="test-without-building"
    fi
    ;;
  --no-coverage)
    coverage_enabled="NO"
    ;;
  --coverage-report)
    coverage_report="YES"
    ;;
  -h | --help)
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

if [[ $test_mode == "ui" && ($suite_count -gt 0 || $skipped_suite_count -gt 0) ]]; then
  echo "error: --suite and --skip-suite select ImaxeTests suites and cannot be used with --ui-only" >&2
  exit 2
fi

if [[ $coverage_enabled == "NO" && $coverage_report == "YES" ]]; then
  echo "error: --coverage-report cannot be used with --no-coverage" >&2
  exit 2
fi

if [[ $build_action == "build-for-testing" &&
  ($test_mode != "all" || $suite_count -gt 0 || $skipped_suite_count -gt 0 || $coverage_report == "YES") ]]; then
  echo "error: --build-only builds all test targets and cannot use test filters or --coverage-report" >&2
  exit 2
fi

RESULTS_DIRECTORY="./build/TestResults"
DERIVED_DATA_DIRECTORY="./build/DerivedData/Tests"
mkdir -p "${RESULTS_DIRECTORY}"
RESULT_BUNDLE="${RESULTS_DIRECTORY}/Imaxe-$(date '+%Y%m%d-%H%M%S').xcresult"

cleanup_result_bundles() {
  if [[ $test_mode != "unit" ]]; then
    rm -rf /private/tmp/com.imaxe.ImaxeUITests
  fi

  local result_bundles
  local bundle
  local oldest_bundle
  local retained_bundles

  shopt -s nullglob
  result_bundles=("${RESULTS_DIRECTORY}"/*.xcresult)
  shopt -u nullglob

  while ((${#result_bundles[@]} > 7)); do
    oldest_bundle="${result_bundles[0]}"
    for bundle in "${result_bundles[@]:1}"; do
      if [[ ${bundle} -ot ${oldest_bundle} ]]; then
        oldest_bundle="${bundle}"
      fi
    done

    retained_bundles=()
    for bundle in "${result_bundles[@]}"; do
      if [[ ${bundle} != "${oldest_bundle}" ]]; then
        retained_bundles+=("${bundle}")
      fi
    done

    rm -rf "${oldest_bundle}"
    result_bundles=("${retained_bundles[@]}")
  done
}
trap cleanup_result_bundles EXIT

xcodebuild_arguments=(
  "${build_action}"
  -destination 'platform=macOS,arch=arm64'
  -enableCodeCoverage "${coverage_enabled}"
  -resultBundlePath "${RESULT_BUNDLE}"
)

if [[ $build_action == "test-without-building" ]]; then
  shopt -s nullglob
  test_runs=("${DERIVED_DATA_DIRECTORY}"/Build/Products/*.xctestrun)
  shopt -u nullglob
  if ((${#test_runs[@]} != 1)); then
    echo "error: --test-without-building requires exactly one .xctestrun in ${DERIVED_DATA_DIRECTORY}/Build/Products" >&2
    exit 2
  fi
  xcodebuild_arguments+=(-xctestrun "${test_runs[0]}")
else
  xcodebuild_arguments+=(
    -project Imaxe.xcodeproj
    -scheme Imaxe
    -configuration Debug
    -derivedDataPath "${DERIVED_DATA_DIRECTORY}"
  )
fi

case "$test_mode" in
unit)
  xcodebuild_arguments+=("-skip-testing:ImaxeUITests")
  ;;
ui)
  if ((ui_test_count > 0)); then
    for ui_test in "${ui_test_filters[@]}"; do
      xcodebuild_arguments+=("-only-testing:ImaxeUITests/ImaxeUITests/${ui_test}")
    done
  else
    xcodebuild_arguments+=("-only-testing:ImaxeUITests")
  fi
  ;;
esac

if ((suite_count > 0)); then
  for suite in "${suite_filters[@]}"; do
    xcodebuild_arguments+=("-only-testing:ImaxeTests/${suite}")
  done
fi

if ((skipped_suite_count > 0)); then
  for suite in "${skipped_suites[@]}"; do
    xcodebuild_arguments+=("-skip-testing:ImaxeTests/${suite}")
  done
fi

xcodebuild "${xcodebuild_arguments[@]}" | xcbeautify

if [[ $coverage_report == "YES" ]]; then
  xcrun xccov view --only-targets --report "${RESULT_BUNDLE}"
fi
