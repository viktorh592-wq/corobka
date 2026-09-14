import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:korobka/data/app_database.dart';
import 'package:korobka/data/daos/item_dao.dart';
import 'package:korobka/data/models/item.dart';
import 'package:korobka/features/collection/collection_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String testDbPath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    testDbPath = p.join(
      Directory.systemTemp.path,
      'korobka_trash_test_${DateTime.now().millisecondsSinceEpoch}.db',
    );
  });

  setUp(() async {
    AppDatabaseTest.setDatabasePath(testDbPath);
    // Каждый тест начинается с чистой базой (иначе данные предыдущих
    // тестов накапливаются и ломают счётчики).
    final f = File(testDbPath);
    if (await f.exists()) {
      await f.delete();
    }
  });

  tearDown(() async {
    await AppDatabase.close();
  });

  CollectionItem makeItem(int id, {String? title, bool favorite = false}) {
    return CollectionItem(
      id: id,
      title: title ?? 'item_$id.png',
      path: '/tmp/item_$id.png',
      width: 10 * id,
      height: 10 * id,
      format: 'png',
      isFavorite: favorite,
      createdAt: 1000 + id,
    );
  }

  test('Мягкое удаление: getAll скрывает корзину, getTrashed показывает',
      () async {
    const dao = ItemDao();
    await dao.insert(makeItem(0));
    await dao.insert(makeItem(0));

    final before = await dao.getAll();
    expect(before, hasLength(2));

    // Перемещаем первый элемент в корзину.
    final first = before.first;
    await dao.moveToTrash(first.id, deletedAt: 9999);

    // Активный список — без удалённого.
    final active = await dao.getAll();
    expect(active, hasLength(1));
    expect(active.firstWhere((e) => e.id == first.id, orElse: () => active.first).id,
        isNot(first.id));

    // Корзина — только удалённый.
    final trashed = await dao.getTrashed();
    expect(trashed, hasLength(1));
    expect(trashed.first.id, first.id);
    expect(trashed.first.isTrashed, isTrue);

    // Восстановление возвращает элемент.
    await dao.restoreFromTrash(first.id);
    final restored = await dao.getAll();
    expect(restored, hasLength(2));
    final inTrash = await dao.getTrashed();
    expect(inTrash, isEmpty);
  });

  test('Поиск по умолчанию исключает корзину', () async {
    const dao = ItemDao();
    await dao.insert(makeItem(0, title: 'уникальный_запрос.png'));
    await dao.insert(makeItem(0, title: 'уникальный_запрос_2.png'));

    final items = await dao.search(const ItemFilter(query: 'уникальный'));
    expect(items, hasLength(2));

    await dao.moveToTrash(items.first.id, deletedAt: 555);

    final afterTrash = await dao.search(const ItemFilter(query: 'уникальный'));
    expect(afterTrash, hasLength(1));

    final withTrash =
        await dao.search(const ItemFilter(query: 'уникальный', includeTrashed: true));
    expect(withTrash, hasLength(2));
  });

  test('countByFolder возвращает счётчики только активных элементов', () async {
    const dao = ItemDao();
    final a = makeItem(0);
    final b = makeItem(0);
    final c = makeItem(0).copyWith(folderId: 42);

    final idA = await dao.insert(a);
    await dao.insert(b);
    await dao.insert(c);

    var counts = await dao.countByFolder();
    expect(counts[null], 2); // корень: a + b
    expect(counts[42], 1);

    // a в корзину → в корне остаётся 1.
    await dao.moveToTrash(idA, deletedAt: 1);
    counts = await dao.countByFolder();
    expect(counts[null], 1);
  });

  test('SortMode меняет порядок элементов', () {
    final items = [
      makeItem(1, title: 'b'),
      makeItem(2, title: 'A'),
      makeItem(3, title: 'c'),
    ];

    List<CollectionItem> sorted(SortMode mode) {
      final copy = [...items];
      switch (mode) {
        case SortMode.dateDesc:
          copy.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        case SortMode.dateAsc:
          copy.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        case SortMode.nameAsc:
          copy.sort((a, b) =>
              a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        case SortMode.nameDesc:
          copy.sort((a, b) =>
              b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        case SortMode.sizeDesc:
          copy.sort((a, b) => b.pixelArea.compareTo(a.pixelArea));
      }
      return copy;
    }

    expect(sorted(SortMode.dateAsc).map((e) => e.id).toList(), [1, 2, 3]);
    expect(sorted(SortMode.dateDesc).map((e) => e.id).toList(), [3, 2, 1]);
    expect(sorted(SortMode.nameAsc).map((e) => e.id).toList(), [2, 1, 3]);
    expect(sorted(SortMode.nameDesc).map((e) => e.id).toList(), [3, 1, 2]);
    // pixelArea: id1=100, id2=400, id3=900 → по убыванию [3, 2, 1].
    expect(sorted(SortMode.sizeDesc).map((e) => e.id).toList(), [3, 2, 1]);
  });

  test('copyWith частично обновляет поля и умеет очищать', () {
    final item = makeItem(1, title: 'orig.png');
    final updated = item.copyWith(title: 'new.png', notes: 'заметка');
    expect(updated.title, 'new.png');
    expect(updated.notes, 'заметка');
    expect(updated.id, 1);

    final cleared = updated.copyWith(clearNotes: true);
    expect(cleared.notes, isNull);

    final clearedFolder = item.copyWith(folderId: 5);
    expect(clearedFolder.folderId, 5);
    expect(item.copyWith(clearFolderId: true).folderId, isNull);
  });

  test('Миграция v1 → v2 добавляет deleted_at и сохраняет данные', () async {
    // Открываем БД вручную со схемой v1 (без deleted_at).
    final legacyPath = p.join(
      Directory.systemTemp.path,
      'korobka_legacy_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    final legacyDb = await openDatabase(legacyPath, version: 1);
    await legacyDb.execute('''
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
    await legacyDb.insert('items', {
      'title': 'legacy.png',
      'path': '/tmp/legacy.png',
      'is_favorite': 0,
      'created_at': 123,
    });
    await legacyDb.close();

    // Открываем через AppDatabase (v2) — должна выполниться миграция.
    AppDatabase.overridePath = legacyPath;
    try {
      const dao = ItemDao();
      final items = await dao.getAll();
      expect(items, hasLength(1));
      expect(items.first.title, 'legacy.png');
      expect(items.first.deletedAt, isNull);
    } finally {
      AppDatabase.overridePath = null;
      final db = await AppDatabase.instance();
      await db.close();
    }
  });
}

/// Хелпер доступа к overridePath (как в database_test.dart).
class AppDatabaseTest {
  static void setDatabasePath(String path) {
    AppDatabase.overridePath = path;
  }
}
