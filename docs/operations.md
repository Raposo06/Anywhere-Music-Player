# Operations

> Building, running and releasing the app — plus the traps that have cost real
> time. Every trap here has been hit in practice.

## Run it

```bash
cp .env.example .env       # then set API_BASE_URL to your Navidrome server
flutter pub get
flutter run
```

`.env` is the entire runtime configuration surface:

| Variable | Purpose |
|---|---|
| `API_BASE_URL` | Navidrome base URL, e.g. `https://navidrome.foxcore.dev` |

Credentials are **not** configured here — you log in through the app, and they're
stored in `SharedPreferences` on the device. Accounts are created in the
Navidrome web UI (the app has no signup — see [decisions.md](decisions.md)).

## Build & release

```bash
flutter build apk            # Android phone + TV
flutter build windows        # Windows
```

Windows distribution is an [Inno Setup](https://jrsoftware.org/isinfo.php)
installer built from `installer.iss` → `AnywhereMusicPlayer_Setup.exe`.

⚠️ **The version lives in two places and they currently disagree:**
`pubspec.yaml` says `1.1.0+2`, `installer.iss` says `1.3`. Whichever is right,
they need bumping together — an installer labelled with a version the app
doesn't report makes bug reports unmatchable to builds.

## Traps

### Windows build fails with a MAX_PATH error

**Symptom:** the build aborts on a path-length error, usually deep inside the
Flutter/plugin tree.

**Cause:** Windows' 260-character path limit. Flutter's build tree plus the
media_kit native libraries exceed it.

**Fix:** enable long-path support, then **restart the terminal** — the setting
isn't picked up by an already-open shell.

### Android: audio never starts, only on Android

**Symptom:** playback works on Windows but silently fails on Android.

**Cause:** just_audio's Android stream cache (`LockCachingAudioSource`) proxies
ExoPlayer through a **local loopback HTTP server on 127.0.0.1** — cleartext,
even when the origin URL is HTTPS. Android blocks cleartext by default, which
kills that loopback specifically.

**Fix:** already in the tree —
`android/app/src/main/res/xml/network_security_config.xml` permits cleartext for
`127.0.0.1`/`localhost` only, wired via `android:networkSecurityConfig` in the
manifest. **Don't "simplify" this to app-wide `usesCleartextTraffic="true"`** —
that would unblock cleartext for every real network destination.

### App won't connect

- Check `.env` exists and `API_BASE_URL` is set and reachable **from the device**
  (a phone on mobile data can't see a LAN-only server).
- Verify the Navidrome user has streaming permission.

### Android TV: app missing from the launcher

- `tv_banner.png` must exist at `android/app/src/main/res/drawable/`
- The manifest needs the `LEANBACK_LAUNCHER` intent filter (it's there — check
  it survived any manifest edit)

## Server dependency

Navidrome runs as a Docker service on the fox-core VPS (Coolify-managed) at
`https://navidrome.foxcore.dev`, with `/mnt/music` — a Hetzner Storage Box
mounted over CIFS — bind-mounted read-only into the container as `/music`.

Consequences worth knowing before debugging the client:

- **The app has no offline mode.** The caches accelerate a working setup; they
  don't substitute for a reachable server.
- **New music appears only after a scan.** Navidrome's scan schedule
  (`ND_SCANSCHEDULE`) governs that, not the app.
- **If the CIFS mount drops**, Navidrome serves an empty or partial library and
  the app faithfully shows nothing wrong — check the server before the client.

## Verification

```bash
flutter analyze
flutter test
```

⚠️ `flutter test` currently runs only the default `test/widget_test.dart`
scaffold — passing it means approximately nothing. Treat manual testing on a real
device as the actual gate, particularly for anything touching playback: the
audio path differs by platform (media_kit on Windows, ExoPlayer + loopback cache
on Android), so a change verified on one says little about the other.

Device logs: `adb logcat` on Android, `flutter logs` elsewhere.
