#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Xinlong Liu.

set -euo pipefail
[[ $# == 3 ]] || {
  echo 'usage: verify-feed.sh <expected.xml> <production-url> <diagnostics-directory>' >&2
  exit 64
}
EXPECTED="$1"
URL="$2"
DIRECTORY="$3"
ATTEMPTS="${FEED_VERIFY_ATTEMPTS:-41}"
DELAY="${FEED_VERIFY_DELAY:-15}"
TIMEOUT="${FEED_VERIFY_TIMEOUT:-600}"
[[ ${ATTEMPTS} =~ ^[1-9][0-9]*$ && ${DELAY} =~ ^[0-9]+$ && ${TIMEOUT} =~ ^[1-9][0-9]*$ ]] || exit 64
deadline=$((SECONDS + TIMEOUT))
mkdir -p "${DIRECTORY}"
EXPECTED_SHA="$(shasum -a 256 "${EXPECTED}" | awk '{print $1}')"
separator='?'
[[ ${URL} != *'?'* ]] || separator='&'
for ((attempt = 1; attempt <= ATTEMPTS; attempt++)); do
  matched=true
  for kind in canonical probe; do
    remaining=$((deadline - SECONDS))
    if [[ ${remaining} -le 0 ]]; then
      matched=false
      break
    fi
    request_timeout=30
    if [[ ${remaining} -lt ${request_timeout} ]]; then request_timeout="${remaining}"; fi
    address="${URL}"
    if [[ ${kind} == probe ]]; then
      address="${URL}${separator}deployment=${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}&attempt=${attempt}"
    fi
    prefix="${DIRECTORY}/attempt-${attempt}-${kind}"
    status=0
    curl --fail --silent --show-error --location --connect-timeout 10 --max-time "${request_timeout}" \
      --proto '=https' --proto-redir '=https' -H 'Cache-Control: no-cache' \
      --dump-header "${prefix}.headers" --output "${prefix}.xml" "${address}" || status=$?
    echo "$(date -u +%FT%TZ) attempt=${attempt}/${ATTEMPTS} request=${kind} curl_status=${status} expected_sha256=${EXPECTED_SHA}"
    if [[ -f ${prefix}.headers ]]; then
      awk '/^HTTP\// || tolower($0) ~ /^(age|etag|last-modified|cache-control|x-cache|x-served-by):/ { gsub("\r", ""); print }' "${prefix}.headers"
    fi
    if [[ -f ${prefix}.xml ]]; then
      shasum -a 256 "${prefix}.xml"
    fi
    if [[ ${status} != 0 ]] || ! cmp -s "${EXPECTED}" "${prefix}.xml"; then
      matched=false
    fi
  done
  if [[ ${matched} == true ]]; then
    echo 'Canonical and cache-probe feeds both match the verified site artifact.'
    exit 0
  fi
  remaining=$((deadline - SECONDS))
  if [[ ${remaining} -le 0 ]]; then break; fi
  pause="${DELAY}"
  if [[ ${remaining} -lt ${pause} ]]; then pause="${remaining}"; fi
  if [[ ${attempt} -lt ${ATTEMPTS} ]]; then sleep "${pause}"; fi
done
echo 'Public appcast did not converge to the verified site artifact; retained response headers and bodies.' >&2
exit 1
