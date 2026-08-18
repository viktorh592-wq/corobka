///
/// Тег используется для свободной маркировки элементов коллекции.
class Tag {
  const Tag({
    required this.id,
    required this.name,
  });

  /// Уникальный идентификатор тега.
  final int id;

  /// Название тега.
  final String name;

  /// Создание объекта из строки БД (SQLite row).
  factory Tag.fromMap(Map<String, dynamic> map) {
    return Tag(
      id: map['id'] as int,
      name: map['name'] as String,
    );
  }

  /// Преобразование объекта в карту для вставки в БД.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
    };
  }
}
