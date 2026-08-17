import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:korobka/data/app_database.dart';
import 'package:korobka/data/daos/folder_dao.dart';
import 'package:korobka/data/daos/item_dao.dart';
import 'package:korobka/data/daos/tag_dao.dart';
import 'package:korobka/data/models/folder.dart';
import 'package:korobka/data/models/item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String testDbPath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    testDbPath = p.join(
      Directory.systemTemp.path,
      'korobka_test_${DateTime.now().millisecondsSinceEpoch}.db',
    );
  });

  setUp(() async {
    await AppDatabaseTest.setDatabasePath(testDbPath);
  });

  tearDown(() async {
    await AppDatabase.close();
  });

  test('Создание папки и получение списка', () async {
    final dao = const FolderDao();
    final id = await dao.insert(const Folder(
      id: 0,
      name: 'Скриншоты',
      createdAt: 0,
    ));

    expect(id, greaterThan(0));

    final folders = await dao.getAll();
    expect(folders, hasLength(1));
    expect(folders.first.name, 'Скриншоты');
  });

  test('Добавление элемента и привязка тега', () async {
    final folderDao = const FolderDao();
    final itemDao = const ItemDao();
    final tagDao = const TagDao();

    final folderId = await folderDao.insert(const Folder(
      id: 0,
      name: 'UI',
      createdAt: 0,
    ));

    final itemId = await itemDao.insert(CollectionItem(
      id: 0,
      folderId: folderId,
      title: 'Главный экран',
      path: '/tmp/main.png',
      format: 'png',
      isFavorite: true,
      createdAt: 0,
    ));

    final tagId = await tagDao.ensureTag('интерфейс');
    await tagDao.attachTagToItem(itemId, tagId);

    final items = await itemDao.getByFolder(folderId);
    expect(items, hasLength(1));
    expect(items.first.isFavorite, isTrue);

    final tags = await tagDao.getTagsForItem(itemId);
    expect(tags, hasLength(1));
    expect(tags.first.name, 'интерфейс');
  });
}

/// Вспомогательный класс для подмены пути к БД в тестах.
class AppDatabaseTest {
  static String? overridePath;

  static void setDatabasePath(String path) {
    overridePath = path;
    AppDatabase.overridePath = path;
  }
}