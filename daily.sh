#!/bin/bash

# Trap for smooth exit on Ctrl+C
trap 'echo -e "${RED}Exiting gracefully...${NC}"; exit 0' INT

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# File paths
LOG_FILE="$HOME/irys_script.log"
CONFIG_FILE="$HOME/.irys_config.json"
DETAILS_FILE="$HOME/irys_file_details.json"
VENV_DIR="$HOME/irys_venv"

# Generate unique suffixes for file names
TIMESTAMP=$(date +%s)
RANDOM_SUFFIX=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)

# Hardcoded API keys with unique file names
PEXELS_API_KEY="iur1f5KGwvSIR1xr8I1t3KR3NP88wFXeCyV12ibHnioNXQYTy95KhE69"
PIXABAY_API_KEY="51848865-07253475f9fc0309b02c38a39"
PEXELS_API_KEY_FILE="$HOME/.pexels_api_key_${RANDOM_SUFFIX}"
PIXABAY_API_KEY_FILE="$HOME/.pixabay_api_key_${RANDOM_SUFFIX}"
echo "$PEXELS_API_KEY" > "$PEXELS_API_KEY_FILE"
echo "$PIXABAY_API_KEY" > "$PIXABAY_API_KEY_FILE"

# Hardcoded RPC URL
RPC_URL="https://lb.drpc.org/sepolia/Ao_8pbYuukXEso-5J5vI5v_ZEE4cLt4R8JhWPkfoZsMe"

# Hardcoded search queries
QUERIES=(
    "nature landscape" "city skyline" "abstract art" "ocean waves" "mountain hiking"
    "sunset beach" "forest path" "urban night" "waterfall" "desert dunes"
    "snowy mountains" "tropical island" "autumn leaves" "spring flowers" "winter forest"
    "street photography" "wildlife animals" "sunrise" "cloudy sky" "rainy day"
    "vintage cars" "modern architecture" "space stars" "aerial drone" "countryside"
    "city lights" "blooming flowers" "stormy sea" "calm lake" "foggy morning"
    "colorful market" "old town" "night sky" "river flow" "green valley"
    "urban street" "peaceful meadow" "sunset city" "mountain peak" "coastal cliffs"
    "desert sunset" "forest stream" "cityscape" "tropical jungle" "snowy village"
    "water reflection" "historic buildings" "sunny beach" "cloud timelapse" "wilderness"
)

# Python script paths with unique names
PIXABAY_DOWNLOADER_PY="$HOME/pixabay_downloader_${TIMESTAMP}_${RANDOM_SUFFIX}.py"
PEXELS_DOWNLOADER_PY="$HOME/pexels_downloader_${TIMESTAMP}_${RANDOM_SUFFIX}.py"

