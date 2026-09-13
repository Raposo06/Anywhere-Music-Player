# Anywhere Music Player

> **Maintenance:** kept in sync from the repo. Updated when something
> *meaningful* changes (architecture, stack, platform support, major features,
> or implemented/remaining status) — not on every commit. Migrated from WikiJS
> (`projects/anywhere-music-player`) on 2026-08-17 so the docs live next to the
> code they describe. Last reviewed: 2026-09-08.

Self-hosted, cross-platform music streaming: **write once (Flutter), host
anywhere (Gonic), play on the desktop**. A private client for a personal music
library — no accounts to create, no catalogue but your own.

## Index

- [Decisions](decisions.md) — **the decision log.** Why sequencing is manual,
  why the Windows audio backend was swapped, why Android was dropped. Read
  before "simplifying" any of it.
- [Operations](operations.md) — building, running, releasing, and the traps
  that have cost time.

## Architecture

```
┌────────────────────────────────────────┐
│            Flutter App                 │
│         Windows │ Linux (Arch)         │
└──────────────────┬─────────────────────┘
                   │ Subsonic API (/rest/*)
                   ▼
┌────────────────────────────────────────┐
│           Gonic Server                 │
│       https://gonic.foxcore.dev        │
│  • Scans & indexes the music path      │
│  • Keeps the real folder tree intact   │
│  • Serves audio streams & cover art    │
│  • User management                     │
│  • Subsonic API implementation         │
└──────────────────┬─────────────────────┘
                   │ read-only bind mount
                   ▼
   /mnt/storagebox/music — Hetzner Storage Box
        (CIFS mount on the fox-core VPS)
```

The app talks **exclusively** through the Subsonic API. The server owns
scanning, metadata, user management, streaming and cover art — the client
deliberately has no backend of its own.

The server is **Gonic**, which is folder-native: it stores the real directory
tree rather than deriving one from tags. That is why the library scan is a
`getIndexes`/`getMusicDirectory` walk and not a whole-library fetch — see
[decisions](decisions.md), "Migrated from Navidrome to Gonic".

The walk finds the songs; the **folder tree comes from each song's `path`**, not
from the directories the walk descended. `getIndexes` has been observed
returning a tag-shaped artist index on this server, and the tree has to be the
on-disk one regardless — see "The song's own `path` decides the folder tree".

### Subsonic endpoints used

| Function | Endpoint |
|---|---|
| Auth check | `GET /rest/ping` |
| Browse library | `GET /rest/getMusicFolders`, `/rest/getIndexes`, `/rest/getMusicDirectory` — walked recursively to find every song. Each song's **own `path` field** is what the browsable folder tree is rebuilt from, because the walk is only as folder-shaped as `getIndexes`. See [decisions](decisions.md) |
| Search | `GET /rest/search3` |
| Stream audio | `GET /rest/stream?id=X` |
| Cover art | `GET /rest/getCoverArt?id=X` |
| Now playing / scrobble | `GET /rest/scrobble?id=X&submission=false\|true` |
| Favourites | `GET /rest/star`, `/rest/unstar`, `/rest/getStarred2` — songs only, see [decisions](decisions.md) |
| Playlists | `GET /rest/getPlaylists`, `/rest/getPlaylist`, `/rest/createPlaylist`, `/rest/updatePlaylist`, `/rest/deletePlaylist` |

## Platform support

| Platform | State |
|---|---|
| Windows | Shipped — Inno Setup installer (`installer.iss`), published by CI |
| Linux | Shipped — Arch package only (`pacman -U`), published by CI. Needs the system's libmpv, see [operations](operations.md) |
| Android (phone, TV) | **Removed 2026-09-13.** Was a target; dropped from releases on 2026-09-09 and from the tree four days later. `android/` is gone — see [decisions](decisions.md) |
| iOS, macOS | **Removed 2026-09-13** with Android. Were Flutter scaffolding, never built |
| Web | **Not supported** — there is no `web/` directory |

Tagged releases (`v*`) are built for Windows and Linux and published to GitHub
Releases by `.github/workflows/release.yml`, with a hosted download page on
foxcore.dev pointing at the latest — see [operations](operations.md) and
[decisions](decisions.md) (2026-09-01).

> ⚠️ The README and the old WikiJS page both listed **Web** as a target. That was
> never true in this tree; corrected 2026-08-17. The Windows audio backend
> (media_kit/MPV) is desktop-native and would not carry to web regardless.

## Stack

