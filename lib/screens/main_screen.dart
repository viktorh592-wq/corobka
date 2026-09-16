import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/settings_repository.dart';
import '../features/collection/collection_state.dart';
import '../features/settings/theme_provider.dart';
import '../widgets/app_dialog.dart';
import '../widgets/content_area.dart';
import '../widgets/left_panel.dart';
import '../widgets/panel_drag_handle.dart';
import '../widgets/right_panel.dart';

/// Главный экран приложения.
///
/// Компоновка трёх областей: левая панель навигации, центральная область
/// контента и правая панель деталей. Границы панелей ПЕРЕТАСКИВАЮТСЯ
/// мышью (зажать границу — потянуть — ширину можно менять; размер
/// сохраняется между запусками). Поддерживает горячие клавиши и настройки
/// (тема, корневой каталог коллекции).
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  /// Ограничения ширины панелей (как в Eagle — разумные границы).
  static const double _leftMin = 170, _leftMax = 460;
  static const double _rightMin = 220, _rightMax = 560;

  double _leftWidth = 220;
  double _rightWidth = 260;

  final SettingsRepository _settings = SettingsRepository();

  @override
  void initState() {
    super.initState();
    _loadPanelWidths();
  }

  /// Загрузка сохранённых ширин панелей.
  Future<void> _loadPanelWidths() async {
    try {
      final left = await _settings.loadLeftPanelWidth();
      final right = await _settings.loadRightPanelWidth();
      if (!mounted) return;
      setState(() {
        if (left != null) _leftWidth = left.clamp(_leftMin, _leftMax);
        if (right != null) _rightWidth = right.clamp(_rightMin, _rightMax);
      });
    } catch (_) {
      // Настройки недоступны — работаем с ширинами по умолчанию.
    }
  }

  void _onLeftDrag(double delta) {
    setState(() {
      _leftWidth = (_leftWidth + delta).clamp(_leftMin, _leftMax);
    });
  }

  void _onRightDrag(double delta) {
    // Правая панель: тянем границу влево — панель шире.
    setState(() {
      _rightWidth = (_rightWidth - delta).clamp(_rightMin, _rightMax);
    });
  }

  Future<void> _savePanelWidths() async {
    try {
      await _settings.saveLeftPanelWidth(_leftWidth);
      await _settings.saveRightPanelWidth(_rightWidth);
    } catch (_) {}
  }

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
              // Индикатор-кнопка локального HTTP-сервера: показывает статус
              // (зелёный — запущен, серый — выключен) и открывает настройки
              // по клику.
              Selector<CollectionState, bool>(
                selector: (_, s) => s.isHttpServerRunning,
                builder: (context, running, _) => IconButton(
                  tooltip: running
                      ? 'Локальный сервер запущен — клик для настроек'
                      : 'Локальный сервер выключен — клик для настроек',
                  icon: Icon(
                    running ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                    color: running
                        ? Colors.green
                        : Theme.of(context).colorScheme.outline,
                  ),
                  onPressed: () => _openSettings(context),
                ),
              ),
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
          body: Row(
            children: [
              SizedBox(width: _leftWidth, child: const LeftPanel()),
              // Перетаскиваемая граница левой панели.
              PanelDragHandle(onDrag: _onLeftDrag, onDragEnd: _savePanelWidths),
              const Expanded(child: ContentArea()),
              // Перетаскиваемая граница правой панели.
              PanelDragHandle(
                onDrag: _onRightDrag,
                onDragEnd: _savePanelWidths,
              ),
              SizedBox(width: _rightWidth, child: const RightPanel()),
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

  /// Диалог настроек: корневой каталог коллекции (как папка библиотеки Eagle)
  /// и локальный HTTP-сервер для прямого приёма файлов (как Eagle Browser
  /// Extension).
  Future<void> _openSettings(BuildContext context) async {
    final state = context.read<CollectionState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: 'Настройки',
        content: _SettingsContent(state: state),
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

/// Содержимое диалога настроек: каталог коллекции + локальный HTTP-сервер.
///
/// Использует `StatefulWidget`, чтобы управлять полем ввода порта локально
/// (без перерисовки всего диалога при наборе).
class _SettingsContent extends StatefulWidget {
  const _SettingsContent({required this.state});

  final CollectionState state;

  @override
  State<_SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends State<_SettingsContent> {
  late final TextEditingController _portController;

  @override
  void initState() {
    super.initState();
    _portController = TextEditingController(
      text: widget.state.httpServerPort.toString(),
    );
  }

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final running = state.isHttpServerRunning;
    final url = state.httpServerUrl;
    final error = state.httpServerError;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Корневой каталог коллекции',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        Text(
          state.rootPath ?? 'Не задан',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Новые импортированные файлы будут сохраняться в выбранный '
          'каталог. Уже добавленные файлы остаются на прежних местах.',
        ),
        const Divider(height: 32),

        // ─────────── Локальный HTTP-сервер ───────────
        Text(
          'Локальный HTTP-сервер',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        const Text(
          'Позволяет расширению браузера и другим приложениям отправлять '
          'файлы в «Коробку» одним кликом (как Eagle). Сервер слушает '
          'только 127.0.0.1 — извне недоступен.',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Switch.adaptive(
              value: running,
              onChanged: (v) => state.setHttpServerEnabled(v),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                running ? 'Запущен' : 'Выключен',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 90,
              child: TextField(
                controller: _portController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Порт',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (value) {
                  final p = int.tryParse(value);
                  if (p != null) state.setHttpServerPort(p);
                },
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () {
                final p = int.tryParse(_portController.text.trim());
                if (p != null) state.setHttpServerPort(p);
              },
              child: const Text('Применить'),
            ),
          ],
        ),
        if (url != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    url,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Копировать URL',
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('URL сервера скопирован'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Пример: POST $url/api/item/add с { "name": "x.png", "base64": "..." }',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              error,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
