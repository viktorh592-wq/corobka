import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../data/models/item.dart';
import '../features/collection/collection_state.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';
import 'color_sliders.dart';
import 'duplicates_dialog.dart';
import 'drop_zone.dart';
import 'folder_icon.dart';
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

  /// Ключ кнопки сортировки — меню открывается прямо под ней.
  final GlobalKey _sortButtonKey = GlobalKey();

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
  ///
  /// Меню открывается строго под кнопкой сортировки (позиция берётся
  /// из рендер-объекта кнопки, а не «на глаз» по координатам экрана).
  Future<void> _pickSortMode(BuildContext context) async {
    final state = widget.state;
    final buttonBox = _sortButtonKey.currentContext?.findRenderObject();
    final overlayBox =
        Overlay.of(context).context.findRenderObject();

    RelativeRect position = RelativeRect.fill;
    if (buttonBox is RenderBox && overlayBox is RenderBox) {
      final topLeft =
          buttonBox.localToGlobal(Offset.zero, ancestor: overlayBox);
      position = RelativeRect.fromRect(
        Rect.fromLTWH(
          topLeft.dx,
          topLeft.dy + buttonBox.size.height + 4,
          buttonBox.size.width + 120,
          8,
        ),
        Offset.zero & overlayBox.size,
      );
    }

    final selected = await showMenu<SortMode>(
      context: context,
      position: position,
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

    // FrostedPanel в iOS-темах даёт эффект стекла (blur + полупрозрачный
    // фон). В Material — обычный Material widget без изменений.
    return FrostedPanel(
      child: Material(
        type: MaterialType.transparency,
        elevation: 0,
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
                        key: _sortButtonKey,
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
      ), // LayoutBuilder (child of Material)
      ), // Material (child of FrostedPanel)
    ); // FrostedPanel — return statement
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

    Widget view;
    switch (state.viewMode) {
      case ViewMode.grid:
        view = _GridView(
          items: state.items,
          extent: state.thumbnailExtent,
        );
      case ViewMode.masonry:
        view = _MasonryView(
          items: state.items,
          extent: state.thumbnailExtent,
        );
      case ViewMode.list:
        view = _ListView(items: state.items);
    }

    // Панель массового выделения поверх списка (Ctrl/Shift/Ctrl+A).
    return Column(
      children: [
        if (state.hasMultiSelection) _SelectionBar(state: state),
        Expanded(child: view),
      ],
    );
  }
}

/// Панель действий над выделенными элементами.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.state});

  final CollectionState state;

  @override
  Widget build(BuildContext context) {
    final count = state.multiSelectedIds.length;
    final isTrash = state.isTrashView;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.checklist,
            size: 18,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Text(
            'Выбрано: $count',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
          ),
          const Spacer(),
          if (!isTrash) ...[
            TextButton.icon(
              onPressed: () => _moveSelected(context),
              icon: const Icon(Icons.drive_file_move_outlined, size: 18),
              label: const Text('Переместить в папку'),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: () => state.trashSelectedItems(),
              icon: Icon(
                Icons.delete_outline,
                size: 18,
                color: Theme.of(context).colorScheme.error,
              ),
              label: Text(
                'В корзину',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            const SizedBox(width: 4),
          ],
          TextButton(
            onPressed: state.clearMultiSelection,
            child: const Text('Снять выделение'),
          ),
        ],
      ),
    );
  }

  /// Диалог выбора папки для перемещения выделенных элементов.
  Future<void> _moveSelected(BuildContext context) async {
    final folderId = await showMoveToFolderPicker(context, state);
    if (folderId == null || !context.mounted) return;
    await state.moveItemsToFolder(
      state.multiSelectedIds.toList(),
      folderId == -1 ? null : folderId,
    );
  }
}

