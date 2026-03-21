# Scripts

Utility scripts for managing your music library.

## convert_vbr.py

Batch converts problematic MP3 files to CBR (constant bitrate) 320kbps at 44.1kHz. This ensures maximum compatibility with mobile players and Navidrome.

### What it detects

- VBR (variable bitrate) encoding
- Non-standard sample rates (anything other than 44.1kHz)
- Low bitrate files (below 192kbps)
- Wrong MPEG layer (Layer 1/2 files disguised as MP3)

### Prerequisites

- Python 3
- ffmpeg installed and on PATH

```bash
cd scripts
python3 -m venv venv
source venv/bin/activate   # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### Usage

**Scan only (dry run):**
```bash
python convert_vbr.py --folder /path/to/music
```

**Convert problematic files (originals backed up to `_converted_backups/`):**
```bash
python convert_vbr.py --folder /path/to/music --convert
```

**Convert and replace originals (no backup):**
```bash
python convert_vbr.py --folder /path/to/music --convert --replace
```

**Re-encode all files regardless:**
```bash
python convert_vbr.py --folder /path/to/music --convert --all
```

You can also set `MUSIC_FOLDER` in a `.env` file instead of using `--folder`.
