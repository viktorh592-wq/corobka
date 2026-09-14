import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../data/models/item.dart';
import '../features/collection/collection_state.dart';
import 'drop_zone.dart';
import 'lightbox_viewer.dart';

/// Центральная область контента.
///
/// Содержит панель инструментов (поиск, импорт, экспорт, фильтры, сортировка,
/// зум) и область просмотра элементов коллекции. Поддерживает drag-and-drop
/// импорт, выбор элемента, контекстное меню и полноэкранный просмотр
/// (lightbox). Режимы отображения: сетка, masonry (waterfall), список.
class ContentArea extends StatelessWidget {
  const ContentArea({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CollectionState>();

    // Показ накопленных ошибок (импорт, БД) через SnackBar.
    final error = state.lastError;
    if (error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error)));
        state.clearError();
      });
    }

    return DropZone(
      controller: state.importController,
      folderId: state.currentNumericFolderId,
      onImported: state.refreshItems,
      child: Column(
        children: [
          _Toolbar(state: state),
          const Divider(height: 1),
          if (state.isImporting)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _ItemGrid()),
        ],
      ),
    );
  }
}

/// Панель инструментов.
class _Toolbar extends StatefulWidget {
  const _Toolbar({required this.state});

  final CollectionState state;

  @override
  State<_Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends State<_Toolbar> {
  late final TextEditingController _searchController;
  Timer? _debounce;

  /// Палитра цветов для быстрой фильтрации.
  static const _palette = <(String, Color)>[
    ('FF5722', Color(0xFFFF5722)), // оранжевый
    ('FFEB3B', Color(0xFFFFEB3B)), // жёлтый
    ('4CAF50', Color(0xFF4CAF50)), // зелёный
    ('2196F3', Color(0xFF2196F3)), // синий
    ('9C27B0', Color(0xFF9C27B0)), // фиолетовый
    ('F44336', Color(0xFFF44336)), // красный
    ('000000', Color(0xFF000000)), // чёрный
    ('FFFFFF', Color(0xFFFFFFFF)), // белый
  ];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: widget.state.searchQuery,
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      widget.state.setSearchQuery(value);
    });
  }

  void _showColorFilter(BuildContext context) {
    final state = widget.state;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Фильтр по цвету'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (hex, color) in _palette)
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () {
                  state.setColorFilter(hex);
                  Navigator.pop(context);
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: state.filterColor == hex
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade400,
                      width: state.filterColor == hex ? 3 : 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              state.clearColorFilter();
              Navigator.pop(context);
            },
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
  }

  /// Выбор режима сортировки (как в Eagle — выпадающее меню).
  Future<void> _pickSortMode(BuildContext context) async {
    final state = widget.state;
    final selected = await showMenu<SortMode>(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.sizeOf(context).width - 260,
        90,
        16,
        0,
      ),
      items: [
        for (final mode in SortMode.values)
          CheckedPopupMenuItem(
            value: mode,
            checked: mode == state.sortMode,
            child: Text(mode.label),
          ),
      ],
    );
    if (selected != null) {
      await state.setSortMode(selected);
    }
  }

  Future<void> _export(BuildContext context) async {
    final state = widget.state;
    if (state.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет элементов для экспорта')),
      );
      return;
    }

    // Захватываем messenger до await — чтобы не использовать context
    // после асинхронного разрыва.
    final messenger = ScaffoldMessenger.of(context);

    final result = state.selectedItem != null
        ? await state.exportSelectedItem()
        : await state.exportCurrentItems();

    if (result == null) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Экспортировано: ${result.exported}, ошибок: ${result.failed}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final isTrash = state.isTrashView;

    return Material(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 200,
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Поиск...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: state.searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            state.clearSearch();
                          },
                        )
                      : null,
                ),
                onChanged: _onSearchChanged,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Фильтр по цвету',
              icon: const Icon(Icons.palette_outlined),
              onPressed: () => _showColorFilter(context),
            ),
            const SizedBox(width: 4),
            if (!isTrash) ...[
              TextButton.icon(
                onPressed: () => state.importFiles(),
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text('Импорт'),
              ),
              TextButton.icon(
                onPressed: () => state.importDirectory(),
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                label: const Text('Папка'),
              ),
            ],
            IconButton(
              tooltip: 'Экспорт',
              icon: const Icon(Icons.download_outlined),
              onPressed: () => _export(context),
            ),
            const Spacer(),
            if (isTrash && state.items.isNotEmpty) ...[
              TextButton.icon(
                onPressed: () => _confirmEmptyTrash(context, state),
                icon: const Icon(Icons.delete_forever_outlined, size: 18),
                label: const Text('Очистить корзину'),
              ),
              const SizedBox(width: 8),
            ],
            // Слайдер зума превью (как в Eagle).
            Icon(
              Icons.photo_size_select_small_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.outline,
            ),
            SizedBox(
              width: 90,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 10),
                ),
                child: Slider(
                  value: state.thumbnailExtent,
                  min: 120,
                  max: 320,
                  onChanged: (v) => state.setThumbnailExtent(v),
                ),
              ),
            ),
            Icon(
              Icons.photo_size_select_large_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: state.sortMode.label,
              icon: const Icon(Icons.sort_outlined),
              onPressed: () => _pickSortMode(context),
            ),
            IconButton(
              tooltip: 'Сетка',
              icon: const Icon(Icons.grid_view_outlined),
              isSelected: state.viewMode == ViewMode.grid,
              onPressed: () => state.setViewMode(ViewMode.grid),
            ),
            IconButton(
              tooltip: 'Masonry',
              icon: const Icon(Icons.dashboard_outlined),
              isSelected: state.viewMode == ViewMode.masonry,
              onPressed: () => state.setViewMode(ViewMode.masonry),
            ),
            IconButton(
              tooltip: 'Список',
              icon: const Icon(Icons.view_list_outlined),
              isSelected: state.viewMode == ViewMode.list,
              onPressed: () => state.setViewMode(ViewMode.list),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmEmptyTrash(
    BuildContext context,
    CollectionState state,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить корзину?'),
        content: Text(
          'Все ${state.items.length} элементов будут удалены безвозвратно '
          'вместе с файлами на диске.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await state.emptyTrash();
    }
  }
}

