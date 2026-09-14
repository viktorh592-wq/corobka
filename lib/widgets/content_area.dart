import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../data/models/item.dart';
import '../features/collection/collection_state.dart';
import 'app_dialog.dart';
import 'duplicates_dialog.dart';
import 'drop_zone.dart';
import 'lightbox_viewer.dart';
import 'media_placeholder.dart';

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
          if (state.isImporting) const LinearProgressIndicator(minHeight: 2),
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
      builder: (dialogContext) => _ColorFilterDialog(
        state: state,
        palette: _palette,
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
      // Горизонтальный скролл: при узком окне (или широких боковых панелях)
      // тулбар не переполняется, а прокручивается. IntrinsicWidth даёт Row
      // фиксированную ширину (Spacer/Expanded остаются корректными), а при
      // нехватке места содержимое прокручивается.
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: IntrinsicWidth(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      // Поле поиска: закруглённое как кнопки (radius 20 —
                      // такой же, как у FilledButton/OutlinedButton в M3),
                      // длина увеличена на 40% (200 → 280).
                      SizedBox(
                        width: 280,
                        child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Поиск...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            // Явная обводка: в тёмной теме стандартная граница
                            // почти не видна — задаём контрастный цвет.
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 1.6,
                              ),
                            ),
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
                          icon: const Icon(Icons.add_photo_alternate_outlined,
                              size: 18),
                          label: const Text('Импорт'),
                        ),
                        TextButton.icon(
                          onPressed: () => state.importDirectory(),
                          icon: const Icon(Icons.create_new_folder_outlined,
                              size: 18),
                          label: const Text('Папка'),
                        ),
                      ],
                      IconButton(
                        tooltip: 'Экспорт',
                        icon: const Icon(Icons.download_outlined),
                        onPressed: () => _export(context),
                      ),
                      IconButton(
                        tooltip: 'Найти дубликаты',
                        icon: const Icon(Icons.content_copy_outlined),
                        onPressed: () => _showDuplicates(context),
                      ),
                      const Spacer(),
                      if (isTrash && state.items.isNotEmpty) ...[
                        TextButton.icon(
                          onPressed: () => _confirmEmptyTrash(context, state),
                          icon: const Icon(Icons.delete_forever_outlined,
                              size: 18),
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
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 10),
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
              ),
            ),
          );
        },
      ),
    );
  }

  /// Диалог поиска дубликатов (по одинаковому содержимому файлов).
  void _showDuplicates(BuildContext context) {
    final state = widget.state;
    showDialog<void>(
      context: context,
      builder: (context) => DuplicatesDialog(state: state),
    );
  }

  Future<void> _confirmEmptyTrash(
    BuildContext context,
    CollectionState state,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: 'Очистить корзину?',
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
        final columns = (constraints.maxWidth / extent).round().clamp(2, 10);
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
            // В masonry-режиме (showFullImage) высота ячейки не ограничена —
            // Expanded внутри Column там запрещён (ошибка макета «non-zero
            // flex with unbounded height», из-за которой карточки исчезали).
            // Используем AspectRatio с реальными пропорциями файла.
            if (showFullImage)
              AspectRatio(
                aspectRatio: _aspectRatio,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                  child: _mediaArea(context, state),
                ),
              )
            else
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                  child: _mediaArea(context, state),
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

  /// Пропорции файла для masonry-режима (fallback 1:1 без метаданных).
  double get _aspectRatio {
    final w = item.width;
    final h = item.height;
    if (w != null && h != null && w > 0 && h > 0) return w / h;
    return 1.0;
  }

  /// Область медиа карточки: изображение, превью-кадр видео или плейсхолдер.
  Widget _mediaArea(BuildContext context, CollectionState state) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Видео/аудио не декодируются как изображения — показываем
        // понятный плейсхолдер; для видео — извлечённый превью-кадр.
        if (item.isImage)
          Image.file(
            File(item.path),
            fit: showFullImage ? BoxFit.contain : BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image_outlined),
            ),
          )
        else if (item.isVideo && state.hasVideoThumbnail(item.path))
          _VideoThumbCard(item: item, state: state)
        else
          MediaPlaceholder(item: item),
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
    );
  }

  void _openLightbox(BuildContext context, CollectionState state) {
    // Видео и аудио открываются системным плеером (как в Eagle —
    // внешний просмотрщик), а не полноэкранным просмотром картинок.
    if (!item.isImage) {
      state.openItemExternally(item);
      return;
    }
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
              title: Text(
                  item.isFavorite ? 'Убрать из избранного' : 'В избранное'),
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
      builder: (context) => AppDialog(
        title: 'Переместить в папку',
        content: SizedBox(
          width: 280,
          height: 300,
          child: ListView(
            shrinkWrap: false,
            children: [
              ListTile(
                dense: true,
                leading: const Icon(Icons.folder_off_outlined),
                title: const Text('Без папки (корень)'),
                onTap: () => Navigator.pop(context, -1),
              ),
              for (final folder in folders)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(folder.name),
                  onTap: () => Navigator.pop(context, folder.id),
                ),
            ],
          ),
        ),
      ),
    );

    if (selected == null) return;
    await state.moveItemToFolder(selected == -1 ? null : selected);
  }
}

