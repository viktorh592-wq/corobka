import '../theme/app_theme.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models/folder.dart';
import '../features/collection/collection_state.dart';
import 'app_dialog.dart';

/// Левая панель навигации по коллекции.
///
/// Отображает системные разделы (Все, Избранное, Теги, Корзина) и
/// пользовательские папки со счётчиками. Папки образуют иерархию —
/// внутри любой папки можно создавать подпапки (рекурсивно). Поддерживает
/// создание, переименование, удаление папок и фильтрацию по тегам.
///
/// Все заголовки секций выполнены в едином стиле: иконка в акцентном
/// («управляющем») цвете + крупный полужирный текст. Диалог создания
/// папки открывается рядом с кнопкой «+».
class LeftPanel extends StatefulWidget {
  const LeftPanel({super.key});

  @override
  State<LeftPanel> createState() => _LeftPanelState();
}

class _LeftPanelState extends State<LeftPanel> {
  /// Ключ кнопки «+» — по нему вычисляется позиция диалога создания папки
  /// (окно открывается рядом с кнопкой, а не в центре экрана).
  final GlobalKey _addFolderButtonKey = GlobalKey();

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
          const _SectionHeader(
            'Коллекция',
            icon: Icons.collections_bookmark_outlined,
          ),
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
          _SectionHeader(
            'Папки',
            icon: Icons.folder_outlined,
            trailing: IconButton(
              key: _addFolderButtonKey,
              tooltip: 'Создать папку',
              icon: const Icon(Icons.add, size: 20),
              onPressed: () => _createFolderDialog(context, state),
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

  /// Диалог создания папки. Открывается рядом с кнопкой «+» (по её
  /// глобальной позиции), а не в центре экрана.
  Future<void> _createFolderDialog(
      BuildContext context, CollectionState state) async {
    final name = await _showFolderNameDialog(
      context: context,
      title: 'Новая папка',
      label: 'Название папки',
      hint: 'Например: Интерфейсы',
      confirmLabel: 'Создать',
      anchorKey: _addFolderButtonKey,
    );

    if (name != null && name.trim().isNotEmpty) {
      await state.createFolder(name.trim());
    }
  }
}

/// Диалог ввода имени папки/подпапки.
///
/// Если передан [anchorKey] — окно позиционируется рядом с элементом
/// (кнопкой «+»), иначе — по центру экрана. В правом верхнем углу —
/// «крестик» закрытия.
Future<String?> _showFolderNameDialog({
  required BuildContext context,
  required String title,
  required String label,
  required String hint,
  required String confirmLabel,
  GlobalKey? anchorKey,
  String? initialText,
}) async {
  final controller = TextEditingController(text: initialText);
  try {
    return await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        // Вычисляем отступ диалога от краёв экрана так, чтобы окно
        // появилось сразу под кнопкой «+» (по её глобальной позиции).
        EdgeInsets insetPadding = const EdgeInsets.all(24);
        if (anchorKey != null) {
          final anchorContext = anchorKey.currentContext;
          final overlay =
              Overlay.of(dialogContext).context.findRenderObject();
          if (anchorContext != null &&
              overlay is RenderBox &&
              anchorContext.findRenderObject() is RenderBox) {
            final box = anchorContext.findRenderObject() as RenderBox;
            if (box.attached && overlay.attached) {
              final topLeft =
                  box.localToGlobal(Offset.zero, ancestor: overlay);
              final bottomLeft = topLeft + Offset(0, box.size.height);
              insetPadding = EdgeInsets.only(
                left: math.max(8.0, topLeft.dx - 4),
                top: bottomLeft.dy + 8,
                right: 8,
                bottom: 8,
              );
            }
          }
        }

        return Dialog(
          alignment: Alignment.topLeft,
          insetPadding: insetPadding,
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: _FolderNameCard(
            title: title,
            label: label,
            hint: hint,
            confirmLabel: confirmLabel,
            controller: controller,
          ),
        );
      },
    );
  } finally {
    controller.dispose();
  }
}

/// Карточка диалога ввода имени (в стиле AlertDialog, но компактнее
/// и с «крестиком» в правом верхнем углу).
class _FolderNameCard extends StatelessWidget {
  const _FolderNameCard({
    required this.title,
    required this.label,
    required this.hint,
    required this.confirmLabel,
    required this.controller,
  });

  final String title;
  final String label;
  final String hint;
  final String confirmLabel;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 12,
      shadowColor: Colors.black45,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: SizedBox(
        width: 300,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    icon: const Icon(Icons.close, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(labelText: label, hintText: hint),
                onSubmitted: (v) => Navigator.of(context).pop(v),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(controller.text),
                    child: Text(confirmLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
          leading: Icon(
            Icons.tag,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
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
                  leading: Icon(
                    Icons.label_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
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

/// Заголовок секции — единый стиль для всех блоков панели:
/// иконка в акцентном цвете + крупный полужирный текст.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label, {this.icon, this.trailing});

  final String label;
  final IconData? icon;

  /// Опциональный элемент справа (например, кнопка «+»).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: scheme.primary),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
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
      // Иконки в акцентном цвете элементов управления — единый стиль UI.
      leading: Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
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
                  // Иконка папки — в акцентном цвете элементов управления.
                  Icon(
                    Icons.folder_outlined,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
              title: Text(
                widget.folder.name,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
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
            // «Крестик» закрытия в правом верхнем углу меню.
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                tooltip: 'Закрыть',
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ),
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
    final name = await _showFolderNameDialog(
      context: context,
      title: 'Подпапка в «${widget.folder.name}»',
      label: 'Название подпапки',
      hint: 'Например: Иконки',
      confirmLabel: 'Создать',
    );

    if (name != null && name.trim().isNotEmpty) {
      await state.createSubfolder(name.trim(), widget.folder.id);
    }
  }

  Future<void> _renameDialog(
      BuildContext context, CollectionState state) async {
    final name = await _showFolderNameDialog(
      context: context,
      title: 'Переименовать папку',
      label: 'Название папки',
      hint: '',
      confirmLabel: 'Сохранить',
      initialText: widget.folder.name,
    );

    if (name != null && name.trim().isNotEmpty) {
      await state.renameFolder(widget.folder.id, name.trim());
    }
  }

  Future<void> _deleteDialog(
      BuildContext context, CollectionState state) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: 'Удалить папку?',
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
