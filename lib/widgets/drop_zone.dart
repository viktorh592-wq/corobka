import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../features/images/import_controller.dart';

/// Область, принимающая перетаскиваемые файлы изображений.
///
/// Оборачивает дочерний виджет и обрабатывает drag-and-drop файлов
/// из файловой системы, передавая их в [ImportController]. Файлы
/// добавляются в папку [folderId] (если она выбрана) — как в Eagle,
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
    return DropTarget(
      onDragDone: (details) => _handleDragDone(details.files),
      onDragEntered: (_) {},
      onDragExited: (_) {},
      child: child,
    );
  }

  Future<void> _handleDragDone(List<XFile> files) async {
    final paths = files.map((f) => f.path).toList();
    await controller.importPaths(paths, folderId: folderId);
    onImported?.call();
  }
}
