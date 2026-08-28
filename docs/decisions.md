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

**Note.** `lib/screens/folder_detail_screen.dart` (phone) has the identical bug — its own `_filteredTracks` filters only `_tracks` too. Left alone this pass since it wasn't part of the desktop work in progress; worth the same fix.

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
