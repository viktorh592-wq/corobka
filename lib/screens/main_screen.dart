import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/settings_repository.dart';
import '../features/collection/collection_state.dart';
import '../features/logging/log_service.dart';
import '../features/settings/theme_provider.dart';
import '../theme/app_theme.dart';
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
        // Выделить все элементы текущего списка.
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): () {
          context.read<CollectionState>().selectAllItems();
        },
        // Снять массовое выделение.
        const SingleActivator(LogicalKeyboardKey.escape): () {
          context.read<CollectionState>().clearMultiSelection();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: _buildAppBar(context),
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

  /// AppBar с эффектом стекла в iOS-темах.
  ///
  /// В Material — обычный opaque AppBar (через AppBarTheme).
  /// В iOS Frosted — transparent фон + BackdropFilter σ=30.
  /// В iOS Transparent — transparent фон + полупрозрачный цвет панели.
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final isGlass = context.designSystem != AppDesignSystem.material;
    final blurOn = context.backdropBlurEnabled && context.backdropBlurSigma > 0;

    Widget? flexibleSpace;
    Color? backgroundColor;

    if (isGlass) {
      // В iOS-темах AppBar сам по себе прозрачный, а стекло рендерит
      // flexibleSpace через BackdropFilter.
      backgroundColor = Colors.transparent;
      if (blurOn) {
        flexibleSpace = BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: context.backdropBlurSigma,
            sigmaY: context.backdropBlurSigma,
            tileMode: TileMode.mirror,
          ),
          child: ColoredBox(color: context.panelColors.panel),
        );
      } else {
        flexibleSpace = ColoredBox(color: context.panelColors.panel);
      }
    }

    return AppBar(
      title: const Text('коробка'),
      backgroundColor: backgroundColor,
      flexibleSpace: flexibleSpace,
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

  /// Диалог настроек: корневой каталог коллекции (как папка библиотеки
  /// Eagle) + управление журналом событий (логом) приложения и плагина.
  Future<void> _openSettings(BuildContext context) async {
    final state = context.read<CollectionState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: 'Настройки',
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
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            // ── Оформление интерфейса ──
            const _DesignSystemSection(),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            // ── Палитра цветов ──
            _PaletteRegenSection(
              state: state,
              messenger: ScaffoldMessenger.of(dialogContext),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            // ── Журнал (лог) приложения и плагина ──
            _LogSection(messenger: ScaffoldMessenger.of(dialogContext)),
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

/// Секция выбора дизайн-системы интерфейса в настройках.
///
/// Три варианта (Material / iOS Frosted / iOS Transparent) плюс переключатель
/// светлой/тёмной темы. Выбор применяется немедленно — [ThemeProvider]
/// перестраивает корневой [MaterialApp].
class _DesignSystemSection extends StatelessWidget {
  const _DesignSystemSection();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Оформление интерфейса',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        const Text(
          'Дизайн-система интерфейса. Material — классический M3-стиль, '
          'iOS Frosted — матовое стекло с размытием, iOS Transparent — '
          'полупрозрачные панели без размытия.',
        ),
        const SizedBox(height: 8),
        // Сегментный контрол дизайн-системы (3 варианта).
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final design in AppDesignSystem.values)
              ChoiceChip(
                label: Text(_designLabel(design)),
                selected: theme.design == design,
                onSelected: (_) => theme.setDesign(design),
              ),
          ],
        ),
        const SizedBox(height: 10),
        // Переключатель яркости (светлая/тёмная/системная).
        Text(
          'Яркость темы',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            ChoiceChip(
              label: const Text('Светлая'),
              selected: theme.mode == AppThemeMode.light,
              onSelected: (_) => theme.setMode(AppThemeMode.light),
            ),
            ChoiceChip(
              label: const Text('Тёмная'),
              selected: theme.mode == AppThemeMode.dark,
              onSelected: (_) => theme.setMode(AppThemeMode.dark),
            ),
            ChoiceChip(
              label: const Text('Системная'),
              selected: theme.mode == AppThemeMode.system,
              onSelected: (_) => theme.setMode(AppThemeMode.system),
            ),
          ],
        ),
      ],
    );
  }

  /// Человекочитаемое название дизайн-системы.
  String _designLabel(AppDesignSystem design) {
    switch (design) {
      case AppDesignSystem.material:
        return 'Material Design';
      case AppDesignSystem.iosFrosted:
        return 'iOS · матовое стекло';
      case AppDesignSystem.iosTransparent:
        return 'iOS · прозрачная';
    }
  }
}

