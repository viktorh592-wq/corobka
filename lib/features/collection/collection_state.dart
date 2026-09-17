import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../data/models/folder.dart';
import '../../data/models/item.dart';
import '../../data/models/tag.dart';
import '../../data/settings_repository.dart';
import '../images/export_service.dart';
import '../images/import_controller.dart';
import '../images/video_thumbnail_service.dart';
import '../logging/log_service.dart';
import 'collection_service.dart';

/// Режимы просмотра коллекции.
enum ViewMode { grid, list, masonry }

/// Режимы сортировки элементов (как в Eagle).
enum SortMode {
  dateDesc('По дате добавления (сначала новые)'),
  dateAsc('По дате добавления (сначала старые)'),
  nameAsc('По названию (А-Я)'),
  nameDesc('По названию (Я-А)'),
  sizeDesc('По размеру (сначала большие)');

  const SortMode(this.label);
  final String label;
}

/// Состояние коллекции.
///
/// Хранит выбранную папку, режим просмотра, поисковый запрос, фильтры
/// и загруженные данные коллекции. Обеспечивает импорт, управление
/// папками/тегами (с иерархией подпапок), избранное, аннотации, корзину,
/// поиск, фильтрацию и экспорт.
class CollectionState extends ChangeNotifier {
  CollectionState({
    CollectionService? service,
    SettingsRepository? settings,
  })  : _service = service ?? CollectionService(),
        _settings = settings ?? SettingsRepository() {
    // ВАЖНО: импортёр обязан использовать ТОТ ЖЕ экземпляр сервиса, что и
    // состояние, иначе у него не инициализирован корневой каталог коллекции
    // и файлы копировались бы в случайный каталог (Directory.current/images).
    _importController = ImportController(
      collection: _service,
      onVideoImported: _ensureVideoThumbnail,
    );
    _importController.addListener(_onImportProgress);
  }

  final CollectionService _service;
  final SettingsRepository _settings;
  late final ImportController _importController;

  /// Реакция на прогресс импорта (уведомляем UI о ходе копирования).
  void _onImportProgress() => notifyListeners();

  String _selectedFolderId = 'all';
  ViewMode _viewMode = ViewMode.grid;
  String _searchQuery = '';
  String? _filterColor;
  double _filterColorTolerance = 0.15;
  int? _filterTagId;
  SortMode _sortMode = SortMode.dateDesc;
  double _thumbnailExtent = 200;

  List<Folder> _folders = const [];
  List<CollectionItem> _items = const [];
  List<Tag> _tags = const [];
  Map<int, int> _tagCounts = const {};
  Map<int?, int> _folderCounts = const {};

  CollectionItem? _selectedItem;
  List<Tag> _selectedItemTags = const [];

  /// Пути исходных видеофайлов, для которых есть превью-кадр.
  /// Синхронный Set — карточки не делают дисковых проверок при сборке.
  final Set<String> _videoThumbnails = <String>{};

  /// Есть ли превью-кадр у видеофайла с путём [sourcePath].
  bool hasVideoThumbnail(String sourcePath) =>
      _videoThumbnails.contains(sourcePath);

  /// Путь к файлу превью для видеофайла или `null`, если превью нет.
  String? videoThumbnailPath(String sourcePath) =>
      _videoThumbnails.contains(sourcePath)
          ? _service.thumbnailPathFor(sourcePath)
          : null;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  /// Последнее сообщение об ошибке (для SnackBar в UI). `null` — ошибок нет.
  /// Присвоение ненулевого значения фиксируется в журнале (LogService).
  String? _lastError;
  String? get lastError => _lastError;
  set lastError(String? value) {
    _lastError = value;
    if (value != null) {
      LogService.instance.add('ERROR', value);
    }
  }

  /// Сбрасывает показанную ошибку.
  void clearError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  /// Доступ к сервису коллекции (для drag-and-drop контроллера).
  CollectionService get collectionService => _service;

  /// Контроллер импорта (drag-and-drop, выбор файлов/папки).
  ImportController get importController => _importController;