| Layer | Tech | Notes |
|---|---|---|
| App | **Flutter** | SDK `>=3.8.0 <4.0.0`; version `1.0.0+2` |
| Audio | **just_audio** | `just_audio_media_kit` (MPV), streaming direct from the server — see [decisions](decisions.md) |
| Windows media keys | **smtc_windows** | System Media Transport Controls |
| Linux media keys | **dbus** | Hand-rolled MPRIS server — see [decisions](decisions.md) |
| State | **provider** | |
| Theme | Hand-rolled `ThemeData` | `lib/theme/` — warm off-black + one teal accent; tokens converted from the design's OKLCH values, see [decisions](decisions.md) |
| Fonts | **Work Sans**, **Source Serif 4** | Bundled static TTFs in `assets/fonts/` (OFL). Serif for titles and track names, sans for everything else |
| Server | **Gonic** | Subsonic API implementation, folder-native browsing. `serverVersion` 0.22.0, API 1.15.0, OpenSubsonic enabled (check yours with `/rest/ping.view`) |
| Config | **flutter_dotenv** | Runtime `.env` → `API_BASE_URL` |
| Credentials | **flutter_secure_storage** | Encrypted, local only. `shared_preferences` is a one-time legacy migration source, not an active store |

## Features

- Desktop (Windows/Linux) shell: app-drawn title bar, sidebar navigation,
  folder grid, docked mini player, and a full-window Now Playing with a
  permanent "Up Next" queue panel
- Folder-based browsing that mirrors the server's filesystem structure
- All-tracks list with local search, reached from the top of Playlists
- Streaming with background playback, seeking, and gapless-style advance
- Manual queue (add / remove / reorder), plus shuffle and repeat
  (off / all / one), both persisted across restarts
- ReplayGain volume normalization — attenuate-only, clipping impossible
- Caching: on-disk library cache for instant cold start — and, while that cache
  is under six hours old, a launch renders from it and skips the folder walk
  entirely (the header refresh button and any Retry force the walk);
  cover-art prefetching
- Scrobbling: plays are reported back to the server (past half the track or
  four minutes), so the server's play counts and "recently played" reflect this
  app; a "now playing" announcement drives its live panel
- Desktop keyboard shortcuts: space, arrow-key seek/volume, Ctrl+arrow skip,
  Ctrl+F to focus search,
  Alt+← (or Escape) to go back a folder or playlist / leave Now Playing — the
  title bar's back chevron does the same thing for the mouse
- Playlists: create, rename, delete, add and remove tracks on
  server-side playlists — stored by the server, so anything else pointed at it
  sees the same lists. Reordering is not supported, see
  [decisions](decisions.md)
- Favourites: star songs from any track row, the mini player or Now Playing,
  with a dedicated sidebar list. Server-side, so it stays in sync with anything
  else pointed at the same server
- Automatic recovery from mid-stream connection drops
- SMTC + keep-awake (Windows); MPRIS media keys (Linux)

## UI layout

One shell. `AuthWrapper` renders `DesktopShell` (`screens/desktop/desktop_shell.dart`)
once logged in: a 224px sidebar (Library / Favourites / Playlists) with a nested
navigator per drill-down destination, and a full-window `DesktopPlayerScreen`
with a docked "Up Next" panel pushed on the root navigator. Everything below
the widget layer — `AudioPlayerService` with `PlaybackCursor` and
`PlaybackPolicy`, `LibraryScanner` with its `FolderWalk`/`FolderTree`,
`CoverArt` — never imports a widget.

Until 2026-09-13 there were three layouts (this one, a phone tab bar, an
Android TV D-pad screen) over the same services; the other two went with
Android — see [decisions](decisions.md).

The desktop shell owns the window: `main()` hides the native frame on
Windows/Linux, so `WindowChrome` is the only way to move, maximise or close the
window, and every desktop screen renders one — including login, via
`DesktopWindowFrame`.

## Authentication

Subsonic token auth: every request carries a fresh random salt and
`token = MD5(password + salt)` — the password itself is never sent. Credentials
live in `flutter_secure_storage` (encrypted) on the device. Older installs that
still had them in `SharedPreferences` get migrated automatically on the next
launch, then the legacy copy is deleted.

`AuthService` owns the `SubsonicApiService` and **disposes it on logout**, so
anything holding the old client answers the next request with "Client is already
closed". Modules whose lifetime is one session — `LibraryScanner`,
`PlaylistsService`, `FavouritesService` — therefore extend `SessionScoped` and
are provided through `sessionScoped()` in `main.dart`, which rebuilds them
whenever the client identity changes and keeps them otherwise.

**There is no in-app signup.** Users are created in Gonic's own admin web UI.
That's a deliberate consequence of having no backend: the client has nothing to
register against.

## Infrastructure dependency

The server is **Gonic**, reachable at `https://gonic.foxcore.dev`: `type: gonic`,
`serverVersion: 0.22.0`, Subsonic API `1.15.0`, `openSubsonic: true`.

Everything below is a **runtime fact about one deployment**, measured on
2026-09-08 by walking the live server. Re-measure rather than assume — the
figures move as the library does. `curl "$API_BASE_URL/rest/ping.view?..."` is
the fastest first check.

