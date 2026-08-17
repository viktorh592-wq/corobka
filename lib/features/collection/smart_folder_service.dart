import '../../data/models/item.dart';
import '../../data/models/smart_folder.dart';
import '../search/search_service.dart';

/// Сервис умных папок.
///
/// Умные папки автоматически группируют элементы коллекции по заданным
/// правилам: теги, цвет палитры, формат, дата. Сервис вычисляет, какие
/// элементы попадают в конкретную умную папку.
class SmartFolderService {
  const SmartFolderService({SearchService? search})
      : _search = search ?? const SearchService();

  final SearchService _search;

  /// Предопределённые правила умных папок.
  ///
  /// Здесь можно добавлять свои правила. Каждое правило автоматически
  /// группирует подходящие элементы.
  static const List<SmartFolderRule> predefinedRules = [
    SmartFolderRule(name: 'Избранное', tagNames: null, format: null),
    SmartFolderRule(
      name: 'Тёплые цвета',
      paletteColor: 'FF5722',
    ),
    SmartFolderRule(
      name: 'Холодные цвета',
      paletteColor: '2196F3',
    ),
    SmartFolderRule(
      name: 'Иконки',
      format: 'svg',
    ),
  ];

  /// Список доступных умных папок.
  List<SmartFolder> getSmartFolders() {
    return [
      for (var i = 0; i < predefinedRules.length; i++)
        _toSmartFolder(predefinedRules[i], i),
    ];
  }

  /// Вычисление элементов, попадающих в умную папку.
  Future<List<CollectionItem>> getItemsFor(SmartFolder folder) {
    return _search.search(
      format: folder.format,
      paletteColor: folder.paletteColor,
      tagIds: folder.tagNames?.map(int.tryParse).whereType<int>().toList(),
    );
  }

  SmartFolder _toSmartFolder(SmartFolderRule rule, int index) {
    return SmartFolder(
      id: index,
      name: rule.name,
      tagNames: rule.tagNames,
      paletteColor: rule.paletteColor,
      format: rule.format,
    );
  }
}