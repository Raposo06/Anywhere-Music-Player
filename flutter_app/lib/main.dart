import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audio_service/audio_service.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/audio_player_service.dart';
import 'services/audio_handler.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/tv_home_screen.dart';
import 'utils/platform_detector.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: ".env");

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
    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? '';

    if (apiBaseUrl.isEmpty) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error, size: 64, color: Colors.red),
                SizedBox(height: 16),
                Text(
                  'Configuration Error',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'API_BASE_URL not found in .env file.\nPlease create a .env file with your API configuration.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return MultiProvider(
      providers: [
        // API Service
        Provider<ApiService>(
          create: (_) => ApiService(baseUrl: apiBaseUrl),
        ),

        // Auth Service
        ChangeNotifierProvider<AuthService>(
          create: (context) => AuthService(
            context.read<ApiService>(),
          ),
        ),

        // Audio Player Service (depends on ApiService for auth headers)
        ChangeNotifierProxyProvider<ApiService, AudioPlayerService>(
          create: (context) => AudioPlayerService(
            context.read<ApiService>(),
            audioHandler: audioHandler,
          ),
          update: (context, apiService, previous) =>
              previous ?? AudioPlayerService(apiService, audioHandler: audioHandler),
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Initialize auth state from storage
      context.read<AuthService>().initialize();
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

    // Show loading screen while checking auth state
    if (authService.isLoading) {
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

    // Use TV UI for Android TV, regular UI for other platforms
    return PlatformDetector.isAndroidTV
        ? const TvHomeScreen()
        : const MainScreen();
  }
}
