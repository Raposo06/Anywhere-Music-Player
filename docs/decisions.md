# Decisions

> **Append-only log.** One entry per decision that was *reversible and actually
> debated* — the ones where a future reader (human or agent) would otherwise
> re-litigate settled ground, or silently undo something load-bearing. Newest
> first. Never rewrite an entry: if a decision is reversed, add a new entry and
> mark the old one **Superseded**.
>
> Seeded 2026-08-17 from rationale already written into the code — most of these
> were recovered from doc comments in `lib/services/`. Dates are approximate
> where the original decision predates this log.

Each entry: **what was decided**, **why**, and **what would reverse it**.

---

## The library scan is three modules: FolderWalk, FolderTree, LibraryScanner (2026-09-09)

**Decided.** Split what had become one 700-line transport class and one
410-line `ChangeNotifier` into three single-purpose modules:

- **`FolderWalk`** (`lib/services/folder_walk.dart`) — the breadth-first
  directory walk (cycle guard, concurrency batching) and the path-resolution
  policy (`_pathOf`/`_isAbsolute`/`_joinPath`/`_fileNameOf`). Takes a
  `LibraryBrowser`, run via `.run()`.
- **`LibraryBrowser`** (`lib/services/library_browser.dart`) — a 3-method
  interface (`getMusicFolders`/`getIndexes`/`getMusicDirectory`) covering the
  whole of what `FolderWalk` needs from a server. `SubsonicApiService`
  implements it; a `FakeBrowser` in tests is the second adapter that makes the
  seam real rather than hypothetical.
- **`FolderTree`** (`lib/services/folder_tree.dart`) — an immutable value
  built by `FolderTree.from(tracks)`: tree construction, cover-art
  inheritance, recursive counting/search, and the root-flatten rule (a
  library entirely under one top-level folder shows that folder's children
  as the top level instead). The rule used to be spelled out three separate
  times across `LibraryScanner`, each testing a slightly different condition
  on the same data; it is now one nullable field computed once at
  construction.
- **`LibraryScanner`** keeps only cache hydration, freshness, and
  `notifyListeners()` orchestration — it holds a `FolderTree` and exposes it
  via `tree`, plus one-line forwarders (`getTopLevelFolders`, `getRootTracks`,
  `getFolderContents`, `getAllTracksInFolder`, `searchFolders`,
  `isFlattenedRoot`, `trackById`) so the ~20 existing call sites across 7
  screen files didn't have to change in this pass.

**Why.** Neither the transport nor the tree-holding `ChangeNotifier` is the
right place for a breadth-first traversal or a path policy — before this,
testing "does this path land in the right tree node" required a fake HTTP
client, a fake path provider, a temp directory, and a `tearDown` retry loop
to dodge an un-awaited cache write. `FolderTree` needs none of that; it's
pure Dart tested with a list of paths in, a tree out.

`subsonic_api_service.dart`: 700 → 546 lines. `library_scanner.dart`:
410 → 202 lines. No behaviour changed; `flutter test` count went from 383 to
393 (nine tests moved to `folder_walk_test.dart`, nine pure ones added there
and in `folder_tree_test.dart`, two dead-parameter tests deleted as
unrelated cleanup — see the two `## 2026-09-09` entries below for that
cleanup).

**Deliberately not done in this pass:** the scanner's forwarders were not
retired in favour of `scanner.tree` at every call site — that's ~20 edits
across 5 screens, a util and a widget for zero behaviour change, and those
screens carry their own widget tests. New code should prefer `tree`
directly; existing call sites can move over per-file, at leisure.

**What would reverse it.** If the server ever grows a real "give me every
song" endpoint, `FolderWalk` is deleted whole rather than unpicked from the
transport again. Nothing foreseeable reverses `FolderTree` — a pure value
object built from a flat list is about as simple as this can get.

Also folded in, as prep rather than a decision of its own: `Track.fromSubsonic`'s
doc comment claimed the folder walk's path "is authoritative in a way the
server's `path` is not" — the exact opposite of what the path policy above has
done since the entry below. Rewritten to match, and its parameter renamed
`pathOverride` → `resolvedPath` since it no longer overrides anything. The
unrelated dead `parentFolderName` parameter and the test-only
`LibraryCache.load()` wrapper were also deleted — both had zero production
callers, kept alive only by their own tests.

See `docs/reviews/2026-09-09-c01-c02-work-order.md` for the full grilling and
step-by-step plan this was built from.

## Desktop cannot use LockCachingAudioSource; it renames an open file (2026-09-09)

**Decided.** Windows and Linux go back to `DirectStreamCache`, hours after being
moved to `DiskStreamCache`. The disk cache and the next-track prefetch it enables
are **Android-only**. `StreamCache.prefetch`, the 50 MB cap and every test stay —
on desktop `prefetch` is simply the documented no-op.

**Why — measured, not reasoned.** The move rested on one assumption:
`LockCachingAudioSource` is plain Dart serving bytes over a loopback
`HttpServer`, so media_kit should not care. `flutter test` cannot exercise
media_kit, so this was shipped explicitly unverified. A standalone Flutter
Windows probe — real libmpv, real `LockCachingAudioSource`, a local origin
server serving a synthesized WAV — then ran both scenarios:

| Scenario | Result |
|---|---|
| Play through the cache, no prefetch | **plays** — load 24 ms, duration 5000 ms, position advanced to 1475 ms |
| Prefetch (`request(0, 1)`) then play | **`setAudioSource` never completes** — 15 s timeout, `stream: Failed to open http://127.0.0.1:…` |

In *both* cases the cache file never materialised — `<id>.part` existed,
`<id>` did not — with an unhandled:

```
PathAccessException: Cannot rename file to '…	rackid',
  path = '…	rackid.part'  (OS Error: errno = 32, file in use)
  at LockCachingAudioSource._fetch (just_audio.dart:3165)
```

`_fetch` downloads to `<id>.part` and `renameSync`s it into place. POSIX permits
renaming a file that is still open; **Windows does not**. So on Windows the
cache never completes: every replay re-downloads, and the exception surfaces as
an unhandled async error. Adding a prefetch puts a second reader on the same
in-flight download and turns that silent failure into a hard one — nothing plays.

**Two things this corrects.** media_kit is *not* the problem: it played the
loopback proxy URL fine in the no-prefetch case, which was the risk actually
flagged. And Linux is untested — the fault is a Windows filesystem semantic, so
Linux probably behaves like Android, but "probably" is what this entry exists to
stop, so Linux reverts with Windows.

**What would reverse it.** just_audio fixing the rename on Windows (copy-then-
delete, or retry), which would need a version bump past the pinned 0.9.40. Or —
better, and independent of the package — desktop prefetching with a **plain HTTP
download we own**: fetch the next track to a temp file, close the sink, rename,
and hand media_kit a `file://` URI. That sidesteps the proxy and the experimental
API entirely, and we control when handles close. That is the shape to build if
desktop prefetch is wanted.

**What this cost, and the lesson.** The change was shipped with "unverified
against the real backend" written next to it three times, and was wrong. A
30-line probe app found it in one run. When a change rests on an assumption the
test suite structurally cannot reach, the probe *is* the test — write it before
shipping, not after.

---

## The next track is prefetched to disk; desktop joins the stream cache (2026-09-09)

**Decided.** Two changes, one mechanism:

1. `StreamCache` gains `prefetch(track, uri, tag)`. `DiskStreamCache` builds the
   next track's `LockCachingAudioSource` and calls `request(0, 1)` on it, which
   is what starts the download of the **whole** file; `DirectStreamCache` has
   nowhere to put bytes, so it is a no-op there.
2. Windows and Linux move from `DirectStreamCache` to `DiskStreamCache`. Only
   web still streams direct.

`AudioPlayerService._prefetchNext` fires it once the current track is loaded and
playing, guarded by the same `_loadToken` as the load.

**Why.** Every track change paid a full open — TLS handshake, first byte, demux
fill — over a Tailscale tunnel to Hetzner, with nothing warmed in advance. Cover
art was already precached for exactly this reason; the audio was not.

**Why not a second player.** The obvious shape is two `AudioPlayer`s ping-ponging
with the next track preloaded on the standby one. That was rejected: the exposed
`positionStream`/`playingStream` are read straight off `_player` by ~10 UI sites,
so a swap kills every live `StreamBuilder` unless they first become forwarded
broadcast streams, and all four presence implementations (Android, Windows,
Linux MPRIS, audio_service) hold the player from `bind()` and would need to
support rebinding. `LockCachingAudioSource` is plain Dart served over a loopback
`HttpServer`, so warming the *bytes* needs none of that and works on every
platform at once. Sequencing stays one-track-at-a-time (load-bearing item 1).

**The invariant this rests on.** Exactly one live source per cache file — two
race a truncating `openWrite` into `<id>.part` and corrupt what is playing. So
`prefetch` holds the instance in a one-slot field and `sourceFor` **takes** it,
emptying the slot; it never builds a second source for a warmed track. Eviction,
which runs after every load, now spares the warm track as well as the playing
one — otherwise each load deleted the prefetch it had just started.

**Bounded to 50 MB.** `LockCachingAudioSource` has no partial mode — asking for
one byte pulls the whole file — so an unbounded prefetch is a hazard rather than
a speed-up. Measured against the live library: mean track 6.5 MB, but 45 tracks
run past ten minutes and the largest is **277 MB** (a 112-minute mix). Starting
that behind a 3-minute opening would saturate the same tunnel the current track
is streaming over, and evict most of a 2 GB cache that only holds ~307 average
tracks to begin with. Over the cap, a track opens cold — exactly what every
track did before this existed.

**Cost.** Desktop playback now goes through just_audio's loopback proxy and
writes to the 2 GB on-disk cache. One track of read-ahead bandwidth is spent
even if the user stops before reaching it. Prefetching on load rather than near
the end of the track is deliberate: it is the longest head start, and the skip
debounce means a burst of Next warms only the track landed on, not every one
passed through.

**What would reverse it.** media_kit misbehaving against the loopback source on
some desktop configuration — then desktop goes back to `DirectStreamCache` and
loses prefetch with it, while Android keeps both. Wanting to spend less
bandwidth would move the trigger later (position-based) rather than remove it.

**Superseded the same day for desktop** — the reversal condition above fired on
first measurement. See "Desktop cannot use LockCachingAudioSource" below. The
prefetch seam, the 50 MB cap and the Android behaviour all stand; only the
desktop wiring was undone.

---

## libmpv's demuxer cache raised 8 MB → 16 MB (2026-09-09)

**Decided.** `JustAudioMediaKit.bufferSize = 16 << 20`. This partially reverses
the 8 MB set the day before in "Desktop footprint trimmed" (2026-09-08), which
stands otherwise — the dropped dependencies and re-exported icons are unaffected.

**Why.** 8 MB made tracks visibly slower to start on Windows. The 2026-09-08
reasoning — "this app streams audio, where 8 MB is minutes of buffer" — was
right about duration and wrong about what the cache is doing on this link. The
server is reached over a Tailscale tunnel to Hetzner, so what matters is not how
many minutes fit but how often libmpv goes back to the network for the next
chunk. A smaller cache means more, smaller reads over a high-latency path.

**How it was isolated.** The user rebuilt after a week on an old binary, so the
suspect list was every change in between. Diffing the two commits over the
playback files left exactly one functional change — the buffer — with the other
two diffs comment-only (`Navidrome` renamed to `the server`). The forced v6
rescan was a candidate confounder and was already spent on an earlier launch, so
the observation was clean.

**Cost.** ~8 MB resident against a ~216 MB private baseline.

**What would reverse it.** A deployment on a low-latency link (the server on the
LAN) where 8 MB starts tracks just as fast — then the memory is worth reclaiming.
Measure start latency before moving it; don't tune it from the duration
arithmetic, which is what got 8 MB chosen in the first place. 32 MB is
libmpv's default and the next step up if 16 still stutters.

---

## The song's own `path` decides the folder tree, not the walk (2026-09-09)

**Decided.** `getAllTracksByFolder` now reads each track's library path from the
song's own `path` field, and only synthesizes one from the descent when the
server's is unusable. This **reverses** point 1 of the Gonic migration entry
(2026-09-08) and item 4 of `CLAUDE.md`'s do-not-simplify list.

**Why — what the old rule assumed, and how it failed.** Synthesizing was
supposed to guarantee the tree matched the directories actually browsed. It
does. The unexamined premise was that those directories are the *on-disk* ones,
and that is only true if `getIndexes` answers with folders.

This server's did not. The library cache written 2026-09-09 08:37 held 4,384
tracks — the right count, from the right server — with paths like:

```
5050/One Piece/01-Jungle P.mp3
7!!/Naruto Shippuden Opening Theme/01-Lovers.mp3
[Unknown Artist]/[Unknown Album]/1 Hour of Relaxing Rainy Night...
```

285 distinct top-level segments, and **zero** tracks under any of the five real
top-level directories (`ANIMES & ANIMATIONS`, `GAMES`, `MIXES & COMPILATIONS`,
`MOVIES & SERIES`, `SPECIALS`). Those segments are artists, and `[Unknown
Artist]`/`[Unknown Album]` are placeholders Gonic generates for untagged files —
no directory on disk is named that. The walk faithfully reproduced a tag-shaped
index. Folder browsing was showing a tag tree, which is the one thing the move
off Navidrome was meant to stop.

