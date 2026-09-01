import 'dart:io' show Platform, exit;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audio_service/audio_service.dart';
import 'package:window_manager/window_manager.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'services/auth_service.dart';
import 'services/audio_player_service.dart';
import 'services/audio_handler.dart';
import 'services/android_presence.dart';
import 'services/linux_presence.dart';
import 'services/now_playing_presence.dart';
import 'services/playback_reporter.dart';
import 'services/stream_cache.dart';
import 'services/stream_url_resolver.dart';
import 'services/windows_presence.dart';
import 'services/favourites_service.dart';
import 'services/library_scanner.dart';
import 'services/playlists_service.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/tv_home_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/desktop/window_chrome.dart';
import 'utils/platform_detector.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Bound the Flutter image cache. Default is 1000 entries / 100 MB, which a
  // music library with thousands of covers can blow through during long
  // scrolls — leading to OOM kills on lower-RAM Android devices. We render
  // each cover at a server-sized URL (small thumbnails + a larger player
  // cover), so 50 MB / 300 entries comfortably holds the working set.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20; // 50 MB
  PaintingBinding.instance.imageCache.maximumSize = 300;

  // Initialize media_kit backend for just_audio on desktop (replaces
  // just_audio_windows which had WMF threading deadlocks on startup).
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    JustAudioMediaKit.ensureInitialized();
  }

  // Initialize window manager early — must happen right after Flutter binding
  // init, before runApp(), per window_manager docs. Linux is included now
  // that the desktop shell draws its own title bar and needs the same
  // window controls Windows does.
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    // The redesign replaces the OS frame with WindowChrome. Hiding it here —
    // before the first frame — avoids the native bar flashing on launch.
    // WindowsPresence still calls setTitle(): that drives the taskbar entry,
    // which the hidden frame doesn't affect.
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        titleBarStyle: TitleBarStyle.hidden,
        minimumSize: Size(900, 600),
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  await dotenv.load(fileName: '.env');

  // Initialize native platform detection (Android TV detection)
  await PlatformDetector.initialize();

  // Mints stream/cover-art URLs on demand from the *current* authenticated
  // session (see StreamUrlResolver) — a stable reference that outlives any
  // one AuthService instance, so AudioPlayerService and the audio handler
  // (both constructed once, here, before login even happens) keep working
  // across logout/re-login. MyApp wires it to AuthService's changes.
  final resolver = RotatingStreamUrlResolver();

  // Same rotating-reference trick as [resolver], for the same reason: the
  // player is built once, before login, but scrobbles have to reach whatever
  // session is current. See RotatingPlaybackReporter.
  final reporter = RotatingPlaybackReporter();

  // Initialize audio service for Android/iOS background playback and
  // lock screen controls. Skip on Windows — SMTC handles media controls there.
  MusicAudioHandler? audioHandler;
  final bool isDesktop =
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  if (!isDesktop) {
    try {
      audioHandler = await AudioService.init(
        builder: () => MusicAudioHandler(resolver: resolver),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.anywhere_music_player.audio',
          androidNotificationChannelName: 'Music Playback',
          androidNotificationChannelDescription: 'Controls for music playback',
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: true,
          androidNotificationClickStartsActivity: true,
          androidNotificationIcon: 'mipmap/ic_launcher',
          androidShowNotificationBadge: true,
        ),
      );
      debugPrint('Audio service initialized successfully');
    } catch (e, stackTrace) {
      debugPrint('Audio service initialization failed: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  // Which adapter tells the OS what's playing — see NowPlayingPresence.
  // Windows gets SMTC/taskbar/wakelock; mobile gets the audio_service
  // notification (only if it initialized above); Linux gets MPRIS (hardware
  // media keys go through it — see LinuxPresence); nothing else gets one.
  final NowPlayingPresence presence = (!kIsWeb && Platform.isWindows)
      ? WindowsPresence(resolver: resolver)
      : audioHandler != null
      ? AndroidPresence(audioHandler)
      : (!kIsWeb && Platform.isLinux)
      ? LinuxPresence(resolver: resolver)
      : const NoPresence();

  // Android streams through an on-disk cache (seekable local files; ExoPlayer
  // can't seek Navidrome's live HTTP stream) — everything else streams direct.
  // See StreamCache.
  final StreamCache streamCache = (!kIsWeb && Platform.isAndroid)
      ? DiskStreamCache()
      : const DirectStreamCache();

  // Built here rather than inside the provider below so window close can get
  // at it — see [_DesktopCloseGuard]. It already belongs with the other
  // once-per-process services above.
  final playerService = AudioPlayerService(
    presence: presence,
    resolver: resolver,
    reporter: reporter,
    streamCache: streamCache,
  );

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    await _DesktopCloseGuard(playerService).install();
  }

  runApp(
    MyApp(
      presence: presence,
      resolver: resolver,
      reporter: reporter,
      player: playerService,
    ),
  );
}

