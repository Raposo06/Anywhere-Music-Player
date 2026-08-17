# Anywhere Music Player

> **Maintenance:** kept in sync from the repo. Updated when something
> *meaningful* changes (architecture, stack, platform support, major features,
> or implemented/remaining status) — not on every commit. Migrated from WikiJS
> (`projects/anywhere-music-player`) on 2026-08-17 so the docs live next to the
> code they describe. Last reviewed: 2026-08-17.

Self-hosted, cross-platform music streaming: **write once (Flutter), host
anywhere (Navidrome), play everywhere**. A private client for a personal music
library — no accounts to create, no catalogue but your own.

## Index

- [Decisions](decisions.md) — **the decision log.** Why sequencing is manual,
  why the Windows audio backend was swapped, why the stream cache is
  Android-only. Read before "simplifying" any of it.
- [Operations](operations.md) — building, running, releasing, and the traps
  that have cost time.

## Architecture

```
┌────────────────────────────────────────┐
│            Flutter App                 │
│      Android TV │ Android │ Windows    │
└──────────────────┬─────────────────────┘
                   │ Subsonic API (/rest/*)
                   ▼
┌────────────────────────────────────────┐
│         Navidrome Server               │
│      https://navidrome.foxcore.dev     │
│  • Scans & indexes /music              │
│  • Serves audio streams & cover art    │
│  • User management                     │
│  • Subsonic API compatibility layer    │
└──────────────────┬─────────────────────┘
                   │ read-only bind mount
                   ▼
        /mnt/music — Hetzner Storage Box
        (CIFS mount on the fox-core VPS)
```

The app talks **exclusively** through the Subsonic API. Navidrome owns scanning,
metadata, user management, streaming and cover art — the client deliberately has
no backend of its own.

### Subsonic endpoints used

| Function | Endpoint |
|---|---|
| Auth check | `GET /rest/ping` |
| Browse folders | `GET /rest/getMusicFolders`, `GET /rest/getMusicDirectory` |
| Search | `GET /rest/search3` |
| Stream audio | `GET /rest/stream?id=X` |
| Cover art | `GET /rest/getCoverArt?id=X` |

## Platform support

| Platform | State |
|---|---|
| Android (phone) | Shipped — APK |
| Android TV | Shipped — D-pad UI, `LEANBACK_LAUNCHER` |
| Windows | Shipped — Inno Setup installer (`installer.iss`) |
| iOS | Scaffolded (`ios/`), not distributed — needs an Apple Developer account |
| Linux / macOS | Scaffolded by Flutter, not built or distributed |
| Web | **Not supported** — there is no `web/` directory |

> ⚠️ The README and the old WikiJS page both listed **Web** as a target. That was
> never true in this tree; corrected 2026-08-17. The Windows audio backend
> (media_kit/MPV) is desktop-native and would not carry to web regardless.

## Stack

| Layer | Tech | Notes |
|---|---|---|
| App | **Flutter** | SDK `>=3.8.0 <4.0.0`; version `1.1.0+2` |
| Audio | **just_audio** | `just_audio_media_kit` (MPV) on Windows/Linux — see [decisions](decisions.md) |
| Background playback | **audio_service** | Android notification + lock screen controls |
| Windows media keys | **smtc_windows** | System Media Transport Controls |
| State | **provider** | |
| Server | **Navidrome** | Subsonic-compatible; Docker on the fox-core VPS, managed by Coolify |
| Config | **flutter_dotenv** | Runtime `.env` → `API_BASE_URL` |
| Credentials | **shared_preferences** | Local only |

## Features

- Folder-based browsing that mirrors the server's filesystem structure
- All-tracks list with local search
- Streaming with background playback, seeking, and gapless-style advance
- Manual queue (add / remove / reorder), plus shuffle and repeat (off / all / one)
- ReplayGain volume normalization — attenuate-only, clipping impossible
- Caching: on-disk library cache for instant cold start, Android on-disk stream
  cache (seekable replay, 2 GB cap), cover-art prefetching
- Automatic recovery from mid-stream connection drops
- Lock screen / notification controls (Android); SMTC + keep-awake (Windows)
- Android TV UI with remote navigation, auto-detected via `UiModeManager`

## Authentication

Subsonic token auth: every request carries a fresh random salt and
`token = MD5(password + salt)` — the password itself is never sent. Credentials
live in `SharedPreferences` on the device.

**There is no in-app signup.** Users are created in the Navidrome web UI. That's
a deliberate consequence of having no backend: the client has nothing to register
against.

## Infrastructure dependency

Navidrome runs as a Docker service on the **fox-core** Hetzner VPS, managed by
Coolify:

- **URL:** `https://navidrome.foxcore.dev`
- **Music volume:** `/mnt/music` — a Hetzner Storage Box mounted via CIFS,
  bind-mounted read-only into the container as `/music`

The app is useless without a reachable Navidrome instance; there is no offline
library mode (the caches accelerate a working setup, they don't replace it).

## Current state

**Implemented:** browsing, search, streaming, queue, shuffle/repeat, ReplayGain,
library + stream + cover caching, drop recovery, Android TV UI, Windows SMTC and
wakelock, Windows installer.

**Remaining / known gaps:**
- No automated tests beyond the default `test/widget_test.dart` scaffold.
- iOS is scaffolded but never distributed (needs an Apple Developer account).
- Library cache is a single file per install, wiped on logout — no per-account
  scoping, so switching users rebuilds from a full scan.

## Source

- Repo: `https://github.com/Raposo06/Anywhere-Music-Player`
- Related: [Foxcore Infrastructure](https://wiki.foxcore.dev/infrastructure) ·
  [Docker & Coolify](https://wiki.foxcore.dev/infrastructure/coolify)
