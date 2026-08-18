import 'package:sqflite/sqflite.dart';

import '../app_database.dart';
import '../models/item.dart';

/// Объект доступа к данным элементов коллекции (таблица `items`).
class ItemDao {
  const ItemDao();

  Future<Database> get _db => AppDatabase.instance();

  /// Вставка нового элемента. Возвращает его идентификатор.
  Future<int> insert(CollectionItem item) async {
    final db = await _db;
    return db.insert('items', item.toMap());
  }

  /// Получение всех элементов (с сортировкой по дате добавления).
  Future<List<CollectionItem>> getAll({int? folderId}) async {
    final db = await _db;
    final rows = await db.query(
      'items',
      where: folderId == null ? null : 'folder_id = ?',
      whereArgs: folderId == null ? null : [folderId],
      orderBy: 'created_at DESC',
    );
    return rows.map(CollectionItem.fromMap).toList();
  }

  /// Получение элементов в указанной папке.
  Future<List<CollectionItem>> getByFolder(int folderId) =>
      getAll(folderId: folderId);

  /// Получение элемента по идентификатору.
  Future<CollectionItem?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(
      'items',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : CollectionItem.fromMap(rows.first);
  }

  /// Обновление названия и заметок элемента.
  Future<int> updateAnnotations(
    int id, {
    String? title,
    String? notes,
  }) async {
    final db = await _db;
    final values = <String, Object?>{};
    if (title != null) values['title'] = title;
    if (notes != null) values['notes'] = notes;
    return db.update('items', values, where: 'id = ?', whereArgs: [id]);
  }

  /// Установка флага «избранное».
  Future<int> setFavorite(int id, bool isFavorite) async {
    final db = await _db;
    return db.update(
      'items',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Перемещение элемента в другую папку (null — в корень).
  Future<int> moveToFolder(int id, int? folderId) async {
    final db = await _db;
    return db.update(
      'items',
      {'folder_id': folderId},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Удаление элемента.
  Future<int> delete(int id) async {
    final db = await _db;
    return db.delete('items', where: 'id = ?', whereArgs: [id]);
  }

  /// Поиск элементов по фильтру.
  ///
  /// Поддерживает полнотекстовый поиск по названию и заметкам, фильтр по
  /// папке, избранному, тегам, формату, диапазону дат и цвету палитры.
  Future<List<CollectionItem>> search(ItemFilter filter) async {
    final db = await _db;

    final where = <String>[];
    final args = <Object?>[];

    if (filter.folderId != null) {
      where.add('folder_id = ?');
      args.add(filter.folderId);
    }

    if (filter.favoritesOnly) {
      where.add('is_favorite = 1');
    }

    if (filter.query != null && filter.query!.trim().isNotEmpty) {
      final like = '%${filter.query!.trim()}%';
      where.add('(title LIKE ? OR notes LIKE ?)');
      args.add(like);
      args.add(like);
    }

    if (filter.format != null) {
      where.add('format = ?');
      args.add(filter.format);
    }

    if (filter.createdBefore != null) {
      where.add('created_at <= ?');
      args.add(filter.createdBefore);
    }

    if (filter.createdAfter != null) {
      where.add('created_at >= ?');
      args.add(filter.createdAfter);
    }

    // Фильтр по цвету палитры (ищем шестнадцатеричное значение в JSON).
    if (filter.paletteColor != null) {
      where.add('palette LIKE ?');
      args.add('%${filter.paletteColor!.toUpperCase()}%');
    }

    if (filter.tagIds != null && filter.tagIds!.isNotEmpty) {
      // Фильтр по тегам (AND): элемент должен иметь все указанные теги.
      final placeholders = List.filled(filter.tagIds!.length, '?').join(', ');
      where.add(
        'id IN ('
        '  SELECT item_id FROM item_tags '
        '  WHERE tag_id IN ($placeholders) '
        '  GROUP BY item_id '
        '  HAVING COUNT(DISTINCT tag_id) = ?'
        ')',
      );
      args.addAll(filter.tagIds!);
      args.add(filter.tagIds!.length);
    }

    final whereClause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final sql = 'SELECT * FROM items $whereClause ORDER BY created_at DESC';

    final rows = await db.rawQuery(sql, args);
    return rows.map(CollectionItem.fromMap).toList();
  }
}

/// Фильтр для поиска элементов коллекции.
///
/// Передаётся в [ItemDao.search] для полнотекстового поиска и фильтрации
/// по папке, избранному, тегам, формату, дате и цвету палитры.
class ItemFilter {
  const ItemFilter({
    this.query,
    this.folderId,
    this.favoritesOnly = false,
    this.tagIds,
    this.format,
    this.createdBefore,
    this.createdAfter,
    this.paletteColor,
  });

  /// Поисковый запрос (поиск по названию и заметкам).
  final String? query;

  /// Идентификатор папки для фильтрации.
  final int? folderId;

  /// Показывать только избранные элементы.
  final bool favoritesOnly;

  /// Список идентификаторов тегов (элемент должен иметь все).
  final List<int>? tagIds;

  /// Фильтр по формату файла.
  final String? format;

  /// Элементы добавленные не позже указанного времени (unix-секунды).
  final int? createdBefore;

  /// Элементы добавленные не раньше указанного времени (unix-секунды).
  final int? createdAfter;

  /// Фильтр по цвету палитры (шестнадцатеричное значение без '#').
  final String? paletteColor;
}
