# Merged work order — architecture + code-quality reviews

**Date:** 2026-08-23 · **Branch:** `main` @ `8b199b1` (clean worktree)
**Merges:** [`2026-08-22-code-quality-review.md`](2026-08-22-code-quality-review.md)
(findings F1–F3, B1–B4, J1–J4, T1–T4) and
[`2026-08-22-architecture-review.html`](2026-08-22-architecture-review.html)
(Candidates 01–08).

Both source reviews were written against `5634a08`. Every code claim spot-checked
against `8b199b1` on 2026-08-23 still holds — see *Verification* at the bottom for
what was and was not re-confirmed. The two documents overlap on
`audio_player_service.dart`; this file resolves that overlap into one sequence and
reorders by live risk rather than structural payoff.

**Not re-run:** `flutter test` (claimed 150 pass / 3 fail) and `flutter analyze`
(claimed 38 issues, 0 errors). Re-run both before trusting those numbers.

---

## The ordering rule

The source reviews rank by structural payoff. This one ranks by **live risk
first, then structure**, with one extra constraint: where a quality fix and an
architecture candidate touch the same code, do whichever one subsumes the other —
never both.

| Source finding | Merged into | Why |
|---|---|---|
| F2 (`peekNextTrack` vs `_nextPlaylistIndex`) | **Candidate 01** | F2's fix *is* C01's cursor extraction in miniature. Fixing it as a private-method refactor and then hoisting it into `PlaybackCursor` is the same surgery twice. |
| F3 (`await play()`) + J3 (merge recovery into `_loadAndPlay`) | **Step 5**, alongside C01 | Load orchestration, not cursor state — survives C01 and lands cleanly next to it. |
| T1 (`Track.filename` is a path) | **Candidate 05** | Same file, same "where do Tracks come from" question. |
| T3 (`LibraryCache` static, takes an api) | **Candidate 07** | C07 removes the `api:` argument that is T3's whole complaint. |

Everything else stands alone.

---

## Sequence

### 1 · J2 — `AuthService.initialize()` can wipe stored credentials

The only finding in either review that loses user data. Independent of all other
work; do it first regardless of what else gets scheduled.

`lib/services/auth_service.dart:100` — the outer `catch` calls `_clearStorage()`
and covers the six `_secureStorage.read()` calls at the top of the method. A
`flutter_secure_storage` plugin failure on startup therefore deletes the saved
credentials — the exact outcome the inner code-40 branch was written to prevent.
`_migrateFromSharedPreferences` and `_clearStorage` have their own catches, so
the reads are the live exposure.

**Minimum fix:** narrow the outer catch so it cannot reach `_clearStorage()`;
only a Subsonic code-40 rejection clears storage.

**Full fix (J2 as written):** collapse `_apiService` + `_currentUser` into one
nullable `Session`, extract a `_Credentials` record with `_read`/`_write`/
`_delete`, and flatten the nesting so the contradiction cannot re-form. The
three-line `_apiService = api; _currentUser = User(...)` block currently appears
three times in the method.

→ verify: `flutter test test/services/auth_service_test.dart`

### 2 · T2 — `LibraryCache` "atomic write" is not atomic on Windows

Not hypothetical: the review's own test run surfaced
`PathAccessException: Cannot rename file ... (OS Error: Acesso negado, errno = 5)`
twice.

`lib/services/library_cache.dart:96-98` — `writeAsString` → `delete()` →
`rename()`. `File.rename` cannot replace an existing file on Windows, hence the
delete, which opens a window where neither file exists. The doc comment at
line 15 promises the opposite.

**Fix:** write → rename-old-aside → rename-new → delete-old, and correct the
comment to match whichever guarantee actually holds.

→ verify: `flutter test test/services/library_cache_test.dart`

### 3 · F1 — two one-liners, one of them a production leak

`lib/services/audio_player_service.dart:836` — `seedForTest` stores the caller's
list by reference (`_playlist = playlist`) while production does
`List.from(tracks)`. A seam whose copy semantics differ from the path it stands
in for makes tests pass and fail for reasons the product never exhibits.

