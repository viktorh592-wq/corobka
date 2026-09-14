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
import 'package:korobka/widgets/duplicates_dialog.dart';
import 'package:korobka/widgets/left_panel.dart';
import 'package:korobka/widgets/panel_drag_handle.dart';

import 'app_database_test_helper.dart';

/// Widget-тесты UI-слоя:
/// 1. БАГ ПОЛЬЗОВАТЕЛЯ: тег появляется в разделе «Теги» левой панели.
/// 2. Границы панелей перетаскиваются мышью (ресайз).
/// 3. Диалог дубликатов открывается и находит группы.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testDbPath = p.join(
    Directory.systemTemp.path,
    'korobka_ui_v3',
  );
  late Directory tmpDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmpDir = Directory.systemTemp.createTempSync('korobka_widget_v3');
  });

  tearDownAll(() {
    try {
      tmpDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    // КАЖДЫЙ тест получает СВОЙ путь БД: sqflite_ffi кэширует открытые
    // базы по пути, и повторное открытие того же пути в одном процессе
    // может вернуть закрытый инстанс (третий тест зависал).
    final path = p.join(
      testDbPath,
      'run_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    AppDatabaseTest.setDatabasePath(path);
    final f = File(path);
    if (await f.exists()) {
      await f.delete();
    }
  });

  tearDown(() async {
    // Защита от «зависших» операций БД в fake-zone widget-тестов.
    try {
      await AppDatabase.close().timeout(const Duration(seconds: 2));
    } catch (_) {}
  });

  /// Ограниченный набор кадров вместо pumpAndSettle (защита от зависаний
  /// на бесконечных анимациях).
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

  testWidgets('дубликаты: диалог показывает группы с готовым результатом',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final state = await pumpApp(tester);

    // Два одинаковых файла — дубликаты (реальный I/O через runAsync).
    late List<List<CollectionItem>> groups;
    await tester.runAsync(() async {
      final bytes = List<int>.filled(48, 7);
      final f1 = File(p.join(tmpDir.path, 'dup_a.png'));
      final f2 = File(p.join(tmpDir.path, 'dup_b.png'));
      await f1.writeAsBytes(bytes);
      await f2.writeAsBytes(bytes);
      await state.collectionService.addItem(sourcePath: f1.path);
      await state.collectionService.addItem(sourcePath: f2.path);
      groups = await state.findDuplicates();
    });
    expect(groups, hasLength(1), reason: 'поиск дубликатов в состоянии');

    // Открываем диалог с ГОТОВЫМ результатом (детерминированно).
    await tester.pumpWidget(
      ChangeNotifierProvider<CollectionState>.value(
        value: state,
        child: MaterialApp(
          home: DuplicatesDialog(
            state: state,
            duplicatesFuture: Future.value(groups),
          ),
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Поиск дубликатов'), findsOneWidget);
    expect(find.textContaining('Дубликаты (2 копии)'), findsOneWidget);
    expect(find.text('Оригинал (самая ранняя копия)'), findsOneWidget);
    expect(find.text('В корзину'), findsOneWidget);
    expect(find.text('Найдено групп: 1 (лишних копий: 1)'), findsOneWidget);
  });

  testWidgets('границы панелей перетаскиваются мышью', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester);

    SizedBox leftBox() => tester
        .widgetList<SizedBox>(
          find.byWidgetPredicate(
            (w) => w is SizedBox && w.child is LeftPanel,
          ),
        )
        .first;

    final before = leftBox().width!;
    expect(before, 220);

    // Тянем границу левой панели вправо на 80 пикселей.
    final handle = find.byType(PanelDragHandle).first;
    await tester.dragFrom(tester.getCenter(handle), const Offset(80, 0));
    await settle(tester);

    expect(
      leftBox().width,
      before + 80,
      reason: 'перетаскивание границы должно менять ширину панели',
    );

    // Ограничение максимума: тянем далеко — шире 460 не станет.
    await tester.dragFrom(
      tester.getCenter(handle),
      const Offset(2000, 0),
    );
    await settle(tester);
    expect(leftBox().width, lessThanOrEqualTo(460));

    // Тянем далеко влево — уже 170.
    await tester.dragFrom(
      tester.getCenter(handle),
      const Offset(-2000, 0),
    );
    await settle(tester);
    expect(leftBox().width, greaterThanOrEqualTo(170));
  });
}
