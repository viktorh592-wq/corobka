import 'dart:ui';

import 'package:flutter/material.dart';

import 'liquid_glass_tokens.dart';

/// Дизайн-система интерфейса приложения.
///
/// Пользователь выбирает оформление в Настройках. Каждая дизайн-система
/// существует в светлой и тёмной версии — см. [AppTheme.themeFor].
enum AppDesignSystem {
  /// Material Design 3 (как было в приложении изначально).
  /// Opaque-панели, classic M3-палитра, скруглённые углы 8px.
  material,

  /// iOS-style с прозрачными панелями (без размытия): панели просто
  /// полупрозрачные, фоновый градиент просвечивает напрямую.
  iosTransparent,

  /// iOS 27 / Liquid Glass — целевая дизайн-система по гайдлайну
  /// COROBKA_iOS27_LiquidGlass_UI_GUIDELINE.md.
  ///
  /// Принципиальные отличия от iosTransparent:
  ///   • НЕТ глобального frosting-слоя на всё окно — контент (изображения)
  ///     остаётся резким и доминирует (§2.1, §25 гайдлайна).
  ///   • Стекло — только функциональный слой: тулбар, поиск, кнопки,
  ///     диалоги, popover-меню, тема-переключатель (§5.1).
  ///   • Централизованные токены — см. [GlassTokens], [MotionTokens],
  ///     [RadiusTokens] в `liquid_glass_tokens.dart`.
  ///   • Капсульные/концентрические радиусы, мягкие тени, subtle edge.
  ///   • Тема-переключатель — отдельный виджет со скользящим knob-ом
  ///     (см. `LiquidGlassThemeToggle`).
  iosLiquidGlass,

  /// Тёмный неоморфизм / Ambient Smart Home — 4-я дизайн-система
  /// по спецификации `docs/design/thermostat_neon_design_spec.json`
  /// (попиксельно снятой с референсов: круговой термостат с неоновой
  /// дугой-крутилкой + сегментный переключатель Auto/Cool/Heat).
  ///
  /// Характеристики (§ спецификации):
  ///   • Фон страницы — радиальный градиент (свет сверху-слева):
  ///     #31334A → #292C3B → #1F222C → #181B24.
  ///   • Панели — приподнятая поверхность циферблата #20242F; контентная
  ///     область — «желобок» #171B26; recessed-вставки #14171F.
  ///   • Неоновый фиолетовый #926AF8 — акцент активных контролов;
  ///     активная кнопка-капсула с вертикальным градиентом
  ///     #C1A7FE → #A17BFC и ТЁМНЫМ текстом #180344 (как «Auto»);
  ///     неактивные элементы — текст #A7ABBD без заливки.
  ///   • Лавандовое свечение #DADAFB, бирюзовые индикаторы #51BFE5.
  ///   • ВАЖНОЕ ПРАВИЛО (от заказчика): ПРЯМЫЕ ЛИНИИ НЕ СКРУГЛЯЮТСЯ —
  ///     разделители, границы и треки-линии остаются острыми
  ///     (BorderRadius.zero у линейных индикаторов); скругления —
  ///     только у кнопок, карточек, панелей и других «объёмных»
  ///     элементов.
  neumorphicSmartHome,
}

