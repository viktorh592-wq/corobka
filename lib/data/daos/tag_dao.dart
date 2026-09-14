import 'package:sqflite/sqflite.dart';

import '../app_database.dart';
import '../models/tag.dart';

/// Объект доступа к данным тегов (таблицы `tags` и `item_tags`).
class TagDao {
  const TagDao();

  Future<Database> get _db => AppDatabase.instance();

  /// Создание тега (если его ещё нет). Возвращает идентификатор тега.
  ///
  /// ВАЖНО: сравнение регистронезависимое и выполняется В DART, потому что
  /// SQLite `COLLATE NOCASE` сворачивает только ASCII (A-Z) и НЕ работает
  /// для кириллицы («Природа» и «природа» были бы разными тегами).
  Future<int> ensureTag(String name) async {
    final db = await _db;
    final trimmed = name.trim();
    final lower = trimmed.toLowerCase();

    final all = await db.query('tags');
    for (final row in all) {
      if ((row['name'] as String).toLowerCase() == lower) {
        return row['id'] as int;
      }
    }

    try {
      return await db.insert('tags', {'name': trimmed});
    } catch (e) {
      // Гонка с параллельной вставкой (UNIQUE) — перечитываем.
      final again = await db.query('tags');
      for (final row in again) {
        if ((row['name'] as String).toLowerCase() == lower) {
          return row['id'] as int;
        }
      }
      rethrow;
    }
  }

  /// Получение всех тегов с количеством элементов, к которым они привязаны.
  Future<List<(Tag, int)>> getAllWithCounts() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT t.id, t.name, COUNT(it.item_id) AS cnt
      FROM tags t
      LEFT JOIN item_tags it ON it.tag_id = t.id
      GROUP BY t.id
      ORDER BY t.name COLLATE NOCASE
    ''');
    return [
      for (final row in rows)
        (
          Tag(id: row['id'] as int, name: row['name'] as String),
          row['cnt'] as int,
        ),
    ];
  }

  /// Получение всех тегов.
  Future<List<Tag>> getAll() async {
    final db = await _db;
    final rows = await db.query('tags', orderBy: 'name');
    return rows.map(Tag.fromMap).toList();
  }

  /// Привязка тега к элементу.
  Future<void> attachTagToItem(int itemId, int tagId) async {
    final db = await _db;
    await db.insert('item_tags', {
      'item_id': itemId,
      'tag_id': tagId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Получение тегов элемента.
  Future<List<Tag>> getTagsForItem(int itemId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT t.* FROM tags t
      INNER JOIN item_tags it ON it.tag_id = t.id
      WHERE it.item_id = ?
      ORDER BY t.name
    ''', [itemId]);
    return rows.map(Tag.fromMap).toList();
  }

  /// Удаление связи тега с элементом.
  Future<void> detachTagFromItem(int itemId, int tagId) async {
    final db = await _db;
    await db.delete(
      'item_tags',
      where: 'item_id = ? AND tag_id = ?',
      whereArgs: [itemId, tagId],
    );
  }

  /// Удаление тега.
  Future<int> delete(int id) async {
    final db = await _db;
    return db.delete('tags', where: 'id = ?', whereArgs: [id]);
  }
}