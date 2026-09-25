import 'dart:ui';

import 'package:flutter/material.dart';

/// Дизайн-система интерфейса приложения.
///
/// Пользователь выбирает оформление в Настройках. Каждая дизайн-система
/// существует в светлой и тёмной версии — см. [AppTheme.themeFor].
enum AppDesignSystem {
  /// Material Design 3 (как было в приложении изначально).
  /// Opaque-панели, classic M3-палитра, скруглённые углы 8px.
  material,

  /// iOS-style с матовым стеклом (frosted glass): панели полупрозрачные,
  /// поверх — `BackdropFilter` с гауссовым размытием. Скруглённые углы 16px.
  iosFrosted,

  /// iOS-style с прозрачными панелями (без размытия): панели просто
  /// полупрозрачные, фоновый градиент просвечивает напрямую.
  iosTransparent,
}

/// Настройки тем приложения «коробка».
///
/// Предоставляет 6 тем (3 дизайн-системы × 2 яркости), а также фоновые цвета
/// панелей, имитирующие оформление Eagle для Material и iOS-стиль — для двух
/// остальных.
class AppTheme {
  const AppTheme._();

  /// Базовый акцентный цвет интерфейса (Material).
  static const Color seedColor = Color(0xFF5B6CFF);

  /// Акцент iOS — системный «синий Apple» (≈ #007AFF).
  static const Color iosAccent = Color(0xFF007AFF);

  /// Устаревший геттер светлой Material-темы — оставлен для обратной
  /// совместимости (использовался в `main.dart` до появления [themeFor]).
  /// В новом коде используйте `AppTheme.themeFor(design, brightness)`.
  static ThemeData get light => _materialLight;

  /// Устаревший геттер тёмной Material-темы — аналогично [light].
  static ThemeData get dark => _materialDark;

  /// Возвращает готовую [ThemeData] для заданных дизайн-системы и яркости.
  static ThemeData themeFor(AppDesignSystem design, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    switch (design) {
      case AppDesignSystem.material:
        return isDark ? _materialDark : _materialLight;
      case AppDesignSystem.iosFrosted:
        return isDark ? _iosFrostedDark : _iosFrostedLight;
      case AppDesignSystem.iosTransparent:
        return isDark ? _iosTransparentDark : _iosTransparentLight;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  //  MATERIAL
  // ─────────────────────────────────────────────────────────────────────

  static ThemeData get _materialLight {
    final scheme = ColorScheme.fromSeed(seedColor: seedColor);
    return _buildMaterial(
      scheme: scheme,
      panelColor: const Color(0xFFF2F3F5),
      contentBackground: const Color(0xFFFFFFFF),
    );
  }

  static ThemeData get _materialDark {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );
    return _buildMaterial(
      scheme: scheme,
      panelColor: const Color(0xFF2A2D34),
      contentBackground: const Color(0xFF1E1F24),
    );
  }

  static ThemeData _buildMaterial({
    required ColorScheme scheme,
    required Color panelColor,
    required Color contentBackground,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: contentBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: panelColor,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      extensions: [
        PanelColors(
          panel: panelColor,
          contentBackground: contentBackground,
        ),
        _DesignSystemExtension(design: AppDesignSystem.material),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  //  iOS FROSTED GLASS
  // ─────────────────────────────────────────────────────────────────────
  //
  //  Стекло видно только тогда, когда за панелью что-то есть. Поэтому
  //  scaffold-фон здесь — мягкий градиент, а панели — белые/чёрные
  //  с прозрачностью 60-70%, поверх BackdropFilter с σ ≈ 30 px.

  static ThemeData get _iosFrostedLight {
    final scheme = ColorScheme.fromSeed(
      seedColor: iosAccent,
      brightness: Brightness.light,
    );
    return _buildIos(
      scheme: scheme,
      brightness: Brightness.light,
      design: AppDesignSystem.iosFrosted,
      panelColor: const Color(0xCCFFFFFF), // white 80%
      contentBackground: const Color(0xB3FFFFFF), // white 70%
      wallpaper: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFE3ECFF), // soft sky
          Color(0xFFFFE3F1), // pinkish
          Color(0xFFE8FFE3), // mint
        ],
      ),
      blurSigma: 30.0,
      blurEnabled: true,
    );
  }

  static ThemeData get _iosFrostedDark {
    final scheme = ColorScheme.fromSeed(
      seedColor: iosAccent,
      brightness: Brightness.dark,
    );
    return _buildIos(
      scheme: scheme,
      brightness: Brightness.dark,
      design: AppDesignSystem.iosFrosted,
      panelColor: const Color(0xCC1C1C1E), // iOS dark gray 80%
      contentBackground: const Color(0xB31C1C1E),
      wallpaper: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF1A1A2E),
          Color(0xFF16213E),
          Color(0xFF0F1C2E),
        ],
      ),
      blurSigma: 30.0,
      blurEnabled: true,
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  //  iOS TRANSPARENT
  // ─────────────────────────────────────────────────────────────────────
  //
  //  Те же полупрозрачные панели, но без BackdropFilter — фоновый градиент
  //  просвечивает напрямую, без размытия. Эффект «лёгкого тинта».