# Create Python scripts for video downloads
create_python_scripts() {
    if [ ! -f "$PIXABAY_DOWNLOADER_PY" ]; then
        cat << 'EOF' > "$PIXABAY_DOWNLOADER_PY"
import requests
import os
import sys
import time
import random
import string
import subprocess
import shutil
try:
    from moviepy.editor import VideoFileClip, concatenate_videoclips
    MOVIEPY_AVAILABLE = True
except ImportError:
    MOVIEPY_AVAILABLE = False

def format_size(bytes_size):
    return f"{bytes_size/(1024*1024):.2f} MB"

def format_time(seconds):
    mins = int(seconds // 60)
    secs = int(seconds % 60)
    return f"{mins:02d}:{secs:02d}"

def draw_progress_bar(progress, total, width=50):
    percent = progress / total * 100
    filled = int(width * progress // total)
    bar = '█' * filled + '-' * (width - filled)
    return f"[{bar}] {percent:.1f}%"

def check_ffmpeg():
    return shutil.which("ffmpeg") is not None

def concatenate_with_moviepy(files, output_file):
    if not MOVIEPY_AVAILABLE:
        print("⚠️ moviepy is not installed. Cannot concatenate with moviepy.")
        return False
    try:
        clips = []
        for fn in files:
            if os.path.exists(fn) and os.path.getsize(fn) > 0:
                try:
                    clip = VideoFileClip(fn)
                    clips.append(clip)
                except Exception as e:
                    print(f"⚠️ Skipping invalid file {fn}: {str(e)}")
        if not clips:
            print("⚠️ No valid video clips to concatenate.")
            return False
        final_clip = concatenate_videoclips(clips, method="compose")
        final_clip.write_videofile(output_file, codec="libx264", audio_codec="aac", temp_audiofile="temp-audio.m4a", remove_temp=True, threads=2)
        for clip in clips:
            clip.close()
        final_clip.close()
        return os.path.exists(output_file) and os.path.getsize(output_file) > 0
    except Exception as e:
        print(f"⚠️ Moviepy concatenation failed: {str(e)}")
        return False

def trim_video_to_size(input_file, target_bytes):
    try:
        duration_str = subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'default=noprint_wrappers=1:nokey=1', input_file]).decode().strip()
        duration = float(duration_str)
        final_size = os.path.getsize(input_file)
        new_duration = duration * (target_bytes / final_size)
        temp_file = "trimmed_" + input_file
        result = subprocess.run(['ffmpeg', '-i', input_file, '-t', str(new_duration), '-c', 'copy', temp_file], capture_output=True, text=True)
        if result.returncode == 0 and os.path.exists(temp_file) and os.path.getsize(temp_file) > 0:
            os.remove(input_file)
            os.rename(temp_file, input_file)
            print(f"✅ Trimmed video to approximate {format_size(os.path.getsize(input_file))}")
            return True
        else:
            print(f"⚠️ Trim failed: {result.stderr}")
            if os.path.exists(temp_file):
                os.remove(temp_file)
            return False
    except Exception as e:
        print(f"⚠️ Failed to trim: {str(e)}")
        return False

def download_videos(query, output_file, target_size_mb=1000):
    api_key_file = os.path.expanduser(f'~/.pixabay_api_key_{os.environ.get("RANDOM_SUFFIX")}')
    if not os.path.exists(api_key_file):
        print("⚠️ Pixabay API key file not found.")
        return
    with open(api_key_file, 'r') as f:
        api_key = f.read().strip()
    per_page = 100
    try:
        url = f"https://pixabay.com/api/videos/?key={api_key}&q={query}&per_page={per_page}&min_width=1920&min_height=1080&video_type=all"
        resp = requests.get(url, timeout=10)
        if resp.status_code != 200:
            print(f"⚠️ Error fetching Pixabay API: {resp.text}")
            return
        data = resp.json()
        videos = data.get('hits', [])
        if not videos:
            print("⚠️ No videos found for query.")
            return
        candidates = []
        for v in videos:
            video_url = v['videos'].get('large', {}).get('url') or v['videos'].get('medium', {}).get('url')
            if not video_url:
                continue
            head_resp = requests.head(video_url, timeout=10)
            size = int(head_resp.headers.get('content-length', 0))
            if size >= 1 * 1024 * 1024:
                candidates.append((size, v, video_url))
        if not candidates:
            print("⚠️ No suitable videos found (at least 1MB).")
            return
        candidates.sort(key=lambda x: x[0])  # smallest first
        downloaded_files = []
        total_size = 0
        total_downloaded = 0
        overall_start_time = time.time()
        min_filesize = 1 * 1024 * 1024
        target_bytes = target_size_mb * 1024 * 1024
        for size, v, video_url in candidates:
            remaining = target_bytes - total_size
            if size < min_filesize or size > remaining:
                continue
            filename = f"pix_{v['id']}_{''.join(random.choices(string.ascii_letters + string.digits, k=8))}.mp4"
            print(f"🎬 Downloading video: {v['tags']} ({format_size(size)}, {v['duration']}s)")
            file_start_time = time.time()
            resp = requests.get(video_url, stream=True, timeout=10)
            with open(filename, 'wb') as f:
                downloaded = 0
                for chunk in resp.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
                        downloaded += len(chunk)
                        percent = downloaded / size * 100 if size else 0
                        elapsed = time.time() - file_start_time
                        speed = downloaded / (1024*1024 * elapsed) if elapsed > 0 else 0
                        eta = (size - downloaded) / (speed * 1024*1024) if speed > 0 else 0
                        print(f"\r⬇️ File Progress: {draw_progress_bar(downloaded, size)} "
                              f"({format_size(downloaded)}/{format_size(size)}) "
                              f"Speed: {speed:.2f} MB/s ETA: {format_time(eta)}", end='')
            print("\r✅ File Download completed")
            file_size = os.path.getsize(filename) if os.path.exists(filename) else 0
            if file_size == 0:
                if os.path.exists(filename):
                    os.remove(filename)
                continue
            total_size += file_size
            total_downloaded += file_size
            downloaded_files.append(filename)
        if not downloaded_files and candidates:
            size, v, video_url = candidates[0]
            filename = f"pix_{v['id']}_{''.join(random.choices(string.ascii_letters + string.digits, k=8))}.mp4"
            print(f"🎬 Downloading large video to trim: {v['tags']} ({format_size(size)}, {v['duration']}s)")
            file_start_time = time.time()
            resp = requests.get(video_url, stream=True, timeout=10)
            with open(filename, 'wb') as f:
                downloaded = 0
                for chunk in resp.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
                        downloaded += len(chunk)
                        percent = downloaded / size * 100 if size else 0
                        elapsed = time.time() - file_start_time
                        speed = downloaded / (1024*1024 * elapsed) if elapsed > 0 else 0
                        eta = (size - downloaded) / (speed * 1024*1024) if speed > 0 else 0
                        print(f"\r⬇️ File Progress: {draw_progress_bar(downloaded, size)} "
                              f"({format_size(downloaded)}/{format_size(size)}) "
                              f"Speed: {speed:.2f} MB/s ETA: {format_time(eta)}", end='')
            print("\r✅ File Download completed")
            file_size = os.path.getsize(filename) if os.path.exists(filename) else 0
            if file_size == 0:
                if os.path.exists(filename):
                    os.remove(filename)
                print("⚠️ Downloaded empty file, skipping.")
                return
            total_size += file_size
            total_downloaded += file_size
            downloaded_files.append(filename)
        if not downloaded_files:
            print("⚠️ No suitable videos downloaded.")
            return
        original_files = downloaded_files.copy()
        original_size = total_size
        while total_size < target_bytes * 0.95 and original_size > 0:
            new_files = []
            for fn in original_files:
                new_fn = "dup_" + ''.join(random.choices(string.ascii_letters + string.digits, k=8)) + "_" + os.path.basename(fn)
                shutil.copy(fn, new_fn)
                new_files.append(new_fn)
            downloaded_files += new_files
            total_size += original_size
        if len(downloaded_files) == 1:
            os.rename(downloaded_files[0], output_file)
            downloaded_files = []
        else:
            success = False
            if check_ffmpeg():
                print("🔗 Concatenating videos with ffmpeg...")
                with open('list.txt', 'w') as f:
                    for fn in downloaded_files:
                        f.write(f"file '{fn}'\n")
                result = subprocess.run(['ffmpeg', '-f', 'concat', '-safe', '0', '-i', 'list.txt', '-c', 'copy', output_file], capture_output=True, text=True)
                if result.returncode == 0 and os.path.exists(output_file) and os.path.getsize(output_file) > 0:
                    success = True
                else:
                    print(f"⚠️ ffmpeg concatenation failed: {result.stderr}")
                if os.path.exists('list.txt'):
                    os.remove('list.txt')
            if not success:
                print("🔗 Falling back to moviepy for concatenation...")
                success = concatenate_with_moviepy(downloaded_files, output_file)
            if not success:
                print("⚠️ Concatenation failed. Using first video only.")
                os.rename(downloaded_files[0], output_file)
                downloaded_files = downloaded_files[1:]
        for fn in downloaded_files:
            if os.path.exists(fn):
                os.remove(fn)
        if os.path.exists(output_file) and os.path.getsize(output_file) > 0:
            final_size = os.path.getsize(output_file)
            if final_size > target_bytes:
                trim_video_to_size(output_file, target_bytes)
            print(f"✅ Video ready: {output_file} ({format_size(os.path.getsize(output_file))})")
        else:
            print("⚠️ Failed to create final video file.")
    except Exception as e:
        print(f"⚠️ An error occurred: {str(e)}")
        for fn in downloaded_files:
            if os.path.exists(fn):
                os.remove(fn)
        if os.path.exists('list.txt'):
            os.remove('list.txt')

if __name__ == "__main__":
    if len(sys.argv) > 2:
        target_size_mb = int(sys.argv[3]) if len(sys.argv) > 3 else 1000
        download_videos(sys.argv[1], sys.argv[2], target_size_mb=target_size_mb)
    else:
        print("Please provide a search query and output filename.")
EOF
    fi

    if [ ! -f "$PEXELS_DOWNLOADER_PY" ]; then
        cat << 'EOF' > "$PEXELS_DOWNLOADER_PY"
import requests
import os
import sys
import time
import random
import string
import subprocess
import shutil
try:
    from moviepy.editor import VideoFileClip, concatenate_videoclips
    MOVIEPY_AVAILABLE = True
except ImportError:
    MOVIEPY_AVAILABLE = False

def format_size(bytes_size):
    return f"{bytes_size/(1024*1024):.2f} MB"

def format_time(seconds):
    mins = int(seconds // 60)
    secs = int(seconds % 60)
    return f"{mins:02d}:{secs:02d}"

def draw_progress_bar(progress, total, width=50):
    percent = progress / total * 100
    filled = int(width * progress // total)
    bar = '█' * filled + '-' * (width - filled)
    return f"[{bar}] {percent:.1f}%"

def check_ffmpeg():
    return shutil.which("ffmpeg") is not None

def concatenate_with_moviepy(files, output_file):
    if not MOVIEPY_AVAILABLE:
        print("⚠️ moviepy is not installed. Cannot concatenate with moviepy.")
        return False
    try:
        clips = []
        for fn in files:
            if os.path.exists(fn) and os.path.getsize(fn) > 0:
                try:
                    clip = VideoFileClip(fn)
                    clips.append(clip)
                except Exception as e:
                    print(f"⚠️ Skipping invalid file {fn}: {str(e)}")
        if not clips:
            print("⚠️ No valid video clips to concatenate.")
            return False
        final_clip = concatenate_videoclips(clips, method="compose")
        final_clip.write_videofile(output_file, codec="libx264", audio_codec="aac", temp_audiofile="temp-audio.m4a", remove_temp=True, threads=2)
        for clip in clips:
            clip.close()
        final_clip.close()
        return os.path.exists(output_file) and os.path.getsize(output_file) > 0
    except Exception as e:
        print(f"⚠️ Moviepy concatenation failed: {str(e)}")
        return False

def trim_video_to_size(input_file, target_bytes):
    try:
        duration_str = subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'default=noprint_wrappers=1:nokey=1', input_file]).decode().strip()
        duration = float(duration_str)
        final_size = os.path.getsize(input_file)
        new_duration = duration * (target_bytes / final_size)
        temp_file = "trimmed_" + input_file
        result = subprocess.run(['ffmpeg', '-i', input_file, '-t', str(new_duration), '-c', 'copy', temp_file], capture_output=True, text=True)
        if result.returncode == 0 and os.path.exists(temp_file) and os.path.getsize(temp_file) > 0:
            os.remove(input_file)
            os.rename(temp_file, input_file)
            print(f"✅ Trimmed video to approximate {format_size(os.path.getsize(input_file))}")
            return True
        else:
            print(f"⚠️ Trim failed: {result.stderr}")
            if os.path.exists(temp_file):
                os.remove(temp_file)
            return False
    except Exception as e:
        print(f"⚠️ Failed to trim: {str(e)}")
        return False

def download_videos(query, output_file, target_size_mb=1000):
    api_key_file = os.path.expanduser(f'~/.pexels_api_key_{os.environ.get("RANDOM_SUFFIX")}')
    if not os.path.exists(api_key_file):
        print("⚠️ Pexels API key file not found.")
        return
    with open(api_key_file, 'r') as f:
        api_key = f.read().strip()
    per_page = 80
    try:
        headers = {'Authorization': api_key}
        url = f"https://api.pexels.com/videos/search?query={query}&per_page={per_page}"
        resp = requests.get(url, headers=headers, timeout=10)
        if resp.status_code != 200:
            print(f"⚠️ Error fetching Pexels API: {resp.text}")
            return
        data = resp.json()
        videos = data.get('videos', [])
        if not videos:
            print("⚠️ No videos found for query.")
            return
        candidates = []
        for v in videos:
            video_files = v.get('video_files', [])
            video_url = None
            for file in video_files:
                if file['width'] >= 1920 and file['height'] >= 1080:
                    video_url = file['link']
                    break
            if not video_url:
                continue
            head_resp = requests.head(video_url, timeout=10)
            size = int(head_resp.headers.get('content-length', 0))
            if size >= 1 * 1024 * 1024:
                candidates.append((size, v, video_url))
        if not candidates:
            print("⚠️ No suitable videos found (at least 1MB).")
            return
        candidates.sort(key=lambda x: x[0])  # smallest first
        downloaded_files = []
        total_size = 0
        total_downloaded = 0
        overall_start_time = time.time()
        min_filesize = 1 * 1024 * 1024
        target_bytes = target_size_mb * 1024 * 1024
        for size, v, video_url in candidates:
            remaining = target_bytes - total_size
            if size < min_filesize or size > remaining:
                continue
            filename = f"pex_{v['id']}_{''.join(random.choices(string.ascii_letters + string.digits, k=8))}.mp4"
            print(f"🎬 Downloading video: {v['id']} ({format_size(size)})")
            file_start_time = time.time()
            resp = requests.get(video_url, stream=True, timeout=10)
            with open(filename, 'wb') as f:
                downloaded = 0
                for chunk in resp.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
                        downloaded += len(chunk)
                        percent = downloaded / size * 100 if size else 0
                        elapsed = time.time() - file_start_time
                        speed = downloaded / (1024*1024 * elapsed) if elapsed > 0 else 0
                        eta = (size - downloaded) / (speed * 1024*1024) if speed > 0 else 0
                        print(f"\r⬇️ File Progress: {draw_progress_bar(downloaded, size)} "
                              f"({format_size(downloaded)}/{format_size(size)}) "
                              f"Speed: {speed:.2f} MB/s ETA: {format_time(eta)}", end='')
            print("\r✅ File Download completed")
            file_size = os.path.getsize(filename) if os.path.exists(filename) else 0
            if file_size == 0:
                if os.path.exists(filename):
                    os.remove(filename)
                continue
            total_size += file_size
            total_downloaded += file_size
            downloaded_files.append(filename)
        if not downloaded_files and candidates:
            size, v, video_url = candidates[0]
            filename = f"pex_{v['id']}_{''.join(random.choices(string.ascii_letters + string.digits, k=8))}.mp4"
            print(f"🎬 Downloading large video to trim: {v['id']} ({format_size(size)})")
            file_start_time = time.time()
            resp = requests.get(video_url, stream=True, timeout=10)
            with open(filename, 'wb') as f:
                downloaded = 0
                for chunk in resp.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
                        downloaded += len(chunk)
                        percent = downloaded / size * 100 if size else 0
                        elapsed = time.time() - file_start_time
                        speed = downloaded / (1024*1024 * elapsed) if elapsed > 0 else 0
                        eta = (size - downloaded) / (speed * 1024*1024) if speed > 0 else 0
                        print(f"\r⬇️ File Progress: {draw_progress_bar(downloaded, size)} "
                              f"({format_size(downloaded)}/{format_size(size)}) "
                              f"Speed: {speed:.2f} MB/s ETA: {format_time(eta)}", end='')
            print("\r✅ File Download completed")
            file_size = os.path.getsize(filename) if os.path.exists(filename) else 0
            if file_size == 0:
                if os.path.exists(filename):
                    os.remove(filename)
                print("⚠️ Downloaded empty file, skipping.")
                return
            total_size += file_size
            total_downloaded += file_size
            downloaded_files.append(filename)
        if not downloaded_files:
            print("⚠️ No suitable videos downloaded.")
            return
        original_files = downloaded_files.copy()
        original_size = total_size
        while total_size < target_bytes * 0.95 and original_size > 0:
            new_files = []
            for fn in original_files:
                new_fn = "dup_" + ''.join(random.choices(string.ascii_letters + string.digits, k=8)) + "_" + os.path.basename(fn)
                shutil.copy(fn, new_fn)
                new_files.append(new_fn)
            downloaded_files += new_files
            total_size += original_size
        if len(downloaded_files) == 1:
            os.rename(downloaded_files[0], output_file)
            downloaded_files = []
        else:
            success = False
            if check_ffmpeg():
                print("🔗 Concatenating videos with ffmpeg...")
                with open('list.txt', 'w') as f:
                    for fn in downloaded_files:
                        f.write(f"file '{fn}'\n")
                result = subprocess.run(['ffmpeg', '-f', 'concat', '-safe', '0', '-i', 'list.txt', '-c', 'copy', output_file], capture_output=True, text=True)
                if result.returncode == 0 and os.path.exists(output_file) and os.path.getsize(output_file) > 0:
                    success = True
                else:
                    print(f"⚠️ ffmpeg concatenation failed: {result.stderr}")
                if os.path.exists('list.txt'):
                    os.remove('list.txt')
            if not success:
                print("🔗 Falling back to moviepy for concatenation...")
                success = concatenate_with_moviepy(downloaded_files, output_file)
            if not success:
                print("⚠️ Concatenation failed. Using first video only.")
                os.rename(downloaded_files[0], output_file)
                downloaded_files = downloaded_files[1:]
        for fn in downloaded_files:
            if os.path.exists(fn):
                os.remove(fn)
        if os.path.exists(output_file) and os.path.getsize(output_file) > 0:
            final_size = os.path.getsize(output_file)
            if final_size > target_bytes:
                trim_video_to_size(output_file, target_bytes)
            print(f"✅ Video ready: {output_file} ({format_size(os.path.getsize(output_file))})")
        else:
            print("⚠️ Failed to create final video file.")
    except Exception as e:
        print(f"⚠️ An error occurred: {str(e)}")
        for fn in downloaded_files:
            if os.path.exists(fn):
                os.remove(fn)
        if os.path.exists('list.txt'):
            os.remove('list.txt')

if __name__ == "__main__":
    if len(sys.argv) > 2:
        target_size_mb = int(sys.argv[3]) if len(sys.argv) > 3 else 1000
        download_videos(sys.argv[1], sys.argv[2], target_size_mb=target_size_mb)
    else:
        print("Please provide a search query and output filename.")
EOF
    fi
}

