# 🎵 Anywhere-Music-Player

> **Self-hosted, cross-platform music streaming for your personal anime collection.**
> *Write Once (Flutter), Host Anywhere (Coolify), Play Everywhere (TV & PC).*

**AniStream** is a private streaming solution designed to solve a specific problem: accessing a local high-quality MP3 library (3GB+) seamlessly on a **PC Web Browser** and a **Smart TV (Android TV)** without relying on commercial cloud services.

## 🏗️ Architecture

The system runs entirely on your existing self-hosted infrastructure using **Coolify** on Hetzner.

```mermaid
graph TD
    subgraph "Local Machine (PC)"
        MP3s[MP3 Files]
        Script[Python Uploader Script]
    end

    subgraph "Hetzner VPS (Coolify)"
        n8n[n8n Automation]
        MinIO["MinIO Storage (S3)""]
        DB[(PostgreSQL)]
        API[PostgREST]
    end

    subgraph Clients
        TV[Android TV App]
        Web[Flutter Web App]
    end

    %% Ingestion Flow
    MP3s --> Script
    Script -->|POST File + Metadata| n8n
    n8n -->|Upload Binary| MinIO
    n8n -->|Insert Metadata| DB

    %% Playback Flow
    TV -->|GET /tracks| API
    Web -->|GET /tracks| API
    API -->|Query| DB
    TV -->|Stream Audio| MinIO
    Web -->|Stream Audio| MinIO
```

### The Stack
*   **Infrastructure:** Hetzner Cloud + Coolify.
*   **Storage:** **MinIO** (S3 Compatible) - Stores the MP3 files.
*   **Database:** **PostgreSQL** - Stores song metadata (Artist, Title, Duration, Stream URL).
*   **Ingestion:** **n8n** - Receives files from PC, handles S3 upload and DB insertion.
*   **Read API:** **PostgREST** - Instantly turns the PostgreSQL database into a REST API for the app to read.
*   **Frontend:** **Flutter** - Single codebase compiling to Android TV (APK) and Web (PWA).

---

## 🚀 Prerequisites

1.  **Flutter SDK** installed on your local machine.
2.  **Python 3** installed (for the uploader script).
3.  **Coolify Instance** running.
4.  **n8n** installed and accessible.

---

## 🛠️ Backend Setup (Coolify)

### 1. Storage (MinIO)
1.  In Coolify, deploy a **MinIO** service.
2.  Create a bucket named `anime-music`.
3.  **Important:** Set the bucket policy to **Public** (Read-only) so the TV can stream without complex auth tokens.
4.  Save your `Access Key`, `Secret Key`, and `Endpoint` for the n8n step.

### 2. Database (PostgreSQL)
Run the following SQL in your existing PostgreSQL instance to create the schema:

```sql
CREATE TABLE public.tracks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    artist TEXT DEFAULT 'Unknown',
    album TEXT,
    filename TEXT NOT NULL,
    stream_url TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Index for faster sorting/searching
CREATE INDEX idx_tracks_artist ON public.tracks(artist);
CREATE INDEX idx_tracks_title ON public.tracks(title);
```

### 3. Read API (PostgREST)
1.  In Coolify, deploy **PostgREST**.
2.  Connect it to your PostgreSQL container.
3.  This will expose your DB at `https://api.YOUR_DOMAIN`.
    *   *Test:* Visiting `https://api.YOUR_DOMAIN/tracks` should return an empty JSON array `[]`.

---

## 📥 Data Ingestion (n8n & Python)

We use **n8n** strictly for the uploading process to handle the file logic and database recording.

### Step 1: Configure n8n Workflow
Create a workflow with a **Webhook Trigger** (POST) that accepts Binary Data.
*   **Node 1 (S3):** Uploads binary to MinIO bucket `anime-music`.
*   **Node 2 (Postgres):** Inserts `title`, `artist`, and constructs the `stream_url`.
    *   *Stream URL Format:* `https://minio.YOUR_DOMAIN/anime-music/{{filename}}`

### Step 2: The Uploader Script
This script runs on your PC. It scans your folder, reads ID3 tags (Title/Artist), and pushes them to n8n.

**`scripts/upload.py`**:
```python
import os
import requests
import eyed3

# CONFIG
FOLDER = r"C:\Music\Anime"
WEBHOOK = "https://n8n.YOUR_DOMAIN/webhook/upload-music"
AUTH_HEADER = {"x-api-key": "your-n8n-secret"}

for root, _, files in os.walk(FOLDER):
    for file in files:
        if file.endswith(".mp3"):
            path = os.path.join(root, file)
            audio = eyed3.load(path)
            
            # Extract tags or fallback to filename
            title = audio.tag.title if audio and audio.tag.title else file
            artist = audio.tag.artist if audio and audio.tag.artist else "Unknown"

            print(f"Uploading: {title}...")
            
            with open(path, 'rb') as f:
                requests.post(
                    WEBHOOK,
                    headers=AUTH_HEADER,
                    data={'title': title, 'artist': artist, 'filename': file},
                    files={'data': f}
                )
```

---

## 📺 Frontend Development (Flutter)

The app is built to be "Remote Control Friendly" (D-Pad navigation).

### Project Structure
```text
lib/
├── models/
│   └── track.dart       # JSON model matches Postgres table
├── services/
│   ├── api_service.dart # Dio calls to PostgREST
│   └── audio_player.dart# Just_Audio implementation
├── ui/
│   ├── home_screen.dart # ListView of songs
│   └── player_view.dart # Big 'Now Playing' screen
└── main.dart
```

### Key Dependencies (`pubspec.yaml`)
```yaml
dependencies:
  flutter:
    sdk: flutter
  just_audio: ^0.9.36      # Audio streaming
  dio: ^5.4.0              # HTTP requests
  audio_session: ^0.1.18   # Manage audio focus (TV vs Phone)
  provider: ^6.1.1         # State management
```

### Building & Running

**1. For Web (PC)**
```bash
flutter run -d chrome
```

**2. For Android TV**
*   Connect TV via ADB: `adb connect 192.168.X.X`
*   Run Debug: `flutter run -d android`
*   **Build Final APK:**
    ```bash
    flutter build apk --split-per-abi
    ```
    *Transfer the resulting APK to your TV using the "Send Files to TV" app.*

---

## 🎮 TV Controls

| Remote Button | Action |
| :--- | :--- |
| **D-Pad Up/Down** | Scroll through song list |
| **Center / Select** | Play song |
| **Back** | Return to list (music keeps playing) |

---

## 🔮 Future Roadmap
- [ ] **Favorites:** Add a boolean column to DB and a toggle in UI.
- [ ] **Search:** Implement server-side search via PostgREST (`/tracks?title=ilike.*naruto*`).
- [ ] **Playlists:** Create a separate table for grouping tracks.

---

## 📝 License
Personal Project - MIT License.