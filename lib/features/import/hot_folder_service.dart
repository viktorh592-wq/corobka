import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../collection/collection_state.dart';
import '../images/image_service.dart';

/// Папка-приёмник для расширения браузера.
///
/// Расширение «Коробка» сохраняет картинки и видео из интернета в
/// «Загрузки/Коробка». Этот сервис следит за папкой и автоматически
/// добавляет новые файлы в коллекцию, после чего удаляет их
/// (файл копируется в хранилище коллекции, оригинал больше не нужен).
///
/// Особенности:
///  - при старте приложения папка сканируется: всё накопленное, пока
///    приложение было закрыто, импортируется;
///  - файлы .crdownload/.tmp (незавершённые загрузки Chrome) пропускаются;
///  - файл считается готовым, когда его размер перестал меняться;
///  - файлы из подпапки «Загрузки/Коробка/<Имя>/» попадают в папку
///    коллекции с именем <Имя> (создаётся при необходимости).
class HotFolderService {
  HotFolderService._();

  static HotFolderService? _instance;

  /// Запуск (идемпотентно — повторный вызов ничего не меняет).
  static Future<void> startFor(CollectionState state) async {
    final existing = _instance;
    if (existing != null) {
      await existing._restart(state);
      return;
    }
    final service = HotFolderService._();
    _instance = service;
    await service._start(state);
  }

  static const String folderName = 'Коробка';

  CollectionState? _state;
  Directory? _dir;
  StreamSubscription<FileSystemEvent>? _subscription;
  Timer? _debounceTimer;
  Timer? _scanTimer;
  bool _scanning = false;

  /// Файлы, импорт которых не удался (не ретраим до следующего запуска).
  final Set<String> _failedPaths = {};

  /// Определяем путь «Загрузки/Коробка».
  Future<Directory?> _resolveDirectory() async {
    Directory? downloads;
    try {
      downloads = await getDownloadsDirectory();
    } catch (e) {
      debugPrint('HotFolder: getDownloadsDirectory error: $e');
    }
    downloads ??= _fallbackDownloadsDirectory();
    if (downloads == null) return null;

    final dir = Directory('${downloads.path}${Platform.pathSeparator}$folderName');
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (e) {
      debugPrint('HotFolder: create dir error: $e');
      return null;
    }
  }

  /// Запасной способ найти «Загрузки», если path_provider не справился.
  Directory? _fallbackDownloadsDirectory() {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'];
    if (home == null || home.isEmpty) return null;
    return Directory('$home${Platform.pathSeparator}Downloads');
  }

  Future<void> _start(CollectionState state) => _restart(state);

  Future<void> _restart(CollectionState state) async {
    _state = state;
    await _subscription?.cancel();
    _scanTimer?.cancel();

    final dir = await _resolveDirectory();
    if (dir == null) {
      debugPrint('HotFolder: папка «Загрузки/$folderName» недоступна — автоподхват выключен');
      return;
    }
    _dir = dir;
    debugPrint('HotFolder: слежу за ${dir.path}');

    // 1. Импорт накопившегося (приложение могло быть закрыто).
    await _scanAndImport();

    // 2. События файловой системы (Windows поддерживает recursive).
    try {
      _subscription = dir.watch(events: FileSystemEvent.create | FileSystemEvent.modify | FileSystemEvent.move | FileSystemEvent.delete)
          .listen((_) => _scheduleScan(), onError: (e) {
        debugPrint('HotFolder: watch error: $e');
      });
    } catch (e) {
      debugPrint('HotFolder: watch недоступен, работает периодический скан: $e');
    }

    // 3. Страховочный периодический скан (пропущенные события).
    _scanTimer = Timer.periodic(const Duration(seconds: 5), (_) => _scheduleScan());
  }