/// Настройки тем приложения «коробка».
///
/// Предоставляет 8 тем (4 дизайн-системы × 2 яркости), а также фоновые цвета
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
      case AppDesignSystem.iosTransparent:
        return isDark ? _iosTransparentDark : _iosTransparentLight;
      case AppDesignSystem.iosLiquidGlass:
        return isDark ? _iosLiquidGlassDark : _iosLiquidGlassLight;
      case AppDesignSystem.neumorphicSmartHome:
        return isDark ? _neumorphicSmartHomeDark : _neumorphicSmartHomeLight;
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
        const _DesignSystemExtension(
          design: AppDesignSystem.material,
        ),
      ],
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

  // ─────────────────────────────────────────────────────────────────────
  //  iOS 27 / LIQUID GLASS
  // ─────────────────────────────────────────────────────────────────────
  //
  //  Целевая дизайн-система по гайдлайну COROBKA_iOS27_LiquidGlass.
  //
  //  Принципиальные отличия от iosTransparent:
  //    • scaffold — НЕ прозрачный. Под контентом — opaque цвет (без
  //      wallpaper-градиента). Контент остаётся резким (§2.1, §25).
  //    • панели (left / right) — слегка translucent, но НЕ размываются
  //      BackdropFilter-ом. Только subtle edge + мягкая тень.
  //    • BackdropFilter применяется только к маленьким контролам через
  //      [LiquidGlassSurface] (тулбар, поиск, диалоги, popover).
  //    • Тематическая палитра сохраняет iOS-синий (#007AFF), но без
  //      wallpaper — фон однотонный, нейтральный.

  static ThemeData get _iosLiquidGlassLight {
    final scheme = ColorScheme.fromSeed(
      seedColor: iosAccent,
      brightness: Brightness.light,
    );
    return _buildLiquidGlass(
      scheme: scheme,
      brightness: Brightness.light,
      // Контентная область — opaque, БЕЗ wallpaper под ней (§2.1).
      // Очень светлый нейтральный, как iOS systemGroupedBackground.
      contentBackground: const Color(0xFFF2F2F7),
      // Боковые панели — чуть темнее контента, чтобы читалась граница,
      // но НЕ прозрачные к wallpaper (его нет).
      panelColor: const Color(0xFFE5E5EA),
    );
  }

  static ThemeData get _iosLiquidGlassDark {
    final scheme = ColorScheme.fromSeed(
      seedColor: iosAccent,
      brightness: Brightness.dark,
    );
    return _buildLiquidGlass(
      scheme: scheme,
      brightness: Brightness.dark,
      // iOS systemGroupedBackground (dark).
      contentBackground: const Color(0xFF000000),
      // Боковые панели — systemGray6 (dark), чуть светлее контента.
      panelColor: const Color(0xFF1C1C1E),
    );
  }

  static ThemeData _buildLiquidGlass({
    required ColorScheme scheme,
    required Brightness brightness,
    required Color panelColor,
    required Color contentBackground,
  }) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // scaffold — opaque. Никакого wallpaper, никакой прозрачности.
      // Контент (изображения) остаётся резким — §2.1, §25 гайдлайна.
      scaffoldBackgroundColor: contentBackground,
      appBarTheme: AppBarTheme(
        // AppBar сам по себе прозрачный — стекло рендерит flexibleSpace
        // в MainScreen._buildAppBar (через LiquidGlassSurface).
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          fontFamily: '-apple-system',
          fontFamilyFallback: const ['Inter', 'Roboto', 'Segoe UI'],
        ),
      ),
      // Карточки — без стекла (изображения = контент, не «стеклянные плитки»).
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(RadiusTokens.medium)),
        ),
      ),
      // Текстовые поля — стекло только для ПОЛЯ (одна поверхность на
      // поле, без вложенных стекол, §19). Реальная glass-обёртка
      // добавляется виджетом LiquidGlassSurface в местах использования.
      // Скругление углов — небольшое (8px), как в Material Design:
      // капсульная форма (capsule/999) выглядела слишком «слипшейся».
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: glassFillColor(brightness),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: glassBorderColor(brightness),
            width: 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: glassBorderColor(brightness),
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: scheme.primary.withValues(alpha: 0.8),
            width: 1.6,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      // Диалоги — glass surface. Полная реализация в [AppDialog]:
      // BackdropFilter + translucent fill + border + soft shadow.
      dialogTheme: DialogThemeData(
        backgroundColor: glassFillColor(brightness),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RadiusTokens.large),
          side: BorderSide(color: glassBorderColor(brightness), width: 1),
        ),
      ),
      // Контекстные меню (PopupMenu) — тоже стекло.
      popupMenuTheme: PopupMenuThemeData(
        color: glassFillColor(brightness),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RadiusTokens.medium),
          side: BorderSide(color: glassBorderColor(brightness), width: 1),
        ),
      ),
      // SnackBar — маленький floating glass toast.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: glassFillColor(brightness),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RadiusTokens.medium),
          side: BorderSide(color: glassBorderColor(brightness), width: 1),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: glassFillColor(brightness),
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(RadiusTokens.large),
            topRight: Radius.circular(RadiusTokens.large),
          ),
        ),
      ),
      // Кнопки с заливкой — capsule, акцентный цвет с лёгкой прозрачностью.
      filledButtonTheme: FilledButtonThemeData(
        style: liquidGlassButtonStyle(
          brightness: brightness,
          prominent: true,
        ),
      ),
      // TextButton — capsule glass secondary (для «Импорт», «Папка» и т.д.).
      textButtonTheme: TextButtonThemeData(
        style: liquidGlassButtonStyle(brightness: brightness),
      ),
      // OutlinedButton — тоже capsule glass (в старых темах у него был
      // outlined border, здесь он не нужен — границу рисует сам glass).
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: liquidGlassButtonStyle(brightness: brightness),
      ),
      // Карточки — opaque, не стекло (контент = контент).
      cardColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      // Chip-ы — capsule glass.
      chipTheme: ChipThemeData(
        backgroundColor: glassFillColor(brightness),
        side: BorderSide(color: glassBorderColor(brightness), width: 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RadiusTokens.capsule),
        ),
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        selectedColor: scheme.primary.withValues(alpha: 0.20),
        checkmarkColor: scheme.primary,
      ),
      // Divider — тонкий, нейтральный.
      dividerTheme: DividerThemeData(
        color: glassBorderColor(brightness),
        thickness: 0.5,
        space: 1,
      ),
      extensions: [
        PanelColors(
          panel: panelColor,
          contentBackground: contentBackground,
        ),
        const _DesignSystemExtension(
          design: AppDesignSystem.iosLiquidGlass,
          // Нет wallpaper — FrostedScaffoldBackground вернёт child как есть.
          wallpaper: null,
          // Нет глобального blur — BackdropFilter только в LiquidGlassSurface.
          blurSigma: 0,
          blurEnabled: false,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  //  НЕОМОРФИЗМ · SMART HOME (4-я дизайн-система)
  // ─────────────────────────────────────────────────────────────────────
  //
  //  По спецификации docs/design/thermostat_neon_design_spec.json
  //  (попиксельный замер референсов «умного дома»).
  //
  //  Принципы:
  //    •Raised/recessed поверхности БЕЗ жёстких границ — глубина
  //      создаётся широкими мягкими тенями и подсветками (как у
  //      циферблата: желобки, фаски, светящиеся кольца).
  //    • Неоновый фиолетовый #926AF8 — акцент активных контролов;
  //      активные кнопки — капсулы с вертикальным градиентом
  //      #C1A7FE → #A17BFC и тёмным текстом #180344.
  //    • ПРЯМЫЕ ЛИНИИ (разделители, границы, линейные индикаторы)
  //      НЕ скругляются — скругления только у «объёмных» элементов:
  //      кнопки, карточки, панели, поля, диалоги.
  //    • Тёмная версия — по спецификации; светлая — адаптация той же
  //      неоморфной системы (светлые поверхности + мягкие серые тени).

  /// Палитра тёмной версии (§ палитра_общая / циферблат спецификации).
  ///
  /// Источник — попиксельный замер референсов (см.
  /// docs/design/thermostat_neon_design_spec.json):
  ///   • фон: радиальный градиент #31334A → #292C3B → #1F222C → #181B24
  ///     (источник света сверху-слева, виньетка к низу-праву);
  ///   • панели/карточки — приподнятая поверхность #20242F,
  ///     блик-хребет #313443;
  ///   • контентная область и «ванны» — желобок #171B26, глубокая
  ///     recessed-вставка #14171F;
  ///   • неоновое ядро #926AF8, кнопочный градиент #C1A7FE → #A17BFC,
  ///     лаванда #DADAFB, бирюза #51BFE5.
  static const Color _neuPageBackground = Color(0xFF181B24);
  static const Color _neuPageBackgroundTopLeft = Color(0xFF31334A);
  static const Color _neuPageBackgroundTop = Color(0xFF292C3B);
  static const Color _neuPageBackgroundMid = Color(0xFF1F222C);
  static const Color _neuSurfaceBase = Color(0xFF20242F);
  static const Color _neuSurfaceHighlight = Color(0xFF313443);
  static const Color _neuSurfaceRecessed = Color(0xFF14171F);
  static const Color _neuContentWell = Color(0xFF171B26);
  static const Color _neuTextPrimary = Color(0xFFFDFEFF);
  static const Color _neuTextSecondary = Color(0xFFA7ABBD);
  static const Color _neuViolet = Color(0xFF926AF8);
  static const Color _neuVioletBright = Color(0xFFA17BFC);
  static const Color _neuVioletLight = Color(0xFFC1A7FE);
  static const Color _neuLavender = Color(0xFFDADAFB);
  static const Color _neuOnAccent = Color(0xFF180344);
  static const Color _neuCyan = Color(0xFF51BFE5);

  /// Радиальный градиент фона страницы (§ палитра_общая:
  /// «radial-gradient(120% 120% at 20% 0%, …)» спецификации).
  static RadialGradient get _neuWallpaper => const RadialGradient(
        center: Alignment(-0.6, -1.0), // ≈ 20% по горизонтали, 0% по вертикали
        radius: 1.5,
        colors: [
          _neuPageBackgroundTopLeft, // #31334A
          _neuPageBackgroundTop, //     #292C3B
          _neuPageBackgroundMid, //     #1F222C
          _neuPageBackground, //        #181B24
        ],
        stops: [0.0, 0.35, 0.65, 1.0],
      );

  /// Палитра светлой версии (адаптация той же системы).
  static const Color _neuLightPageBackground = Color(0xFFE4E9F2);
  static const Color _neuLightSurfaceBase = Color(0xFFEAEFF7);
  static const Color _neuLightSurfaceHighlight = Color(0xFFF6F8FC);
  static const Color _neuLightSurfaceRecessed = Color(0xFFD8DEE9);
  static const Color _neuLightTextPrimary = Color(0xFF1D2430);
  static const Color _neuLightTextSecondary = Color(0xFF5A6478);

  static ThemeData get _neumorphicSmartHomeDark {
    return _buildNeumorphic(
      brightness: Brightness.dark,
      pageBackground: _neuPageBackground,
      surfaceBase: _neuSurfaceBase,
      surfaceHighlight: _neuSurfaceHighlight,
      surfaceRecessed: _neuSurfaceRecessed,
      textPrimary: _neuTextPrimary,
      textSecondary: _neuTextSecondary,
      accent: _neuViolet,
    );
  }

  static ThemeData get _neumorphicSmartHomeLight {
    return _buildNeumorphic(
      brightness: Brightness.light,
      pageBackground: _neuLightPageBackground,
      surfaceBase: _neuLightSurfaceBase,
      surfaceHighlight: _neuLightSurfaceHighlight,
      surfaceRecessed: _neuLightSurfaceRecessed,
      textPrimary: _neuLightTextPrimary,
      textSecondary: _neuLightTextSecondary,
      accent: _neuViolet,
    );
  }

  static ThemeData _buildNeumorphic({
    required Brightness brightness,
    required Color pageBackground,
    required Color surfaceBase,
    required Color surfaceHighlight,
    required Color surfaceRecessed,
    required Color textPrimary,
    required Color textSecondary,
    required Color accent,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      // Активная кнопка-капсула — светло-фиолетовый градиент с ТЁМНЫМ
      // текстом (как «Auto» в референсе: #C1A7FE → #A17BFC + #180344).
      onPrimary: _neuOnAccent,
      secondary: _neuCyan,
      onSecondary: isDark
          ? const Color(0xFF0E2730)
          : const Color(0xFF0E3038),
      error: const Color(0xFFE5484D),
      onError: Colors.white,
      // Фоновые поверхности — неоморфные, без M3-тонирования.
      surface: surfaceBase,
      onSurface: textPrimary,
      surfaceContainerHighest: surfaceHighlight,
      surfaceContainerHigh: surfaceHighlight,
      surfaceContainer: surfaceBase,
      surfaceContainerLow: surfaceBase,
      surfaceContainerLowest: surfaceRecessed,
      onSurfaceVariant: textSecondary,
      outline: textSecondary.withValues(alpha: 0.35),
      outlineVariant: textSecondary.withValues(alpha: 0.18),
      primaryContainer: _neuVioletBright.withValues(alpha: 0.24),
      onPrimaryContainer: isDark
          ? _neuLavender // #DADAFB — лавандовое свечение из референса
          : const Color(0xFF4C2E92),
      secondaryContainer: _neuCyan.withValues(alpha: 0.20),
      onSecondaryContainer: isDark
          ? const Color(0xFF7FD4E8)
          : const Color(0xFF0B4C57),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Тёмная версия: scaffold ПРОЗРАЧНЫЙ — под ним виден радиальный
      // градиент-«обои» (_neuWallpaper: #31334A → #292C3B → #1F222C →
      // #181B24, свет сверху-слева), рисуемый FrostedScaffoldBackground.
      // Светлая версия: плоский светлый фон без обоев.
      scaffoldBackgroundColor:
          isDark ? Colors.transparent : pageBackground,
      appBarTheme: AppBarTheme(
        // AppBar прозрачный: стекло шапки рисует MainScreen
        // через flexibleSpace (ColoredBox поверх panelColors.panel).
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
          fontFamilyFallback: const ['SF Pro Display', 'Segoe UI', 'Roboto'],
        ),
      ),
      // Карточки — крупные радиусы 29px (§ циферблат: приподнятая
      // поверхность #20242F, как тело циферблата).
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: surfaceBase,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(29),
        ),
      ),
      // Текстовые поля — recessed-«углубления» без рамок.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceRecessed,
        hintStyle: TextStyle(color: textSecondary.withValues(alpha: 0.7)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: accent.withValues(alpha: 0.6)),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      // Диалоги — приподнятые неоморфные панели.
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceBase,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      // Контекстные меню — приподнятые поверхности, крупный радиус.
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceBase,
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: 0.34),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      // SnackBar — плавающая «пилюля».
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceHighlight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceBase,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      // Кнопки — активный контрол из референса: светло-фиолетовая
      // капсула (#A17BFC — середина градиента #C1A7FE → #A17BFC) с
      // ТЁМНЫМ текстом #180344 и мягким фиолетовым свечением.
      // (Полный вертикальный градиент накладывается в сегментных
      // переключателях — см. _SegmentRow в main_screen.dart; на
      // уровне темы берём плоский безопасный аналог середины градиента.)
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _neuVioletBright,
          foregroundColor: _neuOnAccent,
          // Мягкое неоновое свечение вокруг активной капсулы
          // (§ css_рецепты: box-shadow 0 0 … rgba(146,106,248,.45)).
          elevation: 2,
          shadowColor: _neuViolet.withValues(alpha: 0.45),
          surfaceTintColor: Colors.transparent,
          // Hover — осветление к верхнему тону градиента (#C1A7FE).
          overlayColor: _neuVioletLight.withValues(alpha: 0.22),
          shape: const StadiumBorder(), // капсула — только для «объёмных» элементов
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          // Неактивные подписи-кнопки — лаванда/серый текст без заливки
          // (как «Cool»/«Heat» в референсе).
          foregroundColor: isDark ? _neuLavender : const Color(0xFF6845C7),
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: BorderSide(color: textSecondary.withValues(alpha: 0.35)),
          shape: const StadiumBorder(),
        ),
      ),
      cardColor: surfaceBase,
      // Chip-ы — сегмент-контрол из референса: капсула-вставка, выбранная
      // — фиолетовая капсула с тёмным текстом, невыбранная — прозрачная
      // с серо-лавандовым текстом #A7ABBD.
      chipTheme: ChipThemeData(
        backgroundColor: surfaceRecessed,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        labelStyle: TextStyle(color: textSecondary, fontSize: 13),
        selectedColor: _neuVioletBright,
        checkmarkColor: _neuOnAccent,
        secondaryLabelStyle: const TextStyle(color: _neuOnAccent, fontSize: 13),
      ),
      // Переключатели (Switch) — неоновая дорожка #A17BFC в активном
      // состоянии, recessed-дорожка с серым ползунком в неактивном.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return isDark ? _neuTextPrimary : Colors.white;
          }
          return textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _neuVioletBright;
          }
          return surfaceRecessed;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      // Слайдеры — неоновая фиолетовая активная дорожка (§ неоновая дуга
      // спецификации) на recessed-треке.
      sliderTheme: SliderThemeData(
        activeTrackColor: _neuViolet,
        inactiveTrackColor: surfaceHighlight,
        thumbColor: isDark ? _neuTextPrimary : Colors.white,
        overlayColor: _neuViolet.withValues(alpha: 0.16),
        valueIndicatorColor: surfaceBase,
      ),
      // ПРЯМЫЕ ЛИНИИ НЕ СКРУГЛЯЮТСЯ (правило заказчика): прогресс-бар —
      // строго прямоугольная линия без радиусов; Divider — острый.
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: _neuViolet,
        linearTrackColor: surfaceHighlight,
        borderRadius: BorderRadius.zero,
      ),
      dividerTheme: DividerThemeData(
        color: textSecondary.withValues(alpha: 0.16),
        thickness: 0.5,
        space: 1,
      ),
      extensions: [
        PanelColors(
          // Боковые панели — приподнятая поверхность циферблата (#20242F).
          panel: surfaceBase,
          // Контентная область — «желобок» (#171B26): сетка файлов лежит
          // в углублении, карточки на нём приподняты (§ слои спецификации).
          contentBackground: isDark ? _neuContentWell : surfaceRecessed,
        ),
        _DesignSystemExtension(
          design: AppDesignSystem.neumorphicSmartHome,
          // Тёмная версия — радиальный градиент фона из спецификации;
          // светлая — плоский фон (обои не нужны).
          wallpaper: isDark ? _neuWallpaper : null,
          blurSigma: 0,
          blurEnabled: false,
        ),
      ],
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
      // Бóльшие скругления, как в iOS. CardThemeData — это новое имя
      // в Flutter 3.22+ (старое CardTheme теперь deprecated и не принимается
      // как аргумент ThemeData.cardTheme начиная с 3.47).
      cardTheme: const CardThemeData(
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
      // просвечивает, сохраняя «воздушный» iOS-look.
      dialogTheme: DialogThemeData(
        backgroundColor: brightness == Brightness.light
            ? const Color(0xF2FFFFFF)
            : const Color(0xF21C1C1E),
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      // Контекстные меню (PopupMenu) — тоже полупрозрачные, чтобы
      // фоновый градиент просвечивал и был эффект стекла.
      popupMenuTheme: PopupMenuThemeData(
        color: brightness == Brightness.light
            ? const Color(0xF2FFFFFF)
            : const Color(0xF21C1C1E),
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      // SnackBar — полупрозрачный «плавающий», как в iOS.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: brightness == Brightness.light
            ? const Color(0xF2FFFFFF)
            : const Color(0xF21C1C1E),
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      // Bottom sheet (если где-то появится) — тоже стекло.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: brightness == Brightness.light
            ? const Color(0xF2FFFFFF)
            : const Color(0xF21C1C1E),
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
          ),
        ),
      ),
      // Кнопки с заливкой (FilledButton) — чуть прозрачнее, чтобы
      // сохранялся «воздушный» стиль.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary.withValues(alpha: 0.85),
          foregroundColor: scheme.onPrimary,
        ),
      ),
      // Карточки: прозрачный фон + мягкая граница, чтобы стекло читалось
      // даже если внутри карточки лежит opaque-виджет.
      cardColor: brightness == Brightness.light
          ? const Color(0xB3FFFFFF)
          : const Color(0xB31C1C1E),
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
class _DesignSystemExtension extends ThemeExtension<_DesignSystemExtension> {
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

