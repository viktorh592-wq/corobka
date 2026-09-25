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

    // iOS-темы: оборачиваем диалог в BackdropFilter + ClipRRect.
    // Если blurEnabled=false (Transparent), берём просто ColoredBox
    // с полупрозрачным фоном.
    Widget wrapped = Material(
      type: MaterialType.transparency,
      child: dialog,
    );

    if (blurOn) {
      wrapped = BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: context.backdropBlurSigma,
          sigmaY: context.backdropBlurSigma,
          tileMode: TileMode.mirror,
        ),
        child: ColoredBox(
          color: dialogBg,
          child: dialog,
        ),
      );
    } else {
      wrapped = ColoredBox(
        color: dialogBg,
        child: dialog,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: wrapped,
    );
  }
}
