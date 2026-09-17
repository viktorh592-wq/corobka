import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:korobka/data/app_database.dart';
import 'package:korobka/features/collection/collection_state.dart';
import 'package:korobka/features/logging/log_service.dart';
import 'package:korobka/features/server/local_api_server.dart';

/// Интеграционные тесты локального HTTP-сервера интеграции
/// «приложение ↔ расширение браузера».
///
/// Проверяются живые HTTP-запросы (HttpClient) к поднятому серверу:
///  - GET /api/ping — приложение отвечает;
///  - GET /api/folder/list — список папок в формате Eagle API;
///  - POST /api/log — строки журнала плагина попадают в LogService.
///
/// ВАЖНО: тест сознательно НЕ вызывает
/// TestWidgetsFlutterBinding.ensureInitialized() — биндинг flutter_test
/// подменяет HttpClient моком (всегда 400). Все используемые здесь
/// зависимости чисто dart'овские (sqflite_common_ffi, dart:io), поэтому
/// биндинг не нужен, а HttpClient остаётся настоящим.
void main() {
  late CollectionState state;
  late int port;
  late String dbPath;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dbPath = '${Directory.systemTemp.path}/korobka_api_test_'
        '${DateTime.now().microsecondsSinceEpoch}.db';
    AppDatabase.overridePath = dbPath;
    await AppDatabase.close();

    state = CollectionState();
    await state.initialize();

    final started = await LocalApiServer.startFor(state);
    expect(started, isNotNull, reason: 'сервер должен подняться на тестовом стенде');
    port = started!;
  });

  tearDown(() async {
    await AppDatabase.close();
    final file = File(dbPath);
    if (await file.exists()) {
      await file.delete();
    }
  });

  /// Реальный HTTP-запрос к серверу.
  Future<Map<String, dynamic>> request(
    String method,
    String path,
    String? body,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        method,
        Uri.parse('http://127.0.0.1:$port$path'),
      );
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(body);
      }
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      return <String, dynamic>{
        'statusCode': response.statusCode,
        'body': responseBody.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(responseBody) as Map<String, dynamic>,
      };
    } finally {
      client.close(force: true);
    }
  }

  test('GET /api/ping отвечает данными приложения', () async {
    final result = await request('GET', '/api/ping', null);
    expect(result['statusCode'], HttpStatus.ok);
    expect((result['body']['data'] as Map)['name'], 'korobka');
  });

  test('GET /api/folder/list отдаёт папки коллекции', () async {
    // Создаём две папки через тот же сервис, что слушает сервер.
    await state.collectionService.createFolder('Проекты');
    await state.collectionService.createFolder('Скриншоты');

    final result = await request('GET', '/api/folder/list', null);
    expect(result['statusCode'], HttpStatus.ok);
    expect(result['body']['status'], 'success');

    final data = (result['body']['data'] as List).cast<Map>();
    final names = data.map((f) => f['name']).toList();
    expect(names, contains('Проекты'));
    expect(names, contains('Скриншоты'));
    // В формате Eagle у папки должен быть числовой id.
    for (final folder in data) {
      expect(folder['id'], isA<int>());
      expect(folder['name'], isA<String>());
    }
  });

  test('POST /api/log пишет строку плагина в журнал', () async {
    await LogService.instance.start();
    addTearDown(() => LogService.instance.stop());

    final result = await request(
      'POST',
      '/api/log',
      jsonEncode({
        'level': 'INFO',
        'descriptor': '[content] drag-save started',
        'data': {'page': 'https://example.com'},
      }),
    );
    expect(result['statusCode'], HttpStatus.ok);
    expect(result['body']['status'], 'success');

    // Строка с меткой [plugin] должна появиться в буфере журнала.
    final lines = LogService.instance.lines;
    expect(
      lines.any((l) => l.contains('[plugin]') && l.contains('drag-save started')),
      isTrue,
      reason: 'лог плагина должен попасть в общий журнал',
    );
  });

  test('Неизвестный путь отдаёт 404', () async {
    final result = await request('GET', '/api/unknown', null);
    expect(result['statusCode'], HttpStatus.notFound);
  });
}
