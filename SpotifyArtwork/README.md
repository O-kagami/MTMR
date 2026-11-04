# Spotify artwork helper

This helper listens for Spotify playback notifications and updates `artwork.png` in its working directory. It fetches public track artwork using Spotify's oEmbed endpoint, rounds the image, and caches recent artwork in memory. It stays alive while either the original MTMR or the local test build is running. The local test build uses the bundle identifier `local.codex.MTMRLocalTest`.

Build on macOS with the Swift command-line tools:

```sh
mkdir -p /tmp/mtmr-swift-cache
swiftc -O -module-cache-path /tmp/mtmr-swift-cache artwork-fast.swift -o artwork-fast-rounded
```

Place `artwork-placeholder.png` in a writable working directory. Start the helper with the directory and the current Spotify track URI (or an empty string when no track is known):

```sh
./artwork-fast-rounded /path/to/artwork-directory 'spotify:track:TRACK_ID'
```

The caller should start it again if it stops while MTMR is running; its lock prevents duplicate workers in the same directory. The helper exits shortly after both recognized MTMR applications exit. `--status` reports whether a worker holds the directory lock. A build was tested with the local test application running, and with the lifecycle test mode simulating no running application. Actual Spotify track-change display remains a physical-device check.

Do not commit personal presets or artwork cache files to the repository.
