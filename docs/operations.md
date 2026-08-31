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

### Linux/Windows: the app dumps core *after* the window closes

**Symptom:** closing the app looks normal — the window goes away — but the
process exits on a signal instead of cleanly. On Linux `coredumpctl list` shows
a dump for `anywhere_music_player` timestamped at the moment you closed it,
SIGSEGV from a release build or SIGABRT from a debug one. Nothing is logged in
the app itself. Only happens if something was actually played first. This has
had **two distinct causes** so far — check the signature before assuming it's
the one already fixed.

**Signature 1 — an mpv thread, dead isolate.** The crashing thread is one of
libmpv's, never the UI thread:

```
#0  n/a (n/a + 0x0)          <- release: an address that is no longer mapped
#1  libmpv.so + 0xcf9b1      <- (debug: abort() out of libflutter_linux_gtk)
#2  libmpv.so + 0xd7377
#3  libmpv.so + 0xa6db9      <- mpv's own event thread, started via pthread
```

The frame between mpv and the abort sits in anonymous memory with no library
name — a Dart FFI callback trampoline, not native code. **Cause:** closing the
window tore down the Flutter engine and the Dart isolate immediately; libmpv's
event thread was still running and still holding FFI callbacks into Dart. The
next event it delivered called a trampoline whose isolate was gone.
`AudioPlayerService.dispose()` couldn't intervene — it's a Provider dispose,
synchronous, and Provider is never torn down on desktop close anyway, since the
process just exits under the widget tree. **Fixed** by
`AudioPlayerService.shutdown()`: an awaitable teardown that closing now waits on
before doing anything else, so mpv's thread is stopped while the isolate is
still alive to receive its last events.

**Signature 2 — the main thread, inside GTK/GLib itself.** Surfaced by the fix
above: waiting for the player first *and then* calling
`windowManager.destroy()` moved the crash from mpv onto GTK's own teardown:

```
main → g_application_run → g_main_context_iteration → (flutter_linux_gtk) → g_list_remove_link   [SEGV]
```

Dozens of mpv threads are alive and idle in this dump — the mpv race above is
genuinely fixed; this is a separate bug. **Cause:** traced through
`window_manager`'s Linux plugin source — `destroy()` doesn't tear the window
down directly, it re-invokes `gtk_window_close()` with prevent-close cleared,
which re-fires `delete-event` and lets GTK's default destroy path run
synchronously from inside the very platform-channel dispatch that invoked
`destroy()`. `windowManager.destroy()` on Linux is independently documented as
flaky on modern Flutter:
https://github.com/leanflutter/window_manager/issues/478. **Fixed** by not
routing the exit through GTK at all: once the player is confirmed stopped,
`_DesktopCloseGuard.onWindowClose` calls `exit(0)` directly instead of
`windowManager.destroy()`.

**Consequence:** cosmetic in practice — it happens after the last frame, so
there is no user-visible failure and nothing to lose (settings and the library
cache are written as they change, not at exit). It does mean a non-zero exit
code, a core dump per close, and real crashes hiding in the noise.

**The fix as it stands** — `_DesktopCloseGuard` in `lib/main.dart` holds the
window open (`setPreventClose(true)`) until `AudioPlayerService.shutdown()` has
awaited the native player's disposal (bounded by a 2 s timeout — a player that
won't die must not leave the window unclosable), then calls `exit(0)`. The
listener must still be registered *before* `setPreventClose(true)`, or a close
landing in between leaves the window with no way to shut itself.

**Don't reach for `windowManager.destroy()` again** on this codepath without
re-reading signature 2 above — it's the thing that was removed, not an
oversight.

`FlutterEngineRemoveView ... The implicit view cannot be removed` on the way out
(when the old `destroy()` path was still in use) was unrelated embedder noise,
not a failure — worth knowing if it shows up again elsewhere.

**Verification note:** confirmed close-with-no-track-played is crash-free after
this fix (`coredumpctl list` clean, exit code 0). Close-*while-playing* — the
case both crash signatures actually require — has not been re-verified after
the signature-2 fix; there was no way to drive playback through the GUI from
the environment that made this fix (no pointer/click automation available).
Play a track, close the window, and check `coredumpctl list` before considering
this fully closed.

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

