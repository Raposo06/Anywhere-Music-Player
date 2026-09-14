import 'dart:io' show Platform, exit;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'services/auth_service.dart';
import 'services/audio_player_service.dart';
import 'services/linux_presence.dart';
import 'services/notices.dart';
import 'services/now_playing_presence.dart';
import 'services/windows_presence.dart';
import 'services/favourites_service.dart';
import 'services/library_scanner.dart';
import 'services/playlists_service.dart';
import 'services/session_scoped.dart';
import 'services/subsonic_api_service.dart';
import 'screens/login_screen.dart';
import 'screens/desktop/desktop_shell.dart';
import 'theme/app_theme.dart';
import 'widgets/desktop/window_chrome.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Bound the Flutter image cache. Default is 1000 entries / 100 MB, which a
  // music library with thousands of covers can blow through during long
  // scrolls. We render each cover at a server-sized URL (small thumbnails +
  // a larger player cover), so 50 MB / 300 entries comfortably holds the
  // working set.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20; // 50 MB
  PaintingBinding.instance.imageCache.maximumSize = 300;

  // Initialize media_kit backend for just_audio on desktop (replaces
  // just_audio_windows which had WMF threading deadlocks on startup).
  if (Platform.isWindows || Platform.isLinux) {
    // libmpv's demuxer cache, which just_audio_media_kit defaults to 32 MB —
    // a size meant for video. This app streams audio, and the default was
    // measurably the largest single piece of memory this app added over a
    // bare Flutter process.
    //
    // 8 MB was the first try and made tracks visibly slower to start over the
    // tunnelled link to the server; 16 MB is the documented middle step. Going
    // lower trades start latency for ~8 MB of resident memory — measure before
    // moving it in either direction.
    // Must be set before ensureInitialized(); it is read at player creation.
    JustAudioMediaKit.bufferSize = 16 << 20; // 16 MB
    JustAudioMediaKit.ensureInitialized();
  }

  // Initialize window manager early — must happen right after Flutter binding
  // init, before runApp(), per window_manager docs. Linux is included now
  // that the desktop shell draws its own title bar and needs the same
  // window controls Windows does.
  if (Platform.isWindows || Platform.isLinux) {
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

  // The session. Built once, here, because the player and the presence
  // adapter are built once, before login, and must mint URLs and report
  // plays against whatever session is current across logout/re-login —
  // AuthService is the resolver and reporter that follows it.
  final auth = AuthService();

  // Which adapter tells the OS what's playing — see NowPlayingPresence.
  // Windows gets SMTC/taskbar/wakelock; Linux gets MPRIS (hardware media keys
  // go through it — see LinuxPresence).
  final NowPlayingPresence presence = Platform.isWindows
      ? WindowsPresence(resolver: auth)
      : Platform.isLinux
      ? LinuxPresence(resolver: auth)
      : const NoPresence();

  // Where every module's one-shot failures go, drained by the shell's
  // NoticesListener — see Notices. Once per process, like the player.
  final notices = Notices();

  // Built here rather than inside the provider below so window close can get
  // at it — see [_DesktopCloseGuard]. It already belongs with the other
  // once-per-process services above.
  final playerService = AudioPlayerService(
    presence: presence,
    resolver: auth,
    reporter: auth,
    notices: notices,
  );

  if (Platform.isWindows || Platform.isLinux) {
    await _DesktopCloseGuard(playerService).install();
  }

  runApp(MyApp(auth: auth, player: playerService, notices: notices));
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
  /// The session, when the caller owns it — `main()` does, because the
  /// player it also owns resolves through it. Null means "make your own",
  /// which is what the widget tests do.
  final AuthService? auth;

  /// The player, when the caller owns it — desktop does, so that window close
  /// can shut it down (see [_DesktopCloseGuard]). Null means "make your own",
  /// which is what the widget tests do.
  final AudioPlayerService? player;

  /// The sink the caller's [player] already pushes to, so the tree shares
  /// it. Null means "make your own", alongside the player.
  final Notices? notices;

  const MyApp({super.key, this.auth, this.player, this.notices});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // One-shot failures from every module below, shown by the shell.
        // First, so the session-scoped modules can be handed it.
        if (notices case final notices?)
          ChangeNotifierProvider<Notices>.value(value: notices)
        else
          ChangeNotifierProvider<Notices>(create: (_) => Notices()),

        // The session (owns the SubsonicApiService after login). A
        // caller-supplied one is provided by value — the player already
        // holds it as its resolver and reporter.
        if (auth case final auth?)
          ChangeNotifierProvider<AuthService>.value(value: auth)
        else
          ChangeNotifierProvider<AuthService>(create: (_) => AuthService()),

        // Audio Player Service. A caller-supplied player is provided by
        // value: its lifetime is main()'s, not this tree's, so Provider must
        // not dispose it out from under the close guard. The made-here one
        // (widget tests) has no presence and no resolver.
        if (player case final player?)
          ChangeNotifierProvider<AudioPlayerService>.value(value: player)
        else
          ChangeNotifierProvider<AudioPlayerService>(
            create: (context) =>
                AudioPlayerService(notices: context.read<Notices>()),
          ),

        // The library, the user's playlists and their starred songs. All
        // three are scoped to the logged-in session — see [sessionScoped] —
        // and all three are provided at the top level so they reach
        // Navigator.push routes like FolderDetailScreen too.
        sessionScoped<LibraryScanner>(
          (api, notices) => LibraryScanner(api, notices: notices),
        ),
        sessionScoped<PlaylistsService>(
          (api, notices) => PlaylistsService(api, notices: notices),
        ),
        sessionScoped<FavouritesService>(
          (api, notices) => FavouritesService(api, notices: notices),
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

/// Provides a [SessionScoped] module, rebuilt whenever the session changes.
///
/// [build] is called with the live [SubsonicApiService] — null while logged
/// out — and again with the new one on every session change, plus the tree's
/// [Notices] for the module to report into. An existing instance survives
/// only while it is still bound to the same client by identity: after logout
/// `AuthService` disposes its client, so an instance that kept hold of it
/// would answer the next request with "Client is already closed", and on
/// re-login there is a brand-new client to bind to.
ChangeNotifierProxyProvider<AuthService, T> sessionScoped<
  T extends SessionScoped
>(T Function(SubsonicApiService? api, Notices notices) build) {
  return ChangeNotifierProxyProvider<AuthService, T>(
    create: (context) => build(null, context.read<Notices>()),
    update: (context, auth, previous) =>
        previous != null && identical(previous.api, auth.apiService)
        ? previous
        : build(auth.apiService, context.read<Notices>()),
  );
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Initialize auth state from storage
      if (mounted) {
        await context.read<AuthService>().initialize();
      }
      if (mounted) setState(() => _initialized = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();

    // Show loading screen only during initial auth check (not during login)
    if (!_initialized) {
      // Wrapped, like the login screen below, because both render before the
      // desktop shell exists and the native window frame is already hidden.
      return const DesktopWindowFrame(
        child: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    if (!authService.isAuthenticated) {
      return const DesktopWindowFrame(child: LoginScreen());
    }
    return const DesktopShell();
  }
}
