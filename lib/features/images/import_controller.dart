import 'package:flutter/foundation.dart';

import '../collection/collection_service.dart';
import 'image_service.dart';
import 'metadata_service.dart';
import 'palette_service.dart';

/// Состояние импорта файлов в коллекцию.
///
/// Управляет процессами добавления изображений: через диалог выбора файлов,
/// выбор папки или drag-and-drop.
class ImportController extends ChangeNotifier {
  ImportController({
    required this.collection,
    ImageService? imageService,
    MetadataService? metadataService,
    PaletteService? paletteService,
  })  : _imageService = imageService ?? const ImageService(),
        _metadataService = metadataService ?? const MetadataService(),
        _paletteService = paletteService ?? const PaletteService();

  final CollectionService collection;
  final ImageService _imageService;
  final MetadataService _metadataService;
  final PaletteService _paletteService;

  /// Идёт ли процесс импорта в данный момент.
  bool _isImporting = false;
  bool get isImporting => _isImporting;

  /// Количество успешно импортированных файлов.
  int _importedCount = 0;
  int get importedCount => _importedCount;

  /// Открытие диалога выбора файлов и их добавление в коллекцию.
  Future<void> importFiles({int? folderId}) async {
    final paths = await _imageService.pickImageFiles();
    if (paths.isEmpty) return;
    await _importMany(paths, folderId: folderId);
  }

  /// Выбор папки и импорт всех изображений внутри неё (рекурсивно).
  Future<void> importDirectory({int? folderId}) async {
    final dirPath = await _imageService.pickDirectory();
    if (dirPath == null) return;

    final paths = await _imageService.listImagesInDirectory(dirPath);
    if (paths.isEmpty) return;
    await _importMany(paths, folderId: folderId);
  }

  /// Импорт переданных путей файлов (drag-and-drop).
  Future<void> importPaths(List<String> paths, {int? folderId}) async {
    final supported = paths.where(_imageService.isSupported).toList();
    if (supported.isEmpty) return;
    await _importMany(supported, folderId: folderId);
  }

  /// Последовательный импорт списка файлов.
  Future<void> _importMany(List<String> paths, {int? folderId}) async {
    _isImporting = true;
    _importedCount = 0;
    notifyListeners();

    try {
      for (final path in paths) {
        await collection.addItem(sourcePath: path, folderId: folderId);
        _importedCount++;
        notifyListeners();
      }
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }
}