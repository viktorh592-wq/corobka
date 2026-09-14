import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models/folder.dart';
import '../features/collection/collection_state.dart';

/// Левая панель навигации по коллекции.
///
/// Отображает системные разделы (Все, Избранное, Теги, Корзина) и
/// пользовательские папки со счётчиками. Папки образуют иерархию —
/// внутри любой папки можно создавать подпапки (рекурсивно). Поддерживает
/// создание, переименование, удаление папок и фильтрацию по тегам.
class LeftPanel extends StatelessWidget {
  const LeftPanel({super.key});

  @override
  Widget build(BuildContext context) {
    // Fallback на случай темы без расширения PanelColors.
    final colors = Theme.of(context).extension<PanelColors>() ??
        PanelColors.fallback(Theme.of(context).brightness);
    final state = context.watch<CollectionState>();

    // Корневые папки (parent_id IS NULL) раскрываются рекурсивно через
    // _FolderTile, который сам рендерит свои подпапки.
    final rootFolders = state.subfoldersOf(null);

    return Material(
      color: colors.panel,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const _SectionHeader('Коллекция'),
          _SystemTile(
            id: 'all',
            icon: Icons.photo_library_outlined,
            label: 'Все',
            count: state.folderCounts.values.fold<int>(0, (a, b) => a + b),
          ),
          const _SystemTile(
            id: 'favorites',
            icon: Icons.star_outline,
            label: 'Избранное',
          ),
          const _TagsSection(),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Папки',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  tooltip: 'Создать папку',
                  icon: const Icon(Icons.add, size: 20),
                  onPressed: () => _createFolderDialog(context, state),
                ),
              ],
            ),
          ),
          for (final folder in rootFolders)
            _FolderTile(folder: folder, level: 0),
          const Divider(),
          const _SystemTile(
            id: 'trash',
            icon: Icons.delete_outline,
            label: 'Корзина',
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '${state.items.length} элементов',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createFolderDialog(
      BuildContext context, CollectionState state) async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новая папка'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Название папки',
            hintText: 'Например: Интерфейсы',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('Создать'),
          ),
        ],
      ),
    );

    if (name != null && name.trim().isNotEmpty) {
      await state.createFolder(name.trim());
    }
  }
}

/// Раздел «Теги»: раскрывающийся список тегов с фильтрацией по клику.
class _TagsSection extends StatefulWidget {
  const _TagsSection();

  @override
  State<_TagsSection> createState() => _TagsSectionState();
}

class _TagsSectionState extends State<_TagsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CollectionState>();
    final tags = state.tags;
    final counts = state.tagCounts;

    return Column(
      children: [
        ListTile(
          dense: true,
          leading: const Icon(Icons.tag, size: 20),
          title: const Text('Теги'),
          selected: state.filterTagId != null && !_expanded,
          selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tags.isNotEmpty)
                Text(
                  '${tags.length}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 20,
              ),
            ],
          ),
          onTap: () {
            setState(() => _expanded = !_expanded);
            if (_expanded) {
              // ЗАЩИТНЫЙ РЕФРЕШ: перечитываем теги прямо из БД при каждом
              // раскрытии раздела. Даже если уведомление где-то было
              // потеряно — пользователь всегда видит актуальный список.
              context.read<CollectionState>().refreshTags();
            }
          },
        ),
        if (_expanded)
          if (tags.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 48, top: 4, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Нет тегов',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ),
            )
          else
            for (final tag in tags)
              Padding(
                padding: const EdgeInsets.only(left: 24),
                child: ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(Icons.label_outline, size: 16),
                  title: Text(tag.name),
                  trailing: Text(
                    '${counts[tag.id] ?? 0}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                  selected: state.filterTagId == tag.id,
                  selectedTileColor:
                      Theme.of(context).colorScheme.secondaryContainer,
                  onTap: () => state.setTagFilter(
                    state.filterTagId == tag.id ? null : tag.id,
                  ),
                ),
              ),
      ],
    );
  }
}

/// Заголовок секции.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

/// Системный раздел (Все, Избранное, Корзина).
class _SystemTile extends StatelessWidget {
  const _SystemTile({
    required this.id,
    required this.icon,
    required this.label,
    this.count,
  });