Note this contradicts the 2026-09-08 verification in this log, which measured 5
top-level directories over the same 4,384 songs. Same server, same library,
different shape — unexplained, and the reason the new rule is written not to
care which shape `getIndexes` returns.

**Why `path` is the better source here.** It is the on-disk tree, stated by the
server per song, and it does not depend on how the index is built. The same
2026-09-08 check found it present on 100% of song responses.

**The two fallbacks, and why they exist.**

- **Absent or empty** — the Subsonic spec does not require `path`.
- **Absolute** (`/mnt/storagebox/music/…`) — a filesystem path whose library
  root this client cannot know, so no prefix is safe to strip. Navidrome sent
  these; that is the case the walk was originally built for, and it is still
  the right answer for it.

Both fall back to the walked path, so a server that behaves the way the old rule
assumed still works exactly as before.

**What would reverse it.** A server whose `path` is relative to a music folder
that disagrees with the browse tree — the original worry, now handled for the
absolute case but not for a mismatched relative root. If that appears, the fix
is to make the source per-server rather than to flip the rule back.

---

## Stay on Flutter; the desktop-rewrite evaluation is closed (2026-09-09)

**Decided.** No migration off Flutter. Qt, Slint and Tauri were all evaluated
against the desktop build and all rejected. Recorded here rather than only in
`HANDOFF.md`, which is transient and gets deleted at merge — the question was
already asked a second time in a later session, which is what a decision log is
supposed to prevent.

**Why.**

- **The 216 MB private RSS is real and not constraining.** 84 MB of it is
  Flutter's floor; the rest was addressable from inside Flutter, and the
  demuxer-cache fix took the largest piece of it without a framework change.
- **The one live capability gap didn't matter.** libmpv's `replaygain`/`af`
  options are sealed behind `just_audio_media_kit`, which holds the media_kit
  `Player` as a private field. That would be a real wall if ReplayGain were
  critical — it isn't, because Gonic tags it on 3% of the library.
- **The ecosystem advantage doesn't cover this app.** Rust's edge is
  concentrated at the audio/OS-integration boundary (`souvlaki`, `libmpv2`,
  `symphonia`). It does not extend to the Subsonic layer — the best Rust client
  crate has 830 lifetime downloads against 651 tested lines here — and cover-art
  loading would get *worse* than `cached_network_image`.
- **Tauri specifically ships a browser engine** (WebKitGTK / WebView2), so it
  does not improve the memory number. Its "native Wayland" pitch is not a
  differentiator: this app already runs as a native Wayland client under
  Hyprland (`xwayland=False`, verified via `hyprctl clients`).
- **Android and Android TV are not in scope for any of the alternatives**, and
  they are two of the four targets. A desktop-only rewrite buys a second
  codebase for the same feature set; a full rewrite gives up the TV D-pad focus
  story, which is the hardest thing here to re-earn.

**What would reverse it — and what wouldn't.** The forcing function is
`just_audio_media_kit` breaking against a Flutter release: it was last published
513 days ago and is the desktop-critical link in the audio chain. But that is an
argument for replacing *that package*, not the framework. The exposed surface is
about twenty members of `AudioPlayer` (`setAudioSource`, `play`, `pause`, `stop`,
`seek`, `setVolume`, `setSpeed`, `setLoopMode`, and the state/position/buffered
streams), all funnelled through `AudioPlayerService` — small because sequencing
is hand-rolled in Dart and `ConcatenatingAudioSource` is unused. Driving
media_kit's `Player` directly, or forking the shim, is days of work against
months for a rewrite. Reconsider the framework only if a *second* capability wall
appears that actually matters. Qt or Slint would be the picks; not Tauri.

---

## Desktop footprint trimmed; libmpv's demuxer cache bounded to 8 MB (2026-09-08)

**Decided.** Four changes, all aimed at memory and bundle size:

1. `JustAudioMediaKit.bufferSize = 8 << 20`, set in `main()` before
   `ensureInitialized()`. The package default is **32 MB**.
2. `cupertino_icons` and `json_annotation` dropped as dependencies, along with
   the `json_serializable` / `build_runner` dev deps.
3. `assets:` lists files individually instead of the `assets/icons/` directory.
4. The four Windows-taskbar `.ico` files re-exported as multi-size icons
   (48/32/24/16) instead of single 128×128 — and `next.ico`, which also carried
   a 256×256 frame.

**Why.** Measured against a bare Flutter counter app built from the same SDK:

| | RSS | PSS | Private |
|---|---|---|---|
| Bare Flutter app | 330 MB | 139 MB | **84 MB** |
| This app, library loaded | 530 MB | 272 MB | **216 MB** |

84 MB is Flutter's floor and not addressable from here. The 132 MB above it is,
and the demuxer cache was the largest single identifiable piece of it: 32 MB is
a video-sized buffer, while this app streams audio, where 8 MB is minutes of
lookahead.

The rest is bundle hygiene worth roughly 800 KB of 28 MB — trivial in isolation,
but all of it was pure waste: `cupertino_icons` was imported in **zero** files
while shipping a 252 KB font; `json_annotation` likewise zero, with no `.g.dart`
file or `part` directive anywhere (the models hand-write their JSON); the
launcher-icon sources were being shipped to users because the asset list named a
directory; and `next.ico` alone was 330 KB for a button Windows draws at 16–24
px.

**What would reverse it.** Rebuffering during playback that `DropRecovery` ends
up catching — raise `bufferSize` to 16 MB and re-measure before going back to
32. Adopting `json_serializable` for the models would bring back its three
dependencies. Adding a runtime asset means adding it to the now-explicit list;
a missing asset fails at load, not at build, so that list is a maintenance
edge — accepted deliberately to stop shipping build-time sources.

**Not done.** The image cache cap (50 MB / 300 entries) was left alone: it is a
ceiling, not an allocation, and lowering it only helps if it is actually being
hit. Log `imageCache.currentSizeBytes` after a long library scroll before
touching it. `getTopLevelFolders()` is also still called twice per build in
`desktop_library_screen.dart` and recomputes `totalTrackCount` each time — ~500
node visits across 239 directories, genuinely negligible at this size, worth
memoising only if the library grows by an order of magnitude.

---

## Now Playing's folder line shows the full path again (2026-09-08)

**Decided.** `nowPlayingFolderPath` returns `canonical.folderPath` unchanged. It
no longer drops the first segment. The line still hides when a track has no
folder at all.

**Why.** The rule it reverses was sound for the library it was written against:
everything sat under one `SOUNDTRACKS` root, so the first segment was a constant
and showing it was pure noise. The move to Gonic reshaped the tree — that root is
gone, and the top level is now five sibling categories (`ANIMES & ANIMATIONS`,
`GAMES`, `MIXES & COMPILATIONS`, `MOVIES & SERIES`, `SPECIALS`). Against that
shape the same rule does real damage:

- it discards the category, which is now discriminating rather than constant —
  `ANIMES & ANIMATIONS/Bleach/…` displayed as `Bleach/…`, one level less context
  than the *old* library showed for the same track; and
- it blanks the line entirely for the 9 tracks that sit directly inside a
  category folder, since nothing survives the drop.

The 2026-08-31 entry named this exact situation as its reversal condition
("libraries that don't use a top-level category folder — there the dropped
segment would be meaningful"). This is that case, reached by the library moving
rather than by anyone changing their mind.

**What would reverse it.** A tree that grows a constant root again, or folder
lines proving too long in the phone player — the deepest paths here are four
segments. A last-two-segments rule was the considered alternative and is a
one-line change; it was rejected because it hides the category on deep tracks,
which is the information the full path was wanted for.

---

## Migrated from Navidrome to Gonic; the library scan is a folder walk (2026-09-08)

**Decided.** The server is now **Gonic** (`https://gonic.foxcore.dev`, verified
live: `type: gonic`, `serverVersion: 0.22.0`, Subsonic API `1.15.0`,
`openSubsonic: true`). The library scan changed with it:

- `getAllSongsNativeApi`/`_getNativeApiToken` are **deleted**. They drove
  Navidrome's native REST API (`POST /auth/login` for a JWT, then paginated
  `GET /api/song`), which Gonic does not implement at all — against Gonic they
  fail on every launch.
- `SubsonicApiService.getAllTracksByFolder()` replaces them: a breadth-first
  walk of `getMusicFolders` → `getIndexes` → `getMusicDirectory`, eight
  directories per round trip.
- `Track.fromNativeApi` is deleted; `Track.fromSubsonic` gained a
  `pathOverride`.
- `LibraryCache._version` 4 → 5.

**Why.** The native-API scan existed for one reason: Navidrome exposes only
tag-based browsing over Subsonic, so the real filesystem paths this app browses
by had to be scraped out of a non-Subsonic endpoint and reassembled into a
virtual tree. Gonic is folder-native — it keeps the tree intact and serves it
through the standard browse endpoints — so the workaround has nothing left to
work around. The app's folder-hierarchy browsing is now reading the server's
actual hierarchy rather than reconstructing one.

Four details that are load-bearing rather than incidental:

1. **Each track's path is synthesized from the descent, not read from the
   song's `path` field.** The walk knows which directories it went through; the
   server's `path` is relative to a music folder it doesn't have to agree with.
   Synthesizing guarantees the tree `LibraryScanner` rebuilds is the tree that
   was actually browsed. `path` is still consulted, but only for the file-name
   segment (falling back to `title` + `suffix`).
   **Superseded 2026-09-09** — reversed; see "The song's own `path` decides the
   folder tree" below. The premise that the walk is folder-shaped turned out to
   depend on `getIndexes`, which this server does not guarantee.
2. **The music folder's name is included in the path only when there is more
   than one.** With a single folder, paths stay relative to the music root —
   the shape the folder tree, the on-disk cache and Now Playing's folder line
   were all built around. With several, the name is the only thing telling two
   identically-named top-level directories apart.
3. **Results are sorted by path.** The walk finishes breadth-first, so the flat
   list would otherwise interleave depths. Path order is what the previous
   whole-library fetch produced (`_sort=path`) and what every list in the UI
   still expects.
4. **The cache version bump is about ids, not shape.** The serialized schema
   didn't change at v5. Song ids are server-assigned, so a cache written against
   Navidrome hydrates tracks whose ids mean nothing to Gonic — rows that look
   playable and fail on tap. Discarding is the only safe read of a cache from a
   different server.

**Cost.** A folder-native server answers one directory per request, so the scan
is now O(directories) round trips instead of O(library/500). The concurrency
window is the mitigation; if a large library scans too slowly, raise
`_walkConcurrency` before reaching for a different shape.

**What would reverse it.** Moving back to a tag-based server, or wanting
tag-based browsing (artist/album) as a real feature alongside folders — Gonic
serves the tag endpoints too, and they carry index data the filesystem walk
doesn't. Recover the deleted native-API methods and `Track.fromNativeApi` from
git history (the commit carrying this entry) rather than re-deriving them.

**Known follow-ups, not resolved here.**

- **ReplayGain** depends on the server sending `replayGain.trackGain` on song
  responses. `Track.fromSubsonic` already reads it; whether Gonic populates it
  for this library is a runtime fact — check a real response before assuming
  normalization is live. Absent the field it reads null, which means no
  attenuation, not a crash.
- **All Tracks** was a Navidrome smart playlist (`all-tracks.nsp`), not app
  code. Gonic has no smart playlists; its playlists are m3u files under
  `GONIC_PLAYLISTS_PATH`. The entry disappears until an equivalent is created
  server-side.
- **Playlist covers.** Navidrome generated a mosaic for every playlist; Gonic
  sends `coverArt` only when it has one, so the fallback glyph will be visible
  far more often.
- **Gonic constrains the library layout**: one album per folder, no album
  spanning folders. Not enforceable client-side.

**Update (2026-09-08, same day) — verified against the live server.** The walk
was run end to end with real credentials. It works: 1 music folder (`music`, so
no name prefix), 5 top-level directories, 239 directories, **4,384 songs, full
scan ~7.5 s** at 8 concurrent fetches. The round-trip cost flagged above is a
non-issue at this size.

Three of the four follow-ups are now settled:

- **`path` is present on 100% of song responses**, and is already the full
  library-relative path. The `title` + `suffix` fallback in `_fileNameOf` is
  therefore dead weight in practice — keep it anyway; it costs nothing and the
  Subsonic spec does not require `path`.
- **ReplayGain is effectively inactive**: `replayGain.trackGain` is present on
  112 of 4,384 tracks (3%); the rest send `replayGain: null`, which the parser
  reads as no gain — no attenuation, no crash. Restoring normalization is a
  server-side tagging job, not a client change.
- **Playlists and starred songs are both empty** on this server. The features
  work; there is nothing in them. All Tracks is gone as predicted.

A fourth item surfaced that was **not** anticipated: the library's top-level
shape changed with the server move (the old tree's single `SOUNDTRACKS` root is
now 5 sibling categories), which trips the reversal condition recorded in "Now
Playing's folder line uses the real path, minus its top-level segment
(2026-08-31)". See that entry.

---

## The Windows installer is not code-signed (2026-09-02)

**Decided.** No Authenticode signing in the release pipeline. Users click through
Defender SmartScreen's "unrecognised publisher" dialog. This is a deliberate
non-purchase, not an oversight — do not read the missing signing step in
`.github/workflows/release.yml` as a gap to fill.