  /// Тонкая граница «стеклянной» панели: 1px, 18% прозрачности.
  /// Используется в [FrostedPanel], [AppDialog], AppBar и [PanelDragHandle]
  /// для визуального отделения панелей друг от друга (иначе они сливаются
  /// в одну простыню из-за мягкого размытия).
  Color get panelBorderColor {
    final isDark = Theme.of(this).brightness == Brightness.dark;
    return isDark
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.18);
  }

  /// Стиль [IconButton] для iOS-тем: полупрозрачная «стеклянная» подложка
  /// с мягкой границей. Для Material-темы возвращает null — используется
  /// стандартный M3-стиль кнопок.
  ///
  /// Применяется в AppBar (Настройки / Тема) и в действиях диалогов.
  ///
  /// Для [AppDesignSystem.iosLiquidGlass] используется централизованный
  /// стиль из [liquidGlassIconButtonStyle] (capsule glass с subtle edge,
  /// hover/pressed states — см. гайдлайн §9 BUTTON SYSTEM).
  ///
  /// Для [AppDesignSystem.neumorphicSmartHome] — «приподнятая» тёмная
  /// поверхность (#2B3444) с мягкой формой, без рамок (§ surface_treatment).
  ButtonStyle? get glassIconButtonStyle {
    if (designSystem == AppDesignSystem.material) return null;
    if (designSystem == AppDesignSystem.iosLiquidGlass) {
      return liquidGlassIconButtonStyle(
        brightness: Theme.of(this).brightness,
      );
    }
    final isDark = Theme.of(this).brightness == Brightness.dark;
    if (designSystem == AppDesignSystem.neumorphicSmartHome) {
      return IconButton.styleFrom(
        // Приподнятая поверхность (§ циферблат: тело #20242F / блик #313443),
        // круглая капсула — скругление только у «объёмных» элементов.
        backgroundColor:
            isDark ? const Color(0xFF242A38) : const Color(0xFFF6F8FC),
        foregroundColor:
            isDark ? const Color(0xFFFDFEFF) : const Color(0xFF1D2430),
        hoverColor: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.05),
        shape: const StadiumBorder(),
      );
    }
    return IconButton.styleFrom(
      backgroundColor: isDark
          ? Colors.white.withValues(alpha: 0.10)
          : Colors.white.withValues(alpha: 0.55),
      foregroundColor: isDark
          ? Colors.white.withValues(alpha: 0.95)
          : Colors.black.withValues(alpha: 0.85),
      // hoverColor — fallback на стандартный behavior (ripple), но с
      // чуть более заметным tintом при наведении (4-6% поверх bg).
      hoverColor: isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.white.withValues(alpha: 0.20),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    );
  }

  /// True, если активна дизайн-система iOS 27 / Liquid Glass.
  /// Используется в [MainScreen] для решения: рисовать ли кастомный
  /// [LiquidGlassThemeToggle] вместо обычной IconButton.
  bool get isLiquidGlass => designSystem == AppDesignSystem.iosLiquidGlass;
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

    if (isGlass &&
        context.backdropBlurEnabled &&
        context.backdropBlurSigma > 0) {
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

    // В iOS-темах добавляем видимую границу ПОВЕРХ стекла (через
    // foregroundDecoration) — иначе BackdropFilter размывает границу,
    // и панели сливаются в одну стеклянную простыню. foregroundDecoration
    // рисуется ПОСЛЕ child, поэтому не подвергается blur.
    if (isGlass && shape == null) {
      final border = Border.all(
        color: context.panelBorderColor,
        width: 1,
      );
      panel = Container(
        foregroundDecoration: BoxDecoration(
          border: border,
          borderRadius:
              borderRadius > 0 ? BorderRadius.circular(borderRadius) : null,
        ),
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
