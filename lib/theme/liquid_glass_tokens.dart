// ─────────────────────────────────────────────────────────────────────────
//  LIQUID GLASS DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────────────
//
//  Централизованный источник истины для дизайн-системы «iOS 27 / Liquid
//  Glass», адаптированной под Flutter Desktop.
//
//  Файл нужен, чтобы не плодить magic numbers по всему UI — см. секцию
//  «46. DESIGN TOKENS» гайдлайна COROBKA_iOS27_LiquidGlass_UI_GUIDELINE.md.
//
//  Принципы (см. секцию 56 гайдлайна):
//    • стекло — функциональный слой, а не «обои» для всего приложения;
//    • контент (изображения/медиа) остаётся резким и доминирует;
//    • BackdropFilter используется ТОЛЬКО для маленьких контролов
//      (тулбар, поиск, диалоги, popover-меню) — нигде не применяется
//      глобально ко всему окну.
import 'dart:ui';

import 'package:flutter/material.dart';

/// Семантические радиусы (гайдлайн §8 CORNER SHAPES).
///
/// Концентричные радиусы: дочерние элементы используют радиус чуть
/// меньше родительского, чтобы визуально вкладываться друг в друга.
class RadiusTokens {
  const RadiusTokens._();

  /// Маленькие контролы (чипы, теги, маленькие кнопки).
  static const double small = 10;

  /// Средние контролы (кнопки тулбара, поля ввода, сегментный контрол).
  static const double medium = 14;

  /// Большие поверхности (диалоги, popover-меню, плавающие панели).
  static const double large = 20;

  /// Капсула — для кнопок «icon + label» и пилюли тема-переключателя.
  static const double capsule = 999;

  /// Круглая иконка-кнопка (например, тема-переключатель knob).
  static const double circular = 50; // % — используется через CircleBorder
}

/// Длительности анимаций (гайдлайн §12 BUTTON ANIMATION TIMING).
///
/// Все значения в миллисекундах. Короткие и прерываемые — см. §40
/// «INTERRUPTIBLE ANIMATIONS».
class MotionTokens {
  const MotionTokens._();

  /// Микро-фидбек для press/release (≈ tactile compression).
  static const int microInteraction = 120;

  /// Быстрая обратная связь для hover/state change.
  static const int quickFeedback = 180;

  /// Стандартная смена состояния (focus, toggle, selected).
  static const int standardTransition = 220;

  /// Появление/скрытие панелей и popover-ов.
  static const int panelTransition = 280;

  /// Крупные переходы (диалоги, morphing сегментного контрола).
  static const int largeTransition = 320;
}

/// Параметры стеклянного материала (гайдлайн §7 GLASS MATERIAL SPEC).
///
/// Эти значения описывают ВИЗУАЛЬНУЮ цель — конкретная реализация
/// (BackdropFilter / полупрозрачная заливка / граница / тень) находится
/// в [LiquidGlassSurface].
class GlassTokens {
  const GlassTokens._();

  /// Сила размытия для маленьких контролов (тулбар, поиск).
  /// Visible but controlled (§7.2) — пользователь видит «материал
  /// с глубиной», а не «всё за стеклом размыто».
  static const double blurSmall = 18;

  /// Сила размытия для средних поверхностей (диалоги, popover).
  static const double blurMedium = 28;

  /// Сила размытия для крупных поверхностей (например, popover со
  /// списком папок). НЕ применяется к main content area.
  static const double blurLarge = 40;

  /// Прозрачность заливки стекла в светлой теме.
  /// 0.62 — баланс между «виден фон под стеклом» и «контрол читается».
  static const double fillOpacityLight = 0.62;

  /// Прозрачность заливки стекла в тёмной теме.
  /// 0.55 — в тёмной теме фон и так тёмный, поэтому стекло чуть
  /// прозрачнее, чтобы edge-highlight был заметнее.
  static const double fillOpacityDark = 0.55;

  /// Прозрачность границы стекла (subtle edge definition, §7.3).
  static const double borderOpacity = 0.18;

  /// Прозрачность внутреннего highlight (subtle specular, §7.5).
  static const double highlightOpacity = 0.10;

  /// Прозрачность мягкой тени (soft diffuse shadow, §7.4).
  static const double shadowOpacityLight = 0.18;
  static const double shadowOpacityDark = 0.45;

