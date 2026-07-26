#!/bin/bash

set -euo pipefail

PROJECT="Imaxe.xcodeproj"
SCHEME="Imaxe"
CONFIGURATION="Release"
BUILD_ROOT="${PWD}/Build"
ARCHIVES_DIR="${BUILD_ROOT}/Archives"
PRODUCTS_DIR="${BUILD_ROOT}/Releases"
DERIVED_DATA_DIR="${BUILD_ROOT}/DerivedData/Release"
PUBLISH=false

if [[ ${1:-} == "--publish" ]]; then
  PUBLISH=true
elif [[ -n ${1:-} ]]; then
  echo "usage: $0 [--publish]" >&2
  exit 64
fi

if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo "error: release builds require a clean Git worktree" >&2
  exit 1
fi

require_value() {
  local name="$1"
  local value="$2"
  if [[ -z ${value} ]]; then
    echo "error: unable to determine ${name}" >&2
    exit 1
  fi
}

release_tag_for_version() {
  local version="$1"
  local component
  local -a components=()

  if [[ ! ${version} =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "error: marketing version must contain one to three numeric components" >&2
    exit 1
  fi

  IFS='.' read -r -a components <<<"${version}"
  for component in "${components[@]}"; do
    if [[ ! ${component} =~ ^[0-9]+$ ]]; then
      echo "error: marketing version must contain only numeric components" >&2
      exit 1
    fi
  done

  while ((${#components[@]} < 3)); do
    components+=("0")
  done

  printf 'v%s.%s.%s' "${components[0]}" "${components[1]}" "${components[2]}"
}

if [[ ${PUBLISH} == true && "$(git branch --show-current)" != "main" ]]; then
  echo "Switching to main..."
  git switch main
fi

BUILD_SETTINGS="$(xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" -destination "platform=macOS,arch=arm64" -showBuildSettings)"
VERSION="$(awk '/ MARKETING_VERSION = / { print $3; exit }' <<<"${BUILD_SETTINGS}")"
BUILD_NUMBER="$(awk '/ CURRENT_PROJECT_VERSION = / { print $3; exit }' <<<"${BUILD_SETTINGS}")"
COMMIT="$(git rev-parse HEAD)"
SHORT_COMMIT="$(git rev-parse --short=12 HEAD)"

require_value "version" "${VERSION}"
require_value "build number" "${BUILD_NUMBER}"
require_value "Git commit" "${COMMIT}"

RELEASE_ID="${SCHEME}-${VERSION}-${BUILD_NUMBER}-${SHORT_COMMIT}"
OUTPUT_DIR="${PRODUCTS_DIR}/${RELEASE_ID}"
STAGING_DIR="${PRODUCTS_DIR}/.${RELEASE_ID}-$(uuidgen).tmp"
ARCHIVE_PATH="${ARCHIVES_DIR}/${RELEASE_ID}.xcarchive"
APP_NAME="${SCHEME}.app"
ZIP_NAME="${RELEASE_ID}-macOS.zip"
ZIP_FILE="${OUTPUT_DIR}/${ZIP_NAME}"
NOTES_FILE="${OUTPUT_DIR}/release-notes.md"
CHECKSUM_FILE="${OUTPUT_DIR}/SHA256SUMS.txt"
TAG="$(release_tag_for_version "${VERSION}")"

if [[ ${PUBLISH} == true ]]; then
  for file in "${ZIP_FILE}" "${NOTES_FILE}" "${CHECKSUM_FILE}"; do
    if [[ ! -f ${file} ]]; then
      echo "error: release artifact not found at ${file}; run $0 before publishing" >&2
      exit 1
    fi
  done

  if ! command -v gh >/dev/null 2>&1; then
    echo "error: GitHub CLI (gh) is required for --publish" >&2
    exit 1
  fi
  if gh release view "${TAG}" >/dev/null 2>&1; then
    echo "error: GitHub Release ${TAG} already exists; refusing to replace it" >&2
    exit 1
  fi

  if git rev-parse --verify --quiet "refs/tags/${TAG}" >/dev/null; then
    echo "error: local tag ${TAG} already exists; refusing to replace it" >&2
    exit 1
  fi
  if git ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1; then
    echo "error: remote tag ${TAG} already exists; refusing to replace it" >&2
    exit 1
  fi

  git tag -a "${TAG}" -m "Imaxe ${TAG}"
  git push origin "${TAG}"
  gh release create --verify-tag "${TAG}" \
    "${ZIP_FILE}" \
    "${CHECKSUM_FILE}" \
    --title "Imaxe ${VERSION}" \
    --notes-file "${NOTES_FILE}"
  echo "Published GitHub Release ${TAG}"
  exit 0
fi

if [[ -e ${OUTPUT_DIR} || -e ${ARCHIVE_PATH} ]]; then
  echo "error: release ${RELEASE_ID} already exists; refusing to overwrite a build identity" >&2
  exit 1
fi

shopt -s nullglob
EXISTING_BUILD_ARTIFACTS=("${PRODUCTS_DIR}/${SCHEME}-${VERSION}-${BUILD_NUMBER}-"*)
if ((${#EXISTING_BUILD_ARTIFACTS[@]} > 0)); then
  echo "error: version ${VERSION} build ${BUILD_NUMBER} already maps to another artifact" >&2
  exit 1
fi
shopt -u nullglob

cleanup() {
  rm -rf "${STAGING_DIR}" "${ARCHIVE_PATH}"
}
trap cleanup EXIT

mkdir -p "${ARCHIVES_DIR}" "${STAGING_DIR}" "${DERIVED_DATA_DIR}"

echo "Archiving ${SCHEME} ${VERSION} (${BUILD_NUMBER}) at ${SHORT_COMMIT}..."
xcodebuild archive \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  -archivePath "${ARCHIVE_PATH}" \
  -quiet

ARCHIVED_APP="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}"
if [[ ! -d ${ARCHIVED_APP} ]]; then
  echo "error: archived app not found at ${ARCHIVED_APP}" >&2
  exit 1
fi

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "${ARCHIVED_APP}/Contents/Info.plist")"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "${ARCHIVED_APP}/Contents/Info.plist")"
if [[ ${APP_VERSION} != "${VERSION}" || ${APP_BUILD} != "${BUILD_NUMBER}" ]]; then
  echo "error: archived app version does not match resolved build settings" >&2
  exit 1
fi

STAGING_ZIP="${STAGING_DIR}/${ZIP_NAME}"
STAGING_NOTES="${STAGING_DIR}/release-notes.md"
STAGING_CHECKSUM="${STAGING_DIR}/SHA256SUMS.txt"

echo "Creating ${STAGING_ZIP}..."
ditto -c -k --sequesterRsrc --keepParent "${ARCHIVED_APP}" "${STAGING_ZIP}"
CHECKSUM="$(shasum -a 256 "${STAGING_ZIP}" | awk '{ print $1 }')"

cat >"${STAGING_NOTES}" <<EOF
## Imaxe ${VERSION} (${BUILD_NUMBER})
EOF

echo "${CHECKSUM}  ${ZIP_NAME}" >"${STAGING_CHECKSUM}"

mv "${STAGING_DIR}" "${OUTPUT_DIR}"
trap - EXIT
echo "Created ${ZIP_FILE}"
