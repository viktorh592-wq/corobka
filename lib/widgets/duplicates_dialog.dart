import 'package:flutter/material.dart';

import '../data/models/item.dart';
import '../features/collection/collection_state.dart';

/// Диалог поиска и обработки дубликатов.
///
/// Показывает группы элементов с одинаковым содержимым (SHA-256 хэш файла).
/// Для каждого лишнего экземпляра доступно перемещение в корзину.
/// Первый (самый старый) элемент группы считается оригиналом.
class DuplicatesDialog extends StatefulWidget {
  const DuplicatesDialog({
    super.key,
    required this.state,
    this.duplicatesFuture,
  });

  final CollectionState state;

  /// Опциональный готовый future с результатом поиска (используется в
  /// тестах и при повторном открытии). Если не задан — поиск запускается
  /// при открытии диалога.
  final Future<List<List<CollectionItem>>>? duplicatesFuture;

  @override
  State<DuplicatesDialog> createState() => _DuplicatesDialogState();
}

class _DuplicatesDialogState extends State<DuplicatesDialog> {
  late Future<List<List<CollectionItem>>> _future;

  @override
  void initState() {
    super.initState();
    _future =
        widget.duplicatesFuture ?? widget.state.findDuplicates();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Поиск дубликатов'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: FutureBuilder<List<List<CollectionItem>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Сравниваем содержимое файлов...'),
                  ],
                ),
              );
            }

            final groups = snapshot.data ?? const [];
            if (groups.isEmpty) {
              return const Center(
                child: Text('Дубликатов не найдено — коллекция чистая!'),
              );
            }

            final totalExtras = groups.fold<int>(
              0,
              (sum, group) => sum + group.length - 1,
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Найдено групп: ${groups.length} '
                  '(лишних копий: $totalExtras)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      for (final group in groups) ...[
                        _GroupHeader(count: group.length),
                        for (var i = 0; i < group.length; i++)
                          _DuplicateRow(
                            item: group[i],
                            isOriginal: i == 0,
                            state: widget.state,
                            onTrashed: () => setState(() {
                              // Перестраиваем список после удаления.
                              _future = widget.state.findDuplicates();
                            }),
                          ),
                        const Divider(),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Row(
        children: [
          const Icon(Icons.content_copy_outlined, size: 16),
          const SizedBox(width: 6),
          Text(
            'Дубликаты ($count копии)',
            style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.bold) ??
                const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _DuplicateRow extends StatelessWidget {
  const _DuplicateRow({
    required this.item,
    required this.isOriginal,
    required this.state,
    required this.onTrashed,
  });

  final CollectionItem item;
  final bool isOriginal;
  final CollectionState state;
  final VoidCallback onTrashed;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.insert_drive_file_outlined),
      title: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        isOriginal
            ? 'Оригинал (самая ранняя копия)'
            : 'Папка: ${item.folderId ?? 'корень'} · добавлен '
                '${_formatDate(item.createdAt)}',
        style: TextStyle(
          color: isOriginal
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline,
        ),
      ),
      trailing: isOriginal
          ? null
          : TextButton.icon(
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('В корзину'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () async {
                await state.trashItem(item);
                onTrashed();
              },
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
