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

**Decided.** The library cache (`library_cache.dart`, schema **v3**) stores
`cover_art_id`. Schema v2 → v3 exists specifically to drop `cover_art_url`.

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