/// Превью-кадр видео на карточке файла: изображение + значок «play».
class _VideoThumbCard extends StatelessWidget {
  const _VideoThumbCard({required this.item, required this.state});

  final CollectionItem item;
  final CollectionState state;

  @override
  Widget build(BuildContext context) {
    final thumbPath = state.videoThumbnailPath(item.path);
    if (thumbPath == null) {
      return MediaPlaceholder(item: item);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          File(thumbPath),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => MediaPlaceholder(item: item),
        ),
        // Полупрозрачная кнопка «play» — сразу видно, что это ролик.
        Center(
          child: Icon(
            Icons.play_circle_outline,
            size: 40,
            color: Colors.white.withValues(alpha: 0.9),
            shadows: const [Shadow(blurRadius: 8, color: Colors.black54)],
          ),
        ),
      ],
    );
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
                child: item.isImage
                    ? Image.file(
                        File(item.path),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child:
                              const Icon(Icons.broken_image_outlined, size: 20),
                        ),
                      )
                    : (item.isVideo && state.hasVideoThumbnail(item.path))
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                File(state.videoThumbnailPath(item.path)!),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    MediaPlaceholder(item: item),
                              ),
                              Center(
                                child: Icon(
                                  Icons.play_circle_outline,
                                  size: 22,
                                  color:
                                      Colors.white.withValues(alpha: 0.9),
                                  shadows: const [
                                    Shadow(blurRadius: 6, color: Colors.black54),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : MediaPlaceholder(item: item),
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

/// Диалог фильтра по цвету с возможностью выбора произвольного цвета.
///
/// Содержит:
///   • сетку быстрых пресетов (клик = применить с похожими оттенками);
///   • поле ввода HEX-кода цвета (#RRGGBB или RRGGBB);
///   • HSV-палитру (три слайдера — тон, насыщенность, яркость);
///   • слайдер «похожести» (допустимого RGB-расстояния);
///   • кнопку «Применить» — запускает поиск по цвету и похожим оттенкам.
///
/// Поиск выполняется не по точному совпадению HEX в JSON-палитре элемента,
/// а по расстоянию в нормированном RGB-кубе: если хотя бы один цвет
/// палитры попадает в tolerance, элемент включается в результат.
class _ColorFilterDialog extends StatefulWidget {
  const _ColorFilterDialog({
    required this.state,
    required this.palette,
  });

  final CollectionState state;
  final List<(String, Color)> palette;

  @override
  State<_ColorFilterDialog> createState() => _ColorFilterDialogState();
}

class _ColorFilterDialogState extends State<_ColorFilterDialog> {
  late final TextEditingController _hexController;
  late HSVColor _hsv;
  late double _tolerance;

  @override
  void initState() {
    super.initState();
    final current = widget.state.filterColor;
    if (current != null) {
      final color = _parseHexColor(current) ?? const Color(0xFFFF5722);
      _hsv = HSVColor.fromColor(color);
      _hexController = TextEditingController(text: '#${_hexOf(color)}');
    } else {
      // Оранжевый по умолчанию.
      _hsv = const HSVColor.fromAHSV(1.0, 18, 0.85, 1.0);
      _hexController =
          TextEditingController(text: '#${_hexOf(_hsv.toColor())}');
    }
    _tolerance = widget.state.filterColorTolerance;
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  /// Преобразование Color → HEX без альфы (`RRGGBB`, uppercase).
  String _hexOf(Color c) {
    final argb = c.toARGB32();
    final rgb = argb & 0xFFFFFF;
    return rgb.toRadixString(16).padLeft(6, '0').toUpperCase();
  }

  /// Разбор строки вида `RRGGBB`, `#RRGGBB`, `#RGB` → Color.
  Color? _parseHexColor(String input) {
    var s = input.trim().toUpperCase();
    if (s.isEmpty) return null;
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 3) {
      s = s.split('').map((c) => '$c$c').join();
    }
    if (s.length != 6) return null;
    final v = int.tryParse(s, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }

  void _syncHsv(HSVColor newHsv) {
    setState(() {
      _hsv = newHsv;
      _hexController.text = '#${_hexOf(newHsv.toColor())}';
    });
  }

  void _onHexChanged(String value) {
    final color = _parseHexColor(value);
    if (color != null) {
      setState(() {
        _hsv = HSVColor.fromColor(color);
      });
    }
  }

  void _apply() {
    final hex = _hexOf(_hsv.toColor());
    widget.state.setColorFilter(hex, tolerance: _tolerance);
    Navigator.of(context).pop();
  }

  void _reset() {
    widget.state.clearColorFilter();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentColor = _hsv.toColor();
    final selectedHex = widget.state.filterColor;

    return AppDialog(
      title: 'Фильтр по цвету',
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Быстрые пресеты ──
              Text('Пресеты', style: theme.textTheme.labelSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (hex, color) in widget.palette)
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        setState(() {
                          _hsv = HSVColor.fromColor(color);
                          _hexController.text = '#$hex';
                        });
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: selectedHex == hex
                                ? theme.colorScheme.primary
                                : Colors.grey.shade400,
                            width: selectedHex == hex ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Кастомный цвет: HEX + превью ──
              Text('Кастомный цвет', style: theme.textTheme.labelSmall),
              const SizedBox(height: 6),
              Row(
                children: [
                  // Превью выбранного цвета.
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: currentColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _hexController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'HEX',
                        hintText: '#FF5722',
                        prefixText: '',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: _onHexChanged,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── HSV-палитра ──
              Text('Палитра', style: theme.textTheme.labelSmall),
              const SizedBox(height: 6),
              _HueSlider(
                value: _hsv.hue,
                onChanged: (h) => _syncHsv(_hsv.withHue(h)),
              ),
              const SizedBox(height: 8),
              _SaturationSlider(
                hsv: _hsv,
                onChanged: (s) => _syncHsv(_hsv.withSaturation(s)),
              ),
              const SizedBox(height: 8),
              _ValueSlider(
                hsv: _hsv,
                onChanged: (v) => _syncHsv(_hsv.withValue(v)),
              ),
              const SizedBox(height: 16),

              // ── Слайдер похожести ──
              Text('Похожесть: ${_tolerance.toStringAsFixed(2)}',
                  style: theme.textTheme.labelSmall),
              Slider(
                min: 0.0,
                max: 0.6,
                divisions: 60,
                value: _tolerance.clamp(0.0, 0.6),
                label: _tolerance.toStringAsFixed(2),
                onChanged: (v) => setState(() => _tolerance = v),
              ),
              Text(
                '0.00 = точное совпадение, 0.15 = похожий оттенок, '
                '0.60 = широкий диапазон',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _reset,
          child: const Text('Сбросить'),
        ),
        FilledButton(
          onPressed: _apply,
          child: const Text('Применить'),
        ),
      ],
    );
  }
}

/// Слайдер тона (hue) с радужным градиентом на треке.
/// Жесты и ползунок берёт Material Slider; цветной трек рисуем под ним.
class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  static const _rainbow = [
    Color(0xFFFF0000),
    Color(0xFFFFFF00),
    Color(0xFF00FF00),
    Color(0xFF00FFFF),
    Color(0xFF0000FF),
    Color(0xFFFF00FF),
    Color(0xFFFF0000),
  ];

  @override
  Widget build(BuildContext context) {
    return _GradientSlider(
      value: value / 360.0,
      fromColor: const Color(0xFFFF0000),
      toColor: const Color(0xFFFF0000),
      gradient: const LinearGradient(colors: _rainbow),
      onChanged: (v) => onChanged(v * 360.0),
    );
  }
}

/// Слайдер насыщенности (saturation) с горизонтальным градиентом
/// от серого к насыщенному цвету текущего тона.
class _SaturationSlider extends StatelessWidget {
  const _SaturationSlider({
    required this.hsv,
    required this.onChanged,
  });

  final HSVColor hsv;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final baseColor = hsv.withSaturation(1).withValue(1).toColor();
    final greyColor = hsv.withSaturation(0).withValue(1).toColor();
    return _GradientSlider(
      value: hsv.saturation,
      fromColor: greyColor,
      toColor: baseColor,
      onChanged: onChanged,
    );
  }
}

/// Слайдер яркости (value) с градиентом от чёрного к насыщенному цвету.
class _ValueSlider extends StatelessWidget {
  const _ValueSlider({
    required this.hsv,
    required this.onChanged,
  });

  final HSVColor hsv;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final baseColor = hsv.withSaturation(1).withValue(1).toColor();
    return _GradientSlider(
      value: hsv.value,
      fromColor: Colors.black,
      toColor: baseColor,
      onChanged: onChanged,
    );
  }
}

/// Универсальный слайдер с произвольным горизонтальным градиентом на треке.
/// Поверх Flutter-слайдера кладём ClipRRect с LinearGradient, чтобы
/// получить «цветной трек». Сам ползунок и логика перетаскивания —
/// от Material Slider.
class _GradientSlider extends StatelessWidget {
  const _GradientSlider({
    required this.value,
    required this.fromColor,
    required this.toColor,
    required this.onChanged,
    this.gradient,
  });

  final double value;
  final Color fromColor;
  final Color toColor;
  final ValueChanged<double> onChanged;

  /// Опционально: кастомный многоцветный градиент (например, радуга
  /// для hue). Если null — используется двуцветный fromColor → toColor.
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final trackGradient = gradient ??
        LinearGradient(colors: [fromColor, toColor]);

    return Stack(
      alignment: Alignment.center,
      children: [
        // Цветной трек.
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 14,
            decoration: BoxDecoration(gradient: trackGradient),
          ),
        ),
        // Поверх — прозрачный Material Slider, который даёт ползунок
        // и обрабатывает жесты перетаскивания.
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 14,
            activeTrackColor: Colors.transparent,
            inactiveTrackColor: Colors.transparent,
            thumbColor: Colors.white,
            overlayColor: const Color(0x14000000),
          ),
          child: Slider(
            min: 0.0,
            max: 1.0,
            value: value.clamp(0.0, 1.0),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
