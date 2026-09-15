#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

IDENTITY="${CODE_SIGN_IDENTITY:-Apple Development: eddykd@icloud.com (3SS94MK3ZN)}"
APP="$ROOT/dist/Soundtrack.app"

swift build -c release --product Soundtrack
BIN="$(swift build -c release --show-bin-path)/Soundtrack"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Soundtrack"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/App/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/App/soundtrack-icon.png" "$APP/Contents/Resources/AppIcon.png"
echo -n 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --deep --sign "$IDENTITY" --identifier com.eddy.soundtrack --timestamp=none "$APP"
echo "Built $APP"
