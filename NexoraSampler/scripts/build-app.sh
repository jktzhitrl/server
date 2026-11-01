#!/bin/bash
# Baut die eigenständige "NEXORA Sampler.app" (Universal: Apple Silicon + Intel) und legt sie in dist/ ab.
# Verwendung: ./scripts/build-app.sh [Release|Debug]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-Release}"
DERIVED="build/DerivedData"

echo "▶︎ Baue NEXORA Sampler ($CONFIG) …"
xcodebuild \
  -project NexoraSampler.xcodeproj \
  -scheme NexoraSampler \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  -destination 'generic/platform=macOS' \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  build

APP="$DERIVED/Build/Products/$CONFIG/NEXORA Sampler.app"
if [ ! -d "$APP" ]; then
  echo "✖︎ App wurde nicht gefunden: $APP" >&2
  exit 1
fi

mkdir -p dist
rm -rf "dist/NEXORA Sampler.app"
cp -R "$APP" dist/
ditto -c -k --keepParent "dist/NEXORA Sampler.app" "dist/NEXORA-Sampler-macOS.zip"

echo "✔︎ Fertig:"
echo "   dist/NEXORA Sampler.app"
echo "   dist/NEXORA-Sampler-macOS.zip"
echo "Installation: App in den Ordner /Programme ziehen."