`lib/services/audio_player_service.dart:91` — `get playlist => _playlist` hands
out the mutable internal list. `get queue` (line 93) correctly returns
`List.unmodifiable`. This one is the production defect: any screen holding the
reference can reorder the player's playlist behind its back.

```dart
_playlist = List.of(playlist);                    // seedForTest
List<Track> get playlist => List.unmodifiable(_playlist);
```

→ verify: `flutter test test/services/audio_player_service_sequencing_test.dart`

### 4 · B1 / B2 — finish what the last session started

The worktree is clean and no `android/.kotlin` files are tracked, so the index
states described as B1/B2 are resolved. Two loose ends remain:

- `.gitignore` still has **no `android/.kotlin/` entry** — the crash logs will
  reappear and be stageable again.
- `Output/AnywhereMusicPlayer_Setup.exe` is **still tracked**, already rewritten
  across 7 commits. Every release permanently adds a copy to every clone.

```bash
printf 'android/.kotlin/\nOutput/\n' >> .gitignore && git rm --cached Output/AnywhereMusicPlayer_Setup.exe
```

Attach installers to GitHub releases instead. B3 (pubspec.lock churn) and B4
(Kotlin trap documentation) are already resolved.

### 5 · F3 + J3 — one load path, and await the play

`_handleStreamError` (`audio_player_service.dart:255-272`) re-implements
`_loadAndPlay` (`:422-437`) and, in copying it, omits four steps:
`_logStreamParams`, `_audioHandler.updateTrackInfo`, `_updateWindowsMetadata`,
and `_evictAudioCacheIfNeeded`. A track that recovers from a drop therefore never
contributes to Android cache eviction. Nobody decided that.

**Fix:** one method —
`Future<void> _loadAndPlay(Track track, int token, {Duration? resumeFrom})`.
`_handleStreamError` becomes: bounds check → capture position → call it.

**F3, refined.** The reviews attribute the misclassified-drop window to the
recovery path. It is broader than that: `_player!.play()` is unawaited in **both**
paths (`:263` and `:428`), while `_isLoading` clears in each `finally`. So there
is a window in *ordinary* playback too where the service reports "not loading,
not playing", and `_handleStreamError`'s `!wasPlaying` guard misreads a drop
arriving in it as unrecoverable. Merging the paths fixes it once — either by
awaiting `play()` or by keying the guard on intended-to-be-playing rather than
the backend's instantaneous `playing` flag.

Do this **before or with** Candidate 01, not after — C01 moves cursor state out
of this file and is easier to review against a single load path.

→ verify: `flutter test test/services/audio_player_service_playback_test.dart`

### 6 · Candidate 01 — lift the sequencer out of the player (subsumes F2)

The largest item, and the one both reviews point at. `audio_player_service.dart`
is the most-changed file in the repo (12 commits) and the largest (894 lines),
holding five unrelated concerns behind ~40 public members. Seven
`@visibleForTesting` holes are drilled through its wall; 425 lines of sequencing
tests never call a production entry point. The tests have already marked where
the seam belongs.

Move `_playlist`, `_currentIndex`, `_queue`, `_shuffleOrder`, `_shufflePos`,
`_playingFromQueue`, `_isShuffleEnabled`, `_repeatMode` into a plain Dart class
with no Flutter and no just_audio import:

```dart
class PlaybackCursor {
  Track? get current;
  Track? peekNext();          // no mutation
  Track? advance();           // queue > playlist > null
  Track? rewind();
  Track? jumpToQueued(int i);
  Track? jumpToUpcoming(int i);
  void  start(List<Track> ctx, {int at, bool shuffled});
  void  enqueue / dequeue / move / reorderUpcoming;
  List<Track> get upcoming;
  set shuffle / repeat;
}
```

`AudioPlayerService` keeps its public API and delegates. All seven `*ForTest`
members are deleted.

**F2 is resolved by construction here.** Today `peekNextTrack` (`:494`) and
`_nextPlaylistIndex` answer the same question differently in two places:
`peekNextTrack` bails on `_currentIndex < 0` (a sequential-mode precondition
applied to the shared path) where `_nextPlaylistIndex` happily returns
`_shuffleOrder[1]`; and at end-of-order under repeat-all, `_nextPlaylistIndex`
regenerates the order while `peekNextTrack` returns the old one's `[0]`. That
second row is a live product bug — `peekNextTrack` drives cover-art prefetch in
`player_screen.dart`, so the last track of every shuffled pass prefetches the
wrong cover. Building `advance()` on top of a pure `peekNext()` removes the
possibility rather than fixing the instance.

