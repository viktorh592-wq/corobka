import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/collection/collection_state.dart';
import '../data/models/item.dart';

/// Правая панель — детали выбранного элемента коллекции.
///
/// Отображает превью, название, метаданные, теги (с добавлением/удалением)
/// и заметки. Поддерживает редактирование аннотаций и избранное.
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Preview(imagePath: item.path),
        const SizedBox(height: 16),
        _TitleEditor(item: item),
        const Divider(),
        _MetadataBlock(item: item),
        const Divider(),
        _TagsBlock(item: item),
        const Divider(),
        _NotesEditor(item: item),
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
class _TitleEditor extends StatelessWidget {
  const _TitleEditor({required this.item});

  final CollectionItem item;

  @override
  Widget build(BuildContext context) {
    final state = context.read<CollectionState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: TextEditingController(text: item.title ?? ''),
                decoration: const InputDecoration(
                  labelText: 'Название',
                  isDense: true,
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty && value != item.title) {
                    state.updateItemAnnotations(title: value.trim());
                  }
                },
              ),
            ),
            IconButton(
              tooltip: item.isFavorite ? 'Убрать из избранного' : 'В избранное',
              icon: Icon(
                item.isFavorite ? Icons.star : Icons.star_border,
                color: item.isFavorite ? Colors.amber : null,
              ),
              onPressed: () => state.toggleFavorite(item),
            ),
          ],
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
class _AddTagField extends StatelessWidget {
  const _AddTagField({required this.item});

  final CollectionItem item;

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController();

    return TextField(
      controller: controller,
      decoration: const InputDecoration(
        labelText: 'Добавить тег',
        isDense: true,
        prefixIcon: Icon(Icons.add, size: 18),
      ),
      onSubmitted: (value) {
        final tag = value.trim();
        if (tag.isNotEmpty) {
          context.read<CollectionState>().addTagToSelectedItem(tag);
          controller.clear();
        }
      },
    );
  }
}

/// Блок заметок.
class _NotesEditor extends StatelessWidget {
  const _NotesEditor({required this.item});

  final CollectionItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Заметки', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
          controller: TextEditingController(text: item.notes ?? ''),
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Добавьте заметку...',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (value) {
            // Сохраняем заметки при изменении (с небольшой задержкой).
            context.read<CollectionState>().updateItemAnnotations(notes: value);
          },
        ),
      ],
    );
  }
}