| Measured | Value |
|---|---|
| Music folders | 1, named `music` — so the walk leaves it out of every path |
| Top-level directories on disk | 5: `ANIMES & ANIMATIONS`, `GAMES`, `MIXES & COMPILATIONS`, `MOVIES & SERIES`, `SPECIALS` |
| What `getIndexes` returned on 2026-09-09 | 285 artist-shaped entries, **not** those 5 — the reason the tree is built from `path`. Re-check before trusting either shape |
| Loose songs at the music root | 0 |
| Directories total | 239 |
| Songs total | 4,384 |
| Full scan wall clock | ~7.5 s at 8 concurrent directory fetches — skipped on launch while the library cache is younger than `LibraryScanner.cacheFreshFor` |

Field coverage on song responses, which is what the client can actually rely on:
`path`, `suffix`, `duration`, `size`, `created`, `artist`, `album` are present on
100%; `coverArt` on all but one track; `track` on 67% and `year` on 74%.
**`replayGain.trackGain` is present on only 3%** — see below.

- **Hosting.** The Navidrome instance this replaced ran as a Docker service on
  the **fox-core** Hetzner VPS under Coolify, with the music volume at
  `/mnt/storagebox/music` — a Hetzner Storage Box over CIFS
  (`//u612406.your-storagebox.de/backup` at `/mnt/storagebox`, per `/etc/fstab`),
  bind-mounted read-only into the container. **Not re-verified for the Gonic
  deployment** — only the Subsonic surface above was. If the CIFS mount is still
  in the picture, the `nofail` trap in `docs/operations.md` still applies: when
  it doesn't come up, the library reads as empty rather than erroring.
- **ReplayGain is effectively inactive.** 112 of 4,384 tracks carry a track gain;
  the rest send `replayGain: null`. The client handles that correctly — no gain
  means no attenuation, which is the safe direction — but volume normalization
  is not doing anything for 97% of this library. Fixing it is a server-side
  tagging job (write `REPLAYGAIN_TRACK_GAIN` into the files, then rescan), not a
  client change.
- **No playlists and no starred songs exist on this server.** Both features work;
  there is simply nothing in them yet. Under Navidrome, **All Tracks** was a
  smart playlist (`all-tracks.nsp`) rather than app code — Gonic has no smart
  playlists, its playlists are m3u files under `GONIC_PLAYLISTS_PATH` named
  `<userid>/<name>.m3u`, so that entry is gone until an equivalent is created
  there.
- **Library layout.** Gonic asks that all files in a folder belong to one album,
  and that one album not span folders. This library keeps loose tracks directly
  inside top-level category folders and browses fine regardless; the rule is
  about how cleanly albums group, not a hard parse requirement.

The app is useless without a reachable server; there is no offline library mode
(the caches accelerate a working setup, they don't replace it).

## Current state

**Implemented:** browsing, search, streaming, queue, shuffle/repeat, ReplayGain,
playlists (create, fill by search, reorder-free add/remove, rename, delete),
library + cover caching, drop recovery, Windows SMTC and wakelock, Windows
installer, Linux MPRIS media keys, Arch packaging (PKGBUILD), the desktop
redesign (theme + sidebar shell + custom window chrome), scrobbling, desktop
keyboard shortcuts, favourites, and playlists.

**Test suite:** 30 test files under `test/` (~7,100 lines including support
fakes) covering the models, services, the screens and the shared widgets.
Playback is exercised against a fake `just_audio` platform
(`test/support/fake_just_audio.dart`) rather than a live backend. Sequencing
(playlist/queue/shuffle/repeat) lives in `PlaybackCursor`, a pure Dart class
with no player or Flutter dependency, tested directly rather than through
seams on `AudioPlayerService`; "what tells the OS this is playing"
(`NowPlayingPresence`), "what's the URL for this track" (`StreamUrlResolver`),
and "what the server's directory tree looks like" (`LibraryBrowser`) are
similarly pulled out into their own seams, each with a no-op/throwing/in-memory
test default so nothing in the suite needs a real platform channel. Run with
`flutter test`. **This does not replace running the app** — the fake player
does not exercise media_kit, and the presence layer (SMTC, MPRIS) is only
reachable on the real OS.

**Remaining / known gaps:**
- *Screen* test coverage is thin: the playlists screens and the shell are
  covered, but the library, folder and player screens are not. The widget
  tests cover the shortcuts, the favourite heart and the track row; `test/`
  otherwise covers the services.
- Playlists cannot be reordered — Subsonic has no reorder parameter, so it
  means rewriting the whole playlist plus a drag surface.
- Library cache is a single file per install, wiped on logout — no per-account
  scoping, so switching users rebuilds from a full scan.

## Source

- Repo: `https://github.com/Raposo06/Anywhere-Music-Player`
- Related: [Foxcore Infrastructure](https://wikijs.foxcore.dev/infrastructure) ·
  [Docker & Coolify](https://wikijs.foxcore.dev/infrastructure/coolify)
