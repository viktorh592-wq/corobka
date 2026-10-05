import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/settings/theme_provider.dart';
import '../theme/liquid_glass_tokens.dart';

/// Тема-переключатель в стиле iOS 27 / Liquid Glass.
///
/// Соответствует гайдлайну §15 «THEME TOGGLE — SPECIAL REQUIREMENT»:
/// стеклянный круглый knob, скользящий по цветной pill-дорожке.
/// Светлая тема — knob слева, иконка солнца, дорожка светло-серая.
/// Тёмная тема — knob справа, иконка луны, дорожка тёмно-серая.
///
/// Анимация:
///   • knob анимированно скользит (AnimatedPositioned) — не «teleport»;
///   • иконка состояния плавно появляется/исчезает (AnimatedOpacity);
///   • tint дорожки плавно интерполируется (AnimatedContainer);
///   • сама UI-тема приложения меняется через notifyListeners().
///
/// См. также секцию §40 «INTERRUPTIBLE ANIMATIONS» — новая перестройка
/// не ждёт завершения предыдущей анимации.
class LiquidGlassThemeToggle extends StatefulWidget {
  const LiquidGlassThemeToggle({super.key, this.size = const Size(72, 32)});

  /// Внешний размер pill-дорожки.
  final Size size;

  @override
  State<LiquidGlassThemeToggle> createState() => _LiquidGlassThemeToggleState();
}

class _LiquidGlassThemeToggleState extends State<LiquidGlassThemeToggle> {
  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final isDark = theme.mode == AppThemeMode.dark ||
        (theme.mode == AppThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    final brightness = isDark ? Brightness.dark : Brightness.light;

    final width = widget.size.width;
    final height = widget.size.height;
    final knobSize = height - 6; // 3px padding с каждой стороны
    final knobTravel = width - knobSize - 6;

    // Цвет дорожки: в светлой теме — нейтральный светло-серый,
    // в тёмной — глубокий тёмно-серый (НЕ чёрный, см. §48).
    final trackColor = isDark
        ? const Color(0xFF2C2C2E)
        : const Color(0xFFE5E5EA);

    // Цвет knob-а — стеклянный белый/тёмный с лёгким translucent.
    final knobFill = isDark
        ? Colors.white.withValues(alpha: 0.92)
        : Colors.white.withValues(alpha: 0.96);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _toggle(context),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: MotionTokens.standardTransition),
          curve: Curves.easeInOut,
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: trackColor,
            borderRadius: BorderRadius.circular(RadiusTokens.capsule),
            border: Border.all(
              color: glassBorderColor(brightness),
              width: 1,
            ),
            boxShadow: glassShadow(brightness),
          ),
          child: Stack(
            children: [
              // Иконка солнца — слева, видна в светлой теме.
              Positioned(
                left: 10,
                top: 0,
                bottom: 0,
                child: Center(
                  child: AnimatedOpacity(
                    duration: const Duration(
                      milliseconds: MotionTokens.standardTransition,
                    ),
                    opacity: isDark ? 0.0 : 0.65,
                    child: Icon(
                      Icons.light_mode_rounded,
                      size: 14,
                      color: brightness == Brightness.light
                          ? const Color(0xFF8E8E93)
                          : Colors.transparent,
                    ),
                  ),
                ),
              ),
              // Иконка луны — справа, видна в тёмной теме.
              Positioned(
                right: 10,
                top: 0,
                bottom: 0,
                child: Center(
                  child: AnimatedOpacity(
                    duration: const Duration(
                      milliseconds: MotionTokens.standardTransition,
                    ),
                    opacity: isDark ? 0.85 : 0.0,
                    child: Icon(
                      Icons.dark_mode_rounded,
                      size: 14,
                      color: brightness == Brightness.dark
                          ? const Color(0xFFE5E5EA)
                          : Colors.transparent,
                    ),
                  ),
                ),
              ),
              // Стеклянный knob — анимированно скользит.
              AnimatedPositioned(
                duration: const Duration(
                  milliseconds: MotionTokens.panelTransition,
                ),
                curve: Curves.easeOutCubic,
                left: isDark ? knobTravel : 3.0,
                top: 3.0,
                child: Container(
                  width: knobSize,
                  height: knobSize,
                  decoration: BoxDecoration(
                    color: knobFill,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: glassBorderColor(brightness),
                      width: 0.5,
                    ),
                    boxShadow: [
                      // Subtle drop shadow под knob — даёт «парящую»
                      // глубину (см. §7.4 — soft diffuse shadow).
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: brightness == Brightness.dark ? 0.40 : 0.15,
                        ),
                        blurRadius: 4,
                        spreadRadius: 0,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      isDark
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      size: knobSize * 0.55,
                      color: isDark
                          ? const Color(0xFF1C1C1E)
                          : const Color(0xFF8E8E93),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Переключение между светлой и тёмной темой.
  ///
  /// В режиме `system` мы переключаемся на явный `dark`/`light`,
  /// чтобы пользовательский выбор был детерминированным (см. ThemeProvider).
  void _toggle(BuildContext context) {
    final theme = context.read<ThemeProvider>();
    final isCurrentlyDark = theme.mode == AppThemeMode.dark ||
        (theme.mode == AppThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    theme.setMode(
      isCurrentlyDark ? AppThemeMode.light : AppThemeMode.dark,
    );
  }
}
