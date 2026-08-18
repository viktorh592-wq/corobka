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

/// Состояние коллекции.
///
/// Хранит выбранную папку, режим просмотра, поисковый запрос, фильтр по цвету
/// и загруженные данные коллекции. Обеспечивает импорт, управление
/// папками/тегами, избранное, аннотации, поиск, фильтрацию, умные папки
/// и экспорт.
class CollectionState extends ChangeNotifier {
  CollectionState({
    CollectionService? service,
    SettingsRepository? settings,
  })  : _service = service ?? CollectionService(),
        _settings = settings ?? SettingsRepository(),
        _importController =
            ImportController(collection: service ?? CollectionService());

  final CollectionService _service;
  final SettingsRepository _settings;
  final SmartFolderService _smartFolders = const SmartFolderService();
  final ImportController _importController;

  String _selectedFolderId = 'all';
  ViewMode _viewMode = ViewMode.grid;
  String _searchQuery = '';
  String? _filterColor;

  List<Folder> _folders = const [];
  List<CollectionItem> _items = const [];
  List<Tag> _tags = const [];

  CollectionItem? _selectedItem;
  List<Tag> _selectedItemTags = const [];

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  /// Доступ к сервису коллекции (для drag-and-drop контроллера).
  CollectionService get collectionService => _service;

  /// Контроллер импорта (drag-and-drop, выбор файлов/папки).
  ImportController get importController => _importController;

  /// Идентификатор выбранной папки (по умолчанию — «Все»).
  String get selectedFolderId => _selectedFolderId;

  /// Текущий режим просмотра.
  ViewMode get viewMode => _viewMode;

  /// Текущий поисковый запрос.
  String get searchQuery => _searchQuery;

  /// Выбранный цвет для фильтрации палитры.
  String? get filterColor => _filterColor;

  /// Список папок коллекции.
  List<Folder> get folders => _folders;

  /// Текущий список элементов (с учётом фильтра по папке).
  List<CollectionItem> get items => _items;

  /// Список всех тегов коллекции.
  List<Tag> get tags => _tags;

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

  /// Инициализация коллекции: настройка корневого каталога и загрузка данных.
  Future<void> initialize() async {
    final savedRoot = await _settings.loadRootPath();
    await _service.initializeRoot(customPath: savedRoot);

    final savedView = await _settings.loadViewMode();
    if (savedView != null) {
      final parsed = ViewMode.values.asNameMap()[savedView];
      if (parsed != null) _viewMode = parsed;
    }

    await _load();
  }

  /// Загрузка папок, элементов и тегов из базы данных.
  Future<void> _load() async {
    _isLoading = true;
    notifyListeners();

    _folders = await _service.getFolders();
    _tags = await _service.getTags();
    _items = await _loadItems();
    _isLoading = false;
    notifyListeners();
  }

  /// Загрузка элементов с учётом выбранного раздела, поиска и фильтра по цвету.
  Future<List<CollectionItem>> _loadItems() async {
    final folderId = int.tryParse(_selectedFolderId);
    final favorites = _selectedFolderId == 'favorites';

    // При активном поиске применяем полнотекстовый поиск с фильтрами.
    if (_searchQuery.trim().isNotEmpty || _filterColor != null) {
      return _service.searchItems(
        query: _searchQuery,
        folderId: folderId,
        favoritesOnly: favorites,
        paletteColor: _filterColor,
      );
    }

    switch (_selectedFolderId) {
      case 'all':
        return _service.getItems();
      case 'favorites':
        return _service.getFavorites();
      default:
        if (folderId == null) return _service.getItems();
        return _service.getItems(folderId: folderId);
    }
  }

  /// Публичный метод обновления списка элементов (после импорта).
  Future<void> refreshItems() => _loadItemsAndNotify();

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

  /// Выбор папки.
  Future<void> selectFolder(String id) async {
    if (id == _selectedFolderId) return;
    _selectedFolderId = id;
    _selectedItem = null;
    _selectedItemTags = const [];
    notifyListeners();
    await _loadItemsAndNotify();
  }

