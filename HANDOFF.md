# Handoff — `gonic-migration` branch

> Working notes for picking this up in a fresh session. **Transient**: delete
> this file once the branch is merged. The durable record is
> [docs/decisions.md](docs/decisions.md) — read that first, it has the *why*.

Branch: `gonic-migration`, cut from `main` at `0482fc3`.
Status: **analyze clean, 363/363 tests passing**, verified against the live
server. Not pushed. Not merged.

---

## What this branch does

Two things, one commit each.

### 1. Migrated the server from Navidrome to Gonic

The app pointed at Navidrome and used **Navidrome's native REST API**
(`POST /auth/login` → paginated `GET /api/song`) to fetch the whole library,
because Navidrome only exposes tag-based browsing over Subsonic and the app
browses by folder. Gonic implements none of that — the scan failed on every
launch.

Gonic is folder-native, so the workaround is gone rather than ported:
`SubsonicApiService.getAllTracksByFolder()` walks
`getMusicFolders` → `getIndexes` → `getMusicDirectory` breadth-first, 8
directories per round trip.

Non-obvious decisions (full reasoning in `docs/decisions.md`):

- **Track paths are synthesized from the walk**, not read from the song's own
  `path` field. The walk knows what it descended through; the server's `path`
  is relative to a music folder it needn't agree with. This is now item 4 in
  `CLAUDE.md`'s do-not-simplify list.
- **The music folder's name enters the path only when there's more than one.**
  With a single folder, paths stay relative to the music root — the shape the
  folder tree, on-disk cache and Now Playing folder line were all built around.
- **`LibraryCache._version` 4 → 5.** The schema didn't change; the *ids* did.
  Song ids are server-assigned, so a Navidrome-era cache hydrates rows that look
  playable and fail on tap.
- **Now Playing shows the full folder path again.** It used to drop the first
  segment, which was correct when everything sat under one `SOUNDTRACKS` root.
  Gonic's tree has 5 sibling categories, so that rule was discarding real
  information and blanking the line entirely for tracks sitting directly inside
  a category folder.

`Track.fromNativeApi` and the native-API methods were **deleted** — recover from
git history rather than re-deriving if a tag-based server ever comes back.

### 2. Trimmed the desktop footprint

Measured against a bare Flutter counter app built from the same SDK:

| | RSS | PSS | Private |
|---|---|---|---|
| Bare Flutter app | 330 MB | 139 MB | **84 MB** |
| This app, library loaded | 530 MB | 272 MB | **216 MB** |

84 MB is Flutter's floor. The 132 MB above it is ours, and the biggest single
identifiable piece was libmpv's demuxer cache: `just_audio_media_kit` defaults
it to **32 MB** (a video-sized buffer) and we never overrode it.

- `JustAudioMediaKit.bufferSize = 8 << 20` in `main()`, before
  `ensureInitialized()`.
- Dropped `cupertino_icons` (imported in **zero** files, shipped a 252 KB font)
  and `json_annotation` + `json_serializable` + `build_runner` (no `.g.dart`
  files, no `part` directives — the models hand-write their JSON).
- `assets:` now lists files individually. It named the `assets/icons/`
  *directory*, which shipped the launcher-icon sources (`psx.png`, `psx.ico`) to
  every user.
- The four Windows-taskbar `.ico` files re-exported as multi-size icons
  (48/32/24/16). `next.ico` alone was 330 KB for a button Windows draws at
  16–24 px.

`flutter_assets`: **2.4 MB → 1.7 MB**. Bundle: 28 MB → 27 MB.

---

## Verified against the live server (2026-09-08)

`https://gonic.foxcore.dev` — `type: gonic`, `serverVersion: 0.22.0`,
Subsonic API `1.15.0`, `openSubsonic: true`.

| Measured | Value |
|---|---|
| Music folders | 1 (`music`) — so no name prefix in paths |
| Top-level directories | 5: `ANIMES & ANIMATIONS`, `GAMES`, `MIXES & COMPILATIONS`, `MOVIES & SERIES`, `SPECIALS` |
| Directories / songs | 239 / 4,384 |
| Full scan | ~7.5 s at 8 concurrent fetches |
| `path`, `suffix`, `duration`, `size`, `created`, `artist`, `album` | present on 100% of songs |
| `replayGain.trackGain` | **present on only 3%** (112 of 4,384) |
| Playlists / starred songs | 0 / 0 |