**Cautions.** The behaviour being moved is genuinely subtle: queue-over-playlist
priority, shuffle anchoring on regenerate, the `_playingFromQueue`
return-to-playlist rule, repeat-all wraparound in both directions. Port the
existing 425 lines of tests first, re-pointed at the new interface, and keep them
green through the move. Per `CLAUDE.md`, verify on **both** Windows and Android —
`flutter test` passing says nothing about either audio backend.

This does **not** contradict the logged "sequencing is hand-rolled in Dart"
decision; it gives that decision its own module, making the eventual reversal a
single-file deletion instead of surgery through an 894-line class.

### 7 · Candidate 02 — one verb per play intent

Six call sites across five files hand-assemble "shuffle-play these tracks" from
`toggleShuffle()` + `playPlaylist(tracks, -1)`, where `-1` is an undocumented
"pick a random start" sentinel that only randomises if shuffle happens to be on,
and the read-then-toggle guard exists purely because `toggleShuffle()` has no
setter form.

Sites: `home_screen.dart:171 :363 :489`, `all_tracks_screen.dart:162`,
`folder_detail_screen.dart:124`, `tv_home_screen.dart:71`. (The `toggleShuffle()`
calls in `player_screen.dart:662` and `tv_player_screen.dart:298` are genuine
toggle buttons — leave them.)

```dart
Future<void> play(List<Track> tracks, {int from = 0});
Future<void> playShuffled(List<Track> tracks);
void         setShuffle(bool enabled);
```

Needs `PlaybackCursor.start(shuffled:)` from step 6 to be more than a wrapper.

### 8 · Candidate 05 — let `Track` own every way it is built (subsumes T1)

`LibraryScanner.scan()` builds `Track` objects by hand from Navidrome's native
API payload, in a loop inside a scan method (`library_scanner.dart:97-118`) — a
third parser living outside the model, disagreeing with the other two on every
key name because the native API genuinely uses different ones (`coverArtId` vs
`coverArt`, `rgTrackGain` vs `replayGain.trackGain`, `createdAt` vs `created`).

**Confirmed drift:** the scanner never sets `folderName`, so it defaults to `''`
(`track.dart:32`) on every track in the library — while `fromSubsonic` computes
it and `toJson` persists it. The scanner path is the one that produces the entire
library on every launch.

**Fix:** add `Track.fromNativeApi(json, api)` beside its two siblings and have
the scanner call it. Three factories side by side make a missing field obvious
instead of buried 100 lines into a scan method.

**T1 folds in here.** `filename` means two things: `fromSubsonic` sets it to
`json['path']` (a library-relative path) but falls back to a bare
`'$title.$suffix'` when the server sends no path, while the scanner always sets a
full path — and `_buildFolderTree` (`library_scanner.dart:171`) splits it on `/`
and treats it as a path, so a track without a server path silently lands at the
tree root. Rename to `path` while all three factories are open, and make the
no-path case explicit rather than degrading into a filename that happens to
parse.

Small and independent of steps 6–7 — can be pulled forward if C01 stalls.

### 9 · Candidate 03 — one `CoverArt` widget

Six facts (dpr multiply, matching rounded size passed to *both* `coverUrl(size:)`
and `coverCacheKey(size:)`, null-check, `ClipRRect(radius: 4)`, fallback icon
twice) restated at six render sites: `home_screen.dart:517 :562 :647`,
`all_tracks_screen.dart:378`, `folder_detail_screen.dart:424 :550`.

The `48 * dpr` expression is written twice per site, so URL size and cache-key
size can fall out of step in a single-character edit — producing a 100% cache
miss, not a crash. This is the same failure mode `decisions.md` already documents
for the Android stream cache, reappearing in the image cache.

```dart
CoverArt(this.source, {required this.size, this.radius = 4});
```