  /// Идёт ли импорт файлов прямо сейчас.
  bool get isImporting => _importController.isImporting;

  /// Сколько файлов импортировано в текущей операции.
  int get importedCount => _importController.importedCount;

  /// Идентификатор выбранной папки (по умолчанию — «Все»).
  String get selectedFolderId => _selectedFolderId;

  /// Текущий режим просмотра.
  ViewMode get viewMode => _viewMode;

  /// Текущий поисковый запрос.
  String get searchQuery => _searchQuery;

  /// Выбранный цвет для фильтрации палитры.
  String? get filterColor => _filterColor;

  /// Допустимое расстояние до выбранного цвета (0 = точное совпадение,
  /// 1 = любые цвета). По умолчанию 0.15 — «похожий оттенок».
  double get filterColorTolerance => _filterColorTolerance;

  /// Выбранный тег для фильтрации.
  int? get filterTagId => _filterTagId;

  /// Текущий режим сортировки.
  SortMode get sortMode => _sortMode;

  /// Максимальный размер превью в сетке (слайдер зума как в Eagle).
  double get thumbnailExtent => _thumbnailExtent;

  /// Список папок коллекции.
  List<Folder> get folders => _folders;

  /// Текущий список элементов (с учётом фильтра по папке).
  List<CollectionItem> get items => _items;

  /// Список всех тегов коллекции.
  List<Tag> get tags => _tags;

  /// Количество элементов для каждого тега (по id тега).
  Map<int, int> get tagCounts => _tagCounts;

  /// Счётчики элементов по папкам (ключ `null` — элементы вне папок).
  Map<int?, int> get folderCounts => _folderCounts;

  /// Выбранный элемент (для правой панели деталей).
  CollectionItem? get selectedItem => _selectedItem;

  /// Теги выбранного элемента.
  List<Tag> get selectedItemTags => _selectedItemTags;

  /// Индекс выбранного элемента в текущем списке (для lightbox-навигации).
  int get selectedItemIndex {
    if (_selectedItem == null) return 0;
    final idx = _items.indexWhere((e) => e.id == _selectedItem!.id);
    return idx < 0 ? 0 : idx;
  }

  /// Открыта ли сейчас корзина.
  bool get isTrashView => _selectedFolderId == 'trash';