---

## Pick up here

### Must do before shipping

1. **Log out and log back in, on every device.** `API_BASE_URL` only pre-fills
   the login screen's server field. The URL actually used is the one stored in
   `flutter_secure_storage` at login, read on every launch by
   `AuthService.initialize`. An install that is already logged in keeps talking
   to Navidrome and **never errors**, because that server is still up. Logout
   clears the credentials *and* the library cache.

2. **Verify the taskbar icons on Windows.** They were resized on Linux and
   include every size the thumbnail toolbar can ask for, so a regression is
   unlikely — but it is unverified. Originals are recoverable from git history.

3. **Never put credentials in `.env` again.** `pubspec.yaml` lists `.env` as a
   Flutter asset, so the whole file is baked into every APK and desktop bundle.
   The app only ever reads `API_BASE_URL`; credentials come from the login
   screen. (A `USERNAME`/`PASSWORD` pair was added locally to verify the walk
   and has been removed. `.env` is gitignored, so nothing leaked to the repo.)

### Worth doing

4. **Re-measure memory.** The 8 MB buffer change should land around ~190 MB
   private, down from 216 MB. Not yet confirmed:
   ```bash
   flutter build linux --release
   ./build/linux/x64/release/bundle/anywhere_music_player &
   # find the real pid — pgrep matches the launcher shell too:
   for p in $(ls /proc | grep -E '^[0-9]+$'); do
     case "$(readlink /proc/$p/exe 2>/dev/null)" in *anywhere_music_player) echo $p;; esac
   done
   awk '/^Rss:|^Pss:|^Private_Clean|^Private_Dirty/{print}' /proc/<pid>/smaps_rollup
   ```
   If rebuffering shows up during playback, raise `bufferSize` to 16 MB before
   going back to 32.

5. **Decide on the image cache.** Capped at 50 MB / 300 entries in `main.dart`.
   That is a *ceiling, not an allocation*, so lowering it only helps if it is
   actually being hit — log `imageCache.currentSizeBytes` after a long library
   scroll first.

6. **Dependency pins are behind.** `just_audio` 0.9.40 (latest 0.10.6),
   `smtc_windows` 0.1.3 (latest 1.1.0). More importantly,
   **`just_audio_media_kit` was last published 513 days ago** and is the
   desktop-critical link in the audio chain. If it breaks against a Flutter
   release, that is the forcing function for a stack change — see the framework
   discussion summarised below.

### Deliberately not done

- **`getTopLevelFolders()` is called twice per `build()`** in
  `desktop_library_screen.dart` (lines ~187 and ~210) and again in
  `home_screen.dart:317`, recomputing `totalTrackCount` each time. That is ~500
  node visits across 239 directories — genuinely negligible. Memoise
  `totalTrackCount`/`coverArtId` onto `_FolderNode` during `_buildFolderTree`
  only if the library grows by an order of magnitude.
- **ReplayGain.** Inactive for 97% of the library because Gonic doesn't tag it.
  The client handles a null gain correctly (no attenuation — the safe
  direction). Fixing it is a server-side tagging job: write
  `REPLAYGAIN_TRACK_GAIN` into the files and rescan. Noted as non-critical.
- **All Tracks.** Was a Navidrome smart playlist (`all-tracks.nsp`), not app
  code. Gonic has no smart playlists — its playlists are m3u files under
  `GONIC_PLAYLISTS_PATH` named `<userid>/<name>.m3u`. Recreate there if wanted.

---

## Framework question — settled

A long evaluation of migrating the desktop app off Flutter (Qt, Slint, Tauri)
concluded: **don't migrate.** Moved out of this file and into
[docs/decisions.md](docs/decisions.md) on 2026-09-09, since this file gets
deleted at merge and that is exactly the knowledge that shouldn't die with it.
