import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:korobka/data/app_database.dart';
import 'package:korobka/features/collection/collection_service.dart';
import 'package:korobka/features/server/local_http_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // TestWidgetsFlutterBinding устанавливает глобальный HttpOverrides, который
  // подменяет HttpClient фейком — все HTTP-запросы возвращают 400 и не доходят
  // до сети. Для тестов локального HTTP-сервера нужен НАСТОЯЩИЙ HttpClient,
  // поэтому сбрасываем глобальный override в null. sqflite_common_ffi и
  // palette_generator (через compute+изолят) работают и без HttpOverrides.
  HttpOverrides.global = null;

  late CollectionService service;
  late String dbPath;
  late String rootPath;
  late LocalHttpServer server;
  late Uri baseUri;
  HttpClient? client;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Уникальный путь для БД И корня коллекции на каждый тест, чтобы
    // файлы не накапливались и не было коллизий имён (addItem переименует
    // файл при совпадении: pixel.png → pixel_1.png, что ломает ассерты).
    final unique = DateTime.now().microsecondsSinceEpoch;
    dbPath = '${Directory.systemTemp.path}/korobka_http_test_$unique.db';
    rootPath = '${Directory.systemTemp.path}/korobka_http_test_$unique';
    await Directory(rootPath).create(recursive: true);
    AppDatabase.overridePath = dbPath;
    await AppDatabase.close();

    service = CollectionService();
    await service.initializeRoot(customPath: rootPath);

    // port = 0 — ОС сама выделит свободный порт, чтобы тесты не падали
    // при конфликте с занятым 57323 (например, запущенным приложением).
    server = LocalHttpServer(
      collection: service,
      port: 0,
      onItemAdded: (_) {},
    );
    await server.start();
    final port = server.actualPort!;
    baseUri = Uri.http('127.0.0.1:$port', '');
    client = HttpClient();
    client!.connectionTimeout = const Duration(seconds: 5);
  });

  tearDown(() async {
    await server.stop();
    client?.close(force: true);
    await AppDatabase.close();
    final file = File(dbPath);
    if (await file.exists()) {
      await file.delete();
    }
    // Удаляем весь каталог коллекции вместе с images/.thumbs — иначе файлы
    // накапливаются и следующий прогон начинает тратить место в /tmp.
    final rootDir = Directory(rootPath);
    if (await rootDir.exists()) {
      try {
        await rootDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final uri = baseUri.replace(path: path);
    final req = await client!.postUrl(uri);
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final resp = await req.close();
    final bytes = await resp.fold<List<int>>(
      <int>[],
      (prev, chunk) => prev..addAll(chunk),
    );
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(resp.statusCode, HttpStatus.ok, reason: 'POST $path failed: $json');
    return json;
  }

  Future<Map<String, dynamic>> get(String path) async {
    final uri = baseUri.replace(path: path);
    final req = await client!.getUrl(uri);
    final resp = await req.close();
    final bytes = await resp.fold<List<int>>(
      <int>[],
      (prev, chunk) => prev..addAll(chunk),
    );
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(resp.statusCode, HttpStatus.ok, reason: 'GET $path failed: $json');
    return json;
  }

  Future<int> optionsMethod(String path) async {
    final uri = baseUri.replace(path: path);
    final req = await client!.openUrl('OPTIONS', uri);
    final resp = await req.close();
    // Вычитываем тело (пустое), чтобы соединение закрылось корректно.
    await resp.drain<void>();
    return resp.statusCode;
  }

  Future<int> getNotFoundStatus(String path) async {
    final uri = baseUri.replace(path: path);
    final req = await client!.getUrl(uri);
    final resp = await req.close();
    await resp.drain<void>();
    return resp.statusCode;
  }

  Future<int> postExpectingError(String path, Map<String, dynamic> body) async {
    final uri = baseUri.replace(path: path);
    final req = await client!.postUrl(uri);
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final resp = await req.close();
    await resp.drain<void>();
    return resp.statusCode;
  }

  test('GET /api/health возвращает статус и версию', () async {
    final health = await get('/api/health');
    expect(health['status'], 'ok');
    expect(health['app'], 'korobka');
    expect(health['version'], isNotEmpty);
    expect(health['port'], server.actualPort);
  });

  test('GET /api/folders возвращает пустой список на старте', () async {
    final result = await get('/api/folders');
    expect(result['folders'], isEmpty);
  });

  test('POST /api/folder/add создаёт папку', () async {
    final resp = await post('/api/folder/add', {'name': 'Скриншоты'});
    expect(resp['status'], 'ok');
    expect(resp['id'], greaterThan(0));
    expect(resp['name'], 'Скриншоты');

    final list = await get('/api/folders');
    expect(list['folders'], hasLength(1));
    expect((list['folders'] as List).first['name'], 'Скриншоты');
  });

  test('POST /api/item/add с base64 импортирует файл в коллекцию', () async {
    // Минимальный валидный PNG 1×1, прозрачный.
    const pngBase64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M8AAAMBAQDJ/pLvAAAAAElFTkSuQmCC';
    final resp = await post('/api/item/add', {
      'name': 'pixel.png',
      'base64': pngBase64,
    });
    expect(resp['status'], 'ok');
    expect(resp['id'], greaterThan(0));
    expect(resp['title'], 'pixel.png');
    expect(resp['path'], isNotEmpty);

    // Файл действительно лежит в каталоге коллекции.
    final file = File(resp['path'] as String);
    expect(await file.exists(), isTrue);

    // Импортированный элемент виден через CollectionService.
    final items = await service.getItems();
    expect(items, hasLength(1));
    expect(items.first.id, resp['id']);
  });

  test('POST /api/item/add с data: URL также импортирует файл', () async {
    const pngBase64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M8AAAMBAQDJ/pLvAAAAAElFTkSuQmCC';
    final resp = await post('/api/item/add', {
      'name': 'pixel.png',
      'base64': 'data:image/png;base64,$pngBase64',
    });
    expect(resp['status'], 'ok');
    expect(resp['id'], greaterThan(0));
  });

  test('POST /api/item/add с tags привязывает теги к элементу', () async {
    const pngBase64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M8AAAMBAQDJ/pLvAAAAAElFTkSuQmCC';
    final resp = await post('/api/item/add', {
      'name': 'pixel.png',
      'base64': pngBase64,
      'tags': ['foo', 'bar'],
    });
    final id = resp['id'] as int;
    final tags = await service.getTagsForItem(id);
    final names = tags.map((t) => t.name).toSet();
    expect(names, containsAll(<String>{'foo', 'bar'}));
  });

  test('POST /api/item/add с folderId кладёт файл в указанную папку', () async {
    final folderResp = await post('/api/folder/add', {'name': 'Проект'});
    final folderId = folderResp['id'] as int;

    const pngBase64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M8AAAMBAQDJ/pLvAAAAAElFTkSuQmCC';
    final resp = await post('/api/item/add', {
      'name': 'pixel.png',
      'base64': pngBase64,
      'folderId': folderId,
    });
    expect(resp['folderId'], folderId);

    final items = await service.getItems(folderId: folderId);
    expect(items, hasLength(1));
    expect(items.first.id, resp['id']);
  });

  test('POST /api/item/add без base64 и url возвращает 400', () async {
    final status = await postExpectingError('/api/item/add', {'name': 'no-data'});
    expect(status, HttpStatus.badRequest);
  });

  test('POST /api/items/add импортирует пакет элементов', () async {
    const pngBase64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M8AAAMBAQDJ/pLvAAAAAElFTkSuQmCC';
    final resp = await post('/api/items/add', {
      'items': [
        {'name': 'a.png', 'base64': pngBase64},
        {'name': 'b.png', 'base64': pngBase64},
      ],
    });
    expect(resp['status'], 'ok');
    expect(resp['added'], 2);
    expect(resp['total'], 2);
    expect(resp['results'], hasLength(2));

    final items = await service.getItems();
    expect(items, hasLength(2));
  });

  test('CORS preflight (OPTIONS) возвращает 204', () async {
    final status = await optionsMethod('/api/health');
    expect(status, HttpStatus.noContent);
  });

  test('Неизвестный путь возвращает 404', () async {
    final status = await getNotFoundStatus('/api/unknown');
    expect(status, HttpStatus.notFound);
  });
}

