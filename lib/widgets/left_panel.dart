import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models/folder.dart';
import '../data/models/smart_folder.dart';
import '../features/collection/collection_state.dart';

/// Левая панель навигации по коллекции.
///
/// Отображает системные разделы (Все, Избранное, Теги), пользовательские
/// папки и умные папки. Поддерживает создание, переименование и удаление
/// пользовательских папок.
class LeftPanel extends StatelessWidget {
  const LeftPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<PanelColors>()!;
    final state = context.watch<CollectionState>();

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
          ),
          _SystemTile(
            id: 'favorites',
            icon: Icons.star_outline,
            label: 'Избранное',
          ),
          _SystemTile(
            id: 'tags',
            icon: Icons.tag,
            label: 'Теги',
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Папки', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  tooltip: 'Создать папку',
                  icon: const Icon(Icons.add, size: 20),
                  onPressed: () => _createFolderDialog(context, state),
                ),
              ],
            ),
          ),
          for (final folder in state.folders)
            _FolderTile(folder: folder),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Умные папки',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                    letterSpacing: 1.2,
                  ),
            ),
          ),
          for (final smart in state.getSmartFolders())
            _SmartFolderTile(smartFolder: smart),
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

  Future<void> _createFolderDialog(BuildContext context, CollectionState state) async {
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

/// Системный раздел (Все, Избранное, Теги).
class _SystemTile extends StatelessWidget {
  const _SystemTile({
    required this.id,
    required this.icon,
    required this.label,
  });

  final String id;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CollectionState>();
    final selected = state.selectedFolderId == id;

    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20),
      title: Text(label),
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
      onTap: () => state.selectFolder(id),
    );
  }
}

/// Пользовательская папка с контекстным меню.
class _FolderTile extends StatelessWidget {
  const _FolderTile({required this.folder});

  final Folder folder;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CollectionState>();
    final selected = state.selectedFolderId == folder.id.toString();

    return ListTile(
      dense: true,
      leading: const Icon(Icons.folder_outlined, size: 20),
      title: Text(folder.name),
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
      onTap: () => state.selectFolder(folder.id.toString()),
      onLongPress: () => _showMenu(context, state),
    );
  }

  Future<void> _showMenu(BuildContext context, CollectionState state) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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

    if (action == 'rename') {
      await _renameDialog(context, state);
    } else if (action == 'delete') {
      await _deleteDialog(context, state);
    }
  }

  Future<void> _renameDialog(BuildContext context, CollectionState state) async {
    final nameController = TextEditingController(text: folder.name);
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
      await state.renameFolder(folder.id, name.trim());
    }
  }

  Future<void> _deleteDialog(BuildContext context, CollectionState state) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить папку?'),
        content: Text('Папка «${folder.name}» будет удалена.'),
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
      await state.deleteFolder(folder.id);
    }
  }
}

/// Плитка умной папки.
class _SmartFolderTile extends StatelessWidget {
  const _SmartFolderTile({required this.smartFolder});

  final SmartFolder smartFolder;

  @override
  Widget build(BuildContext context) {
    final state = context.read<CollectionState>();

    return ListTile(
      dense: true,
      leading: const Icon(Icons.auto_awesome_outlined, size: 20),
      title: Text(smartFolder.name),
      subtitle: Text(
        _ruleDescription(smartFolder),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      onTap: () => _showItems(context, state),
    );
  }

  /// Краткое описание правила умной папки.
  String _ruleDescription(SmartFolder folder) {
    final parts = <String>[
      if (folder.format != null) 'формат: ${folder.format}',
      if (folder.paletteColor != null) 'цвет: #${folder.paletteColor}',
      if (folder.tagNames != null) 'теги: ${folder.tagNames!.join(', ')}',
    ];
    return parts.isEmpty ? 'автоматическая' : parts.join(', ');
  }

  /// Показ элементов умной папки в диалоге.
  Future<void> _showItems(BuildContext context, CollectionState state) async {
    final items = await state.getSmartFolderItems(smartFolder);

    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${smartFolder.name} (${items.length})'),
        content: SizedBox(
          width: 300,
          child: items.isEmpty
              ? const Text('Нет подходящих элементов')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final item in items)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.image_outlined),
                        title: Text(item.title ?? ''),
                        subtitle: Text(
                          '${item.width ?? '?'} × ${item.height ?? '?'}'
                          ' · ${item.format ?? ''}',
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }
}