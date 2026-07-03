/// Where the backend lives, configured at build time rather than hardcoded,
/// so the same source works for local dev (defaults to localhost) and a
/// production build (pass --dart-define=API_HOST=... at build time) without
/// ever needing to edit code to switch between them.
///
/// Local dev (no flags needed):
///   flutter run -d chrome
///
/// Production build, pointed at a real backend:
///   flutter build web --release \
///     --dart-define=API_HOST=your-backend.example.com \
///     --dart-define=USE_HTTPS=true
class AppConfig {
  static const String apiHost =
      String.fromEnvironment('API_HOST', defaultValue: 'localhost:8080');
  static const bool useHttps =
      bool.fromEnvironment('USE_HTTPS', defaultValue: false);

  static String get _httpScheme => useHttps ? 'https' : 'http';
  static String get _wsScheme => useHttps ? 'wss' : 'ws';

  static String get apiBaseUrl => '$_httpScheme://$apiHost/api';

  /// Builds a WebSocket URL for [path] (e.g. '/ws/chat?token=...'),
  /// using wss:// when the API itself is served over https.
  static String wsUrl(String path) => '$_wsScheme://$apiHost$path';
}
