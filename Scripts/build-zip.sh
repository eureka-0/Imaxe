#!/bin/bash

set -euo pipefail

PROJECT="Imaxe.xcodeproj"
SCHEME="Imaxe"
CONFIGURATION="Release"
BUILD_DIR="./Build"
ARCHIVES_DIR="${HOME}/Library/Developer/Xcode/Archives"

RUN_DATE="$(date '+%Y-%m-%d')"
RUN_TIMESTAMP="$(date '+%Y-%m-%d %H.%M.%S')"
ARCHIVE_PATH="${ARCHIVES_DIR}/${RUN_DATE}/${SCHEME} ${RUN_TIMESTAMP}.xcarchive"

APP_NAME="${SCHEME}.app"
ZIP_NAME="${SCHEME}.zip"

mkdir -p "$(dirname "${ARCHIVE_PATH}")"

echo "Archiving ${SCHEME}..."
xcodebuild archive \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "platform=macOS,arch=arm64" \
  -archivePath "${ARCHIVE_PATH}" \
  -quiet

ARCHIVED_APP="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}"
if [[ ! -d "${ARCHIVED_APP}" ]]; then
  echo "error: archived app not found at ${ARCHIVED_APP}" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${ARCHIVED_APP}/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${ARCHIVED_APP}/Contents/Info.plist")"
OUTPUT_DIR="${BUILD_DIR}/${SCHEME} ${VERSION}(${BUILD_NUMBER})"
OUTPUT_APP="${OUTPUT_DIR}/${APP_NAME}"
OUTPUT_ZIP="${OUTPUT_DIR}/${ZIP_NAME}"

echo "Preparing ${OUTPUT_DIR}..."
mkdir -p "${OUTPUT_DIR}"
rm -rf "${OUTPUT_APP}" "${OUTPUT_ZIP}"

ditto "${ARCHIVED_APP}" "${OUTPUT_APP}"

echo "Creating ${OUTPUT_ZIP}..."
(
  cd "${OUTPUT_DIR}"
  ditto -c -k --sequesterRsrc --keepParent "${APP_NAME}" "${ZIP_NAME}"
)

echo "Removing copied app bundle..."
rm -rf "${OUTPUT_APP}"

echo "Keeping the newest 3 archives for ${SCHEME}..."
ARCHIVE_COUNT=0
while IFS= read -r ARCHIVE; do
  ARCHIVE_COUNT=$((ARCHIVE_COUNT + 1))
  if [[ "${ARCHIVE_COUNT}" -le 3 ]]; then
    continue
  fi

  echo "Deleting old archive: ${ARCHIVE}"
  rm -rf "${ARCHIVE}"
done < <(ls -td "${ARCHIVES_DIR}"/*/"${SCHEME} "*.xcarchive 2>/dev/null || true)

echo "Created ${OUTPUT_ZIP}"
