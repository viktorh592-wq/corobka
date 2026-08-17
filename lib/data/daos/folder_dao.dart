import 'package:sqflite/sqflite.dart';

import '../app_database.dart';
import '../models/folder.dart';

/// Объект доступа к данным папок (таблица `folders`).
class FolderDao {
  const FolderDao();

  Future<Database> get _db => AppDatabase.instance();

  /// Создание новой папки. Возвращает её идентификатор.
  Future<int> insert(Folder folder) async {
    final db = await _db;
    return db.insert('folders', folder.toMap());
  }

  /// Получение всех папок.
  Future<List<Folder>> getAll() async {
    final db = await _db;
    final rows = await db.query('folders', orderBy: 'name');
    return rows.map(Folder.fromMap).toList();
  }

  /// Получение папки по идентификатору.
  Future<Folder?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(
      'folders',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Folder.fromMap(rows.first);
  }

  /// Переименование папки.
  Future<int> rename(int id, String newName) async {
    final db = await _db;
    return db.update(
      'folders',
      {'name': newName},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Удаление папки.
  Future<int> delete(int id) async {
    final db = await _db;
    return db.delete('folders', where: 'id = ?', whereArgs: [id]);
  }
}