/// Stops the audio player before the process is allowed to go away.
///
/// Closing a desktop window otherwise tears down the Flutter engine and the
/// Dart isolate immediately, while mpv's event thread is still running and
/// still holding FFI callbacks into Dart — the next event it delivers lands in
/// a dead isolate and the process dumps core. The window is *cosmetically*
/// gone by then, which is why this looks like "it crashes on exit" rather than
/// a visible failure. See the shutdown-crash trap in `docs/operations.md`.
///
/// Nothing else can do this: [AudioPlayerService.dispose] is Provider's, and
/// Provider is never torn down on desktop close — the process just exits under
/// the widget tree.
///
/// The actual exit is a hard [exit], not `windowManager.destroy()`. On Linux
/// `destroy()` re-enters GTK's own `delete-event`/close machinery and lets it
/// tear the window down synchronously from inside that same dispatch — which
/// crashes on its own (a `g_list_remove_link` SEGV deep in
/// `libflutter_linux_gtk`, hit while testing this fix) and is independently
/// documented as flaky on modern Flutter
/// (https://github.com/leanflutter/window_manager/issues/478). Once the player
/// is confirmed stopped there is nothing left worth a clean GTK teardown for —
/// settings and the library cache are written as they change, not at exit — so
/// this skips that path rather than trusting it.
class _DesktopCloseGuard with WindowListener {
  final AudioPlayerService player;

  _DesktopCloseGuard(this.player);

  /// Order matters: the listener has to be registered *before* close is
  /// prevented, or a close landing in between would leave the window with no
  /// way to shut itself.
  Future<void> install() async {
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
  }

  @override
  void onWindowClose() async {
    // Bounded: a player that won't die must not leave the window unclosable.
    // Timing out exits anyway rather than hanging forever.
    await player.shutdown().timeout(
      const Duration(seconds: 2),
      onTimeout: () => debugPrint('Player shutdown timed out; exiting anyway'),
    );
    exit(0);
  }
}

class MyApp extends StatelessWidget {
  final NowPlayingPresence presence;
  final StreamUrlResolver resolver;

  /// Where scrobbles go. Kept pointed at the current session alongside
  /// [resolver] below; null in tests, which don't report anywhere.
  final RotatingPlaybackReporter? reporter;

  /// The player, when the caller owns it — desktop does, so that window close
  /// can shut it down (see [_DesktopCloseGuard]). Null means "make your own",
  /// which is what mobile and the widget tests do.
  final AudioPlayerService? player;