  /// Цвет стекла в светлой теме (нейтральный белый).
  static const Color fillLight = Color(0xFFFFFFFF);

  /// Цвет стекла в тёмной теме (тёмный нейтральный, не чисто-чёрный).
  static const Color fillDark = Color(0xFF1C1C1E);

  /// Цвет акцента (iOS-синий, сохраняет семантику приложения).
  static const Color accent = Color(0xFF007AFF);

  /// Цвет «разрушительного» действия (restrained red, §10.4).
  static const Color destructive = Color(0xFFFF3B30);

  /// Цвет «успешного» действия (restrained green, §47).
  static const Color success = Color(0xFF34C759);

  /// Цвет предупреждения (restrained orange, §47).
  static const Color warning = Color(0xFFFF9500);
}

/// Утилита: возвращает цвет стекла для текущей яркости.
Color glassFillColor(Brightness brightness) {
  return brightness == Brightness.light
      ? GlassTokens.fillLight.withValues(alpha: GlassTokens.fillOpacityLight)
      : GlassTokens.fillDark.withValues(alpha: GlassTokens.fillOpacityDark);
}

/// Утилита: цвет границы стекла (subtle edge, §7.3).
///
/// В светлой теме — тёмный 18%, в тёмной — светлый 22% (чуть выше,
/// чтобы край был заметен на тёмном фоне).
Color glassBorderColor(Brightness brightness) {
  return brightness == Brightness.light
      ? Colors.black.withValues(alpha: 0.18)
      : Colors.white.withValues(alpha: 0.22);
}

/// Утилита: мягкая тень стекла (soft diffuse, §7.4).
///
/// Сильная, но размытая — communicates elevation only, no glow.
List<BoxShadow> glassShadow(Brightness brightness) {
  final opacity = brightness == Brightness.light
      ? GlassTokens.shadowOpacityLight
      : GlassTokens.shadowOpacityDark;
  return [
    BoxShadow(
      color: Colors.black.withValues(alpha: opacity),
      blurRadius: 24,
      spreadRadius: 0,
      offset: const Offset(0, 8),
    ),
  ];
}

/// Виджет-«Liquid Glass поверхность»: полупрозрачная заливка + мягкая
/// граница + мягкая тень + (опционально) BackdropFilter для маленьких
/// контролов.
///
/// Это единственное место, где используется BackdropFilter в этой
/// дизайн-системе. Применяется к:
///   • тулбару (top app bar);
///   • полю поиска;
///   • кнопкам тулбара (capsule glass);
///   • диалогам / popover-меню;
///   • тема-переключателю;
///   • floating kontROLS в lightbox.
///
/// К главному контенту (image grid, masonry, list) СТЕКЛО НЕ
/// ПРИМЕНЯЕТСЯ — см. гайдлайн §25 «IMAGE CARDS / THUMBNAILS».
class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    super.key,
    required this.child,
    this.radius = RadiusTokens.medium,
    this.applyBlur = true,
    this.blurSigma = GlassTokens.blurSmall,
    this.elevation = true,
    this.highlight = true,
    this.padding,
    this.backgroundColor,
  });

  /// Дочерний виджет.
  final Widget child;

  /// Радиус скругления (концентричные радиусы — см. [RadiusTokens]).
  final double radius;

  /// Применять ли BackdropFilter (для маленьких контролов — да,
  /// для больших поверхностей — нет, см. §44 PERFORMANCE).
  final bool applyBlur;

  /// Сила размытия (если [applyBlur] = true).
  final double blurSigma;

  /// Рисовать ли мягкую тень (для «парящих» контролов — да, для
  /// встроенных в панель — нет).
  final bool elevation;

  /// Рисовать ли внутренний specular highlight (§7.5).
  final bool highlight;

  /// Внутренний padding (если нужен).
  final EdgeInsetsGeometry? padding;

  /// Переопределение цвета заливки (по умолчанию — [glassFillColor]
  /// от текущей яркости).
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final fill = backgroundColor ?? glassFillColor(brightness);
    final border = glassBorderColor(brightness);
    final shadows = elevation ? glassShadow(brightness) : const <BoxShadow>[];
    final highlightColor = brightness == Brightness.light
        ? Colors.white.withValues(alpha: GlassTokens.highlightOpacity)
        : Colors.white.withValues(alpha: GlassTokens.highlightOpacity * 1.4);

    Widget content = padding == null
        ? child
        : Padding(padding: padding!, child: child);

    // Специкулярный highlight — тонкая (1px) светлая полоска сверху
    // (см. §7.5 — «strongest near the top/edge»).
    if (highlight) {
      content = Stack(
        children: [
          content,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: highlightColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(radius),
                  topRight: Radius.circular(radius),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Material — для InkWell/ripple, если внутри есть кнопки.
    content = Material(
      type: MaterialType.transparency,
      elevation: 0,
      child: content,
    );

    // Декорация поверхности: заливка + граница + тень.
    content = Container(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border, width: 1),
        boxShadow: shadows,
      ),
      child: content,
    );

    // BackdropFilter — только для маленьких контролов. Важный момент:
    // ImageFilter.blur сам по себе ничего не рендерит, он модифицирует
    // то, что находится ПОД виджетом. Сама заливка и контент остаются
    // резкими.
    if (applyBlur && blurSigma > 0) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: blurSigma,
            sigmaY: blurSigma,
            tileMode: TileMode.mirror,
          ),
          child: content,
        ),
      );
    }

    return content;
  }
}

