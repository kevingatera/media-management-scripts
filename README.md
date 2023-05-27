# Media Management Scripts

This repository contains two utility scripts for managing media files:

1. `clean_audio_tracks.sh`: This script cleans up audio tracks in media files. It removes unsupported audio sources and converts non-standard audio codecs to a more common format (e.g., AC3).

2. `check_codec_support.sh`: This script checks if the codecs used in your media files are supported by your devices or media players.

## Usage

For `clean_audio_tracks.sh`:

```bash
./clean_audio_tracks.sh [--dir=DIR] [--dry-run] [--no-progress]
```

For `check_codec_support.sh`:

```bash
./check_codec_support.sh [--file=FILE]
```
