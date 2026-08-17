import 'package:flutter/material.dart';

/// Настройки тем приложения «коробка».
///
/// Предоставляет светлую и тёмную темы, а также фоновые цвета панелей,
/// имитирующие оформление Eagle.
class AppTheme {
  const AppTheme._();

  /// Базовый акцентный цвет интерфейса.
  static const Color seedColor = Color(0xFF5B6CFF);

  /// Светлая тема.
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(seedColor: seedColor);
    return _build(
      scheme: scheme,
      panelColor: const Color(0xFFF2F3F5),
      contentBackground: const Color(0xFFFFFFFF),
    );
  }

  /// Тёмная тема.
  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );
    return _build(
      scheme: scheme,
      panelColor: const Color(0xFF2A2D34),
      contentBackground: const Color(0xFF1E1F24),
    );
  }

  static ThemeData _build({
    required ColorScheme scheme,
    required Color panelColor,
    required Color contentBackground,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: contentBackground,
      extensions: [
        PanelColors(
          panel: panelColor,
          contentBackground: contentBackground,
        ),
      ],
    );
  }
}

/// Расширенные цвета панелей, доступные через контекст.
class PanelColors extends ThemeExtension<PanelColors> {
  const PanelColors({
    required this.panel,
    required this.contentBackground,
  });

  /// Цвет левой и правой панелей.
  final Color panel;

  /// Цвет центральной области контента.
  final Color contentBackground;

  @override
  PanelColors copyWith({Color? panel, Color? contentBackground}) {
    return PanelColors(
      panel: panel ?? this.panel,
      contentBackground: contentBackground ?? this.contentBackground,
    );
  }

  @override
  PanelColors lerp(ThemeExtension<PanelColors>? other, double t) {
    if (other is! PanelColors) return this;
    return PanelColors(
      panel: Color.lerp(panel, other.panel, t)!,
      contentBackground:
          Color.lerp(contentBackground, other.contentBackground, t)!,
    );
  }
}

/// Удобный доступ к цветам панелей из контекста.
extension PanelColorsX on BuildContext {
  PanelColors get panelColors =>
      Theme.of(this).extension<PanelColors>()!;
}