#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

IDENTITY="${CODE_SIGN_IDENTITY:-Apple Development: eddykd@icloud.com (3SS94MK3ZN)}"
APP="$ROOT/dist/Soundtrack.app"
HELPERS="$APP/Contents/Helpers"
RESOURCES="$APP/Contents/Resources"

swift build -c release --product Soundtrack
BIN="$(swift build -c release --show-bin-path)/Soundtrack"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$RESOURCES" "$HELPERS/Licenses"
cp "$BIN" "$APP/Contents/MacOS/Soundtrack"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/App/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/App/soundtrack-icon.png" "$APP/Contents/Resources/AppIcon.png"
echo -n 'APPL????' > "$APP/Contents/PkgInfo"

LAME_BIN="$(python3 -c "import os; print(os.path.realpath('/opt/homebrew/bin/lame'))")"
MPG_LIB="/opt/homebrew/opt/mpg123/lib/libmpg123.0.dylib"
if [[ ! -x "$LAME_BIN" || ! -f "$MPG_LIB" ]]; then
  echo "Need Homebrew lame (brew install lame) to bundle the MP3 encoder." >&2
  exit 1
fi

cp "$LAME_BIN" "$HELPERS/lame"
cp "$MPG_LIB" "$HELPERS/libmpg123.0.dylib"
chmod u+w "$HELPERS/lame" "$HELPERS/libmpg123.0.dylib"
install_name_tool -id @executable_path/libmpg123.0.dylib "$HELPERS/libmpg123.0.dylib"
install_name_tool -change /opt/homebrew/opt/mpg123/lib/libmpg123.0.dylib @executable_path/libmpg123.0.dylib "$HELPERS/lame"
cp /opt/homebrew/Cellar/lame/*/COPYING "$HELPERS/Licenses/LAME-COPYING"
cp /opt/homebrew/Cellar/lame/*/LICENSE "$HELPERS/Licenses/LAME-LICENSE"
cp /opt/homebrew/Cellar/mpg123/*/COPYING "$HELPERS/Licenses/mpg123-COPYING"

codesign --force --sign "$IDENTITY" --identifier com.eddy.soundtrack.lame --timestamp=none "$HELPERS/libmpg123.0.dylib"
codesign --force --sign "$IDENTITY" --identifier com.eddy.soundtrack.lame --timestamp=none "$HELPERS/lame"
codesign --force --deep --sign "$IDENTITY" --identifier com.eddy.soundtrack --timestamp=none "$APP"
echo "Built $APP"
