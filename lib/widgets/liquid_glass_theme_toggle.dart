import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/settings/theme_provider.dart';

/// Тема-переключатель в стиле iOS 27 / Liquid Glass.
///
/// Дизайн по скриншоту заказчика:
///   • Светлая тема — оранжевый градиент дорожки ( FF8C00 → FFB347),
///     knob слева, иконка солнца.
///   • Тёмная тема — зелёный градиент дорожки ( 228B22 → 32CD32),
///     knob справа, иконка луны.
///   • Knob — матовое стекло: полупрозрачный тёмный фон + BackdropFilter
///     с размытием 22px, тонкая светлая граница, мягкая тень «парения».
///   • Иконка внутри knob-а белая (солнце/луна).
///   • На дорожке с противоположной от knob стороны — полупрозрачная
///     стрелка-индикатор ( › / ‹ ).
///
/// Анимация:
///   • knob анимированно скользит (AnimatedPositioned);
///   • tint дорожки плавно интерполируется (AnimatedContainer);
///   • иконка состояния плавно появляется/исчезает (AnimatedOpacity).
class LiquidGlassThemeToggle extends StatefulWidget {
  const LiquidGlassThemeToggle({super.key, this.size = const Size(96, 44)});

  /// Внешний размер pill-дорожки.
  final Size size;

  @override
  State<LiquidGlassThemeToggle> createState() =>
      _LiquidGlassThemeToggleState();
}

class _LiquidGlassThemeToggleState extends State<LiquidGlassThemeToggle> {
  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final isDark = theme.mode == AppThemeMode.dark ||
        (theme.mode == AppThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    final width = widget.size.width;
    final height = widget.size.height;
    // Knob чуть меньше высоты дорожки — виден «ободок» стекла по периметру.
    final knobSize = height - 8;
    final knobPadding = (height - knobSize) / 2;
    final knobTravel = width - knobSize - knobPadding * 2;

    // Градиент дорожки:
    //   светлая — оранжевый ( FF8C00 → FFB347),
    //   тёмная — зелёный ( 228B22 → 32CD32).
    final trackGradient = isDark
        ? const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF228B22), Color(0xFF32CD32)],
          )
        : const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFFFF8C00), Color(0xFFFFB347)],
          );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _toggle(context),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOut,
          width: width,
          height: height,
          decoration: BoxDecoration(
            gradient: trackGradient,
            borderRadius: BorderRadius.circular(height / 2),
            boxShadow: [
              // Лёгкая внешняя тень дорожки.
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 8,
                spreadRadius: 0,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              // ── Стрелка-индикатор на дорожке (с противоположной от knob стороны) ──
              // В светлой теме knob слева → стрелка справа ( ›).
              // В тёмной теме knob справа → стрелка слева ( ‹).
              Positioned(
                left: isDark ? 10 : null,
                right: isDark ? null : 10,
                top: 0,
                bottom: 0,
                child: Center(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: 0.65,
                    child: Icon(
                      isDark ? Icons.chevron_left : Icons.chevron_right,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              // ── Стеклянный knob — анимированно скользит ──
              AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                left: isDark ? knobTravel + knobPadding : knobPadding,
                top: knobPadding,
                child: _GlassKnob(
                  size: knobSize,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Переключение между светлой и тёмной темой.
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

/// Стеклянный knob тема-переключателя.
///
/// Многослойная структура (снизу вверх):
///   1. BackdropFilter — размытие фона за knob-ом (σ = 22px, матовое стекло).
///   2. Полупрозрачная тёмная заливка ( rgba 40,42,48, 0.65).
///   3. Тонкая светлая граница 1px ( rgba 255,255,255, 0.25).
///   4. Внутренний specular highlight — блик сверху.
///   5. Мягкая тень «парения» ( 0 8px 24px rgba(0,0,0,0.4)).
///   6. Иконка солнца/луны — белая, по центру.
class _GlassKnob extends StatelessWidget {
  const _GlassKnob({required this.size, required this.isDark});

  final double size;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      // 5. Мягкая тень «парения» рисуется внешним Container-ом.
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      // ClipOval чтобы BackdropFilter не выходил за круг.
      child: ClipOval(
        child: Stack(
          children: [
            // 1. BackdropFilter — матовое стекло (размытие фона).
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: const SizedBox.expand(),
            ),
            // 2 + 3. Полупрозрачная тёмная заливка + светлая граница.
            Container(
              decoration: BoxDecoration(
                color: const Color(0xA6282A30),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
            ),
            // 4. Внутренний specular highlight — блик сверху.
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.30),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.5],
                ),
              ),
            ),
            // 6. Иконка солнца/луны — белая, по центру.
            Center(
              child: Icon(
                isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                size: size * 0.48,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
