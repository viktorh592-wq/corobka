import 'dart:async';

import '../theme/app_theme.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/collection/collection_state.dart';
import '../data/models/item.dart';

/// Правая панель — детали выбранного элемента коллекции.
///
/// Отображает превью, название, метаданные, теги (с добавлением/удалением),
/// заметки и действия (избранное, перемещение в папку, удаление).
class RightPanel extends StatelessWidget {
  const RightPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<PanelColors>()!;
    final state = context.watch<CollectionState>();
    final item = state.selectedItem;

    return Material(
      color: colors.panel,
      child: item == null
          ? const _EmptyDetails()
          : _ItemDetails(item: item),
    );
  }
}

/// Пустое состояние (элемент не выбран).
class _EmptyDetails extends StatelessWidget {
  const _EmptyDetails();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.info_outline,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            'Выберите элемент',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// Детали выбранного элемента.
class _ItemDetails extends StatelessWidget {
  const _ItemDetails({required this.item});

  final CollectionItem item;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CollectionState>();
    final isTrash = state.isTrashView;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Preview(imagePath: item.path),
        const SizedBox(height: 16),
        _TitleEditor(item: item),
        const Divider(),
        _MetadataBlock(item: item),
        const Divider(),
        if (!isTrash) ...[
          _MoveToFolderBlock(item: item),
          const Divider(),
          _TagsBlock(item: item),
          const Divider(),
          _NotesEditor(item: item),
          const SizedBox(height: 12),
          _ActionsBlock(item: item),
        ] else ...[
          const SizedBox(height: 8),
          Text(
            'Элемент находится в корзине',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 12),
          _TrashActionsBlock(item: item),
        ],
      ],
    );
  }
}

/// Превью изображения.
class _Preview extends StatelessWidget {
  const _Preview({required this.imagePath});

  final String imagePath;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Image.file(
          File(imagePath),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.broken_image_outlined, size: 40),
          ),
        ),
      ),
    );
  }
}

/// Редактирование названия.
///
/// Отдельный StatefulWidget с собственным контроллером: текст не сбрасывается
/// при перестроении дерева (раньше поле «самостирались» при каждом вводе).
class _TitleEditor extends StatefulWidget {
  const _TitleEditor({required this.item});

  final CollectionItem item;

  @override
  State<_TitleEditor> createState() => _TitleEditorState();
}

class _TitleEditorState extends State<_TitleEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  int _lastItemId = -1;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.item.title);
    _focusNode = FocusNode();
    _lastItemId = widget.item.id;
  }

  @override
  void didUpdateWidget(_TitleEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Обновляем текст только при смене выбранного элемента ИЛИ если поле
    // не в фокусе (внешнее обновление названия). Иначе курсор прыгает.
    final idChanged = widget.item.id != _lastItemId;
    if (idChanged) {
      _controller.text = widget.item.title;
      _lastItemId = widget.item.id;
    } else if (!_focusNode.hasFocus &&
        _controller.text != widget.item.title) {
      _controller.text = widget.item.title;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<CollectionState>();

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            decoration: const InputDecoration(
              labelText: 'Название',
              isDense: true,
            ),
            onSubmitted: (value) {
              final trimmed = value.trim();
              if (trimmed.isNotEmpty && trimmed != widget.item.title) {
                state.updateItemAnnotations(title: trimmed);
              } else {
                _controller.text = widget.item.title;
              }
            },
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: widget.item.isFavorite ? 'Убрать из избранного' : 'В избранное',
          icon: Icon(
            widget.item.isFavorite ? Icons.star : Icons.star_border,
            color: widget.item.isFavorite ? Colors.amber : null,
          ),
          onPressed: () => state.toggleFavorite(widget.item),
        ),
      ],
    );
  }
}

/// Блок метаданных.
class _MetadataBlock extends StatelessWidget {
  const _MetadataBlock({required this.item});

  final CollectionItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetaRow(label: 'Формат', value: item.format ?? '—'),
        _MetaRow(
          label: 'Размер',
          value: '${item.width ?? '?'} × ${item.height ?? '?'}',
        ),
        if (item.palette != null) _PaletteBlock(paletteJson: item.palette!),
      ],
    );
  }
}

/// Строка метаданных.
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

/// Отображение цветовой палитры.
class _PaletteBlock extends StatelessWidget {
  const _PaletteBlock({required this.paletteJson});

  final String paletteJson;

