import 'package:flutter/material.dart';

import '../../data/settings_repository.dart';
import '../../theme/app_theme.dart';

/// Возможные режимы темы интерфейса.
enum AppThemeMode { light, dark, system }

/// Провайдер управления темой приложения.
///
/// Хранит выбранный режим темы, предоставляет актуальную [ThemeData]
/// и сохраняет выбор в локальном хранилище.
class ThemeProvider extends ChangeNotifier {
  ThemeProvider({SettingsRepository? repository})
      : _repository = repository ?? SettingsRepository();

  final SettingsRepository _repository;

  AppThemeMode _mode = AppThemeMode.system;

  AppThemeMode get mode => _mode;

  /// Загрузка сохранённого режима темы при старте.
  Future<void> load() async {
    final saved = await _repository.loadThemeMode();
    if (saved == null) return;

    final parsed = AppThemeMode.values.asNameMap()[saved];
    if (parsed != null) {
      _mode = parsed;
      notifyListeners();
    }
  }

  /// Переключение режима темы.
  Future<void> setMode(AppThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    await _repository.saveThemeMode(mode.name);
  }

  /// Возвращает актуальную тему в зависимости от выбранного режима.
  ThemeData themeFor(Brightness platformBrightness) {
    switch (_mode) {
      case AppThemeMode.light:
        return AppTheme.light;
      case AppThemeMode.dark:
        return AppTheme.dark;
      case AppThemeMode.system:
        return platformBrightness == Brightness.dark
            ? AppTheme.dark
            : AppTheme.light;
    }
  }
}