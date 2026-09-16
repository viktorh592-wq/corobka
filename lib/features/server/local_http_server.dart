import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../collection/collection_service.dart';

/// Локальный HTTP-сервер коллекции (аналог сервера Eagle для расширений
/// браузера и сторонних приложений).
///
/// Запускается на `127.0.0.1` (только локальная машина — извне недоступен)
/// и принимает JSON-запросы на добавление файлов в коллекцию, создание
/// папок и чтение состояния. Это позволяет внешним приложениям (расширение
/// браузера, скрипты, веб-интерфейс) отправлять изображения/видео/аудио
/// в «Коробку» одним кликом, без ручного импорта через диалог.
///
/// Протокол вдохновлён Eagle API:
/// * `GET  /api/health`            — статус сервера и приложения
/// * `GET  /api/folders`           — список папок коллекции
/// * `POST /api/folder/add`        — создать новую папку
/// * `POST /api/item/add`          — добавить один элемент (base64 или URL)
/// * `POST /api/items/add`         — добавить пакет элементов
/// * `POST /api/heartbeat`         — проверка живости (алиас /health)
///
/// Все ответы — JSON с CORS-заголовками (`Access-Control-Allow-Origin: *`),
/// чтобы запросы работали прямо из расширений браузера.
class LocalHttpServer {
  LocalHttpServer({
    required CollectionService collection,
    this.port = kDefaultPort,
    this.onItemAdded,
  }) : _collection = collection;

  /// Порт по умолчанию (как у Eagle — `57323`).
  static const int kDefaultPort = 57323;

  /// Сервис коллекции — используется для добавления элементов и папок.
  final CollectionService _collection;

  /// Слушаемый порт (можно переназначить перед [start]).
  final int port;

  /// Колбэк, вызываемый после успешного добавления элемента —
  /// CollectionState использует его для перезагрузки списка и обновления UI.
  final void Function(int? folderId)? onItemAdded;

  HttpServer? _server;
  bool _isRunning = false;

  /// Запущен ли сервер в данный момент.
  bool get isRunning => _isRunning;

  /// Текущий порт (можно вызвать после [start], чтобы узнать реальный порт
  /// — может отличаться, если передан `port = 0` для авто-выбора).
  int? get actualPort => _server?.port;

  /// Запуск сервера. Идемпотентен: повторный вызов ничего не делает.
  Future<void> start() async {
    if (_isRunning) return;
    try {
      _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      _isRunning = true;
      unawaited(_serveLoop());
      debugPrint('LocalHttpServer: listening on http://127.0.0.1:${_server!.port}');
    } catch (e, stack) {
      debugPrint('LocalHttpServer bind error: $e\n$stack');
      _isRunning = false;
      rethrow;
    }
  }

