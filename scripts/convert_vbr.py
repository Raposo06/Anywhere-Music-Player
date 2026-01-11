#!/usr/bin/env python3
"""
VBR to CBR Converter for Anywhere Music Player

This script:
1. Scans your music folder for VBR-encoded MP3 files
2. Re-encodes them to CBR 320kbps for Windows/Android compatibility
3. Re-uploads converted files to MinIO
4. Updates the database with new file sizes

Requirements:
    - ffmpeg installed and in PATH
    - pip install mutagen tqdm python-dotenv minio psycopg2-binary

Usage:
    python convert_vbr.py                    # Dry run (shows what would be converted)
    python convert_vbr.py --convert          # Convert, backup originals, re-upload to MinIO
    python convert_vbr.py --convert --replace # Convert, replace originals, re-upload to MinIO
"""

import os
import sys
import subprocess
import shutil
import argparse
from pathlib import Path

try:
    from mutagen.mp3 import MP3
    from mutagen.id3 import ID3
    from tqdm import tqdm
    from dotenv import load_dotenv
    from minio import Minio
    from minio.error import S3Error
    import psycopg2
    from psycopg2 import sql
except ImportError as e:
    print(f"❌ Missing dependency: {e}")
    print("📦 Install with: pip install mutagen tqdm python-dotenv minio psycopg2-binary")
    sys.exit(1)

load_dotenv()

# Configuration from environment
MUSIC_FOLDER = os.getenv("MUSIC_FOLDER")
MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT")
MINIO_ACCESS_KEY = os.getenv("MINIO_ACCESS_KEY")
MINIO_SECRET_KEY = os.getenv("MINIO_SECRET_KEY")
MINIO_BUCKET = os.getenv("MINIO_BUCKET")
MINIO_SECURE = os.getenv("MINIO_SECURE", "true").lower() == "true"

DB_HOST = os.getenv("DB_HOST")
DB_PORT = os.getenv("DB_PORT")
DB_NAME = os.getenv("DB_NAME")
DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")
DB_SCHEMA = os.getenv("DB_SCHEMA")


def check_ffmpeg():
    """Check if ffmpeg is installed."""
    try:
        subprocess.run(
            ["ffmpeg", "-version"],
            capture_output=True,
            check=True
        )
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False


def cleanup_temp_files(folder):
    """Remove any leftover temp files from interrupted conversions."""
    temp_count = 0
    for root, _, files in os.walk(folder):
        for file in files:
            if file.endswith(".cbr_temp.mp3"):
                temp_path = os.path.join(root, file)
                try:
                    os.remove(temp_path)
                    temp_count += 1
                except OSError:
                    pass
    return temp_count


def is_vbr(file_path):
    """Check if an MP3 file is VBR encoded."""
    try:
        audio = MP3(file_path, ID3=ID3)
        if audio.info and hasattr(audio.info, 'bitrate_mode'):
            # bitrate_mode: 0=CBR, 1=VBR, 2=ABR
            return audio.info.bitrate_mode == 1
        return False
    except Exception:
        return False


def get_vbr_files(folder):
    """Find all VBR MP3 files in folder and subfolders."""
    vbr_files = []
    all_mp3s = []

    # Folders to skip (backup folders, temp files)
    skip_folders = {'_vbr_backups', '__pycache__', '.git'}

    for root, dirs, files in os.walk(folder):
        # Skip backup and system folders
        dirs[:] = [d for d in dirs if d not in skip_folders]

        for file in files:
            # Skip temp files from interrupted conversions
            if file.endswith(".cbr_temp.mp3"):
                continue
            if file.lower().endswith(".mp3"):
                all_mp3s.append(os.path.join(root, file))

    print(f"📂 Scanning {len(all_mp3s)} MP3 files for VBR encoding...")

    for file_path in tqdm(all_mp3s, desc="Checking", unit="file"):
        if is_vbr(file_path):
            vbr_files.append(file_path)

    return vbr_files


