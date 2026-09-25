import 'dart:io';

import 'package:crypto/crypto.dart';
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

  /// Текущий корневой каталог (для отображения в настройках).
  String? get rootPath => _rootPath;

  /// Открытие диалога выбора нового корневого каталога коллекции.
  Future<String?> pickRootDirectory() => _imageService.pickDirectory();

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

  /// Каталог превью-кадров видео (скрытая папка в корне коллекции).
  String get thumbnailsPath {
    final root = _rootPath ?? Directory.current.path;
    return '$root${Platform.pathSeparator}.thumbs';
  }

  /// Путь к файлу превью для исходного видеофайла (по хэшу полного пути —
  /// без коллизий и без изменения схемы БД).
  String thumbnailPathFor(String sourcePath) {
    final key = md5.convert(sourcePath.codeUnits).toString();
    return '$thumbnailsPath${Platform.pathSeparator}$key.jpg';
  }

  /// Создание каталога превью (если его ещё нет).
  Future<void> ensureThumbnailsDir() async {
    final dir = Directory(thumbnailsPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Список всех существующих файлов превью (полные пути).
  Future<List<String>> listThumbnailPaths() async {
    try {
      final dir = Directory(thumbnailsPath);
      if (!await dir.exists()) return const [];
      final result = <String>[];
      await for (final entity in dir.list()) {
        if (entity is File) result.add(entity.path);
      }
      return result;
    } catch (e) {
      debugPrint('listThumbnailPaths error: $e');
      return const [];
    }
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

  /// Прямые дочерние папки указанного родителя (null = корневые).
  Future<List<Folder>> getSubfolders(int? parentId) =>
      _folderDao.getChildren(parentId);

  Future<int> createFolder(String name, {int? parentId}) => _folderDao.insert(
        Folder(
          id: 0,
          name: name,
          parentId: parentId,
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ),
      );

  /// Создание подпапки внутри указанного родителя.
  Future<int> createSubfolder(String name, int parentId) =>
      _folderDao.insert(
        Folder(
          id: 0,
          name: name,
          parentId: parentId,
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ),
      );

  Future<int> renameFolder(int id, String newName) =>
      _folderDao.rename(id, newName);

  /// Установка цвета иконки папки (HEX без решётки либо null — сброс).
  Future<int> setFolderColor(int id, String? hexColor) =>
      _folderDao.setColor(id, hexColor);

  Future<int> deleteFolder(int id) => _folderDao.delete(id);

  // ─────────── ЭЛЕМЕНТЫ ───────────

  Future<List<CollectionItem>> getItems({int? folderId}) =>
      _itemDao.getAll(folderId: folderId);

  /// Элементы в корзине.
  Future<List<CollectionItem>> getTrashed() => _itemDao.getTrashed();

  /// Количество активных элементов по папкам (для счётчиков в левой панели).
  Future<Map<int?, int>> countByFolder() => _itemDao.countByFolder();

  Future<List<CollectionItem>> getFavorites() => _search.search(
        favoritesOnly: true,
      );

  /// Перемещение элемента в корзину (мягкое удаление, как в Eagle).
  Future<void> moveItemToTrash(int id) async {
    await _itemDao.moveToTrash(
      id,
      deletedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  /// Восстановление элемента из корзины.
  Future<void> restoreItemFromTrash(int id) =>
      _itemDao.restoreFromTrash(id);

  /// Полное удаление элемента: файл на диске и запись в БД.
  Future<void> purgeItem(CollectionItem item) async {
    try {
      final file = File(item.path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Файл мог быть перемещён/удалён пользователем — запись всё равно
      // удаляем, чтобы не оставлять «битых» элементов в коллекции.
      debugPrint('purgeItem: не удалось удалить файл: $e');
    }
    await _itemDao.delete(item.id);
  }

  /// Очистка корзины: полное удаление всех элементов в ней.
  Future<int> emptyTrash() async {
    final trashed = await _itemDao.getTrashed();
    for (final item in trashed) {
      await purgeItem(item);
    }
    return trashed.length;
  }

  Future<CollectionItem> addItem({
    required String sourcePath,
    int? folderId,
  }) async {
    final imagesDir = imagesPath;
    final targetPath =
        await _imageService.copyToDirectory(sourcePath, imagesDir);

    final isMedia =
        _imageService.isVideo(targetPath) || _imageService.isAudio(targetPath);

    // Метаданные извлекаем в фоновом изоляте — UI не «замирает»
    // при импорте больших изображений.
    final metadata =
        await _metadataService.extractMetadataInBackground(targetPath);
    final palette =
        isMedia ? null : await _paletteService.extractPalette(targetPath);

    // SHA-256 хэш содержимого — для поиска дубликатов. Считаем в изоляте,
    // чтобы большие файлы не блокировали UI.
    final hash = await compute(_hashFileSync, targetPath);

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
      hash: hash,
    );

    final id = await _itemDao.insert(item);
    return _copyWithId(item, id);
  }

  /// Синхронное вычисление SHA-256 файла (исполняется в изоляте).
  static String? _hashFileSync(String path) {
    try {
      final bytes = File(path).readAsBytesSync();
      return sha256.convert(bytes).toString();
    } catch (_) {
      return null;
    }
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

  /// Пересчёт цветовой палитры для одного элемента.
  ///
  /// Используется после увеличения `maximumColorCount` в [PaletteService]:
  /// старые записи в БД хранят палитру из 5 цветов и не обновятся
  /// автоматически — нужно явное пересчитывание.
  Future<String?> regeneratePalette(CollectionItem item) async {
    if (item.isVideo || item.isAudio) return null;
    final palette = await _paletteService.extractPalette(item.path);
    if (palette != null) {
      await _itemDao.updatePalette(item.id, palette);
    }
    return palette;
  }

  /// Массовый пересчёт палитры для всех изображений коллекции.
  ///
  /// Возвращает количество обработанных элементов. [onProgress] вызывается
  /// после каждого элемента с индексом и общим числом — для прогресс-бара.
  Future<int> regenerateAllPalettes({
    void Function(int done, int total)? onProgress,
  }) async {
    final items = await _itemDao.allActiveItems();
    final images =
        items.where((e) => !e.isVideo && !e.isAudio).toList();
    var done = 0;
    for (final item in images) {
      try {
        await regeneratePalette(item);
      } catch (e) {
        // Не валим весь процесс из-за одной битой картинки.
        debugPrint('Palette regen failed for ${item.path}: $e');
      }
      done++;
      onProgress?.call(done, images.length);
    }
    return done;
  }

  // ─────────── ТЕГИ ───────────

  Future<List<Tag>> getTags() => _tagDao.getAll();

  /// Теги с количеством связанных элементов.
  Future<List<(Tag, int)>> getTagsWithCounts() => _tagDao.getAllWithCounts();

  Future<List<Tag>> getTagsForItem(int itemId) =>
      _tagDao.getTagsForItem(itemId);

  Future<void> addTagToItem(int itemId, String tagName) async {
    final tagId = await _tagDao.ensureTag(tagName);
    await _tagDao.attachTagToItem(itemId, tagId);
  }

  Future<void> removeTagFromItem(int itemId, int tagId) =>
      _tagDao.detachTagFromItem(itemId, tagId);

  /// Установка BPM аудиофайла с автоматическим тегом `BPM <значение>`.
  ///
  /// Предыдущий BPM-тег элемента удаляется, новый привязывается.
  /// `bpm == null` — сброс значения и тега.
  Future<void> setItemBpm(int itemId, int? bpm) async {
    await _itemDao.updateBpm(itemId, bpm);

    // Удаляем прежние BPM-теги этого элемента.
    final currentTags = await _tagDao.getTagsForItem(itemId);
    for (final tag in currentTags) {
      if (tag.name.toUpperCase().startsWith('BPM ')) {
        await _tagDao.detachTagFromItem(itemId, tag.id);
      }
    }

    if (bpm != null) {
      final tagId = await _tagDao.ensureTag('BPM $bpm');
      await _tagDao.attachTagToItem(itemId, tagId);
    }
  }

  // ─────────── ДУБЛИКАТЫ ───────────

  /// Группы дубликатов (одинаковый хэш содержимого файла).
  Future<List<List<CollectionItem>>> getDuplicateGroups() =>
      _itemDao.getDuplicateGroups();

  /// Обратное заполнение хэшей для элементов, импортированных раньше
  /// появления функции дубликатов. Возвращает число обновлённых записей.
  Future<int> backfillHashes() async {
    final pending = await _itemDao.getWithoutHash();
    var updated = 0;
    for (final item in pending) {
      final hash = await compute(_hashFileSync, item.path);
      if (hash != null) {
        await _itemDao.updateHash(item.id, hash);
        updated++;
      }
    }
    return updated;
  }

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
    String? paletteColorSimilar,
    double colorTolerance = 0.15,
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
      paletteColorSimilar: paletteColorSimilar,
      colorTolerance: colorTolerance,
    );
  }

  // ─────────── СИСТЕМНЫЙ ПЛЕЕР ───────────

  /// Открытие файла системным проигрывателем (видео/аудио и др.).
  Future<void> openWithSystemPlayer(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      }
    } catch (e) {
      debugPrint('openWithSystemPlayer error: $e');
      rethrow;
    }
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
      hash: item.hash,
      bpm: item.bpm,
    );
  }

  String _extensionOf(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final idx = name.lastIndexOf('.');
    return idx == -1 ? '' : name.substring(idx + 1);
  }
}
