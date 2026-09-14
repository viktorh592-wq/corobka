/// Тип медиафайла (определяется по расширению).
enum ItemKind { image, video, audio }

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
    this.deletedAt,
    this.hash,
    this.bpm,
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

  /// Время перемещения в корзину (unix-время, секунды).
  /// `null` — элемент не удалён (как в Eagle: удаление сначала попадает
  /// в корзину и может быть отменено).
  final int? deletedAt;

  /// SHA-256 хэш содержимого файла (для поиска дубликатов).
  final String? hash;

  /// Значение BPM (ударов в минуту) для аудиофайлов.
  final int? bpm;

  /// Элемент находится в корзине.
  bool get isTrashed => deletedAt != null;

  /// Тип медиафайла — определяется по расширению.
  ItemKind get kind => kindOfExtension(format ?? _extensionOf(path));

  /// Это видеофайл?
  bool get isVideo => kind == ItemKind.video;

  /// Это аудиофайл?
  bool get isAudio => kind == ItemKind.audio;

  /// Это изображение?
  bool get isImage => kind == ItemKind.image;

  static String _extensionOf(String path) {
    final name = path.split('/').last.split('\\').last;
    final idx = name.lastIndexOf('.');
    return idx == -1 ? '' : name.substring(idx + 1);
  }

  /// Определение типа файла по расширению (без точки).
  static ItemKind kindOfExtension(String ext) {
    final e = ext.toLowerCase();
    const videoExts = {
      'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v', 'wmv', 'flv',
    };
    const audioExts = {
      'mp3', 'wav', 'flac', 'ogg', 'm4a', 'aac', 'wma', 'opus',
    };
    if (videoExts.contains(e)) return ItemKind.video;
    if (audioExts.contains(e)) return ItemKind.audio;
    return ItemKind.image;
  }

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
      deletedAt: map['deleted_at'] as int?,
      hash: map['hash'] as String?,
      bpm: map['bpm'] as int?,
    );
  }

  /// Преобразование объекта в карту для вставки в БД.
  Map<String, dynamic> toMap() {
    return {
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
      'deleted_at': deletedAt,
      'hash': hash,
      'bpm': bpm,
    };
  }

  /// Копирование с переопределением отдельных полей.
  CollectionItem copyWith({
    int? id,
    int? folderId,
    String? title,
    String? path,
    int? width,
    int? height,
    String? format,
    String? palette,
    String? notes,
    bool? isFavorite,
    int? createdAt,
    int? deletedAt,
    String? hash,
    int? bpm,
    bool clearFolderId = false,
    bool clearDeletedAt = false,
    bool clearNotes = false,
    bool clearBpm = false,
  }) {
    return CollectionItem(
      id: id ?? this.id,
      folderId: clearFolderId ? null : (folderId ?? this.folderId),
      title: title ?? this.title,
      path: path ?? this.path,
      width: width ?? this.width,
      height: height ?? this.height,
      format: format ?? this.format,
      palette: palette ?? this.palette,
      notes: clearNotes ? null : (notes ?? this.notes),
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      hash: hash ?? this.hash,
      bpm: clearBpm ? null : (bpm ?? this.bpm),
    );
  }

  /// Площадь изображения (для сортировки по размеру).
  int get pixelArea => (width ?? 0) * (height ?? 0);
}