/// Общий диалог «Переместить в папку» с поиском по папкам.
///
/// Возвращает идентификатор папки, -1 (корень) или null (отмена).
Future<int?> showMoveToFolderPicker(
  BuildContext context,
  CollectionState state,
) {
  return showDialog<int?>(
    context: context,
    builder: (dialogContext) {
      final queryController = TextEditingController();
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final query = queryController.text.trim().toLowerCase();
          final folders = query.isEmpty
              ? state.folders
              : state.folders
                  .where((f) => f.name.toLowerCase().contains(query))
                  .toList();

          return AppDialog(
            title: 'Переместить в папку',
            content: SizedBox(
              width: 300,
              height: 360,
              child: Column(
                children: [
                  // ── Поиск по папкам ──
                  TextField(
                    controller: queryController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Поиск папки...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                setDialogState(() => queryController.clear());
                              },
                            ),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: folders.isEmpty
                        ? Center(
                            child: Text(
                              'Папки не найдены',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.outline,
                                  ),
                            ),
                          )
                        : ListView(
                            shrinkWrap: false,
                            children: [
                              if (query.isEmpty)
                                ListTile(
                                  dense: true,
                                  leading:
                                      const Icon(Icons.folder_off_outlined),
                                  title: const Text('Без папки (корень)'),
                                  onTap: () =>
                                      Navigator.pop(dialogContext, -1),
                                ),
                              for (final folder in folders)
                                Builder(builder: (context) {
                                  final count =
                                      state.folderCounts[folder.id] ?? 0;
                                  return ListTile(
                                    dense: true,
                                    leading: FolderIcon(
                                      colorHex: folder.color,
                                      size: 20,
                                    ),
                                    title: Text(folder.name),
                                    trailing: count > 0
                                        ? Text(
                                            '$count',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .outline,
                                                ),
                                          )
                                        : null,
                                    onTap: () => Navigator.pop(
                                        dialogContext, folder.id),
                                  );
                                }),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Перетаскиваемая карточка элемента: тянет одиночный элемент
/// или всё массовое выделение (если элемент входит в него).
class _ItemDraggable extends StatelessWidget {
  const _ItemDraggable({required this.item, required this.child});

  final CollectionItem item;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CollectionState>();

    // Из корзины перетаскивать нечего.
    if (state.isTrashView) return child;

    final ids = state.isMultiSelected(item)
        ? state.multiSelectedIds.toList()
        : <int>[item.id];

    return Draggable<List<int>>(
      data: ids,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragFeedback(
        count: ids.length,
        thumbnailPath: item.isImage ? item.path : null,
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: child),
      child: child,
    );
  }
}

/// «Отзыв» при перетаскивании: превью + счётчик выбранных файлов.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.count, this.thumbnailPath});

  final int count;
  final String? thumbnailPath;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary,
            width: 2,
          ),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox.expand(
                child: thumbnailPath != null
                    ? Image.file(
                        File(thumbnailPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.image_outlined),
                      )
                    : const Icon(Icons.image_outlined),
              ),
            ),
            if (count > 1)
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
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
    final multiSelected = state.isMultiSelected(item);
    final highlighted = selected || multiSelected;

    final card = GestureDetector(
      onTap: () => state.handleCardTap(item),
      onDoubleTap: () => _openLightbox(context, state),
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, state, details.globalPosition),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: highlighted
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            width: highlighted ? 2 : 1,
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

    // Карточку можно перетащить в папку (одиночную или всё выделение).
    return _ItemDraggable(item: item, child: card);
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
  ///
  /// Меню открывается строго под курсором: границы RelativeRect
  /// рассчитываются от курсора до краёв экрана, а не «16 px от края»
  /// (из-за фиксированных границ меню раньше улетало в сторону).
  /// Если элемент входит в массовое выделение — пункты действуют
  /// на всё выделение.
  Future<void> _showContextMenu(
    BuildContext context,
    CollectionState state,
    Offset position,
  ) async {
    final multiSelected = state.isMultiSelected(item);
    final selectionCount = state.multiSelectedIds.length;
    final actOnSelection = multiSelected && selectionCount > 1;

    // Считаем позицию меню ДО await — context не «протухает».
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final screenSize = overlayBox?.size ?? MediaQuery.sizeOf(context);

    if (!actOnSelection) {
      await state.selectItem(item);
    }
    if (!context.mounted) return;

    final isTrash = state.isTrashView;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        (screenSize.width - position.dx).clamp(0, screenSize.width),
        (screenSize.height - position.dy).clamp(0, screenSize.height),
      ),
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
          PopupMenuItem(
            value: 'move',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.drive_file_move_outlined),
              title: Text(actOnSelection
                  ? 'Переместить выбранные ($selectionCount) в папку...'
                  : 'Переместить в папку...'),
            ),
          ),
        if (!isTrash && actOnSelection)
          PopupMenuItem(
            value: 'trashSelection',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Удалить выбранные ($selectionCount)',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
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
        if (actOnSelection) {
          final folderId = await showMoveToFolderPicker(context, state);
          if (folderId == null || !context.mounted) return;
          await state.moveItemsToFolder(
            state.multiSelectedIds.toList(),
            folderId == -1 ? null : folderId,
          );
        } else {
          await _moveToFolderDialog(context, state);
        }
      case 'trashSelection':
        await state.trashSelectedItems();
      case 'trash':
        await state.trashItem(item);
      case 'restore':
        await state.restoreItem(item);
      case 'purge':
        await state.purgeItem(item);
    }
  }

  /// Диалог перемещения элемента в папку.
  ///
  /// Содержит поле поиска по папкам (фильтрация списка по названию,
  /// как на референс-скриншоте) и цветные иконки папок — цвет берётся
  /// из «настройки цвета папки».
  Future<void> _moveToFolderDialog(
    BuildContext context,
    CollectionState state,
  ) async {
    final selected = await showMoveToFolderPicker(context, state);

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
    final multiSelected = state.isMultiSelected(item);
    final highlighted = selected || multiSelected;

    final row = GestureDetector(
      onTap: () => state.handleCardTap(item),
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
          color: highlighted
              ? Theme.of(context).colorScheme.secondaryContainer
              : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: highlighted
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

    // Строку списка тоже можно перетащить в папку.
    return _ItemDraggable(item: item, child: row);
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
              HueSlider(
                value: _hsv.hue,
                onChanged: (h) => _syncHsv(_hsv.withHue(h)),
              ),
              const SizedBox(height: 8),
              SaturationSlider(
                hsv: _hsv,
                onChanged: (s) => _syncHsv(_hsv.withSaturation(s)),
              ),
              const SizedBox(height: 8),
              ValueSlider(
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
