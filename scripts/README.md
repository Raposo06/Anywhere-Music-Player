# 🎵 MP3 Uploader Script

Python script to upload your music library to MinIO and populate the PostgreSQL database.

---

## 📋 What It Does

This script automatically:
- ✅ Scans your music folder for MP3 files
- ✅ Extracts metadata (title, artist, album, duration)
- ✅ Extracts album cover art (if embedded in MP3)
- ✅ Uploads MP3 files to MinIO storage
- ✅ Uploads cover art images to MinIO
- ✅ Inserts track metadata into PostgreSQL
- ✅ Shows progress bar for large libraries
- ✅ Skips duplicate files automatically

---

## 🚀 Quick Start

### 1. Install Python Dependencies

```bash
cd scripts
pip install -r requirements.txt
```

### 2. Configure Environment

```bash
# Copy the example configuration
cp .env.example .env

# Edit .env with your credentials
nano .env  # or use your favorite editor
```

Fill in:
- `MUSIC_FOLDER` - Path to your local MP3 files
- `MINIO_ENDPOINT` - Your MinIO server (e.g., `minio.yourdomain.com`)
- `MINIO_ACCESS_KEY` - MinIO access key from Coolify
- `MINIO_SECRET_KEY` - MinIO secret key from Coolify
- `DB_PASSWORD` - PostgreSQL password

### 3. Set Up SSH Tunnel (If Needed)

If your PostgreSQL isn't publicly accessible:

```bash
# In a separate terminal, create SSH tunnel
ssh -L 5432:localhost:5432 root@YOUR_HETZNER_IP

# Keep this terminal open while running the uploader
```

### 4. Run the Uploader

```bash
python upload.py
```

---

## 📊 Example Output

```
🎵 Anywhere Music Player - MP3 Uploader
==================================================
🔌 Connecting to MinIO...
✅ MinIO connected
🔌 Connecting to PostgreSQL...
✅ Database connected

📂 Scanning folder: C:\Music\Anime
📊 Found 247 MP3 file(s)

⬆️  Uploading files...

Progress: 100%|████████████████| 247/247 [05:23<00:00,  1.31s/file]

==================================================
📊 Upload Summary:
   ✅ Uploaded: 245
   ⏭️  Skipped (duplicates): 2
   ❌ Failed: 0
==================================================

🎉 Success! 245 track(s) uploaded to your music library.

💡 Next steps:
   1. Verify tracks at: https://api.YOUR_DOMAIN/tracks
   2. Build the Flutter app to start streaming!
```

---

## 🔧 Configuration Reference

### Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `MUSIC_FOLDER` | Path to your MP3 library | `/home/user/Music` |
| `MINIO_ENDPOINT` | MinIO server (no https://) | `minio.example.com` |
| `MINIO_ACCESS_KEY` | MinIO access key | `minioadmin` |
| `MINIO_SECRET_KEY` | MinIO secret key | `minioadmin123` |
| `MINIO_BUCKET` | Bucket name | `anime-music` |
| `MINIO_SECURE` | Use HTTPS | `true` |
| `DB_HOST` | Database host | `localhost` |
| `DB_PORT` | Database port | `5432` |
| `DB_NAME` | Database name | `postgres` |
| `DB_USER` | Database user | `postgres` |
| `DB_PASSWORD` | Database password | (your password) |
| `DB_SCHEMA` | Schema name | `musicplayer` |

---

## 📁 Folder Structure

After running, your MinIO bucket will look like:

```
anime-music/
├── song1.mp3
├── song2.mp3
├── song3.mp3
└── covers/
    ├── song1.jpg
    ├── song2.jpg
    └── song3.jpg
```

---

## 🎨 Cover Art Handling

The script automatically:
- Extracts embedded album art from MP3 ID3 tags
- Resizes large images to max 800x800px (saves bandwidth)
- Converts to JPEG format
- Uploads to `covers/` subfolder in MinIO
- Stores URL in database (`cover_art_url` column)

**If no cover art is found:**
- The track is still uploaded
- `cover_art_url` is set to `NULL`
- Flutter app can show a default placeholder

---

## 🔄 Re-running the Script

The script is **idempotent** - safe to run multiple times:

- ✅ Duplicate files are automatically skipped (based on filename)
- ✅ New files are uploaded
- ✅ Existing files are not re-uploaded
- ✅ Database uses `ON CONFLICT (filename) DO NOTHING`

**To re-upload a file:**
1. Delete it from MinIO bucket
2. Delete it from `musicplayer.tracks` table
3. Run the script again

---

## ⚠️ Troubleshooting

### Error: "Missing dependency"

**Problem:** Python packages not installed

**Solution:**
```bash
pip install -r requirements.txt
```

---

### Error: "Music folder not found"

**Problem:** `MUSIC_FOLDER` path is incorrect

**Solution:**
- Check path in `.env` file
- Use absolute paths (not `~` or `..`)
- Windows: Use forward slashes or escape backslashes
  - ✅ `C:/Music/Anime`
  - ✅ `C:\\Music\\Anime`
  - ❌ `C:\Music\Anime` (invalid)

---

### Error: "MinIO connection failed"

**Problem:** MinIO credentials or endpoint incorrect

**Solution:**
1. Check `MINIO_ENDPOINT` (no `https://` prefix)
2. Verify access key and secret key from Coolify
3. Test connection:
   ```bash
   curl https://minio.yourdomain.com/minio/health/live
   ```

---

### Error: "Database connection failed"

**Problem:** Can't reach PostgreSQL

**Solution:**

**If using SSH tunnel:**
```bash
# In separate terminal:
ssh -L 5432:localhost:5432 root@YOUR_IP

# In .env:
DB_HOST=localhost
```

**If publicly accessible:**
```bash
# In .env:
DB_HOST=YOUR_HETZNER_IP
```

---

### Error: "permission denied for schema musicplayer"

**Problem:** Database user doesn't have permission

**Solution:**
Run in PostgreSQL:
```sql
GRANT USAGE ON SCHEMA musicplayer TO postgres;
GRANT INSERT ON musicplayer.tracks TO postgres;
```

---

### Warning: "Could not extract metadata"

**Not an error** - the script continues with:
- Title = filename
- Artist = "Unknown"
- Album = NULL

**Causes:**
- Corrupted MP3 file
- Missing ID3 tags
- Non-standard MP3 format

---

## 📝 Metadata Extraction

The script extracts:

| Field | Source | Fallback |
|-------|--------|----------|
| Title | ID3 `TIT2` tag | Filename |
| Artist | ID3 `TPE1` tag | "Unknown" |
| Album | ID3 `TALB` tag | NULL |
| Duration | MP3 audio length | NULL |
| File Size | File system | (always available) |
| Cover Art | ID3 `APIC` frame | NULL |

---

## 🧪 Testing the Upload

After running the script, verify the data:

### 1. Check MinIO

```bash
# List uploaded files
curl https://minio.yourdomain.com/anime-music/
```

Or visit the MinIO console: `https://minio-console.yourdomain.com`

### 2. Check Database

```sql
-- Connect to PostgreSQL
psql -h localhost -U postgres -d postgres

-- Count uploaded tracks
SELECT COUNT(*) FROM musicplayer.tracks;

-- View recent uploads
SELECT title, artist, album, created_at
FROM musicplayer.tracks
ORDER BY created_at DESC
LIMIT 10;
```

### 3. Check API

```bash
# Get all tracks via PostgREST
curl https://api.yourdomain.com/tracks
```

---

## 🔐 Security Notes

- ✅ `.env` file is in `.gitignore` (never committed)
- ✅ Use SSH tunnel for database access
- ✅ MinIO credentials should be unique (not defaults)
- ⚠️ MinIO bucket is public (read-only for streaming)

---

## 🚀 Advanced Usage

### Upload Only New Files

The script automatically skips duplicates, so just run it again:

```bash
python upload.py
```

### Upload from Multiple Folders

Update `.env` and run multiple times:

```bash
# First run
MUSIC_FOLDER=/path/to/anime python upload.py

# Second run
MUSIC_FOLDER=/path/to/ost python upload.py
```

### Batch Processing

For very large libraries (10,000+ files), consider splitting:

```bash
# Process 1000 files at a time (manual split)
python upload.py  # processes all files
```

The script already uses batching internally and commits to database after each file.

---

## 📦 Dependencies

- **minio** - S3-compatible storage client
- **psycopg2-binary** - PostgreSQL adapter
- **mutagen** - MP3 metadata extraction (better than eyed3)
- **Pillow** - Image processing for cover art
- **tqdm** - Progress bar
- **python-dotenv** - Environment variable management

---

## ✅ Next Steps

After uploading your music:

1. ✅ Verify data in database and MinIO
2. ✅ Test API endpoint: `GET /tracks`
3. ✅ Build the Flutter app
4. ✅ Start streaming on Android TV and Web!

---

**Questions?** Check the main README.md or the `/docs` folder.
