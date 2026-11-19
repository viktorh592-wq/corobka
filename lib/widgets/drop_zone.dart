import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../features/images/import_controller.dart';
import 'file_drag.dart';

/// Область, принимающая перетаскиваемые файлы.
///
/// Использует нативный drag-and-drop (super_drag_and_drop):
/// 1. Из Проводника Windows — файлы передаются реальными путями
///    (через `Formats.fileUri` / CF_HDROP) и импортируются в коллекцию
///    без промежуточного копирования.
/// 2. Изнутри приложения (перетаскивание элементов на фон контента) —
///    игнорируется: перемещение работает только на папки в левой панели.
///
/// Файлы добавляются в папку [folderId] (если она выбрана) — как в Eagle,
/// где drop попадает в текущую открытую папку.
class DropZone extends StatelessWidget {
  const DropZone({
    super.key,
    required this.controller,
    required this.child,
    this.folderId,
    this.onImported,
  });

  final ImportController controller;
  final Widget child;
  final int? folderId;
  final VoidCallback? onImported;

  @override
  Widget build(BuildContext context) {
    // В тестах нативный drag-and-drop недоступен — обёртка не подключается.
    if (!kNativeDragDropSupported) return child;

    return DropRegion(
      formats: const [Formats.fileUri],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: (event) {
        // Внутренние перетаскивания на фон контента не принимаем.
        if (isInternalDrag(event)) return DropOperation.none;
        final hasFiles = event.session.items.any(
          (item) => item.canProvide(Formats.fileUri),
        );
        return hasFiles ? DropOperation.copy : DropOperation.none;
      },
      onPerformDrop: (event) async {
        for (final item in event.session.items) {
          final reader = item.dataReader;
          if (reader == null || !reader.canProvide(Formats.fileUri)) continue;
          // Реальные пути файлов (Windows: CF_HDROP → file:// URI).
          // Значения приходят асинхронно — импортируем по мере готовности.
          reader.getValue<Uri>(
            Formats.fileUri,
            (value) async {
              if (value == null) return;
              try {
                await controller.importPaths(
                  [value.toFilePath()],
                  folderId: folderId,
                );
                onImported?.call();
              } catch (e) {
                debugPrint('DropZone: ошибка импорта: $e');
              }
            },
            onError: (error) {
              debugPrint('DropZone: не удалось прочитать путь: $error');
            },
          );
        }
      },
      child: child,
    );
  }
}
