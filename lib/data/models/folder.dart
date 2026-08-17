/// Модель папки коллекции.
///
/// Представляет узел иерархической структуры папок, в которых
/// группируются элементы коллекции (скриншоты).
class Folder {
  const Folder({
    required this.id,
    required this.name,
    this.parentId,
    required this.createdAt,
  });

  /// Уникальный идентификатор папки.
  final int id;

  /// Название папки.
  final String name;

  /// Идентификатор родительской папки. `null` — корневая папка.
  final int? parentId;

  /// Дата создания папки (unix-время, секунды).
  final int createdAt;

  /// Создание объекта из строки БД (SQLite row).
  factory Folder.fromMap(Map<String, dynamic> map) {
    return Folder(
      id: map['id'] as int,
      name: map['name'] as String,
      parentId: map['parent_id'] as int?,
      createdAt: map['created_at'] as int,
    );
  }

  /// Преобразование объекта в карту для вставки в БД.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'parent_id': parentId,
      'created_at': createdAt,
    };
  }
}