**Why.** A publicly-trusted code-signing certificate has required its private key
on FIPS-140-2 L2 hardware (USB token or cloud HSM) since mid-2023, so it is a
recurring subscription plus key custody, not a one-off file. And it would not
even remove the prompt: SmartScreen reputation is per *file hash*, so an OV
certificate leaves every new tag warning until that specific asset accrues
downloads — a threshold one user will never cross. Only EV buys immediate trust.
Against that, the audience is one person installing a binary built from their own
tag, for whom the dialog is a single extra click.

**What would reverse it.** Distributing to people who did not build it — at which
point "unknown publisher" stops being a formality and starts costing trust. Go
EV, or Azure Trusted Signing if its business-identity check can be satisfied; an
OV certificate is the worst of both, paying the money and keeping the dialog.

---

## Linux releases drop the `.tar.gz` — Arch package only (2026-09-02)

**Decided.** The `linux` job no longer builds
`AnywhereMusicPlayer-<version>-linux-x64.tar.gz`; the only Linux release asset is
the `.pkg.tar.zst`. Supersedes the closing line of **2026-09-02 — Linux ships an
Arch package, not an AppImage**, which kept the tarball "as the distro-agnostic
fallback".

**Why.** There is no non-Arch Linux user. The only Linux target is Omarchy, which
takes the pacman package — so the tarball was an asset nobody downloads, sitting
next to the one they do, on a page whose whole point is one obvious button per
platform. It also can't be installed, only extracted, so it is the *worse* of the
two even for the Arch user who finds it first.

**What would reverse it.** A non-Arch Linux install actually being needed. The
tarball is two lines (`tar -C build/linux/x64/release/bundle -czf …`) and is in
git history, but the better answer at that point is still a Flatpak or `.deb`,
per the entry below — a raw bundle with an undeclared libmpv dependency is not
much of a distribution channel.

**Note.** This does not touch how Linux is *built*: the Arch package is made from
`build/linux/x64/release/bundle` directly by `packaging/arch/PKGBUILD.bin`, never
from the tarball, so nothing else in the job depends on it.

---

## The standalone All Tracks screens are deleted (2026-09-01)

**Decided.** `screens/all_tracks_screen.dart`, `screens/desktop/desktop_all_tracks_screen.dart`
and `test/screens/all_tracks_screen_test.dart` are gone. Supersedes the "Left
behind, deliberately" note on **2026-08-30 — All Tracks is a Navidrome smart
playlist**: they were kept as the reuse target for a cache-backed fetch path if
load time proved a problem. It hasn't — All Tracks has served from `getPlaylist`
since then with no complaint — and the screens had drifted (they never got the
`play_actions` / `CentredMessage` treatment the live screens did) into pure dead
weight that still showed up in every codebase search.

**What would reverse it.** The load-time problem finally biting. The fix then is
still to special-case the *fetch* (serve the smart playlist's tracks from the
library cache), not to resurrect a screen — recover these from git history only
as a reference for the list/search wiring, not as-is.

---

## The phone gets a shared `CentredMessage`, like the desktop's `DesktopErrorState` (2026-09-01)

**Decided.** `lib/widgets/centred_message.dart` holds `CentredMessage` — the
centred icon + title (+ optional subtitle and action) for a phone screen's empty
and error states. Favourites and Playlists each had a byte-identical private
copy (`_CentredMessage` / `_Message`); those are gone, and Home's two scan/search
error blocks now use it too. Finishes "2026-08-30 — One `DesktopErrorState`, not
three" on the phone side.

**Why.** The best copy — the scroll-wrapped one that keeps a `RefreshIndicator`
pullable on an empty list — was private to Playlists, so the other phone screens
reinvented plainer variants. One widget makes the scroll-wrap (and the styling)
reach all of them.

**Visible change on Home.** Its scan-error and search-error states were red
body text with a bare `ElevatedButton`; they now match Favourites/Playlists —
an `error_outline` icon, muted text, a `FilledButton` retry.

**Not done.** A shared widget owning the whole loading/error/empty branch
*precedence* (three services expose the same `isLoading`/`isLoaded`/`error`
triplet). The deletion test is ambiguous — it would spread four lines of
branching back across four screens rather than concentrate them — so it waits
for a fourth phone list or a precedence bug.

**What would reverse it.** The phone empty/error states diverging enough per
screen that a shared widget needs more configuration than the inline version
costs.

---

## The stream cache is a `StreamCache` seam, not `AudioPlayerService` internals (2026-09-01)

**Decided.** The Android on-disk stream cache — directory bootstrap, the
`LockCachingAudioSource` choice, and the 2 GB LRU eviction with its
`.part`/`.mime` sidecar protection — moved out of `AudioPlayerService` into
`lib/services/stream_cache.dart` as a `StreamCache` interface with two
implementations: `DiskStreamCache` (Android) and `DirectStreamCache` (desktop,
web, tests, and the default). `main()` picks one next to the `NowPlayingPresence`
wiring; `AudioPlayerService` just calls `sourceFor` / `evict`. Nothing about the
cache's behaviour changed — this is the same code behind an interface. The
keyed-by-id and 2 GB decisions below still stand.

**Why.** It was ~90 lines of platform-specific file I/O — including the
codebase's single most regression-prone rule (the sidecar protection) —
interleaved through the busiest file in the repo and reachable only behind a
live ExoPlayer, so it had no test. Behind a two-method interface the eviction
rule is plain file I/O over a directory a test hands it:
`test/services/stream_cache_test.dart`. It also matches the seam pattern the
service already used four times (`NowPlayingPresence`, `StreamUrlResolver`,
`PlaybackReporter`, and `PlaybackCursor`), and drops the `_isAndroid` branch out
of the load path.

**What would reverse it.** Desktop or web wanting the same on-disk cache — at
which point `DiskStreamCache` stops being Android-specific and the split is
about caching vs not, which the interface already expresses.

---

## The scrub bar's drag/seek machine lives in one widget (2026-09-01)

**Decided.** `lib/widgets/scrub_bar.dart` holds `ScrubBar` — the "follow the
finger while dragging, seek on release unless the track advanced mid-drag"
state machine that the phone, desktop and TV player bars each spelled out in
full. The three bars keep their own `Slider` theme, label typography and column
layout and get the machine's output through a `builder`. `formatPlaybackDuration`
moved here from `widgets/desktop/desktop_primitives.dart` (it was never a
desktop concept) and is now the one formatter all three use.

**Seeking has no platform gate.** The dead `_seekSupported` getter (always
`true`, doc describing an ExoPlayer limitation that the Android stream cache
removed) is gone; `ScrubBar` seeks whenever the track length is known and an
`onSeek` is given. Do not re-add a platform check — Android plays from a
seekable cache file, desktop/media_kit seeks natively.

**Visible change on TV.** TV's bespoke `_fmt` produced non-padded minutes and
no hour rollover (`3:05`, and `70:00` for a 70-minute track); it now matches
phone/desktop (`03:05`, `1:10:00`).

**What would reverse it.** The three bars' layouts diverging so far that the
`builder` indirection costs more than the shared machine saves — at which point
the machine could become a plain controller object the three instantiate
directly. Extends "2026-08-22 architecture review" Candidate 02.

---

## "Play this, and show it" is one helper, not eleven copies (2026-09-01)

**Decided.** `lib/widgets/play_actions.dart` owns the whole track-pick gesture:
`playFromList(context, track, tracks)` and `playAll(context, tracks, {shuffled})`
start playback *and* bring Now Playing forward, and `playFromList` skips the
restart when the tapped track is already playing. Every list screen — phone,
desktop and TV — calls those two verbs and nothing else. The "show Now Playing"
half is a seam: `openNowPlaying` uses the shell's `NowPlayingOpener`
`InheritedWidget` when one is installed (the desktop shell, which owns the
root-navigator push + `FolderRequest` round-trip — this is the old
`DesktopPlayerLauncher`, renamed and moved out of `desktop_shell.dart`), and
otherwise pushes the platform's player route directly (phone, TV, widget tests).

**Why.** The rule has three parts (play from here / unless already current /
then open the player) and it was hand-written in ~11 screens in three different
shapes — two of them, the phone Home list and Android TV, were missing the
"already current" guard entirely, so tapping the playing song restarted it and
double-scrobbled it. This is exactly the "fixes that have to be made twice"
signal the 2026-08-28 phone/desktop split entry named as *its* reversal trigger,
so the gesture policy moves to the shared side while the layouts stay split.
Extends "2026-08-29 — Picking a track on desktop opens Now Playing": same
behaviour, now the single implementation for all three form factors.

**What would reverse it.** Wanting a list you can queue from without it yanking
you to Now Playing — that would be a per-surface option on the helper, not a
return to per-screen copies.

---

## Linux ships an Arch package, not an AppImage (2026-09-02)

> **Partly superseded** by *Linux releases drop the `.tar.gz` — Arch package
> only* (2026-09-02). The AppImage reasoning below stands; the `.tar.gz` no
> longer ships.

**Decided.** The release workflow builds a `.pkg.tar.zst` via
`packaging/arch/PKGBUILD.bin` in an `archlinux:base-devel` container, alongside
the plain `.tar.gz`. The AppImage attempt and
`scripts/package-linux-appimage.sh` are deleted. Installing on Arch/Omarchy is
`sudo pacman -U anywhere-music-player-*.pkg.tar.zst`.

**Why.** The AppImage never worked — it shipped as `continue-on-error` and
silently produced nothing on `v1.1.0`. The reason it was hard is the reason the
package is easy: media_kit `dlopen()`s libmpv and `flutter_secure_storage`
needs a Secret Service daemon, so an AppImage has to vendor libmpv's whole
ffmpeg tree and *still* can't supply a keyring. A pacman package declares
`depends=('gtk3' 'mpv' 'libsecret')` and the distro solves all of it. It also
gives what the AppImage never would: a desktop entry, an icon, a `/usr/bin`
symlink and `pacman -R` to uninstall.

**Why a second PKGBUILD rather than reusing the existing one.**
`packaging/arch/PKGBUILD` runs `flutter build linux` in `build()`, which would
mean installing the Flutter SDK into an Arch container. `PKGBUILD.bin` drops
`build()` and packages the bundle the `linux` job already compiled on Ubuntu.
Ubuntu-built → Arch-installed is safe in that direction only: glibc is
backward compatible, so a binary linked against an older glibc runs against a
newer one. The two files also differ on version — the local one derives
`pkgver` from `pubspec.yaml` because a local `makepkg` has no tag to read; the
CI one has it rewritten from the git tag, consistent with every other asset.

**What would reverse it.** A non-Arch Linux user actually needing an install
(then it's a `.deb`/Flatpak, not a revived AppImage — Flatpak solves the
keyring and portal story properly, which is where AppImage failed). The
`.tar.gz` stays either way as the distro-agnostic fallback.

---

## Releases are built in CI, and the git tag is the version (2026-09-01)

**Decided.** `.github/workflows/release.yml` builds Android / Windows / Linux on
a `v*` tag and publishes a GitHub Release. The tag — not `pubspec.yaml`, not
`installer.iss` — is the version of a released build: the workflow feeds it to
`flutter build --build-name` and `ISCC /DMyAppVersion`. `versionCode` is the
Actions run number (monotonic). The apps get a hosted download page
(foxcore.dev) pointing at `releases/latest`.

**Why.** Builds were hand-cranked per platform per release, which is why
`pubspec.yaml` (`1.1.0+2`) and `installer.iss` (`1.3`) had already drifted apart
— the exact failure the Arch PKGBUILD's `pkgver()` was written to avoid.
Deriving every artifact's version from one tag makes drift structurally
impossible instead of a thing to remember. GitHub Releases (not the VPS, not
R2, not binaries in a repo) because the repo is public so assets download with
no auth, it's CDN-backed and free, and CI can attach to a release in one step
where committing 40 MB binaries back to a repo is an antipattern.

**Why not iOS.** `ios/` is untouched Flutter scaffolding, and iOS has no
download-page distribution path regardless — App Store or TestFlight only, both
needing the paid Developer Program and a Mac to build. Out of scope until those
change.

**Android signing changed with this.** `buildTypes.release` was debug-signed
(`signingConfigs.debug`); it now uses a real `signingConfigs.release` read from
a gitignored `android/key.properties`, falling back to debug when that file is
absent so plain dev checkouts are unaffected. CI reconstructs the file from
secrets. See [operations.md](operations.md) "Automated releases".

**What would reverse it.** Making the repo private (assets would then need a
token — move to Cloudflare R2 or a public releases-only repo), or adding a
platform CI can't build for free (iOS/macOS need paid macOS runners — likely
stays a local `flutter build` + manual upload).

---

## `just_audio`'s `play()` is fired, never awaited (2026-09-01)

**Decided.** `AudioPlayerService._loadAndPlay` fires `_player!.play()` and moves
on, with a `catchError` for the error path. It must stay that way, and the
comment saying so must stay with it.

**Why.** `play()` completes when playback *stops*, not when it starts. On
Android (ExoPlayer) the platform holds the reply until `STATE_ENDED`, so
awaiting it holds `_isLoading` true for the whole track — which gates off the
`completed` handler that advances the playlist (playback dead-stops at the end
of every song), defers `_presence.show` and the now-playing report to track end
(the notification re-announces the song as it finishes), and blocks
`_handleStreamError`'s drop recovery, which checks `_isLoading`. media_kit
returns from `play()` immediately, so **desktop shows none of this** — this is
the platform split in `CLAUDE.md` biting for real. `ad2629a` added the `await`
during a refactor; this entry exists so it doesn't get added back as a tidy-up.

