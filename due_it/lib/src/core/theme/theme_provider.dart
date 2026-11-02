import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

const String _themePrefKey = 'selected_app_theme';

class ThemeNotifier extends Notifier<AppThemeKey> {
  @override
  AppThemeKey build() {
    _loadTheme();
    return AppThemeKey.modernLavender;
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString(_themePrefKey);
      if (savedId != null) {
        state = AppThemeKeyExtension.fromId(savedId);
      }
    } catch (_) {
      // Fallback to default
    }
  }

  Future<void> setTheme(AppThemeKey themeKey) async {
    state = themeKey;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themePrefKey, themeKey.id);
    } catch (_) {
      // Ignore preference write failure
    }
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, AppThemeKey>(() {
  return ThemeNotifier();
});