/// Область просмотра элементов коллекции.
class _ItemGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<CollectionState>();

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              state.isTrashView
                  ? Icons.delete_outline
                  : Icons.photo_library_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              state.isTrashView
                  ? 'Корзина пуста'
                  : 'Перетащите изображения сюда или нажмите «Импорт»',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    switch (state.viewMode) {
      case ViewMode.grid:
        return _GridView(
          items: state.items,
          extent: state.thumbnailExtent,
        );
      case ViewMode.masonry:
        return _MasonryView(
          items: state.items,
          extent: state.thumbnailExtent,
        );
      case ViewMode.list:
        return _ListView(items: state.items);
    }
  }
}

/// Сетка одинаковых ячеек.
class _GridView extends StatelessWidget {
  const _GridView({required this.items, required this.extent});

  final List<CollectionItem> items;
  final double extent;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: extent,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return _ItemCard(item: items[index]);
      },
    );
  }
}

/// Masonry (waterfall) режим — карточки сохраняют пропорции изображения,
/// как «водопад» в Eagle.
class _MasonryView extends StatelessWidget {
  const _MasonryView({required this.items, required this.extent});

  final List<CollectionItem> items;
  final double extent;

  @override
  Widget build(BuildContext context) {
    // Число колонок подстраивается под слайдер зума и ширину области.
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            (constraints.maxWidth / extent).round().clamp(2, 10);
        return MasonryGridView.count(
          padding: const EdgeInsets.all(12),
          crossAxisCount: columns,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          itemCount: items.length,
          itemBuilder: (context, index) {
            return _ItemCard(item: items[index], showFullImage: true);
          },
        );
      },
    );
  }
}

/// Список (строки с превью и метаданными).
class _ListView extends StatelessWidget {
  const _ListView({required this.items});

  final List<CollectionItem> items;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final item = items[index];
        return _ItemListRow(item: item);
      },
    );
  }
}

