import os
import sys
from pathlib import Path

try:
    from minio import Minio
    from minio.error import S3Error
    from tqdm import tqdm
    from dotenv import load_dotenv
except ImportError as e:
    print(f"Missing dependency: {e}")
    print("Install dependencies with: pip install -r requirements.txt")
    sys.exit(1)

load_dotenv()

MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT")
MINIO_ACCESS_KEY = os.getenv("MINIO_ACCESS_KEY")
MINIO_SECRET_KEY = os.getenv("MINIO_SECRET_KEY")
MINIO_BUCKET = os.getenv("MINIO_BUCKET")
MINIO_SECURE = os.getenv("MINIO_SECURE", "true").lower() == "true"

DOWNLOAD_FOLDER = os.getenv("DOWNLOAD_FOLDER", os.path.join(os.getcwd(), "downloads"))

AUDIO_EXTENSIONS = {'.mp3', '.flac', '.m4a', '.ogg', '.opus', '.wav', '.aac', '.wma'}


def initialize_minio():
    try:
        client = Minio(
            MINIO_ENDPOINT,
            access_key=MINIO_ACCESS_KEY,
            secret_key=MINIO_SECRET_KEY,
            secure=MINIO_SECURE
        )
        if not client.bucket_exists(MINIO_BUCKET):
            print(f"Bucket not found: {MINIO_BUCKET}")
            sys.exit(1)
        return client
    except S3Error as e:
        print(f"MinIO connection failed: {e}")
        sys.exit(1)


def main():
    print("Anywhere Music Player - Song Downloader")
    print("=" * 50)

    minio_client = initialize_minio()
    print(f"MinIO connected ({MINIO_ENDPOINT})")

    # List all objects in the bucket
    print("Scanning bucket...")
    objects = []
    for obj in minio_client.list_objects(MINIO_BUCKET, recursive=True):
        if Path(obj.object_name).suffix.lower() in AUDIO_EXTENSIONS:
            objects.append(obj)

    print(f"Found {len(objects)} audio files")

    os.makedirs(DOWNLOAD_FOLDER, exist_ok=True)

    downloaded = 0
    skipped = 0
    failed = 0

    for obj in tqdm(objects, desc="Downloading", unit="song"):
        try:
            local_path = os.path.join(DOWNLOAD_FOLDER, obj.object_name)

            # Skip if file already exists with matching size
            if os.path.exists(local_path) and os.path.getsize(local_path) == obj.size:
                skipped += 1
                continue

            # Create parent directories
            os.makedirs(os.path.dirname(local_path), exist_ok=True)

            minio_client.fget_object(MINIO_BUCKET, obj.object_name, local_path)
            downloaded += 1

        except Exception as e:
            tqdm.write(f"Failed: {obj.object_name} - {e}")
            failed += 1

    print("\n" + "=" * 50)
    print(f"Summary: {downloaded} Downloaded | {skipped} Skipped | {failed} Failed")
    print(f"Location: {DOWNLOAD_FOLDER}")
    print("=" * 50)


if __name__ == "__main__":
    main()
