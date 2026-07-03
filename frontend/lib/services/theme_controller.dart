import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../theme/app_theme.dart';

/// Drives light/dark mode. Rather than swapping between two separate
/// ThemeData trees, this mutates AppColors' values in place (see
/// app_theme.dart for why) and notifies listeners so the app rebuilds with
/// the new palette.
class ThemeController with ChangeNotifier {
  final _storage = const FlutterSecureStorage();

  bool get isDark => AppColors.isDark;

  Future<void> load() async {
    final stored = await _storage.read(key: 'theme_mode');
    AppColors.setDark(stored == 'dark');
    notifyListeners();
  }

  Future<void> setDark(bool value) async {
    AppColors.setDark(value);
    notifyListeners(); // update the UI immediately - don't make the toggle wait on disk I/O
    await _storage.write(key: 'theme_mode', value: value ? 'dark' : 'light');
  }
}
