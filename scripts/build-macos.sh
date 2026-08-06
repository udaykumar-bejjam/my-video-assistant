#!/usr/bin/env bash
# Build a distributable macOS CaptionStudio.app (ad-hoc signed).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DERIVED="${DERIVED_DATA_PATH:-$ROOT/build/DerivedData}"
OUT_DIR="${OUT_DIR:-$ROOT/build/dist}"
APP_NAME="CaptionStudio"
ZIP_NAME="${ZIP_NAME:-CaptionStudio-macOS.zip}"

rm -rf "$DERIVED" "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo "==> Building $APP_NAME (macOS Release, ad-hoc signed)"
xcodebuild \
  -project CaptionStudio.xcodeproj \
  -scheme CaptionStudio \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  DEVELOPMENT_TEAM="" \
  ONLY_ACTIVE_ARCH=NO \
  build

APP_PATH="$(find "$DERIVED/Build/Products/Release" -maxdepth 2 -name "${APP_NAME}.app" -print -quit)"
if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "ERROR: ${APP_NAME}.app not found under $DERIVED/Build/Products/Release"
  find "$DERIVED/Build/Products" -maxdepth 3 -type d -name "*.app" || true
  exit 1
fi

echo "==> Found app at $APP_PATH"
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --verbose=2 "$APP_PATH" || true

STAGE="$OUT_DIR/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"

cat > "$STAGE/INSTALL.txt" <<'EOF'
CaptionStudio for macOS (unsigned / ad-hoc build)

Requirements
- macOS 14 Sonoma or newer
- Optional: Node 22+ for the local Cursor enhancer (see README)

Install
1. Unzip this archive.
2. Drag CaptionStudio.app to /Applications (or run in place).
3. First launch: right-click the app → Open → Open
   (Gatekeeper blocks ad-hoc signed apps until you allow once.)
   Or: xattr -dr com.apple.quarantine /Applications/CaptionStudio.app

Enhancer (optional AI placements)
  cd enhancer-server && npm install && npm start

Speech captions work offline without the enhancer.
EOF

(
  cd "$STAGE"
  ditto -c -k --sequesterRsrc --keepParent CaptionStudio.app "../${ZIP_NAME%.zip}-app-only.zip" 2>/dev/null || \
    zip -r "../${ZIP_NAME%.zip}-app-only.zip" CaptionStudio.app
  zip -r "../$ZIP_NAME" CaptionStudio.app INSTALL.txt
)

echo "==> Artifacts:"
ls -lh "$OUT_DIR"/*.zip
echo "APP_PATH=$APP_PATH"
echo "ZIP=$OUT_DIR/$ZIP_NAME"
