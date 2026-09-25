import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'dart:math' as math;

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
  /// Элементы из корзины исключаются.
  Future<List<CollectionItem>> getAll({int? folderId}) async {
    final db = await _db;
    final rows = await db.query(
      'items',
      where: folderId == null ? 'deleted_at IS NULL' : 'deleted_at IS NULL AND folder_id = ?',
      whereArgs: folderId == null ? null : [folderId],
      orderBy: 'created_at DESC',
    );
    return rows.map(CollectionItem.fromMap).toList();
  }

  /// Получение элементов, находящихся в корзине.
  Future<List<CollectionItem>> getTrashed() async {
    final db = await _db;
    final rows = await db.query(
      'items',
      where: 'deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC',
    );
    return rows.map(CollectionItem.fromMap).toList();
  }

  /// Количество активных (не удалённых) элементов по каждой папке.
  /// Ключ `null` — количество элементов вне папок (корень).
  Future<Map<int?, int>> countByFolder() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT folder_id, COUNT(*) AS cnt
      FROM items
      WHERE deleted_at IS NULL
      GROUP BY folder_id
    ''');
    return {
      for (final row in rows) row['folder_id'] as int?: row['cnt'] as int,
    };
  }

  /// Мягкое удаление: перемещение элемента в корзину.
  Future<int> moveToTrash(int id, {required int deletedAt}) async {
    final db = await _db;
    return db.update(
      'items',
      {'deleted_at': deletedAt},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Восстановление элемента из корзины.
  Future<int> restoreFromTrash(int id) async {
    final db = await _db;
    return db.update(
      'items',
      {'deleted_at': null},
      where: 'id = ?',
      whereArgs: [id],
    );
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

  /// Обновление SHA-256 хэша элемента (для поиска дубликатов).
  Future<int> updateHash(int id, String? hash) async {
    final db = await _db;
    return db.update(
      'items',
      {'hash': hash},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Обновление BPM аудиофайла (null — сбросить).
  Future<int> updateBpm(int id, int? bpm) async {
    final db = await _db;
    return db.update(
      'items',
      {'bpm': bpm},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Обновление цветовой палитры элемента (JSON-строка `["RRGGBB", ...]`).
  ///
  /// Используется при пересчёте палитры после изменения числа цветов
  /// (раньше было 5, стало 10 — старые записи хранят устаревшую палитру).
  Future<int> updatePalette(int id, String? palette) async {
    final db = await _db;
    return db.update(
      'items',
      {'palette': palette},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Все элементы коллекции (без корзины) — для массового пересчёта
  /// палитры.
  Future<List<CollectionItem>> allActiveItems() async {
    final db = await _db;
    final rows = await db.query(
      'items',
      where: 'deleted_at IS NULL',
    );
    return rows.map(CollectionItem.fromMap).toList();
  }

  /// Группы дубликатов: элементы с одинаковым хэшем содержимого.
  /// Возвращает список групп (в группе минимум 2 элемента).
  Future<List<List<CollectionItem>>> getDuplicateGroups() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT * FROM items
      WHERE deleted_at IS NULL AND hash IS NOT NULL
        AND hash IN (
          SELECT hash FROM items
          WHERE deleted_at IS NULL AND hash IS NOT NULL
          GROUP BY hash
          HAVING COUNT(*) > 1
        )
      ORDER BY hash, created_at ASC
    ''');

    final items = rows.map(CollectionItem.fromMap).toList();
    final groups = <List<CollectionItem>>[];
    String? currentHash;
    var hasCurrent = false;
    var currentGroup = <CollectionItem>[];
    for (final item in items) {
      if (!hasCurrent || item.hash != currentHash) {
        if (currentGroup.length > 1) groups.add(currentGroup);
        currentHash = item.hash;
        hasCurrent = true;
        currentGroup = [item];
      } else {
        currentGroup.add(item);
      }
    }
    if (currentGroup.length > 1) groups.add(currentGroup);
    return groups;
  }

  /// Элементы без вычисленного хэша (для обратного заполнения).
  Future<List<CollectionItem>> getWithoutHash({int limit = 500}) async {
    final db = await _db;
    final rows = await db.query(
      'items',
      where: 'deleted_at IS NULL AND hash IS NULL',
      limit: limit,
    );
    return rows.map(CollectionItem.fromMap).toList();
  }

  /// Поиск элементов по фильтру.
  ///
  /// SQL применяется для фильтров по папке, избранному, формату, дате,
  /// цвету и тегам. Полнотекстовый поиск по названию/заметкам выполняется
  /// на стороне Dart (регистронезависимо для кириллицы).
  Future<List<CollectionItem>> search(ItemFilter filter) async {
    final db = await _db;

    final where = <String>[];
    final args = <Object?>[];

    // Из поиска по умолчанию исключаем элементы в корзине.
    if (!filter.includeTrashed) {
      where.add('deleted_at IS NULL');
    }

    if (filter.folderId != null) {
      where.add('folder_id = ?');
      args.add(filter.folderId);
    }

    if (filter.favoritesOnly) {
      where.add('is_favorite = 1');
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
    var items = rows.map(CollectionItem.fromMap).toList();

    // Полнотекстовый поиск — надёжно на стороне Dart.
    // Регистронезависимо для кириллицы через toLowerCase().
    if (filter.query != null && filter.query!.trim().isNotEmpty) {
      final q = filter.query!.trim().toLowerCase();
      items = items.where((e) {
        final title = e.title.toLowerCase();
        final notes = (e.notes ?? '').toLowerCase();
        return title.contains(q) || notes.contains(q);
      }).toList();
    }

    // Поиск по кастомному цвету + похожим оттенкам.
    // SQL LIKE не подходит — нужно вычислять расстояние в RGB
    // между целевым цветом и каждым цветом палитры элемента.
    if (filter.paletteColorSimilar != null) {
      final target = _parseHex(filter.paletteColorSimilar!);
      if (target != null) {
        final tol = filter.colorTolerance.clamp(0.0, 1.0);
        items = items.where((e) => _paletteMatches(e, target, tol)).toList();
      }
    }

    return items;
  }

  /// Проверяет, есть ли в палитре элемента цвет, близкий к целевому.
  ///
  /// Палитра хранится как JSON-массив строк вида `["RRGGBB", ...]`.
  /// Расстояние — нормализованное Евклидово в RGB (0 = точно совпадает,
  /// 1 = максимально удалённые цвета). Считается от ближайшего цвета палитры.
  static bool _paletteMatches(CollectionItem item, _Rgb target, double tol) {
    final palette = item.palette;
    if (palette == null || palette.isEmpty) return false;
    try {
      final decoded = jsonDecode(palette);
      if (decoded is! List) return false;
      for (final raw in decoded) {
        if (raw is! String) continue;
        final c = _parseHex(raw);
        if (c == null) continue;
        if (_distance(target, c) <= tol) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Евклидово расстояние между двумя цветами в нормированном RGB-кубе.
  /// Возвращает значение от 0 (одинаковые цвета) до 1 (максимально разные).
  static double _distance(_Rgb a, _Rgb b) {
    final dr = (a.r - b.r).toDouble();
    final dg = (a.g - b.g).toDouble();
    final db = (a.b - b.b).toDouble();
    // Максимальное расстояние в RGB-кубе со стороной 255 = sqrt(3 * 255^2) ≈ 441.673.
    const maxDist = 441.67303395087074;
    return math.sqrt(dr * dr + dg * dg + db * db) / maxDist;
  }

  /// Разбор строки вида `"RRGGBB"`, `"#RRGGBB"` или `"#RGB"`.
  /// Возвращает null, если строка не похожа на HEX-цвет.
  static _Rgb? _parseHex(String input) {
    var s = input.trim().toUpperCase();
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 3) {
      s = s.split('').map((c) => '$c$c').join();
    }
    if (s.length != 6) return null;
    final v = int.tryParse(s, radix: 16);
    if (v == null) return null;
    return _Rgb((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
  }
}

/// RGB-цвет в виде трёх байтовых компонент.
class _Rgb {
  const _Rgb(this.r, this.g, this.b);
  final int r, g, b;
}

/// Фильтр для поиска элементов коллекции.
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
    this.paletteColorSimilar,
    this.colorTolerance = 0.15,
    this.includeTrashed = false,
  });

  final String? query;
  final int? folderId;
  final bool favoritesOnly;
  final List<int>? tagIds;
  final String? format;
  final int? createdBefore;
  final int? createdAfter;
  final String? paletteColor;

  /// Поиск по кастомному цвету и похожим оттенкам.
  /// HEX-строка (`RRGGBB`, `#RRGGBB`, `RGB`). Использует расстояние в RGB
  /// к каждому цвету палитры элемента; если хотя бы один цвет попадает
  /// в [colorTolerance], элемент включается в результат.
  final String? paletteColorSimilar;

  /// Допустимое нормализованное расстояние (0 = точное совпадение,
  /// 1 = любые цвета). По умолчанию 0.15 — «похожий оттенок».
  final double colorTolerance;

  /// Включать ли элементы из корзины в результат поиска.
  final bool includeTrashed;
}