Pair with a `CoverArtRef` mixin so `Track` and `Folder` stop carrying identical
copies of `coverUrl`/`coverCacheKey`.

### 10 · Candidate 04 — one `TrackTile`, not three (needs 9)

`_TrackTile` (`home_screen.dart:630`), `_AllTracksTile`
(`all_tracks_screen.dart:314`) and `_FolderTrackTile`
(`folder_detail_screen.dart:482`) share a body: a `Selector` on
`currentTrack?.id`, blue-and-bold current-track styling, an `Icons.equalizer`
marker, the cover block from step 9, and `formattedDuration` as subtitle.

**Confirmed drift:** commit `20906a4` added swipe-right-to-queue to two of the
three. `Dismissible` appears in `all_tracks_screen.dart` and
`folder_detail_screen.dart` but **not** `home_screen.dart` — so root tracks and
search results are the only places in the app where swiping right does nothing.

One public `TrackTile` in `lib/widgets/` with the two genuine variations as
parameters (nullable `leadingIndex`, `swipeToQueue` defaulting true). Fixes the
missing gesture as a side effect and makes the next tile change land everywhere
by construction.

### 11 · J1 — `SubsonicApiService`'s nine copies of one request envelope

609 lines, of which ~90 are the same four-line try/uri/get/parse shape.
Confirmed counts: **9** copies of `if (e is SubsonicApiException) rethrow` and
**5** copies of the trailing-slash normalization for a value that cannot change
after construction. `getFolders` and `getRootTracks` are the same method
differing only in what they accumulate.

- `late final String _baseUrl` in the constructor — deletes 5 copies.
- One private `_request(endpoint, {params, cacheKey, failureContext})` — deletes
  ~90 lines and removes the hazard that one of the nine forgets the `rethrow`
  guard and double-wraps the error.
- `_rootContents()` returning a record; the two public methods project from it.

Also here: T4 — `_getFromCache<T>` casts `dynamic` to `T?` unchecked against a
stringly-typed key, and `getIndexes`/`getMusicDirectory` return raw
`Map<String, dynamic>` while every other method returns models, leaking
Subsonic's JSON shape into callers.

### 12 · Candidate 06 — a `NowPlayingPresence` seam

"Tell the OS what is playing" is implemented twice — Windows via
`_updateWindowsMetadata` + a lazily-initialised singleton + `windowManager.setTitle`
+ a wakelock toggle; Android via an optional `MusicAudioHandler?` null-checked at
each use — and the player interleaves both inline behind `if (_isWindows)`. Two
adapters already exist, so the seam is real rather than hypothetical.

```dart
abstract class NowPlayingPresence {
  void bind(PlaybackCommands c);
  void show(Track t);
  void setPlaying(bool playing);
  void clear();
}
// WindowsPresence · AndroidPresence · NoPresence (const no-op, the test default)
```

Biggest win is the test surface: `playback_test.dart` currently mocks the raw
`window_manager` MethodChannel purely to stop an unrelated test throwing. A
`NoPresence` default deletes that workaround. Much easier once step 6 has pulled
cursor bookkeeping out of the playback code.

### 13 · Candidate 07 — `StreamUrlResolver` (subsumes T3) — **scope with care**

`Track` and `Folder` import `SubsonicApiService`, so the domain model depends on
the transport, every construction site threads an `api:` argument, and every
`Track` in memory holds a live password-equivalent token+salt for the whole
session.

**T3 folds in:** `LibraryCache` is an all-static class taking a
`SubsonicApiService` purely to re-mint URLs, so it has no seam — tests reach it
only by globally faking `path_provider`, which is why the Windows rename failures
from step 2 leak into unrelated screen tests. C07 removes the argument; making
`LibraryCache` an instance with an injected directory removes the rest.

⚠ **Boundary.** `decisions.md` records "cached cover art stores the id, not the
resolved URL" with the reversal condition *"nothing — this is a security floor"*,
enforced by schema v3. C07 extends that reasoning to the in-memory copy, which is
compatible — but any exploration here must preserve id-only persistence. Treat
the on-disk format as out of scope, not as something to revisit.

### 14 · Candidate 08 — screen rituals (speculative)

