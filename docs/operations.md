# Operations

> Building, running and releasing the app — plus the traps that have cost real
> time. Every trap here has been hit in practice.

## Run it

```bash
cp .env.example .env       # then set API_BASE_URL to your Gonic server
flutter pub get
flutter run
```

`.env` is the entire runtime configuration surface:

| Variable | Purpose |
|---|---|
| `API_BASE_URL` | Server base URL, e.g. `https://gonic.foxcore.dev` |

Credentials are **not** configured here — you log in through the app, and they're
stored in `flutter_secure_storage` on the device. `SharedPreferences` holds only the
non-sensitive server URL, plus legacy credentials that `AuthService` migrates
out of on first run. Accounts are created in Gonic's own
admin web UI (the app has no signup — see [decisions.md](decisions.md)).

## Build & release

```bash
flutter build windows        # Windows
flutter build linux          # Linux — needs libmpv installed first, see Traps
```

Windows distribution is an [Inno Setup](https://jrsoftware.org/isinfo.php)
installer built from `installer.iss` → `AnywhereMusicPlayer_Setup.exe`.
`installer.iss` needs Inno Setup **6.5.4+** — it uses `WizardStyle=modern dark
polar`, which older compilers reject.

**Neither hardcoded version matters for a tagged release** — the workflow passes
the git tag to both via `--build-name` / `/DMyAppVersion` (see
[decisions.md](decisions.md), 2026-09-01). `pubspec.yaml` (`1.0.0+2`) and
`installer.iss`'s fallback (`1.0.0`) agree as of 2026-09-09; they only apply to
a hand-run `flutter build` / `ISCC` with no override. Keep them roughly in step,
but the tag is what ships — check the files rather than this line, which has
been wrong before.

### Automated releases (GitHub Actions)

`.github/workflows/release.yml` builds the **desktop** platforms and publishes a
GitHub Release on any `v*` tag:

```bash
git tag v1.2.0 && git push origin v1.2.0
```

Assets: `-setup.exe`, `-x86_64.pkg.tar.zst` (Arch package) and `SHA256SUMS`.
Linux ships **only** the Arch package — see [decisions.md](decisions.md),
2026-09-02. The build number is the workflow run number, so it always increases.

**Installing on Arch/Omarchy** — download the `.pkg.tar.zst` from the release
(or the foxcore.dev card) and:

```bash
sudo pacman -U anywhere-music-player-*.pkg.tar.zst
```

That gets the `/usr/bin/anywhere-music-player` symlink, desktop entry and icon,
with `sudo pacman -R anywhere-music-player` to remove — same layout as building
locally with `packaging/arch/PKGBUILD`, but with nothing to compile. `pacman`
pulls `gtk3`, `mpv` and `libsecret` as normal dependencies.

The CI package is built by `packaging/arch/PKGBUILD.bin` inside an
`archlinux:base-devel` container, wrapping the bundle the `linux` job already
compiled on Ubuntu — see that file's header for why there are two PKGBUILDs and
why an Ubuntu-built binary is safe to install on Arch.

A `test` job (`flutter analyze` + `flutter test`) gates all three build jobs, so
a tag whose suite is red fails before anything is published. It is the only
place either command runs in CI.

`workflow_dispatch` (Actions → Release → Run workflow) is a smoke test —
publishes nothing, tags nothing. It runs the same Windows + Linux builds a tag
would, so it is the cheap way to check a build before making it permanent.

**One-time setup — repo variable:**

- Settings → Secrets and variables → Actions → **Variables** → `API_BASE_URL`,
  e.g. `https://gonic.foxcore.dev`. `flutter_dotenv` bakes this into every
  build's asset bundle; the job fails fast if it's unset. It is not a secret
  (it's public DNS), so a variable, not a secret.

Windows and Linux only. Android was dropped from releases on 2026-09-09 and
from the codebase on 2026-09-13; the `ios/` and `macos/` scaffolding went with
it. See [decisions.md](decisions.md).

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

### `flutter build windows` fails with "No CMAKE_CXX_COMPILER could be found"

**Symptom:** a Windows build of a *new* scratch project dies in CMake's compiler
check, while the main project on the same machine builds fine — so the toolchain
is plainly installed.

**Cause:** the project path is too long. This is the MAX_PATH trap below wearing
a different hat: CMake's compiler probe builds a test binary several directories
deeper than the project root, so a path that is merely long becomes over-long
there, and the failure names the compiler rather than the path.

**Fix:** build from a short path (`C:\Users\<you>\proj`), not from a deep temp or
scratch directory.

**And if you copy a Flutter project between directories,** delete `build/`,
`.dart_tool/`, `windows/flutter/ephemeral/` and `.flutter-plugins-dependencies`
first, or the next build dies on `Cannot create link ... errno = 183` — the
copied plugin symlinks still point at the old location.

### Windows build fails with a MAX_PATH error

**Symptom:** the build aborts on a path-length error, usually deep inside the
Flutter/plugin tree.

**Cause:** Windows' 260-character path limit. Flutter's build tree plus the
media_kit native libraries exceed it.

**Fix:** enable long-path support, then **restart the terminal** — the setting
isn't picked up by an already-open shell.

### CI Windows build fails on `smtc_windows` tar extraction or `permission_handler` coroutines

**Symptom:** the release workflow's `windows` job fails (a local `flutter build
windows` on the same commit is fine). One or both of:

```
CMake Error: Problem with archive_write_header(): Cannot extract through symlink
  .../windows/flutter/ephemeral/.plugin_symlinks/smtc_windows/windows/smtc_windows-v0.1.3.tar.gz

error C2338: static assertion failed: 'error STL1011: The /await compiler option,
  <experimental/coroutine> ... are deprecated by Microsoft and will be REMOVED SOON'
  [...permission_handler_windows_plugin.vcxproj]
```

**Cause:** `windows-latest` moved to VS 18 / MSVC 14.51 plus a CMake new enough
that (a) libarchive refuses to extract `smtc_windows`'s bundled prebuilt tarball
because the path runs through Flutter's `.plugin_symlinks` symlink, and (b)
`<experimental/coroutine>`, still `#include`d by the pinned
`permission_handler_windows`, is now a hard `static_assert` instead of a
deprecation warning. Both are runner-toolchain drift, not a code change here.

**Fix:** in `.github/workflows/release.yml` the `windows` job pins
`runs-on: windows-2022` (older CMake + MSVC 17.x) and sets
`env._CL_: /D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` (cl.exe reads
`_CL_` regardless of generator, so it covers the coroutine assert on any MSVC).

**If `windows-2022` is later retired:** pin CMake instead — add
`jwlawson/actions-setup-cmake` with a 3.30.x version before the Flutter step so
it wins on `PATH` — and/or bump `smtc_windows` / `permission_handler` to versions
that dropped the tarball-through-symlink and `<experimental/coroutine>`.

### Windows: SmartScreen blocks the installer, "Editor desconhecido"

**Symptom:** running `AnywhereMusicPlayer-<version>-setup.exe` raises a red
"O Windows protegeu o seu PC" / "Windows protected your PC" dialog naming an
unrecognised publisher.

**This is expected, and it is not a finding about the binary.** Nothing in the
pipeline Authenticode-signs the `.exe`. SmartScreen weighs
two things and we fail both by construction: a known-publisher signature, and
per-file-hash reputation, which a freshly published asset cannot have.

**Fix:** *More info* → *Run anyway* (**Executar mesmo assim**). Correct answer
for a binary built from your own tag by your own workflow.

**Removing it properly** means a code-signing certificate, and since mid-2023 the
private key has to sit on FIPS-140-2 L2 hardware (USB token or cloud HSM), which
is the part that makes it awkward rather than merely paid. An OV certificate
still shows the prompt until each release accrues reputation; only EV grants
immediate trust. Azure Trusted Signing is the cheap path if you can satisfy its
business-identity check. Deliberately not done — see [decisions.md](decisions.md),
2026-09-02 "The Windows installer is not code-signed".

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
- Verify the server user exists and can stream (log in to Gonic's admin UI).

### Changing `API_BASE_URL` doesn't move an installed app to the new server

**Symptom.** `.env` points at the new server, the build picks it up, and the app
still talks to the old one — old library, old ids, old cover art. Nothing errors,
because the old server is still up and still answering.

**Cause.** `API_BASE_URL` only **pre-fills the login screen's server field**
(`login_screen.dart`). The URL actually used is the one stored in
`flutter_secure_storage` under `server_url` at login, and `AuthService.initialize`
reads it on every launch. An install that is already logged in never consults
`.env` again.

**And check `.env` itself first.** It is gitignored, so a server-migration
commit can update `.env.example` but *not* the `.env` on any working machine —
ours still read `navidrome.foxcore.dev` a day after the Gonic migration landed,
which means a *fresh* install pre-fills the old server too. Symptom and fix look
identical from the app; the difference is whether the stale URL is in the
keystore or on disk.

**A stale URL has a third home: the `API_BASE_URL` repo variable.** CI never
sees your local `.env` — it writes its own from that variable, so a *released*
build carries whatever the variable says, however correct every working copy is.
Ours was still `navidrome.foxcore.dev` on 2026-09-09, the day before the first
post-migration release would have shipped with it. A migration is three edits,
not one: `.env.example`, every machine's `.env`, and

```bash
gh variable set API_BASE_URL --body "https://gonic.foxcore.dev"
gh variable list   # verify — this is the one nobody thinks to check
```

**Fix.** Log out and log back in, on every device. Logout clears the stored
credentials *and* the library cache (`LibraryScanner.resetAndClearCache`), which
is what you want here: track ids are server-assigned, so a library cache written
against a different server is only convincing-looking rubbish. Bumping
`LibraryCache._version` covers the same ground for installs that update without
logging out.

### The server shows an empty library; the app shows 0 folders and 0 tracks

**Symptom.** The library and playlists go empty across every client at once —
this app and the server's own web UI. Nothing was deleted; `du -sh` on the music
path reports a few KB instead of tens of GB, and the directory looks like an
empty folder rather than a missing one.

Diagnosed against Navidrome, but nothing about it is Navidrome-specific: any
server indexing that path sees the same empty directory.

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
docker restart $(docker ps -qf name=gonic)  # its index cached the empty dir
```

The last line matters: the server will have indexed the empty directory, so the
library stays empty until it rescans. Navidrome did **not** delete files it
couldn't see — it marked them missing and waited for a human. Confirm the same
of whatever is running now before trusting it; either way the files on the share
are untouched by the client.

**Do not** diagnose this by writing test files to the music path. While
unmounted, those writes land on the root disk and then vanish under the share
when it remounts, which looks alarmingly like data loss and proves nothing.

### `flutter test` hangs forever on a widget that calls `LibraryScanner.scan()`

**Symptom:** a `testWidgets()` test hangs indefinitely (real wall-clock
minutes, not just simulated time) on any path that reaches `scan()` —
directly, or indirectly via `HomeScreen`'s `initState`. `flutter test`'s
per-test timeout (10 min) is what eventually kills it; no exception, no
useful stack trace beyond `dart:isolate _RawReceivePort._handleMessage`.

**Since 2026-09-14 this only bites with the disk cache.** `LibraryScanner`
takes a `LibraryCache`; hand it a `MemoryLibraryCache` (what
`test/support/fake_scanner.dart`'s `scannerWithSongs` does) and there is no
isolate — the scan still needs `runAsync` for the MockClient's futures, but
nothing below hangs. The rest of this entry is the disk-cache story.

**Cause:** `LibraryScanner.scan()` calls `DiskLibraryCache.load`/`save`, which use
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

### The local Flutter SDK is stuck several minor versions behind

**Symptom:** `flutter --version` reports something well below what this doc
says the tree targets (e.g. 3.38.x against a 3.47.x target). `flutter analyze`
shows `undefined_hidden_name` warnings for `RepeatMode` (see next trap);
`flutter test` fails the two `find.widgetWithText(FilledButton, 'Add songs')`
assertions in the playlist screen tests, because on the old SDK
`FilledButton.icon` returns a private `_FilledButtonWithIcon` and `find.byType`
matches exact runtime type. `flutter upgrade` alone doesn't fix it.

**Cause:** the SDK checkout's `stable` branch has diverged — Flutter rewrites
`stable`'s history on each release, so a checkout that missed a few becomes
"diverged, N and M different commits" against `origin/stable` and stops
fast-forwarding. `flutter upgrade` won't force past that.

**Fix:** reset the SDK's `stable` branch straight to the target tag. The
diverged commits are all upstream release commits — nobody develops in the SDK
checkout, so there's nothing local to lose:

```bash
cd /c/flutter   # wherever `where flutter` points
git fetch origin --tags
git checkout stable && git reset --hard 3.47.1
flutter --version   # re-provisions bin/cache for the new version — minutes
```

Then in the project: `flutter pub get && flutter analyze && flutter test`.
Confirmed 2026-09-01: this took the dev SDK from 3.38.9 to 3.47.1, cleared the
`RepeatMode` warnings and the `FilledButton` test failures, and left analyze
clean.

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

The server is **Gonic** at `https://gonic.foxcore.dev` (`type: gonic`,
`serverVersion: 0.22.0`, Subsonic API `1.15.0`). Walked live on 2026-09-08:
1 music folder, 239 directories, 4,384 songs, full scan ~7.5 s. See
[overview.md](overview.md) for the full measurement.

### Gonic: a large playlist lists fine but 502s when opened

**Symptom.** A playlist shows in Playlists with the right track count, but
opening it fails — the app logs `PlaylistsService: loadTracks(...) failed: HTTP
error 502`. (Before 2026-09-13 it spun forever instead; the error is shown now.)

**Cause.** Two things in gonic's source, neither configurable:
`cmd/gonic/gonic.go` builds its `http.Server` with `WriteTimeout: 5 *
time.Second`, and `server/ctrlsubsonic/handlers_playlist.go` resolves
`getPlaylist` one item at a time — a path lookup plus a track load, two SQLite
queries per entry, no batching. A 4,384-entry playlist is ~9,000 queries; the
response is still being built at 5 s, Go closes the socket, Traefik reports
502. The app's own 15 s request timeout never gets a say.

**Where the line is.** Not measured. A few hundred entries is fine in practice;
the whole library is not. If a hand-made playlist starts doing this, split it.

**Do not** try to reproduce "All Tracks" as an m3u. It was tried: gonic reads
`<GONIC_PLAYLISTS_PATH>/<userid>/<name>.m3u` (metadata as `#GONIC-NAME:"…"`
and `#GONIC-IS-PUBLIC:"true"` lines, then one absolute container path per
track), and a `find /music … | sort` into `/playlists/1/all-tracks.m3u` lists
correctly — and then hits exactly this. The Library header's Play All /
Shuffle buttons are the replacement; see [decisions.md](decisions.md).

The hosting details below described the Navidrome instance this replaced — a
Docker service on the fox-core VPS under Coolify, with `/mnt/music` (a Hetzner
Storage Box over CIFS) bind-mounted read-only into the container as `/music`.
**They have not been re-verified for the Gonic deployment**; check before
relying on them.

Consequences worth knowing before debugging the client:

- **The app has no offline mode.** The caches accelerate a working setup; they
  don't substitute for a reachable server.
- **New music appears only after a server-side scan.** Gonic's scan interval
  (`GONIC_SCAN_INTERVAL`, plus `GONIC_SCAN_AT_START`) governs that, not the app
  — the app's own "rescan" only re-walks what the server already indexed.
- **Gonic constrains the folder layout**: all files in a folder must belong to
  one album, and one album must not span folders. A tree that breaks this
  browses oddly, and no client-side change fixes it.
- **If the CIFS mount drops**, the server offers an empty or partial library and
  the app faithfully shows nothing wrong — check the server before the client.

## Verification

```bash
flutter analyze
flutter test
```

See [overview.md](overview.md)'s "Test suite" section for what `flutter test`
actually covers. Treat a manual run as the real gate for anything touching
playback, though: both platforms share media_kit/MPV, but the presence layer
differs (SMTC on Windows, MPRIS on Linux), so media keys and the OS
now-playing surface need checking on each.

Logs: `flutter logs`, or the app's own `debugPrint` output on the console.