**What would reverse it.** just_audio changing `play()` to mean "started" (it
has been "stops" since 0.9.x and the doc comment says so), or dropping the
ExoPlayer backend. If sequencing ever moves onto `ConcatenatingAudioSource`,
the whole `_isLoading`/`completed` handshake goes away with it — but see the
entry on why sequencing is hand-rolled before going there.

---

## Now Playing's folder line uses the real path, minus its top-level segment (2026-08-31)

> **Step 2 reversed (2026-09-08)** by "Now Playing's folder line shows the
> full path". Step 1 — resolving the playing track to its scanned copy by
> id — stands unchanged and is still what keeps the line consistent across
> playback sources.

**Decided.** The folder line on every player (`player_screen.dart`,
`desktop_player_screen.dart`, `tv_player_screen.dart`) now:
1. resolves the playing track to its scanned copy by id
   (`LibraryScanner.trackById`) before reading `folderPath`, and
2. drops the first path segment for display (`nowPlayingFolderPath` in
   `lib/utils/now_playing_folder.dart`) — hiding the line entirely when nothing
   is left.

**Why.** The same song showed two different folder lines depending on how
playback started: from a playlist (`api.getPlaylist` → `Track.fromSubsonic`) the
path is Subsonic's tag-based virtual path (`AlbumArtist/Album`); from library
browse (`LibraryScanner` → `Track.fromNativeApi`) it's the real filesystem path.
Reported as inconsistent, and the playlist path also made the tap-through open a
folder that doesn't exist in the virtual tree. Resolving by id (the pattern
`desktop_library_screen.dart` already uses for search results) fixes both. The
first real segment is a broad category (`SOUNDTRACKS`, …) shared across large
swaths of the library — noise next to the folder that actually identifies the
album, and redundant with the artist line above it.

**What would reverse it.** Wanting the full real path shown (drop step 2), or
libraries that don't use a top-level category folder — there the dropped segment
would be meaningful. A leaf-only or last-2-segments rule would be a one-line
change to `nowPlayingFolderPath`.

---

## Now Playing scales with the window; its cover art request does not (2026-08-28)

**Decided.** The Now Playing pane sizes the cover art and the info column from
the available space (`LayoutBuilder`), clamped to 240–520px and 340–620px. The
art is still *requested* at a fixed 640px and scaled down to fit.

**Why.** The design is a fixed composition at a 1240px reference width — 320px
art, 380px info column. Taken literally it leaves most of a maximised window
empty. The ratio 0.38 is what the design's own art occupies at its reference
width, so the mock is reproduced there and grows from there; the clamps stop the
cover dwarfing the transport controls beside it. The request size is deliberately
*not* the display size: a request that tracked the layout would mint a new URL
and cache key on every resize and re-download the same cover — the same failure
mode `CoverArt` and the Android stream cache already warn about. One oversized
fetch is cheaper. The precache uses the same constant so the warmed key and the
rendered key cannot drift.