/// Секция массового пересчёта цветовой палитры в настройках.
///
/// После увеличения `maximumColorCount` (5 → 10) в [PaletteService] старые
/// изображения в коллекции всё ещё хранят палитру из 5 цветов. Эта секция
/// позволяет пересчитать палитру разом для всех существующих картинок.
class _PaletteRegenSection extends StatefulWidget {
  const _PaletteRegenSection({required this.state, required this.messenger});

  final CollectionState state;
  final ScaffoldMessengerState messenger;

  @override
  State<_PaletteRegenSection> createState() => _PaletteRegenSectionState();
}

class _PaletteRegenSectionState extends State<_PaletteRegenSection> {
  bool _running = false;
  int _done = 0;
  int _total = 0;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _done = 0;
      _total = 0;
    });
    try {
      final count = await widget.state.regenerateAllPalettes(
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _done = done;
            _total = total;
          });
        },
      );
      if (!mounted) return;
      widget.messenger.showSnackBar(
        SnackBar(content: Text('Палитра обновлена для $count изображений')),
      );
    } catch (e) {
      if (!mounted) return;
      widget.messenger.showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Цветовая палитра',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        const Text(
          'Палитра извлекается при импорте. После обновления числа цветов '
          '(теперь их 10 вместо 5) старые изображения хранят устаревшую '
          'палитру — пересчитайте, чтобы получить все 10 цветов.',
        ),
        const SizedBox(height: 8),
        if (_running && _total > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: _done / _total,
                  minHeight: 4,
                ),
                const SizedBox(height: 4),
                Text(
                  '$_done / $_total',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            FilledButton.tonalIcon(
              icon: const Icon(Icons.palette_outlined, size: 16),
              label: const Text('Пересчитать для всех'),
              onPressed: _running ? null : _run,
            ),
          ],
        ),
      ],
    );
  }
}

/// Секция управления журналом в настройках.
///
/// Кнопки «Начать запись» / «Остановить запись» / «Выгрузить лог».
/// В журнал пишутся события и приложения, и расширения браузера:
/// логи плагина приходят через локальный HTTP-сервер (POST /api/log)
/// и помечаются в файле меткой [plugin].
class _LogSection extends StatelessWidget {
  const _LogSection({required this.messenger});

  final ScaffoldMessengerState messenger;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LogService.instance,
      builder: (context, _) {
        final log = LogService.instance;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Журнал (лог)',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  log.isRecording
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 14,
                  color: log.isRecording
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    log.isRecording
                        ? 'Запись ведётся (приложение + плагин)'
                        : 'Запись остановлена',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            if (log.isRecording && log.logFilePath != null) ...[
              const SizedBox(height: 4),
              Text(
                log.logFilePath!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (!log.isRecording)
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.fiber_manual_record, size: 16),
                    label: const Text('Начать запись'),
                    onPressed: () => LogService.instance.start(),
                  )
                else
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.stop, size: 16),
                    label: const Text('Остановить запись'),
                    onPressed: () => LogService.instance.stop(),
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.file_download_outlined, size: 16),
                  label: const Text('Выгрузить лог'),
                  onPressed: () => _exportLog(context),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'В лог пишутся события приложения и расширения браузера '
              'одновременно. Выгрузка сохраняет текущий журнал в файл.',
            ),
          ],
        );
      },
    );
  }

  /// Сохранение журнала в файл, выбранный пользователем.
  Future<void> _exportLog(BuildContext context) async {
    try {
      final path = await LogService.instance.export(
        pickPath: (defaultName) async {
          final result = await FilePicker.platform.saveFile(
            dialogTitle: 'Выгрузить лог',
            fileName: defaultName,
          );
          // На некоторых платформах saveFile возвращает имя без пути —
          // тогда используем его как есть (плагин сам даёт полный путь).
          return result;
        },
      );
      if (path == null) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Лог сохранён: $path')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось сохранить лог: $e')),
      );
    }
  }
}
