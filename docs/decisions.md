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
