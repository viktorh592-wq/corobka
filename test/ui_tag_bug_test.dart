import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:korobka/data/app_database.dart';
import 'package:korobka/data/models/item.dart';
import 'package:korobka/features/collection/collection_state.dart';
import 'package:korobka/screens/main_screen.dart';
import 'package:korobka/widgets/left_panel.dart';

import 'app_database_test_helper.dart';

/// Widget-тест бага пользователя: тег, добавленный картинке, появляется
/// в разделе «Теги» левой панели. Вынесен в отдельный файл: widget-тесты
/// в одном изоляте интерферируют через глобальный движок sqflite.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;
  var run = 0;
  late String dbPath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmpDir = Directory.systemTemp.createTempSync('korobka_tag_widget');
    dbPath = p.join(
      Directory.systemTemp.path,
      'korobka_tag_w_${DateTime.now().millisecondsSinceEpoch}.db',
    );
  });

  tearDownAll(() {
    try {
      tmpDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    run++;
    final path = '${dbPath}_run$run.db';
    AppDatabaseTest.setDatabasePath(path);
    final f = File(path);
    if (await f.exists()) {
      await f.delete();
    }
  });

  tearDown(() async {
    try {
      await AppDatabase.close().timeout(const Duration(seconds: 2));
    } catch (_) {}
  });

  const png1x1 = [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0x00,
    0x01,
    0x00,
    0x00,
    0x05,
    0x00,
    0x01,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ];

  /// Ограниченный набор кадров вместо pumpAndSettle.
  Future<void> settle(WidgetTester tester, {int frames = 8}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<CollectionState> pumpApp(WidgetTester tester) async {
    final state = CollectionState();
    // initialize выполняет реальные обращения к плагинам/БД — runAsync.
    await tester.runAsync(state.initialize);
    await tester.pumpWidget(
      ChangeNotifierProvider<CollectionState>.value(
        value: state,
        child: const MaterialApp(home: MainScreen()),
      ),
    );
    await settle(tester);
    return state;
  }

  /// Импорт файла и выбор элемента — реальный I/O через runAsync.
  Future<CollectionItem> importAndSelect(
    WidgetTester tester,
    CollectionState state,
    String name,
    List<int> bytes,
  ) async {
    late CollectionItem item;
    await tester.runAsync(() async {
      final img = File(p.join(tmpDir.path, name));
      await img.writeAsBytes(bytes);
      item = await state.collectionService.addItem(sourcePath: img.path);
      await state.selectItem(item);
    });
    await settle(tester);
    return item;
  }

  testWidgets(
    'БАГ: после добавления тега он появляется в разделе «Теги» левой панели',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final state = await pumpApp(tester);
      await importAndSelect(tester, state, 'widget_pic.png', png1x1);

      // Раскрываем раздел «Теги» именно ЛЕВОЙ панели (ListTile с текстом).
      await tester.tap(find.widgetWithText(ListTile, 'Теги').first);
      await settle(tester);
      expect(find.text('Нет тегов'), findsOneWidget);

      // Добавляем тег через логику состояния (runAsync — реальные
      // операции БД; widget-контекст тот же провайдер).
      await tester.runAsync(() => state.addTagToSelectedItem('пейзаж'));
      await settle(tester);

      // Диагностика.
      // ignore: avoid_print
      print('DEBUG state.tags: ${state.tags.map((t) => t.name)}');

      // Тег появился в разделе «Теги» ЛЕВОЙ панели (это и был баг).
      expect(
        find.descendant(
          of: find.byType(LeftPanel),
          matching: find.text('пейзаж'),
        ),
        findsOneWidget,
        reason: 'тег должен появиться в левой панели',
      );

      // Второй тег — через кнопку подтверждения в правой панели (UI-путь).
      // Нажатие кнопки синхронно очищает поле (_submit → отправка тега);
      // сама запись в БД покрыта state-тестами (в fake-zone widget-тестов
      // реальные фьючерсы БД не завершаются — среда, не продукт).
      final tagField =
          find.widgetWithText(TextField, 'Добавить тег (Enter или кнопка)');
      await tester.enterText(tagField, 'море');
      await settle(tester, frames: 2);
      await tester.tap(find.byTooltip('Добавить тег'));
      await settle(tester, frames: 2);

      final field = tester.widget<TextField>(tagField);
      expect(
        field.controller!.text,
        isEmpty,
        reason: 'кнопка «Добавить тег» отправляет тег и очищает поле',
      );
    },
  );
}