  static ThemeData get _iosTransparentLight {
    final scheme = ColorScheme.fromSeed(
      seedColor: iosAccent,
      brightness: Brightness.light,
    );
    return _buildIos(
      scheme: scheme,
      brightness: Brightness.light,
      design: AppDesignSystem.iosTransparent,
      panelColor: const Color(0x66FFFFFF), // white 40%
      contentBackground: const Color(0x33FFFFFF), // white 20%
      wallpaper: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFD1DC),
          Color(0xFFC1E8FF),
          Color(0xFFFFE7BA),
        ],
      ),
      blurSigma: 0.0,
      blurEnabled: false,
    );
  }

  static ThemeData get _iosTransparentDark {
    final scheme = ColorScheme.fromSeed(
      seedColor: iosAccent,
      brightness: Brightness.dark,
    );
    return _buildIos(
      scheme: scheme,
      brightness: Brightness.dark,
      design: AppDesignSystem.iosTransparent,
      panelColor: const Color(0x661C1C1E),
      contentBackground: const Color(0x331C1C1E),
      wallpaper: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF2C0735),
          Color(0xFF0B1D3F),
          Color(0xFF1A0B2E),
        ],
      ),
      blurSigma: 0.0,
      blurEnabled: false,
    );
  }

  static ThemeData _buildIos({
    required ColorScheme scheme,
    required Brightness brightness,
    required AppDesignSystem design,
    required Color panelColor,
    required Color contentBackground,
    required Gradient wallpaper,
    required double blurSigma,
    required bool blurEnabled,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Scaffold сам по себе прозрачный — под ним Stack с wallpaper-градиентом.
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: panelColor,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          // SF-style fallback на системный шрифт Apple-платформ.
          fontFamily: '-apple-system',
          fontFamilyFallback: const ['Inter', 'Roboto', 'Segoe UI'],
        ),
      ),
      // Бóльшие скругления, как в iOS. CardTheme (а не CardThemeData)
      // для совместимости со старыми Flutter 3.x.
      cardTheme: const CardTheme(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
      // Полупрозрачный фон у диалогов — фоновый градиент слегка
      // просвечивает, сохраняя «воздушный» iOS-look. DialogTheme (а не
      // DialogThemeData) — для совместимости со старыми Flutter 3.x.
      dialogTheme: DialogTheme(
        backgroundColor: brightness == Brightness.light
            ? const Color(0xF2FFFFFF)
            : const Color(0xF21C1C1E),
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      extensions: [
        PanelColors(
          panel: panelColor,
          contentBackground: contentBackground,
        ),
        _DesignSystemExtension(
          design: design,
          wallpaper: wallpaper,
          blurSigma: blurSigma,
          blurEnabled: blurEnabled,
        ),
      ],
    );
  }
}

/// Расширение темы: дизайн-система + параметры стекла.
///
/// Используется [FrostedPanel] для решения, нужен ли [BackdropFilter]
/// и какая интенсивность размытия. [wallpaper] рисуется под scaffold-ом
/// в [FrostedScaffoldBackground].
class _DesignSystemExtension
    extends ThemeExtension<_DesignSystemExtension> {
  const _DesignSystemExtension({
    required this.design,
    this.wallpaper,
    this.blurSigma = 0,
    this.blurEnabled = false,
  });

  final AppDesignSystem design;
  final Gradient? wallpaper;
  final double blurSigma;
  final bool blurEnabled;

  @override
  _DesignSystemExtension copyWith({
    AppDesignSystem? design,
    Gradient? wallpaper,
    double? blurSigma,
    bool? blurEnabled,
  }) {
    return _DesignSystemExtension(
      design: design ?? this.design,
      wallpaper: wallpaper ?? this.wallpaper,
      blurSigma: blurSigma ?? this.blurSigma,
      blurEnabled: blurEnabled ?? this.blurEnabled,
    );
  }

  @override
  _DesignSystemExtension lerp(
      ThemeExtension<_DesignSystemExtension>? other, double t) {
    if (other is! _DesignSystemExtension) return this;
    return _DesignSystemExtension(
      design: t < 0.5 ? design : other.design,
      wallpaper: wallpaper,
      blurSigma: blurSigma + (other.blurSigma - blurSigma) * t,
      blurEnabled: t < 0.5 ? blurEnabled : other.blurEnabled,
    );
  }
}

