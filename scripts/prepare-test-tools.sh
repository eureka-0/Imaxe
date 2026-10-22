#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Xinlong Liu.
set -euo pipefail

cd "$(dirname "$0")/.."
project_root="${PWD}"
tool_directory="${project_root}/build/Tools/Tests"
mode="${1:-build}"
[[ $# -le 1 && (${mode} == build || ${mode} == --verify) ]] || exit 64
temporary="$(mktemp -d)"
trap 'rm -rf "${temporary}"' EXIT
tools=(appcast validate-release profile-release fixture-app)

{
  echo 'target=arm64-apple-macos15.6'
  xcodebuild -version
  xcrun --sdk macosx --show-sdk-version
  xcrun --sdk macosx --show-sdk-build-version
  # Swift's version command reports the host target, even with -target supplied.
  xcrun --sdk macosx swiftc --version | sed '/^Target:/d'
  xcrun --sdk macosx clang -target arm64-apple-macos15.6 --version
  shasum -a 256 scripts/prepare-test-tools.sh scripts/appcast.swift \
    scripts/validate-release.swift scripts/profile-release.swift
} >"${temporary}/inputs.txt"

valid=true
cmp -s "${temporary}/inputs.txt" "${tool_directory}/inputs.txt" || valid=false
for tool in "${tools[@]}"; do
  [[ -x ${tool_directory}/${tool} ]] || valid=false
done
if [[ ${valid} == true ]]; then
  (cd "${tool_directory}" && shasum -a 256 "${tools[@]}") >"${temporary}/actual-checksums.txt"
  cmp -s "${temporary}/actual-checksums.txt" "${tool_directory}/SHA256SUMS.txt" || valid=false
fi
if [[ ${valid} == true ]]; then
  echo 'Test tools verified; reusing prepared binaries.'
  exit 0
fi
if [[ ${mode} == --verify ]]; then
  echo 'error: test tools are missing, changed or from another source/toolchain; run just test --build-only' >&2
  exit 1
fi

mkdir -p "${project_root}/build/ModuleCache/TestTools"
swift_arguments=(-target arm64-apple-macos15.6
  -module-cache-path "${project_root}/build/ModuleCache/TestTools")
for tool in appcast validate-release profile-release; do
  started=${SECONDS}
  echo "Compiling test tool: ${tool}"
  if [[ ${tool} == profile-release ]]; then
    xcrun --sdk macosx swiftc "${swift_arguments[@]}" -swift-version 6 \
      -default-isolation MainActor "scripts/${tool}.swift" -o "${temporary}/${tool}"
  else
    # Relative #filePath lets the verifier read each fixture's own source Info.plist.
    xcrun --sdk macosx swiftc "${swift_arguments[@]}" "scripts/${tool}.swift" -o "${temporary}/${tool}"
  fi
  echo "Prepared ${tool} in $((SECONDS - started))s"
done
echo 'int main(void) { return 0; }' >"${temporary}/fixture.c"
xcrun --sdk macosx clang -target arm64-apple-macos15.6 \
  "${temporary}/fixture.c" -o "${temporary}/fixture-app"
(cd "${temporary}" && shasum -a 256 "${tools[@]}" >SHA256SUMS.txt)
mkdir -p "${tool_directory}"
for tool in "${tools[@]}"; do
  mv "${temporary}/${tool}" "${tool_directory}/${tool}"
done
mv "${temporary}/inputs.txt" "${temporary}/SHA256SUMS.txt" "${tool_directory}/"
