import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../../data/models/item.dart';

/// Результат операции экспорта.
class ExportResult {
  const ExportResult({
    required this.exported,
    required this.failed,
    required this.targetPath,
  });

  /// Количество успешно экспортированных файлов.
  final int exported;

  /// Количество файлов, которые не удалось экспортировать.
  final int failed;

  /// Каталог, в который выполнена выгрузка.
  final String targetPath;
}

/// Сервис экспорта элементов коллекции.
///
/// Позволяет выгрузить выбранные элементы (изображения) в указанную
/// пользователем папку на диске.
class ExportService {
  const ExportService();

  /// Экспорт элементов в выбранную пользователем папку.
  ///
  /// Открывает диалог выбора целевой папки и копирует туда файлы.
  /// Возвращает результат экспорта или `null`, если операция отменена.
  Future<ExportResult?> exportItems(List<CollectionItem> items) async {
    if (items.isEmpty) return null;

    final targetPath = await FilePicker.platform.getDirectoryPath();
    if (targetPath == null) return null;

    var exported = 0;
    var failed = 0;

    for (final item in items) {
      try {
        final source = File(item.path);
        if (!await source.exists()) {
          failed++;
          continue;
        }

        final fileName = source.uri.pathSegments.last;
        final destPath = '$targetPath${Platform.pathSeparator}$fileName';

        // Уникальное имя, чтобы не перезаписывать существующие файлы.
        final unique = await _uniqueName(fileName, targetPath);
        await source.copy('$targetPath${Platform.pathSeparator}$unique');
        exported++;
      } catch (_) {
        failed++;
      }
    }

    return ExportResult(
      exported: exported,
      failed: failed,
      targetPath: targetPath,
    );
  }

  /// Генерация уникального имени файла в целевой папке.
  Future<String> _uniqueName(String original, String dir) async {
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
    var candidate = ext.isEmpty
        ? '${base}_$counter'
        : '${base}_$counter.$ext';
    while (existing.contains(candidate)) {
      counter++;
      candidate = ext.isEmpty
          ? '${base}_$counter'
          : '${base}_$counter.$ext';
    }
    return candidate;
  }
}