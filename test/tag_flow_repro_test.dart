import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:korobka/data/app_database.dart';
import 'package:korobka/features/collection/collection_state.dart';

import 'app_database_test_helper.dart';

/// Воспроизведение и регрессия бага: после добавления тега элементу тег
/// должен появляться в разделе «Теги» левой панели (state.tags).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String testDbPath;
  late Directory tmpDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmpDir = Directory.systemTemp.createTempSync('korobka_tag_repro');
    testDbPath = p.join(
      Directory.systemTemp.path,
      'korobka_tag_repro_${DateTime.now().millisecondsSinceEpoch}.db',
    );
  });

  tearDownAll(() {
    try {
      tmpDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    AppDatabaseTest.setDatabasePath(testDbPath);
    final f = File(testDbPath);
    if (await f.exists()) {
      await f.delete();
    }
  });

  tearDown(() async {
    try {
      await AppDatabase.close().timeout(const Duration(seconds: 2));
    } catch (_) {}
  });

  test('addTagToSelectedItem обновляет state.tags (левая панель)', () async {
    final state = CollectionState();
    await state.initialize();

    // Создаём реальный файл-картинку для импорта.
    final img = File(p.join(tmpDir.path, 'pic.png'));
    img.writeAsBytesSync(_png1x1);

    final service = state.collectionService;
    final item = await service.addItem(sourcePath: img.path);

    await state.selectItem(item);
    expect(state.selectedItem, isNotNull);
    expect(state.tags, isEmpty, reason: 'Изначально тегов нет');

    await state.addTagToSelectedItem('природа');

    expect(state.selectedItemTags.map((t) => t.name), contains('природа'),
        reason: 'Чип тега в правой панели');
    expect(state.tags.map((t) => t.name), contains('природа'),
        reason: 'ТЕГ ДОЛЖЕН ПОЯВИТЬСЯ В ЛЕВОЙ ПАНЕЛИ (state.tags)');

    await AppDatabase.close();
  });

  test('повторное добавление того же тега не падает и не дублируется',
      () async {
    final state = CollectionState();
    await state.initialize();

    final img = File(p.join(tmpDir.path, 'pic2.png'));
    img.writeAsBytesSync(_png1x1);
    final item = await state.collectionService.addItem(sourcePath: img.path);
    await state.selectItem(item);

    await state.addTagToSelectedItem('тег1');
    await state.addTagToSelectedItem('тег1');

    expect(state.tags.where((t) => t.name == 'тег1'), hasLength(1));
    expect(state.selectedItemTags, hasLength(1));

    await AppDatabase.close();
  });
}

const _png1x1 = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];
