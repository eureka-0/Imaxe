#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Xinlong Liu.

set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# == 1 ]] || {
  echo 'usage: prepare-updates.sh <gh-pages checkout>' >&2
  exit 64
}
SITE="$(cd "$1" && pwd)"
TEMP_DIR="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/imaxe-updates.XXXXXX")"
trap 'rm -rf "${TEMP_DIR}"' EXIT
REPOSITORY="eureka-0/Imaxe"
gh api --paginate --slurp "repos/${REPOSITORY}/releases" >"${TEMP_DIR}/releases.json"
swiftc scripts/appcast.swift -o "${TEMP_DIR}/appcast"
swiftc scripts/validate-release.swift -o "${TEMP_DIR}/validate-release"
"${TEMP_DIR}/appcast" catalog "${SITE}/history" "${TEMP_DIR}/releases.json" >"${TEMP_DIR}/catalog.json"
jq -r '.[] | [.tag, .version, .commit] | @tsv' "${TEMP_DIR}/catalog.json" >"${TEMP_DIR}/selected"
while IFS=$'\t' read -r tag version commit; do
  [[ "$(gh api "repos/${REPOSITORY}/commits/${tag}" --jq .sha)" == "${commit}" ]] || {
    echo "History source commit differs from release tag ${tag}" >&2
    exit 1
  }
  directory="${TEMP_DIR}/${tag}"
  mkdir -p "${directory}"
  for name in "Imaxe-${version}.zip" SHA256SUMS.txt; do
    curl --fail --silent --show-error --location --retry 3 --retry-all-errors --retry-delay 2 \
      --retry-max-time 120 --connect-timeout 15 --max-time 120 \
      --proto '=https' --proto-redir '=https' \
      "https://github.com/${REPOSITORY}/releases/download/${tag}/${name}" -o "${directory}/${name}"
  done
  cp "${SITE}/history/${tag}/appcast.xml" "${directory}/appcast.xml"
  "${TEMP_DIR}/validate-release" "${directory}" "${commit}"
done <"${TEMP_DIR}/selected"
"${TEMP_DIR}/appcast" merge "${SITE}/history" "${TEMP_DIR}/releases.json" "${SITE}/appcast.xml"
[[ -f ${SITE}/.nojekyll ]] || {
  echo 'Missing gh-pages .nojekyll marker' >&2
  exit 1
}