### First Android build on a fresh Linux machine: three version floors and a JRE-only JDK

**Symptom.** `flutter build apk` fails, not on missing tools, but on version
floors the installed Flutter (3.47.1) silently enforces against whatever the
Android project last had checked in. Each fix uncovers the next one:

1. `AGP version (8.6.0) is lower than Flutter's minimum supported version of
   8.11.1` — bump `com.android.application` in `android/settings.gradle`'s
   `plugins {}` block **and** `com.android.tools.build:gradle` in
   `android/build.gradle`'s `buildscript.dependencies` — both exist, both must
   move together, or the second one silently wins.
2. Next: `Kotlin version (2.1.0) is lower than Flutter's minimum supported
   version of 2.2.20` — same two-places pattern, `org.jetbrains.kotlin.android`
   in `settings.gradle` and `ext.kotlin_version` in `build.gradle`.
3. Then a real (not version-floor) failure: `Toolchain installation
   '/usr/lib/jvm/java-21-openjdk' does not provide the required capabilities:
   [JAVA_COMPILER]`. The system's "default" JDK was `jre21-openjdk` — a
   runtime with no `javac` — while a full `jdk17-openjdk` sat installed and
   unused. Fixed without touching the system default:
   `flutter config --jdk-dir=/usr/lib/jvm/java-17-openjdk`.

**Stop at AGP/Kotlin 8.11.1 / 2.2.20, don't chase the "will soon be dropped"
warnings to 9.0.1 / 2.3.20+.** Once the build succeeds, Flutter *warns* that
these floors are moving again, but the Flutter Fix box printed alongside it is
explicit: **"Starting AGP 9+, only the new DSL interface will be read. This
results in a build failure when applying the Flutter Gradle plugin"** — this
project's Flutter Gradle plugin does not yet speak the new DSL
(`android.newDsl=false` in `android/gradle.properties` is the existing,
deliberate opt-out). Bumping past the warning breaks the build outright rather
than just aging.

**The Android SDK itself needs setting up on a machine that has never built
Android before** — this one hadn't. `flutter doctor` reporting "Unable to
locate Android SDK" means starting from nothing:
`android-sdk-cmdline-tools-latest` and `android-sdk-platform-tools` from the
AUR, both root-owned by the pacman install. `sdkmanager`/`android sdk install`
then needs to *write into* that same directory (installing platforms,
build-tools, licenses) — `sudo chown -R $USER:$USER /opt/android-sdk` once,
rather than sudo for every component install afterward. Point Flutter at it
with `flutter config --android-sdk /opt/android-sdk`.

**`flutter doctor --android-licenses` can report "unknown" forever on a newer
SDK.** It works by shelling out to `sdkmanager --licenses` and grepping the
output for the literal string `"All SDK package licenses accepted."` — this
SDK's `cmdline-tools` ships a newer "Android CLI" that intercepts `sdkmanager`
calls with `Warning: The --licenses option is no longer needed.` and never
prints that string, so the doctor check stays red even though licenses are
genuinely fine (individual `android sdk install` runs accept them
per-package, visible as `License for package ... accepted.` in the build log).
**Trust the actual build, not this doctor line** — `flutter build apk`
succeeding is stronger evidence than the license check passing.

**First install on a phone that already had the app prompts "install
anyway" / not-verified, even though nothing in the app changed.** Release
builds sign with `signingConfigs.debug` (`android/app/build.gradle`) — the
machine's own debug keystore, auto-created on first use. This SDK generation
puts it at **`~/.config/.android/debug.keystore`**, not the traditional
`~/.android/debug.keystore` — worth knowing before grepping the wrong
directory. A machine that has never built Android before mints a brand-new
certificate, which a phone that already trusts a *different* machine's debug
key (Windows, say) has never seen — Android's installer treats an unrecognized
certificate as more suspicious than a familiar one, regardless of what the
app actually does. Not a bug, nothing to fix; it stops recurring once the
phone has seen this machine's certificate a few times, since every later
build from here reuses the same keystore.

### Navidrome shows an empty library; the app shows 0 folders and 0 tracks

