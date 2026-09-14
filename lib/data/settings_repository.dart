import 'package:shared_preferences/shared_preferences.dart';

/// Репозиторий хранения настроек интерфейса.
///
/// Сохраняет режим темы, режим просмотра и путь к корневому каталогу
/// коллекции в локальном хранилище (`shared_preferences`).
class SettingsRepository {
  static const _kThemeMode = 'theme_mode';
  static const _kViewMode = 'view_mode';
  static const _kRootPath = 'collection_root_path';
  static const _kSortMode = 'sort_mode';
  static const _kThumbnailExtent = 'thumbnail_extent';

  /// Сохранение режима темы.
  Future<void> saveThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, mode);
  }

  /// Чтение сохранённого режима темы. `null`, если не задан.
  Future<String?> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kThemeMode);
  }

  /// Сохранение режима просмотра.
  Future<void> saveViewMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kViewMode, mode);
  }

  /// Чтение сохранённого режима просмотра. `null`, если не задан.
  Future<String?> loadViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kViewMode);
  }

  /// Сохранение пути к корневому каталогу коллекции.
  Future<void> saveRootPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRootPath, path);
  }

  /// Чтение сохранённого пути к корневому каталогу. `null`, если не задан.
  Future<String?> loadRootPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kRootPath);
  }

  /// Сохранение режима сортировки.
  Future<void> saveSortMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSortMode, mode);
  }

  /// Чтение сохранённого режима сортировки. `null`, если не задан.
  Future<String?> loadSortMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSortMode);
  }

  /// Сохранение размера превью в сетке.
  Future<void> saveThumbnailExtent(double extent) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kThumbnailExtent, extent);
  }

  /// Чтение сохранённого размера превью. `null`, если не задан.
  Future<double?> loadThumbnailExtent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kThumbnailExtent);
  }
}