import 'package:flutter/foundation.dart';

import '../../data/models/folder.dart';
import '../../data/models/item.dart';
import '../../data/models/smart_folder.dart';
import '../../data/models/tag.dart';
import '../../data/settings_repository.dart';
import '../images/export_service.dart';
import '../images/import_controller.dart';
import 'collection_service.dart';
import 'smart_folder_service.dart';

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
/// папками/тегами, избранное, аннотации, корзину, поиск, фильтрацию,
/// умные папки и экспорт.
class CollectionState extends ChangeNotifier {
  CollectionState({
    CollectionService? service,
    SettingsRepository? settings,
  })  : _service = service ?? CollectionService(),
        _settings = settings ?? SettingsRepository() {
    // ВАЖНО: импортёр обязан использовать ТОТ ЖЕ экземпляр сервиса, что и
    // состояние, иначе у него не инициализирован корневой каталог коллекции
    // и файлы копировались бы в случайный каталог (Directory.current/images).
    _importController = ImportController(collection: _service);
    _importController.addListener(_onImportProgress);
  }

  final CollectionService _service;
  final SettingsRepository _settings;
  final SmartFolderService _smartFolders = const SmartFolderService();
  late final ImportController _importController;

  /// Реакция на прогресс импорта (уведомляем UI о ходе копирования).
  void _onImportProgress() => notifyListeners();

  String _selectedFolderId = 'all';
  ViewMode _viewMode = ViewMode.grid;
  String _searchQuery = '';
  String? _filterColor;
  int? _filterTagId;
  SortMode _sortMode = SortMode.dateDesc;
  double _thumbnailExtent = 200;

  List<Folder> _folders = const [];
  List<CollectionItem> _items = const [];
  List<Tag> _tags = const [];
  Map<int?, int> _folderCounts = const {};

  CollectionItem? _selectedItem;
  List<Tag> _selectedItemTags = const [];

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  /// Последнее сообщение об ошибке (для SnackBar в UI). `null` — ошибок нет.
  String? _lastError;
  String? get lastError => _lastError;

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
    _tags = await _service.getTags();
    _folderCounts = await _service.countByFolder();
    _items = _applySort(await _loadItems());
    _isLoading = false;
    notifyListeners();
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
        paletteColor: _filterColor,
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
  Future<void> setColorFilter(String colorHex) async {
    if (colorHex == _filterColor) return;
    _filterColor = colorHex;
    notifyListeners();
    await _loadItemsAndNotify();
  }

  /// Сброс фильтра по цвету.
  Future<void> clearColorFilter() async {
    if (_filterColor == null) return;
    _filterColor = null;
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

  // ─────────────────────────── ПАПКИ ───────────────────────────

  /// Создание новой папки.
  Future<void> createFolder(String name) async {
    await _service.createFolder(name);
    await _load();
  }

  /// Переименование папки.
  Future<void> renameFolder(int id, String newName) async {
    await _service.renameFolder(id, newName);
    await _load();
  }

  /// Удаление папки (элементы остаются в коллекции, но без папки —
  /// как в Eagle, где папка — лишь метка организации).
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

  /// Добавление тега к выбранному элементу.
  Future<void> addTagToSelectedItem(String tagName) async {
    final item = _selectedItem;
    if (item == null || tagName.trim().isEmpty) return;

    await _service.addTagToItem(item.id, tagName);
    await _reloadSelectedItemTags();
    await _loadTagsAndNotify();
  }

  /// Удаление тега с выбранного элемента.
  Future<void> removeTagFromSelectedItem(int tagId) async {
    final item = _selectedItem;
    if (item == null) return;

    await _service.removeTagFromItem(item.id, tagId);
    await _reloadSelectedItemTags();
    // Если активен фильтр по этому тегу — обновляем список элементов.
    if (_filterTagId == tagId) {
      await _loadItemsAndNotify();
    } else {
      await _loadTagsAndNotify();
    }
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

  // ─────────────────────────── УМНЫЕ ПАПКИ ───────────────────────────

  /// Список доступных умных папок.
  List<SmartFolder> getSmartFolders() => _smartFolders.getSmartFolders();

  /// Получение элементов, попадающих в умную папку.
  Future<List<CollectionItem>> getSmartFolderItems(SmartFolder folder) =>
      _smartFolders.getItemsFor(folder);

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
    _tags = await _service.getTags();
    notifyListeners();
  }

  @override
  void dispose() {
    _importController.removeListener(_onImportProgress);
    _importController.dispose();
    super.dispose();
  }
}
