import os
import sys
from pathlib import Path
from io import BytesIO

try:
    from minio import Minio
    from minio.error import S3Error
    import psycopg2
    from psycopg2 import sql
    from mutagen import File as MutagenFile
    from mutagen.id3 import APIC
    from mutagen.flac import FLAC
    from tqdm import tqdm
    from dotenv import load_dotenv
    from PIL import Image
except ImportError as e:
    print(f"❌ Missing dependency: {e}")
    print("📦 Install dependencies with: pip install -r requirements.txt")
    sys.exit(1)

# Load environment variables from .env file
load_dotenv()

# ============================================================================
# Configuration
# ============================================================================

MUSIC_FOLDER = os.getenv("MUSIC_FOLDER")
MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT")
MINIO_ACCESS_KEY = os.getenv("MINIO_ACCESS_KEY")
MINIO_SECRET_KEY = os.getenv("MINIO_SECRET_KEY")
MINIO_BUCKET = os.getenv("MINIO_BUCKET")
MINIO_SECURE = os.getenv("MINIO_SECURE", "true").lower() == "true"

DB_HOST = os.getenv("DB_HOST")
DB_PORT = int(os.getenv("DB_PORT"))
DB_NAME = os.getenv("DB_NAME")
DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")
DB_SCHEMA = os.getenv("DB_SCHEMA")

# Supported audio file extensions
AUDIO_EXTENSIONS = {'.mp3', '.flac', '.m4a', '.ogg', '.opus', '.wav', '.aac', '.wma'}

# Map file extension to MIME content type
CONTENT_TYPE_MAP = {
    '.mp3': 'audio/mpeg',
    '.flac': 'audio/flac',
    '.m4a': 'audio/mp4',
    '.aac': 'audio/aac',
    '.ogg': 'audio/ogg',
    '.opus': 'audio/opus',
    '.wav': 'audio/wav',
    '.wma': 'audio/x-ms-wma',
}


# ============================================================================
# Database & MinIO Setup
# ============================================================================

def initialize_minio():
    """Initialize MinIO client."""
    try:
        client = Minio(
            MINIO_ENDPOINT,
            access_key=MINIO_ACCESS_KEY,
            secret_key=MINIO_SECRET_KEY,
            secure=MINIO_SECURE
        )
        if not client.bucket_exists(MINIO_BUCKET):
            print(f"📦 Creating bucket: {MINIO_BUCKET}")
            client.make_bucket(MINIO_BUCKET)
        return client
    except S3Error as e:
        print(f"❌ MinIO connection failed: {e}")
        sys.exit(1)


def initialize_database():
    """Initialize PostgreSQL connection with Schema set."""
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            # This line fixes the 'relation does not exist' error
            options=f"-c search_path={DB_SCHEMA}"
        )
        # Enable autocommit or handle manually to ensure immediate saves
        conn.autocommit = False
        return conn
    except psycopg2.Error as e:
        print(f"❌ Database connection failed: {e}")
        sys.exit(1)


