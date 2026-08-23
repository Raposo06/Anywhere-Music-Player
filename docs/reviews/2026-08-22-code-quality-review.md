# Thermo-Nuclear Code Quality Review — Anywhere Music Player

**Branch:** `main` @ `5634a08` (in sync with `origin/main`) · **Date:** 2026-08-22
**Reviewed:** the pending index/worktree changes, plus the code landed in
`677212a` / `5634a08` / `af44308`.

**Verdict: NOT APPROVED.** Three blockers in the pending change, one live
credential-loss bug, and **three failing tests on `main`** whose root causes are
structural, not flaky.

Verified: `flutter analyze` → 38 issues (6 warnings, 32 info, 0 errors).
`flutter test` → **150 passed, 3 failed**.

> **Resuming in a later session:** re-check `git status` and `flutter test` before
> trusting anything in Section 0 and 1 below — B1–B3 describe the index state as
> it stood on 2026-08-22 and may already be resolved. F1–F3 (the three test
> failures) and J1–J4 (the code-judo opportunities) are about code on `main` and
> stay valid until someone changes that code. Companion document:
> `docs/reviews/2026-08-22-architecture-review.html` — its Candidate 01
> (`PlaybackCursor`) touches the same file as F1–F3/J3 here, so landing those
> fixes first means less rework when 01 lands.

---

## 0. Failing tests — root causes (all structural)

### F1 · `seedForTest` aliases the caller's list, and `playlist` is unwrapped
`audio_player_service_sequencing_test.dart:391` — *reorderUpcoming sequential*

```
Expected: ['0', '2', '3', '1']
  Actual: ['0', '3', '1', '2']
```

The assertion compares the mutated list against itself. `seedForTest` stores the
list **by reference**:

```dart
if (playlist != null) _playlist = playlist;      // aliases the caller's list
```

while production does `_playlist = List.from(tracks)`. `reorderUpcoming` then
mutates `_playlist` in place — which is the test's own `tracks` fixture — so by
the time the expectation is built, `tracks[3]` is no longer track 3.

Two defects behind one failure:

1. **The test seam does not behave like the production path.** A seam whose
   copy semantics differ from the code it stands in for is worse than no seam:
   it makes tests pass or fail for reasons the product never exhibits.
2. **`get playlist => _playlist` hands out the mutable internal list.**
   `get queue` returns `List.unmodifiable(_queue)`; `playlist` does not. Any
   screen holding a reference can reorder the player's playlist behind its back.

**Fix:** copy in `seedForTest` (`_playlist = List.of(playlist)`), and return
`List.unmodifiable(_playlist)` from the getter. Both are one-liners; the second
is the one that matters in production.

### F2 · `peekNextTrack` and `_nextPlaylistIndex` answer the same question differently
`audio_player_service_sequencing_test.dart:264` — *peekNextTrack shuffle-aware*

```
Expected: '0'
  Actual: <null>
```

`peekNextTrack` bails on `_currentIndex < 0`. In shuffle mode `_currentIndex` is
not the cursor — `_shufflePos` is — so that guard is a sequential-mode
precondition applied to the shared path. `_nextPlaylistIndex()` has no such
guard and returns `_shuffleOrder[1]` happily from the same state.

The two methods are a **copy of the same wraparound algorithm**, one mutating
and one not, and they have already drifted in two places:

| state | `_nextPlaylistIndex()` | `peekNextTrack()` |
|---|---|---|
| shuffle on, `_currentIndex == -1` | returns `_shuffleOrder[1]` | **returns null** |
| shuffle on, end of order, repeat-all | **regenerates** the order anchored at current, returns new `[0]` | returns **old** order's `[0]` |

The second row is a live (if harmless) product bug: `peekNextTrack` drives
cover-art prefetch in `player_screen.dart`, so the last track of every shuffled
pass prefetches the wrong cover.

**Fix — code judo:** stop having two algorithms. Make the mutating path *use*
the pure one:

```dart
({int index, bool regenerated})? _peekNext();     // pure, no mutation
int? _nextPlaylistIndex() { /* _peekNext() + commit shufflePos/order */ }
Track? peekNextTrack() => _queue.firstOrNull ?? _playlist[_peekNext()?.index];
```

### F3 · Drop recovery reports "not playing" before playback has resumed
`audio_player_service_playback_test.dart:251` — *gives up after 3 rapid attempts*

```
Expected: null
  Actual: 'Playback error: drop 1'
```

The **second** injected drop surfaces an error even though it is well inside the
3-attempt bound. `_handleStreamError` gates on
`!(_player?.playing ?? false)` → `_handlePlaybackError(error)`. But the recovery
path clears `_isLoading` in its `finally` while `_player!.play()` is left
unawaited — so there is a window where the service reports "not loading, not
playing", and a drop arriving in that window is misclassified as unrecoverable.

The test waits on `!service.isLoading`, which is the service's own readiness
signal — so this is not the test being impatient; the signal is wrong.

**Fix:** await `play()` (or key the guard on "intended to be playing" rather
than the backend's instantaneous `playing` flag) — and see J3 below, which
removes the duplicated recovery path this lives in.

---

## 1. Blockers in the pending change

### B1 · Kotlin crash logs staged for commit
```
A  android/.kotlin/errors/errors-1783293056698.log   (198 lines)
A  android/.kotlin/errors/errors-1783294280999.log   (232 lines)
```
430 lines of Kotlin daemon stack traces staged as source. These are the
*evidence* for the `kotlin.incremental=false` fix, not the fix. `.gitignore` has
no `android/.kotlin/` entry, so they will keep reappearing.

```bash
git restore --staged android/.kotlin && printf 'android/.kotlin/\n' >> .gitignore
```

### B2 · A tracked installer binary left in an unmerged index state
```
UU Output/AnywhereMusicPlayer_Setup.exe
```
There is no `MERGE_HEAD`, `CHERRY_PICK_HEAD` or `REBASE_HEAD` — a merge was
abandoned and this conflict was never resolved. The index is in a state that
will block or corrupt the next commit.

Separately: `Output/AnywhereMusicPlayer_Setup.exe` is a **built installer
tracked in git**, already rewritten across 7 commits. Every release
permanently adds a copy to the clone. Untrack it and attach installers to
GitHub releases instead.

### B3 · 168 lines of `pubspec.lock` churn with no `pubspec.yaml` change
A full dependency re-resolution staged alongside a Kotlin build fix, and the
file is `MM` (staged, then modified again). Either commit the lock change on
its own with a reason, or drop it.

### B4 · The Kotlin trap was fixed but not documented — **fixed in this session**
`CLAUDE.md` requires environment traps go in `docs/operations.md` *with the
symptom*. The `gradle.properties` comment is good but invisible to someone
hitting the crash. Added: **"Android build: Kotlin daemon crashes on Windows,
then the build retries."**

---

## 2. Missed code-judo — the big wins

### J1 · `SubsonicApiService`: nine copies of one request envelope
609 lines, of which roughly 90 are the same four-line shape repeated:

```dart
try {
  final uri = _buildUri(endpoint, params);
  final response = await _get(uri);
  final data = _parseResponse(response);
  ...extract...
} catch (e) {
  if (e is SubsonicApiException) rethrow;             // ×9
  throw SubsonicApiException('Failed to X: $e');
}
```

Plus **5 copies** of the trailing-slash normalization
(`serverUrl.endsWith('/') ? serverUrl.substring(...) : serverUrl` at lines 97,
115, 123, 515, 552) — a value that cannot change after construction.

Plus `getFolders` and `getRootTracks`, which are the *same method* differing
only in whether they accumulate `.folders` or `.tracks`.

**Judo:**
- `late final String _baseUrl` computed once in the constructor. Deletes 5 copies.
- One private `_request(endpoint, {params, cacheKey, failureContext})` doing
  uri → get → parse → cache → wrap. Every public method drops to its extraction
  logic. Deletes ~90 lines and removes the hazard that one of the nine forgets
  the `rethrow` guard and double-wraps the error.
- `_rootContents()` returning the record; `getFolders`/`getRootTracks` project
  from it.

Nine hand-written copies of an error-wrapping idiom is not style — it is nine
chances to get the error contract subtly wrong.

### J2 · `AuthService.initialize()` — the outer `catch` contradicts the inner design, and it can wipe credentials

The inner logic is deliberate and well-commented: only a Subsonic code-40
rejection should clear stored credentials; every other failure (offline,
timeout, server down) must keep the session so the library cache stays usable.

But the whole body is wrapped in:

```dart
} catch (e) {
  debugPrint('Error initializing auth: $e');
  await _clearStorage();          // ← logs the user out
}
```

That catch also covers `_secureStorage.read()` and
`_migrateFromSharedPreferences()`. **A `flutter_secure_storage` plugin failure
on startup silently deletes the user's saved credentials** — the exact outcome
the inner branches were written to prevent. This is a bug the structure
produced: the nesting is what hides the contradiction.

The same three lines appear **three times** in the method:

```dart
_apiService = api;
_currentUser = User(username: username);
```

**Judo — reframe so the branches disappear:**

```dart
final creds = await _readCredentials();          // returns null if incomplete
if (creds == null) return;
final api = _apiFactory(...);
if (await _serverRejectedCredentials(api)) {     // true only for code 40
  await _clearStorage();
  return;
}
_session = Session(api, User(username: creds.username));
```

Two supporting simplifications:
- **`_apiService` + `_currentUser` are always set and cleared together.** Two
  nullable fields encoding one state, with `isAuthenticated` re-deriving the
  invariant by checking both. Make it one nullable `Session`.
- **The three-key credential triple is written out 5 times** (read, migrate
  read, migrate write, migrate remove, clear ×2). A `_Credentials` record with
  `_read`/`_write`/`_delete` collapses ~40 lines.

### J3 · `_handleStreamError` re-implements `_loadAndPlay`, and drops four steps

The recovery path duplicates the entire load sequence — `++_loadToken`,
`_isLoading` bookkeeping, `_setSourceWithRetry`, the token re-check,
`setVolume(_volume * _replayGainFactor(track))`, `play()`, the
`finally` — and in copying it, silently omits:

- `_logStreamParams(track)`
- `_audioHandler.updateTrackInfo(track)`
- `_updateWindowsMetadata(track)`
- `_evictAudioCacheIfNeeded()`

So a track that recovers from a drop never contributes to Android cache
eviction. Nobody decided that.

**Judo:** one method.
```dart
Future<void> _loadAndPlay(Track track, int token, {Duration? resumeFrom});
```
`_handleStreamError` becomes: bounds check → capture position → call it.
Deletes ~25 lines and the divergence — and is where F3's `await play()` fix
belongs.

### J4 · `pump_helpers.dart` — two functions differing by one line

`waitForAsyncWork` and `pumpAndWaitForAsyncWork` are identical except that the
first action is `tester.pump()` vs `tester.pumpWidget(widget)`. The 12-line
rationale comment explaining the zone-binding subtlety is duplicated too — so
the *hardest* thing in the file to keep correct exists in two places.

```dart
Future<void> runUntilIdle(
  WidgetTester tester,
  Future<void> Function() start,
  bool Function() isBusy,
) => tester.runAsync(() async {
      await start();
      while (isBusy()) await Future<void>.delayed(const Duration(milliseconds: 10));
    });
```

Callers pass `() => tester.pump()` or `() => tester.pumpWidget(w)`.

Similarly, `fake_auth.dart` and `fake_scanner.dart` each hand-build a
`SubsonicApiService` + `MockClient`; one `fakeApi({handler})` helper serves both.

---

## 3. Boundary / type-contract problems

### T1 · `Track.filename` means two different things
`fromSubsonic` sets it to `json['path']` — a full library-relative path — but
falls back to a bare `'$title.$suffix'` when the server sends no path. The
scanner always sets a full path. Then `LibraryScanner._buildFolderTree` splits
it on `/` and treats it as a path, so a track without a server path silently
lands at the tree root.

One field, two shapes, a name that describes the less common one. Rename to
`path` and make the no-path case explicit rather than degrading into a
filename that happens to parse.

### T2 · `LibraryCache`'s "atomic write" is not atomic on Windows
The doc comment promises: *"If the app dies between these calls, the existing
(stale-but-valid) cache remains."* The implementation is:

```dart
await tmp.writeAsString(json, flush: true);
if (await target.exists()) await target.delete();   // ← window with no cache
await tmp.rename(target.path);
```

`File.rename` cannot replace an existing file on Windows, hence the delete — but
that opens a window where neither file exists, which is exactly the failure the
comment says cannot happen. The test run surfaced the related symptom twice:

```
LibraryCache: failed to save: PathAccessException: Cannot rename file to
'...library_cache.json' (OS Error: Acesso negado, errno = 5)
```

Use a replace-style API (or write → rename-old-aside → rename-new → delete-old),
and correct the comment to match whichever guarantee actually holds.

### T3 · `LibraryCache` is an all-static class that takes an api client
Static methods taking `SubsonicApiService` purely to re-mint URLs. There is no
seam: tests can only reach it by globally faking `path_provider`
(`FakePathProviderPlatform`), which is why the two Windows rename failures above
leak into unrelated screen tests. Make it an instance with an injected
directory.

### T4 · `_getFromCache<T>` casts `dynamic` to `T?` unchecked
An unchecked cast keyed by a stringly-typed cache key. Two public methods
(`getIndexes`, `getMusicDirectory`) also return raw `Map<String, dynamic>` while
every other method returns models — the raw-map boundary leaks Subsonic's JSON
shape into callers.

---

## 4. Analyzer findings worth acting on

`flutter analyze` — 38 issues, **0 errors**:

- **6 × `unnecessary_non_null_assertion`** (warnings) —
  `library_scanner.dart:75,93,106,107` and `audio_player_service.dart:164,429`.
  `!` applied to values the analyzer proves non-nullable. Not cosmetic: these
  are the residue of a null-check that moved, and they obscure where the real
  nullability lives.
- **2 × `use_build_context_synchronously`** — `home_screen.dart:146–147`.
  `_handleLogout` uses `context` after three `await`s. On a slow logout the
  widget can be gone.
- 30 info-level nits (`unnecessary_underscores` ×24, one deprecated
  `withOpacity`, three `prefer_const_constructors`). Batchable in one pass.

---

## 5. What is already good

Worth saying, because these are the patterns the rest of the code should copy:

- **`queue_sheet.dart`** is the counter-example to the screens: one shared
  `_TrackRow` taking `reorderIndex` / `onTap` / `onDismissed` instead of three
  copy-pasted tiles. This is exactly the shape the screen tiles should take.
- **The comments carry real reasoning**, not restatement — the
  `_replayGainPreAmpDb` reference table, the loopback-cleartext note, the
  `_skipDebounce` asymmetry, the `pump_helpers` zone-binding explanation. Rare,
  and worth protecting through any refactor.
- **`docs/operations.md`'s fake-async trap entry** is exemplary: symptom first,
  cause, then fix.
- Injecting `http.Client` and `apiFactory` rather than reaching for a mocking
  framework keeps the seams honest and the tests fast.

---

## Approval bar

| Criterion | |
|---|---|
| No structural regression | ❌ B1–B3 |
| No missed dramatic simplification | ❌ J1–J4 |
| No spaghetti growth from special-case branching | ❌ F2 (mode-specific guard on a shared path) |
| No hacky abstraction obscuring the design | ❌ J2 (nested catch hides a credential-wiping path) |
| Tests green | ❌ 3 failing |

**Suggested order:** B1–B3 (unblock committing) → F1 + F3 + J3 (green suite) →
J2 (the credential bug) → J1 → F2/J4 → analyzer sweep.