/// Стиль кнопки в стиле Liquid Glass (capsule shape, translucent fill).
///
/// Возвращает [ButtonStyle] для FilledButton / TextButton / OutlinedButton.
/// Используется в тулбаре, диалогах, popover-меню — везде, где нужна
/// «стеклянная» кнопка с padding-ом и hover/pressed states.
ButtonStyle liquidGlassButtonStyle({
  required Brightness brightness,
  bool prominent = false,
  bool destructive = false,
}) {
  final fill = prominent
      ? GlassTokens.accent.withValues(alpha: 0.92)
      : destructive
          ? GlassTokens.destructive.withValues(alpha: 0.85)
          : glassFillColor(brightness);

  final foreground = (prominent || destructive)
      ? Colors.white
      : (brightness == Brightness.light ? Colors.black : Colors.white);

  return ButtonStyle(
    shape: WidgetStateProperty.all<RoundedRectangleBorder>(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RadiusTokens.capsule),
      ),
    ),
    backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.disabled)) {
        return fill.withValues(alpha: 0.4);
      }
      if (states.contains(WidgetState.pressed)) {
        return fill.withValues(alpha: brightness == Brightness.light ? 0.85 : 0.70);
      }
      if (states.contains(WidgetState.hovered)) {
        return fill.withValues(alpha: brightness == Brightness.light ? 0.85 : 0.75);
      }
      return fill;
    }),
    foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.disabled)) {
        return foreground.withValues(alpha: 0.4);
      }
      return foreground;
    }),
    elevation: WidgetStateProperty.all<double>(0),
    padding: WidgetStateProperty.all<EdgeInsetsGeometry>(
      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    ),
    side: WidgetStateProperty.resolveWith<BorderSide?>((states) {
      if (prominent || destructive) return null;
      // Subtle edge — §7.3.
      final border = glassBorderColor(brightness);
      if (states.contains(WidgetState.focused) ||
          states.contains(WidgetState.hovered)) {
        return BorderSide(
          color: border.withValues(alpha: 0.40),
          width: 1,
        );
      }
      return BorderSide(color: border, width: 1);
    }),
  );
}

/// Стиль иконки-кнопки в стиле Liquid Glass (circular glass capsule).
ButtonStyle liquidGlassIconButtonStyle({
  required Brightness brightness,
}) {
  final fill = glassFillColor(brightness);
  final border = glassBorderColor(brightness);
  final foreground =
      brightness == Brightness.light ? Colors.black : Colors.white;

  return IconButton.styleFrom(
    backgroundColor: fill,
    foregroundColor: foreground,
    hoverColor: brightness == Brightness.light
        ? Colors.white.withValues(alpha: 0.55)
        : Colors.white.withValues(alpha: 0.18),
    focusColor: brightness == Brightness.light
        ? Colors.white.withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.25),
    highlightColor: brightness == Brightness.light
        ? Colors.black.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.10),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(RadiusTokens.medium)),
    ),
    side: BorderSide(color: border, width: 1),
    padding: const EdgeInsets.all(8),
  );
}