def create_table_if_not_exists(conn):
    """Creates the tracks table if it is missing."""
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                           CREATE TABLE IF NOT EXISTS tracks
                           (
                               id
                               SERIAL
                               PRIMARY
                               KEY,
                               title
                               TEXT,
                               filename
                               TEXT
                               UNIQUE
                               NOT
                               NULL,
                               stream_url
                               TEXT
                               NOT
                               NULL,
                               cover_art_url
                               TEXT,
                               folder_path
                               TEXT,
                               duration_seconds
                               INTEGER,
                               file_size_bytes
                               BIGINT,
                               created_at
                               TIMESTAMP
                               DEFAULT
                               CURRENT_TIMESTAMP
                           );
                           """)
            conn.commit()
    except Exception as e:
        print(f"❌ Failed to create table: {e}")
        sys.exit(1)


# ============================================================================
# Logic: Metadata & Sanitization
# ============================================================================

def get_relative_path_key(file_path, base_folder):
    """
    Generates a MinIO-safe object key.
    Fixes 400 Errors, Fake Slashes, and Emojis.
    """
    try:
        # Preserve folder structure (Artist/Album/Song.mp3)
        rel = Path(file_path).relative_to(base_folder)
        path_str = str(rel).replace("\\", "/")
    except ValueError:
        path_str = Path(file_path).name

    # --- SPECIFIC REPLACEMENTS (For aesthetics/safety) ---
    path_str = path_str.replace("#", "No.")
    path_str = path_str.replace("&", "and")
    path_str = path_str.replace("：", "-")
    path_str = path_str.replace(":", "-")
    path_str = path_str.replace("?", "")
    path_str = path_str.replace(";", "")

    # Fix Fake Slash
    path_str = path_str.replace("\u29f8", "-")
    path_str = path_str.replace("⧸", "-")

    # --- THE NUCLEAR FIX (Removes Emojis) ---
    # This keeps standard text and accents (ã, é) but drops 👈, 🔥, etc.
    try:
        path_str = path_str.encode('latin-1', 'ignore').decode('latin-1')
    except Exception:
        pass  # Safety net
    # ----------------------------------------

    # Clean up double spaces created by removing emojis
    path_str = path_str.replace("  ", " ").strip()

    return path_str


def extract_metadata(file_path):
    """Extract title and duration from any supported audio format."""
    fallback = {
        "title": Path(file_path).stem,
        "duration_seconds": 0,
        "file_size_bytes": os.path.getsize(file_path)
    }
    try:
        audio = MutagenFile(file_path)
        if audio is None:
            return fallback

        title = None
        if audio.tags:
            # ID3 (MP3, some WAV)
            if hasattr(audio.tags, 'getall'):
                tit2 = audio.tags.getall('TIT2')
                if tit2:
                    title = str(tit2[0])
            # Vorbis comments (FLAC, OGG, Opus)
            if not title and 'title' in audio.tags:
                val = audio.tags['title']
                title = val[0] if isinstance(val, list) else str(val)
            # MP4/M4A
            if not title and '\xa9nam' in audio.tags:
                title = audio.tags['\xa9nam'][0]

        duration = int(audio.info.length) if audio.info else 0
        return {
            "title": title or Path(file_path).stem,
            "duration_seconds": duration,
            "file_size_bytes": os.path.getsize(file_path)
        }
    except Exception:
        return fallback


def extract_cover_art(file_path):
    """Extract embedded cover art from any supported audio format."""
    try:
        audio = MutagenFile(file_path)
        if audio is None:
            return None

        image_data = None

        # ID3 tags (MP3, some WAV)
        if hasattr(audio, 'tags') and audio.tags:
            for tag in audio.tags.values():
                if isinstance(tag, APIC):
                    image_data = tag.data
                    break

        # FLAC embedded pictures
        if image_data is None and isinstance(audio, FLAC) and audio.pictures:
            image_data = audio.pictures[0].data

        # MP4/M4A cover art
        if image_data is None and hasattr(audio, 'tags') and audio.tags:
            covr = audio.tags.get('covr')
            if covr:
                image_data = bytes(covr[0])

        if image_data is None:
            return None

        image = Image.open(BytesIO(image_data))
        if image.width > 800 or image.height > 800:
            image.thumbnail((800, 800))
        output = BytesIO()
        image.convert("RGB").save(output, format="JPEG", quality=85)
        output.seek(0)
        return output
    except:
        return None


# ============================================================================
# Main Loop
# ============================================================================

def main():
    print("🎵 Anywhere Music Player - Audio Uploader")
    print("=" * 50)

    if not MUSIC_FOLDER or not os.path.exists(MUSIC_FOLDER):
        print(f"❌ Music folder not found: {MUSIC_FOLDER}")
        sys.exit(1)

    minio_client = initialize_minio()
    print("✅ MinIO connected")

    db_conn = initialize_database()
    create_table_if_not_exists(db_conn)
    print("✅ Database connected")

    audio_files = []
    for root, _, files in os.walk(MUSIC_FOLDER):
        for file in files:
            if Path(file).suffix.lower() in AUDIO_EXTENSIONS:
                audio_files.append(os.path.join(root, file))

    print(f"🚀 Processing {len(audio_files)} files...")

    uploaded = 0
    skipped = 0
    failed = 0

    # REMOVED outer 'with db_conn:' to allow manual commits per song
    with db_conn.cursor() as cursor:
        # --- OPTIMIZATION: Load existing files into memory ---
        print("📋 Fetching existing file list from database...")
        cursor.execute("SELECT filename FROM tracks")
        existing_files = {row[0] for row in cursor.fetchall()}
        print(f"✅ Loaded {len(existing_files)} existing tracks into memory.")
        # --- OPTIMIZATION END ---

        for file_path in tqdm(audio_files, desc="Uploading", unit="song"):
            try:
                # 1. Generate Safe Key
                object_key = get_relative_path_key(file_path, MUSIC_FOLDER)

                # 2. Check if exact path exists in DB
                if object_key in existing_files:
                    skipped += 1
                    continue

                # 3. Upload Audio
                try:
                    ext = Path(file_path).suffix.lower()
                    content_type = CONTENT_TYPE_MAP.get(ext, 'application/octet-stream')
                    minio_client.fput_object(
                        MINIO_BUCKET, object_key, file_path, content_type=content_type
                    )
                    stream_url = f"https://{MINIO_ENDPOINT}/{MINIO_BUCKET}/{object_key}"
                except S3Error as e:
                    tqdm.write(f"❌ MinIO Error: {e}")
                    failed += 1
                    continue

                # 4. Upload Cover Art
                cover_data = extract_cover_art(file_path)
                cover_url = None
                if cover_data:
                    cover_key = f"covers/{Path(object_key).stem}_{os.path.getsize(file_path)}.jpg"
                    try:
                        minio_client.put_object(
                            MINIO_BUCKET, cover_key, cover_data,
                            length=cover_data.getbuffer().nbytes,
                            content_type="image/jpeg"
                        )
                        cover_url = f"https://{MINIO_ENDPOINT}/{MINIO_BUCKET}/{cover_key}"
                    except:
                        pass

                # 5. Insert to DB
                meta = extract_metadata(file_path)
                # Get folder path (empty string for root-level files)
                parent_path = Path(object_key).parent.as_posix()
                folder_path_db = "" if parent_path == "." else parent_path

                cursor.execute("""
                               INSERT INTO tracks
                               (title, filename, stream_url, cover_art_url, folder_path, duration_seconds,
                                file_size_bytes)
                               VALUES (%s, %s, %s, %s, %s, %s, %s) ON CONFLICT (filename) DO NOTHING
                               """, (
                                   meta['title'], object_key, stream_url, cover_url,
                                   folder_path_db, meta['duration_seconds'], meta['file_size_bytes']
                               ))

                # --- CRITICAL FIX: Commit immediately after each insert ---
                db_conn.commit()

                uploaded += 1

                # Add to cache to prevent re-upload if duplicates exist locally
                existing_files.add(object_key)

            except Exception as e:
                # Rollback current transaction if error prevents consistency
                db_conn.rollback()
                tqdm.write(f"❌ Unexpected Error on {Path(file_path).name}: {e}")
                failed += 1

    print("\n" + "=" * 50)
    print(f"📊 Summary: ✅ {uploaded} Uploaded | ⏭️ {skipped} Skipped | ❌ {failed} Failed")
    print("=" * 50)
    db_conn.close()


if __name__ == "__main__":
    main()