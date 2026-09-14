import 'package:flutter/material.dart';

/// Разделяемая перетаскиваемая граница между панелями (как в любых
/// настольных приложениях: навели курсор на границу — зажали ЛКМ —
/// потянули в сторону — ширина панели изменилась).
///
/// [onDrag] получает дельту по горизонтали (+ вправо, − влево).
class PanelDragHandle extends StatefulWidget {
  const PanelDragHandle({super.key, required this.onDrag, this.onDragEnd});

  /// Колбэк перетаскивания: дельта изменения ширины панели.
  final void Function(double delta) onDrag;

  /// Вызывается при отпускании кнопки мыши (для сохранения размера).
  final VoidCallback? onDragEnd;

  @override
  State<PanelDragHandle> createState() => _PanelDragHandleState();
}

class _PanelDragHandleState extends State<PanelDragHandle> {
  bool _hovering = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovering || _dragging;
    final highlight = Theme.of(context).colorScheme.primary;

    return MouseRegion(
      // Курсор «изменить ширину колонки» — стандарт для границ панелей.
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
        onHorizontalDragEnd: (_) {
          setState(() => _dragging = false);
          widget.onDragEnd?.call();
        },
        child: Container(
          width: 6,
          color: active ? highlight.withValues(alpha: 0.35) : Colors.transparent,
          child: Center(
            child: Container(
              width: 1,
              color: Theme.of(context).dividerColor,
            ),
          ),
        ),
      ),
    );
  }
}