  /// Остановка сервера. Идемпотентен.
  Future<void> stop() async {
    final server = _server;
    _server = null;
    _isRunning = false;
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (e) {
        debugPrint('LocalHttpServer stop error: $e');
      }
    }
  }

  /// Основной цикл обработки запросов.
  Future<void> _serveLoop() async {
    final server = _server;
    if (server == null) return;
    try {
      await for (final request in server) {
        try {
          await _handle(request);
        } catch (e, stack) {
          debugPrint('LocalHttpServer handler error: $e\n$stack');
          _safeRespond(request, HttpStatus.internalServerError,
              body: {'error': 'internal_error', 'message': e.toString()});
        } finally {
          try {
            // Если тело запроса не было прочитано обработчиком — вычитываем его,
            // чтобы освободить соединение для следующих запросов (иначе клиент
            // мог бы зависнуть, ожидая подтверждения отправки тела).
            await request.drain<void>();
          } catch (_) {}
          try {
            await request.response.close();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('LocalHttpServer serve loop stopped: $e');
    }
  }

  Future<void> _handle(HttpRequest request) async {
    _addCorsHeaders(request.response);
    final path = request.uri.path;
    final method = request.method;

    // CORS preflight — отвечаем сразу, без тела.
    if (method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      return;
    }

    switch (path) {
      case '/':
      case '/api/health':
      case '/api/heartbeat':
        await _handleHealth(request);
        return;
      case '/api/folders':
        if (method == 'GET') {
          await _handleListFolders(request);
        } else {
          _methodNotAllowed(request);
        }
        return;
      case '/api/folder/add':
        if (method == 'POST') {
          await _handleAddFolder(request);
        } else {
          _methodNotAllowed(request);
        }
        return;
      case '/api/item/add':
        if (method == 'POST') {
          await _handleAddItem(request);
        } else {
          _methodNotAllowed(request);
        }
        return;
      case '/api/items/add':
        if (method == 'POST') {
          await _handleAddItems(request);
        } else {
          _methodNotAllowed(request);
        }
        return;
      default:
        _safeRespond(request, HttpStatus.notFound,
            body: {'error': 'not_found', 'path': path});
    }
  }

  /// `GET /api/health` — статус сервера и приложения.
  Future<void> _handleHealth(HttpRequest request) async {
    _safeRespond(request, HttpStatus.ok, body: {
      'status': 'ok',
      'app': 'korobka',
      'version': '0.3.0',
      'port': _server?.port,
      'rootPath': _collection.rootPath,
      'imagesPath': _collection.imagesPath,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// `GET /api/folders` — список папок коллекции.
  Future<void> _handleListFolders(HttpRequest request) async {
    final folders = await _collection.getFolders();
    final result = folders
        .map((f) => {
              'id': f.id,
              'name': f.name,
              'parentId': f.parentId,
              'color': f.color,
              'createdAt': f.createdAt,
            })
        .toList();
    _safeRespond(request, HttpStatus.ok, body: {'folders': result});
  }

  /// `POST /api/folder/add` — создать новую папку.
  ///
  /// Тело: `{ "name": "Foo", "parentId": 12 }` (parentId опционален —
  /// корневая папка).
  Future<void> _handleAddFolder(HttpRequest request) async {
    final body = await _readJson(request);
    final name = (body['name'] ?? '').toString().trim();
    if (name.isEmpty) {
      _safeRespond(request, HttpStatus.badRequest,
          body: {'error': 'bad_request', 'message': 'name is required'});
      return;
    }
    final parentIdRaw = body['parentId'];
    final parentId =
        parentIdRaw == null ? null : int.tryParse(parentIdRaw.toString());
    final id = await _collection.createFolder(name, parentId: parentId);
    _safeRespond(request, HttpStatus.ok, body: {
      'status': 'ok',
      'id': id,
      'name': name,
      'parentId': parentId,
    });
  }

  /// `POST /api/item/add` — добавить один элемент в коллекцию.
  ///
  /// Тело (JSON):
  /// ```
  /// {
  ///   "name":     "image.png",        // имя файла (опц., по умолчанию из url)
  ///   "base64":   "<data>",           // содержимое файла в base64 (обязательно
  ///                                  //   если нет `url`)
  ///   "url":      "https://...",      // ИЛИ http(s)-URL для скачивания
  ///   "folderId": 12,                 // опционально, иначе корень
  ///   "tags":     ["foo", "bar"]      // опционально, имена тегов
  /// }
  /// ```
  Future<void> _handleAddItem(HttpRequest request) async {
    final body = await _readJson(request);
    final result = await _importOne(body);
    if (result.error != null) {
      _safeRespond(request, result.status, body: {
        'error': result.error,
        'message': result.message,
      });
      return;
    }
    final folderId = result.folderId;
    if (onItemAdded != null) onItemAdded!(folderId);
    _safeRespond(request, HttpStatus.ok, body: {
      'status': 'ok',
      'id': result.id,
      'title': result.title,
      'path': result.path,
      'folderId': folderId,
    });
  }

  /// `POST /api/items/add` — добавить пакет элементов.
  ///
  /// Тело: `{ "items": [ { ...один элемент... }, ... ] }`.
  /// Возвращает массив результатов по каждому элементу.
  Future<void> _handleAddItems(HttpRequest request) async {
    final body = await _readJson(request);
    final rawItems = body['items'];
    if (rawItems is! List) {
      _safeRespond(request, HttpStatus.badRequest, body: {
        'error': 'bad_request',
        'message': 'items must be an array',
      });
      return;
    }
    final results = <Map<String, dynamic>>[];
    int? lastFolderId;
    var okCount = 0;
    for (final entry in rawItems) {
      if (entry is! Map) {
        results.add({
          'status': 'error',
          'error': 'bad_request',
          'message': 'item must be an object',
        });
        continue;
      }
      final r = await _importOne(entry);
      if (r.error != null) {
        results.add({
          'status': 'error',
          'error': r.error,
          'message': r.message,
        });
        continue;
      }
      okCount++;
      lastFolderId = r.folderId;
      results.add({
        'status': 'ok',
        'id': r.id,
        'title': r.title,
        'path': r.path,
        'folderId': r.folderId,
      });
    }
    if (okCount > 0 && onItemAdded != null && lastFolderId != null) {
      onItemAdded!(lastFolderId);
    }
    _safeRespond(request, HttpStatus.ok, body: {
      'status': okCount > 0 ? 'ok' : 'error',
      'added': okCount,
      'total': rawItems.length,
      'results': results,
    });
  }

  Future<_ImportResult> _importOne(Map<dynamic, dynamic> body) async {
    final folderIdRaw = body['folderId'];
    final folderId =
        folderIdRaw == null ? null : int.tryParse(folderIdRaw.toString());

    final name = (body['name'] ?? '').toString().trim();
    final base64Data = (body['base64'] ?? '').toString().trim();
    final url = (body['url'] ?? '').toString().trim();
    final tags = body['tags'];

    File? tempFile;
    try {
      if (base64Data.isNotEmpty) {
        tempFile = await _saveBase64(base64Data, name);
      } else if (url.isNotEmpty) {
        tempFile = await _downloadToTemp(url, name);
      } else {
        return _ImportResult(
          status: HttpStatus.badRequest,
          error: 'bad_request',
          message: 'either `base64` or `url` is required',
        );
      }

      final item = await _collection.addItem(
        sourcePath: tempFile.path,
        folderId: folderId,
      );

      // Теги опциональны — ошибки их добавления не роняют импорт.
      if (tags is List) {
        for (final tag in tags) {
          final tagName = tag.toString().trim();
          if (tagName.isEmpty) continue;
          try {
            await _collection.addTagToItem(item.id, tagName);
          } catch (e) {
            debugPrint('LocalHttpServer: addTagToItem failed: $e');
          }
        }
      }

      return _ImportResult(
        status: HttpStatus.ok,
        id: item.id,
        title: item.title,
        path: item.path,
        folderId: folderId,
      );
    } catch (e, stack) {
      debugPrint('LocalHttpServer import failed: $e\n$stack');
      return _ImportResult(
        status: HttpStatus.internalServerError,
        error: 'import_failed',
        message: e.toString(),
      );
    } finally {
      // Временный файл больше не нужен — CollectionService уже скопировал
      // его в каталог коллекции.
      if (tempFile != null) {
        try {
          if (await tempFile.exists()) await tempFile.delete();
        } catch (_) {}
      }
    }
  }

  /// Декодирует base64 в байты и сохраняет во временный файл. Имя берётся
  /// из [name] или генерируется по timestamp.
  Future<File> _saveBase64(String base64Data, String name) async {
    // Поддержка Data URL: `data:image/png;base64,iVBORw0...`
    final dataUriMatch = RegExp(
      r'^data:([a-zA-Z0-9./-]+);base64,(.+)$',
    ).firstMatch(base64Data);
    String mime = 'application/octet-stream';
    String payload = base64Data;
    if (dataUriMatch != null) {
      mime = dataUriMatch.group(1) ?? mime;
      payload = dataUriMatch.group(2)!;
    }
    final bytes = base64.decode(payload);
    final ext = _extensionFor(name, mime);
    final fileName = name.isNotEmpty
        ? _sanitizeFileName(name, ext)
        : 'korobka_$timestamp$ext';
    final tempDir = await _tempDir();
    final file = File('${tempDir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Скачивает URL во временный файл (используется HttpClient — без доп. зав-стей).
  Future<File> _downloadToTemp(String url, String name) async {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      throw ArgumentError('url must be http(s)://... — got: $url');
    }
    final uri = Uri.parse(url);
    final client = HttpClient();
    client.userAgent = 'Korobka/0.3 (local http server)';
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode} for $url');
      }
      final mime = response.headers.contentType?.mimeType ??
          'application/octet-stream';
      final ext = _extensionFor(name, mime);
      final fileName = name.isNotEmpty
          ? _sanitizeFileName(name, ext)
          : (uri.pathSegments.isNotEmpty && uri.pathSegments.last.isNotEmpty
              ? _sanitizeFileName(uri.pathSegments.last, ext)
              : 'korobka_$timestamp$ext');
      final tempDir = await _tempDir();
      final file = File('${tempDir.path}${Platform.pathSeparator}$fileName');
      final sink = file.openWrite();
      try {
        await response.pipe(sink);
      } catch (e) {
        try {
          await sink.close();
        } catch (_) {}
        rethrow;
      }
      return file;
    } finally {
      client.close(force: true);
    }
  }

  String get timestamp =>
      DateTime.now().millisecondsSinceEpoch.toString();

  Future<Directory> _tempDir() async {
    final dir = Directory.systemTemp;
    final korobkaDir =
        Directory('${dir.path}${Platform.pathSeparator}korobka_inbox');
    if (!await korobkaDir.exists()) {
      await korobkaDir.create(recursive: true);
    }
    return korobkaDir;
  }

  /// Расширение для сохраняемого файла: либо берётся из имени, либо выводится
  /// из MIME-типа.
  String _extensionFor(String name, String mime) {
    final dotIdx = name.lastIndexOf('.');
    if (dotIdx >= 0 && dotIdx < name.length - 1) {
      return name.substring(dotIdx).toLowerCase();
    }
    switch (mime.toLowerCase()) {
      case 'image/jpeg':
      case 'image/jpg':
        return '.jpg';
      case 'image/png':
        return '.png';
      case 'image/gif':
        return '.gif';
      case 'image/webp':
        return '.webp';
      case 'image/bmp':
        return '.bmp';
      case 'image/svg+xml':
        return '.svg';
      case 'image/avif':
        return '.avif';
      case 'image/x-icon':
        return '.ico';
      case 'video/mp4':
        return '.mp4';
      case 'video/quicktime':
        return '.mov';
      case 'video/x-msvideo':
        return '.avi';
      case 'video/x-matroska':
        return '.mkv';
      case 'video/webm':
        return '.webm';
      case 'audio/mpeg':
        return '.mp3';
      case 'audio/wav':
      case 'audio/x-wav':
        return '.wav';
      case 'audio/flac':
        return '.flac';
      case 'audio/ogg':
        return '.ogg';
      case 'audio/aac':
        return '.aac';
      default:
        return '';
    }
  }

  /// Убирает опасные символы из имени файла и гарантирует расширение.
  String _sanitizeFileName(String name, String expectedExt) {
    final cleaned = name.replaceAll(
      RegExp(r'[/\\:*?"<>|]'),
      '_',
    );
    var result = cleaned;
    if (expectedExt.isNotEmpty &&
        !result.toLowerCase().endsWith(expectedExt.toLowerCase())) {
      result = '$result$expectedExt';
    }
    return result;
  }

  /// Чтение JSON-тела запроса.
  Future<Map<dynamic, dynamic>> _readJson(HttpRequest request) async {
    final contentType = request.headers.contentType?.mimeType ?? '';
    if (contentType.isNotEmpty &&
        contentType != 'application/json' &&
        contentType != 'text/plain') {
      throw HttpException('unsupported content type: $contentType');
    }
    final bytes = await _collectBody(request);
    if (bytes.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('expected JSON object');
    }
    return decoded;
  }

  Future<List<int>> _collectBody(HttpRequest request) async {
    final builder = BytesBuilder();
    await for (final chunk in request) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  void _addCorsHeaders(HttpResponse response) {
    response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..set('Access-Control-Allow-Headers',
          'Content-Type, Authorization, X-Requested-With')
      ..set('Access-Control-Max-Age', '86400');
  }

  void _methodNotAllowed(HttpRequest request) {
    _safeRespond(request, HttpStatus.methodNotAllowed, body: {
      'error': 'method_not_allowed',
      'method': request.method,
      'path': request.uri.path,
    });
  }

  void _safeRespond(HttpRequest request, int status,
      {required Map<String, dynamic> body}) {
    try {
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json;
      request.response.write(jsonEncode(body));
    } catch (e) {
      debugPrint('LocalHttpServer respond error: $e');
    }
  }
}

/// Внутренний результат импорта одного элемента.
class _ImportResult {
  _ImportResult({
    required this.status,
    this.id,
    this.title,
    this.path,
    this.folderId,
    this.error,
    this.message,
  });

  final int status;
  final int? id;
  final String? title;
  final String? path;
  final int? folderId;
  final String? error;
  final String? message;
}
