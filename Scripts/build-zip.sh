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

if [[ "${1:-}" == "--publish" ]]; then
  PUBLISH=true
elif [[ -n "${1:-}" ]]; then
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
  if [[ -z "${value}" ]]; then
    echo "error: unable to determine ${name}" >&2
    exit 1
  fi
}

BUILD_SETTINGS="$(xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" -showBuildSettings)"
VERSION="$(awk '/ MARKETING_VERSION = / { print $3; exit }' <<< "${BUILD_SETTINGS}")"
BUILD_NUMBER="$(awk '/ CURRENT_PROJECT_VERSION = / { print $3; exit }' <<< "${BUILD_SETTINGS}")"
MINIMUM_MACOS="$(awk '/ MACOSX_DEPLOYMENT_TARGET = / { print $3; exit }' <<< "${BUILD_SETTINGS}")"
COMMIT="$(git rev-parse HEAD)"
SHORT_COMMIT="$(git rev-parse --short=12 HEAD)"

require_value "version" "${VERSION}"
require_value "build number" "${BUILD_NUMBER}"
require_value "minimum macOS version" "${MINIMUM_MACOS}"
require_value "Git commit" "${COMMIT}"

RELEASE_ID="${SCHEME}-${VERSION}-${BUILD_NUMBER}-${SHORT_COMMIT}"
OUTPUT_DIR="${PRODUCTS_DIR}/${RELEASE_ID}"
STAGING_DIR="${PRODUCTS_DIR}/.${RELEASE_ID}-$(uuidgen).tmp"
ARCHIVE_PATH="${ARCHIVES_DIR}/${RELEASE_ID}.xcarchive"
APP_NAME="${SCHEME}.app"
ZIP_NAME="${RELEASE_ID}-macOS.zip"
OUTPUT_ZIP="${STAGING_DIR}/${ZIP_NAME}"
METADATA_FILE="${STAGING_DIR}/build-metadata.txt"
NOTES_FILE="${STAGING_DIR}/release-notes.md"
CHECKSUM_FILE="${STAGING_DIR}/SHA256SUMS.txt"
TAG="v${VERSION}-build.${BUILD_NUMBER}"

if [[ -e "${OUTPUT_DIR}" || -e "${ARCHIVE_PATH}" ]]; then
  echo "error: release ${RELEASE_ID} already exists; refusing to overwrite a build identity" >&2
  exit 1
fi

shopt -s nullglob
EXISTING_BUILD_ARTIFACTS=("${PRODUCTS_DIR}/${SCHEME}-${VERSION}-${BUILD_NUMBER}-"*)
if (( ${#EXISTING_BUILD_ARTIFACTS[@]} > 0 )); then
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
  -destination "generic/platform=macOS" \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  -archivePath "${ARCHIVE_PATH}" \
  -quiet

ARCHIVED_APP="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}"
if [[ ! -d "${ARCHIVED_APP}" ]]; then
  echo "error: archived app not found at ${ARCHIVED_APP}" >&2
  exit 1
fi

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "${ARCHIVED_APP}/Contents/Info.plist")"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "${ARCHIVED_APP}/Contents/Info.plist")"
if [[ "${APP_VERSION}" != "${VERSION}" || "${APP_BUILD}" != "${BUILD_NUMBER}" ]]; then
  echo "error: archived app version does not match resolved build settings" >&2
  exit 1
fi

ARCHITECTURES="$(lipo -archs "${ARCHIVED_APP}/Contents/MacOS/${SCHEME}")"

echo "Creating ${OUTPUT_ZIP}..."
ditto -c -k --sequesterRsrc --keepParent "${ARCHIVED_APP}" "${OUTPUT_ZIP}"
CHECKSUM="$(shasum -a 256 "${OUTPUT_ZIP}" | awk '{ print $1 }')"

cat > "${METADATA_FILE}" <<EOF
product=${SCHEME}
version=${VERSION}
build=${BUILD_NUMBER}
git_commit=${COMMIT}
minimum_macos=${MINIMUM_MACOS}
architectures=${ARCHITECTURES}
archive=${ARCHIVE_PATH#${PWD}/}
artifact=${ZIP_NAME}
sha256=${CHECKSUM}
EOF

cat > "${NOTES_FILE}" <<EOF
## Imaxe ${VERSION} (${BUILD_NUMBER})

- Requires macOS ${MINIMUM_MACOS} or later.
- Architectures: ${ARCHITECTURES}.
- Git commit: \`${COMMIT}\`.
- SHA-256: \`${CHECKSUM}\`.

If Gatekeeper blocks the downloaded app, extract the zip in Finder, Control-click \`Imaxe.app\`,
choose **Open**, then confirm **Open**. Verify the checksum before launching.
EOF

echo "${CHECKSUM}  ${ZIP_NAME}" > "${CHECKSUM_FILE}"

if [[ "${PUBLISH}" == true ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "error: GitHub CLI (gh) is required for --publish" >&2
    exit 1
  fi
  if gh release view "${TAG}" >/dev/null 2>&1; then
    echo "error: GitHub Release ${TAG} already exists; refusing to replace it" >&2
    exit 1
  fi
  gh release create "${TAG}" \
    "${OUTPUT_ZIP}" \
    "${METADATA_FILE}" \
    "${CHECKSUM_FILE}" \
    --title "Imaxe ${VERSION} (${BUILD_NUMBER})" \
    --notes-file "${NOTES_FILE}"
fi

mv "${STAGING_DIR}" "${OUTPUT_DIR}"
trap - EXIT
echo "Created ${OUTPUT_DIR}/${ZIP_NAME}"
