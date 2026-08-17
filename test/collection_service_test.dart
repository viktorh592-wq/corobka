import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:korobka/data/app_database.dart';
import 'package:korobka/data/daos/item_dao.dart';
import 'package:korobka/data/models/item.dart';
import 'package:korobka/features/collection/collection_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CollectionService service;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.overridePath =
        '${Directory.systemTemp.path}/korobka_svc_test.db';
    await AppDatabase.close();

    service = CollectionService();
    await service.initializeRoot(customPath: Directory.systemTemp.path);
  });

  tearDown(() async {
    await AppDatabase.close();
  });

  test('Создание, переименование и удаление папки', () async {
    final id = await service.createFolder('Проекты');
    expect(id, greaterThan(0));

    var folders = await service.getFolders();
    expect(folders, hasLength(1));
    expect(folders.first.name, 'Проекты');

    await service.renameFolder(id, 'Дизайн');
    folders = await service.getFolders();
    expect(folders.first.name, 'Дизайн');

    await service.deleteFolder(id);
    folders = await service.getFolders();
    expect(folders, isEmpty);
  });

  test('Перемещение элемента в папку', () async {
    final folderId = await service.createFolder('Скриншоты');

    final itemId = await const ItemDao().insert(const CollectionItem(
      id: 0,
      title: 'Экран',
      path: '/tmp/screen.png',
      format: 'png',
      createdAt: 0,
    ));

    await service.moveItemToFolder(itemId, folderId);

    final inFolder = await service.getItems(folderId: folderId);
    expect(inFolder, hasLength(1));
    expect(inFolder.first.id, itemId);
  });

  test('Перемещение элемента в корень', () async {
    final folderId = await service.createFolder('Временная');

    final itemId = await const ItemDao().insert(const CollectionItem(
      id: 0,
      title: 'Экран',
      path: '/tmp/screen.png',
      format: 'png',
      folderId: folderId,
      createdAt: 0,
    ));

    await service.moveItemToFolder(itemId, null);

    final item = await const ItemDao().getById(itemId);
    expect(item?.folderId, isNull);
  });
}