def convert_to_cbr(input_path, output_path, bitrate="320k"):
    """Convert a file to CBR using ffmpeg."""
    try:
        result = subprocess.run(
            [
                "ffmpeg", "-i", input_path,
                "-acodec", "libmp3lame",
                "-b:a", bitrate,
                "-y",  # Overwrite output
                "-loglevel", "error",
                output_path
            ],
            capture_output=True,
            text=True
        )

        if result.returncode != 0:
            return False, result.stderr
        return True, None

    except Exception as e:
        return False, str(e)


def initialize_minio():
    """Initialize MinIO client."""
    try:
        client = Minio(
            MINIO_ENDPOINT,
            access_key=MINIO_ACCESS_KEY,
            secret_key=MINIO_SECRET_KEY,
            secure=MINIO_SECURE
        )
        return client
    except Exception as e:
        print(f"❌ MinIO connection failed: {e}")
        return None


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
        return None


def upload_to_minio(minio_client, file_path, object_name):
    """Upload a file to MinIO, replacing existing."""
    try:
        minio_client.fput_object(
            MINIO_BUCKET,
            object_name,
            file_path,
            content_type="audio/mpeg",
        )
        return True
    except S3Error as e:
        print(f"⚠️  MinIO upload failed for {object_name}: {e}")
        return False


def update_database_filesize(db_conn, filename, new_size):
    """Update file size in database after conversion."""
    cursor = db_conn.cursor()
    try:
        query = sql.SQL("""
            UPDATE {schema}.tracks
            SET file_size_bytes = %s
            WHERE filename = %s
        """).format(schema=sql.Identifier(DB_SCHEMA))

        cursor.execute(query, (new_size, filename))
        db_conn.commit()
        return cursor.rowcount > 0
    except psycopg2.Error as e:
        db_conn.rollback()
        print(f"⚠️  Database update failed for {filename}: {e}")
        return False
    finally:
        cursor.close()


