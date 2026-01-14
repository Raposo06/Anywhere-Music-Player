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

# Standard sample rates that Windows Media Foundation handles well
STANDARD_SAMPLE_RATES = {44100, 48000}
# Minimum bitrate for quality (files below this are likely problematic)
MIN_BITRATE = 128000  # 128 kbps


def check_ffmpeg():
    try:
        subprocess.run(["ffmpeg", "-version"], capture_output=True, check=True)
        return True
    except:
        return False


def is_vbr(file_path):
    """Check if file uses VBR encoding."""
    try:
        audio = MP3(file_path, ID3=ID3)
        if audio.info and hasattr(audio.info, 'bitrate_mode'):
            return audio.info.bitrate_mode == 1  # 1 is VBR
        return False
    except Exception:
        return False


def needs_conversion(file_path):
    """
    Check if file needs conversion due to:
    - VBR encoding
    - Non-standard sample rate
    - Very low bitrate
    - Unreadable/corrupted headers
    """
    try:
        audio = MP3(file_path, ID3=ID3)

        if not audio.info:
            return True, "No audio info (corrupted)"

        # Check for VBR
        if hasattr(audio.info, 'bitrate_mode') and audio.info.bitrate_mode == 1:
            return True, "VBR encoding"

        # Check sample rate
        sample_rate = getattr(audio.info, 'sample_rate', 0)
        if sample_rate not in STANDARD_SAMPLE_RATES:
            return True, f"Non-standard sample rate ({sample_rate} Hz)"

        # Check bitrate (very low bitrates cause issues)
        bitrate = getattr(audio.info, 'bitrate', 0)
        if bitrate < MIN_BITRATE:
            return True, f"Low bitrate ({bitrate // 1000}k)"

        return False, None

    except Exception as e:
        return True, f"Read error: {str(e)[:50]}"


def get_problematic_files(folder, check_all=False):
    """Find files that need conversion."""
    problematic_files = []
    all_mp3s = []
    skip_folders = {'_vbr_backups', '__pycache__', '.git', '$RECYCLE.BIN', 'System Volume Information'}

    for root, dirs, files in os.walk(folder):
        dirs[:] = [d for d in dirs if d not in skip_folders]
        for file in files:
            if file.lower().endswith(".mp3") and not file.endswith(".cbr_temp.mp3"):
                all_mp3s.append(os.path.join(root, file))

    print(f"📂 Scanning {len(all_mp3s)} MP3 files...")

    for file_path in tqdm(all_mp3s, desc="Analyzing", unit="file"):
        if check_all:
            problematic_files.append((file_path, "Force re-encode"))
        else:
            needs_conv, reason = needs_conversion(file_path)
            if needs_conv:
                problematic_files.append((file_path, reason))

    return problematic_files


def convert_to_cbr(input_path, output_path, bitrate="320k"):
    """Convert to CBR with standard settings for Windows compatibility."""
    try:
        cmd = [
            "ffmpeg",
            "-i", input_path,
            "-acodec", "libmp3lame",
            "-ar", "44100",  # Standard sample rate (fixes 48kHz issues)
            "-b:a", bitrate,
            "-minrate", bitrate,  # Force minimum bitrate to match target
            "-maxrate", bitrate,  # Force maximum bitrate to match target
            "-bufsize", "2M",  # Set buffer size (required for min/maxrate)
            "-write_xing", "0",  # Disable VBR/Xing header
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
    parser = argparse.ArgumentParser(
        description="Convert problematic MP3s for Windows compatibility"
    )
    parser.add_argument("--convert", action="store_true",
                        help="Actually perform the conversion")
    parser.add_argument("--replace", action="store_true",
                        help="Replace originals (no backup)")
    parser.add_argument("--all", action="store_true",
                        help="Re-encode ALL MP3 files, not just problematic ones")
    parser.add_argument("--folder", default=MUSIC_FOLDER,
                        help="Music folder to scan")
    args = parser.parse_args()

    if not args.folder or not os.path.exists(args.folder):
        print("❌ Invalid folder.")
        sys.exit(1)

    if args.convert and not check_ffmpeg():
        print("❌ ffmpeg missing.")
        sys.exit(1)

    # Find problematic files (or all files if --all)
    problematic_files = get_problematic_files(args.folder, check_all=args.all)

    if not problematic_files:
        print("✅ No problematic files found.")
        sys.exit(0)

    # Show summary by reason
    print(f"\n📊 Found {len(problematic_files)} files to convert:")
    reasons = {}
    for _, reason in problematic_files:
        reasons[reason] = reasons.get(reason, 0) + 1
    for reason, count in sorted(reasons.items(), key=lambda x: -x[1]):
        print(f"   • {reason}: {count}")

    if not args.convert:
        print("\nℹ️  Run with --convert to process these files.")
        print("   Add --all to re-encode ALL files (safest for Windows).")
        sys.exit(0)

    backup_folder = None
    if not args.replace:
        backup_folder = Path(args.folder) / "_converted_backups"
        backup_folder.mkdir(exist_ok=True)
        print(f"\n📁 Backups will be saved to: {backup_folder}")

    converted = 0
    failed = 0

    for file_path, reason in tqdm(problematic_files, desc="Converting", unit="file"):
        file_path = Path(file_path)
        temp_output = file_path.with_suffix(".cbr_temp.mp3")

        success, error = convert_to_cbr(str(file_path), str(temp_output))

        if success:
            if not args.replace and backup_folder:
                # Create subdirectory structure in backup
                rel_path = file_path.relative_to(args.folder)
                backup_path = backup_folder / rel_path
                backup_path.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(file_path), str(backup_path))
            else:
                os.remove(file_path)

            temp_output.rename(file_path)
            converted += 1
        else:
            tqdm.write(f"❌ {file_path.name}: {error}")
            if temp_output.exists():
                os.remove(temp_output)
            failed += 1

    print(f"\n{'=' * 50}")
    print(f"📊 Summary: ✅ {converted} converted | ❌ {failed} failed")
    print(f"{'=' * 50}")


if __name__ == "__main__":
    main()