/// Карточка элемента коллекции.
class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, this.showFullImage = false});

  final CollectionItem item;
  final bool showFullImage;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CollectionState>();
    final selected = state.selectedItem?.id == item.id;

    return GestureDetector(
      onTap: () => state.selectItem(item),
      onDoubleTap: () => _openLightbox(context, state),
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, state, details.globalPosition),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      File(item.path),
                      fit: showFullImage ? BoxFit.contain : BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color:
                            Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                    if (item.isFavorite)
                      const Positioned(
                        top: 4,
                        right: 4,
                        child: Icon(
                          Icons.star,
                          size: 18,
                          color: Colors.amber,
                          shadows: [Shadow(blurRadius: 4)],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openLightbox(BuildContext context, CollectionState state) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LightboxViewer(
          items: state.items,
          initialIndex: state.items.indexWhere((e) => e.id == item.id),
        ),
      ),
    );
  }

  /// Контекстное меню карточки (правая кнопка мыши) — как в Eagle.
  Future<void> _showContextMenu(
    BuildContext context,
    CollectionState state,
    Offset position,
  ) async {
    await state.selectItem(item);
    if (!context.mounted) return;

    final isTrash = state.isTrashView;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, 16, 16),
      items: [
        const PopupMenuItem(
          value: 'open',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.open_in_new_outlined),
            title: Text('Открыть'),
          ),
        ),
        if (!isTrash)
          PopupMenuItem(
            value: 'favorite',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                item.isFavorite ? Icons.star_border : Icons.star,
              ),
              title: Text(item.isFavorite ? 'Убрать из избранного' : 'В избранное'),
            ),
          ),
        if (!isTrash)
          const PopupMenuItem(
            value: 'move',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.drive_file_move_outlined),
              title: Text('Переместить в папку...'),
            ),
          ),
        if (isTrash)
          const PopupMenuItem(
            value: 'restore',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.restore_outlined),
              title: Text('Восстановить'),
            ),
          ),
        PopupMenuItem(
          value: isTrash ? 'purge' : 'trash',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              isTrash ? Icons.delete_forever_outlined : Icons.delete_outline,
              color: isTrash ? null : Theme.of(context).colorScheme.error,
            ),
            title: Text(
              isTrash ? 'Удалить навсегда' : 'Удалить',
              style: isTrash
                  ? null
                  : TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      ],
    );

    if (action == null || !context.mounted) return;
    switch (action) {
      case 'open':
        _openLightbox(context, state);
      case 'favorite':
        await state.toggleFavorite(item);
      case 'move':
        await _moveToFolderDialog(context, state);
      case 'trash':
        await state.trashItem(item);
      case 'restore':
        await state.restoreItem(item);
      case 'purge':
        await state.purgeItem(item);
    }
  }

  /// Диалог перемещения элемента в папку.
  Future<void> _moveToFolderDialog(
    BuildContext context,
    CollectionState state,
  ) async {
    final folders = state.folders;
    final selected = await showDialog<int?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Переместить в папку'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, -1),
            child: const ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.folder_off_outlined),
              title: Text('Без папки (корень)'),
            ),
          ),
          for (final folder in folders)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, folder.id),
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_outlined),
                title: Text(folder.name),
              ),
            ),
        ],
      ),
    );

    if (selected == null) return;
    await state.moveItemToFolder(selected == -1 ? null : selected);
  }
}

/// Строка элемента для режима списка.
class _ItemListRow extends StatelessWidget {
  const _ItemListRow({required this.item});

  final CollectionItem item;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CollectionState>();
    final selected = state.selectedItem?.id == item.id;

    return GestureDetector(
      onTap: () => state.selectItem(item),
      onDoubleTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => LightboxViewer(
              items: state.items,
              initialIndex: state.items.indexWhere((e) => e.id == item.id),
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.secondaryContainer
              : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 56,
                height: 56,
                child: Image.file(
                  File(item.path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.broken_image_outlined, size: 20),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.width ?? '?'} × ${item.height ?? '?'} · '
                    '${(item.format ?? '').toUpperCase()} · '
                    '${_formatDate(item.createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            ),
            if (item.isFavorite)
              const Icon(Icons.star, size: 18, color: Colors.amber),
          ],
        ),
      ),
    );
  }

  String _formatDate(int seconds) {
    final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    return '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.'
        '${dt.year}';
  }
}