  /// Переключение режима просмотра.
  Future<void> setViewMode(ViewMode mode) async {
    if (mode == _viewMode) return;
    _viewMode = mode;
    notifyListeners();
    await _settings.saveViewMode(mode.name);
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

  /// Удаление папки.
  Future<void> deleteFolder(int id) async {
    await _service.deleteFolder(id);
    if (_selectedFolderId == id.toString()) {
      _selectedFolderId = 'all';
    }
    await _load();
  }

  // ─────────────────────────── АННОТАЦИИ ───────────────────────────

  /// Обновление названия и заметок выбранного элемента.
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
    await selectItem(item);
    await _loadItemsAndNotify();
  }

  // ─────────────────────────── ИЗБРАННОЕ ───────────────────────────

  /// Переключение флага «избранное» для элемента.
  Future<void> toggleFavorite(CollectionItem item) async {
    final newValue = !item.isFavorite;
    await _service.setFavorite(item.id, newValue);

    if (_selectedItem?.id == item.id) {
      _selectedItem = _copyWith(item, isFavorite: newValue);
    }
    await _loadItemsAndNotify();
  }

  // ─────────────────────────── ТЕГИ ───────────────────────────

  /// Добавление тега к выбранному элементу.
  Future<void> addTagToSelectedItem(String tagName) async {
    final item = _selectedItem;
    if (item == null || tagName.trim().isEmpty) return;

    await _service.addTagToItem(item.id, tagName);
    await selectItem(item);
    await _loadTagsAndNotify();
  }

  /// Удаление тега с выбранного элемента.
  Future<void> removeTagFromSelectedItem(int tagId) async {
    final item = _selectedItem;
    if (item == null) return;

    await _service.removeTagFromItem(item.id, tagId);
    await selectItem(item);
    await _loadTagsAndNotify();
  }

  // ─────────────────────────── ПЕРЕМЕЩЕНИЕ ───────────────────────────

  /// Перемещение выбранного элемента в указанную папку.
  Future<void> moveItemToFolder(int? folderId) async {
    final item = _selectedItem;
    if (item == null) return;

    await _service.moveItemToFolder(item.id, folderId);
    _selectedItem = null;
    _selectedItemTags = const [];
    await _loadItemsAndNotify();
  }

  // ─────────────────────────── УМНЫЕ ПАПКИ ───────────────────────────

  /// Список доступных умных папок.
  List<SmartFolder> getSmartFolders() => _smartFolders.getSmartFolders();

  /// Получение элементов, попадающих в умную папку.
  Future<List<CollectionItem>> getSmartFolderItems(SmartFolder folder) =>
      _smartFolders.getItemsFor(folder);

  // ─────────────────────────── ИМПОРТ ───────────────────────────

  /// Открытие диалога выбора файлов и их импорт.
  Future<void> importFiles() async {
    await _importController.importFiles(folderId: _currentFolderId);
    await _loadItemsAndNotify();
  }

  /// Выбор папки и импорт всех изображений внутри неё.
  Future<void> importDirectory() async {
    await _importController.importDirectory(folderId: _currentFolderId);
    await _loadItemsAndNotify();
  }

  /// Идентификатор выбранной папки (числовой) или `null` для системных разделов.
  int? get _currentFolderId => int.tryParse(_selectedFolderId);

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
    _items = await _loadItems();
    notifyListeners();
  }

  Future<void> _loadTagsAndNotify() async {
    _tags = await _service.getTags();
    notifyListeners();
  }

  CollectionItem _copyWith(
    CollectionItem item, {
    bool? isFavorite,
  }) {
    return CollectionItem(
      id: item.id,
      folderId: item.folderId,
      title: item.title,
      path: item.path,
      width: item.width,
      height: item.height,
      format: item.format,
      palette: item.palette,
      notes: item.notes,
      isFavorite: isFavorite ?? item.isFavorite,
      createdAt: item.createdAt,
    );
  }
}

/// Режимы просмотра коллекции.
enum ViewMode { grid, list }