def main():
    parser = argparse.ArgumentParser(description="Convert VBR MP3s to CBR for maximum compatibility")
    parser.add_argument("--convert", action="store_true", help="Actually convert files (default is dry run)")
    parser.add_argument("--replace", action="store_true", help="Replace originals instead of backing up")
    parser.add_argument("--bitrate", default="320k", help="Target bitrate (default: 320k)")
    parser.add_argument("--folder", default=MUSIC_FOLDER, help="Music folder to scan")
    parser.add_argument("--skip-upload", action="store_true", help="Skip MinIO re-upload (local only)")
    args = parser.parse_args()

    print("🎵 VBR to CBR Converter")
    print("=" * 50)
    print("🎯 Target: Maximum compatibility (Windows, Android, Android TV)")
    print("=" * 50)

    if not args.folder or not os.path.exists(args.folder):
        print(f"❌ Music folder not found: {args.folder}")
        print("💡 Set MUSIC_FOLDER in .env or use --folder")
        sys.exit(1)

    # Clean up any temp files from previous interrupted runs
    temp_cleaned = cleanup_temp_files(args.folder)
    if temp_cleaned > 0:
        print(f"🧹 Cleaned up {temp_cleaned} temp file(s) from previous run")

    if args.convert and not check_ffmpeg():
        print("❌ ffmpeg not found. Please install ffmpeg:")
        print("   Ubuntu/Debian: sudo apt install ffmpeg")
        print("   macOS: brew install ffmpeg")
        print("   Windows: Download from https://ffmpeg.org/download.html")
        sys.exit(1)

    # Find VBR files
    vbr_files = get_vbr_files(args.folder)

    if not vbr_files:
        print("\n✅ No VBR files found! Your library is already fully compatible.")
        sys.exit(0)

    print(f"\n📊 Found {len(vbr_files)} VBR file(s) that need conversion")

    if not args.convert:
        # Dry run - just list files
        print("\n📋 VBR files that would be converted:")
        for f in vbr_files[:20]:
            print(f"   - {Path(f).name}")
        if len(vbr_files) > 20:
            print(f"   ... and {len(vbr_files) - 20} more")

        print(f"\n💡 To convert these files, run:")
        print(f"   python convert_vbr.py --convert          # Backup originals")
        print(f"   python convert_vbr.py --convert --replace # Replace originals")
        sys.exit(0)

    # Initialize connections for upload
    minio_client = None
    db_conn = None

    if not args.skip_upload:
        print("\n🔌 Connecting to MinIO...")
        minio_client = initialize_minio()
        if not minio_client:
            print("⚠️  Could not connect to MinIO. Use --skip-upload to convert locally only.")
            sys.exit(1)
        print("✅ MinIO connected")

        print("🔌 Connecting to PostgreSQL...")
        db_conn = initialize_database()
        if not db_conn:
            print("⚠️  Could not connect to database. Use --skip-upload to convert locally only.")
            sys.exit(1)
        print("✅ Database connected")

    # Create backup folder if not replacing
    backup_folder = None
    if not args.replace:
        backup_folder = Path(args.folder) / "_vbr_backups"
        backup_folder.mkdir(exist_ok=True)
        print(f"\n📁 Backing up originals to: {backup_folder}")

    # Convert files
    print(f"\n🔄 Converting {len(vbr_files)} files to CBR {args.bitrate}...\n")

    converted = 0
    uploaded = 0
    failed = 0
    failed_files = []

    for i, file_path in enumerate(tqdm(vbr_files, desc="Converting", unit="file")):
        file_path = Path(file_path)
        filename = file_path.name
        temp_output = file_path.with_suffix(".cbr_temp.mp3")

        try:
            # Convert to temp file
            success, error = convert_to_cbr(str(file_path), str(temp_output), args.bitrate)

            if success and temp_output.exists():
                new_size = temp_output.stat().st_size

                if not args.replace and backup_folder:
                    # Backup original
                    backup_path = backup_folder / filename
                    counter = 1
                    while backup_path.exists():
                        backup_path = backup_folder / f"{file_path.stem}_{counter}{file_path.suffix}"
                        counter += 1
                    shutil.move(str(file_path), str(backup_path))
                else:
                    # Remove original
                    file_path.unlink()

                # Rename temp to original name
                temp_output.rename(file_path)
                converted += 1

                # Re-upload to MinIO and update database
                if minio_client and db_conn:
                    if upload_to_minio(minio_client, str(file_path), filename):
                        uploaded += 1
                        update_database_filesize(db_conn, filename, new_size)
            else:
                failed += 1
                failed_files.append((str(file_path), error or "Conversion failed"))
                if temp_output.exists():
                    temp_output.unlink()

        except Exception as e:
            failed += 1
            failed_files.append((str(file_path), str(e)))
            # Clean up temp file if it exists
            if temp_output.exists():
                try:
                    temp_output.unlink()
                except:
                    pass
            # Print error but continue with next file
            tqdm.write(f"⚠️  Error on {filename}: {str(e)[:50]}")

    # Close database connection
    if db_conn:
        db_conn.close()

    # Summary
    print("\n" + "=" * 50)
    print("📊 Conversion Summary:")
    print(f"   ✅ Converted: {converted}")
    if not args.skip_upload:
        print(f"   ☁️  Re-uploaded to MinIO: {uploaded}")
    print(f"   ❌ Failed: {failed}")
    if backup_folder and not args.replace:
        print(f"   📁 Backups saved to: {backup_folder}")
    print("=" * 50)

    if failed_files:
        print("\n❌ Failed files:")
        for path, error in failed_files[:10]:
            print(f"   - {Path(path).name}")
            if error:
                print(f"     Error: {error[:100]}")
        if len(failed_files) > 10:
            print(f"   ... and {len(failed_files) - 10} more")

        # Save failed files log
        log_file = Path(args.folder) / "convert_failed.log"
        with open(log_file, "w") as f:
            f.write("Failed conversions log\n")
            f.write("=" * 50 + "\n\n")
            for path, error in failed_files:
                f.write(f"File: {path}\n")
                f.write(f"Error: {error}\n\n")
        print(f"\n   📄 Full log saved to: {log_file}")

    if converted > 0:
        print(f"\n🎉 Successfully converted {converted} file(s) to CBR {args.bitrate}!")
        print("\n✅ Your library is now compatible with:")
        print("   • Windows (Media Foundation)")
        print("   • Android Phone")
        print("   • Android TV")

        if args.skip_upload:
            print("\n💡 Don't forget to re-upload converted files to MinIO!")


if __name__ == "__main__":
    main()