  @override
  Widget build(BuildContext context) {
    final colors = _parseColors(paletteJson);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          for (final color in colors)
            Container(
              width: 24,
              height: 24,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Color> _parseColors(String json) {
    final list = (json.replaceAll('[', '').replaceAll(']', '').replaceAll('"', ''))
        .split(',')
        .where((s) => s.trim().isNotEmpty)
        .map((s) => int.tryParse(s.trim(), radix: 16))
        .whereType<int>()
        .map((v) => Color(0xFF000000 | v))
        .toList();
    return list;
  }
}

/// Перемещение элемента в папку (выпадающий список, как в Eagle).
class _MoveToFolderBlock extends StatelessWidget {
  const _MoveToFolderBlock({required this.item});

  final CollectionItem item;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CollectionState>();

    return Row(
      children: [
        Text(
          'Папка:',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              isDense: true,
              isExpanded: true,
              value: item.folderId,
              hint: const Text('Без папки'),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Без папки (корень)'),
                ),
                for (final folder in state.folders)
                  DropdownMenuItem<int?>(
                    value: folder.id,
                    child: Text(
                      folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (folderId) {
                if (folderId == item.folderId) return;
                state.moveItemToFolder(folderId);
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Блок тегов.
class _TagsBlock extends StatelessWidget {
  const _TagsBlock({required this.item});

  final CollectionItem item;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CollectionState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Теги', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tag in state.selectedItemTags)
              Chip(
                label: Text(tag.name),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => state.removeTagFromSelectedItem(tag.id),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _AddTagField(item: item),
      ],
    );
  }
}

/// Поле добавления тега.
class _AddTagField extends StatefulWidget {
  const _AddTagField({required this.item});

  final CollectionItem item;

  @override
  State<_AddTagField> createState() => _AddTagFieldState();
}

class _AddTagFieldState extends State<_AddTagField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: const InputDecoration(
        labelText: 'Добавить тег',
        isDense: true,
        prefixIcon: Icon(Icons.add, size: 18),
      ),
      onSubmitted: (value) {
        final tag = value.trim();
        if (tag.isNotEmpty) {
          context.read<CollectionState>().addTagToSelectedItem(tag);
          _controller.clear();
        }
      },
    );
  }
}

/// Блок заметок.
///
/// Отдельный StatefulWidget: контроллер создаётся один раз, изменения
/// сохраняются с задержкой (debounce), текст не откатывается при вводе.
class _NotesEditor extends StatefulWidget {
  const _NotesEditor({required this.item});

  final CollectionItem item;

  @override
  State<_NotesEditor> createState() => _NotesEditorState();
}

class _NotesEditorState extends State<_NotesEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _debounce;
  int _lastItemId = -1;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.item.notes ?? '');
    _focusNode = FocusNode();
    _lastItemId = widget.item.id;
  }

  @override
  void didUpdateWidget(_NotesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Смена элемента — подгружаем его заметки. Пока поле в фокусе,
    // внешние обновления не затирают ввод.
    final idChanged = widget.item.id != _lastItemId;
    if (idChanged) {
      _debounce?.cancel();
      _controller.text = widget.item.notes ?? '';
      _lastItemId = widget.item.id;
    } else if (!_focusNode.hasFocus &&
        _controller.text != (widget.item.notes ?? '')) {
      _controller.text = widget.item.notes ?? '';
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      context.read<CollectionState>().updateItemAnnotations(notes: value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Заметки', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Добавьте заметку...',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: _onChanged,
        ),
      ],
    );
  }
}

/// Действия с элементом: удаление в корзину.
class _ActionsBlock extends StatelessWidget {
  const _ActionsBlock({required this.item});

  final CollectionItem item;

  @override
  Widget build(BuildContext context) {
    final state = context.read<CollectionState>();

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Удалить'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => state.trashItem(item),
          ),
        ),
      ],
    );
  }
}

/// Действия для элемента в корзине: восстановить / удалить навсегда.
class _TrashActionsBlock extends StatelessWidget {
  const _TrashActionsBlock({required this.item});

  final CollectionItem item;

  @override
  Widget build(BuildContext context) {
    final state = context.read<CollectionState>();

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.restore_outlined, size: 18),
            label: const Text('Восстановить'),
            onPressed: () => state.restoreItem(item),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.delete_forever_outlined, size: 18),
            label: const Text('Удалить навсегда'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => state.purgeItem(item),
          ),
        ),
      ],
    );
  }
}
