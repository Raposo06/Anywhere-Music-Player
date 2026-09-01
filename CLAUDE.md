# Anywhere Music Player

Flutter client for a self-hosted **Navidrome** server, over the **Subsonic API**
(`/rest/*`). Targets Android phone, Android TV and Windows. See `README.md` for
setup, `docs/overview.md` for how it fits together.

## Load-bearing — do not "simplify" these

Each of these looks like an obvious cleanup and is not. The reasoning is in
[docs/decisions.md](docs/decisions.md); the short version:

1. **Sequencing is manual, in Dart.** One track is loaded at a time; playlist
   order, shuffle, repeat and the queue are hand-rolled. `ConcatenatingAudioSource`
   is buggy under `just_audio_media_kit` on Windows/Linux.
2. **The Android stream cache is keyed by track id, never the URL.** Stream URLs
   embed an auth token + salt that rotate on every request build — keying on the
   URL silently produces a 100% miss rate.
3. **ReplayGain is attenuate-only** (`clamp(0, 1)`). The clamp is what makes
   clipping impossible; the `+6 dB` pre-amp is the tuning knob, not the clamp.
4. **The library cache stores `cover_art_id`, never a resolved cover-art URL.**
   A resolved URL carries a live, password-equivalent credential into a plaintext
   file on disk. Schema v3 exists to enforce this.
5. **Cleartext is permitted for loopback only.** Never widen it to
   `usesCleartextTraffic="true"` — that unblocks cleartext for the real server too.
6. **Drop recovery never auto-resumes while paused.** Idle connections drop when
   paused; resuming there starts music the user deliberately stopped.
7. **`just_audio`'s `play()` is never awaited.** It completes when playback
   *stops*, not when it starts — on Android the platform holds that future until
   the track ends, so awaiting it pins `_isLoading` true for the whole song and
   silently kills end-of-track advance. media_kit returns immediately, so the
   bug is invisible on desktop. It reads like a missing `await`; it is not.

## Platform reality

The audio path **differs by platform**: media_kit/MPV on Windows/Linux,
ExoPlayer + loopback stream cache on Android. A playback change verified on one
platform says little about the other — test both.

There is **no web target** (no `web/` directory), despite older docs claiming one.

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
the Navidrome library contains, whether the CIFS mount is up) and is **not** the
same everywhere. Never state a runtime fact as if it were global — say how to
check it instead.

**Verify before asserting.** Docs reduce re-derivation; they don't replace
checking. Before stating that something exists, works, or is done, confirm it
against the code or a live check.

Do this proactively at the end of any change that meets the bar above — no need
to ask first; make the edit and mention it in your summary.

WikiJS (`projects/anywhere-music-player`) is **no longer** the source of truth —
its content was migrated here on 2026-08-17.