Follow-the-playing-track is ~35 lines duplicated near-verbatim across
`all_tracks_screen.dart` and `folder_detail_screen.dart` (same `_followedTrackId`
guard, same `alignment: 0.3`, same 400 ms easing, same bare `try/catch` in
dispose); only the index mapping differs. Scanner-waiting is improvised three
different ways.

Marked speculative in the source review, and that stands — but **pull one bug out
of it now rather than waiting**: `folder_detail_screen` reads the scanner once and
never listens, so it does not update if a background refresh lands while it is
open. That is a behaviour gap, not UI plumbing, and does not need the
`FollowingTrackList` / `LibraryData` widgets to be fixed.

### 15 · Analyzer sweep

Claimed at review time (re-run to confirm): 38 issues, 0 errors.

- 6 × `unnecessary_non_null_assertion` (warnings) — `library_scanner.dart:75,93,106,107`,
  `audio_player_service.dart:164,429`. Residue of a null-check that moved; they
  obscure where the real nullability lives.
- 2 × `use_build_context_synchronously` — `home_screen.dart:146-147`.
  `_handleLogout` uses `context` after three `await`s.
- 30 info-level nits (`unnecessary_underscores` ×24, one deprecated
  `withOpacity`, three `prefer_const_constructors`). One batch.

Also J4, whenever the test helpers are next touched: `waitForAsyncWork` and
`pumpAndWaitForAsyncWork` in `test/support/pump_helpers.dart` differ by one line,
and the 12-line comment explaining the zone-binding subtlety is duplicated with
them — so the hardest thing in the file to keep correct exists twice.

---

## The pattern underneath

Four separate findings — F2, C03, C04, C05 — are the same mechanism: **a copy
diverged silently and nothing caught it.**

| | Copies | What drifted | Visible as |
|---|---|---|---|
| F2 | 2 | end-of-shuffle regeneration | wrong cover prefetched on last shuffled track |
| C03 | 6 | `size * dpr` written twice per site | 100% image-cache miss |
| C04 | 3 | `Dismissible` added to 2 of 3 | no swipe-to-queue on home screen |
| C05 | 3 | `folderName` never set by scanner | empty on every scanned track |

None of these produced a crash; three produced a silent behavioural or
performance regression that nobody chose. That is the argument for steps 6–10
taken together, and it is stronger than any of the four cases alone.

---

## Verification

Checked against `8b199b1` on 2026-08-23 — all confirmed present:

| Claim | Location |
|---|---|
| F1 `seedForTest` aliases; `get playlist` unwrapped | `audio_player_service.dart:836`, `:91` |
| F2 divergent guard + regeneration | `:494` vs `_nextPlaylistIndex` |
| F3 `play()` unawaited | `:263` **and** `:428` |
| J1 9 × rethrow, 5 × trailing-slash, 609 lines | `subsonic_api_service.dart` |
| J2 outer catch reaches `_clearStorage()` | `auth_service.dart:100` |
| J3 four steps omitted from recovery | `:255-272` vs `:422-437` |
| T2 delete-then-rename window | `library_cache.dart:96-98` |
| C01 seven `*ForTest` holes | `:817-871` |
| C02 six ritual sites (+2 legit toggles) | six files |
| C04 three tiles, `Dismissible` in two | three screens |
| C05 scanner omits `folderName` | `library_scanner.dart:105` |

Resolved since the source reviews: B1/B2 index states (clean worktree, no tracked
`android/.kotlin`), B3, B4.
Still open from B1/B2: no `android/.kotlin/` in `.gitignore`;
`Output/AnywhereMusicPlayer_Setup.exe` still tracked.

**Not re-run, do not trust without checking:** the 3 failing tests and the 38
analyzer issues.

```bash
flutter analyze && flutter test
```

## Deliberately not proposed

Settled ground per `docs/decisions.md` and `CLAUDE.md`, listed so a future pass
does not re-suggest them: replacing manual sequencing with
`ConcatenatingAudioSource`; keying the Android stream cache on the URL; removing
the ReplayGain `clamp(0,1)`; widening cleartext beyond loopback; auto-resuming
drop recovery while paused; persisting resolved cover-art URLs.
