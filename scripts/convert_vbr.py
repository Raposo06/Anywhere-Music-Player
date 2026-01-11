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
except ImportError as e:
    print(f"❌ Missing dependency: {e}")
    sys.exit(1)

load_dotenv()
MUSIC_FOLDER = os.getenv("MUSIC_FOLDER")


def check_ffmpeg():
    try:
        subprocess.run(["ffmpeg", "-version"], capture_output=True, check=True)
        return True
    except:
        return False


def is_vbr(file_path):
    try:
        audio = MP3(file_path, ID3=ID3)
        if audio.info and hasattr(audio.info, 'bitrate_mode'):
            return audio.info.bitrate_mode == 1  # 1 is VBR
        return False
    except Exception:
        return False


def get_vbr_files(folder):
    vbr_files = []
    all_mp3s = []
    skip_folders = {'_vbr_backups', '__pycache__', '.git', '$RECYCLE.BIN', 'System Volume Information'}

    for root, dirs, files in os.walk(folder):
        dirs[:] = [d for d in dirs if d not in skip_folders]
        for file in files:
            if file.lower().endswith(".mp3") and not file.endswith(".cbr_temp.mp3"):
                all_mp3s.append(os.path.join(root, file))

    print(f"📂 Scanning {len(all_mp3s)} MP3 files...")
    for file_path in tqdm(all_mp3s, desc="Checking VBR", unit="file"):
        if is_vbr(file_path):
            vbr_files.append(file_path)
    return vbr_files


def convert_to_cbr(input_path, output_path, bitrate="320k"):
    """Convert to CBR and enforce NO VBR HEADERS."""
    try:
        cmd = [
            "ffmpeg",
            "-i", input_path,
            "-acodec", "libmp3lame",
            "-b:a", bitrate,
            "-minrate", bitrate,  # Force minimum bitrate to match target
            "-maxrate", bitrate,  # Force maximum bitrate to match target
            "-bufsize", "2M",  # Set buffer size (required for min/maxrate)
            "-write_xing", "0",  # <--- KEY FIX: Disable VBR/Xing header
            "-map", "0:a",  # Map audio
            "-map", "0:v?",  # Map cover art if exists
            "-map_metadata", "0",  # Copy metadata
            "-id3v2_version", "3",  # Windows friendly tags
            "-y",  # Overwrite
            "-loglevel", "error",
            output_path
        ]

        # Windows-specific subprocess flags to hide console window
        startupinfo = None
        if os.name == 'nt':
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            startupinfo=startupinfo
        )

        if result.returncode != 0:
            return False, result.stderr

        # Double check: ensure the new file is actually detected as CBR
        # If mutagen still says it's VBR, we shouldn't replace the original
        if is_vbr(output_path):
            return False, "Converted file still detected as VBR (FFmpeg flag failed)"

        return True, None

    except Exception as e:
        return False, str(e)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--convert", action="store_true")
    parser.add_argument("--replace", action="store_true")
    parser.add_argument("--folder", default=MUSIC_FOLDER)
    args = parser.parse_args()

    if not args.folder or not os.path.exists(args.folder):
        print("❌ Invalid folder.")
        sys.exit(1)

    if args.convert and not check_ffmpeg():
        print("❌ ffmpeg missing.")
        sys.exit(1)

    vbr_files = get_vbr_files(args.folder)

    if not vbr_files:
        print("✅ No VBR files found.")
        sys.exit(0)

    print(f"\n📊 Found {len(vbr_files)} VBR files.")

    if not args.convert:
        print("ℹ️  Run with --convert to process.")
        sys.exit(0)

    backup_folder = None
    if not args.replace:
        backup_folder = Path(args.folder) / "_vbr_backups"
        backup_folder.mkdir(exist_ok=True)

    converted = 0

    for file_path in tqdm(vbr_files, desc="Converting", unit="file"):
        file_path = Path(file_path)
        temp_output = file_path.with_suffix(".cbr_temp.mp3")

        success, error = convert_to_cbr(str(file_path), str(temp_output))

        if success:
            if not args.replace and backup_folder:
                shutil.move(str(file_path), str(backup_folder / file_path.name))
            else:
                os.remove(file_path)

            temp_output.rename(file_path)
            converted += 1
        else:
            print(f"\n❌ Error converting {file_path.name}: {error}")
            if temp_output.exists():
                os.remove(temp_output)

    print(f"\n✅ Converted {converted} files.")


if __name__ == "__main__":
    main()