# Setup virtual environment
setup_venv() {
    if [ ! -d "$VENV_DIR" ]; then
        echo -e "${BLUE}Setting up virtual environment...${NC}"
        python3 -m venv "$VENV_DIR" || { echo -e "${RED}Failed to create venv. Ensure python3-venv is installed.${NC}"; exit 1; }
    fi
    source "$VENV_DIR/bin/activate"
    pip install requests moviepy imageio-ffmpeg > /dev/null 2>&1 || echo -e "${YELLOW}Some packages may not install, but continuing...${NC}"
    if ! command -v ffmpeg >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️ ffmpeg is not installed. Attempting to install... 🔧${NC}"
        sudo apt update && sudo apt install -y ffmpeg 2>&1 | tee -a "$LOG_FILE"
        if ! command -v ffmpeg >/dev/null 2>&1; then
            echo -e "${YELLOW}⚠️ Failed to install ffmpeg. Continuing without it...${NC}"
        else
            echo -e "${GREEN}✅ ffmpeg installed successfully. 🎥${NC}"
        fi
    fi
}

# Load config from JSON
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        PRIVATE_KEY=$(jq -r '.private_key // empty' "$CONFIG_FILE")
        WALLET_ADDRESS=$(jq -r '.wallet_address // empty' "$CONFIG_FILE")
    fi
    if [ -z "$PRIVATE_KEY" ] || [ -z "$WALLET_ADDRESS" ]; then
        echo -e "${RED}❌ Private key or wallet address missing in $CONFIG_FILE. Please run initial setup script first.${NC}"
        exit 1
    fi
}

