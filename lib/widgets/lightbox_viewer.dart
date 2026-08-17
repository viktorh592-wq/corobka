import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models/item.dart';

/// Полноэкранный просмотр элемента (lightbox) с зумом и навигацией.
///
/// Поддерживает:
/// - зум (приближение/отдаление) с помощью кнопок и колеса мыши;
/// - перетаскивание увеличенного изображения;
/// - переключение между элементами стрелками;
/// - закрытие по Esc или кнопке.
class LightboxViewer extends StatefulWidget {
  const LightboxViewer({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  /// Список элементов для навигации.
  final List<CollectionItem> items;

  /// Начальный индекс отображаемого элемента.
  final int initialIndex;

  @override
  State<LightboxViewer> createState() => _LightboxViewerState();
}

class _LightboxViewerState extends State<LightboxViewer> {
  late int _index;
  double _scale = 1.0;
  Offset _offset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
  }

  CollectionItem get _current => widget.items[_index];

  void _previous() {
    if (widget.items.isEmpty) return;
    setState(() {
      _index = (_index - 1 + widget.items.length) % widget.items.length;
      _resetTransform();
    });
  }

  void _next() {
    if (widget.items.isEmpty) return;
    setState(() {
      _index = (_index + 1) % widget.items.length;
      _resetTransform();
    });
  }

  void _resetTransform() {
    _scale = 1.0;
    _offset = Offset.zero;
  }

  void _zoom(double delta) {
    setState(() {
      _scale = (_scale + delta).clamp(1.0, 5.0);
    });
  }

  void _close() {
    Navigator.of(context).pop();
  }

  Future<void> _handleKey(KeyEvent event) async {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _previous();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _next();
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: _handleKey,
      child: Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            // Изображение с зумом и панорамированием.
            Center(
              child: GestureDetector(
                onScaleStart: (_) => _offset = Offset.zero,
                onScaleUpdate: (details) {
                  setState(() {
                    _scale = details.scale.clamp(1.0, 5.0);
                    _offset += details.focalPointDelta;
                  });
                },
                child: Transform.translate(
                  offset: _offset,
                  child: Transform.scale(
                    scale: _scale,
                    child: _ImagePreview(path: _current.path),
                  ),
                ),
              ),
            ),

            // Верхняя панель: заголовок и закрытие.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _current.title ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Закрыть (Esc)',
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: _close,
                    ),
                  ],
                ),
              ),
            ),

            // Индикатор позиции.
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_index + 1} из ${widget.items.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),

            // Кнопки навигации.
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _NavButton(
                  icon: Icons.chevron_left,
                  onPressed: _previous,
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _NavButton(
                  icon: Icons.chevron_right,
                  onPressed: _next,
                ),
              ),
            ),

            // Нижняя панель: зум и метаданные.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                color: Colors.black54,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Уменьшить',
                      icon: const Icon(Icons.zoom_out, color: Colors.white),
                      onPressed: () => _zoom(-0.5),
                    ),
                    Text(
                      '${(_scale * 100).round()}%',
                      style: const TextStyle(color: Colors.white),
                    ),
                    IconButton(
                      tooltip: 'Увеличить',
                      icon: const Icon(Icons.zoom_in, color: Colors.white),
                      onPressed: () => _zoom(0.5),
                    ),
                    const Spacer(),
                    Text(
                      '${_current.width ?? '?'} × ${_current.height ?? '?'}'
                      ' · ${_current.format ?? ''}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Кнопка навигации по краям экрана.
class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black38,
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 36),
        onPressed: onPressed,
      ),
    );
  }
}

/// Превью изображения (с учётом кеширования).
class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      maxScale: 5,
      child: Image.file(
        File(path),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.white54),
        ),
      ),
    );
  }
}