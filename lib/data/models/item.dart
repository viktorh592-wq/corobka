/// Модель элемента коллекции (изображение/скриншот).
///
/// Содержит метаданные изображения: название, путь к файлу,
/// размеры, формат, палитру и заметки.
class CollectionItem {
  const CollectionItem({
    required this.id,
    this.folderId,
    required this.title,
    required this.path,
    this.width,
    this.height,
    this.format,
    this.palette,
    this.notes,
    this.isFavorite = false,
    required this.createdAt,
  });

  /// Уникальный идентификатор элемента.
  final int id;

  /// Идентификатор папки, в которой находится элемент.
  final int? folderId;

  /// Название элемента.
  final String title;

  /// Путь к файлу изображения.
  final String path;

  /// Ширина изображения (в пикселях).
  final int? width;

  /// Высота изображения (в пикселях).
  final int? height;

  /// Формат файла (png, jpg, webp и т.д.).
  final String? format;

  /// Цветовая палитра, извлечённая из изображения (JSON-строка).
  final String? palette;

  /// Текстовые заметки пользователя.
  final String? notes;

  /// Флаг «избранное».
  final bool isFavorite;

  /// Дата добавления элемента (unix-время, секунды).
  final int createdAt;

  /// Создание объекта из строки БД (SQLite row).
  factory CollectionItem.fromMap(Map<String, dynamic> map) {
    return CollectionItem(
      id: map['id'] as int,
      folderId: map['folder_id'] as int?,
      title: map['title'] as String,
      path: map['path'] as String,
      width: map['width'] as int?,
      height: map['height'] as int?,
      format: map['format'] as String?,
      palette: map['palette'] as String?,
      notes: map['notes'] as String?,
      isFavorite: (map['is_favorite'] as int) == 1,
      createdAt: map['created_at'] as int,
    );
  }

  /// Преобразование объекта в карту для вставки в БД.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'folder_id': folderId,
      'title': title,
      'path': path,
      'width': width,
      'height': height,
      'format': format,
      'palette': palette,
      'notes': notes,
      'is_favorite': isFavorite ? 1 : 0,
      'created_at': createdAt,
    };
  }
}