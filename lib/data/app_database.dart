import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Инициализация и доступ к локальной базе данных SQLite.
///
/// Использует `sqflite_common_ffi` для работы на десктопе (Windows),
/// где нет нативной поддержки `sqflite`.
class AppDatabase {
  AppDatabase._();

  static const _dbName = 'korobka.db';
  static const _dbVersion = 1;

  static Database? _instance;

  /// Путь к файлу БД для подмены в тестах.
  static String? overridePath;

  /// Возвращает синглтон базы данных, инициализируя её при первом обращении.
  static Future<Database> instance() async {
    if (_instance != null) return _instance!;

    // Для десктопных платформ используем FFI-реализацию SQLite.
    if (databaseFactory == null) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = overridePath ?? await _defaultDbPath();

    _instance = await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: _onCreate,
    );
    return _instance!;
  }

  /// Определение стандартного пути к файлу БД.
  static Future<String> _defaultDbPath() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, _dbName);
  }

  /// Создание схемы базы данных при первом запуске.
  static Future<void> _onCreate(Database db, int version) async {
    // Таблица папок.
    await db.execute('''
      CREATE TABLE folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        parent_id INTEGER,
        created_at INTEGER NOT NULL
      )
    ''');

    // Таблица элементов коллекции.
    await db.execute('''
      CREATE TABLE items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        folder_id INTEGER,
        title TEXT NOT NULL,
        path TEXT NOT NULL,
        width INTEGER,
        height INTEGER,
        format TEXT,
        palette TEXT,
        notes TEXT,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    // Таблица тегов.
    await db.execute('''
      CREATE TABLE tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )
    ''');

    // Связь many-to-many между элементами и тегами.
    await db.execute('''
      CREATE TABLE item_tags (
        item_id INTEGER NOT NULL,
        tag_id INTEGER NOT NULL,
        PRIMARY KEY (item_id, tag_id),
        FOREIGN KEY (item_id) REFERENCES items (id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES tags (id) ON DELETE CASCADE
      )
    ''');

    // Индекс для поиска по папке.
    await db.execute(
      'CREATE INDEX idx_items_folder ON items (folder_id)',
    );
    // Индекс для поиска по названию.
    await db.execute(
      'CREATE INDEX idx_items_title ON items (title)',
    );
  }

  /// Закрытие базы данных (вызывается при завершении работы).
  static Future<void> close() async {
    await _instance?.close();
    _instance = null;
  }
}