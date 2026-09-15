# Soundtrack

A small Mac app that records what your Mac is playing — not the microphone — and saves a 320 kbps MP3 on your Desktop.

You may download, use, copy, and share it freely.

## Download

**[Soundtrack-macOS.zip](https://github.com/eddydong/soundtrack/releases/latest/download/Soundtrack-macOS.zip)**

Apple silicon Mac, macOS 14 or later.

## Install

1. Unzip the file.
2. Drag Soundtrack into Applications, or leave it in Downloads.
3. First launch: Control-click Soundtrack, choose **Open**, then click **Open**. This build is not notarized, so that extra click is required once.
4. When macOS asks, allow Soundtrack under **System Settings → Privacy & Security → Screen and System Audio Recording**.
5. Quit and reopen Soundtrack if recording still fails after you allow it.

## Record

1. Start the song or page you want.
2. Choose **Everything playing** or **Browser only**.
3. Press **Record**, then **Stop** when the music ends.
4. The MP3 appears on your Desktop.

## Build from source

```sh
./scripts/package.sh
```

That writes `dist/Soundtrack-macOS.zip` and copies it to your Desktop.
