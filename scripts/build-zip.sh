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
  echo "Build using build/Releases/Imaxe-<version>-<build>-<commit>/Imaxe-<version>.md."
  echo "If notes are missing, the script prints their path; write them and rerun."
  echo "Use --publish to publish the exact existing artifact from main."
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
BUILD_ROOT="${PWD}/build"
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
NOTES_FILE="${OUTPUT_DIR}/${NOTES_NAME}"
ASSETS=("${ZIP_NAME}" SHA256SUMS.txt)

if [[ ${PUBLISH} == false ]]; then
  [[ ! -e ${ARCHIVE_PATH} ]] || fail "release identity already exists; refusing to overwrite"
  [[ ! -L ${OUTPUT_DIR} ]] || fail "release directory must not be a symbolic link"
  shopt -s nullglob dotglob
  for path in "${BUILD_ROOT}/Releases/${SCHEME}-${VERSION}-${BUILD_NUMBER}-"*; do
    [[ ${path} == "${OUTPUT_DIR}" && -d ${path} ]] || fail "this version/build already identifies another artifact"
  done
  for path in "${OUTPUT_DIR}/"*; do
    [[ ${path} == "${NOTES_FILE}" && -f ${path} && ! -L ${path} ]] || fail "release identity already exists; refusing to overwrite"
  done
  shopt -u nullglob dotglob
  mkdir -p "${OUTPUT_DIR}"
  [[ -f ${NOTES_FILE} ]] || fail "write release notes to ${NOTES_FILE}, then rerun the build"
  [[ "$(head -n 1 "${NOTES_FILE}")" == "# Imaxe ${VERSION}" ]] || fail "release notes must start with # Imaxe ${VERSION}"
fi

TEMP_DIR="$(mktemp -d "${BUILD_ROOT}/.release-check.XXXXXX")"

# Validate public reachability before creating or publishing an update-enabled build.
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
  "${FEED_URL}" -o "${TEMP_DIR}/online.xml"
xmllint --nonet --noout "${TEMP_DIR}/online.xml"
ONLINE_BUILD="$(swift scripts/appcast.swift newest "${TEMP_DIR}/online.xml")"
if [[ ${ONLINE_BUILD} -gt 0 ]]; then
  [[ ${BUILD_NUMBER} -ge ${ONLINE_BUILD} ]] || fail "build number is lower than the public feed"
  if [[ ${BUILD_NUMBER} -eq ${ONLINE_BUILD} ]]; then
    [[ ${PUBLISH} == true ]] || fail "increase the public build number before building"
  fi
fi

# Check the complete public release catalog, including items pruned from the root feed.
[[ "$(gh api "repos/${REPOSITORY}" --jq .visibility)" == public ]] || fail "repository must be public"
git clone --quiet --depth 1 --single-branch --branch gh-pages "$(git remote get-url origin)" "${TEMP_DIR}/site"
gh api --paginate --slurp "repos/${REPOSITORY}/releases" >"${TEMP_DIR}/releases.json"
swift scripts/appcast.swift catalog "${TEMP_DIR}/site/history" "${TEMP_DIR}/releases.json" >"${TEMP_DIR}/catalog.json"
while IFS=$'\t' read -r PUBLISHED_BUILD PUBLISHED_COMMIT PUBLISHED_VERSION; do
  [[ ${BUILD_NUMBER} -ge ${PUBLISHED_BUILD} ]] || fail "build number is lower than a published release"
  if [[ ${BUILD_NUMBER} -eq ${PUBLISHED_BUILD} ]]; then
    [[ ${PUBLISH} == true ]] || fail "increase the build number beyond all published releases"
    [[ ${PUBLISHED_COMMIT} == "${COMMIT}" && ${PUBLISHED_VERSION} == "${VERSION}" ]] || fail "published build identifies a different artifact"
  fi
done < <(jq -r '.[] | [.build, .commit, .version] | @tsv' "${TEMP_DIR}/catalog.json")

