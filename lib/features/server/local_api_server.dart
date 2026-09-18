import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/models/folder.dart';
import '../collection/collection_state.dart';
import '../logging/log_service.dart';

/// Локальный HTTP-сервер интеграции «приложение ↔ расширение браузера».
///
/// Слушает только 127.0.0.1. Расширение «Коробка» обращается к нему:
///  - GET  /api/ping          — проверка, что приложение запущено;
///  - GET  /api/folder/list   — список папок коллекции (для окна
///    перетаскивания плагина; формат совместим с Eagle API);
///  - POST /api/log           — приём строк журнала плагина
///    (пишутся в общий лог через LogService).
///
/// Порт: 41595 (как у Eagle), если занят — 41596, затем 41597.
/// Расширение перебирает эти же порты, поэтому связка работает всегда.
///
/// Дополнительные команды (добавлены в v0.4.0 по запросу — раньше кнопки
/// расширения «создать папку» и «сохранить изображение» получали 404):
///  - POST /api/folder/create — создание папки {name, parentId?};
///  - POST /api/item/add      — сохранение картинки в коллекцию.
class LocalApiServer {
  LocalApiServer._();

  static LocalApiServer? _instance;

  /// Запуск (идемпотентно). Возвращает порт, на котором слушает сервер,
  /// либо null — запустить не удалось.
  static Future<int?> startFor(CollectionState state) async {
    final existing = _instance;
    if (existing != null) {
      return existing._port > 0 ? existing._port : null;
    }
    final server = LocalApiServer._();
    final port = await server._start(state);
    if (port != null) {
      _instance = server;
      LogService.instance
          .add('INFO', 'Сервер интеграции запущен на 127.0.0.1:$port');
    }
    return port;
  }

  CollectionState? _state;
  HttpServer? _http;
  int _port = 0;

  int get port => _port;

  /// Порты, которые расширение перебирает при поиске приложения.
  static const List<int> candidatePorts = [41595, 41596, 41597];

