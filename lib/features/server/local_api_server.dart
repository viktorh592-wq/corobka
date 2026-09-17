import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

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
            'version': '0.3.0',
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
