import '../../data/daos/item_dao.dart';
import '../../data/models/item.dart';

/// Сервис поиска и фильтрации элементов коллекции.
///
/// Обеспечивает полнотекстовый поиск по названию/заметкам и фильтры
/// по тегам, формату, дате и цвету палитры.
class SearchService {
  const SearchService({ItemDao? itemDao}) : _itemDao = itemDao ?? const ItemDao();

  final ItemDao _itemDao;

  /// Поиск элементов по запросу и фильтрам.
  Future<List<CollectionItem>> search({
    String? query,
    int? folderId,
    bool favoritesOnly = false,
    List<int>? tagIds,
    String? format,
    DateTime? before,
    DateTime? after,
    String? paletteColor,
  }) {
    return _itemDao.search(
      ItemFilter(
        query: query,
        folderId: folderId,
        favoritesOnly: favoritesOnly,
        tagIds: tagIds,
        format: format,
        createdBefore: before?.millisecondsSinceEpoch ~/ 1000,
        createdAfter: after?.millisecondsSinceEpoch ~/ 1000,
        paletteColor: paletteColor,
      ),
    );
  }
}