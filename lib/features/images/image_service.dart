import 'dart:io';

import 'package:file_picker/file_picker.dart';

/// Сервис работы с файлами изображений.
///
/// Отвечает за выбор файлов через системный диалог, чтение изображений
/// и копирование/перемещение файлов в хранилище коллекции.
class ImageService {
  const ImageService();

  /// Поддерживаемые расширения файлов изображений.
  static const List<String> imageExtensions = [
    'png',
    'jpg',
    'jpeg',
    'webp',
    'bmp',
    'gif',
    'tiff',
    'svg',
    'ico',
  ];

  /// Поддерживаемые расширения видеофайлов.
  static const List<String> videoExtensions = [
    'mp4',
    'mov',
    'avi',
    'mkv',
    'webm',
    'm4v',
    'wmv',
    'flv',
  ];

  /// Поддерживаемые расширения аудиофайлов.
  static const List<String> audioExtensions = [
    'mp3',
    'wav',
    'flac',
    'ogg',
    'm4a',
    'aac',
    'wma',
    'opus',
  ];

  /// Все поддерживаемые расширения (изображения + видео + аудио).
  static List<String> get supportedExtensions => [
        ...imageExtensions,
        ...videoExtensions,
        ...audioExtensions,
      ];

  /// Открытие системного диалога выбора файлов (изображения, видео, аудио).
  ///
  /// Возвращает список путей к выбранным файлам.
  Future<List<String>> pickImageFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedExtensions,
      allowMultiple: true,
    );

    if (result == null) return const [];
    return result.paths.whereType<String>().toList();
  }

  /// Открытие системного диалога выбора папки.
  ///
  /// Возвращает путь к выбранной папке или `null`.
  Future<String?> pickDirectory() async {
    final path = await FilePicker.platform.getDirectoryPath();
    return path;
  }

  /// Проверка, что файл является поддерживаемым медиафайлом.
  bool isSupported(String path) {
    final ext = _extensionOf(path).toLowerCase();
    return supportedExtensions.contains(ext);
  }

  /// Является ли файл видео.
  bool isVideo(String path) =>
      videoExtensions.contains(_extensionOf(path).toLowerCase());

  /// Является ли файл аудио.
  bool isAudio(String path) =>
      audioExtensions.contains(_extensionOf(path).toLowerCase());

  /// Получение списка файлов изображений в папке (рекурсивно).
  Future<List<String>> listImagesInDirectory(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return const [];

    final result = <String>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && isSupported(entity.path)) {
        result.add(entity.path);
      }
    }
    return result;
  }

  /// Копирование файла в целевую папку с уникальным именем.
  ///
  /// Возвращает путь к скопированному файлу.
  Future<String> copyToDirectory(String sourcePath, String targetDir) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Исходный файл не найден', sourcePath);
    }

    final dir = Directory(targetDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final uniqueName = await _uniqueNameIn(
      source.uri.pathSegments.last,
      targetDir,
    );
    final destination = File('$targetDir${Platform.pathSeparator}$uniqueName');
    await source.copy(destination.path);
    return destination.path;
  }

  /// Генерация уникального имени файла внутри папки.
  Future<String> _uniqueNameIn(String original, String targetDir) async {
    final dir = Directory(targetDir);
    final existing = await dir.exists()
        ? (await dir.list().toList())
            .map((e) => e.path.split(Platform.pathSeparator).last)
            .toSet()
        : <String>{};

    if (!existing.contains(original)) return original;

    final base = original.contains('.')
        ? original.substring(0, original.lastIndexOf('.'))
        : original;
    final ext = _extensionOf(original);

    var counter = 1;
    var candidate = '${base}_$counter.$ext';
    while (existing.contains(candidate)) {
      counter++;
      candidate = '${base}_$counter.$ext';
    }
    return candidate;
  }

  /// ��звлечение расширения файла (без точки).
  String _extensionOf(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final idx = name.lastIndexOf('.');
    return idx == -1 ? '' : name.substring(idx + 1);
  }
}