/// Расширенные цвета панелей, доступные через контекст.
class PanelColors extends ThemeExtension<PanelColors> {
  const PanelColors({
    required this.panel,
    required this.contentBackground,
  });

  /// Резервная палитра для случая, когда тема не задаёт расширение
  /// (например, сторонний MaterialApp без AppTheme) — раньше падало
  /// с «Null check operator used on a null value».
  factory PanelColors.fallback(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return PanelColors(
      panel: dark ? const Color(0xFF1E1F24) : const Color(0xFFF3F3F5),
      contentBackground: dark ? const Color(0xFF161719) : Colors.white,
    );
  }

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
      Theme.of(this).extension<PanelColors>() ??
      PanelColors.fallback(Theme.of(this).brightness);

  /// Дизайн-система, выбранная пользователем (с fallback на Material).
  AppDesignSystem get designSystem =>
      Theme.of(this).extension<_DesignSystemExtension>()?.design ??
      AppDesignSystem.material;

  /// Параметры стекла: нужен ли [BackdropFilter] и какой силы.
  bool get backdropBlurEnabled =>
      Theme.of(this).extension<_DesignSystemExtension>()?.blurEnabled ?? false;

  double get backdropBlurSigma =>
      Theme.of(this).extension<_DesignSystemExtension>()?.blurSigma ?? 0;

  /// Декоративный градиент-фон под стеклянными панелями (только для iOS-тем).
  Gradient? get wallpaper =>
      Theme.of(this).extension<_DesignSystemExtension>()?.wallpaper;
}

/// Виджет-«стекло»: оборачивает ребёнка [BackdropFilter] + полупрозрачным
/// фоном, если выбрана iOS-тема. Для Material — просто [Material] без изменений.
///
/// Используется в [LeftPanel], [RightPanel], [ContentArea] и AppBar-обёртке
/// в [MainScreen].
class FrostedPanel extends StatelessWidget {
  const FrostedPanel({
    super.key,
    required this.child,
    this.color,
    this.borderRadius = 0,
    this.shape,
  });

  final Widget child;

  /// Цвет фона панели. Если не задан — берётся из [PanelColors.panel].
  final Color? color;

  /// Скругление углов (для стекла применяется через Clip).
  final double borderRadius;

  /// Альтернативно [borderRadius] — кастомная форма.
  final ShapeBorder? shape;

  @override
  Widget build(BuildContext context) {
    final isGlass = context.backdropBlurEnabled ||
        context.designSystem != AppDesignSystem.material;
    final baseColor = color ?? context.panelColors.panel;

    // Material нужен ВСЕГДА — он даёт InkWell-рипплы для ListTile/IconButton
    // внутри панелей. Для iOS-тем Material делаем полупрозрачным, а поверх
    // (снаружи) навешиваем BackdropFilter.
    Widget panel = Material(
      color: baseColor,
      shape: shape,
      child: child,
    );

    if (isGlass && context.backdropBlurEnabled && context.backdropBlurSigma > 0) {
      // iOS Frosted: blur «за» полупрозрачной панелью.
      panel = BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: context.backdropBlurSigma,
          sigmaY: context.backdropBlurSigma,
          tileMode: TileMode.mirror,
        ),
        child: panel,
      );
    }

    if (borderRadius > 0) {
      panel = ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: panel,
      );
    }

    return panel;
  }
}

/// Рисует декоративный градиент (wallpaper) под всем контентом окна.
///
/// Используется только в iOS-темах, чтобы полупрозрачные панели имели
/// «что размывать» и эффект стекла был визуально заметен. Для Material
/// отрисовывается прозрачный контейнер (никакого вклада в верстку).
class FrostedScaffoldBackground extends StatelessWidget {
  const FrostedScaffoldBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wallpaper = context.wallpaper;
    if (wallpaper == null) return child;

    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: wallpaper),
          ),
        ),
        child,
      ],
    );
  }
}
