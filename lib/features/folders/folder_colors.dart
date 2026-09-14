import 'package:flutter/material.dart';

/// Утилиты и пресеты для цвета иконок папок.
///
/// Используются диалогом «Настройка цвета папки», левой панелью
/// (отрисовка цветных иконок в дереве) и диалогом перемещения
/// элементов в папку — чтобы цвет папки выглядел одинаково во всём
/// приложении.

/// Быстрые пресеты цветов папок (как цветные папки в Eagle):
/// красный, оранжевый, зелёный, бирюзовый, синий, фиолетовый,
/// розовый и серый.
const List<(String, Color)> folderColorPresets = <(String, Color)>[
  ('F44336', Color(0xFFF44336)), // красный
  ('FF9800', Color(0xFFFF9800)), // оранжевый
  ('4CAF50', Color(0xFF4CAF50)), // зелёный
  ('009688', Color(0xFF009688)), // бирюзовый
  ('2196F3', Color(0xFF2196F3)), // синий
  ('9C27B0', Color(0xFF9C27B0)), // фиолетовый
  ('E91E63', Color(0xFFE91E63)), // розовый
  ('9E9E9E', Color(0xFF9E9E9E)), // серый
];

/// Разбор HEX-строки («F44336», «#F44336», «F53») в [Color].
/// Возвращает `null`, если строка пустая, null или некорректна.
Color? colorFromHex(String? hex) {
  if (hex == null) return null;
  var s = hex.trim().replaceAll('#', '');
  if (s.isEmpty) return null;
  if (s.length == 3) {
    s = s.split('').map((c) => '$c$c').join();
  }
  if (s.length != 6) return null;
  final v = int.tryParse(s, radix: 16);
  if (v == null) return null;
  return Color(0xFF000000 | v);
}

/// Форматирование [Color] в HEX-строку без решётки (например, «F44336»).
String hexOfColor(Color color) {
  final v = color.toARGB32() & 0xFFFFFF;
  return v.toRadixString(16).padLeft(6, '0').toUpperCase();
}
