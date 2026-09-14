import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Инициализация и доступ к локальной базе данных SQLite.
///
/// Использует `sqflite_common_ffi` для работы на десктопе (Windows),
/// где нет нативной поддержки `sqflite`.
class AppDatabase {
  AppDatabase._();

  static const _dbName = 'korobka.db';
  static const _dbVersion = 4;

  static Database? _instance;

  /// Путь к файлу БД для подмены в тестах.
  static String? overridePath;

  /// Возвращает синглтон базы данных, инициализируя её при первом обращении.
  static Future<Database> instance() async {
    if (_instance != null) return _instance!;

    // Для десктопных платформ используем FFI-реализацию SQLite.
    //
    // КРИТИЧНО: глобальный геттер `databaseFactory` из sqflite_common
    // НЕ МОЖЕТ быть null — он бросает StateError при обращении, если
    // фабрика не установлена. Поэтому проверка `if (databaseFactory == null)`
    // всегда была ложной, FFI-инициализация никогда не выполнялась и
    // ЛЮБАЯ операция с БД падала («databaseFactory not initialized»).
    // Именно поэтому в приложении работало только переключение темы.
    //
    // Правильная последовательность — безусловная (документированный
    // шаблон sqflite_common_ffi):
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dbPath = overridePath ?? await _defaultDbPath();

    _instance = await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _instance!;
  }

  /// Определение стандартного пути к файлу БД.
  static Future<String> _defaultDbPath() async {
    try {
      final dir = await getApplicationSupportDirectory();
      if (dir.path.isNotEmpty) return p.join(dir.path, _dbName);
    } catch (e) {
      // path_provider недоступен — используем запасной путь.
    }
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    final base = home != null && home.isNotEmpty ? home : Directory.current.path;
    return p.join(base, _dbName);
  }

  /// Создание схемы базы данных при первом запуске.
  static Future<void> _onCreate(Database db, int version) async {
    // Таблица папок.
    await db.execute('''
      CREATE TABLE folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        parent_id INTEGER,
        created_at INTEGER NOT NULL,
        color TEXT
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
        created_at INTEGER NOT NULL,
        deleted_at INTEGER,
        hash TEXT,
        bpm INTEGER
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

  /// Миграции при обновлении версии схемы.
  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      // v2: корзина (мягкое удаление, как в Eagle).
      // Колонка может уже существовать, если БД создана свежим кодом.
      final cols = await db.rawQuery('PRAGMA table_info(items)');
      final hasColumn = cols.any((c) => c['name'] == 'deleted_at');
      if (!hasColumn) {
        await db.execute('ALTER TABLE items ADD COLUMN deleted_at INTEGER');
      }
    }

    if (oldVersion < 3) {
      // v3: дубликаты (SHA-256 хэш файла) и BPM для аудио.
      // Колонки могли уже появиться, если БД создана свежим кодом.
      final cols = await db.rawQuery('PRAGMA table_info(items)');
      final hasHash = cols.any((c) => c['name'] == 'hash');
      if (!hasHash) {
        await db.execute('ALTER TABLE items ADD COLUMN hash TEXT');
      }
      final hasBpm = cols.any((c) => c['name'] == 'bpm');
      if (!hasBpm) {
        await db.execute('ALTER TABLE items ADD COLUMN bpm INTEGER');
      }
    }

    if (oldVersion < 4) {
      // v4: цвет иконки папки (HEX-строка) для «настройки цвета папки».
      // Защита: у совсем старых БД (например, легаси-схема v1 из тестов)
      // таблицы folders может не быть — создаём её целиком.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS folders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          parent_id INTEGER,
          created_at INTEGER NOT NULL,
          color TEXT
        )
      ''');
      final cols = await db.rawQuery('PRAGMA table_info(folders)');
      final hasColor = cols.any((c) => c['name'] == 'color');
      if (!hasColor) {
        await db.execute('ALTER TABLE folders ADD COLUMN color TEXT');
      }
    }
  }

  /// Закрытие базы данных (вызывается при завершении работы).
  static Future<void> close() async {
    await _instance?.close();
    _instance = null;
  }
}
