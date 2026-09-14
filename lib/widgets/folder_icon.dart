import 'package:flutter/material.dart';

import '../features/folders/folder_colors.dart';

/// Иконка папки с поддержкой пользовательского цвета.
///
/// Если цвет задан (HEX из «настройки цвета папки») — рисуется залитая
/// иконка папки выбранного цвета (как цветные папки в Eagle).
/// Если цвета нет — стандартная контурная иконка в акцентном цвете
/// элементов управления, единая для всего приложения.
class FolderIcon extends StatelessWidget {
  const FolderIcon({
    super.key,
    this.colorHex,
    this.size = 20,
  });

  /// HEX-строка цвета папки (без решётки) либо null — стандартный цвет.
  final String? colorHex;

  /// Размер иконки (логические пиксели).
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = colorFromHex(colorHex);
    if (color == null) {
      return Icon(
        Icons.folder_outlined,
        size: size,
        color: Theme.of(context).colorScheme.primary,
      );
    }
    return Icon(
      Icons.folder,
      size: size,
      color: color,
    );
  }
}
