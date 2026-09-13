# Anywhere Music Player

Flutter client for a self-hosted **Gonic** server, over the **Subsonic API**
(`/rest/*`). Targets Windows and Linux (Arch). See `README.md` for setup,
`docs/overview.md` for how it fits together.

Migrated from Navidrome on 2026-09-08 — see `docs/decisions.md`. Gonic is
folder-native, so the library scan **walks the server's own directory tree**
(`getMusicFolders` → `getIndexes` → `getMusicDirectory`) instead of scraping
filesystem paths out of a non-Subsonic endpoint.

## Load-bearing — do not "simplify" these

Each of these looks like an obvious cleanup and is not. The reasoning is in
[docs/decisions.md](docs/decisions.md); the short version:

1. **Sequencing is manual, in Dart.** One track is loaded at a time; playlist
   order, shuffle, repeat and the queue are hand-rolled. `ConcatenatingAudioSource`
   is buggy under `just_audio_media_kit` on Windows/Linux.
2. **ReplayGain is attenuate-only** (`clamp(0, 1)`). The clamp is what makes
   clipping impossible; the `+6 dB` pre-amp is the tuning knob, not the clamp.
3. **The scan reads each track's path from the song's own `path` field**, and
   only synthesizes one from the directories it walked when the server's is
   absent or absolute. This was the other way round until 2026-09-09: the walk
   is only as folder-shaped as `getIndexes`, and this server answered it with a
   tag-shaped artist index, so the synthesized path buried the real folder tree
   under `Artist/Album`. Don't flip it back without re-reading the entry — both
   directions have a failure mode, and the fallbacks cover the walk's.
4. **The library cache stores `cover_art_id`, never a resolved cover-art URL.**
   A resolved URL carries a live, password-equivalent credential into a plaintext
   file on disk. Schema v3 exists to enforce this. The same salt rotation is why
   nothing anywhere is keyed on a stream or cover URL.
5. **Drop recovery never auto-resumes while paused.** Idle connections drop when
   paused; resuming there starts music the user deliberately stopped.
6. **`just_audio`'s `play()` is never awaited.** Its contract is that it completes
   when playback *stops*, not when it starts. media_kit happens to return at
   once, but a backend that honours the contract holds the reply until the
   track ends — awaiting it then pins `_isLoading` true for the whole song and
   silently kills end-of-track advance. It reads like a missing `await`; it is
   not.
7. **Drop recovery yields one microtask before reloading.** `_handleStreamError`
   runs *inside* just_audio's own error dispatch (its event subject is
   synchronous), and calling `setAudioSource` from in there re-enters a
   controller still firing; the reload fails and the drop is never recovered.
   The `await Future<void>.value()` reads like a pointless `await`; it is not.
   Until 2026-09-13 an incidental `await` in the Android disk cache did this by
   accident — removing the cache removed the yield and took recovery with it.

## Platform reality

Both targets share one audio path — media_kit/MPV, streaming direct from the
server — so a playback change verified on one usually holds on the other. What
**differs** is the presence layer: SMTC + taskbar + wakelock on Windows, a
hand-rolled MPRIS D-Bus server on Linux. Media keys and the OS now-playing
surface need checking on each.

Android (phone and TV) was a target until 2026-09-13 and is not now; the
`android/`, `ios/` and `macos/` trees are gone, not merely unbuilt. There is
**no web target** either.

## docs/ — keep it in sync

`docs/` is the **source of truth** for how this solution works and why it is the
way it is. Prefer reading it over re-deriving from code, and prefer extending it
over letting knowledge live only in a commit message or a chat transcript.

| File | Update cadence |
|---|---|
| `docs/overview.md` | **Live** — keep current |
| `docs/decisions.md` | **Append** a dated entry whenever a reversible choice is made or reversed |
| `docs/operations.md` | Update when the build/run/release flow changes, or a new environment trap is diagnosed |

**Keep `docs/overview.md` current.** Update it whenever something *meaningful*
changes — architecture, stack, platform support, major features, or
implemented/remaining status. Do **not** update for trivial changes (typos,
small refactors, dependency bumps, internal renames).

**Log decisions in `docs/decisions.md`.** Append an entry — *what was decided,
why, and what would reverse it* — whenever a reversible choice is made or an
earlier one is reversed. This is the file that stops a future session
re-litigating settled ground. It is **append-only**: mark a superseded entry,
never rewrite it.

**Write down environment traps in `docs/operations.md`.** If diagnosing something
cost more than a few minutes and would cost that again next time, record the
**symptom** alongside the fix — the symptom is what makes it findable.

**Distinguish repo facts from runtime facts.** A repo fact is verifiable from the
code and true for everyone (versions in `pubspec.yaml`, which platform folders
exist). A runtime fact depends on the device or server (what's installed, what
the server's library contains, whether the CIFS mount is up) and is **not** the
same everywhere. Never state a runtime fact as if it were global — say how to
check it instead.

**Verify before asserting.** Docs reduce re-derivation; they don't replace
checking. Before stating that something exists, works, or is done, confirm it
against the code or a live check.

Do this proactively at the end of any change that meets the bar above — no need
to ask first; make the edit and mention it in your summary.

WikiJS (`projects/anywhere-music-player`) is **no longer** the source of truth —
its content was migrated here on 2026-08-17.
