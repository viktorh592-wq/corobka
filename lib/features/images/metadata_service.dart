import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../data/models/item.dart';

/// Сервис извлечения метаданных изображений.
///
/// Читает размеры, разрешение и формат файла, обновляя соответствующие
/// поля модели [CollectionItem].
class MetadataService {
  const MetadataService();

  /// Чтение метаданных изображения из файла.
  ///
  /// Возвращает карту с полями: ширина, высота, формат.
  /// Если изображение не удалось декодировать, поля остаются пустыми.
  Future<Map<String, dynamic>> extractMetadata(String path) async {
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);

      if (decoded == null) {
        return {'width': null, 'height': null, 'format': _extensionOf(path)};
      }

      return {
        'width': decoded.width,
        'height': decoded.height,
        'format': _formatOf(bytes),
      };
    } catch (_) {
      // Не удалось декодировать — возвращаем только расширение.
      return {'width': null, 'height': null, 'format': _extensionOf(path)};
    }
  }

  /// Формирование обновлённой модели [CollectionItem] с метаданными.
  CollectionItem applyMetadata(
    CollectionItem item,
    Map<String, dynamic> metadata,
  ) {
    return CollectionItem(
      id: item.id,
      folderId: item.folderId,
      title: item.title,
      path: item.path,
      width: metadata['width'] as int? ?? item.width,
      height: metadata['height'] as int? ?? item.height,
      format: (metadata['format'] as String?) ?? item.format,
      palette: item.palette,
      notes: item.notes,
      isFavorite: item.isFavorite,
      createdAt: item.createdAt,
    );
  }

  /// Определение формата изображения по сигнатуре файла.
  String? _formatOf(Uint8List bytes) {
    if (bytes.length < 12) return null;

    // PNG
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E) {
      return 'png';
    }
    // JPEG
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return 'jpg';
    }
    // WEBP
    if (bytes.length >= 12 &&
        _ascii(bytes, 0, 4) == 'RIFF' &&
        _ascii(bytes, 8, 4) == 'WEBP') {
      return 'webp';
    }
    // GIF
    if (_ascii(bytes, 0, 4) == 'GIF8') {
      return 'gif';
    }
    // BMP
    if (_ascii(bytes, 0, 2) == 'BM') {
      return 'bmp';
    }
    return null;
  }

  /// Извлечение ASCII-строки из байтов.
  String _ascii(Uint8List bytes, int start, int length) {
    return String.fromCharCodes(bytes.sublist(start, start + length));
  }

  /// Извлечение расширения файла (без точки).
  String _extensionOf(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final idx = name.lastIndexOf('.');
    return idx == -1 ? '' : name.substring(idx + 1);
  }
}