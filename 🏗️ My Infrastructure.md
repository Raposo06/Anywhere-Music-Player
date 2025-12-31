# 🏗️ AniStream Infrastructure

> Infrastructure specification for the **Anywhere-Music-Player (AniStream)** project.

---

## 1. ☁️ The Server (Hardware)

- **Provider:** [Hetzner Cloud](https://console.hetzner.cloud/)
- **Location:** Germany (Nuremberg/Falkenstein) — _Low latency for EU._
- **Server Type:** **CX22** (Intel/AMD x86 Architecture)
- **Specs:**
    - **CPU:** 2 vCPU
    - **RAM:** 4 GB
    - **Disk:** 40 GB NVMe
- **Operating System:** Ubuntu 24.04 LTS
- **Cost:** ~€4.35/month (excl. VAT)
- **IP Address:** _(Check your Hetzner Dashboard)_

---

## 2. 🛠️ The Management Layer (PaaS)

- **Software:** [Coolify](https://coolify.io/)
- **Function:** Manages Docker containers, Reverse Proxy (Traefik), and SSL certificates automatically.
- **Installation:** Self-hosted on the Hetzner server ("Localhost").
- **Access Port:** `http://YOUR_IP:8000` (initially) or via your configured domain.

---

## 3. 🧩 The Software Stack (Applications)

All applications run as Docker containers managed by Coolify.

### A. Object Storage (MinIO)

- **Software:** [MinIO](https://min.io/)
- **Type:** Docker Service (S3-compatible storage)
- **Domain:** `https://minio.YOUR_DOMAIN/`
- **Console Domain:** `https://minio-console.YOUR_DOMAIN/`
- **Bucket Name:** `anime-music`
- **Bucket Policy:** **Public (Read-only)** — Allows streaming without auth tokens.
- **Configuration:**
    - **Access Key:** _(Store securely)_
    - **Secret Key:** _(Store securely)_
- **Stream URL Format:** `https://minio.YOUR_DOMAIN/anime-music/{filename}`

### B. Database (PostgreSQL)

- **Software:** PostgreSQL 16
- **Type:** Docker Service
- **Purpose:** Stores track metadata for the music library.
- **Access Configuration:**
    - **Internal (PostgREST):** Connects via Docker internal network.
    - **External (Uploader Script/DBeaver):** SSH Tunnel recommended (not exposed publicly).
- **Security:** Port mappings left **empty** (not exposed to public internet).
- **Schema:**
    ```sql
    CREATE TABLE public.tracks (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        title TEXT NOT NULL,
        artist TEXT DEFAULT 'Unknown',
        album TEXT,
        filename TEXT NOT NULL UNIQUE,
        stream_url TEXT NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
    );

    CREATE INDEX idx_tracks_artist ON public.tracks(artist);
    CREATE INDEX idx_tracks_title ON public.tracks(title);
    ```
- **Naming Conventions:**
    - **Format:** `snake_case` (e.g., `stream_url`)
    - **Language:** English
    - **Tables:** Plural (e.g., `tracks`)
    - **Schema:** `public`

### C. Read API (PostgREST)

- **Software:** [PostgREST](https://postgrest.org/)
- **Type:** Docker Service
- **Domain:** `https://api.YOUR_DOMAIN/`
- **Purpose:** Exposes PostgreSQL as a RESTful API for the Flutter app.
- **Endpoints:**
    - `GET /tracks` — List all tracks
    - `GET /tracks?title=ilike.*keyword*` — Search by title
    - `GET /tracks?artist=eq.ArtistName` — Filter by artist
- **Connection:** Reads from the same PostgreSQL instance (Business Database).
- **Security:** Read-only role (no mutations from API).

---

## 4. 🌐 Networking & DNS

- **Provider:** Cloudflare
- **SSL Mode:** **Full (Strict)**
- **Base Domain:** `YOUR_DOMAIN` _(e.g., anistream.example.com)_

### DNS Records

| Type | Name | Value | Proxy |
|------|------|-------|-------|
| `A` | `@` | Hetzner IP | ☁️ Proxied |
| `A` | `minio` | Hetzner IP | ☁️ Proxied |
| `A` | `minio-console` | Hetzner IP | ☁️ Proxied |
| `A` | `api` | Hetzner IP | ☁️ Proxied |

---

## 5. 🔑 Credentials Checklist

Store these securely (password manager recommended):

| Service | Credentials |
|---------|-------------|
| **Hetzner** | Root SSH password/key |
| **Coolify** | Admin email/password |
| **MinIO** | Access Key + Secret Key |
| **PostgreSQL** | Database user/password |

---

## 6. 📝 Quick Commands

```bash
# Connect to server
ssh root@YOUR_HETZNER_IP

# Check running containers
docker ps

# Check Coolify logs
docker logs -f coolify

# Check MinIO logs
docker logs -f <minio-container-id>

# Check PostgREST logs
docker logs -f <postgrest-container-id>

# Test API endpoint
curl https://api.YOUR_DOMAIN/tracks
```

---

## 7. 🗺️ Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    Hetzner VPS (CX22)                           │
│                    Ubuntu 24.04 + Coolify                       │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                     Docker Network                         │  │
│  │                                                            │  │
│  │   ┌─────────┐    ┌─────────────┐    ┌───────────────┐     │  │
│  │   │  MinIO  │    │  PostgreSQL │    │   PostgREST   │     │  │
│  │   │ :9000   │    │    :5432    │◄───│    :3000      │     │  │
│  │   │         │    │             │    │               │     │  │
│  │   └────▲────┘    └──────▲──────┘    └───────────────┘     │  │
│  │        │                │                    ▲             │  │
│  │        │                │                    │             │  │
│  └────────┼────────────────┼────────────────────┼─────────────┘  │
│           │                │                    │                │
└───────────┼────────────────┼────────────────────┼────────────────┘
            │                │                    │
            │   ┌────────────┘                    │
            │   │                                 │
    ┌───────┴───┴───┐                    ┌────────┴────────┐
    │ Python Script │                    │  Flutter Apps   │
    │   (Upload)    │                    │  (Web + TV)     │
    └───────────────┘                    └─────────────────┘
```

---

## 8. 📊 Resource Estimates

| Component | RAM | CPU | Storage |
|-----------|-----|-----|---------|
| Coolify | ~500 MB | Low | ~2 GB |
| MinIO | ~200 MB | Low | **Scales with library (max 6GB)** |
| PostgreSQL | ~200 MB | Low | ~100 MB |
| PostgREST | ~50 MB | Very Low | Minimal |
| **Total** | **~1 GB** | — | **~10 GB used** |

> **Note:** CX22 with 4GB RAM and 40GB NVMe has plenty of headroom for this stack.
