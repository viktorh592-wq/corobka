import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/daos/folder_dao.dart';
import '../../data/daos/item_dao.dart';
import '../../data/daos/tag_dao.dart';
import '../../data/models/folder.dart';
import '../../data/models/item.dart';
import '../../data/models/tag.dart';
import '../images/image_service.dart';
import '../images/metadata_service.dart';
import '../images/palette_service.dart';
import '../search/search_service.dart';

/// Высокоуровневый сервис работы с коллекцией.
class CollectionService {
  CollectionService({
    FolderDao? folderDao,
    ItemDao? itemDao,
    TagDao? tagDao,
    SearchService? search,
    ImageService? imageService,
    MetadataService? metadataService,
    PaletteService? paletteService,
  })  : _folderDao = folderDao ?? const FolderDao(),
        _itemDao = itemDao ?? const ItemDao(),
        _tagDao = tagDao ?? const TagDao(),
        _search = search ?? const SearchService(),
        _imageService = imageService ?? const ImageService(),
        _metadataService = metadataService ?? const MetadataService(),
        _paletteService = paletteService ?? const PaletteService();

  final FolderDao _folderDao;
  final ItemDao _itemDao;
  final TagDao _tagDao;
  final SearchService _search;
  final ImageService _imageService;
  final MetadataService _metadataService;
  final PaletteService _paletteService;

  /// Корневой каталог коллекции.
  String? _rootPath;

  /// Инициализация корневого каталога коллекции.
  Future<void> initializeRoot({String? customPath}) async {
    if (customPath != null && customPath.trim().isNotEmpty) {
      _rootPath = customPath.trim();
    } else {
      _rootPath = await _defaultRootPath();
    }
    final dir = Directory(_rootPath!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Путь к каталогу хранения файлов коллекции.
  String get imagesPath {
    final root = _rootPath ?? Directory.current.path;
    return '$root${Platform.pathSeparator}images';
  }

  Future<String> _defaultRootPath() async {
    // Пытаемся использовать каталог поддержки приложения.
    try {
      final dir = await getApplicationSupportDirectory();
      if (dir.path.isNotEmpty) return dir.path;
    } catch (e) {
      debugPrint('getApplicationSupportDirectory error: $e');
    }
    // Запасной вариант — домашний каталог пользователя.
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      final dir = Directory('$home${Platform.pathSeparator}korobka');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir.path;
    }
    // Последний запасной вариант — текущий каталог.
    return Directory.current.path;
  }

  // ─────────── ПАПКИ ───────────

  Future<List<Folder>> getFolders() => _folderDao.getAll();

  Future<int> createFolder(String name) => _folderDao.insert(
        Folder(
          id: 0,
          name: name,
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ),
      );

  Future<int> renameFolder(int id, String newName) =>
      _folderDao.rename(id, newName);

  Future<int> deleteFolder(int id) => _folderDao.delete(id);

  // ─────────── ЭЛЕМЕНТЫ ───────────

  Future<List<CollectionItem>> getItems({int? folderId}) =>
      _itemDao.getAll(folderId: folderId);

  Future<List<CollectionItem>> getFavorites() => _search.search(
        favoritesOnly: true,
      );

  Future<CollectionItem> addItem({
    required String sourcePath,
    int? folderId,
  }) async {
    final imagesDir = imagesPath;
    final targetPath =
        await _imageService.copyToDirectory(sourcePath, imagesDir);

    final metadata = await _metadataService.extractMetadata(targetPath);
    final palette = await _paletteService.extractPalette(targetPath);

    final title = targetPath.split(Platform.pathSeparator).last;

    final item = CollectionItem(
      id: 0,
      folderId: folderId,
      title: title,
      path: targetPath,
      width: metadata['width'] as int?,
      height: metadata['height'] as int?,
      format: (metadata['format'] as String?) ?? _extensionOf(targetPath),
      palette: palette,
      notes: null,
      isFavorite: false,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    final id = await _itemDao.insert(item);
    return _copyWithId(item, id);
  }

  Future<int> updateItemAnnotations(
    int id, {
    String? title,
    String? notes,
  }) =>
      _itemDao.updateAnnotations(id, title: title, notes: notes);

  Future<int> setFavorite(int id, bool isFavorite) =>
      _itemDao.setFavorite(id, isFavorite);

  Future<int> moveItemToFolder(int id, int? folderId) =>
      _itemDao.moveToFolder(id, folderId);

  // ─────────── ТЕГИ ───────────

  Future<List<Tag>> getTags() => _tagDao.getAll();

  Future<List<Tag>> getTagsForItem(int itemId) =>
      _tagDao.getTagsForItem(itemId);

  Future<void> addTagToItem(int itemId, String tagName) async {
    final tagId = await _tagDao.ensureTag(tagName);
    await _tagDao.attachTagToItem(itemId, tagId);
  }

  Future<void> removeTagFromItem(int itemId, int tagId) =>
      _tagDao.detachTagFromItem(itemId, tagId);

  // ─────────── ПОИСК ───────────

  Future<List<CollectionItem>> searchItems({
    String? query,
    int? folderId,
    bool favoritesOnly = false,
    List<int>? tagIds,
    String? format,
    int? createdBefore,
    int? createdAfter,
    String? paletteColor,
  }) {
    return _search.search(
      query: query,
      folderId: folderId,
      favoritesOnly: favoritesOnly,
      tagIds: tagIds,
      format: format,
      before: createdBefore == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(createdBefore * 1000),
      after: createdAfter == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(createdAfter * 1000),
      paletteColor: paletteColor,
    );
  }

  // ─────────── ВСПОМОГАТЕЛЬНОЕ ───────────

  CollectionItem _copyWithId(CollectionItem item, int id) {
    return CollectionItem(
      id: id,
      folderId: item.folderId,
      title: item.title,
      path: item.path,
      width: item.width,
      height: item.height,
      format: item.format,
      palette: item.palette,
      notes: item.notes,
      isFavorite: item.isFavorite,
      createdAt: item.createdAt,
    );
  }

  String _extensionOf(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final idx = name.lastIndexOf('.');
    return idx == -1 ? '' : name.substring(idx + 1);
  }
}