  final String id;
  final IconData icon;
  final String label;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CollectionState>();
    final selected = state.selectedFolderId == id;

    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20),
      title: Text(label),
      trailing: count != null && count! > 0
          ? Text(
              '$count',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            )
          : null,
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
      onTap: () => state.selectFolder(id),
    );
  }
}

/// Пользовательская папка с контекстным меню, счётчиком и поддержкой
/// иерархии подпапок. [level] — уровень вложенности (0 = корневая),
/// используется для визуального отступа слева.
class _FolderTile extends StatefulWidget {
  const _FolderTile({required this.folder, required this.level});

  final Folder folder;
  final int level;

  @override
  State<_FolderTile> createState() => _FolderTileState();
}

class _FolderTileState extends State<_FolderTile> {
  /// Раскрыта ли папка (видны ли её подпапки). По умолчанию collapsed.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CollectionState>();
    final selected = state.selectedFolderId == widget.folder.id.toString();
    final count = state.folderCounts[widget.folder.id];
    final children = state.subfoldersOf(widget.folder.id);
    final hasChildren = children.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Сама плитка папки.
        GestureDetector(
          onSecondaryTapUp: (details) => _showMenu(context, state),
          child: Padding(
            padding: EdgeInsets.only(left: widget.level * 12.0),
            child: ListTile(
              dense: true,
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Шеврон раскрытия: виден только если есть дочерние папки.
                  if (hasChildren)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          _expanded
                              ? Icons.expand_more
                              : Icons.chevron_right,
                          size: 18,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 22),
                  const Icon(Icons.folder_outlined, size: 20),
                ],
              ),
              title: Text(widget.folder.name),
              trailing: count != null && count > 0
                  ? Text(
                      '$count',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    )
                  : null,
              selected: selected,
              selectedTileColor:
                  Theme.of(context).colorScheme.secondaryContainer,
              onTap: () => state.selectFolder(widget.folder.id.toString()),
              onLongPress: () => _showMenu(context, state),
            ),
          ),
        ),
        // Дочерние подпапки (рекурсивно).
        if (_expanded && hasChildren)
          for (final child in children)
            _FolderTile(folder: child, level: widget.level + 1),
      ],
    );
  }

  /// Контекстное меню: создание подпапки, переименование, удаление.
  Future<void> _showMenu(BuildContext context, CollectionState state) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('Добавить подпапку'),
              onTap: () => Navigator.pop(context, 'add_subfolder'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Переименовать'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Удалить'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (action == 'add_subfolder') {
      if (!context.mounted) return;
      // Автоматически раскрываем родителя — чтобы новая подпапка была видна.
      setState(() => _expanded = true);
      await _createSubfolderDialog(context, state);
    } else if (action == 'rename') {
      if (!context.mounted) return;
      await _renameDialog(context, state);
    } else if (action == 'delete') {
      if (!context.mounted) return;
      await _deleteDialog(context, state);
    }
  }

  /// Диалог создания подпапки внутри текущей папки.
  Future<void> _createSubfolderDialog(
    BuildContext context,
    CollectionState state,
  ) async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Подпапка в «${widget.folder.name}»'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Название подпапки',
            hintText: 'Например: Иконки',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('Создать'),
          ),
        ],
      ),
    );

    if (name != null && name.trim().isNotEmpty) {
      await state.createSubfolder(name.trim(), widget.folder.id);
    }
  }

  Future<void> _renameDialog(
      BuildContext context, CollectionState state) async {
    final nameController = TextEditingController(text: widget.folder.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Переименовать папку'),
        content: TextField(
          controller: nameController,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (name != null && name.trim().isNotEmpty) {
      await state.renameFolder(widget.folder.id, name.trim());
    }
  }

  Future<void> _deleteDialog(
      BuildContext context, CollectionState state) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить папку?'),
        content: Text(
          'Папка «${widget.folder.name}» будет удалена. Элементы не удаляются — '
          'они останутся в коллекции без папки. Подпапки поднимутся '
          'на уровень выше.',
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
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await state.deleteFolder(widget.folder.id);
    }
  }
}
