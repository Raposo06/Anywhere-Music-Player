class AppConfig {
  static const String serverUrl = String.fromEnvironment(
    'SERVER_URL',
    defaultValue: '',
  );

  static bool get hasServerUrl => serverUrl.isNotEmpty;
}
