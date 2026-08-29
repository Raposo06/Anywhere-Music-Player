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
flutter build linux          # Linux — needs libmpv installed first, see Traps
```

Windows distribution is an [Inno Setup](https://jrsoftware.org/isinfo.php)
installer built from `installer.iss` → `AnywhereMusicPlayer_Setup.exe`.

⚠️ **The version lives in two places and they currently disagree:**
`pubspec.yaml` says `1.1.0+2`, `installer.iss` says `1.3`. Whichever is right,
they need bumping together — an installer labelled with a version the app
doesn't report makes bug reports unmatchable to builds.

Linux distribution (personal-use install, not published anywhere) is a
[PKGBUILD](https://wiki.archlinux.org/title/PKGBUILD) at
`packaging/arch/PKGBUILD`:

```bash
cd packaging/arch && makepkg -si
```

It builds straight from the repo checkout it lives in (`source=()` is
intentionally empty — see the comment header in the PKGBUILD) and derives
`pkgver` from `pubspec.yaml` at build time via a `pkgver()` function, so it
can't drift out of sync with the app the way `installer.iss`'s hardcoded
version has. It needs `flutter` on `PATH` and a populated `.env` at the repo
root at build time (`flutter_dotenv` bundles `.env` into the Flutter asset
bundle, so whatever `API_BASE_URL` is set when you run `makepkg` is what
ships in that build). Installs to `/usr/lib/anywhere-music-player/` with a
`/usr/bin/anywhere-music-player` symlink and a desktop entry — remove with
`sudo pacman -R anywhere-music-player`.

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

### Linux build/run fails or plays no audio: missing libmpv

**Symptom:** `flutter build linux` fails to link, or the built app runs but
throws on `AudioPlayer` init / plays nothing, with an error mentioning
`mpv`/`libmpv`.

**Cause:** unlike Windows (`media_kit_libs_windows_audio` bundles the DLLs
directly), on Linux `media_kit` links against the **system's** libmpv —
`media_kit_libs_linux` only supplies the CMake glue to find it. Nothing in
the Flutter build tree provides the library itself; it has to already be on
the machine.

**Fix:** install it via the distro's package manager before building —

```bash
sudo pacman -S mpv                 # Arch/Omarchy — one package covers build + runtime
sudo apt install libmpv-dev mpv    # Debian/Ubuntu
```

Also needs the standard Flutter Linux desktop toolchain (`clang`, `cmake`,
`ninja`, `pkgconf`, `gtk3`) and `flutter config --enable-linux-desktop` if
that hasn't been turned on for the SDK yet. The built binary lands at
`build/linux/x64/release/bundle/anywhere_music_player` (`x64/debug/` for a
debug build) — run it from there, or `flutter run -d linux` for a dev loop.

### Linux build fails: `identifier '_json' preceded by whitespace ... deprecated-literal-operator`

**Symptom:** `flutter build linux` fails to compile with errors like
`identifier '_json' preceded by whitespace in a literal operator declaration
is deprecated [-Werror,-Wdeprecated-literal-operator]`, pointing at
`.../flutter_secure_storage_linux/linux/include/json.hpp` (a vendored
nlohmann/json single header, not our code).

**Cause:** that vendored header declares literal operators the old way
(`operator"" _json`, with a space) — valid but deprecated since C++17. A
sufficiently new Clang (this repo has hit it on Clang 22) turns that
deprecation warning into a hard error under `linux/CMakeLists.txt`'s
`-Wall -Werror`, which every plugin target inherits via
`apply_standard_settings`. It's an upstream/toolchain issue, not something a
code change here caused.

**Fix:** already in the tree — `apply_standard_settings` in
`linux/CMakeLists.txt` adds `-Wno-error=deprecated-literal-operator` after
`-Werror`, downgrading just that one diagnostic back to non-fatal everywhere
`apply_standard_settings` is used (runner + all plugins). The warning still
prints; the build no longer aborts on it.

### Red screen: "Tried to use `context.select` outside of the `build` method"

**Symptom:** opening a screen throws
`'package:provider/src/inherited_provider.dart': Failed assertion: line 270 pos 12:
'widget is LayoutBuilder || debugDoingBuild'`.

**Cause:** a `State` method that calls `context.select` (or `context.watch`) is
being called from inside a `Selector`/`Consumer`/`Builder` callback. Those
callbacks run when the *builder widget's* element builds — which is after the
enclosing `State.build()` has already returned. So the `State`'s own `context`
is no longer building, and the assertion fires. The bare identifier `context`
inside such a helper method resolves to `State.context`, not the callback's
shadowed `context` parameter, which is what makes this easy to write by
accident.

**Fix:** take `BuildContext` as a parameter and pass the callback's own
`context` in — see `_watchForErrors` in
`lib/screens/desktop/desktop_player_screen.dart`. `context.read` is unaffected
(it never registers a dependency), which is why the neighbouring calls are fine.

### Red screen: `setState()` or `markNeedsBuild()` called during build, from an animation

**Symptom:** a list containing the playing-track glyph throws during build the
moment playback starts or stops.

**Cause:** calling `AnimationController.repeat()`/`.stop()` inside a `build`
notifies the controller's listeners *synchronously*. On any rebuild after the
first, an `AnimatedBuilder` below is already one of those listeners, so it calls
`markNeedsBuild` while the frame is still building. It survives the first build
only because nothing is listening yet — which is exactly why this reaches
runtime instead of being caught immediately.

**Fix:** drive the controller from a post-frame callback, not from `build` — see
`PlayingBars` in `lib/widgets/desktop/desktop_primitives.dart`.

### Desktop window can't be moved or closed on some screen

**Symptom:** on Windows or Linux a screen appears with no title bar at all —
no drag region, no close button — and the only way out is the taskbar or
killing the process.

**Cause:** `main()` calls `windowManager.setTitleBarStyle(TitleBarStyle.hidden)`
on desktop, so the OS frame is gone app-wide. Anything rendered *outside*
`DesktopShell` therefore has to draw the replacement itself.

**Fix:** wrap the screen in `DesktopWindowFrame`
(`lib/widgets/desktop/window_chrome.dart`), which adds `WindowChrome` on desktop
and is a passthrough elsewhere. The auth-loading state and `LoginScreen` already
use it; `DesktopShell` and `DesktopPlayerScreen` render `WindowChrome`
themselves. Any new top-level route needs one of the two.

### App won't connect

- Check `.env` exists and `API_BASE_URL` is set and reachable **from the device**
  (a phone on mobile data can't see a LAN-only server).
- Verify the Navidrome user has streaming permission.

### Android TV: app missing from the launcher

- `tv_banner.png` must exist at `android/app/src/main/res/drawable/`
- The manifest needs the `LEANBACK_LAUNCHER` intent filter (it's there — check
  it survived any manifest edit)

### Android build: Kotlin daemon crashes on Windows, then the build retries

**Symptom:** `flutter build apk` / `flutter run` on Windows prints a Kotlin
daemon failure mid-build — `Daemon compilation failed: null`, with
`Storage for [...] is already registered` or `Could not close incremental
caches` in the stack trace — and drops a stack-trace file under
`android/.kotlin/errors/`. **The build then succeeds anyway**, which is why it
is easy to ignore: Gradle falls back to in-process compilation and carries on.
The cost is the wasted retry, not a failure.

**Cause:** Gradle's no-isolation Kotlin workers race each other on the
incremental-compile cache files. It reproduces on Windows; it has not been seen
on the Linux/CI path.

**Fix:** already in the tree — `kotlin.incremental=false` in
`android/gradle.properties`. This app's Kotlin surface is one file
(`MainActivity.kt`), so incremental compilation buys nothing and turning it off
removes the race outright.

**Don't commit the evidence.** `android/.kotlin/errors/*.log` are build
artifacts; add `android/.kotlin/` to `.gitignore` rather than checking the
stack traces in.

### `flutter test` hangs forever on a widget that calls `LibraryScanner.scan()`

**Symptom:** a `testWidgets()` test hangs indefinitely (real wall-clock
minutes, not just simulated time) on any path that reaches `scan()` —
directly, or indirectly via `HomeScreen`'s `initState`. `flutter test`'s
per-test timeout (10 min) is what eventually kills it; no exception, no
useful stack trace beyond `dart:isolate _RawReceivePort._handleMessage`.

**Cause:** `LibraryScanner.scan()` calls `LibraryCache.load`/`save`, which use
`compute()` (spawns a real isolate). `testWidgets()` runs the test body in a
fake-async zone so animations/timers are deterministic — but a `Future`'s
continuation stays bound to the zone it was *created* in, and a real
isolate's response message never gets delivered inside that fake zone. Plain
`test()` (no `testWidgets`) isn't affected — no fake-async zone involved.
`pump()`/`pumpAndSettle()` can't fix it either: they only pump Flutter frames,
not the isolate message queue.

**Fix:** the call that *starts* the scan has to happen inside
`tester.runAsync(...)` — Flutter's documented escape hatch back to the real
zone. For a scan called directly in the test, wrap it:
`await tester.runAsync(() => scanner.scan());`. For `HomeScreen`, where
`initState`'s `WidgetsBinding.instance.addPostFrameCallback` fires the scan
as a side effect of `pumpWidget()` itself, `pumpWidget()` has to be the thing
running inside `runAsync` — a `pump()` called after `pumpWidget()` runs on
the outside is too late, the callback (and its zone-bound `scan()`) has
already fired. See `test/support/pump_helpers.dart`'s `waitForAsyncWork` /
`pumpAndWaitForAsyncWork` and their usage in `test/screens/`.

### `flutter test` / build fails: `RepeatMode` is imported from both ... and `repeating_animation_builder.dart`

**Symptom:** compilation fails (build or `flutter test`) with `'RepeatMode' is
imported from both 'package:anywhere_music_player/services/playback_cursor.dart'
and 'package:flutter/src/widgets/repeating_animation_builder.dart'`, pointing at
`lib/screens/player_screen.dart` / `lib/screens/tv_player_screen.dart`.

**Cause:** Flutter 3.47 added its own `RepeatMode` class (for animation
repeating), exported transitively through `material.dart`. It collides with
this app's own `RepeatMode` enum (`lib/services/playback_cursor.dart`,
re-exported by `audio_player_service.dart`) in any file that imports both —
an SDK-bump trap, not something a code change introduced.

**Fix:** already in the tree — the two colliding files hide Flutter's symbol
at the import site: `import 'package:flutter/material.dart' hide RepeatMode;`.
If a new screen starts importing both `material.dart` and something exposing
this app's `RepeatMode`, it needs the same `hide`.

**The inverse symptom, on an older SDK:** `warning - The library
'package:flutter/material.dart' doesn't export a member with the hidden name
'RepeatMode' - undefined_hidden_name`. That is the *same* trap seen from the
other side: the toolchain predates Flutter's `RepeatMode`, so there is nothing
to hide. It is a warning, not an error, and the `hide` must stay — removing it
to silence the warning re-breaks the build on a newer SDK. **New files should not
add a `hide` they don't need** — add it only when the analyzer actually reports
the ambiguity.

As of 2026-08-28 this tree builds on Flutter 3.47.1, which is new enough that the
`hide` is *required* (a hard error otherwise, per the symptom above), not merely
tolerated. The desktop redesign's `desktop_player_screen.dart` and
`desktop_mini_player.dart` were added without it and broke `flutter build linux`;
both now carry the `hide`. On an older SDK (≤ 3.38.x) the same files instead emit
the harmless `undefined_hidden_name` warning.

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

See [overview.md](overview.md)'s "Test suite" section for what `flutter test`
actually covers. Treat manual testing on a real device as the real gate for
anything touching playback, though: the audio path differs by platform
(media_kit/MPV on Windows and Linux, ExoPlayer + loopback cache on Android),
so a change verified on one says little about the others.

Device logs: `adb logcat` on Android, `flutter logs` elsewhere.
