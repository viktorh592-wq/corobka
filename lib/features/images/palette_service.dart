import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:palette_generator/palette_generator.dart';

/// Сервис извлечения цветовой палитры из изображения.
///
/// Возвращает палитру в виде JSON-строки, которую можно сохранить
/// в базе данных и использовать для фильтрации по цвету.
class PaletteService {
  const PaletteService();

  /// Извлечение палитры из файла изображения.
  ///
  /// Возвращает JSON-строку со списком цветов в формате `RRGGBB`
  /// (например `["5B6CFF", "FFFFFF", "1E1F24"]`).
  Future<String?> extractPalette(String path) async {
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final generator = await PaletteGenerator.fromImage(
        image,
        maximumColorCount: 5,
      );

      image.dispose();
      codec.dispose();

      final colors = <String>[];
      final addColor = (ui.Color? c) {
        if (c == null) return;
        final hex = _toHex(c);
        if (!colors.contains(hex)) colors.add(hex);
      };

      addColor(generator.dominantColor?.color);
      for (final entry in generator.paletteColors) {
        addColor(entry.color);
      }

      if (colors.isEmpty) return null;
      return jsonEncode(colors);
    } catch (_) {
      return null;
    }
  }

  /// Преобразование цвета в шестнадцатеричную строку `RRGGBB`.
  String _toHex(ui.Color c) {
    final argb = c.toARGB32();
    final rgb = argb & 0xFFFFFF;
    return rgb.toRadixString(16).padLeft(6, '0').toUpperCase();
  }
}
