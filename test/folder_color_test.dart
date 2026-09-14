import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:korobka/data/app_database.dart';
import 'package:korobka/data/daos/folder_dao.dart';
import 'package:korobka/data/models/folder.dart';
import 'package:korobka/features/collection/collection_service.dart';
import 'package:korobka/features/folders/folder_colors.dart';

/// Тесты «настройки цвета папки» (v4 схемы БД):
/// колонка folders.color, DAO setColor, сервис setFolderColor и
/// утилиты разбора HEX.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CollectionService service;
  late String dbPath;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dbPath = '${Directory.systemTemp.path}/korobka_folder_color_test_'
        '${DateTime.now().microsecondsSinceEpoch}.db';
    AppDatabase.overridePath = dbPath;
    await AppDatabase.close();

    service = CollectionService();
    await service.initializeRoot(customPath: Directory.systemTemp.path);
  });

  tearDown(() async {
    await AppDatabase.close();
    final file = File(dbPath);
    if (await file.exists()) {
      await file.delete();
    }
  });

  test('Разбор HEX: полный, с решёткой, короткий и некорректный', () {
    expect(colorFromHex('F44336'), const Color(0xFFF44336));
    expect(colorFromHex('#2196F3'), const Color(0xFF2196F3));
    expect(colorFromHex('F53'), const Color(0xFFFF5533));
    expect(colorFromHex(null), isNull);
    expect(colorFromHex(''), isNull);
    expect(colorFromHex('ZZZZZZ'), isNull);
    expect(colorFromHex('12345'), isNull);
  });

  test('hexOfColor возвращает 6 заглавных символов без решётки', () {
    expect(hexOfColor(const Color(0xFFF44336)), 'F44336');
    expect(hexOfColor(const Color(0xFF000000)), '000000');
    // Раунд-трип: parse → format → parse.
    final parsed = colorFromHex('4CAF50')!;
    expect(colorFromHex(hexOfColor(parsed)), parsed);
  });

  test('Модель Folder сохраняет и читает цвет (fromMap/toMap)', () {
    const folder = Folder(
      id: 1,
      name: 'видео',
      createdAt: 100,
      color: 'E91E63',
    );

    final map = folder.toMap();
    expect(map['color'], 'E91E63');

    final restored = Folder.fromMap({
      'id': 1,
      'name': 'видео',
      'parent_id': null,
      'created_at': 100,
      'color': 'E91E63',
    });
    expect(restored.color, 'E91E63');

    // Без цвета — null (папки, созданные до обновления).
    const noColor = Folder(id: 2, name: 'звуки', createdAt: 100);
    expect(noColor.color, isNull);
  });

  test('FolderDao.setColor записывает цвет и сбрасывает его', () async {
    const dao = FolderDao();
    final id = await dao.insert(const Folder(
      id: 0,
      name: 'шрифты',
      createdAt: 0,
    ));

    await dao.setColor(id, '9C27B0');
    var folder = await dao.getById(id);
    expect(folder?.color, '9C27B0');

    // Перезапись другим цветом.
    await dao.setColor(id, '009688');
    folder = await dao.getById(id);
    expect(folder?.color, '009688');

    // Сброс на стандартный (null).
    await dao.setColor(id, null);
    folder = await dao.getById(id);
    expect(folder?.color, isNull);
  });

  test('Service.setFolderColor: полный цикл через сервис', () async {
    final id = await service.createFolder('часы');

    await service.setFolderColor(id, 'FF9800');
    var folders = await service.getFolders();
    expect(folders.firstWhere((f) => f.id == id).color, 'FF9800');

    await service.setFolderColor(id, null);
    folders = await service.getFolders();
    expect(folders.firstWhere((f) => f.id == id).color, isNull);
  });

  test('Цвет сохраняется после переименования папки', () async {
    const dao = FolderDao();
    final id = await dao.insert(const Folder(
      id: 0,
      name: 'архив',
      createdAt: 0,
    ));

    await dao.setColor(id, 'F44336');
    await dao.rename(id, 'архив 2026');

    final folder = await dao.getById(id);
    expect(folder?.name, 'архив 2026');
    expect(folder?.color, 'F44336');
  });
}
