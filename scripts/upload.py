import os
import sys
from pathlib import Path
from io import BytesIO

try:
    from minio import Minio
    import psycopg2
    from mutagen.mp3 import MP3
    from mutagen.id3 import ID3, APIC
    from tqdm import tqdm
    from dotenv import load_dotenv
    from PIL import Image
except ImportError:
    print("❌ Dependencies missing. Run: pip install minio psycopg2-binary mutagen tqdm python-dotenv Pillow")
    sys.exit(1)

load_dotenv()

# Configuration
MUSIC_FOLDER = os.getenv("MUSIC_FOLDER")
MINIO_BUCKET = os.getenv("MINIO_BUCKET")

# DB Config
DB_SCHEMA = os.getenv("DB_SCHEMA", "public")  # Default to public if not set


def get_db_connection():
    # We add the 'options' parameter to force the connection to use your specific schema
    return psycopg2.connect(
        host=os.getenv("DB_HOST"),
        port=os.getenv("DB_PORT"),
        dbname=os.getenv("DB_NAME"),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
        options=f"-c search_path={DB_SCHEMA}"
    )


# Create table in the correct schema if it's missing
def create_table_if_not_exists(conn):
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
            print(f"✅ Database table 'tracks' checked in schema '{DB_SCHEMA}'.")
    except Exception as e:
        print(f"❌ Failed to create/check table: {e}")
        sys.exit(1)


def extract_metadata(file_path):
    try:
        audio = MP3(file_path, ID3=ID3)
        title = str(audio.get("TIT2", Path(file_path).stem))
        duration = int(audio.info.length) if audio.info else 0
        return {
            "title": title,
            "duration": duration,
            "size": os.path.getsize(file_path)
        }
    except Exception:
        return {"title": Path(file_path).stem, "duration": 0, "size": 0}


def extract_cover_art(file_path):
    try:
        audio = ID3(file_path)
        for tag in audio.values():
            if isinstance(tag, APIC):
                image = Image.open(BytesIO(tag.data))
                if image.width > 800 or image.height > 800:
                    image.thumbnail((800, 800))
                output = BytesIO()
                image.convert("RGB").save(output, format="JPEG", quality=85)
                output.seek(0)
                return output
        return None
    except:
        return None


def get_relative_path_key(file_path, base_folder):
    try:
        rel = Path(file_path).relative_to(base_folder)
        return str(rel).replace("\\", "/")
    except ValueError:
        return Path(file_path).name


def upload_to_minio(client, file_path, object_name):
    try:
        client.fput_object(
            MINIO_BUCKET,
            object_name,
            file_path,
            content_type='audio/mpeg'
        )
        return f"/{MINIO_BUCKET}/{object_name}"
    except Exception as e:
        print(f"\n❌ Upload failed for {object_name}: {e}")
        return None


def main():
    if not MUSIC_FOLDER or not os.path.exists(MUSIC_FOLDER):
        print(f"❌ MUSIC_FOLDER not found: {MUSIC_FOLDER}")
        sys.exit(1)

    # Init MinIO
    try:
        minio_client = Minio(
            os.getenv("MINIO_ENDPOINT"),
            access_key=os.getenv("MINIO_ACCESS_KEY"),
            secret_key=os.getenv("MINIO_SECRET_KEY"),
            secure=str(os.getenv("MINIO_SECURE", "true")).lower() == "true"
        )
        if not minio_client.bucket_exists(MINIO_BUCKET):
            minio_client.make_bucket(MINIO_BUCKET)
            print(f"📦 Created bucket: {MINIO_BUCKET}")
    except Exception as e:
        print(f"❌ MinIO Connection Error: {e}")
        sys.exit(1)

    # Init DB
    try:
        conn = get_db_connection()
        create_table_if_not_exists(conn)
    except Exception as e:
        print(f"❌ DB Connection Error: {e}")
        sys.exit(1)

    mp3_files = []
    for root, _, files in os.walk(MUSIC_FOLDER):
        for file in files:
            if file.lower().endswith(".mp3"):
                mp3_files.append(os.path.join(root, file))

    print(f"🚀 Preparing to upload {len(mp3_files)} files...")

    uploaded = 0
    skipped = 0

    with conn:
        with conn.cursor() as cursor:
            for file_path in tqdm(mp3_files, unit="song"):

                object_key = get_relative_path_key(file_path, MUSIC_FOLDER)

                # Check DB (Now looks in musicplayer.tracks)
                cursor.execute(
                    "SELECT 1 FROM tracks WHERE filename = %s LIMIT 1",
                    (object_key,)
                )
                if cursor.fetchone():
                    skipped += 1
                    continue

                # Upload to MinIO
                stream_url = upload_to_minio(minio_client, file_path, object_key)
                if not stream_url:
                    continue

                # Cover Art
                cover_data = extract_cover_art(file_path)
                cover_url = None
                if cover_data:
                    cover_key = f"covers/{Path(object_key).stem}_{os.path.getsize(file_path)}.jpg"
                    try:
                        minio_client.put_object(
                            MINIO_BUCKET,
                            cover_key,
                            cover_data,
                            length=cover_data.getbuffer().nbytes,
                            content_type="image/jpeg"
                        )
                        cover_url = f"/{MINIO_BUCKET}/{cover_key}"
                    except Exception as e:
                        pass

                meta = extract_metadata(file_path)

                # Insert into DB
                try:
                    cursor.execute("""
                                   INSERT INTO tracks
                                   (title, filename, stream_url, cover_art_url, duration_seconds, file_size_bytes)
                                   VALUES (%s, %s, %s, %s, %s, %s) ON CONFLICT (filename) DO NOTHING
                                   """, (
                                       meta['title'],
                                       object_key,
                                       stream_url,
                                       cover_url,
                                       meta['duration'],
                                       meta['size']
                                   ))
                    uploaded += 1
                except Exception as e:
                    print(f"❌ DB Insert Error: {e}")

    print("\n" + "=" * 30)
    print(f"✅ Uploaded: {uploaded}")
    print(f"⏭️  Skipped (Already in DB): {skipped}")
    print("=" * 30)
    conn.close()


if __name__ == "__main__":
    main()