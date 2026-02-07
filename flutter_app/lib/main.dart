import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/audio_player_service.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: ".env");

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
          create: (context) => AudioPlayerService(context.read<ApiService>()),
          update: (context, apiService, previous) =>
              previous ?? AudioPlayerService(apiService),
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
    // Initialize auth state from storage
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthService>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();

    // Show loading screen while checking auth state
    if (authService.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Show appropriate screen based on auth state
    return authService.isAuthenticated
        ? const MainScreen()
        : const LoginScreen();
  }
}