# Get balance in ETH
get_balance_eth() {
    balance_output=$(irys balance "$WALLET_ADDRESS" -t ethereum -n devnet --provider-url "$RPC_URL" 2>&1)
    echo "$balance_output" | grep -oP '(?<=\()[0-9.]+(?= ethereum\))' || echo "0"
}

# Upload file to Irys
upload_file() {
    local file_to_upload="$1"
    local output_file="$2"
    if [ -f "$file_to_upload" ]; then
        size_mb=$(du -m "$file_to_upload" | cut -f1 2>/dev/null || echo 0)
        balance_eth=$(get_balance_eth)
        estimated_cost=$(awk "BEGIN {print ($size_mb / 100) * 0.0012}")
        if [ "$(awk "BEGIN {if ($balance_eth < $estimated_cost) print 1; else print 0}")" = "1" ]; then
            echo -e "${RED}⚠️ Insufficient balance for $output_file. You have ${balance_eth} ETH, need ~${estimated_cost} ETH.${NC}" | tee -a "$LOG_FILE"
            rm -f "$file_to_upload"
            return 1
        fi
        echo -e "${BLUE}⬆️ Uploading $output_file to Irys... 🚀${NC}"
        retries=0
        max_retries=3
        while [ $retries -lt $max_retries ]; do
            attempt=$((retries+1))
            echo -e "${BLUE}📤 Upload attempt ${attempt}/${max_retries}... 🔄${NC}"
            upload_output=$(irys upload "$file_to_upload" -n devnet -t ethereum -w "$PRIVATE_KEY" --provider-url "$RPC_URL" --tags file_name "${output_file%.*}" --tags file_format "${output_file##*.}" 2>&1)
            if [ $? -eq 0 ]; then
                echo "$upload_output" | tee -a "$LOG_FILE"
                url=$(echo "$upload_output" | grep -oP 'Uploaded to \K(https?://[^\s]+)')
                txid=$(basename "$url")
                if [ -n "$txid" ]; then
                    echo -e "${BLUE}💾 Saving file details to $DETAILS_FILE... 📝${NC}"
                    if [ ! -f "$DETAILS_FILE" ]; then
                        echo "[]" > "$DETAILS_FILE"
                    fi
                    jq --arg fn "$output_file" --arg fid "$txid" --arg dl "$url" --arg sl "$url" \
                       '. + [{"file_name": $fn, "file_id": $fid, "direct_link": $dl, "social_link": $sl}]' \
                       "$DETAILS_FILE" > tmp.json && mv tmp.json "$DETAILS_FILE"
                    if [ $? -eq 0 ]; then
                        echo -e "${GREEN}✅ File details saved successfully. 🎉${NC}"
                    else
                        echo -e "${YELLOW}⚠️ Failed to save file details to $DETAILS_FILE 😞${NC}"
                    fi
                    echo -e "${BLUE}🗑️ Deleting local file... 🧹${NC}"
                    rm -f "$file_to_upload"
                    return 0
                else
                    echo -e "${YELLOW}⚠️ Failed to extract Transaction ID or URL. 🤔${NC}"
                fi
            else
                echo -e "${YELLOW}⚠️ Upload failed: $upload_output${NC}" | tee -a "$LOG_FILE"
            fi
            retries=$((retries+1))
            sleep 5
        done
        echo -e "${RED}❌ Upload failed after $max_retries attempts for $output_file. Check logs in $LOG_FILE. 😔${NC}"
        rm -f "$file_to_upload" 2>/dev/null
        return 1
    else
        echo -e "${YELLOW}⚠️ File $output_file not found. Download may have failed. 😞${NC}"
        return 1
    fi
}

