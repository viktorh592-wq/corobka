import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:korobka/data/app_database.dart';
import 'package:korobka/data/models/item.dart';
import 'package:korobka/features/collection/collection_state.dart';

import 'app_database_test_helper.dart';

/// Тесты новых функций v0.3: дубликаты, видео/аудио, BPM-теги,
/// миграция БД v3, регистронезависимые теги.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String testDbPath;
  late Directory tmpDir;
  var counter = 0;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmpDir = Directory.systemTemp.createTempSync('korobka_v3_features');
    testDbPath = p.join(
      Directory.systemTemp.path,
      'korobka_v3_${DateTime.now().millisecondsSinceEpoch}.db',
    );
  });

  tearDownAll(() {
    tmpDir.deleteSync(recursive: true);
  });

  setUp(() async {
    AppDatabaseTest.setDatabasePath(testDbPath);
    final f = File(testDbPath);
    if (await f.exists()) {
      await f.delete();
    }
  });

  tearDown(() async {
    await AppDatabase.close();
  });

  /// Создание файла с уникальным содержимым (для контроля хэшей).
  Future<File> makeFile(String name, List<int> bytes) async {
    counter++;
    final file = File(p.join(tmpDir.path, '${counter}_$name'));
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<CollectionState> freshState() async {
    final state = CollectionState();
    await state.initialize();
    return state;
  }

  group('миграция БД v3', () {
    test('таблица items содержит колонки hash и bpm', () async {
      final db = await AppDatabase.instance();
      final cols = await db.rawQuery('PRAGMA table_info(items)');
      final names = cols.map((c) => c['name'] as String).toSet();
      expect(names, containsAll(['hash', 'bpm']));
    });
  });

  group('типы медиафайлов', () {
    test('видео и аудио распознаются по расширению', () {
      expect(
        CollectionItem.kindOfExtension('mp4'),
        ItemKind.video,
      );
      expect(CollectionItem.kindOfExtension('MKV'), ItemKind.video);
      expect(CollectionItem.kindOfExtension('mp3'), ItemKind.audio);
      expect(CollectionItem.kindOfExtension('flac'), ItemKind.audio);
      expect(CollectionItem.kindOfExtension('png'), ItemKind.image);
      expect(CollectionItem.kindOfExtension('jpg'), ItemKind.image);
    });

    test('импорт видео: kind=video, без палитры, с хэшем', () async {
      final state = await freshState();
      final file = await makeFile('clip.mp4', [1, 2, 3, 4, 5, 6, 7, 8]);
      final item = await state.collectionService.addItem(
        sourcePath: file.path,
      );

      expect(item.isVideo, isTrue, reason: 'видео должно распознаваться');
      expect(item.palette, isNull, reason: 'у видео нет палитры');
      expect(item.hash, isNotNull, reason: 'хэш нужен для дубликатов');
      expect(item.width, isNull, reason: 'размеры кадра не извлекаются');
      await AppDatabase.close();
    });

    test('импорт аудио: kind=audio', () async {
      final state = await freshState();
      final file = await makeFile('track.mp3', [9, 8, 7, 6, 5, 4]);
      final item = await state.collectionService.addItem(
        sourcePath: file.path,
      );
      expect(item.isAudio, isTrue);
      await AppDatabase.close();
    });
  });

  group('дубликаты', () {
    test('два одинаковых файла образуют группу, разные — нет', () async {
      final state = await freshState();

      final a1 = await makeFile('dup.png', List.filled(64, 1));
      final a2 = await makeFile('dup_copy.png', List.filled(64, 1));
      final b = await makeFile('uniq.png', List.filled(64, 2));

      final i1 = await state.collectionService.addItem(sourcePath: a1.path);
      final i2 = await state.collectionService.addItem(sourcePath: a2.path);
      final i3 = await state.collectionService.addItem(sourcePath: b.path);

      expect(i1.hash, isNotNull);
      expect(i1.hash, equals(i2.hash), reason: 'одинаковое содержимое');
      expect(i3.hash, isNot(equals(i1.hash)), reason: 'разное содержимое');

      final groups = await state.findDuplicates();
      expect(groups, hasLength(1));
      expect(groups.first, hasLength(2));
      expect(
        groups.first.map((e) => e.id).toSet(),
        {i1.id, i2.id},
      );
      await AppDatabase.close();
    });

    test('элемент в корзине не считается дубликатом', () async {
      final state = await freshState();

      final a1 = await makeFile('dup2.png', List.filled(32, 3));
      final a2 = await makeFile('dup2_copy.png', List.filled(32, 3));
      await state.collectionService.addItem(sourcePath: a1.path);
      final i2 =
          await state.collectionService.addItem(sourcePath: a2.path);

      await state.trashItem(i2);
      final groups = await state.findDuplicates();
      expect(groups, isEmpty);
      await AppDatabase.close();
    });
  });

  group('BPM-теги', () {
    test('установка BPM сохраняет значение и создаёт тег', () async {
      final state = await freshState();
      final file = await makeFile('song.mp3', List.filled(16, 5));
      final item = await state.collectionService.addItem(
        sourcePath: file.path,
      );
      await state.selectItem(item);

      await state.setSelectedItemBpm(128);

      expect(state.selectedItem?.bpm, 128);
      expect(
        state.selectedItemTags.map((t) => t.name),
        contains('BPM 128'),
        reason: 'BPM-тег должен привязаться автоматически',
      );
      expect(state.tags.map((t) => t.name), contains('BPM 128'));
      await AppDatabase.close();
    });

    test('смена BPM заменяет старый тег новым', () async {
      final state = await freshState();
      final file = await makeFile('song2.mp3', List.filled(16, 6));
      final item = await state.collectionService.addItem(
        sourcePath: file.path,
      );
      await state.selectItem(item);

      await state.setSelectedItemBpm(120);
      await state.setSelectedItemBpm(140);

      expect(state.selectedItem?.bpm, 140);
      expect(
        state.selectedItemTags.map((t) => t.name),
        contains('BPM 140'),
      );
      expect(
        state.selectedItemTags.map((t) => t.name),
        isNot(contains('BPM 120')),
        reason: 'старый BPM-тег должен быть снят',
      );
      await AppDatabase.close();
    });

    test('сброс BPM (null) снимает тег', () async {
      final state = await freshState();
      final file = await makeFile('song3.mp3', List.filled(16, 7));
      final item = await state.collectionService.addItem(
        sourcePath: file.path,
      );
      await state.selectItem(item);

      await state.setSelectedItemBpm(100);
      await state.setSelectedItemBpm(null);

      expect(state.selectedItem?.bpm, isNull);
      expect(state.selectedItemTags, isEmpty);
      await AppDatabase.close();
    });
  });

  group('теги', () {
    test('регистронезависимый поиск: «Природа» и «природа» — один тег',
        () async {
      final state = await freshState();
      final file = await makeFile('t.png', List.filled(8, 9));
      final item = await state.collectionService.addItem(
        sourcePath: file.path,
      );
      await state.selectItem(item);

      await state.addTagToSelectedItem('Природа');
      await state.addTagToSelectedItem('природа');

      expect(
        state.tags.where((t) => t.name.toLowerCase() == 'природа'),
        hasLength(1),
        reason: 'дубликаты тега с разным регистром недопустимы',
      );
      expect(state.selectedItemTags, hasLength(1));
      await AppDatabase.close();
    });

    test('счётчики тегов возвращают число связанных элементов', () async {
      final state = await freshState();

      final f1 = await makeFile('c1.png', List.filled(8, 11));
      final f2 = await makeFile('c2.png', List.filled(8, 12));
      final i1 = await state.collectionService.addItem(sourcePath: f1.path);
      final i2 = await state.collectionService.addItem(sourcePath: f2.path);

      await state.selectItem(i1);
      await state.addTagToSelectedItem('общий');
      await state.selectItem(i2);
      await state.addTagToSelectedItem('общий');

      expect(state.tagCounts[state.tags.first.id], 2);
      await AppDatabase.close();
    });
  });
}
