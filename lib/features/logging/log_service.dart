import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Журнал событий приложения и плагина.
///
/// Управляется из настроек приложения (запись / остановка / выгрузка).
/// Лог ведётся одновременно из двух источников:
///  - само приложение (импорт, ошибки, БД, HTTP-сервер интеграции);
///  - расширение браузера — его события приходят через локальный
///    HTTP-сервер (POST /api/log) и помечаются меткой «plugin».
///
/// Особенности:
///  - кольцевой буфер последних строк живёт всегда (даже до старта
///    записи) — при нажатии «Начать запись» в файл попадает предыстория;
///  - файл лога создаётся во временной папке системы (korobka-logs);
///  - «Выгрузить лог» сохраняет текущий журнал в место, выбранное
///    пользователем (системный диалог сохранения).
class LogService extends ChangeNotifier {
  LogService._();

  static final LogService instance = LogService._();

  /// Максимум строк в оперативном буфере (предыстория + текущая запись).
  static const int _maxBufferLines = 3000;

  /// Количество строк предыстории, сбрасываемых в файл при старте записи.
  static const int _historyLines = 300;

  bool _recording = false;
  File? _logFile;
  DateTime? _startedAt;

  /// Кольцевой буфер строк журнала.
  final List<String> _buffer = <String>[];

  bool get isRecording => _recording;
  String? get logFilePath => _logFile?.path;
  DateTime? get startedAt => _startedAt;
  List<String> get lines => List.unmodifiable(_buffer);

  /// Папка для файлов логов (временная папка системы / korobka-logs).
  Future<Directory> _resolveDirectory() async {
    Directory base;
    try {
      base = await getTemporaryDirectory();
    } catch (e) {
      base = Directory.systemTemp;
      debugPrint('LogService: getTemporaryDirectory error: $e');
    }
    final dir = Directory('${base.path}${Platform.pathSeparator}korobka-logs');
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } catch (e) {
      debugPrint('LogService: create dir error: $e');
    }
    return dir;
  }

  /// Старт записи: создаёт файл лога и сбрасывает в него предысторию.
  Future<void> start() async {
    if (_recording) return;
    final dir = await _resolveDirectory();
    final now = DateTime.now();
    final name = 'log-${_fileNameStamp(now)}.log';
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    try {
      final sw = StringBuffer();
      sw.writeln('=== коробка — журнал событий ===');
      sw.writeln('=== запись начата: ${_stamp(now)} ===');
      final history = _buffer.length > _historyLines
          ? _buffer.sublist(_buffer.length - _historyLines)
          : _buffer;
      if (history.isNotEmpty) {
        sw.writeln('--- предыстория (последние ${history.length} строк) ---');
        for (final line in history) {
          sw.writeln(line);
        }
        sw.writeln('--- конец предыстории ---');
      }
      await file.writeAsString(sw.toString(), flush: true);
      _logFile = file;
      _recording = true;
      _startedAt = now;
      add('INFO', 'Запись журнала начата: ${file.path}');
    } catch (e) {
      debugPrint('LogService: start error: $e');
      _recording = false;
    }
    notifyListeners();
  }

  /// Остановка записи.
  Future<void> stop() async {
    if (!_recording) return;
    _recording = false;
    _startedAt = null;
    add('INFO', 'Запись журнала остановлена');
    _logFile = null;
    notifyListeners();
  }

  /// Добавление строки в журнал.
  ///
  /// Строка всегда попадает в буфер предыстории, но в файл пишется
  /// только пока идёт запись. [source] — «app» или «plugin».
  void add(String level, String message, {String source = 'app'}) {
    final line = '${_stamp(DateTime.now())} [$source] [$level] '
        '${message.replaceAll('\n', ' | ')}';
    _buffer.add(line);
    if (_buffer.length > _maxBufferLines) {
      _buffer.removeRange(0, _buffer.length - _maxBufferLines);
    }
    if (_recording && _logFile != null) {
      final file = _logFile!;
      // Пишем «в фоне»: журнал не должен тормозить UI-поток.
      unawaited(() async {
        try {
          await file.writeAsString('$line\n',
              mode: FileMode.append, flush: false);
        } catch (e) {
          debugPrint('LogService: write error: $e');
        }
      }());
    }
  }

  /// Выгрузка журнала: сохраняет все накопленные строки в файл,
  /// выбранный пользователем. Возвращает путь или null (отмена).
  ///
  /// [pickPath] — колбэк системного диалога сохранения (внедряется
  /// снаружи, чтобы не тянуть UI-зависимости в сервис).
  Future<String?> export({
    required Future<String?> Function(String defaultName) pickPath,
  }) async {
    final name = 'korobka-log-${_fileNameStamp(DateTime.now())}.log';
    final target = await pickPath(name);
    if (target == null || target.isEmpty) return null;

    final sw = StringBuffer();
    sw.writeln('=== коробка — выгрузка журнала '
        '(${_stamp(DateTime.now())}) ===');
    sw.writeln('строк в буфере: ${_buffer.length}');
    for (final line in _buffer) {
      sw.writeln(line);
    }

    final file = File(target);
    try {
      await file.writeAsString(sw.toString(), flush: true);
    } catch (e) {
      debugPrint('LogService: export error: $e');
      rethrow;
    }

    // Выгрузка тоже фиксируется в журнале.
    final wasRecording = _recording;
    _logFile = file;
    add('INFO', 'Журнал выгружен: $target');
    if (!wasRecording) _logFile = null;
    return target;
  }

  /// Текст журнала целиком (для показа в UI при необходимости).
  String dump() => _buffer.join('\n');

  String _fileNameStamp(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}'
      '-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}'
      '_${t.hour.toString().padLeft(2, '0')}-${t.minute.toString().padLeft(2, '0')}'
      '-${t.second.toString().padLeft(2, '0')}';

  String _stamp(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}.'
      '${t.millisecond.toString().padLeft(3, '0')}';
}
