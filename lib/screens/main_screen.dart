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
/// контента и правая панель деталей. Поддерживает горячие клавиши.
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
        // Переключение темы.
        const SingleActivator(LogicalKeyboardKey.keyT): () {
          _toggleTheme(context);
        },
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('коробка'),
          actions: [
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
            const VerticalDivider(width: 1),
            Expanded(child: ContentArea()),
            const VerticalDivider(width: 1),
            SizedBox(width: 260, child: RightPanel()),
          ],
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
}