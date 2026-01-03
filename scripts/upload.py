#!/usr/bin/env python3
"""
Anywhere Music Player - MP3 Uploader Script

This script:
1. Scans a folder for MP3 files
2. Extracts metadata (title, artist, album, duration)
3. Extracts album cover art (if available)
4. Uploads MP3 files to MinIO
5. Uploads cover art images to MinIO
6. Inserts metadata into PostgreSQL (musicplayer.tracks table)
7. Shows progress bar for large libraries
8. Skips duplicate files (based on filename)

Usage:
    python upload.py

Configuration:
    Edit .env file with your credentials and paths
"""

import os
import sys
from pathlib import Path
from io import BytesIO

# Third-party imports
try:
    from minio import Minio
    from minio.error import S3Error
    import psycopg2
    from psycopg2 import sql
    from mutagen.mp3 import MP3
    from mutagen.id3 import ID3, APIC
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
# Configuration from Environment Variables
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


# ============================================================================
# Validation
# ============================================================================

def validate_config():
    """Validate that all required configuration is present."""
    missing = []

    if not MINIO_ACCESS_KEY:
        missing.append("MINIO_ACCESS_KEY")
    if not MINIO_SECRET_KEY:
        missing.append("MINIO_SECRET_KEY")
    if not DB_PASSWORD:
        missing.append("DB_PASSWORD")

    if missing:
        print("❌ Missing required environment variables:")
        for var in missing:
            print(f"   - {var}")
        print("\n💡 Create a .env file with these variables (see .env.example)")
        sys.exit(1)

    if not os.path.exists(MUSIC_FOLDER):
        print(f"❌ Music folder not found: {MUSIC_FOLDER}")
        print("💡 Update MUSIC_FOLDER in your .env file")
        sys.exit(1)


# ============================================================================
# MinIO Client
# ============================================================================

def initialize_minio():
    """Initialize MinIO client and ensure bucket exists."""
    try:
        client = Minio(
            MINIO_ENDPOINT,
            access_key=MINIO_ACCESS_KEY,
            secret_key=MINIO_SECRET_KEY,
            secure=MINIO_SECURE
        )

        # Check if bucket exists, create if not
        if not client.bucket_exists(MINIO_BUCKET):
            print(f"📦 Creating bucket: {MINIO_BUCKET}")
            client.make_bucket(MINIO_BUCKET)
            print(f"✅ Bucket created")

        return client

    except S3Error as e:
        print(f"❌ MinIO connection failed: {e}")
        sys.exit(1)


# ============================================================================
# PostgreSQL Connection
# ============================================================================

def initialize_database():
    """Initialize PostgreSQL connection."""
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD
        )
        return conn

    except psycopg2.Error as e:
        print(f"❌ Database connection failed: {e}")
        sys.exit(1)


# ============================================================================
# Metadata Extraction
# ============================================================================

def extract_metadata(file_path):
    """
    Extract metadata from MP3 file.

    Returns:
        dict: Metadata including title, duration, file_size
    """
    try:
        audio = MP3(file_path, ID3=ID3)

        # Extract title from ID3 tags (or use filename)
        title = str(audio.get("TIT2", Path(file_path).stem))

        # Get duration in seconds
        duration = int(audio.info.length) if audio.info else None

        # Get file size in bytes
        file_size = os.path.getsize(file_path)

        return {
            "title": title,
            "duration_seconds": duration,
            "file_size_bytes": file_size
        }

    except Exception as e:
        print(f"⚠️  Warning: Could not extract metadata from {Path(file_path).name}: {e}")
        return {
            "title": Path(file_path).stem,
            "duration_seconds": None,
            "file_size_bytes": os.path.getsize(file_path)
        }


def extract_cover_art(file_path):
    """
    Extract album cover art from MP3 file.

    Returns:
        BytesIO: Cover art as JPEG image, or None if not found
    """
    try:
        audio = ID3(file_path)

        # Look for embedded artwork (APIC frame)
        for tag in audio.values():
            if isinstance(tag, APIC):
                # Convert to JPEG if needed
                image = Image.open(BytesIO(tag.data))

                # Resize if too large (max 800x800)
                if image.width > 800 or image.height > 800:
                    image.thumbnail((800, 800), Image.Resampling.LANCZOS)

                # Convert to JPEG
                output = BytesIO()
                image.convert("RGB").save(output, format="JPEG", quality=85)
                output.seek(0)
                return output

        return None

    except Exception:
        # No cover art found or error reading
        return None


# ============================================================================
# Upload Functions
# ============================================================================

def upload_to_minio(minio_client, file_path, object_name):
    """Upload a file to MinIO."""
    try:
        minio_client.fput_object(
            MINIO_BUCKET,
            object_name,
            file_path,
        )
        return f"https://{MINIO_ENDPOINT}/{MINIO_BUCKET}/{object_name}"

    except S3Error as e:
        print(f"⚠️  MinIO upload failed for {object_name}: {e}")
        return None


def upload_cover_art(minio_client, cover_art_data, filename):
    """Upload cover art image to MinIO."""
    try:
        object_name = f"covers/{Path(filename).stem}.jpg"

        minio_client.put_object(
            MINIO_BUCKET,
            object_name,
            cover_art_data,
            length=cover_art_data.getbuffer().nbytes,
            content_type="image/jpeg"
        )

        return f"https://{MINIO_ENDPOINT}/{MINIO_BUCKET}/{object_name}"

    except S3Error as e:
        print(f"⚠️  Cover art upload failed: {e}")
        return None


