#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Xinlong Liu.
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
tool_directory="${project_root}/build/Tools/ReleaseProfile"
source_file="${project_root}/scripts/profile-release.swift"
tool="${tool_directory}/profile-release"
mkdir -p "${tool_directory}"
if [[ ! -x ${tool} || ${source_file} -nt ${tool} ]]; then
  temporary_tool="${tool}.$$"
  trap 'rm -f "${temporary_tool}"' EXIT
  xcrun swiftc -swift-version 6 -default-isolation MainActor \
    -target arm64-apple-macos15.6 -module-cache-path "${project_root}/build/ModuleCache" \
    "${source_file}" -o "${temporary_tool}"
  mv "${temporary_tool}" "${tool}"
fi
exec "${tool}" "$@"
