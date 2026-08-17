import 'package:sqflite/sqflite.dart';

import '../app_database.dart';
import '../models/tag.dart';

/// Объект доступа к данным тегов (таблицы `tags` и `item_tags`).
class TagDao {
  const TagDao();

  Future<Database> get _db => AppDatabase.instance();

  /// Создание тега (если его ещё нет). Возвращает идентификатор тега.
  Future<int> ensureTag(String name) async {
    final db = await _db;
    final rows = await db.query(
      'tags',
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.first['id'] as int;

    return db.insert('tags', {'name': name});
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