  Future<int?> _start(CollectionState state) async {
    _state = state;
    for (final port in candidatePorts) {
      try {
        final server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          port,
        );
        _http = server;
        _port = port;
        server.listen(
          _handleRequest,
          onError: (Object e) {
            debugPrint('LocalApiServer: error: $e');
            LogService.instance.add('ERROR', 'Сервер интеграции: $e');
          },
          cancelOnError: false,
        );
        return port;
      } catch (e) {
        debugPrint('LocalApiServer: порт $port занят/недоступен: $e');
      }
    }
    debugPrint('LocalApiServer: не удалось занять ни один порт');
    return null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    // CORS: расширение ходит к нам напрямую из контент-скриптов.
    request.response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Content-Type')
      ..set('Access-Control-Allow-Private-Network', 'true');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    final path = request.uri.path;
    try {
      if (request.method == 'GET' &&
          (path == '/api/ping' || path == '/' || path == '/ping')) {
        await _sendJson(request, {
          'status': 'success',
          'data': {
            'name': 'korobka',
            'version': '0.4.0',
            'port': _port,
          },
        });
        return;
      }

      if (request.method == 'GET' &&
          (path == '/api/folder/list' || path == '/api/folders')) {
        final folders = await _state?.collectionService.getFolders() ?? [];
        await _sendJson(request, {
          'status': 'success',
          'data': [for (final f in folders) _folderToJson(f)],
        });
        return;
      }

      if (request.method == 'POST' && path == '/api/log') {
        final body = await utf8.decoder.bind(request).join();
        Map<String, dynamic> payload;
        try {
          payload = (jsonDecode(body) as Map).cast<String, dynamic>();
        } catch (e) {
          await _sendJson(
            request,
            {'status': 'error', 'message': 'invalid json'},
            code: HttpStatus.badRequest,
          );
          return;
        }
        final level = (payload['level'] ?? 'INFO').toString().toUpperCase();
        final descriptor = (payload['descriptor'] ?? '').toString();
        final data = payload['data'];
        var message = descriptor;
        if (data != null && data.toString().isNotEmpty) {
          final dataStr = jsonEncode(data);
          message = message.isEmpty
              ? dataStr
              : '$message | $dataStr';
        }
        LogService.instance.add(level, message, source: 'plugin');
        await _sendJson(request, {'status': 'success'});
        return;
      }

      // ─────────── СОЗДАНИЕ ПАПКИ ИЗ РАСШИРЕНИЯ ───────────
      if (request.method == 'POST' &&
          (path == '/api/folder/create' || path == '/api/folders')) {
        final payload = await _readJsonBody(request);
        if (payload == null) {
          await _sendJson(request, {'status': 'error', 'message': 'invalid json'},
              code: HttpStatus.badRequest);
          return;
        }
        final name = (payload['name'] ?? '').toString().trim();
        if (name.isEmpty) {
          await _sendJson(
            request,
            {'status': 'error', 'message': 'folder name is empty'},
            code: HttpStatus.badRequest,
          );
          return;
        }
        if (name.length > 100 || name.contains(RegExp(r'[\\/:*?"<>|]'))) {
          await _sendJson(
            request,
            {'status': 'error', 'message': 'invalid folder name'},
            code: HttpStatus.badRequest,
          );
          return;
        }
        final parentId = _normalizeId(payload['parentId']);
        if (parentId != null && !await _folderExists(parentId)) {
          await _sendJson(
            request,
            {'status': 'error', 'message': 'parent folder not found'},
            code: HttpStatus.badRequest,
          );
          return;
        }
        final state = _state;
        if (state == null) {
          await _sendJson(
            request,
            {'status': 'error', 'message': 'app is not ready'},
            code: HttpStatus.serviceUnavailable,
          );
          return;
        }
        try {
          final id = await state.createFolderExternal(name, parentId: parentId);
          await _sendJson(request, {
            'status': 'success',
            'data': {'id': id, 'name': name, 'parentId': parentId},
          });
        } catch (e) {
          await _sendJson(
            request,
            {'status': 'error', 'message': 'create failed: $e'},
            code: HttpStatus.internalServerError,
          );
        }
        return;
      }

      // ─────────── СОХРАНЕНИЕ ИЗОБРАЖЕНИЯ ИЗ РАСШИРЕНИЯ ───────────
      // Принимает либо url (приложение скачает само), либо base64
      // (для blob: и data: картинок, которые приложение скачать не может).
      if (request.method == 'POST' &&
          (path == '/api/item/add' || path == '/api/items/add')) {
        final payload = await _readJsonBody(request);
        if (payload == null) {
          await _sendJson(request, {'status': 'error', 'message': 'invalid json'},
              code: HttpStatus.badRequest);
          return;
        }
        final folderId = _normalizeId(payload['folderId']);
        if (folderId != null && !await _folderExists(folderId)) {
          await _sendJson(
            request,
            {'status': 'error', 'message': 'folder not found'},
            code: HttpStatus.badRequest,
          );
          return;
        }
        final state = _state;
        if (state == null) {
          await _sendJson(
            request,
            {'status': 'error', 'message': 'app is not ready'},
            code: HttpStatus.serviceUnavailable,
          );
          return;
        }

        final url = (payload['url'] ?? '').toString().trim();
        final base64Data = (payload['base64'] ?? '').toString().trim();
        final rawFilename = (payload['filename'] ?? '').toString();

        String tempPath;
        try {
          if (base64Data.isNotEmpty) {
            tempPath = await _writeBase64ToTemp(
              base64Data,
              filename: rawFilename,
              mime: (payload['mime'] ?? '').toString(),
            );
          } else if (url.isNotEmpty && (url.startsWith('http://') || url.startsWith('https://'))) {
            tempPath = await _downloadToTemp(url, preferredName: rawFilename);
          } else {
            await _sendJson(
              request,
              {'status': 'error', 'message': 'no url or base64 payload'},
              code: HttpStatus.badRequest,
            );
            return;
          }
        } catch (e) {
          await _sendJson(
            request,
            {'status': 'error', 'message': 'download failed: $e'},
            code: HttpStatus.badGateway,
          );
          return;
        }

        try {
          await state.importExternalFiles([tempPath], folderId: folderId);
        } catch (e) {
          _deleteQuietly(File(tempPath));
          await _sendJson(
            request,
            {'status': 'error', 'message': 'import failed: $e'},
            code: HttpStatus.internalServerError,
          );
          return;
        }
        _deleteQuietly(File(tempPath));

        LogService.instance.add(
          'INFO',
          'Сохранено из расширения: ${base64Data.isNotEmpty ? rawFilename : url}',
          source: 'plugin',
        );
        await _sendJson(request, {
          'status': 'success',
          'data': {'saved': true, 'folderId': folderId},
        });
        return;
      }

      await _sendJson(
        request,
        {'status': 'error', 'message': 'not found'},
        code: HttpStatus.notFound,
      );
    } catch (e) {
      debugPrint('LocalApiServer: handler error: $e');
      try {
        await _sendJson(
          request,
          {'status': 'error', 'message': '$e'},
          code: HttpStatus.internalServerError,
        );
      } catch (_) {/* соединение уже закрыто */}
    }
  }

  /// Сериализация папки в формат, близкий к Eagle API.
  Map<String, dynamic> _folderToJson(Folder folder) => {
        'id': folder.id,
        'name': folder.name,
        'parentId': folder.parentId,
        'color': folder.color,
        'description': '',
        'password': '',
        'mtime': 0,
      };

  // ─────────── ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ НОВЫХ КОМАНД ───────────

  /// Чтение JSON-тела запроса. Возвращает null, если тело не распарсилось.
  Future<Map<String, dynamic>?> _readJsonBody(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      if (body.trim().isEmpty) return null;
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Приведение id папки из JSON (int, числовая строка, null) к int?.
  int? _normalizeId(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    return int.tryParse(raw.toString().trim());
  }

  /// Существует ли папка с таким id (null считается «корнем» и валиден).
  Future<bool> _folderExists(int? id) async {
    if (id == null) return true;
    try {
      final folders = await _state?.collectionService.getFolders() ?? [];
      return folders.any((f) => f.id == id);
    } catch (_) {
      return false;
    }
  }

  /// Каталог-приёмник для временных файлов: <temp>/korobka_inbox/.
  Future<Directory> _inboxDir() async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}${Platform.pathSeparator}korobka_inbox');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Уникальное имя файла: korobka_<мс>_<счётчик>.<ext>.
  String _uniqueName(String ext) {
    final ms = DateTime.now().microsecondsSinceEpoch;
    final n = (_uniqueCounter = (_uniqueCounter + 1) % 10000).toString().padLeft(4, '0');
    final safeExt = ext.trim().isEmpty ? 'jpg' : ext.trim();
    return 'korobka_${ms}_$n.${safeExt.replaceAll(RegExp(r'[^a-z0-9]'), '')}';
  }

  int _uniqueCounter = 0;

  /// Расширение из MIME-типа (только известные изображениям значения).
  String _extFromMime(String mime) {
    final m = mime.toLowerCase().split(';').first.trim();
    const map = {
      'image/jpeg': 'jpg',
      'image/jpg': 'jpg',
      'image/png': 'png',
      'image/webp': 'webp',
      'image/gif': 'gif',
      'image/bmp': 'bmp',
      'image/tiff': 'tiff',
      'image/svg+xml': 'svg',
      'image/x-icon': 'ico',
      'image/vnd.microsoft.icon': 'ico',
    };
    return map[m] ?? '';
  }

  /// Расширение из URL (без query/fragment), если оно «картинокное».
  String _extFromUrl(String url) {
    try {
      final pathOnly = Uri.parse(url).path;
      final name = pathOnly.split('/').last;
      final idx = name.lastIndexOf('.');
      if (idx == -1 || idx == name.length - 1) return '';
      final ext = name.substring(idx + 1).toLowerCase();
      const known = ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif', 'tiff', 'svg', 'ico'];
      return known.contains(ext) ? (ext == 'jpeg' ? 'jpg' : ext) : '';
    } catch (_) {
      return '';
    }
  }

  /// Расширение из имени файла (для base64-сохранений).
  String _extFromFilename(String filename) {
    final name = filename.replaceAll('\\', '/').split('/').last;
    final idx = name.lastIndexOf('.');
    if (idx == -1 || idx == name.length - 1) return '';
    final ext = name.substring(idx + 1).toLowerCase();
    const known = ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif', 'tiff', 'svg', 'ico'];
    return known.contains(ext) ? (ext == 'jpeg' ? 'jpg' : ext) : '';
  }

  /// Декодирование base64 (возможно с префиксом data:) во временный файл.
  Future<String> _writeBase64ToTemp(
    String base64Data, {
    String filename = '',
    String mime = '',
  }) async {
    var payload = base64Data;
    var dataMime = '';
    // Формат data:image/png;base64,AAAA…
    final marker = 'base64,';
    if (payload.startsWith('data:') && payload.contains(marker)) {
      final meta = payload.substring(5, payload.indexOf(marker));
      dataMime = meta.split(';').first.trim();
      payload = payload.substring(payload.indexOf(marker) + marker.length);
    }
    payload = payload.replaceAll(RegExp(r'\s'), '');
    final bytes = base64Decode(payload);
    if (bytes.isEmpty) {
      throw Exception('empty payload');
    }

    var ext = _extFromFilename(filename);
    if (ext.isEmpty) ext = _extFromMime(dataMime);
    if (ext.isEmpty) ext = _extFromMime(mime);
    if (ext.isEmpty) ext = _guessExtFromBytes(bytes);

    final dir = await _inboxDir();
    final file = File('${dir.path}${Platform.pathSeparator}${_uniqueName(ext)}');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Определение расширения по магическим байтам (страховка).
  String _guessExtFromBytes(List<int> b) {
    // PNG: 89 50 4E 47
    if (b.length >= 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return 'png';
    }
    // JPEG: FF D8 FF
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'jpg';
    }
    // WEBP: RIFF....WEBP
    if (b.length >= 12 &&
        b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
      return 'webp';
    }
    // GIF: GIF8
    if (b.length >= 4 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
      return 'gif';
    }
    // BMP: BM
    if (b.length >= 2 && b[0] == 0x42 && b[1] == 0x4D) return 'bmp';
    return 'jpg';
  }

  /// Скачивание изображения по URL во временный файл.
  /// Chrome и Pinterest требуют User-Agent, иначе отдают 403.
  Future<String> _downloadToTemp(String url, {String preferredName = ''}) async {
    final client = HttpClient();
    client.userAgent =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/126.0 Safari/537.36 Korobka/0.4';
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close().timeout(const Duration(seconds: 30));
      if (resp.statusCode != HttpStatus.ok) {
        throw Exception('HTTP ${resp.statusCode}');
      }

      var ext = _extFromMime(resp.headers.contentType?.toString() ?? '');
      if (ext.isEmpty) ext = _extFromUrl(url);
      if (ext.isEmpty) ext = _extFromFilename(preferredName);

      final builder = BytesBuilder(copy: false);
      await for (final chunk in resp) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (bytes.isEmpty) throw Exception('empty response');

      // Последняя страховка — по содержимому.
      if (ext.isEmpty) ext = _guessExtFromBytes(bytes);

      final dir = await _inboxDir();
      final file = File('${dir.path}${Platform.pathSeparator}${_uniqueName(ext)}');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } catch (_) {
      // временный файл не критичен — оставляем как есть
    }
  }

  Future<void> _sendJson(
    HttpRequest request,
    Map<String, dynamic> body, {
    int code = HttpStatus.ok,
  }) async {
    request.response.statusCode = code;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  /// Остановка сервера (для полноты API сервиса).
  Future<void> stop() async {
    await _http?.close(force: true);
    _http = null;
    _port = 0;
  }
}
