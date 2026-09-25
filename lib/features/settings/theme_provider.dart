import 'package:flutter/material.dart';

import '../../data/settings_repository.dart';
import '../../theme/app_theme.dart';

/// Возможные режимы темы интерфейса.
enum AppThemeMode { light, dark, system }

/// Провайдер управления темой приложения.
///
/// Хранит выбранные:
/// - [_mode] — яркость (light / dark / system);
/// - [_design] — дизайн-систему интерфейса (Material / iOS Frosted / iOS Transparent).
///
/// Соответствующая [ThemeData] собирается через [AppTheme.themeFor]
/// при каждой перестройке корневого [MaterialApp] (см. [main.dart]).
class ThemeProvider extends ChangeNotifier {
  ThemeProvider({SettingsRepository? repository})
      : _repository = repository ?? SettingsRepository();

  final SettingsRepository _repository;

  AppThemeMode _mode = AppThemeMode.system;
  AppDesignSystem _design = AppDesignSystem.material;

  AppThemeMode get mode => _mode;
  AppDesignSystem get design => _design;

  /// Загрузка сохранённых настроек темы при старте.
  Future<void> load() async {
    final savedMode = await _repository.loadThemeMode();
    if (savedMode != null) {
      final parsed = AppThemeMode.values.asNameMap()[savedMode];
      if (parsed != null) _mode = parsed;
    }

    final savedDesign = await _repository.loadDesignSystem();
    if (savedDesign != null) {
      final parsed = AppDesignSystem.values.asNameMap()[savedDesign];
      if (parsed != null) _design = parsed;
    }
    notifyListeners();
  }

  /// Переключение режима яркости.
  Future<void> setMode(AppThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    await _repository.saveThemeMode(mode.name);
  }

  /// Переключение дизайн-системы интерфейса.
  Future<void> setDesign(AppDesignSystem design) async {
    if (design == _design) return;
    _design = design;
    notifyListeners();
    await _repository.saveDesignSystem(design.name);
  }

  /// Возвращает актуальную тему в зависимости от выбранных режима и яркости.
  ThemeData themeFor(Brightness platformBrightness) {
    final effective = _mode == AppThemeMode.system
        ? platformBrightness
        : (_mode == AppThemeMode.dark ? Brightness.dark : Brightness.light);
    return AppTheme.themeFor(_design, effective);
  }
}