if [[ ${PUBLISH} == true ]]; then
  swift scripts/validate-release.swift "${OUTPUT_DIR}" "${COMMIT}"
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

  RELEASE_STATE="${TEMP_DIR}/github-release-state.json"
  if ! gh release view "${TAG}" --repo "${REPOSITORY}" --json isDraft,assets,body >"${RELEASE_STATE}"; then
    gh release create "${TAG}" --repo "${REPOSITORY}" --verify-tag --draft \
      --title "Imaxe ${VERSION}" --notes-file "${OUTPUT_DIR}/${NOTES_NAME}"
    gh release view "${TAG}" --repo "${REPOSITORY}" --json isDraft,assets,body >"${RELEASE_STATE}"
  fi
  jq -e --arg zip "${ZIP_NAME}" \
    'all(.assets[]; .name == $zip or .name == "SHA256SUMS.txt")' \
    "${RELEASE_STATE}" >/dev/null || fail "release contains unexpected assets"
  jq -e --rawfile notes "${OUTPUT_DIR}/${NOTES_NAME}" '.body == $notes' \
    "${RELEASE_STATE}" >/dev/null || fail "release notes differ from the verified artifact"
  mkdir -p "${TEMP_DIR}/download"
  for asset in "${ASSETS[@]}"; do
    if jq -e --arg name "${asset}" '.assets[] | select(.name == $name)' "${RELEASE_STATE}" >/dev/null; then
      gh release download "${TAG}" --repo "${REPOSITORY}" --pattern "${asset}" --dir "${TEMP_DIR}/download"
      cmp -s "${TEMP_DIR}/download/${asset}" "${OUTPUT_DIR}/${asset}" || fail "published asset differs: ${asset}"
    else
      [[ "$(jq -r .isDraft "${RELEASE_STATE}")" == true ]] || fail "published release is missing ${asset}"
      gh release upload "${TAG}" "${OUTPUT_DIR}/${asset}" --repo "${REPOSITORY}"
      gh release download "${TAG}" --repo "${REPOSITORY}" --pattern "${asset}" --dir "${TEMP_DIR}/download"
      cmp -s "${TEMP_DIR}/download/${asset}" "${OUTPUT_DIR}/${asset}" || fail "uploaded asset differs: ${asset}"
    fi
  done
  cp "${OUTPUT_DIR}/appcast.xml" "${TEMP_DIR}/download/appcast.xml"
  swift scripts/validate-release.swift "${TEMP_DIR}/download" "${COMMIT}"
  HISTORY_FILE="${TEMP_DIR}/site/history/${TAG}/appcast.xml"
  if [[ -e ${HISTORY_FILE} ]]; then
    cmp -s "${OUTPUT_DIR}/appcast.xml" "${HISTORY_FILE}" || fail "history already contains a different artifact for ${TAG}"
  else
    mkdir -p "$(dirname "${HISTORY_FILE}")"
    cp "${OUTPUT_DIR}/appcast.xml" "${HISTORY_FILE}"
    git -C "${TEMP_DIR}/site" add "history/${TAG}/appcast.xml"
    git -C "${TEMP_DIR}/site" commit -m "chore(updates): archive appcast for ${TAG}"
    git -C "${TEMP_DIR}/site" push origin HEAD:refs/heads/gh-pages
  fi
  if [[ "$(jq -r .isDraft "${RELEASE_STATE}")" == true ]]; then
    gh release edit "${TAG}" --repo "${REPOSITORY}" --draft=false --latest
  fi
  echo "Verified GitHub Release ${TAG}; the Updates workflow deploys its appcast."
  exit 0
fi

mkdir -p "${BUILD_ROOT}/Archives" "${TEMP_DIR}/artifacts" "${BUILD_ROOT}/Releases"
CREATED_ARCHIVE=true
cp "${NOTES_FILE}" "${TEMP_DIR}/artifacts/${NOTES_NAME}"
xcodebuild archive -project Imaxe.xcodeproj -scheme "${SCHEME}" -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "${DERIVED_DATA_DIR}" \
  -archivePath "${ARCHIVE_PATH}" ARCHS=arm64 CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual -quiet

APP="${ARCHIVE_PATH}/Products/Applications/Imaxe.app"
INFO="${APP}/Contents/Info.plist"
[[ "$(plist "${INFO}" CFBundleShortVersionString)" == "${VERSION}" && "$(plist "${INFO}" CFBundleVersion)" == "${BUILD_NUMBER}" ]] || fail "archive version mismatch"
[[ -x ${SPARKLE_BIN}/generate_appcast ]] || fail "Sparkle tool missing from this archive's resolved artifacts"
[[ "$("${SPARKLE_BIN}/generate_keys" -p)" == "${PUBLIC_KEY}" ]] || fail "Keychain signing key does not match SUPublicEDKey"
ARTIFACTS="${TEMP_DIR}/artifacts"
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${ARTIFACTS}/${ZIP_NAME}"

"${SPARKLE_BIN}/generate_appcast" --maximum-deltas 0 \
  --download-url-prefix "${REPOSITORY_URL}/releases/download/${TAG}/" \
  --embed-release-notes --full-release-notes-url "${REPOSITORY_URL}/releases/tag/${TAG}" \
  --link "${REPOSITORY_URL}" "${ARTIFACTS}"
swift scripts/appcast.swift stamp "${ARTIFACTS}/appcast.xml" "${COMMIT}"
(cd "${ARTIFACTS}" && shasum -a 256 "${ZIP_NAME}" >SHA256SUMS.txt)
swift scripts/validate-release.swift "${ARTIFACTS}" "${COMMIT}"
cmp -s "${NOTES_FILE}" "${ARTIFACTS}/${NOTES_NAME}" || fail "release notes changed during the build; rerun with the final notes"
mv "${ARTIFACTS}/${ZIP_NAME}" "${ARTIFACTS}/appcast.xml" "${ARTIFACTS}/SHA256SUMS.txt" "${OUTPUT_DIR}/"
CREATED_ARCHIVE=false
echo "Created and verified ${OUTPUT_DIR}"
