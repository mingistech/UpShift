#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
# This is a local sandbox prototype, not an App Store submission/export.
IDENTITY="${1:-Developer ID Application: Brandon Thompson (A8BNP8EEKC)}"
FFMPEG="${2:-$PROJECT_DIR/work/release-sources/ffmpeg-7.1/ffmpeg}"
if [[ ! -x .runtime/venv/bin/python || ! -x "$FFMPEG" ]]; then
    echo 'Install the development engine and build the encoder described in RELEASING.md first.' >&2
    exit 1
fi
STAGING="$PROJECT_DIR/work/AppStorePreview-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$STAGING"
xcodebuild -project UpShift.xcodeproj -scheme UpShift -configuration Release \
    -derivedDataPath work/StoreDerivedData ARCHS=arm64 \
    PRODUCT_BUNDLE_IDENTIFIER=com.mingistech.UpShift.StorePreview \
    CODE_SIGNING_ALLOWED=NO build
APP="$STAGING/UpShift.app"
ditto work/StoreDerivedData/Build/Products/Release/UpShift.app "$APP"
.runtime/venv/bin/python Scripts/package-runtime.py "$APP" --ffmpeg "$FFMPEG" --app-store
LICENSES="$APP/Contents/SharedSupport/Licenses"
mkdir -p "$LICENSES"
cp Configuration/AppStore/Licenses/OpenProteus-LICENSE.md "$LICENSES/"
cp Configuration/AppStore/Licenses/FFmpeg-LGPL-2.1.txt "$LICENSES/"
.runtime/venv/bin/python Scripts/sign-release.py "$APP" --identity "$IDENTITY" --app-store
.runtime/venv/bin/python Scripts/check-app-store.py "$APP" --prototype
printf '%s\n' "$APP" > work/app-store-preview-path.txt
printf '\nSandbox preview ready: %s\n' "$APP"
printf 'Store submission is gated on licensing, distribution signing, and the remaining App Store checklist.\n'