**What would reverse it.** Wanting true fidelity to the mock at all sizes (cap
both at the design's numbers), or a design revision that scales the *type* with
the window too — this only scales the boxes, the 34px title is unchanged.

---

## Folder-screen search spans the whole folder recursively, not just its direct tracks (2026-08-28)

**Decided.** `DesktopFolderScreen`'s search filters `LibraryScanner.getAllTracksInFolder` (the same recursive set `_playAll` already used), not `getFolderContents`'s direct-children list. Search-result rows number by position in the results, not by "real" position in the folder; tapping a result plays from the recursive set so playback continues past the filtered view, mirroring how `DesktopAllTracksScreen` already treats its own search.

**Why.** Verified against the real library cache: a typical Library-grid folder has **zero** direct tracks — e.g. `SOUNDTRACKS/GAMES` holds 0 direct / 2,218 recursive, `SOUNDTRACKS/ANIMES & ANIMATIONS` 0/1,578 — because the actual files sit one or more album subfolders down. Filtering only direct tracks made search return nothing for almost every real folder, while the Library and All Tracks screens (which already search everything) worked fine — reported as "search doesn't work inside folders."

**What would reverse it.** Nothing likely — this was a bug, not a tradeoff.

**Update (2026-08-28, same day).** `lib/screens/folder_detail_screen.dart` (phone) had the identical bug — its own `_filteredTracks` filtered only `_tracks` too. Fixed the same way, plus a regression test (`search finds tracks nested in a subfolder, not just direct children`) reproducing the exact shape that broke it: a track several folders below the one being searched from.

---

## Desktop gets its own screens; the phone keeps the old ones (2026-08-28)

**Decided.** The desktop redesign lives in `lib/screens/desktop/` and
`lib/widgets/desktop/` as a parallel set of screens, selected by
`PlatformDetector.isDesktop` in `MainScreen`. The phone screens
(`home_screen.dart`, `all_tracks_screen.dart`, `folder_detail_screen.dart`,
`player_screen.dart`, `widgets/mini_player.dart`) are untouched structurally and
keep serving Android; Android TV keeps `tv_*`. The **theme** is the one thing
shared across all three.

**Why.** The two layouts disagree about almost everything above the data layer:
sidebar vs bottom tabs, a folder grid vs a list, a docked "Up Next" panel vs a
modal queue sheet, an app-drawn title bar vs none. Expressing that as
`if (isDesktop)` inside the existing screens would have put a form-factor branch
around most of every build method for no shared code worth the coupling. The
services underneath — `AudioPlayerService`, `PlaybackCursor`, `LibraryScanner`,
`CoverArt` — are shared unchanged, which is where the duplication would actually
have cost something.

**What would reverse it.** Convergence: if phone and desktop layouts ever grow
close enough that one responsive screen is genuinely smaller than two, collapse
them. Watch for fixes that have to be made twice — that is the signal.

---

## Desktop draws its own title bar (2026-08-28)

**Decided.** On Windows and Linux `main()` calls
`windowManager.setTitleBarStyle(TitleBarStyle.hidden)` before the first frame,
and `WindowChrome` renders the 40px bar — app mark, context label, and
minimise/maximise/close — inside the Flutter tree. Every desktop screen must
render one, including the login and auth-loading screens (via
`DesktopWindowFrame`), because there is no native frame left to fall back on.

**Why.** The design specifies it, and a hidden-frame app that shows an OS title
bar on one screen and not another looks broken. Hiding the frame *before* the
first frame (inside `waitUntilReadyToShow`) is what avoids the native bar
flashing on launch.

**What would reverse it.** Window-management friction that can't be fixed in
Dart — snap layouts, per-monitor DPI, or a Linux WM that fights
`TitleBarStyle.hidden`. The escape hatch is small: drop the `WindowOptions`
in `main()` and stop rendering `WindowChrome`; nothing else depends on it.

**Note.** `WindowsPresence.setTitle()` still runs and still drives the **taskbar**
entry — the hidden frame doesn't affect it. The in-window context line is a
separate thing, fed by the shell's navigator observer.

---

## Colour tokens are stored as sRGB hex, converted once from OKLCH (2026-08-28)

**Decided.** `lib/theme/app_colors.dart` holds the palette as Flutter `Color`
constants, each with its source `oklch(...)` value in a comment beside it. The
conversion was done once, numerically (OKLab → linear sRGB → sRGB), not matched
by eye.

**Why.** The handoff specifies every colour in OKLCH and asks for a direct
conversion, because the palette is a deliberate lightness/chroma ramp — hand-
tweaking a hex silently steps off it. Flutter has no OKLCH type, so converting
at build time would mean shipping the maths for a value that never changes.

**What would reverse it.** Flutter gaining first-class wide-gamut colour, or
needing runtime-generated palettes (a per-album accent). Either way, re-derive
from the OKLCH values in the comments — not from the hex.

---

## Shuffle and repeat persist across restarts (2026-08-28)

**Decided.** `AudioPlayerService` reads both modes from `SharedPreferences` in
its constructor and writes them back on every toggle. `PlaybackCursor` gained
`setRepeatMode` to make the restore expressible without the test-only `seed`.

**Why.** The handoff asks for it, and both modes are sticky user intent rather
than per-session state — "shuffle off" is a preference, not a fact about this
playlist. Persistence lives in the service, not the cursor, because the cursor
is deliberately plain Dart with no plugin dependencies so it stays testable
without a platform channel.

**What would reverse it.** Nothing likely. Note the reads and writes swallow
their errors on purpose: with no `shared_preferences` implementation (widget
tests) the cursor's defaults are a fine fallback, and failing to remember a
toggle must never break playback.

**Note.** The handoff describes shuffle and repeat as *net-new* for this
redesign. They were not — the state, the cycling and the sequencing already
existed in `PlaybackCursor`. Only persistence and the new controls were missing.

---

## The desktop folder card's play button plays in order, not shuffled (2026-08-28)

**Decided.** The round accent play button on a library folder card calls
`play()`. The phone's equivalent called `playShuffled()`.

**Why.** The redesign puts an explicit Shuffle control on the folder screen, in
the mini player and on Now Playing. With shuffle visible and separately
controllable, a plain ▶ that silently randomises is a lie about what it does.

**What would reverse it.** Finding that folder-card playback is overwhelmingly
used as "surprise me". The phone still shuffles here, so the two form factors
currently disagree — worth unifying once there's a preference either way.

---

## Windows wakelock tracks the raw player stream, not `NowPlayingPresence.setPlaying` (2026-08-27)

**Decided.** `WindowsPresence` subscribes to `AudioPlayer.playingStream`
directly inside `bind()` to drive `WindowsWakelock.enable()`/`.disable()`,
instead of doing it inside `setPlaying()` like the SMTC update.

**Why.** This was a regression, not a fresh design choice. Before the
`NowPlayingPresence` seam existed, the `playingStream` listener in
`AudioPlayerService` called `WindowsWakelock.enable()`/`.disable()`
unconditionally on every play/pause transition; SMTC's update was the only
part gated on `_currentTrack != null` (SMTC needs metadata to show). Folding
both into one `presence.setPlaying()` call put wakelock behind that same gate
— a contract `NowPlayingPresence.setPlaying` documents ("only called while a
track is current") that makes sense for SMTC but has nothing to do with
whether the PC should be allowed to sleep. Net effect: the PC could suspend
during playback in any state transition where that gate wasn't satisfied,
silently undoing the original fix from commit `468156c`.

**What would reverse it.** If `NowPlayingPresence` ever needs the same "raw,
ungated" hook for another adapter, promote it to a proper interface method
instead of each adapter reaching into the player stream itself.

---

## Linux media keys: a hand-rolled MPRIS server on `package:dbus`, not a library (2026-08-24)

**Decided.** `LinuxPresence`/`MprisMediaService` implement `org.mpris.MediaPlayer2`
and `.Player` directly on top of the general-purpose `dbus` package — exporting
a `DBusObject` at `/org/mpris/MediaPlayer2`, handling `Play`/`Pause`/`PlayPause`/
`Stop`/`Next`/`Previous`, and serving `Metadata`/`PlaybackStatus`/`Position` —
rather than pulling in an existing MPRIS package or leaning on mpv's own MPRIS
support.

**Why.** Neither of the two paths that might have made this a config change
actually work: `audio_service` (Android's lock-screen/notification integration)
ships no Linux platform implementation at all, and `media_kit`'s embedded
libmpv doesn't auto-load `mpv-mpris` — that plugin lives in mpv's user config
directory, and embedded libmpv disables config loading by default unless the
host app explicitly turns it on, which nothing in this app's `media_kit`
`PlayerConfiguration` does. The one MPRIS package on pub.dev is a *client* for
controlling other players (built for talking to spotifyd), the wrong
direction — so there was nothing to depend on. `dbus` is pure Dart, actively
maintained, and MPRIS's method/property surface is small enough that hand-rolling
it directly was less work and less risk than routing through mpv's config system
or shelling out to `playerctld`.

**What would reverse it.** A published, maintained Dart package that does this
well would be worth switching to. Turning on `mpv-mpris` instead (enabling
libmpv's `config`/`config-dir` options) was considered and rejected — it would
also pull in the user's own mpv config/keybindings/OSD, not just the MPRIS
script, which is a much bigger behavior change than adding one dependency.

**Verified.** Manually, over the real session bus (`busctl --user`) — not just
type-checked. Registered the name, ran `Properties.GetAll` on both interfaces,
and confirmed `Next`/`Previous`/`PlayPause` D-Bus calls actually reached the
Dart callbacks. This can't be covered by `flutter test` (`defaultTargetPlatform`
defaults to `android` in that harness, and there's no live session bus in
`test/`) or by on-device testing on any other platform — Windows/Android
verification says nothing about this path.

---

## `LibraryCache.save()` swaps files via rename-aside, not delete-then-rename (2026-08-24)

**Decided.** `save()`'s write order changed from `write .tmp → delete target →
rename .tmp to target` to `write .tmp → rename target to .old → rename .tmp
to target → delete .old`. The class doc comment now says "crash-safe", not
"atomic" — the actual guarantee is that a crash never corrupts the cache; in
the sub-millisecond window between the two renames it degrades to "no
cache" (same as first launch), not to a corrupt or missing-then-broken file.

**Why.** Not hypothetical — the architecture review's own test run hit
`PathAccessException: Cannot rename file ... (OS Error: Acesso negado,
errno = 5)` twice. `File.rename` can't replace an existing file on Windows,
which is why the delete existed at all, but deleting the target and then
immediately renaming onto that exact path is a known Windows race: a
just-deleted path can briefly stay in a pending-delete state, and the
rename lands on it before the OS has fully released it. Renaming the old
file aside instead of deleting it means the target path is never reused
immediately after something is removed from it — this is the standard
atomic-replace idiom on Windows for exactly this reason.

**What would reverse it.** Nothing planned. If `File.rename` on Windows is
ever confirmed to replace an existing destination reliably (newer Dart SDK
behavior), the aside-rename becomes unnecessary — verify with a real
repeated-save stress test before reverting, not just a version bump.

---

## `AuthService.initialize()`'s outer catch no longer clears storage (2026-08-24)

**Decided.** The outer `try/catch` wrapping the six `_secureStorage.read()`
calls in `initialize()` now only logs on failure — it no longer calls
`_clearStorage()`. Only the inner `on SubsonicApiException catch (e)` branch,
when `e.code == 40` (server actively rejects the credentials), may clear
storage.

**Why.** The outer catch previously covered both the storage reads *and* the
ping/login logic below them, so any `flutter_secure_storage` plugin failure
on startup (corrupted keystore, OS-level storage error — not the credentials
being wrong) fell into the same branch as "credentials rejected" and wiped
the saved login. That's a real data-loss path and directly contradicted the
comment two lines above it, which promises clearing only happens on a
code-40 rejection. This was the only finding in either review that loses
user data, so it was fixed first regardless of scheduling.

**What would reverse it.** Nothing planned — this is a correctness fix, not
a capability being held open. A broader refactor (collapsing
`_apiService`/`_currentUser` into one `Session`, extracting a `_Credentials`
read/write/delete helper) was considered and declined for now — the bug is
fixed with a one-line change to the outer catch; the duplication it would
clean up is real but not a live risk.

---

## `SubsonicApiService` dropped its tag-based directory browsing methods (2026-08-24)

> **Partly superseded (2026-09-08)** by "Migrated from Navidrome to Gonic".
> `getMusicFolders`/`getIndexes`/`getMusicDirectory` are back — not as the
> tag-based browsing this entry deleted, but as the folder-native browsing
> that replaced the native-API scan. The reversal condition below named
> tag-based browsing specifically; that part still stands, and the tag
> endpoints (`getArtists`, `getAlbumList2`, …) remain deleted.

**Decided.** Removed `getMusicFolders`, `getIndexes`, `getMusicDirectory`,
`getFolders`, `getRootTracks`, `getDirectoryContents`,
`getAllTracksInDirectory`, `getRandomSongs`, `getAlbumList2`, and the in-memory
LRU response cache (`_cache`/`_getFromCache`/`_putInCache`/`clearCache`) that
existed only to serve three of them. `ping`, `search3`, `buildStreamUrl`,
`buildCoverArtUrl`, and the native-API scan path
(`getAllSongsNativeApi`/`_getNativeApiToken`) are untouched. The file drops
from 609 lines to ~300. A shared `_baseUrl` field (trailing slash stripped
once, in the constructor) and a small `_request()` helper replace the
duplicated URI-build/GET/parse/rethrow shape across what's left.

**Why.** `LibraryScanner` builds the entire virtual folder tree from
`getAllSongsNativeApi`'s real filesystem paths (see "Track sequencing" note
below, and `Track.fromNativeApi`) — the tag-based Subsonic browsing path was
superseded by that migration and nothing called it anymore. Confirmed by
grep: zero production call sites for any of the nine methods outside their
own definitions, and no existing test coverage for seven of them.
`README.md`/`docs/overview.md` still listed `getMusicFolders`/
`getMusicDirectory` as the live "Browse folders" mechanism — corrected here.

**What would reverse it.** Reintroducing tag-based (artist/album) browsing as
a real feature — Navidrome's tag index has data the filesystem-path scan
doesn't (album/artist metadata quality varies by tagging, but the *index* is
richer). If that's ever wanted, recover the deleted methods from git history
(this commit) rather than re-deriving them; they were previously exercised
manually even without unit tests.

---

## Track/Folder stopped carrying a resolved streamUrl/coverArtUrl (2026-08-24)

**Decided.** `Track.streamUrl` and `Track.coverArtUrl`/`Folder.coverArtUrl` are
gone. Both models now hold only the raw `coverArtId` (`Track.path`/`id` double
as the stream key). A new `StreamUrlResolver` interface (implemented by
`SubsonicApiService`) is consulted at the moment of use instead — by
`AudioPlayerService` when it actually loads a track, and by `CoverArt`/the
handful of screens that render one, via the live `AuthService.apiService`.
`AudioPlayerService` and the Android audio handler are both constructed once,
before login, so each takes a `RotatingStreamUrlResolver` — a stable
reference `main.dart` keeps pointed at whatever session is current, updated
by a plain listener on `AuthService`.

**Why.** The old design meant every `Track` held a live, password-equivalent
auth token+salt baked into a URL, frozen in memory for as long as the object
lived — for the whole library, for the whole session. It also meant the
domain model imported the transport (`Track`/`Folder` importing
`SubsonicApiService`) just to mint a URL once at parse time, and every
construction site (the scanner, the cache, three spots in
`subsonic_api_service.dart`) had to thread an `api:` argument through for it.
Minting fresh at the point of use also matches what the auth scheme already
assumes elsewhere: the Android stream cache is keyed on track id specifically
*because* the salt rotates per request (see that decision below) — the old
code kept a stale URL around anyway, it just didn't matter because nothing
re-minted it.

**What would reverse it.** Nothing planned. This is a dependency-direction
and freshness fix, not a capability being held open.

**Note.** This *extends* "Cached cover art stores the id, not the resolved
URL" below rather than touching it — that decision is about the on-disk
cache and stays exactly as it was (still id-only, still schema-versioned).
This one applies the same reasoning to the copy that used to sit in memory.

---

## Library cache schema v3 → v4: `filename` renamed to `path` (2026-08-23)

**Decided.** `Track.filename` is renamed to `Track.path`, and the persisted
JSON key follows (`filename` → `path`). The no-path fallback also changes:
`Track.fromSubsonic` used to synthesize a filename-shaped string
(`'$title.$suffix'`) when the server sent no path; it now uses `''`, matching
the empty-string-means-absent convention `folderPath`/`folderName` already
use. `LibraryCache._version` bumps to 4 so old caches self-heal via a fresh
scan rather than being read under the old key name.

**Why.** The field held a full relative path (e.g.
`"Artist/Album/song.flac"`) everywhere it was actually used — building the
virtual folder tree — but its name and one fallback path described a bare
filename. That mismatch let a third construction path (`LibraryScanner`'s
inline `Track(...)`, now `Track.fromNativeApi`) go a full release without
ever setting `folderName`, because it was never obvious the fields disagreed.

**What would reverse it.** Nothing planned — this is a naming and consistency
fix, not a capability being held open.

---

## Track sequencing is hand-rolled in Dart, not `ConcatenatingAudioSource`

**Decided.** The player loads **one track at a time**. All sequencing — playlist
order, shuffle, repeat, the manual queue — is implemented in Dart in
`audio_player_service.dart`, not delegated to just_audio's
`ConcatenatingAudioSource`.

**Why.** `ConcatenatingAudioSource` is buggy under `just_audio_media_kit`
(Windows/Linux). Using it would mean a player that behaves differently per
platform, which is the one thing a "write once" app can't afford.

**What would reverse it.** `just_audio_media_kit` fixing concatenating sources
on desktop — at which point deleting the manual sequencer would remove real
complexity. Verify on Windows specifically before believing it.

**Note.** This is why the queue, shuffle permutation and repeat modes are all
bespoke state rather than player features. They look like reinvention; they
aren't.

---

## Windows/Linux audio goes through media_kit (MPV), not `just_audio_windows`

**Decided.** `JustAudioMediaKit.ensureInitialized()` on Windows and Linux
(`main.dart`), pulling in `media_kit_libs_windows_audio`.

**Why.** `just_audio_windows` uses Windows Media Foundation and hit **threading
deadlocks on startup** — the app could hang before playing anything.

**What would reverse it.** `just_audio_windows` resolving the WMF deadlock. The
payoff would be dropping the native MPV libraries, which are a large slice of the
Windows bundle.

---

## The Android stream cache is keyed by track id, never by URL

**Decided.** Android wraps playback in `LockCachingAudioSource`, writing each
song to a per-track file keyed by **track id**. Capped at **2 GB**, oldest
evicted after each load, never evicting the track currently playing. Desktop
(media_kit) streams direct with no cache.

**Why.** Two separate reasons, both load-bearing:
- **Seeking.** Navidrome's live HTTP stream isn't seekable for VBR/FLAC/OGG.
  Caching to a local file is what makes the scrubber work at all.
- **Keyed by id, not URL.** The stream URL embeds an auth token and a salt that
  **rotate on every request build** — keying on it would produce a cache miss
  every single time, silently defeating the whole mechanism.

**What would reverse it.** Navidrome serving seekable ranges for compressed
formats would remove the seeking justification (replay savings would remain).

**Note.** The Android-only scope is deliberate: media_kit handles its own
buffering on desktop. "Add the cache to Windows too" is not a free win.

---

## ReplayGain is attenuate-only, with a +6 dB pre-amp

**Decided.** Playback gain = `10^((trackGainDb + 6) / 20)`, clamped to `[0, 1]`.
Tracks with no ReplayGain data play unchanged.

**Why.** The clamp at 1.0 means quiet tracks are **never boosted**, so clipping
is impossible by construction. The pre-amp is a deliberate midpoint between two
competing goals, and the tradeoff is documented in the code with a reference
table (for a typical −7 dB pop master):

| Pre-amp | Factor | Effect |
|---|---|---|
| 0 dB | 0.45 | Full normalization, library plays quiet |
| 3 dB | 0.63 | |
| **6 dB** | **0.89** | **Current** — near the file's own level |
| 9 dB | 1.00 | Leveling effectively off |

**What would reverse it.** Wanting true equal-loudness over absolute volume →
lower the pre-amp. Wanting maximum loudness → raise it. **Don't change the clamp**
— that's what prevents clipping, not a tuning knob.

---

## Cached cover art stores the id, not the resolved URL (security)

**Decided.** The library cache (`library_cache.dart`, schema **v4** as of
2026-08-23; v3 when this was decided) stores `cover_art_id`. Schema v2 → v3
exists specifically to drop `cover_art_url`; the v3 → v4 bump was an unrelated
field rename (see the schema v3 → v4 entry above) and didn't touch this.

**Why.** A resolved cover-art URL has a **live auth token and salt baked into
it**. Persisting it meant a password-equivalent credential sitting in a plaintext
JSON file on disk until the next scan overwrote it. The bare id is inert.

**What would reverse it.** Nothing — this is a security floor. If URL caching is
ever reintroduced for performance, the credential has to be stripped first.

**Note.** The schema version is the enforcement mechanism: old caches are
discarded on load and rebuilt, so the bad field can't survive an upgrade.

---

## Cleartext is permitted for loopback only, not app-wide

**Decided.** `network_security_config.xml` permits cleartext traffic for
`127.0.0.1` and `localhost` only. The app does **not** set
`usesCleartextTraffic="true"`.

**Why.** just_audio's Android stream cache (`LockCachingAudioSource`) proxies
ExoPlayer through a local loopback HTTP server — cleartext, regardless of the
origin stream being HTTPS. Android blocks cleartext by default, which breaks that
loopback specifically. The app-wide flag would fix it too, but would also unblock
cleartext for **every real network destination**, including the Navidrome server.

**What would reverse it.** just_audio serving its cache over HTTPS loopback, or
dropping the Android stream cache (which would cost seeking — see the cache
entry above).

---

## Skips are debounced; natural track-end is not

**Decided.** A burst of Next/Previous presses updates the displayed track
instantly but coalesces into a **single** stream load — only the track the user
lands on is opened. Natural end-of-track advance **bypasses** the debounce and
loads immediately.

**Why.** Holding Next through ten tracks shouldn't open ten streams. But applying
the same delay to natural advance would insert an audible gap between tracks,
losing the gapless-style behaviour.

**What would reverse it.** Nothing likely — the asymmetry *is* the design.

---

## Mid-stream drop recovery never auto-resumes a paused player

**Decided.** When the server or proxy closes a connection mid-playback, the
player re-opens the track, seeks back to where it stopped, and resumes — bounded
to **3 rapid attempts**, with the counter resetting after **30 s** of successful
playback. It acts only on steady-state playback: not during a deliberate load,
and **not while paused**.

**Why.** Idle connections routinely drop *while paused* — auto-resuming there
would start music the user deliberately stopped, which is worse than the bug it
fixes. The 30 s reset distinguishes a long track that drops occasionally (keeps
recovering) from a dead source (stops looping).

**What would reverse it.** Nothing likely. If recovery ever seems too eager,
tune the bound — don't remove the paused-state guard.

---

## No backend of our own: Navidrome via the Subsonic API

> **Server superseded (2026-09-08)** by "Migrated from Navidrome to Gonic".
> The decision this entry records — no backend of our own, everything over
> the Subsonic API — is unchanged; only the server on the other end moved.

**Decided.** The app is a pure Subsonic client. Navidrome owns scanning,
metadata, users, streaming and cover art. There is **no in-app signup** — users
are created in the Navidrome web UI.

**Why.** Subsonic is a stable, widely-implemented API, and Navidrome already
solves the parts that are tedious and easy to get wrong (library scanning,
transcoding, auth). Writing a backend would add an entire deployable for no
capability the client actually needs.

**What would reverse it.** Wanting a feature the Subsonic API can't express, or
multi-server federation. Both are large enough that the client would stop being
"a Subsonic client".

**Note.** This is why auth is MD5-salt token auth — it's the Subsonic protocol's
scheme, not a choice made here.

---

## 2026-08-29 — Picking a track on desktop opens Now Playing

**Decided.** On the desktop shell, choosing a track (or Play All / Shuffle All)
starts playback *and* pushes `DesktopPlayerScreen`, matching what the phone has
always done. Tapping the track that is already playing opens the player without
restarting it. The shell exposes the push through a `DesktopPlayerLauncher`
`InheritedWidget`, and guards against stacking a second copy of the route.

**Why.** The redesign left the desktop lists silently starting playback with no
visible confirmation beyond the mini player's 72px strip. The push has to stay
the shell's: Now Playing lives on the *root* navigator and hands a folder back
to the shell when closed (`FolderRequest`), so a list screen can't own it.

**What would reverse it.** Wanting the desktop list to be a browsing surface you
can queue from without losing your place — in which case the right answer is
probably a preference, not removing the navigation.

---

## 2026-08-29 — Now Playing's left pane fills the window it is given

**Decided.** Three changes, all aimed at the pane having no dead space at any
window size:

- **Gutters scale.** The gap and horizontal padding interpolate from 48px down
  to 24px as the pane narrows past 900px.
- **The art absorbs the leftover width.** The info column is sized first and
  capped at 820px; the art then takes whatever the pane has left, bounded by
  the pane's height and by the 800px fetch size (so it is never upscaled).
- **The cluster centres vertically.** The scroll view's child is floored at the
  pane height, so `Center` centres on both axes instead of pinning the cluster
  to the top.

**Why.** The old fixed 48px gutters plus 240/340 minimums needed ~724px before
art and info fit side by side, so a merely-narrow window stacked them. At the
other end, the info column capped out long before the pane did and the art was
sized from a fraction of the pane rather than from what was actually left over,
which on a 1600px pane stranded ~170px of empty width beside the cluster and
~400px of empty height below it. Sizing info first and giving the art the
remainder means the two together consume the pane exactly.

**What would reverse it.** A redesign that gives the pane a fixed content width
instead of tracking the window. Note the art's ceiling is deliberately tied to
`_artRequestSize`: raising one without the other either upscales a smaller
fetch or downloads pixels that are never drawn.

---

## 2026-08-29 — Desktop window close is intercepted to stop the player first

**Decided.** On Windows and Linux the window no longer closes directly:
`_DesktopCloseGuard` (in `main.dart`) sets `setPreventClose(true)`, and on close
awaits `AudioPlayerService.shutdown()` before ending the process with `exit(0)`.
`AudioPlayerService` is therefore constructed in `main()` and handed to `MyApp`
by value, rather than being created inside its provider — Provider must not own
something whose lifetime is now the process's. `shutdown()` is a new awaitable
teardown; `dispose()` delegates to the same once-only `_teardown()`.

**Why.** Closing the window tore down the engine and the Dart isolate while
mpv's event thread was still holding FFI callbacks into Dart, so the next event
landed in a dead isolate: SIGSEGV in release builds, SIGABRT in debug, on every
close after something had played. Four core dumps with an identical signature.
`dispose()` could not fix it twice over — it is synchronous, so it can't wait for
mpv, and Provider never runs it on desktop anyway, because the process exits out
from under the widget tree.

The exit itself went through `windowManager.destroy()` first, which promptly
surfaced a *second*, unrelated crash — a `g_list_remove_link` SEGV inside GTK's
own main loop, with the mpv race genuinely fixed (dozens of mpv threads alive
and idle in that dump). Traced to `destroy()` re-entering GTK's
`delete-event`/close machinery and letting it tear the window down synchronously
from inside that same dispatch — independently documented as flaky on Linux for
modern Flutter (leanflutter/window_manager#478). Superseded within the same
change: `onWindowClose` now calls `exit(0)` once the player is confirmed
stopped, instead of asking `windowManager` for a clean GTK teardown it can't
reliably deliver. See the Traps entry in `docs/operations.md` for both
signatures.

**What would reverse it.** media_kit fixing its shutdown race upstream, or
window_manager fixing `destroy()` on Linux, would remove the *reason* for this,
but not necessarily the mechanism — `exit()` after confirmed cleanup is a
reasonable steady state either way. Note the guard is what makes the window
closable at all now — deleting the listener while leaving `setPreventClose(true)`
would strand the user in an unclosable window, which is why the install order
and the 2 s shutdown timeout are both deliberate.

---

## 2026-08-30 — Scrobbling: position-based threshold, best-effort delivery

**Decided.** The app now reports listening to the server over `/rest/scrobble`:
a `submission=false` "now playing" announcement when a track starts, and a
`submission=true` play once playback passes **half the track or four minutes,
whichever comes first** (the Last.fm rule). The submission carries `time` — when
the *listen* began, not when the threshold was crossed.

The trigger is **playback position**, not accumulated listening time. Scrubbing
to the end therefore counts as a play.

Delivery is **best-effort**: `AudioPlayerService._report` swallows every failure
to a debug line. A server that is slow, down, or doesn't implement the endpoint
must never surface as a playback error.

Wired as a seam (`PlaybackReporter`, with `NoPlaybackReporter` as the default
and `RotatingPlaybackReporter` following the session), exactly mirroring
`StreamUrlResolver` — `AudioPlayerService` gains no knowledge of the transport,
and tests get a no-op by default.

**Why.** Navidrome keeps play counts, "recently played" and "most played", and
can bridge to Last.fm / ListenBrainz — all of which saw *nothing* from this app,
because `/rest/scrobble` was never called. Every discovery feature that could be
built on play history needs the history to exist first.

Position-based is the simpler rule, it is what most Subsonic clients do, and
over-counting a track you deliberately seeked through is the benign direction to
err in. Accumulated-playtime would need delta accounting on the position stream
to distinguish a seek from playback.

A listen is identified by a counter bumped in `_selectAndPlay`, which is what
makes the edges correct: repeat-one re-selects, so a looped track counts each
time; mid-stream drop recovery re-enters `_loadAndPlay` *without* re-selecting,
so a dropped-and-resumed track counts once. Both are covered by tests.

**What would reverse it.** Scrub-to-end false positives becoming annoying in
practice — then switch the trigger to accumulated playtime, keeping the same
threshold and the same session identity. Nothing else about the design needs to
change for that.

---

## 2026-08-30 — Desktop keyboard shortcuts live on both roots, and yield to text fields

**Decided.** `DesktopPlaybackShortcuts` binds Space (play/pause), ←/→ (seek
∓10s), Ctrl+←/→ (previous/next), ↑/↓ (volume ±5%), and Escape (close Now
Playing, where a handler is passed).

It wraps **both** desktop roots — `DesktopShell` *and* `DesktopPlayerScreen` —
and every binding is a no-op while a text field holds focus.

**Why.** Now Playing is pushed on the root navigator, so it is not inside the
shell's subtree; wrapping only the shell would leave the player screen — the one
place a user is most likely to reach for these keys — without them.

The typing guard is not optional: these bindings sit above the whole window, so
without it a space typed into the search box would pause the music instead of
typing. Arrow keys happen to be consumed by `EditableText`'s own closer handlers
first, but the guard covers them rather than depending on that ordering.

Media keys are a separate, system-wide path that already worked (MPRIS on Linux,
SMTC on Windows); this is in-window only, and the two don't interact.

**What would reverse it.** Nothing likely. Note the widget owns a
`Focus(autofocus: true)` holder, because key events only reach a
`CallbackShortcuts` by bubbling up from the focused node and the route's
`FocusScope` sits above it — with nothing focused inside, the shortcuts would be
dead until the user clicked something. The cost is that it claims autofocus: a
desktop screen that later wants an autofocusing field would have to take focus
explicitly instead. No desktop screen autofocuses today.

**Not included:** Ctrl+F to focus search. Both searchable screens live in an
`IndexedStack` (so both are mounted at once) *and* the library one sits behind a
nested navigator whose folder screens have their own search fields — so "focus
the search box" has no single correct target without a focus registry keyed on
the active destination. Deferred rather than half-built.
**(Superseded 2026-08-30 — the registry was built; see the entry at the end.)**

---

## 2026-08-30 — Keyboard shortcuts are advertised in tooltips, not a shortcuts overlay

**Decided.** The desktop transport buttons' tooltips carry their key: "Play
(Space)", "Previous (Ctrl+←)", "Next (Ctrl+→)", in both the mini player and Now
Playing. There is no `?` shortcuts overlay and no settings page listing them.

**Why.** The shortcuts shipped with zero discoverability — nothing on screen
said they existed, so in practice nobody would find them. Tooltips put the hint
exactly where the cursor already is, on the control the user was about to click
anyway, and cost one string each. An overlay is a new surface that has to be
discovered by a binding that is itself undiscovered, so it mostly serves people
who already suspect shortcuts exist.

Only the three keys with a matching button are advertised. Seek (←/→) and volume
(↑/↓) have no button to hang a tooltip on — they map to the sliders, which have
no tooltip — so they remain undocumented in-app.

The arrow glyphs are safe to use here: `WorkSans-Regular.ttf`'s cmap was checked
directly and covers U+2190–U+2193, so they render from the bundled font rather
than falling back (or showing tofu).

**What would reverse it.** Enough shortcuts to make per-button hints impractical,
or wanting the seek/volume keys discoverable too — either would justify the
overlay, with the tooltips kept as the first-contact hint.

---

## 2026-08-30 — Favourites: songs only, optimistic, desktop-only for now

**Decided.** Starred songs, held server-side and mirrored by
`FavouritesService`, over `/rest/star`, `/rest/unstar` and `/rest/getStarred2`.
A heart appears on desktop track rows (hidden until hovered unless already
starred), in the mini player, and on Now Playing; a third sidebar destination
lists them.

Three constraints worth keeping:

- **Songs only.** Subsonic can star albums and artists too, but folders in this
  app are *virtual*: `LibraryScanner.toFolder` sets their `id` to the library
  path, because the library is built by grouping `/api/song` results by path
  rather than from Subsonic's album entities. There is no album id to send, so
  starring a folder is not a thing that can be built without a different
  lookup — not a scope cut.
- **Optimistic, with rollback.** `toggle` applies locally, notifies, then calls
  the server, and reverts (restoring the track's original list position) if it
  is rejected. A heart that waits on a round trip before filling in feels
  broken. A rollback surfaces as a SnackBar from the shell, because a heart
  quietly reverting is otherwise indistinguishable from a mis-click.
- **Loaded at shell startup**, not when the Favourites tab is first opened.
  Every track row asks `isStarred`, and an unloaded service answers "no" — so
  hearts everywhere else would be wrong until you happened to visit the tab.

**Why.** Favourites are the one piece of per-user state Navidrome already keeps
that the app had no access to, and being server-side they stay in sync with the
web UI and any other client. Nothing about it needs a local store.

**What would reverse it.** Nothing likely for the model.

**Not done:** no offline cache of the starred list (it is one request, and the
app already requires a reachable server); no starred-albums view; the TV layout
shows no hearts.

**Update (same day):** the phone layout now has them too — see the entry below.

---

## 2026-08-30 — Favourites on the phone; the heart becomes a shared widget

**Decided.** The phone gets the same favourites: a heart on every [TrackTile]
and in [PlayerScreen]'s app bar, plus a third bottom-nav destination listing
them. `FavouriteButton` and the error listener moved out of
`lib/widgets/desktop/` to `lib/widgets/`, since both layouts now use them
unchanged.

Phone-specific choices:

- **Pull-to-refresh** on the list. Desktop re-syncs by clicking the already
  active sidebar item; the phone's tab bar has no equivalent gesture, and the
  list can go stale when another client stars something.
- **The heart is always visible**, where desktop hides it until the row is
  hovered. There is no hover to reveal it with, so `visible` stays at its
  default. The empty and error states are deliberately scrollable so the
  refresh gesture still works with no rows.
- **`BottomNavigationBarType.fixed`**, because three destinations otherwise
  switch Material to the shifting style, which hides the inactive labels.

**Why.** The service and API were already shared — only the widgets were
desktop-only — so this was UI work, not a second implementation. Favourites
starred on the phone appear on the desktop and in Navidrome's web UI, because
none of it is local state.

**What would reverse it.** Nothing likely. Android TV still has no hearts: its
D-pad UI is a separate screen set, and starring wants a deliberate focus
target rather than a heart hung off a list row.

**A latent bug this surfaced.** Putting a `Selector` inside `TrackTile` meant
every screen test needed `FavouritesService` in scope, and writing the phone
screen test then exposed two real defects in `AudioPlayerService`, both fixed
here: an in-flight load could call `notifyListeners()` *after* `dispose()`
(async completion outliving teardown), and `dispose()` was not idempotent
despite `_teardown()` being so — `ChangeNotifier.dispose` asserts on a second
call, which matters because the desktop close guard calls `shutdown()` and
Provider may dispose afterwards.

---

## 2026-08-30 — Alt + ← and Escape go back on desktop

**Decided.** `DesktopPlaybackShortcuts` gained an `onBack` handler (replacing
the narrower `onEscape`), bound to **both Alt + ←** and **Escape**. The shell
wires it to popping one level off the library navigator; Now Playing wires it
to the same plain pop its back chevron does. The chevron's tooltip now names
the key, matching what the transport buttons do.

**Why.** Folder drill-down was the one place you go deep and the only way out
was the mouse — breadcrumbs, or clicking the active sidebar item to jump to the
root. Alt + ← is the desktop convention; Escape carries over the muscle memory
Now Playing already taught.

Two things this leans on, both deliberate:

- **No collision with Ctrl + ← (previous track) or plain ← (seek).**
  `SingleActivator` matches modifiers *exactly*, so each combination fires only
  its own binding. There is a test asserting Alt + ← does not also seek.
- **`canPop()` is checked before popping.** The library navigator is nested, so
  popping its first route would leave the shell with an empty navigator rather
  than being harmlessly refused. `maybePop` is not enough here.

Back is a no-op on All Tracks and Favourites — they are flat, so there is
nothing to go back through and doing something else would be surprising.

**What would reverse it.** Wanting a full forward/back history across
destinations rather than "up one folder", which would need a navigation stack
the shell does not currently keep.

**Not covered by a test:** the shell's `_goBack` itself — the key bindings are
tested at the widget level, but there is no `DesktopShell` widget test to drive
a real folder pop through, and drilling into a folder needs a pointer, which
the environment this was written in cannot drive.

---

## 2026-08-30 — Playlists: server-side, not optimistic, add-only for now

**Decided.** Server playlists over Subsonic's five endpoints, as a fourth
destination on both layouts (sidebar item on desktop, fourth tab on phone).
`PlaylistsService` mirrors `FavouritesService`'s shape — rebound to the live
session by a proxy provider — but differs from it in three deliberate ways.

**1. Nothing is optimistic.** Favourites apply locally and roll back; playlist
edits wait for the server and then re-read. A playlist is shared, structural,
server-owned data, and — critically — **Subsonic removes tracks by *position*,
not by id** (`songIndexToRemove`). Acting on a stale local copy can therefore
delete the wrong track. Adding is by id (`songIdToAdd`) and has no such hazard,
which is why adding shipped and removing did not.

**2. Removing a track is not implemented yet.** Two things the Subsonic spec
leaves undefined decide how it must be written, and both are
implementation-defined per server:

- is `songIndexToRemove` 0- or 1-based?
- does `createPlaylist` with an existing `playlistId` *replace* the contents or
  *append* to them? (This is also the only way to reorder — there is no reorder
  parameter at all.)

`packaging`-adjacent scratch script `probe_playlists.sh` (in the session
scratchpad, not committed) answers both against a real server in one run.
**Do not guess these.** Guessing wrong deletes the wrong track or silently
duplicates a playlist.

**3. Editing is gated on ownership.** Subsonic only lets the *owner* modify a
playlist, so `Playlist.isEditableBy` hides rename/delete and disables the row
in the add-to picker for playlists owned by someone else. Unknown ownership is
treated as editable — the server is the real authority, and hiding controls on
a playlist the user *can* edit is a silent dead end, whereas showing one that
fails at least says why.

This cannot detect Navidrome **smart playlists** (`.nsp`): they are read-only
even to their owner and carry no flag in the Subsonic response, so editing one
fails server-side and surfaces as an error message.

**On naming.** `PlaybackCursor` already calls the browsing context feeding
playback "the playlist". Rather than rename that — it is load-bearing
sequencing code, and the gain would be cosmetic — the new concepts are named
unambiguously (`Playlist`, `PlaylistsService`, `playlists_screen.dart`) and the
distinction is documented on the model. If the collision ever causes a real
mistake, rename the cursor's field, not these.

**On placement.** Playlists is its own destination rather than a container that
also holds All Tracks. All Tracks is a *view of the library* — not user-created,
not stored on the server, not editable — and putting it in a list where every
other entry can be renamed, reordered and deleted invites "why can't I remove a
song from this one?". Four destinations fit both layouts comfortably (Material
allows 3–5 fixed bottom tabs).

**What would reverse it.** Wanting reorder badly enough to take the
full-rewrite path, which would also settle the `createPlaylist` question. Note
that `_buildUri` was widened to accept `List<String>` values so repeated
parameters (`songId=a&songId=b`) work — that is how Subsonic takes lists, and
there is a test asserting the encoding.

---

## 2026-08-30 — Playlist track removal, settled from Navidrome's source

**Supersedes the "add-only" part of the playlists entry above.** Removing a
track is now implemented; the two behaviours that gated it were answered by
reading Navidrome's implementation rather than probing a live server:

| Question | Answer | Where |
|---|---|---|
| Is `songIndexToRemove` 0- or 1-based? | **Zero-based** | `core/playlists/playlists.go` — `positions[i] = strconv.Itoa(idx + 1)` |
| Does `createPlaylist` with a `playlistId` replace or append? | **Replaces** | same file — `pls.Tracks = nil; pls.AddMediaFilesByID(ids)` |

Both are *behavioural* dependencies on Navidrome, not documented guarantees:
the Subsonic spec states neither. A different Subsonic server could differ, and
this is the first place to look if removal ever deletes the wrong track.

**How removal stays safe.** `PlaylistsService.removeTrack` takes the index the
UI drew *and* the track id. It re-reads the playlist immediately beforehand,
then uses the index only when it still holds the expected track — which is what
disambiguates a playlist containing the same song twice — and otherwise
locates the track afresh by id. A track already gone counts as success: the
desired state holds, and reporting an error for it would be noise.

**What would reverse it.** Nothing likely. Note that reordering is now
*unblocked* by the same finding — `createPlaylist` replacing contents is
exactly the primitive a reorder needs — but it is still not built, because it
also needs a drag-and-drop surface on both layouts.

**On the discarded probe.** A script was written to determine the two answers
empirically against a live server. Reading the source was faster, needed no
credentials, and gave a citable answer, so the script was not kept. Recorded
here because the *questions* remain the right ones to ask of any future
Subsonic-behaviour uncertainty — check the server's source first.

---

## 2026-08-30 — Playlist UI tests, and the three bugs they found

**Decided.** The playlist screens are covered by widget tests
(`add_to_playlist_test.dart`, `playlists_screen_test.dart`,
`desktop_playlists_screen_test.dart`) on top of the service tests, closing the
gap where playlists had service-only coverage while favourites had three
layers.

They run against `FakePlaylistServer` (test/support/fake_playlists.dart), an
in-memory Subsonic that **applies writes for real** — including removing by
zero-based index, as Navidrome does. So the assertions are "the row is gone",
not "this request was sent", and they stay true if the service changes how it
gets there.

**They found three real bugs, all fixed here:**

1. **A disposed `TextEditingController`.** The desktop rename dialog created a
   controller, passed it to a `TextField`, and disposed it as soon as
   `showDialog` returned — while the dialog's *exit animation* still had the
   field mounted. Fixed by making `PlaylistNameDialog` stateful and owning its
   own controller, which both the create and rename paths now share.

2. **A playlist opened directly was never editable.** `loadTracks` fetched a
   fresh `Playlist` but discarded it unless the list had already been loaded,
   so `byId` returned null and the detail screen's ownership check failed
   closed — no remove option. Invisible in the app only because both shells
   call `load()` at startup. Now the detail fetch keeps what it learned.

3. **Desktop context-menu labels overflowed.** A popup menu constrains its
   items to ~256px; "Remove from playlist" plus its icon exceeded that and
   painted an overflow stripe. The labels are now `Flexible` with ellipsis, so
   a long one degrades instead of overflowing.

**Two test-harness facts worth keeping.** Desktop screens need a desktop-sized
surface — use `tester.binding.setSurfaceSize`, not `tester.view.physicalSize`,
whose reset runs while the tree is still mounted and trips a framework
assertion. And any screen showing a `TrackTile` or `DesktopTrackRow` now needs
`FavouritesService` in scope, because both carry a favourite heart.

**What would reverse it.** Nothing. Note the pattern these bugs share: each was
invisible in normal use and only appeared under a slightly different entry
order — a dialog dismissed, a screen opened directly, a label just too long.

## 2026-08-30 — All Tracks is a Navidrome smart playlist, not an app concept

**Decided.** Delete the special-cased "All Tracks" card and its screens from
both shells. The list is now a `.nsp` smart playlist living at the music-folder
root on the server, and the app renders it as an ordinary playlist with no
knowledge that it is special.

`all-tracks.nsp`:

```json
{
  "name": "All Tracks",
  "public": true,
  "all": [ { "gt": { "duration": -1 } } ],
  "sort": "title"
}
```

**Why.** The pinned card was a permanent seam: it needed `LibraryScanner`
injected into both playlists screens purely to render a count, it had to be
excluded from the add-to-playlist picker, it had no cover art, and it sat
*outside* `service.playlists` so the header read "0 playlists" while a playlist
was plainly on screen. Every one of those was a symptom of modelling a playlist
as not-a-playlist. Moving it server-side deleted all of them at once, and
Navidrome throws in generated cover art for free.

**Two things worth keeping.**

*Why `duration`, not `playCount`.* Navidrome's docs suggest `playCount > -1` as
the match-everything rule. It silently doesn't. `play_count` arrives via a
`LEFT JOIN` on `annotation` and is only made NULL-safe in the **select** list
(`coalesce(play_count, 0) as play_count`, `persistence/sql_annotations.go`); a
criteria rule lands in the `WHERE`, where an unplayed track's value is NULL and
`NULL > -1` is NULL. The playlist would have contained only songs already
played. `duration` is a plain `media_file` column and is never NULL.

*`readonly` replaced the ownership guess.* `Playlist.isEditableBy` previously
compared owners and carried a comment admitting it could not detect smart
playlists. Navidrome does report this, via OpenSubsonic's `readonly` field
(`server/subsonic/playlists.go`), which is authoritative for smart playlists,
foreign ownership *and* `TracksEditable()` — strictly better than what we
inferred. Because every consumer already routed through `isEditableBy`, one
model change fixed the picker, the overflow menu and track removal on both
platforms. Without it, All Tracks would have been offered as an add-to
destination and failed server-side after the fact.

**What would reverse it.** Load time. The old screens read `LibraryScanner`'s
local cache; a playlist fetches `getPlaylist` with all 4,384 entries over the
network. If that proves slow in practice, the fix is to special-case the
*fetch* (serve a known-smart playlist's tracks from the library cache), not to
bring back a special-cased card — the card was the part that hurt.

**Left behind, deliberately.** `screens/all_tracks_screen.dart` and
`screens/desktop/desktop_all_tracks_screen.dart` are now unreachable. They are
kept until the load-time question above is settled, since they are exactly what
a cache-backed path would reuse.

## 2026-08-30 — Filling a playlist is playlist-first, not only track-first

**Decided.** Add `AddSongsToPlaylist` — a search-and-add picker opened *from* a
playlist — alongside the existing `AddToPlaylist`, which is opened from a track.
Creating a playlist now also opens it.

**Why.** The only way to fill a playlist was track-first: find a track,
right-click (desktop) or long-press (phone), pick the playlist. That is fine for
one song noticed in passing and hopeless for twenty, and it made "New playlist"
a dead end — you named it, landed back on the grid, and nothing on screen said
what to do next. The empty state's advice ("Long-press a track anywhere to add
it here") was accurate and useless.

The two directions are complements, not duplicates: track-first answers "where
does this song go?", playlist-first answers "what goes in here?".

**Adds are committed one at a time, not batched on close.** The sheet stays
open, and each tap writes immediately and flips the row to a tick. Batching
would be fewer requests, but dismissing the sheet mid-way — the single most
likely thing a user does — would silently discard the work.

**Search filters `LibraryScanner`'s cache, not `search3`.** Results are instant
and keystroke-by-keystroke with no debounce, no spinner and no failure path.
The cost is that it only finds what the last scan saw. This reintroduces a
`LibraryScanner` dependency to the playlist screens, which the entry above had
just removed — but for a different reason: that one injected a scanner to
render a *count*, this one genuinely searches the library. Results cap at 100;
refining the query beats scrolling.

**`PlaylistsService.create` now returns the new `Playlist`, not a bool**, so the
caller can open it. Which playlist that is gets settled without trusting
`createPlaylist`'s response body — the id it reports is used when present, and
the fallback is whichever id is in the list after the re-read and was not
before. The body varies between servers; the fake server in our own tests
returns none at all, which is what surfaced this.

**What would reverse it.** If library search needs to match things the cache
does not hold (genre, year, comments), the filter has to become `search3` and
grow a debounce and an error state with it.


## 2026-08-30 — Ctrl+F focuses search, via a registry of mounted search fields

**Supersedes** the "Not included: Ctrl+F" note in the desktop-shortcuts entry
above, which deferred it for want of "a focus registry keyed on the active
destination". This is that registry.

**Decided.** `SearchFocusScope` (an `InheritedWidget` provided by
`DesktopPlaybackShortcuts`) lets any `DesktopSearchField` below register itself
on mount. Ctrl+F walks the registrations newest-first and focuses the first one
that will actually accept focus, also selecting whatever is already typed so the
next keystroke replaces the query. The field's tooltip advertises it, matching
the "Action (Ctrl+X)" convention the transport controls already set.

**Why a registry rather than passing the destination down.** The shortcut layer
sits *above* the screens that own search fields, and inherited widgets only pass
data downwards — so the field has to announce itself upwards. Keying on the
active destination, as the deferred note proposed, would have worked too but
requires the shell to know which destinations are searchable; registration keeps
that knowledge in the one widget that has it.

**Newest-first is what makes the nested navigator right.** A folder screen
pushed on the library's navigator registers after the list behind it, so it
wins; popping it disposes and deregisters, and the one behind takes over.

**What settles the `IndexedStack` problem the old note raised.** The shell keeps
all three destinations mounted, so the Library's field stays registered while
Playlists is on screen. `IndexedStack` wraps non-selected children in
`ExcludeFocus`, which makes requesting focus on them a *silent no-op* — the
shortcut would have looked broken rather than failed loudly. So a field reports
itself focusable only if `canRequestFocus` holds and every ancestor has
`descendantsAreFocusable`; a field that declines is skipped, not unregistered,
because it becomes focusable again when its destination is selected.

**The typing guard is relaxed for this one binding.** Every other shortcut is
suppressed while an `EditableText` has focus. Ctrl+F is suppressed only when the
focused field is *not* a registered search box — so it selects the query when
you are already in search (what a browser's find bar does) but will not yank
focus out of a rename dialog.

**What would reverse it.** A second searchable widget on one screen, or a
searchable surface that is not a `DesktopSearchField` — either would make
"newest registration" too blunt, and the registry would need an explicit
priority or scope key.

---

## 2026-08-30 — Window chrome is taller, and the shell's back chevron actually shows

**Decided.** `AppMetrics.titlebarHeight` goes from 48 to 72 — 56 was tried
first and still read as thin against a real 1080p window, per a screenshot.
Everything else in the bar scaled up with it rather than just leaving more
empty padding: the app glyph 20→26px, its icon 14→17, the context label
13→15px, the window-control glyphs 10→13px, and both the back chevron's icon
(20→26) and every chrome button's hit target (32/44→50px wide) grew to match.
More load-bearing than any of those numbers: `DesktopShell` now passes
`onBack` to its own `WindowChrome`, which it never did — the chevron only ever
appeared on `DesktopPlayerScreen`. Library and Playlists drill-down have had no
mouse target at all until now.

**Why.** The "Alt + ← and Escape go back on desktop" entry above solved
*discoverability* for the keyboard but left the mouse with nothing — the shell
kept `_goBack` and `canPop()` entirely internal, wired only to key bindings.
Whether a user reaches for Alt+← at all is a matter of habit, and the chrome
already had a chevron shape for exactly this job on one screen; it just wasn't
wired up on the other. Narrowing that one button to 32px while its siblings sat
at 44px wasn't chosen for any reason tied to how often it gets clicked.

**How the chevron knows when to show itself.** `_TopRouteObserver` is renamed
`_NavigatorTracker` and now publishes a `canPop` flag alongside the route name,
one instance per nested navigator (library, playlists — Favourites has neither,
it never pushes anything). The shell reads both through an `AnimatedBuilder`
over `Listenable.merge([...])`, replacing the single `ValueListenableBuilder`
that only ever watched the library's route name. Deriving "show the chevron"
from `canPop()` directly (read during `build()`) would not have rebuilt when a
nested navigator changed under it — the same reason the route name was already
a notifier rather than a live read.

**A side effect worth having.** The title bar's context line now follows into
an open playlist ("Roadtrip — Anywhere Music Player"), the same way it already
followed into a folder. It never did before, because nothing was tracking the
playlists navigator's top route at all.

**A drive-by fix.** Two doc comments in `desktop_shell.dart` still said "All
Tracks" was a flat destination alongside Favourites — leftover from before All
Tracks was folded into Playlists (see the smart-playlist entry above).
Corrected while in the neighbourhood; `SidebarDestination` has had only
`library`, `favourites`, `playlists` since that merge.

**Test-environment note, correcting the earlier entry.** "Alt + ← and Escape go
back on desktop" said driving a folder pop through the shell needed a pointer
the writing environment couldn't simulate. `test/screens/desktop_shell_test.dart`
does exactly that — pumps the real `DesktopShell`, taps into a playlist, taps
the chevron, and asserts `DesktopPlaylistScreen` actually leaves the tree. The
one wrinkle: popping a real `MaterialPageRoute` runs a ~300ms transition, unlike
the dialogs every other `settle()` in this codebase waits on, so that one
assertion needs 16 short pumps instead of the usual 8 — first test in the suite
to push and pop a full screen rather than a dialog.

**What would reverse it.** Wanting the chrome narrower again — a TV-style
remote-only mode, say, where a mouse target is wasted space. `onBack` staying
optional on `WindowChrome` means dropping the shell's wiring is a one-line
revert; the height and button-width bumps are independent of it.

---

## 2026-08-30 — The hand cursor is an explicit opt-in, per button family

**Decided.** Every button theme in `buildAppTheme` sets
`enabledMouseCursor: pointerCursor` (and `disabledMouseCursor: basic`), and
`AccentCircleButton` sets `mouseCursor` on its `InkWell` directly. A regression
test, `test/widgets/pointer_cursor_test.dart`, asserts the resolved cursor for
each widget family.

**Why this is not redundant.** Material's default is
`WidgetStateMouseCursor.adaptiveClickable`, which resolves to
`kIsWeb ? click : basic`. On desktop, Flutter gives buttons the plain arrow *on
purpose* — native macOS and Windows treat the hand as a hyperlink affordance,
not a button one. This app disagrees and wants the hand on anything clickable,
which is what `HoverRow` had always done for rows. That mismatch is what the
user reported: rows changed the cursor, buttons didn't.

**Why it needs five theme entries plus one widget.** Only `ButtonStyleButton`
subclasses read a button theme, so elevated, outlined, text, filled and icon
buttons each need their own. `InkWell` is not one of them, so no theme reaches
`AccentCircleButton` and it sets the cursor itself.

**Disabled controls keep the arrow.** A hand over something that does nothing
when clicked misdescribes the control, so `disabledMouseCursor` stays `basic`
everywhere. There is a test for this on `AccentCircleButton`.

**What makes this worth a test rather than trusting the theme.** The failure is
silent — no throw, no log, the button still works, and it only shows up under a
real pointer. A future Flutter upgrade flipping the default, or someone tidying
these lines away as boilerplate, would go unnoticed until a user complained
again. Cursor resolution turns out to be testable headlessly via
`MouseTracker.debugDeviceActiveCursor`, so the test costs nothing to run.

**Two dead ends worth recording, so they aren't retried.** This looked like a
platform fault for a while: hover was assumed broken, then Wayland was
suspected, then Tooltip's nested `MouseRegion(cursor: defer)` was suspected and
`_ChromeIconButton` was briefly rewritten to wrap its Tooltip instead of sitting
inside it. `GDK_BACKEND=x11` changed nothing, and the Tooltip rewrite was
reverted after a test proved both orders resolve `click` identically. The clue
that settled it was the user's own observation that rows worked and buttons did
not — same cursor value, same app, same session, so nothing below the widget
tree could be at fault.

**What would reverse it.** Deciding the app should follow native desktop
convention after all, in which case delete the theme entries and the test
together rather than one without the other.

---

## 2026-08-30 — One `DesktopErrorState`, not three

**Decided.** `desktop_library_screen.dart`, `desktop_playlists_screen.dart` and
`desktop_favourites_screen.dart` each carried a private `_ErrorState` — icon,
message, Retry button — used identically in all three: an error with nothing
loaded yet is a dead end that needs a retry. They'd drifted apart with no
reason tied to the screen. Library's was the outlier (red message text, no
icon, `ElevatedButton`); playlists and favourites already agreed with each
other (`error_outline` icon, muted text, `OutlinedButton`). Replaced all three
with `DesktopErrorState` in `desktop_primitives.dart`, standardised on the
majority style.

**Why the library one moved rather than the other two.** Nothing about a
library-scan failure is more severe than a playlists-load failure — both are
"couldn't fetch the list, here's why, try again" — so there was no reason for
one to read as more alarming than the others. Two screens already agreeing was
the tie-breaker.

**What would reverse it.** A screen that genuinely needs a different register
for its errors (blocking vs. transient, say) — then it stops being one shared
widget and becomes a `severity` parameter on it, not three private copies again.

---

## 2026-09-09 — A launch inside six hours of the last scan skips the folder walk

**Decided.** `LibraryScanner.scan()` used to do the same two things on every
launch: hydrate from the on-disk cache, then *always* walk the server's folder
tree behind it. The walk is one request per directory — 239 of them on this
library, about 7.5 s at 8 concurrent — and it ran even when the cache was
minutes old. It now short-circuits: if the cache carries a `scannedAt` stamp
younger than `LibraryScanner.cacheFreshFor` (6 hours), the launch renders from
disk and stops there.

The stamp was already being written into the cache file; nothing but `load()`
discarding it stopped this working before. `LibraryCache.loadEntry()` returns
`(tracks, scannedAt)` and `load()` is now a wrapper over it, so no caller that
only wants the tracks had to change.

**Why six hours, and why a stamp rather than a flag.** The number is a guess at
"a session's worth", tuned to the failure it prevents: relaunching the app
several times in an evening, each time paying 7.5 s for a library that did not
change. It is one named constant, deliberately, so it is one edit to retune. A
stamp rather than "did we scan this process" because the win is across launches,
not within one — an in-memory flag is exactly what already existed.

**A missing or future-dated stamp counts as stale.** An unparseable value, a
cache from an older build, a clock that jumped — all fall back to scanning. The
cost of scanning when we needn't is a slow launch; the cost of the other
direction is a library that silently disagrees with the server, which is the
worse of the two and much harder to attribute.

**The escape hatch is a real requirement, not a nicety.** Skipping the walk
means "I just added an album" no longer resolves itself by restarting, so both
layouts grew a way to force it: pull-to-refresh on the phone home screen and a
refresh button in the desktop library header, both onto `rescan()`, which now
passes `force: true` through `scan()`. The phone's empty state moved from a bare
`Center` to `CentredMessage` for the same reason — `CentredMessage` stays
scrollable, so the pull still works when the library has nothing in it. Android
TV has no such affordance; it is a lean-back surface with no obvious gesture for
it, and a TV that is 6 hours stale self-heals on the next launch.

**What would reverse it.** A server that changes often enough that six hours is
visibly wrong (retune the constant first, not the design), or moving to a real
change signal — Subsonic has no library-changed endpoint, but the `getIndexes`
response defines a `lastModified` attribute, and honouring it would replace the
guess with an answer. Check what this server actually puts there before building
on it; the walk already proved `getIndexes` answers differently than expected
here. That is the version of this worth building if the constant becomes a
nuisance.

---

## 2026-09-09 — Releases are desktop-only; Android is no longer published

**Decided.** `.github/workflows/release.yml` no longer builds or publishes an
APK. The `android` job is gone, the `include_android` dispatch input with it,
and `release` waits only on `windows` and `linux`. A `v*` tag now produces
`-setup.exe`, `-x86_64.pkg.tar.zst` and `SHA256SUMS`.

**What did not change.** Android phone and TV are still supported targets:
`flutter build apk` works, the D-pad UI and `LEANBACK_LAUNCHER` are untouched,
and nothing in the app was removed. The change is to distribution only.

**The keystore secrets stay.** ~~Superseded the same day — see the entry
below.~~ `ANDROID_KEYSTORE_BASE64` and the three passwords are now dormant. Deleting them would save nothing and cost real
recovery: an upload keystore is unrecoverable, and any device with the app
installed can only take updates signed by the same key. Re-adding four secrets
is the cheap half of restoring the job.

**What would reverse it.** Wanting an installable Android build published
again — restore the job from git history and flip `release`'s `needs` back. The
secrets it needs are already there, so it is one revert, not a re-setup.

---

## 2026-09-09 — The Android keystore secrets were deleted after all

**Supersedes** the "keystore secrets stay" paragraph in the entry above, made
hours earlier the same day.

**Decided.** The four `ANDROID_*` repo secrets are deleted. The earlier
reasoning — keep them, because "a keystore is unrecoverable and re-adding
secrets is cheaper than regenerating a key" — was wrong on its own terms.
**GitHub Actions secrets are write-only.** `ANDROID_KEYSTORE_BASE64` could never
be read back out, not even to make a backup before deleting it, so it protected
no recovery path and was never an off-machine copy of the key. What it actually
was is an unused credential in a repo, which anything able to edit a workflow
can echo into a log. Re-adding four values is five minutes if the CI APK build
ever returns.

**What the earlier entry got right, and matters more.** The keystore genuinely
is unrecoverable, and deleting the secrets does not change that either way. Its
survival rests entirely on `android/app/upload-keystore.jks` being copied
somewhere off the machine — it is gitignored, so the repo never held it, and the
secret was not a second copy in any usable sense. On 2026-09-09 that file
existed in exactly one place. Verify a real backup exists rather than assuming
one does.

**What would reverse it.** Restoring the Android release job, which needs the
four secrets re-added from the keystore and the passwords in Vaultwarden.
