import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../features/collection/collection_state.dart';
import '../features/settings/theme_provider.dart';
import '../widgets/content_area.dart';
import '../widgets/left_panel.dart';
import '../widgets/right_panel.dart';

/// Главный экран приложения.
///
/// Компоновка трёх областей: левая панель навигации, центральная область
/// контента и правая панель деталей. Поддерживает горячие клавиши и настройки
/// (тема, корневой каталог коллекции).
class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        // Сетка.
        const SingleActivator(LogicalKeyboardKey.keyG): () {
          context.read<CollectionState>().setViewMode(ViewMode.grid);
        },
        // Список.
        const SingleActivator(LogicalKeyboardKey.keyL): () {
          context.read<CollectionState>().setViewMode(ViewMode.list);
        },
        // Masonry.
        const SingleActivator(LogicalKeyboardKey.keyM): () {
          context.read<CollectionState>().setViewMode(ViewMode.masonry);
        },
        // Переключение темы.
        const SingleActivator(LogicalKeyboardKey.keyT): () {
          _toggleTheme(context);
        },
        // Удаление выбранного элемента в корзину.
        const SingleActivator(LogicalKeyboardKey.delete): () {
          final item = context.read<CollectionState>().selectedItem;
          if (item != null) {
            context.read<CollectionState>().trashItem(item);
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('коробка'),
            actions: [
              IconButton(
                tooltip: 'Настройки',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => _openSettings(context),
              ),
              IconButton(
                tooltip: 'Переключить тему (T)',
                icon: const Icon(Icons.dark_mode_outlined),
                onPressed: () => _toggleTheme(context),
              ),
            ],
          ),
          body: const Row(
            children: [
              SizedBox(width: 220, child: LeftPanel()),
              VerticalDivider(width: 1),
              Expanded(child: ContentArea()),
              VerticalDivider(width: 1),
              SizedBox(width: 260, child: RightPanel()),
            ],
          ),
        ),
      ),
    );
  }

  /// Переключение темы между светлой и тёмной.
  void _toggleTheme(BuildContext context) {
    final theme = context.read<ThemeProvider>();
    theme.setMode(
      theme.mode == AppThemeMode.dark
          ? AppThemeMode.light
          : AppThemeMode.dark,
    );
  }

  /// Диалог настроек: корневой каталог коллекции (как папка библиотеки Eagle).
  Future<void> _openSettings(BuildContext context) async {
    final state = context.read<CollectionState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Настройки'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Корневой каталог коллекции',
              style: Theme.of(dialogContext).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Text(
              state.rootPath ?? 'Не задан',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'Новые импортированные файлы будут сохраняться в выбранный '
              'каталог. Уже добавленные файлы остаются на прежних местах.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Закрыть'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: const Text('Выбрать каталог'),
            onPressed: () async {
              final picked =
                  await state.collectionService.pickRootDirectory();
              if (picked == null) return;
              await state.changeRootPath(picked);
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            },
          ),
        ],
      ),
    );
  }
}
