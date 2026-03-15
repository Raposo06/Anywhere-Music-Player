import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audio_service/audio_service.dart';
import 'services/auth_service.dart';
import 'services/audio_player_service.dart';
import 'services/audio_handler.dart';
import 'services/library_scanner.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/tv_home_screen.dart';
import 'utils/platform_detector.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize native platform detection (Android TV detection)
  await PlatformDetector.initialize();

  // Initialize audio service early for reliable background playback.
  // The handler is created now but the AudioPlayer is attached later
  // by AudioPlayerService via attachPlayer().
  MusicAudioHandler? audioHandler;
  try {
    audioHandler = await AudioService.init(
      builder: () => MusicAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.anywhere_music_player.audio',
        androidNotificationChannelName: 'Music Playback',
        androidNotificationChannelDescription: 'Controls for music playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        androidNotificationClickStartsActivity: true,
        androidNotificationIcon: 'drawable/ic_notification',
        androidShowNotificationBadge: true,
      ),
    );
    debugPrint('Audio service initialized successfully');
  } catch (e, stackTrace) {
    debugPrint('Audio service initialization failed: $e');
    debugPrint('Stack trace: $stackTrace');
  }

  runApp(MyApp(audioHandler: audioHandler));
}

class MyApp extends StatelessWidget {
  final MusicAudioHandler? audioHandler;

  const MyApp({super.key, this.audioHandler});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Auth Service (owns the SubsonicApiService after login)
        ChangeNotifierProvider<AuthService>(
          create: (_) => AuthService(),
        ),

        // Audio Player Service
        ChangeNotifierProvider<AudioPlayerService>(
          create: (_) => AudioPlayerService(audioHandler: audioHandler),
        ),

        // Library Scanner - depends on AuthService for the API connection.
        // Provided at the top level so it's accessible to all routes
        // (including Navigator.push routes like FolderDetailScreen).
        ChangeNotifierProxyProvider<AuthService, LibraryScanner>(
          create: (_) => LibraryScanner(null),
          update: (_, auth, previous) {
            if (auth.isAuthenticated && auth.apiService != null) {
              if (previous == null || !previous.hasApi) {
                return LibraryScanner(auth.apiService!);
              }
            }
            return previous ?? LibraryScanner(null);
          },
        ),
      ],
      child: MaterialApp(
        title: 'Anywhere Music Player',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Initialize auth state from storage
      await context.read<AuthService>().initialize();
      if (mounted) setState(() => _initialized = true);
      // Request notification permission for lock screen controls (Android 13+)
      _requestNotificationPermission();
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

    // Initialize platform detection with screen size (fallback heuristic)
    final size = MediaQuery.of(context).size;
    PlatformDetector.initializeWithScreenSize(size.width, size.height);

    // Show loading screen only during initial auth check (not during login)
    if (!_initialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Show appropriate screen based on auth state and platform
    if (!authService.isAuthenticated) {
      return const LoginScreen();
    }

    return PlatformDetector.isAndroidTV
        ? const TvHomeScreen()
        : const MainScreen();
  }
}
