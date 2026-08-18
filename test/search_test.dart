import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:korobka/data/app_database.dart';
import 'package:korobka/data/daos/item_dao.dart';
import 'package:korobka/data/models/item.dart';
import 'package:korobka/features/search/search_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ItemDao itemDao;
  late SearchService searchService;
  late String dbPath;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Уникальный путь для каждого теста, чтобы БД всегда была чистой.
    dbPath = '${Directory.systemTemp.path}/korobka_search_'
        '${DateTime.now().microsecondsSinceEpoch}.db';
    AppDatabase.overridePath = dbPath;

    itemDao = const ItemDao();
    searchService = const SearchService();
  });

  tearDown(() async {
    await AppDatabase.close();
    final file = File(dbPath);
    if (await file.exists()) {
      await file.delete();
    }
  });

  Future<void> _insert(
    String title, {
    String notes = '',
    bool fav = false,
    String? palette,
  }) async {
    await itemDao.insert(CollectionItem(
      id: 0,
      title: title,
      path: '/tmp/$title.png',
      format: 'png',
      notes: notes,
      palette: palette,
      isFavorite: fav,
      createdAt: 0,
    ));
  }

  test('Полнотекстовый поиск по названию', () async {
    await _insert('Главный экран');
    await _insert('Экран настроек');
    await _insert('Логотип');

    final results = await searchService.search(query: 'экран');
    expect(results, hasLength(2));
  });

  test('Поиск по заметкам', () async {
    await _insert('Photo1', notes: 'дизайн интерфейса');
    await _insert('Photo2');

    final results = await searchService.search(query: 'интерфейса');
    expect(results, hasLength(1));
    expect(results.first.title, 'Photo1');
  });

  test('Фильтр по избранному', () async {
    await _insert('Обычный');
    await _insert('Важный', fav: true);

    final favorites = await searchService.search(favoritesOnly: true);
    expect(favorites, hasLength(1));
    expect(favorites.first.isFavorite, isTrue);
  });

  test('Фильтр по формату', () async {
    await itemDao.insert(const CollectionItem(
      id: 0,
      title: 'Картинка',
      path: '/tmp/a.png',
      format: 'png',
      createdAt: 0,
    ));
    await itemDao.insert(const CollectionItem(
      id: 0,
      title: 'Вектор',
      path: '/tmp/b.svg',
      format: 'svg',
      createdAt: 0,
    ));

    final results = await searchService.search(format: 'svg');
    expect(results, hasLength(1));
    expect(results.first.title, 'Вектор');
  });

  test('Фильтр по цвету палитры', () async {
    await _insert('Красный элемент', palette: '["FF5722","FFFFFF"]');
    await _insert('Синий элемент', palette: '["2196F3","FFFFFF"]');

    final red = await searchService.search(paletteColor: 'FF5722');
    expect(red, hasLength(1));
    expect(red.first.title, 'Красный элемент');

    final blue = await searchService.search(paletteColor: '2196F3');
    expect(blue, hasLength(1));
    expect(blue.first.title, 'Синий элемент');
  });
}
