import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/liquid_glass_tokens.dart';

/// Показывает контекстное меню с эффектом матового стекла (glassmorphism).
///
/// В отличие от стандартного [showMenu], этот вариант оборачивает меню в
/// [BackdropFilter] — фон за меню размывается (σ = 28px), поверх —
/// полупрозрачная заливка стекла + тонкая граница + мягкая тень.
///
/// Используется в дизайн-системе iOS 27 / Liquid Glass для контекстных
/// меню (правый клик / long-press на элементе коллекции или папке).
///
/// Совместима по API со стандартным [showMenu] — принимает те же
/// `items` (PopupMenuItem / CheckedPopupMenuItem) и возвращает выбранное
/// значение через [Future].
Future<T?> showGlassMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  T? initialValue,
  double? elevation,
  String? semanticLabel,
}) {
  // Только для Liquid Glass используется эффект стекла.
  // Для остальных тем — fallback на стандартный showMenu.
  final isGlass = context.designSystem == AppDesignSystem.iosLiquidGlass;
  if (!isGlass) {
    return showMenu<T>(
      context: context,
      position: position,
      items: items,
      initialValue: initialValue,
      elevation: elevation,
      semanticLabel: semanticLabel,
    );
  }

  final brightness = Theme.of(context).brightness;
  final screenSize = MediaQuery.sizeOf(context);

  // Вычисляем позицию в абсолютных координатах.
  final left = position.left;
  final top = position.top;

  // Примерная ширина меню (Flutter по умолчанию _kMenuMaxWidth = 5*56).
  const menuWidth = 280.0;
  // Примерная высота: 48px на пункт + padding.
  final menuHeight = items.length * 48.0 + 16;

  // Корректируем позицию чтобы меню не выходило за пределы экрана.
  final adjustedLeft = (left + menuWidth > screenSize.width)
      ? (screenSize.width - menuWidth - 8).clamp(8.0, screenSize.width)
      : left;
  final adjustedTop = (top + menuHeight > screenSize.height)
      ? (screenSize.height - menuHeight - 8).clamp(8.0, screenSize.height)
      : top;

  return showDialog<T>(
    context: context,
    barrierColor: Colors.transparent,
    useRootNavigator: true,
    builder: (dialogContext) {
      return Stack(
        children: [
          // Полупрозрачный барьер: захватывает тапы вне меню для закрытия.
          GestureDetector(
            onTap: () => Navigator.of(dialogContext).pop(),
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
          // Меню в позиции курсора.
          Positioned(
            left: adjustedLeft,
            top: adjustedTop,
            child: _GlassMenuContainer<T>(
              brightness: brightness,
              items: items,
            ),
          ),
        ],
      );
    },
  );
}

/// Контейнер меню с эффектом матового стекла.
///
/// Порядок слоёв (снизу вверх):
///   1. BackdropFilter — размытие фона приложения за меню.
///   2. Material — полупрозрачная заливка стекла ( glassFillColor).
///   3. Граница 1px ( glassBorderColor).
///   4. Мягкая тень «парения».
///   5. Элементы меню ( PopupMenuItem / CheckedPopupMenuItem / divider).
///
/// PopupMenuItem вызывает Navigator.pop(context, value) при тапе —
/// это закрывает showDialog и возвращает выбранное значение.
class _GlassMenuContainer<T> extends StatelessWidget {
  const _GlassMenuContainer({
    required this.brightness,
    required this.items,
  });

  final Brightness brightness;
  final List<PopupMenuEntry<T>> items;

  @override
  Widget build(BuildContext context) {
    final fill = glassFillColor(brightness);
    final border = glassBorderColor(brightness);
    const radius = RadiusTokens.medium;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: GlassTokens.blurMedium,
          sigmaY: GlassTokens.blurMedium,
          tileMode: TileMode.mirror,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: border, width: 1),
            boxShadow: glassShadow(brightness),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: items.cast<Widget>().toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
