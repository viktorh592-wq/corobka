import 'package:flutter/material.dart';

/// Переиспользуемые цветные слайдеры (тон / насыщенность / яркость).
///
/// Вынесены из диалога «Фильтр по цвету», чтобы их же использовал
/// диалог «Настройка цвета папки» — окна выглядят единообразно.

/// Слайдер тона (hue) с радужным градиентом на треке.
/// Жесты и ползунок берёт Material Slider; цветной трек рисуем под ним.
class HueSlider extends StatelessWidget {
  const HueSlider({super.key, required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  static const _rainbow = [
    Color(0xFFFF0000),
    Color(0xFFFFFF00),
    Color(0xFF00FF00),
    Color(0xFF00FFFF),
    Color(0xFF0000FF),
    Color(0xFFFF00FF),
    Color(0xFFFF0000),
  ];

  @override
  Widget build(BuildContext context) {
    return GradientSlider(
      value: value / 360.0,
      fromColor: const Color(0xFFFF0000),
      toColor: const Color(0xFFFF0000),
      gradient: const LinearGradient(colors: _rainbow),
      onChanged: (v) => onChanged(v * 360.0),
    );
  }
}

/// Слайдер насыщенности (saturation) с горизонтальным градиентом
/// от серого к насыщенному цвету текущего тона.
class SaturationSlider extends StatelessWidget {
  const SaturationSlider({
    super.key,
    required this.hsv,
    required this.onChanged,
  });

  final HSVColor hsv;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final baseColor = hsv.withSaturation(1).withValue(1).toColor();
    final greyColor = hsv.withSaturation(0).withValue(1).toColor();
    return GradientSlider(
      value: hsv.saturation,
      fromColor: greyColor,
      toColor: baseColor,
      onChanged: onChanged,
    );
  }
}

/// Слайдер яркости (value) с градиентом от чёрного к насыщенному цвету.
class ValueSlider extends StatelessWidget {
  const ValueSlider({
    super.key,
    required this.hsv,
    required this.onChanged,
  });

  final HSVColor hsv;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final baseColor = hsv.withSaturation(1).withValue(1).toColor();
    return GradientSlider(
      value: hsv.value,
      fromColor: Colors.black,
      toColor: baseColor,
      onChanged: onChanged,
    );
  }
}

/// Универсальный слайдер с произвольным горизонтальным градиентом на треке.
/// Поверх Flutter-слайдера кладём ClipRRect с LinearGradient, чтобы
/// получить «цветной трек». Сам ползунок и логика перетаскивания —
/// от Material Slider.
class GradientSlider extends StatelessWidget {
  const GradientSlider({
    super.key,
    required this.value,
    required this.fromColor,
    required this.toColor,
    required this.onChanged,
    this.gradient,
  });

  final double value;
  final Color fromColor;
  final Color toColor;
  final ValueChanged<double> onChanged;

  /// Опционально: кастомный многоцветный градиент (например, радуга
  /// для hue). Если null — используется двуцветный fromColor → toColor.
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final trackGradient = gradient ??
        LinearGradient(colors: [fromColor, toColor]);

    return Stack(
      alignment: Alignment.center,
      children: [
        // Цветной трек.
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 14,
            decoration: BoxDecoration(gradient: trackGradient),
          ),
        ),
        // Поверх — прозрачный Material Slider, который даёт ползунок
        // и обрабатывает жесты перетаскивания.
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 14,
            activeTrackColor: Colors.transparent,
            inactiveTrackColor: Colors.transparent,
            thumbColor: Colors.white,
            overlayColor: const Color(0x14000000),
            trackShape: const RoundedRectSliderTrackShape(),
          ),
          child: Slider(
            value: value.clamp(0.0, 1.0),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
