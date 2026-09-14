import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// Сервис извлечения превью-кадров из видеофайлов.
///
/// Использует media_kit (libmpv): открывает файл, перематывается на
/// небольшой отступ от начала и снимает кадр в JPEG. Если нативные
/// библиотеки недоступны (например, в тестовом окружении), сервис
/// «отключается» после первой ошибки и больше не пытается работать —
/// приложение продолжает показывать плейсхолдер.
class VideoThumbnailService {
  VideoThumbnailService._();

  static final VideoThumbnailService instance = VideoThumbnailService._();

  /// Доступен ли декодер (после фатальной ошибки — false).
  bool _available = true;

  /// Флаг доступности (для пропуска перебора видео в бэкфилле).
  bool get isAvailable => _available;

  /// Извлечение кадра из видео в байты JPEG.
  ///
  /// Возвращает `null`, если кадр извлечь не удалось.
  Future<Uint8List?> extractFrame(
    String videoPath, {
    Duration position = const Duration(seconds: 1),
  }) async {
    if (!_available) return null;

    Player? player;
    try {
      player = Player();
    } catch (e) {
      // Нет нативных библиотек (тесты/не поддерживаемая система).
      debugPrint('VideoThumbnail: player unavailable: $e');
      _available = false;
      return null;
    }

    try {
      // Открываем без воспроизведения — достаточно для декодирования кадра.
      await player
          .open(Media(videoPath), play: false)
          .timeout(const Duration(seconds: 15));

      // Ждём готовности метаданных (до 5 секунд).
      try {
        await player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 5));
      } on TimeoutException {
        // Метаданные не пришли — пробуем снять кадр как есть.
      }

      // Перематываем чуть вперёд от начала: первый кадр часто чёрный.
      final duration = player.state.duration;
      if (duration > const Duration(seconds: 3)) {
        final target = position < duration ? position : Duration.zero;
        if (target > Duration.zero) {
          await player.seek(target);
        }
        // Даём декодеру время отрисовать кадр.
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }

      final bytes = await player
          .screenshot(format: 'image/jpeg')
          .timeout(const Duration(seconds: 10));
      return bytes;
    } catch (e) {
      debugPrint('VideoThumbnail: extract failed for "$videoPath": $e');
      return null;
    } finally {
      try {
        await player.dispose();
      } catch (_) {}
    }
  }

  /// Извлечение кадра с сохранением в JPEG-файл [outputPath].
  ///
  /// Возвращает путь к файлу или `null` при неудаче.
  Future<String?> extractToFile(String videoPath, String outputPath) async {
    final bytes = await extractFrame(videoPath);
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final file = File(outputPath);
      await file.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return outputPath;
    } catch (e) {
      debugPrint('VideoThumbnail: write failed: $e');
      return null;
    }
  }
}
