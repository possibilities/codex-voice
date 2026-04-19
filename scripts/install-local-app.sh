#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CodexVoice.app"
DEST_DIR="${HOME}/Applications"
DEST_APP="${DEST_DIR}/${APP_NAME}"

cd "${ROOT_DIR}"

xcodebuild -project CodexVoice.xcodeproj -scheme CodexVoice -configuration Debug build >/dev/null

BUILD_SETTINGS="$(xcodebuild -project CodexVoice.xcodeproj -scheme CodexVoice -configuration Debug -showBuildSettings)"
TARGET_BUILD_DIR="$(printf '%s\n' "${BUILD_SETTINGS}" | awk -F' = ' '/TARGET_BUILD_DIR/ {print $2; exit}')"

if [[ -z "${TARGET_BUILD_DIR}" ]]; then
  echo "Could not determine TARGET_BUILD_DIR" >&2
  exit 1
fi

mkdir -p "${DEST_DIR}"
rm -rf "${DEST_APP}"
cp -R "${TARGET_BUILD_DIR}/${APP_NAME}" "${DEST_APP}"

open "${DEST_APP}"

echo "Installed to ${DEST_APP}"
