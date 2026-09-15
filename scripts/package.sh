#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build.sh"

STAGE="$ROOT/dist/website"
APP_SRC="$ROOT/dist/Soundtrack.app"
ZIP="$ROOT/dist/Soundtrack-macOS.zip"
DESKTOP="$HOME/Desktop/Soundtrack-macOS.zip"

rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP_SRC" "$STAGE/Soundtrack.app"

# Website copies are ad-hoc signed so other Macs can open them with Control-click.
# Apple Development signatures only work on this Mac.
codesign --force --sign - --identifier com.eddy.soundtrack.lame "$STAGE/Soundtrack.app/Contents/Helpers/libmpg123.0.dylib"
codesign --force --sign - --identifier com.eddy.soundtrack.lame "$STAGE/Soundtrack.app/Contents/Helpers/lame"
codesign --force --deep --sign - --identifier com.eddy.soundtrack "$STAGE/Soundtrack.app"

cat > "$STAGE/Read Me.txt" <<'EOF'
Soundtrack
==========

A free Mac app that records what your Mac is playing — not the microphone —
and saves a 320 kbps MP3 on your Desktop.

You may download, use, copy, and share this app freely.

What you need
-------------
• An Apple silicon Mac (M1, M2, M3, M4, or later)
• macOS 14 Sonoma or later

Install
--------
1. Unzip this file.
2. Drag Soundtrack into Applications (or leave it in Downloads).
3. First launch: Control-click Soundtrack, choose Open, then click Open.
   Apple has not notarized this build, so that extra click is required once.
4. When macOS asks, allow Soundtrack under
   System Settings → Privacy & Security → Screen & System Audio Recording.
5. Quit and reopen Soundtrack if recording still fails after you allow it.

How to record
-------------
1. Start the song or page you want.
2. Choose “Everything playing” or “Browser only”.
3. Press Record, then Stop when the music ends.
4. The MP3 appears on your Desktop. Soundtrack never turns the mic on.

Soundtrack uses the LAME MP3 encoder (LGPL) and mpg123. Their licenses are
inside Soundtrack.app/Contents/Helpers/Licenses.
EOF

rm -f "$ZIP"
ditto -c -k "$STAGE" "$ZIP"
cp "$ZIP" "$DESKTOP"

echo "Website file: $ZIP"
echo "Also copied to: $DESKTOP"
ls -lh "$ZIP"
echo "---- zip contents ----"
unzip -l "$ZIP"
echo "---- signature ----"
codesign --verify --verbose=2 "$STAGE/Soundtrack.app"
echo "---- lame linkage ----"
otool -L "$STAGE/Soundtrack.app/Contents/Helpers/lame"
