import 'package:sqflite/sqflite.dart';

import '../app_database.dart';
import '../models/folder.dart';

/// Объект доступа к данным папок (таблица `folders`).
///
/// Папки образуют иерархию через поле `parent_id` (null = корневая).
/// Удаление папки не затрагивает элементы (они остаются в коллекции),
/// но дочерние подпапки «поднимаются» на уровень удаляемой (их parent_id
/// становится равным parent_id удаляемой).
class FolderDao {
  const FolderDao();

  Future<Database> get _db => AppDatabase.instance();

  /// Создание новой папки. Возвращает её идентификатор.
  Future<int> insert(Folder folder) async {
    final db = await _db;
    return db.insert('folders', folder.toMap());
  }

  /// Получение всех папок (плоский список).
  Future<List<Folder>> getAll() async {
    final db = await _db;
    final rows = await db.query('folders', orderBy: 'name');
    return rows.map(Folder.fromMap).toList();
  }

  /// Получение прямых дочерних папок указанного родителя.
  /// `parentId == null` возвращает корневые папки.
  Future<List<Folder>> getChildren(int? parentId) async {
    final db = await _db;
    final rows = await db.query(
      'folders',
      where: parentId == null
          ? 'parent_id IS NULL'
          : 'parent_id = ?',
      whereArgs: parentId == null ? null : [parentId],
      orderBy: 'name',
    );
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

  /// Установка цвета иконки папки. `null` возвращает стандартный цвет.
  Future<int> setColor(int id, String? hexColor) async {
    final db = await _db;
    return db.update(
      'folders',
      {'color': hexColor},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Перемещение папки под нового родителя (null — в корень).
  Future<int> moveToParent(int id, int? parentId) async {
    final db = await _db;
    return db.update(
      'folders',
      {'parent_id': parentId},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Удаление папки. Дочерние подпапки поднимаются на уровень удаляемой
  /// (наследуют её parent_id), чтобы не потеряться в иерархии.
  Future<int> delete(int id, {int? newParentId}) async {
    final db = await _db;
    final folder = await getById(id);
    final inheritParent = newParentId ?? folder?.parentId;
    // Переподчиняем дочерние папки, чтобы они не остались «висящими».
    await db.update(
      'folders',
      {'parent_id': inheritParent},
      where: 'parent_id = ?',
      whereArgs: [id],
    );
    return db.delete('folders', where: 'id = ?', whereArgs: [id]);
  }
}