**Symptom.** The library and playlists go empty across every client at once —
app and Navidrome's own web UI. Nothing was deleted; `du -sh` on the music path
reports a few KB instead of tens of GB, and the directory looks like an empty
folder rather than a missing one.

**Cause.** The CIFS mount for the Hetzner Storage Box is not attached, so
`/mnt/storagebox/music` is an empty directory on the VPS's own root disk, and
the container's `/music` bind mount happily follows it. `nofail` in `/etc/fstab`
is what makes this silent: the mount is *designed* to be skipped when it can't
be established at boot, so nothing fails loudly and nothing alerts.

The underlying failure is a missing kernel module. The fstab entry specifies
`iocharset=utf8`, and `nls_utf8` ships in `linux-modules-extra-$(uname -r)`,
which is **not** installed by default on Hetzner's Ubuntu cloud image — the base
kernel carries only `nls_iso8859-1` and `nls_ucs2_utils`. A kernel upgrade
therefore reintroduces this on the next reboot unless the module is pinned.

`mount.cifs` reports this uselessly as:

```
mount error(79): Can not access a needed shared library
```

which points at a linker problem that isn't there — `ldd $(which mount.cifs)`
is clean. The real message is in the kernel log:

```
# dmesg | grep -i cifs
CIFS: VFS: CIFS mount error: iocharset utf8 not found
```

**Diagnose.** `findmnt -T /mnt/storagebox/music` is the fastest tell: if it
reports `/dev/sda1 ext4` instead of `cifs`, the share is detached and you are
looking at the local disk. `findmnt | grep cifs` returning nothing confirms it
system-wide.

**Fix.**

```bash
apt install -y linux-modules-extra-$(uname -r)
modprobe nls_utf8
mount -a
echo nls_utf8 > /etc/modules-load.d/cifs.conf   # survives the next kernel bump
docker restart $(docker ps -qf name=navidrome)  # its index cached the empty dir
```

The last line matters: Navidrome will have indexed the empty directory, so the
library stays empty until it rescans. It does **not** delete files it can't see
— it marks them missing in its own database and waits for a human — so the
music itself is never at risk from this.

**Do not** diagnose this by writing test files to the music path. While
unmounted, those writes land on the root disk and then vanish under the share
when it remounts, which looks alarmingly like data loss and proves nothing.

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

### Buttons show the arrow cursor, not the hand — but rows show the hand

**Symptom.** On desktop, hovering "Play All", "Shuffle", the round play/pause
button, or a window control leaves the pointer as a plain arrow. Hovering a
track row or a sidebar item correctly turns it into a hand. Nothing throws, the
buttons still click, and it looks like a broken hover handler.

**It is not a hover bug, a Wayland bug, or a cursor-theme bug.** Material's
buttons default their cursor to `WidgetStateMouseCursor.adaptiveClickable`,
which is literally:

```dart
return kIsWeb ? SystemMouseCursors.click : SystemMouseCursors.basic;
```

So on every desktop platform Flutter deliberately gives buttons the arrow,
copying the native macOS/Windows convention that a hand means a hyperlink. Rows
work because `HoverRow` sets `SystemMouseCursors.click` itself. Chasing this as
a platform problem is a dead end — `GDK_BACKEND=x11` changes nothing, because
nothing is broken at the platform layer.

**The fix** is an explicit opt-in per button family, in `buildAppTheme`:
`enabledMouseCursor: pointerCursor` on the elevated / outlined / text / filled /
icon button themes. `InkWell` is not a `ButtonStyleButton`, so no button theme
reaches it — `AccentCircleButton` sets `mouseCursor` directly.
`test/widgets/pointer_cursor_test.dart` locks all of this in.

**How to check it without a display.** Cursor resolution is testable headlessly,
which is how this was diagnosed:

```dart
final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
await gesture.addPointer(location: Offset.zero);
await tester.pump();
await gesture.moveTo(tester.getCenter(find.text('Play All')));
await tester.pumpAndSettle();
RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1); // the real answer
```

One gesture per test — a second `addPointer` with the same device id trips an
assertion inside `MouseTracker` that reads like a framework bug and isn't.

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