def insert_track(db_conn, metadata, filename, stream_url, cover_art_url, folder_path):
    """Insert track metadata into PostgreSQL."""
    cursor = db_conn.cursor()

    try:
        query = sql.SQL("""
            INSERT INTO {schema}.tracks
            (title, filename, stream_url, cover_art_url, folder_path, duration_seconds, file_size_bytes)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (filename) DO NOTHING
            RETURNING id
        """).format(schema=sql.Identifier(DB_SCHEMA))

        cursor.execute(query, (
            metadata["title"],
            filename,
            stream_url,
            cover_art_url,
            folder_path,
            metadata["duration_seconds"],
            metadata["file_size_bytes"]
        ))

        result = cursor.fetchone()
        db_conn.commit()

        return result is not None  # True if inserted, False if duplicate

    except psycopg2.Error as e:
        db_conn.rollback()
        print(f"⚠️  Database insert failed for {filename}: {e}")
        return False

    finally:
        cursor.close()


def file_exists_in_db(db_conn, filename):
    """
    Check if a file already exists in the database.

    Returns:
        bool: True if file exists, False otherwise
    """
    cursor = db_conn.cursor()

    try:
        query = sql.SQL("""
            SELECT 1 FROM {schema}.tracks WHERE filename = %s LIMIT 1
        """).format(schema=sql.Identifier(DB_SCHEMA))

        cursor.execute(query, (filename,))
        return cursor.fetchone() is not None

    finally:
        cursor.close()


# ============================================================================
# Main Upload Process
# ============================================================================

def get_relative_folder_path(file_path, base_folder):
    """
    Extract relative folder path from base folder.
    Files in the root get the base folder name.

    Examples:
        file_path: /home/user/Music/Animes/song.mp3
        base_folder: /home/user/Music/Animes
        returns: "Animes"

        file_path: /home/user/Music/Animes/Naruto/opening1.mp3
        base_folder: /home/user/Music/Animes
        returns: "Naruto"

        file_path: /home/user/Music/Animes/Tekken/Tekken 2/track1.mp3
        base_folder: /home/user/Music/Animes
        returns: "Tekken/Tekken 2"
    """
    file_path = Path(file_path).resolve()
    base_folder = Path(base_folder).resolve()

    # Get the directory containing the MP3 file
    file_dir = file_path.parent

    # Get relative path from base folder
    try:
        relative_path = file_dir.relative_to(base_folder)
        # If file is in root (.), use the base folder name
        if str(relative_path) == '.':
            return base_folder.name
        return str(relative_path)
    except ValueError:
        # File is not under base_folder
        return None


def find_mp3_files(folder):
    """Find all MP3 files in folder and subfolders."""
    mp3_files = []
    for root, _, files in os.walk(folder):
        for file in files:
            if file.lower().endswith(".mp3"):
                mp3_files.append(os.path.join(root, file))
    return mp3_files


def main():
    """Main upload process."""
    print("🎵 Anywhere Music Player - MP3 Uploader")
    print("=" * 50)

    # Validate configuration
    validate_config()

    # Initialize connections
    print("🔌 Connecting to MinIO...")
    minio_client = initialize_minio()
    print("✅ MinIO connected")

    print("🔌 Connecting to PostgreSQL...")
    db_conn = initialize_database()
    print("✅ Database connected")

    # Find MP3 files
    print(f"\n📂 Scanning folder: {MUSIC_FOLDER}")
    mp3_files = find_mp3_files(MUSIC_FOLDER)

    if not mp3_files:
        print("❌ No MP3 files found")
        sys.exit(0)

    print(f"📊 Found {len(mp3_files)} MP3 file(s)")

    # Process files with progress bar
    uploaded = 0
    skipped = 0
    failed = 0

    print("\n⬆️  Uploading files...\n")

    for file_path in tqdm(mp3_files, desc="Progress", unit="file"):
        filename = Path(file_path).name

        try:
            # Check if file already exists in database (skip MinIO upload if duplicate)
            if file_exists_in_db(db_conn, filename):
                skipped += 1
                continue

            # Extract metadata
            metadata = extract_metadata(file_path)

            # Extract folder path
            folder_path = get_relative_folder_path(file_path, MUSIC_FOLDER)

            # Upload MP3 to MinIO
            stream_url = upload_to_minio(minio_client, file_path, filename)
            if not stream_url:
                failed += 1
                continue

            # Extract and upload cover art
            cover_art = extract_cover_art(file_path)
            cover_art_url = None
            if cover_art:
                cover_art_url = upload_cover_art(minio_client, cover_art, filename)

            # Insert into database
            inserted = insert_track(db_conn, metadata, filename, stream_url, cover_art_url, folder_path)

            if inserted:
                uploaded += 1
            else:
                # This shouldn't happen since we checked above, but just in case
                skipped += 1

        except Exception as e:
            print(f"\n❌ Error processing {filename}: {e}")
            failed += 1

    # Close database connection
    db_conn.close()

    # Summary
    print("\n" + "=" * 50)
    print("📊 Upload Summary:")
    print(f"   ✅ Uploaded: {uploaded}")
    print(f"   ⏭️  Skipped (duplicates): {skipped}")
    print(f"   ❌ Failed: {failed}")
    print("=" * 50)

    if uploaded > 0:
        print(f"\n🎉 Success! {uploaded} track(s) uploaded to your music library.")

    print("\n💡 Next steps:")
    print("   1. Verify tracks at: https://api.YOUR_DOMAIN/tracks")
    print("   2. Build the Flutter app to start streaming!")


if __name__ == "__main__":
    main()
