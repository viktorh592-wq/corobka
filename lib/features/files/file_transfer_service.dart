import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Результат операции передачи файлов (скачивание, экспорт).
class TransferResult {
  const TransferResult({
    required this.exported,
    required this.failed,
    required this.targetPath,
  });

  /// Количество успешно скопированных файлов.
  final int exported;

  /// Количество файлов, которые не удалось скопировать.
  final int failed;

  /// Каталог, в который выполнена выгрузка.
  final String targetPath;
}

/// Сервис передачи файлов из коллекции в файловую систему ПК.
///
/// Отвечает за три сценария:
/// 1. «Скачать» — копирование файлов в системную папку «Загрузки»
///    (`C:\Users\<user>\Downloads`).
/// 2. «Открыть папку» — открытие папки с файлом в Проводнике
///    с выделением этого файла (`explorer /select`).
/// 3. Drag-out — перетаскивание файлов из приложения в Проводник
///    или любое другое ПО (реализуется на уровне виджетов через
///    `super_drag_and_drop`, см. `lib/widgets/file_drag.dart`).
class FileTransferService {
  const FileTransferService();

  /// Копирует файлы в системную папку «Загрузки».
  ///
  /// Возвращает [TransferResult] со счётчиками скопированных файлов.
  /// При невозможности определить папку «Загрузки» бросает исключение.
  Future<TransferResult> downloadToDownloads(List<String> paths) async {
    final downloads = await getDownloadsDirectory();
    if (downloads == null) {
      throw Exception('Не удалось определить папку «Загрузки»');
    }
    return copyFiles(paths, downloads.path);
  }

  /// Копирование файлов в целевую папку с уникальными именами.
  ///
  /// Файлы не перезаписываются: при совпадении имён к копии добавляется
  /// суффикс `_1`, `_2`, ... (как в браузерах при скачивании).
  Future<TransferResult> copyFiles(List<String> paths, String targetDir) async {
    var exported = 0;
    var failed = 0;

    for (final path in paths) {
      try {
        final source = File(path);
        if (!await source.exists()) {
          failed++;
          continue;
        }

        final fileName = source.uri.pathSegments.last;
        final unique = await uniqueName(fileName, targetDir);
        await source.copy('$targetDir${Platform.pathSeparator}$unique');
        exported++;
      } catch (e) {
        debugPrint('copyFiles error for $path: $e');
        failed++;
      }
    }

    return TransferResult(
      exported: exported,
      failed: failed,
      targetPath: targetDir,
    );
  }

  /// Открывает папку, содержащую файл, и выделяет файл в ней.
  ///
  /// Windows: `explorer /select,"путь"` — Проводник открывает папку
  /// и подсвечивает файл. macOS: `open -R`. Linux: `xdg-open` папки.
  ///
  /// ВАЖНО: explorer.exe возвращает ненулевой код выхода даже при
  /// успехе, поэтому код выхода не проверяется.
  Future<void> revealInFileManager(String path) async {
    final file = File(path);
    final absolutePath = file.absolute.path;

    if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,', absolutePath]);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', absolutePath]);
    } else if (Platform.isLinux) {
      final parent = file.absolute.parent.path;
      await Process.run('xdg-open', [parent]);
    } else {
      throw UnsupportedError(
        'Открытие папки не поддерживается на ${Platform.operatingSystem}',
      );
    }
  }

  /// Генерация уникального имени файла в целевой папке.
  Future<String> uniqueName(String original, String dir) async {
    final target = Directory(dir);
    final existing = await target.exists()
        ? (await target.list().toList())
            .map((e) => e.path.split(Platform.pathSeparator).last)
            .toSet()
        : <String>{};

    if (!existing.contains(original)) return original;

    final base = original.contains('.')
        ? original.substring(0, original.lastIndexOf('.'))
        : original;
    final ext = original.contains('.')
        ? original.substring(original.lastIndexOf('.') + 1)
        : '';

    var counter = 1;
    var candidate = ext.isEmpty ? '${base}_$counter' : '${base}_$counter.$ext';
    while (existing.contains(candidate)) {
      counter++;
      candidate = ext.isEmpty ? '${base}_$counter' : '${base}_$counter.$ext';
    }
    return candidate;
  }
}
