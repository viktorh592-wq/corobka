/// Модель правила умной папки.
///
/// Умная папка автоматически группирует элементы по заданным правилам:
/// по тегам, цвету, формату или дате добавления. Правила можно комбинировать.
class SmartFolder {
  const SmartFolder({
    required this.id,
    required this.name,
    this.tagNames,
    this.paletteColor,
    this.format,
    this.before,
    this.after,
  });

  /// Уникальный идентификатор умной папки.
  final int id;

  /// Название умной папки.
  final String name;

  /// Список тегов (элемент должен содержать любой из них).
  final List<String>? tagNames;

  /// Фильтр по цвету палитры (шестнадцатеричное значение).
  final String? paletteColor;

  /// Фильтр по формату файла.
  final String? format;

  /// Элементы добавленные до указанной даты.
  final DateTime? before;

  /// Элементы добавленные после указанной даты.
  final DateTime? after;
}

/// Описание правила для конфигурации умных папок.
class SmartFolderRule {
  const SmartFolderRule({
    required this.name,
    this.tagNames,
    this.paletteColor,
    this.format,
  });

  /// Название умной папки.
  final String name;

  /// Теги для фильтрации.
  final List<String>? tagNames;

  /// Цвет палитры для фильтрации.
  final String? paletteColor;

  /// Формат файла для фильтрации.
  final String? format;
}