# Main upload function
daily_upload() {
    setup_venv
    rm -f "$HOME/video_downloader.py" "$HOME/pixabay_downloader_*.py" "$HOME/pexels_downloader_*.py" "$HOME/.pexels_api_key_*" "$HOME/.pixabay_api_key_*" 2>/dev/null
    create_python_scripts
    load_config
    source "$VENV_DIR/bin/activate"
    
    # Determine number of files to upload (5 to 10)
    num_files=$((RANDOM % 6 + 5))
    
    # Ensure ~60% videos, 40% images
    num_videos=$(( (num_files * 60 + 50) / 100 )) # Rounds to ~60%
    num_images=$((num_files - num_videos))
    
    # Get balance and calculate max upload size per file
    balance_eth=$(get_balance_eth)
    max_total_mb=$(awk "BEGIN {print int(($balance_eth / 0.0012) * 100)}")
    # Spread uploads over a week (7 days), so use 1/7 of balance daily
    daily_max_mb=$(awk "BEGIN {print int($max_total_mb / 14)}")
    # Ensure at least 1 MB per file, max 50 MB per file to avoid large videos
    max_mb_per_file=$(awk "BEGIN {print int($daily_max_mb / $num_files)}")
    max_mb_per_file=$(( max_mb_per_file < 1 ? 1 : max_mb_per_file > 50 ? 50 : max_mb_per_file ))
    
    echo -e "${BLUE}📊 Balance: ${balance_eth} ETH, Daily Max: ${daily_max_mb} MB, Uploading ${num_files} files (${num_videos} videos, ${num_images} images, max ${max_mb_per_file} MB each)${NC}"
    
    # Export RANDOM_SUFFIX for Python scripts
    export RANDOM_SUFFIX
    
    # Upload videos (~60%)
    for ((i=0; i<num_videos; i++)); do
        query_index=$((RANDOM % ${#QUERIES[@]}))
        query="${QUERIES[$query_index]}"
        random_suffix=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
        output_file="video_$random_suffix.mp4"
        # Randomly choose between Pexels and Pixabay
        if (( RANDOM % 2 )); then
            echo -e "${BLUE}📥 Downloading video from Pexels... ✨${NC}"
            python3 "$PEXELS_DOWNLOADER_PY" "$query" "$output_file" "$max_mb_per_file" 2>&1 | tee -a "$LOG_FILE"
        else
            echo -e "${BLUE}📥 Downloading video from Pixabay... 🌟${NC}"
            python3 "$PIXABAY_DOWNLOADER_PY" "$query" "$output_file" "$max_mb_per_file" 2>&1 | tee -a "$LOG_FILE"
        fi
        upload_file "$output_file" "$output_file"
        # Random delay between uploads (30-50 seconds)
        upload_delay=$((RANDOM % 21 + 30))
        echo -e "${BLUE}⏰ Waiting ${upload_delay} seconds before next upload...${NC}"
        sleep $upload_delay
    done
    
    # Upload images (~40%)
    for ((i=0; i<num_images; i++)); do
        width=$((RANDOM % 1921 + 640))
        height=$((RANDOM % 1081 + 480))
        if (( RANDOM % 2 )); then grayscale="?grayscale"; else grayscale=""; fi
        blur=$((RANDOM % 11))
        if [ $blur -gt 0 ]; then blur_param="&blur=$blur"; else blur_param=""; fi
        seed=$((RANDOM % 10000))
        if [ -n "$seed" ]; then seed_path="/seed/$seed"; else seed_path=""; fi
        url="https://picsum.photos$seed_path/$width/$height$grayscale$blur_param"
        random_suffix=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
        output_file="picsum_$random_suffix.jpg"
        echo -e "${BLUE}📥 Downloading image from Picsum: $url ... 🖼️${NC}"
        curl -L -o "$output_file" "$url" 2>&1 | tee -a "$LOG_FILE"
        upload_file "$output_file" "$output_file"
        # Random delay between uploads (30-50 seconds), except for the last file
        if [ $i -lt $((num_images - 1)) ] || [ $num_videos -gt 0 ]; then
            upload_delay=$((RANDOM % 21 + 30))
            echo -e "${BLUE}⏰ Waiting ${upload_delay} seconds before next upload...${NC}"
            sleep $upload_delay
        fi
    done
    
    deactivate
    echo -e "${GREEN}✅ Daily upload completed! Uploaded ${num_files} files (${num_videos} videos, ${num_images} images). 🎉${NC}"
}

while true; do
    # Random delay between 18h (64800s) and 22h (79200s)
    random_delay=3
    echo -e "${BLUE}⏰ Waiting $((random_delay / 3600))h $(((random_delay % 3600) / 60))m before next upload...${NC}"
    sleep $random_delay
    daily_upload
done
