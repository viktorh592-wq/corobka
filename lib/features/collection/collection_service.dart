/// Поиск элементов по запросу и фильтрам.
  ///
  /// Позволяет искать по названию/заметкам и фильтровать по папке,
  /// избранному, тегам, формату, дате и цвету палитры.
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
    return _itemDao.search(
      ItemFilter(
        query: query,
        folderId: folderId,
        favoritesOnly: favoritesOnly,
        tagIds: tagIds,
        format: format,
        createdBefore: createdBefore,
        createdAfter: createdAfter,
        paletteColor: paletteColor,
      ),
    );
  }