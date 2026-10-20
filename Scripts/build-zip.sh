#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Xinlong Liu.

set -euo pipefail
cd "$(dirname "$0")/.."

PUBLISH=false
case "${1:-}" in
--publish) PUBLISH=true ;;
--help | -h)
  echo "usage: $0 [--publish]"
  echo "Build a signed update archive, or publish the exact existing artifact from main."
  exit 0
  ;;
"") ;;
*)
  echo "usage: $0 [--publish]" >&2
  exit 64
  ;;
esac

fail() {
  echo "error: $*" >&2
  exit 1
}
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }

REPOSITORY="eureka-0/Imaxe"
REPOSITORY_URL="https://github.com/${REPOSITORY}"
SCHEME="Imaxe"
BUILD_ROOT="${PWD}/Build"
DERIVED_DATA_DIR="${BUILD_ROOT}/DerivedData/Release"
SPARKLE_BIN="${DERIVED_DATA_DIR}/SourcePackages/artifacts/sparkle/Sparkle/bin"
FEED_URL="$(plist Imaxe/Info.plist SUFeedURL)"
PUBLIC_KEY="$(plist Imaxe/Info.plist SUPublicEDKey)"

[[ $# -le 1 ]] || fail "only one option is accepted"
[[ -z "$(git status --porcelain --untracked-files=normal)" ]] || fail "release builds require a clean Git worktree"
if [[ ${PUBLISH} == true ]]; then
  [[ "$(git branch --show-current)" == main ]] || fail "publish from main; the script will not switch branches"
  case "$(git remote get-url origin)" in
  https://github.com/eureka-0/Imaxe | https://github.com/eureka-0/Imaxe.git | git@github.com:eureka-0/Imaxe.git | ssh://git@github.com/eureka-0/Imaxe.git) ;;
  *) fail "origin must point to eureka-0/Imaxe" ;;
  esac
fi
for tool in gh jq swift xmllint curl shasum; do
  command -v "${tool}" >/dev/null || fail "missing required tool: ${tool}"
done
[[ ${FEED_URL} == https://eureka-0.github.io/Imaxe/appcast.xml ]] || fail "unexpected stable feed URL"

mkdir -p "${BUILD_ROOT}"
LOCK_DIR="${BUILD_ROOT}/.release.lock"
mkdir "${LOCK_DIR}" 2>/dev/null || fail "release build or publish already holds ${LOCK_DIR}; remove it only if no release process is running"
TEMP_DIR=""
ARCHIVE_PATH=""
CREATED_ARCHIVE=false
cleanup() {
  local status=$?
  trap - EXIT
  if [[ -n ${TEMP_DIR} ]]; then rm -rf "${TEMP_DIR}" || status=1; fi
  if [[ ${CREATED_ARCHIVE} == true ]]; then rm -rf "${ARCHIVE_PATH}" || status=1; fi
  rmdir "${LOCK_DIR}" || status=1
  exit "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

BUILD_SETTINGS="$(xcodebuild -project Imaxe.xcodeproj -scheme "${SCHEME}" \
  -configuration Release -destination 'platform=macOS,arch=arm64' -showBuildSettings)"
VERSION="$(awk '/ MARKETING_VERSION = / { print $3; exit }' <<<"${BUILD_SETTINGS}")"
BUILD_NUMBER="$(awk '/ CURRENT_PROJECT_VERSION = / { print $3; exit }' <<<"${BUILD_SETTINGS}")"
[[ ${VERSION} =~ ^[0-9]+(\.[0-9]+)*$ ]] || fail "invalid marketing version"
[[ ${BUILD_NUMBER} =~ ^[0-9]+$ ]] || fail "build number must be a positive integer"
[[ ${BUILD_NUMBER} -gt 0 ]] || fail "build number must be a positive integer"
COMMIT="$(git rev-parse HEAD)"
SHORT_COMMIT="$(git rev-parse --short=12 HEAD)"
TAG="v${VERSION}"
RELEASE_ID="${SCHEME}-${VERSION}-${BUILD_NUMBER}-${SHORT_COMMIT}"
OUTPUT_DIR="${BUILD_ROOT}/Releases/${RELEASE_ID}"
ARCHIVE_PATH="${BUILD_ROOT}/Archives/${RELEASE_ID}.xcarchive"
ZIP_NAME="Imaxe-${VERSION}.zip"
NOTES_NAME="Imaxe-${VERSION}.md"
ASSETS=("${ZIP_NAME}" release.json SHA256SUMS.txt)

TEMP_DIR="$(mktemp -d "${BUILD_ROOT}/.release-check.XXXXXX")"

# Validate public reachability before creating or publishing an update-enabled build.
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
  "${FEED_URL}" -o "${TEMP_DIR}/online.xml"
xmllint --nonet --noout "${TEMP_DIR}/online.xml"
[[ "$(xmllint --nonet --xpath 'count(/rss/channel)' "${TEMP_DIR}/online.xml")" == 1 ]] || fail "feed is not an RSS appcast"
[[ "$(xmllint --nonet --xpath 'count(/rss/channel/item)' "${TEMP_DIR}/online.xml")" -le 1 ]] || fail "review multi-item feed version policy before publishing"
ONLINE_BUILD="$(xmllint --nonet --xpath 'string(/rss/channel/item/*[local-name()="version"])' "${TEMP_DIR}/online.xml")"
if [[ -n ${ONLINE_BUILD} ]]; then
  [[ ${ONLINE_BUILD} =~ ^[0-9]+$ ]] || fail "online feed has an invalid build number"
  [[ ${BUILD_NUMBER} -ge ${ONLINE_BUILD} ]] || fail "build number is lower than the public feed"
  if [[ ${BUILD_NUMBER} -eq ${ONLINE_BUILD} ]]; then
    [[ ${PUBLISH} == true ]] || fail "increase the public build number before building"
    cmp -s "${TEMP_DIR}/online.xml" "${OUTPUT_DIR}/appcast.xml" || fail "same online build has a different appcast"
  fi
fi

# A withdrawn/stale feed must not hide a higher build already published on GitHub.
[[ "$(gh api "repos/${REPOSITORY}" --jq .visibility)" == public ]] || fail "repository must be public"
gh api --paginate "repos/${REPOSITORY}/releases" \
  --jq '.[] | select(.draft == false and .prerelease == false) | .assets[] | select(.name == "release.json") | .browser_download_url' \
  >"${TEMP_DIR}/published-manifests"
while IFS= read -r manifest_url; do
  [[ -n ${manifest_url} ]] || continue
  curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    "${manifest_url}" -o "${TEMP_DIR}/published.json"
  PUBLISHED_BUILD="$(jq -r .build "${TEMP_DIR}/published.json")"
  [[ ${PUBLISHED_BUILD} =~ ^[0-9]+$ ]] || fail "published release has an invalid build number"
  [[ ${BUILD_NUMBER} -ge ${PUBLISHED_BUILD} ]] || fail "build number is lower than a published release"
  if [[ ${BUILD_NUMBER} -eq ${PUBLISHED_BUILD} ]]; then
    [[ ${PUBLISH} == true ]] || fail "increase the build number beyond all published releases"
    [[ "$(jq -r .commit "${TEMP_DIR}/published.json")" == "${COMMIT}" &&
    "$(jq -r .version "${TEMP_DIR}/published.json")" == "${VERSION}" ]] || fail "published build identifies a different artifact"
  fi
done <"${TEMP_DIR}/published-manifests"

if [[ ${PUBLISH} == true ]]; then
  swift Scripts/validate-release.swift "${OUTPUT_DIR}" "${COMMIT}"
  REMOTE_MAIN="$(git ls-remote origin refs/heads/main | awk '{print $1}')"
  [[ ${REMOTE_MAIN} == "${COMMIT}" ]] || fail "origin/main must point to this exact commit"

  REMOTE_TAGS="$(git ls-remote origin "refs/tags/${TAG}" "refs/tags/${TAG}^{}")"
  REMOTE_TAG_COMMIT="$(awk '/\^\{\}$/ {print $1; found=1} END {if (!found) exit 1}' <<<"${REMOTE_TAGS}" || true)"
  if [[ -z ${REMOTE_TAG_COMMIT} ]]; then REMOTE_TAG_COMMIT="$(awk 'NR == 1 {print $1}' <<<"${REMOTE_TAGS}")"; fi
  [[ -z ${REMOTE_TAG_COMMIT} || ${REMOTE_TAG_COMMIT} == "${COMMIT}" ]] || fail "remote tag belongs to another commit"
  if git rev-parse --verify --quiet "refs/tags/${TAG}" >/dev/null; then
    [[ "$(git rev-parse "${TAG}^{commit}")" == "${COMMIT}" ]] || fail "local tag belongs to another commit"
  elif [[ -z ${REMOTE_TAG_COMMIT} ]]; then
    git tag -a "${TAG}" -m "Imaxe ${TAG}"
  fi
  if [[ -z ${REMOTE_TAG_COMMIT} ]]; then git push origin "refs/tags/${TAG}"; fi

  if ! gh release view "${TAG}" --repo "${REPOSITORY}" --json isDraft,assets,body >"${TEMP_DIR}/release.json"; then
    gh release create "${TAG}" --repo "${REPOSITORY}" --verify-tag --draft \
      --title "Imaxe ${VERSION}" --notes-file "${OUTPUT_DIR}/${NOTES_NAME}"
    gh release view "${TAG}" --repo "${REPOSITORY}" --json isDraft,assets,body >"${TEMP_DIR}/release.json"
  fi
  jq -e --arg zip "${ZIP_NAME}" \
    'all(.assets[]; .name == $zip or .name == "release.json" or .name == "SHA256SUMS.txt")' \
    "${TEMP_DIR}/release.json" >/dev/null || fail "release contains unexpected assets"
  jq -e --rawfile notes "${OUTPUT_DIR}/${NOTES_NAME}" '.body == $notes' \
    "${TEMP_DIR}/release.json" >/dev/null || fail "release notes differ from the verified artifact"
  mkdir -p "${TEMP_DIR}/download"
  for asset in "${ASSETS[@]}"; do
    if jq -e --arg name "${asset}" '.assets[] | select(.name == $name)' "${TEMP_DIR}/release.json" >/dev/null; then
      gh release download "${TAG}" --repo "${REPOSITORY}" --pattern "${asset}" --dir "${TEMP_DIR}/download"
      cmp -s "${TEMP_DIR}/download/${asset}" "${OUTPUT_DIR}/${asset}" || fail "published asset differs: ${asset}"
    else
      [[ "$(jq -r .isDraft "${TEMP_DIR}/release.json")" == true ]] || fail "published release is missing ${asset}"
      gh release upload "${TAG}" "${OUTPUT_DIR}/${asset}" --repo "${REPOSITORY}"
      gh release download "${TAG}" --repo "${REPOSITORY}" --pattern "${asset}" --dir "${TEMP_DIR}/download"
      cmp -s "${TEMP_DIR}/download/${asset}" "${OUTPUT_DIR}/${asset}" || fail "uploaded asset differs: ${asset}"
    fi
  done
  swift Scripts/validate-release.swift "${TEMP_DIR}/download" "${COMMIT}"
  if [[ "$(jq -r .isDraft "${TEMP_DIR}/release.json")" == true ]]; then
    gh release edit "${TAG}" --repo "${REPOSITORY}" --draft=false --latest
  fi
  echo "Verified GitHub Release ${TAG}; the Updates workflow deploys its appcast."
  exit 0
fi

[[ ! -e ${OUTPUT_DIR} && ! -e ${ARCHIVE_PATH} ]] || fail "release identity already exists; refusing to overwrite"
shopt -s nullglob
EXISTING=("${BUILD_ROOT}/Releases/${SCHEME}-${VERSION}-${BUILD_NUMBER}-"*)
[[ ${#EXISTING[@]} -eq 0 ]] || fail "this version/build already identifies another artifact"
shopt -u nullglob
mkdir -p "${BUILD_ROOT}/Archives" "${TEMP_DIR}/artifacts" "${BUILD_ROOT}/Releases"
CREATED_ARCHIVE=true
xcodebuild archive -project Imaxe.xcodeproj -scheme "${SCHEME}" -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "${DERIVED_DATA_DIR}" \
  -archivePath "${ARCHIVE_PATH}" ARCHS=arm64 CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual -quiet

APP="${ARCHIVE_PATH}/Products/Applications/Imaxe.app"
INFO="${APP}/Contents/Info.plist"
[[ "$(plist "${INFO}" CFBundleShortVersionString)" == "${VERSION}" && "$(plist "${INFO}" CFBundleVersion)" == "${BUILD_NUMBER}" ]] || fail "archive version mismatch"
[[ -x ${SPARKLE_BIN}/generate_appcast ]] || fail "Sparkle tool missing from this archive's resolved artifacts"
[[ "$("${SPARKLE_BIN}/generate_keys" -p)" == "${PUBLIC_KEY}" ]] || fail "Keychain signing key does not match SUPublicEDKey"
MINIMUM_SYSTEM="$(plist "${INFO}" LSMinimumSystemVersion)"
ARTIFACTS="${TEMP_DIR}/artifacts"
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${ARTIFACTS}/${ZIP_NAME}"
[[ "$(head -n 1 Distribution/release-notes.md)" == "# Imaxe ${VERSION}" ]] || fail "update release notes for this version"
cp Distribution/release-notes.md "${ARTIFACTS}/${NOTES_NAME}"

"${SPARKLE_BIN}/generate_appcast" --maximum-deltas 0 \
  --download-url-prefix "${REPOSITORY_URL}/releases/download/${TAG}/" \
  --embed-release-notes --full-release-notes-url "${REPOSITORY_URL}/releases/tag/${TAG}" \
  --link "${REPOSITORY_URL}" "${ARTIFACTS}"
jq -n --arg version "${VERSION}" --arg build "${BUILD_NUMBER}" --arg commit "${COMMIT}" \
  --arg minimumSystemVersion "${MINIMUM_SYSTEM}" --arg feedURL "${FEED_URL}" --arg publicEDKey "${PUBLIC_KEY}" \
  --rawfile appcastXML "${ARTIFACTS}/appcast.xml" \
  '{version:$version,build:$build,commit:$commit,minimumSystemVersion:$minimumSystemVersion,feedURL:$feedURL,publicEDKey:$publicEDKey,appcastXML:$appcastXML}' \
  >"${ARTIFACTS}/release.json"
(cd "${ARTIFACTS}" && shasum -a 256 "${ZIP_NAME}" release.json >SHA256SUMS.txt)
swift Scripts/validate-release.swift "${ARTIFACTS}" "${COMMIT}"
mv "${ARTIFACTS}" "${OUTPUT_DIR}"
CREATED_ARCHIVE=false
echo "Created and verified ${OUTPUT_DIR}"
