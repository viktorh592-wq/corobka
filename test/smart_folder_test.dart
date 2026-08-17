import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:korobka/data/app_database.dart';
import 'package:korobka/data/daos/item_dao.dart';
import 'package:korobka/data/models/item.dart';
import 'package:korobka/features/collection/smart_folder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ItemDao itemDao;
  late SmartFolderService service;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.overridePath =
        '${Directory.systemTemp.path}/korobka_smart_test.db';
    await AppDatabase.close();

    itemDao = const ItemDao();
    service = const SmartFolderService();
  });

  tearDown(() async {
    await AppDatabase.close();
  });

  test('Умные папки создаются из правил', () {
    final folders = service.getSmartFolders();
    expect(folders, isNotEmpty);
    expect(folders.first.name, 'Избранное');
  });

  test('Умная папка по формату возвращает подходящие элементы', () async {
    await itemDao.insert(const CollectionItem(
      id: 0,
      title: 'Векторная иконка',
      path: '/tmp/icon.svg',
      format: 'svg',
      createdAt: 0,
    ));
    await itemDao.insert(const CollectionItem(
      id: 0,
      title: 'Растровый скрин',
      path: '/tmp/screen.png',
      format: 'png',
      createdAt: 0,
    ));

    final smart = service.getSmartFolders().firstWhere(
          (f) => f.name == 'Иконки',
        );
    final items = await service.getItemsFor(smart);

    expect(items, hasLength(1));
    expect(items.first.title, 'Векторная иконка');
  });
}