  /// Инициализация коллекции: настройка корневого каталога и загрузка данных.
  Future<void> initialize() async {
    try {
      String? savedRoot;
      try {
        savedRoot = await _settings.loadRootPath();
      } catch (e) {
        debugPrint('loadRootPath error: $e');
      }

      try {
        await _service.initializeRoot(customPath: savedRoot);
      } catch (e) {
        debugPrint('initializeRoot error: $e');
        // Даже при ошибке пробуем дефолтный путь, чтобы не было null.
        try {
          await _service.initializeRoot(customPath: null);
        } catch (_) {}
      }

      String? savedView;
      try {
        savedView = await _settings.loadViewMode();
        if (savedView != null) {
          final parsed = ViewMode.values.asNameMap()[savedView];
          if (parsed != null) _viewMode = parsed;
        }
      } catch (e) {
        debugPrint('loadViewMode error: $e');
      }

      try {
        final savedExtent = await _settings.loadThumbnailExtent();
        if (savedExtent != null) _thumbnailExtent = savedExtent;
      } catch (e) {
        debugPrint('loadThumbnailExtent error: $e');
      }

      String? savedSort;
      try {
        savedSort = await _settings.loadSortMode();
        final parsed = SortMode.values.asNameMap()[savedSort];
        if (parsed != null) _sortMode = parsed;
      } catch (e) {
        debugPrint('loadSortMode error: $e');
      }

      await _load();

      // Превью видео достраиваем в фоне — UI не ждёт декодирования.
      unawaited(_backfillVideoThumbnails());
    } catch (e, stack) {
      debugPrint('initialize error: $e\n$stack');
      _lastError = 'Ошибка запуска: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Загрузка папок, элементов, тегов и счётчиков из базы данных.
  Future<void> _load() async {
    _isLoading = true;
    notifyListeners();

    _folders = await _service.getFolders();
    await _loadTags();
    _folderCounts = await _service.countByFolder();
    _items = _applySort(await _loadItems());
    await _loadVideoThumbnails();
    _isLoading = false;
    notifyListeners();
  }

  /// Перечитывает список существующих файлов превью из каталога .thumbs.
  Future<void> _loadVideoThumbnails() async {
    try {
      final files = await _service.listThumbnailPaths();
      final known = files.toSet();
      // Оставляем только те пути видео, чьё превью реально существует.
      _videoThumbnails
        ..clear()
        ..addAll(_items
            .where((i) => i.isVideo && known.contains(_service.thumbnailPathFor(i.path)))
            .map((i) => i.path));
    } catch (e) {
      debugPrint('loadVideoThumbnails error: $e');
    }
  }

  /// Достраивает превью для видео без кадра (после запуска приложения).
  Future<void> _backfillVideoThumbnails() async {
    try {
      final all = await _service.getItems();
      for (final item in all) {
        if (!item.isVideo) continue;
        if (!VideoThumbnailService.instance.isAvailable) return;
        if (_videoThumbnails.contains(item.path)) continue;
        await _ensureVideoThumbnail(item.path);
      }
    } catch (e) {
      debugPrint('backfillVideoThumbnails error: $e');
    }
  }

  /// Гарантирует наличие превью-кадра для видеофайла (извлекает при
  /// отсутствии). Вызывается при импорте и в фоновом достраивании.
  Future<void> _ensureVideoThumbnail(String videoPath) async {
    final thumbPath = _service.thumbnailPathFor(videoPath);
    try {
      if (File(thumbPath).existsSync()) {
        if (_videoThumbnails.add(videoPath)) notifyListeners();
        return;
      }
      await _service.ensureThumbnailsDir();
      final saved = await VideoThumbnailService.instance
          .extractToFile(videoPath, thumbPath);
      if (saved != null) {
        _videoThumbnails.add(videoPath);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('ensureVideoThumbnail error: $e');
    }
  }

  /// Загрузка элементов с учётом выбранного раздела, поиска и фильтров.
  Future<List<CollectionItem>> _loadItems() async {
    final folderId = int.tryParse(_selectedFolderId);
    final favorites = _selectedFolderId == 'favorites';

    // При активном поиске применяем полнотекстовый поиск с фильтрами.
    if (_searchQuery.trim().isNotEmpty ||
        _filterColor != null ||
        _filterTagId != null) {
      return _service.searchItems(
        query: _searchQuery,
        folderId: folderId,
        favoritesOnly: favorites,
        // Поиск по цвету использует новый путь с похожими оттенками:
        // вычисляется RGB-расстояние до цветов палитры элемента.
        paletteColorSimilar: _filterColor,
        colorTolerance: _filterColorTolerance,
        tagIds: _filterTagId == null ? null : [_filterTagId!],
      );
    }

    switch (_selectedFolderId) {
      case 'all':
        return _service.getItems();
      case 'favorites':
        return _service.getFavorites();
      case 'trash':
        return _service.getTrashed();
      default:
        if (folderId == null) return _service.getItems();
        return _service.getItems(folderId: folderId);
    }
  }

  /// Применяет текущую сортировку к списку элементов.
  List<CollectionItem> _applySort(List<CollectionItem> items) {
    final sorted = [...items];
    switch (_sortMode) {
      case SortMode.dateDesc:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case SortMode.dateAsc:
        sorted.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case SortMode.nameAsc:
        sorted.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case SortMode.nameDesc:
        sorted.sort(
          (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        );
      case SortMode.sizeDesc:
        sorted.sort((a, b) => b.pixelArea.compareTo(a.pixelArea));
    }
    return sorted;
  }

  /// Публичный метод обновления списка элементов (после импорта).
  Future<void> refreshItems() => _loadItemsAndNotify();

  // ─────────────────────────── ФИЛЬТРЫ И ПОИСК ───────────────────────────

  /// Установка поискового запроса и обновление результатов.
  Future<void> setSearchQuery(String query) async {
    if (query == _searchQuery) return;
    _searchQuery = query;
    _selectedItem = null;
    _selectedItemTags = const [];
    notifyListeners();
    await _loadItemsAndNotify();
  }

  /// Сброс поискового запроса.
  Future<void> clearSearch() => setSearchQuery('');

  /// Установка фильтра по цвету палитры.
  ///
  /// [tolerance] — допустимое нормализованное RGB-расстояние (0 = точное
  /// совпадение, 1 = любые цвета). По умолчанию 0.15 — «похожий оттенок».
  /// Используется новый путь поиска с вычислением расстояния между целевым
  /// цветом и цветами палитры каждого элемента.
  Future<void> setColorFilter(
    String colorHex, {
    double tolerance = 0.15,
  }) async {
    if (colorHex == _filterColor && tolerance == _filterColorTolerance) return;
    _filterColor = colorHex;
    _filterColorTolerance = tolerance;
    notifyListeners();
    await _loadItemsAndNotify();
  }

  /// Сброс фильтра по цвету.
  Future<void> clearColorFilter() async {
    if (_filterColor == null) return;
    _filterColor = null;
    _filterColorTolerance = 0.15;
    notifyListeners();
    await _loadItemsAndNotify();
  }

  /// Фильтрация по тегу (клик по тегу в левой панели).
  Future<void> setTagFilter(int? tagId) async {
    if (tagId == _filterTagId) return;
    _filterTagId = tagId;
    _selectedItem = null;
    _selectedItemTags = const [];
    notifyListeners();
    await _loadItemsAndNotify();
  }

  /// Установка режима сортировки.
  Future<void> setSortMode(SortMode mode) async {
    if (mode == _sortMode) return;
    _sortMode = mode;
    notifyListeners();
    try {
      await _settings.saveSortMode(mode.name);
    } catch (e) {
      debugPrint('saveSortMode error: $e');
    }
    await _loadItemsAndNotify();
  }

  /// Изменение размера превью (слайдер зума сетки).
  Future<void> setThumbnailExtent(double extent) async {
    if (extent == _thumbnailExtent) return;
    _thumbnailExtent = extent;
    notifyListeners();
    try {
      await _settings.saveThumbnailExtent(extent);
    } catch (e) {
      debugPrint('saveThumbnailExtent error: $e');
    }
  }

  // ─────────────────────────── НАВИГАЦИЯ ───────────────────────────

  /// Выбор папки/раздела.
  Future<void> selectFolder(String id) async {
    if (id == _selectedFolderId) return;
    _selectedFolderId = id;
    _selectedItem = null;
    _selectedItemTags = const [];
    _filterTagId = null;
    // Массовое выделение сбрасываем — идентификаторы другого списка.
    _multiSelectedIds.clear();
    _multiSelectAnchorId = null;
    notifyListeners();
    await _loadItemsAndNotify();
  }

  /// Переключение режима просмотра.
  Future<void> setViewMode(ViewMode mode) async {
    if (mode == _viewMode) return;
    _viewMode = mode;
    notifyListeners();
    try {
      await _settings.saveViewMode(mode.name);
    } catch (e) {
      debugPrint('saveViewMode error: $e');
    }
  }

  /// Выбор элемента для просмотра в правой панели.
  Future<void> selectItem(CollectionItem item) async {
    _selectedItem = item;
    _selectedItemTags = await _service.getTagsForItem(item.id);
    notifyListeners();
  }

  // ─────────────────────── МАССОВОЕ ВЫДЕЛЕНИЕ ───────────────────────

  /// Идентификаторы выбранных элементов (Ctrl/Shift-клик, Ctrl+A).
  final Set<int> _multiSelectedIds = <int>{};

  /// «Якорь» для диапазонного выделения по Shift.
  int? _multiSelectAnchorId;

  /// Идентификаторы выбранных элементов (только для чтения).
  Set<int> get multiSelectedIds => Set.unmodifiable(_multiSelectedIds);

  /// Есть ли активное массовое выделение.
  bool get hasMultiSelection => _multiSelectedIds.isNotEmpty;

  /// Выбран ли элемент в массовом выделении.
  bool isMultiSelected(CollectionItem item) =>
      _multiSelectedIds.contains(item.id);

  /// Обработка клика по карточке с учётом модификаторов (Ctrl/Shift).
  ///
  ///  - обычный клик: сброс выделения + выбор элемента (как раньше);
  ///  - Ctrl+клик: добавить/убрать элемент из выделения;
  ///  - Shift+клик: выделить диапазон от «якоря» до элемента.
  void handleCardTap(CollectionItem item) {
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    if (ctrl && !shift) {
      if (!_multiSelectedIds.remove(item.id)) {
        _multiSelectedIds.add(item.id);
      }
      _multiSelectAnchorId ??= item.id;
      notifyListeners();
      return;
    }

    if (shift) {
      final anchor = _multiSelectAnchorId ?? item.id;
      final a = _items.indexWhere((e) => e.id == anchor);
      final b = _items.indexWhere((e) => e.id == item.id);
      if (a >= 0 && b >= 0) {
        _multiSelectedIds
          ..clear()
          ..addAll([
            for (var i = math.min(a, b); i <= math.max(a, b); i++)
              _items[i].id,
          ]);
        notifyListeners();
      }
      return;
    }

    // Обычный клик: если было массовое выделение — снимаем его.
    if (_multiSelectedIds.isNotEmpty) {
      _multiSelectedIds.clear();
      notifyListeners();
    }
    selectItem(item);
  }

  /// Выделить все элементы текущего списка (Ctrl+A).
  void selectAllItems() {
    if (_items.isEmpty) return;
    _multiSelectAnchorId ??= _items.first.id;
    _multiSelectedIds
      ..clear()
      ..addAll([for (final item in _items) item.id]);
    notifyListeners();
  }

  /// Снять массовое выделение.
  void clearMultiSelection() {
    if (_multiSelectedIds.isEmpty) return;
    _multiSelectAnchorId = null;
    _multiSelectedIds.clear();
    notifyListeners();
  }

  /// Перемещение набора элементов в папку (null — в корень коллекции).
  Future<void> moveItemsToFolder(List<int> ids, int? folderId) async {
    if (ids.isEmpty) return;
    for (final id in ids) {
      try {
        await _service.moveItemToFolder(id, folderId);
      } catch (e) {
        debugPrint('moveItemsToFolder: элемент $id — ошибка: $e');
      }
    }
    _multiSelectedIds.clear();
    _multiSelectAnchorId = null;
    if (_selectedItem != null && ids.contains(_selectedItem!.id)) {
      _selectedItem =
          _selectedItem!.copyWith(folderId: folderId, clearFolderId: folderId == null);
    }
    await _loadItemsAndNotify();
  }

  /// Перемещение выделенных элементов в корзину.
  Future<void> trashSelectedItems() async {
    if (_multiSelectedIds.isEmpty) return;
    final ids = _multiSelectedIds.toList();
    for (final id in ids) {
      try {
        await _service.moveItemToTrash(id);
      } catch (e) {
        debugPrint('trashSelectedItems: элемент $id — ошибка: $e');
      }
    }
    if (_selectedItem != null && ids.contains(_selectedItem!.id)) {
      _selectedItem = null;
      _selectedItemTags = const [];
    }
    _multiSelectedIds.clear();
    _multiSelectAnchorId = null;
    await _load();
  }

  // ─────────────────────────── ПАПКИ ───────────────────────────

  /// Создание новой корневой папки.
  Future<void> createFolder(String name) async {
    await _service.createFolder(name);
    await _load();
  }

  /// Создание подпапки внутри указанного родителя.
  /// Иерархия поддерживается через parent_id (см. Folder, FolderDao).
  Future<void> createSubfolder(String name, int parentId) async {
    await _service.createSubfolder(name, parentId);
    await _load();
  }

  /// Список дочерних папок для заданного родителя.
  /// `parentId == null` возвращает корневые папки.
  List<Folder> subfoldersOf(int? parentId) {
    return _folders.where((f) => f.parentId == parentId).toList();
  }

  /// Переименование папки.
  Future<void> renameFolder(int id, String newName) async {
    await _service.renameFolder(id, newName);
    await _load();
  }

  /// Установка цвета иконки папки («настройка цвета папки»).
  /// [hexColor] — HEX-строка без решётки либо `null` для сброса
  /// на стандартный акцентный цвет. Перезагружает только список папок,
  /// чтобы дерево в левой панели мгновенно перекрасилось.
  Future<void> setFolderColor(int id, String? hexColor) async {
    await _service.setFolderColor(id, hexColor);
    _folders = await _service.getFolders();
    notifyListeners();
  }

  /// Удаление папки (элементы остаются в коллекции, но без папки —
  /// как в Eagle, где папка — лишь метка организации). Дочерние подпапки
  /// поднимаются на уровень удаляемой (наследуют её parent_id).
  Future<void> deleteFolder(int id) async {
    await _service.deleteFolder(id);
    if (_selectedFolderId == id.toString()) {
      _selectedFolderId = 'all';
    }
    await _load();
  }

  // ─────────────────────────── АННОТАЦИИ ───────────────────────────

  /// Обновление названия и заметок выбранного элемента.
  ///
  /// ВАЖНО: не перезагружает выбор из БД, а обновляет локальную копию —
  /// иначе текстовые поля правой панели «откатывались» бы при вводе.
  Future<void> updateItemAnnotations({
    String? title,
    String? notes,
  }) async {
    final item = _selectedItem;
    if (item == null) return;

    await _service.updateItemAnnotations(
      item.id,
      title: title,
      notes: notes,
    );

    _selectedItem = item.copyWith(
      title: title,
      notes: notes,
      clearNotes: notes != null && notes.isEmpty,
    );
    notifyListeners();
    await _loadItemsAndNotify();
  }

  // ─────────────────────────── ИЗБРАННОЕ ───────────────────────────

  /// Переключение флага «избранное» для элемента.
  Future<void> toggleFavorite(CollectionItem item) async {
    final newValue = !item.isFavorite;
    await _service.setFavorite(item.id, newValue);

    if (_selectedItem?.id == item.id) {
      _selectedItem = _selectedItem!.copyWith(isFavorite: newValue);
    }
    // Обновляем счётчики и список (элемент может исчезнуть из «Избранного»).
    await _loadItemsAndNotify();
  }

  // ─────────────────────────── ТЕГИ ───────────────────────────

  /// Публичная перезагрузка списка тегов из БД.
  ///
  /// Вызывается левой панелью при раскрытии раздела «Теги» — гарантирует
  /// актуальные данные, даже если уведомление было пропущено.
  Future<void> refreshTags() => _loadTagsAndNotify();

  /// Добавление тега к выбранному элементу.
  ///
  /// Ошибки не «глотаются»: они попадают в [lastError] и видны пользователю.
  Future<void> addTagToSelectedItem(String tagName) async {
    final item = _selectedItem;
    final name = tagName.trim();
    if (item == null || name.isEmpty) return;

    try {
      await _service.addTagToItem(item.id, name);
      await _loadTagsAndNotify();
      await _reloadSelectedItemTags();
    } catch (e) {
      _lastError = 'Не удалось добавить тег: $e';
      notifyListeners();
    }
  }

  /// Удаление тега с выбранного элемента.
  Future<void> removeTagFromSelectedItem(int tagId) async {
    final item = _selectedItem;
    if (item == null) return;

    try {
      await _service.removeTagFromItem(item.id, tagId);
      await _loadTagsAndNotify();
      await _reloadSelectedItemTags();
      // Если активен фильтр по этому тегу — обновляем список элементов.
      if (_filterTagId == tagId) {
        await _loadItemsAndNotify();
      }
    } catch (e) {
      _lastError = 'Не удалось удалить тег: $e';
      notifyListeners();
    }
  }

  /// Загрузка тегов и счётчиков их использования.
  Future<void> _loadTags() async {
    final pairs = await _service.getTagsWithCounts();
    _tags = [for (final (tag, _) in pairs) tag];
    _tagCounts = {for (final (tag, cnt) in pairs) tag.id: cnt};
  }

  Future<void> _reloadSelectedItemTags() async {
    final item = _selectedItem;
    if (item == null) return;
    _selectedItemTags = await _service.getTagsForItem(item.id);
    notifyListeners();
  }

  // ─────────────────────────── ПЕРЕМЕЩЕНИЕ ───────────────────────────

  /// Перемещение выбранного элемента в указанную папку (`null` — в корень).
  Future<void> moveItemToFolder(int? folderId) async {
    final item = _selectedItem;
    if (item == null) return;

    await _service.moveItemToFolder(item.id, folderId);
    _selectedItem = item.copyWith(folderId: folderId, clearFolderId: folderId == null);
    notifyListeners();
    await _loadItemsAndNotify();
  }

  // ─────────────────────────── КОРЗИНА ───────────────────────────

  /// Перемещение элемента в корзину (как в Eagle — удаление обратимо).
  Future<void> trashItem(CollectionItem item) async {
    await _service.moveItemToTrash(item.id);
    if (_selectedItem?.id == item.id) {
      _selectedItem = null;
      _selectedItemTags = const [];
    }
    await _load();
  }

  /// Восстановление элемента из корзины.
  Future<void> restoreItem(CollectionItem item) async {
    await _service.restoreItemFromTrash(item.id);
    if (_selectedItem?.id == item.id) {
      _selectedItem = null;
      _selectedItemTags = const [];
    }
    await _load();
  }

  /// Полное удаление элемента из корзины (файл + запись).
  Future<void> purgeItem(CollectionItem item) async {
    await _service.purgeItem(item);
    if (_selectedItem?.id == item.id) {
      _selectedItem = null;
      _selectedItemTags = const [];
    }
    await _load();
  }

  /// Очистка корзины.
  Future<void> emptyTrash() async {
    await _service.emptyTrash();
    _selectedItem = null;
    _selectedItemTags = const [];
    await _load();
  }

  // ─────────────────────────── ИМПОРТ ───────────────────────────

  /// Открытие диалога выбора файлов и их импорт.
  ///
  /// Ошибки не «проглатываются»: они попадают в [lastError] и показываются
  /// пользователю через SnackBar (раньше любые сбои были невидимыми).
  Future<void> importFiles() async {
    try {
      await _importController.importFiles(folderId: _currentFolderId);
      await _loadItemsAndNotify();
      _lastError = importedCount > 0 ? null : null;
    } catch (e) {
      _lastError = 'Ошибка импорта: $e';
      notifyListeners();
    }
  }

  /// Импорт файлов, пойманных папкой-приёмником «Загрузки/Коробка»
  /// (расширение браузера сохраняет их туда, HotFolderService их приносит).
  ///
  /// Для видео превью-кадр достраивается тем же механизмом,
  /// что и при обычном импорте.
  Future<void> importExternalFiles(List<String> paths, {int? folderId}) async {
    for (final path in paths) {
      try {
        final item = await _service.addItem(sourcePath: path, folderId: folderId);
        // Для видео сразу достраиваем превью-кадр (как в ImportController).
        if (item.isVideo) {
          try {
            await _ensureVideoThumbnail(item.path);
          } catch (e) {
            debugPrint('importExternalFiles: video thumbnail failed: $e');
          }
        }
      } catch (e) {
        rethrow;
      }
    }
    await _loadItemsAndNotify();
  }

  /// Выбор папки и импорт всех изображений внутри неё (рекурсивно).
  Future<void> importDirectory() async {
    try {
      await _importController.importDirectory(folderId: _currentFolderId);
      await _loadItemsAndNotify();
    } catch (e) {
      _lastError = 'Ошибка импорта папки: $e';
      notifyListeners();
    }
  }

  /// Идентификатор выбранной папки (числовой) или `null` для системных разделов.
  int? get _currentFolderId => int.tryParse(_selectedFolderId);

  /// Числовой идентификатор выбранной папки для drag-and-drop импорта.
  /// Для системных разделов (Все/Избранное/Корзина) — `null` (корень).
  int? get currentNumericFolderId => _currentFolderId;

  // ─────────────────────────── НАСТРОЙКИ ───────────────────────────

  /// Текущий корневой каталог коллекции.
  String? get rootPath => _service.rootPath;

  /// Смена корневого каталога коллекции (настройки, как в Eagle).
  Future<void> changeRootPath(String newPath) async {
    if (newPath.trim().isEmpty) return;
    await _service.initializeRoot(customPath: newPath.trim());
    await _settings.saveRootPath(newPath.trim());
    await _load();
  }

  // ─────────────────────────── ЭКСПОРТ ───────────────────────────

  /// Экспорт выбранного элемента в папку на диске.
  Future<ExportResult?> exportSelectedItem() async {
    final item = _selectedItem;
    if (item == null) return null;
    const exportService = ExportService();
    return exportService.exportItems([item]);
  }

  /// Экспорт всех текущих элементов списка в папку на диске.
  Future<ExportResult?> exportCurrentItems() async {
    if (_items.isEmpty) return null;
    const exportService = ExportService();
    return exportService.exportItems(_items);
  }

  // ─────────────────────────── ВСПОМОГАТЕЛЬНОЕ ───────────────────────────

  Future<void> _loadItemsAndNotify() async {
    _items = _applySort(await _loadItems());
    _folderCounts = await _service.countByFolder();
    notifyListeners();
  }

  Future<void> _loadTagsAndNotify() async {
    await _loadTags();
    notifyListeners();
  }

  // ─────────────────────────── BPM ───────────────────────────

  /// Установка BPM выбранного аудиофайла (null — сброс).
  ///
  /// Значение сохраняется и автоматически привязывается тег `BPM <n>`
  /// (прежний BPM-тег снимается). Список тегов и элементы обновляются.
  Future<void> setSelectedItemBpm(int? bpm) async {
    final item = _selectedItem;
    if (item == null) return;

    try {
      await _service.setItemBpm(item.id, bpm);
      _selectedItem = item.copyWith(bpm: bpm, clearBpm: bpm == null);
      notifyListeners();
      await _loadTagsAndNotify();
      await _reloadSelectedItemTags();
    } catch (e) {
      _lastError = 'Не удалось сохранить BPM: $e';
      notifyListeners();
    }
  }

  // ─────────────────────────── ДУБЛИКАТЫ ───────────────────────────

  /// Поиск групп дубликатов (одинаковый хэш содержимого файла).
  Future<List<List<CollectionItem>>> findDuplicates() async {
    try {
      // Сначала досчитываем хэши для старых элементов без хэша.
      await _service.backfillHashes();
      return await _service.getDuplicateGroups();
    } catch (e) {
      _lastError = 'Ошибка поиска дубликатов: $e';
      notifyListeners();
      return const [];
    }
  }

  // ─────────────────────────── СИСТЕМНЫЙ ПЛЕЕР ───────────────────────────

  /// Открытие файла системным проигрывателем (видео/аудио).
  Future<void> openItemExternally(CollectionItem item) async {
    try {
      await _service.openWithSystemPlayer(item.path);
    } catch (e) {
      _lastError = 'Не удалось открыть файл: $e';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _importController.removeListener(_onImportProgress);
    _importController.dispose();
    super.dispose();
  }
}
