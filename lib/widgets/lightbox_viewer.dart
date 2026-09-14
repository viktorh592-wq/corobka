import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models/item.dart';

/// Полноэкранный просмотр элемента (lightbox) в стиле классического
/// просмотрщика Windows.
///
/// Поддерживает:
/// - перетаскивание увеличенного изображения мышью (панорамирование);
/// - зум колесиком мыши (с фокусом на позицию курсора);
/// - полоску масштабирования в нижней панели + кнопки «+/-»;
/// - сброс масштаба двойным кликом;
/// - переключение между элементами стрелками;
/// - закрытие по Esc или «крестику».
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
  /// Границы масштаба (аналог классического просмотрщика).
  static const double _minScale = 1.0;
  static const double _maxScale = 8.0;

  late int _index;
  double _scale = 1.0;
  Offset _offset = Offset.zero;

  // Значения на момент начала жеста (чтобы перетаскивание мышью
  // не сбрасывало масштаб — раньше drag возвращал зум к 100%).
  double _gestureBaseScale = 1.0;
  Offset _gestureBaseOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
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

  /// Плавный зум без фокусной точки (кнопки «+/-» и слайдер).
  void _zoomStep(double delta) {
    _setScale(_scale + delta);
  }

  /// Установка масштаба из слайдера/кнопок. При возврате к 100%
  /// изображение снова центрируется.
  void _setScale(double value) {
    setState(() {
      _scale = value.clamp(_minScale, _maxScale);
      if (_scale <= _minScale + 0.001) {
        _offset = Offset.zero;
      }
    });
  }

  /// Зум колесиком мыши с фокусом на позиции курсора: точка под курсором
  /// остаётся на месте (как в классическом просмотрщике Windows).
  void _zoomAtPoint(Offset cursor, double sizeDelta, Size areaSize) {
    final newScale = (_scale * (1.0 + sizeDelta)).clamp(_minScale, _maxScale);
    if (newScale == _scale) return;
    final center = areaSize.center(Offset.zero);
    setState(() {
      // screen = center + (point - center) * scale + offset
      // Фиксируем точку под курсором: offset' = offset - (cursor - center) * (new - old)
      _offset -= (cursor - center) * (newScale - _scale);
      _scale = newScale;
      if (_scale <= _minScale + 0.001) {
        _offset = Offset.zero;
      } else {
        _offset = _clampedOffset(_offset, areaSize);
      }
    });
  }

  /// Ограничение смещения — изображение нельзя «потерять» за краями экрана.
  Offset _clampedOffset(Offset offset, Size areaSize) {
    final maxDx = areaSize.width * 0.5 * (_scale - 1) + areaSize.width * 0.25;
    final maxDy = areaSize.height * 0.5 * (_scale - 1) + areaSize.height * 0.25;
    return Offset(
      offset.dx.clamp(-maxDx, maxDx),
      offset.dy.clamp(-maxDy, maxDy),
    );
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
    } else if (event.logicalKey == LogicalKeyboardKey.equal ||
        event.logicalKey == LogicalKeyboardKey.numpadAdd) {
      _zoomStep(0.5);
    } else if (event.logicalKey == LogicalKeyboardKey.minus ||
        event.logicalKey == LogicalKeyboardKey.numpadSubtract) {
      _zoomStep(-0.5);
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
            // Зона изображения: колесо мыши — зум, drag — панорамирование.
            LayoutBuilder(
              builder: (context, constraints) {
                final areaSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                // Listener растягивается на всю зону — колесо работает
                // в любой точке экрана, а не только над картинкой.
                return Listener(
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent) {
                      // Один «щелчок» колеса ≈ ±25% масштаба.
                      final delta = -event.scrollDelta.dy / 400.0;
                      _zoomAtPoint(event.localPosition, delta, areaSize);
                    }
                  },
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    // Центр задаёт изображению границы зоны просмотра.
                    child: Center(
                      child: GestureDetector(
                        onScaleStart: (details) {
                          // Запоминаем состояние — масштаб сохраняется при drag.
                          _gestureBaseScale = _scale;
                          _gestureBaseOffset = _offset;
                        },
                        onScaleUpdate: (details) {
                          if (_scale <= _minScale && details.scale == 1.0) {
                            // На 100% панорамирование не нужно (как в Windows).
                            return;
                          }
                          setState(() {
                            _scale = (_gestureBaseScale * details.scale)
                                .clamp(_minScale, _maxScale);
                            _offset = _clampedOffset(
                              _gestureBaseOffset + details.focalPointDelta,
                              areaSize,
                            );
                          });
                        },
                        onDoubleTap: () => _setScale(_minScale),
                        child: Transform.translate(
                          offset: _offset,
                          child: Transform.scale(
                            scale: _scale,
                            child: _ImagePreview(path: _current.path),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            // Верхняя панель: заголовок и закрытие («крестик»).
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _current.title,
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

            // Нижняя панель: полоска масштабирования + метаданные.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: Colors.black54,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Уменьшить',
                      icon: const Icon(Icons.zoom_out, color: Colors.white),
                      onPressed: () => _zoomStep(-0.5),
                    ),
                    // Полоска масштабирования (как в классических
                    // просмотрщиках): 100% — 800%.
                    SizedBox(
                      width: 180,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 12,
                          ),
                        ),
                        child: Slider(
                          value: _scale,
                          min: _minScale,
                          max: _maxScale,
                          label: '${(_scale * 100).round()}%',
                          onChanged: _setScale,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Увеличить',
                      icon: const Icon(Icons.zoom_in, color: Colors.white),
                      onPressed: () => _zoomStep(0.5),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(
                        '${(_scale * 100).round()}%',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Сбросить масштаб (двойной клик)',
                      icon: const Icon(
                        Icons.fit_screen_outlined,
                        color: Colors.white,
                      ),
                      onPressed: () => _setScale(_minScale),
                    ),
                    const Spacer(),
                    Text(
                      '${_current.width ?? '?'} × ${_current.height ?? '?'}'
                      ' · ${_current.format ?? ''}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
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

/// Превью изображения.
///
/// ВАЖНО: без InteractiveViewer — он конфликтует с внешним
/// Transform/GestureDetector (двойное панорамирование и «дёрганье»).
/// Вся логика зума и переноса живёт в [_LightboxViewerState].
class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(path),
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.white54),
      ),
    );
  }
}
