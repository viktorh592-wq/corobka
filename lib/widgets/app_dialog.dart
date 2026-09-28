import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Единое модальное окно приложения «коробка».
///
/// От обычного [AlertDialog] отличается тем, что в правом верхнем углу
/// заголовка всегда есть кнопка-«крестик» для закрытия (поведение
/// классических десктопных диалогов). Крестик закрывает окно без
/// результата — как кнопка «Отмена».
///
/// В iOS-темах (Frosted / Transparent) дополнительно оборачивается в
/// [BackdropFilter] — получается настоящий эффект матового стекла, а не
/// просто полупрозрачный фон.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.content,
    this.actions,
  });

  /// Заголовок окна.
  final String title;

  /// Содержимое окна (опционально).
  final Widget? content;

  /// Кнопки действий внизу окна (опционально).
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final isGlass = context.designSystem != AppDesignSystem.material;
    final blurOn = context.backdropBlurEnabled && context.backdropBlurSigma > 0;
    final brightness = Theme.of(context).brightness;
    final dialogBg = brightness == Brightness.light
        ? const Color(0xF2FFFFFF)
        : const Color(0xF21C1C1E);

    final dialog = AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 18, 8, 0),
      // В iOS-темах фон задаём сами (через BackdropFilter ниже),
      // а для AlertDialog — прозрачный, иначе двойная заливка.
      backgroundColor: isGlass ? Colors.transparent : dialogBg,
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton(
            tooltip: 'Закрыть',
            icon: const Icon(Icons.close, size: 22),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: content,
      actions: actions,
    );

    if (!isGlass) return dialog;

    // iOS-темы: glass dialog с border 1px + мягкой тенью.
    //
    // Порядок слоёв (снизу вверх):
    //   1. BackdropFilter (размытие wallpaper-градиента под диалогом)
    //   2. ColoredBox(dialogBg) — полупрозрачная заливка стекла
    //   3. AlertDialog (content + actions)
    //   4. ClipRRect(18) — скругление углов всего «стекла»
    //   5. Container(decoration) — внешняя граница + тень поверх скругления
    //      (border и shadow рисуются снаружи ClipRRect, чтобы не обрезаться)
    Widget glass = ColoredBox(
      color: dialogBg,
      child: dialog,
    );

    if (blurOn) {
      glass = BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: context.backdropBlurSigma,
          sigmaY: context.backdropBlurSigma,
          tileMode: TileMode.mirror,
        ),
        child: glass,
      );
    }

    // Скругление углов всего «стекла» — backdrop + fill + content
    // обрезаются по одному радиусу 18px.
    glass = ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: glass,
    );

    // Внешний декор: тонкая граница 1px (та же, что у панелей) +
    // мягкая тень, чтобы диалог визуально отделялся от затемнённого
    // фона showModal. Тень рисуется снаружи скругления — Flutter
    // отрисовывает boxShadow поверх child даже при color: transparent.
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.panelBorderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: brightness == Brightness.dark
                ? Colors.black.withValues(alpha: 0.45)
                : Colors.black.withValues(alpha: 0.20),
            blurRadius: 24,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: glass,
    );
  }
}