  void _scheduleScan() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 900), () {
      _scanAndImport();
    });
  }

  Future<void> _scanAndImport() async {
    if (_scanning || _dir == null || _state == null) return;
    _scanning = true;
    try {
      final candidates = await _collectCandidates();
      for (final path in candidates) {
        await _importFile(path);
      }
    } catch (e) {
      debugPrint('HotFolder: scan error: $e');
    } finally {
      _scanning = false;
    }
  }

  /// Список готовых к импорту файлов (рекурсивно, глубина — подпапки).
  Future<List<String>> _collectCandidates() async {
    final result = <String>[];
    try {
      await for (final entity
          in _dir!.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final path = entity.path;
        if (_failedPaths.contains(path)) continue;
        if (!_isCandidate(path)) continue;
        result.add(path);
      }
    } catch (e) {
      debugPrint('HotFolder: list error: $e');
    }
    return result;
  }

  bool _isCandidate(String path) {
    final name = path.split(Platform.pathSeparator).last;
    if (name.isEmpty || name.startsWith('.')) return false;
    if (name.startsWith('~')) return false;
    final lower = name.toLowerCase();
    // Незавершённые загрузки Chrome/браузеров.
    if (lower.endsWith('.crdownload') ||
        lower.endsWith('.part') ||
        lower.endsWith('.tmp') ||
        lower.endsWith('.download')) {
      return false;
    }
    final ext = _extensionOf(path);
    return ImageService.supportedExtensions.contains(ext);
  }

  Future<void> _importFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return; // уже удалён (событие delete)

    // Ждём, пока размер файла стабилизируется (Chrome дописывает файл).
    if (!await _waitUntilStable(file)) return;

    // Подпапка «Загрузки/Коробка/<Имя>/file.png» → папка коллекции <Имя>.
    final folderId = await _resolveFolderId(path);

    final state = _state!;
    try {
      await state.importExternalFiles([path], folderId: folderId);
    } catch (e) {
      debugPrint('HotFolder: импорт не удался ($path): $e');
      _failedPaths.add(path);
      return;
    }

    // Импорт успешен — удаляем файл из папки-приёмника.
    try {
      await file.delete();
      debugPrint('HotFolder: импортирован и удалён: $path');
    } catch (e) {
      debugPrint('HotFolder: не удалось удалить файл ($path): $e');
      _failedPaths.add(path);
    }
  }

  /// Ждём стабильности размера файла (две пробы с интервалом).
  Future<bool> _waitUntilStable(File file, {int attempts = 8}) async {
    var lastSize = -1;
    for (var i = 0; i < attempts; i++) {
      try {
        final size = await file.length();
        if (size > 0 && size == lastSize) return true;
        lastSize = size;
      } catch (e) {
        return false; // файл исчез/занят
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    return false;
  }

  /// Сопоставление подпапки с папкой коллекции (по имени, без учёта регистра).
  Future<int?> _resolveFolderId(String path) async {
    try {
      final rootPath = _dir!.path;
      if (!path.startsWith(rootPath)) return null;
      var relative = path.substring(rootPath.length);
      if (relative.startsWith(Platform.pathSeparator)) {
        relative = relative.substring(1);
      }
      final segments =
          relative.split(Platform.pathSeparator).where((s) => s.isNotEmpty).toList();
      if (segments.length < 2) return null; // файл в корне папки-приёмника

      final folderName = segments[0];
      final folders = await _state!.collectionService.getFolders();
      for (final folder in folders) {
        if (folder.name.toLowerCase() == folderName.toLowerCase()) {
          return folder.id;
        }
      }
      final id = await _state!.collectionService.createFolder(folderName);
      debugPrint('HotFolder: создана папка коллекции «$folderName»');
      return id;
    } catch (e) {
      debugPrint('HotFolder: resolveFolderId error: $e');
      return null;
    }
  }

  String _extensionOf(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final idx = name.lastIndexOf('.');
    return idx == -1 ? '' : name.substring(idx + 1).toLowerCase();
  }

  /// Остановка слежения (для тестов/горячей перезагрузки).
  Future<void> stop() async {
    await _subscription?.cancel();
    _scanTimer?.cancel();
    _debounceTimer?.cancel();
    _dir = null;
    _state = null;
  }
}