  const MyApp({
    super.key,
    this.presence = const NoPresence(),
    this.resolver = const NoResolver(),
    this.reporter,
    this.player,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Auth Service (owns the SubsonicApiService after login). If
        // [resolver] is the rotating kind (always true in production — see
        // main()), keep it pointed at whatever session is current, so
        // AudioPlayerService and the audio handler — both constructed once,
        // before login — always resolve against the live session.
        ChangeNotifierProvider<AuthService>(
          create: (_) {
            final auth = AuthService();
            final resolver = this.resolver;
            if (resolver is RotatingStreamUrlResolver) {
              resolver.updateFrom(auth.apiService);
              auth.addListener(() => resolver.updateFrom(auth.apiService));
            }
            // SubsonicApiService is both the resolver and the reporter, so
            // the two rotate together off the same session change.
            if (reporter case final reporter?) {
              reporter.updateFrom(auth.apiService);
              auth.addListener(() => reporter.updateFrom(auth.apiService));
            }
            return auth;
          },
        ),

        // Audio Player Service. A caller-supplied player is provided by
        // value: its lifetime is main()'s, not this tree's, so Provider must
        // not dispose it out from under the close guard.
        if (player case final player?)
          ChangeNotifierProvider<AudioPlayerService>.value(value: player)
        else
          ChangeNotifierProvider<AudioPlayerService>(
            create: (_) =>
                AudioPlayerService(presence: presence, resolver: resolver),
          ),

        // Library Scanner - depends on AuthService for the API connection.
        // Provided at the top level so it's accessible to all routes
        // (including Navigator.push routes like FolderDetailScreen).
        ChangeNotifierProxyProvider<AuthService, LibraryScanner>(
          create: (_) => LibraryScanner(null),
          update: (_, auth, previous) {
            // Always reflect the current api reference. After logout the
            // auth service disposes its api client, so we must drop our
            // hold on it; on re-login a brand-new api is created and the
            // scanner must rebind to it (otherwise we'd hit
            // "Client is already closed" on the next request).
            if (previous != null && identical(previous.api, auth.apiService)) {
              return previous;
            }
            return LibraryScanner(auth.apiService);
          },
        ),

        // Server playlists — rebound to the live session for exactly the same
        // reason the scanner above is.
        ChangeNotifierProxyProvider<AuthService, PlaylistsService>(
          create: (_) => PlaylistsService(null),
          update: (_, auth, previous) {
            if (previous != null && identical(previous.api, auth.apiService)) {
              return previous;
            }
            return PlaylistsService(auth.apiService);
          },
        ),

        // Starred songs — rebound to the live session for exactly the same
        // reason the scanner above is.
        ChangeNotifierProxyProvider<AuthService, FavouritesService>(
          create: (_) => FavouritesService(null),
          update: (_, auth, previous) {
            if (previous != null && identical(previous.api, auth.apiService)) {
              return previous;
            }
            return FavouritesService(auth.apiService);
          },
        ),
      ],
      child: MaterialApp(
        title: 'Anywhere Music Player',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        themeMode: ThemeMode.dark,
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _initialized = false;
  bool _screenSizeDetected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Initialize auth state from storage
      if (mounted) {
        await context.read<AuthService>().initialize();
      }
      if (mounted) setState(() => _initialized = true);
      // Request notification permission for lock screen controls (Android 13+)
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        _requestNotificationPermission();
      }
    });
  }

  Future<void> _requestNotificationPermission() async {
    try {
      final status = await Permission.notification.request();
      debugPrint('Notification permission: $status');
    } catch (e) {
      debugPrint('Permission request failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();

    // Initialize platform detection with screen size (fallback heuristic).
    // Only needs to run once — this build method re-runs on every auth
    // state change, and the detection result never changes at runtime.
    if (!_screenSizeDetected) {
      _screenSizeDetected = true;
      final size = MediaQuery.of(context).size;
      PlatformDetector.initializeWithScreenSize(size.width, size.height);
    }

    // Show loading screen only during initial auth check (not during login)
    if (!_initialized) {
      // Wrapped, like the login screen below, because both render before the
      // desktop shell exists and the native window frame is already hidden.
      return const DesktopWindowFrame(
        child: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    // Show appropriate screen based on auth state and platform
    if (!authService.isAuthenticated) {
      return const DesktopWindowFrame(child: LoginScreen());
    }

    return PlatformDetector.isAndroidTV
        ? const TvHomeScreen()
        : const MainScreen();
  }
}
