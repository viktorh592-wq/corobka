import 'dart:async';

import '../theme/app_theme.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    // Fallback на случай темы без расширения PanelColors.
    final colors = Theme.of(context).extension<PanelColors>() ??
        PanelColors.fallback(Theme.of(context).brightness);
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
        _Preview(item: item),
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
          if (item.isAudio) ...[
            _BpmBlock(item: item),
            const Divider(),
          ],
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

/// Превью элемента: изображение, видео или аудио.
class _Preview extends StatelessWidget {
  const _Preview({required this.item});

  final CollectionItem item;

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (item.isVideo) {
      // Показываем извлечённый превью-кадр, если он уже есть.
      final state = context.read<CollectionState>();
      final thumbPath = state.videoThumbnailPath(item.path);
      content = thumbPath != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(thumbPath),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      _videoPlaceholder(context, item),
                ),
                Center(
                  child: Icon(
                    Icons.play_circle_outline,
                    size: 44,
                    color: Colors.white.withValues(alpha: 0.9),
                    shadows: const [
                      Shadow(blurRadius: 10, color: Colors.black54),
                    ],
                  ),
                ),
              ],
            )
          : _videoPlaceholder(context, item);
    } else if (item.isAudio) {
      content = Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.audio_file_outlined, size: 48),
            const SizedBox(height: 8),
            Text('Аудио · ${item.format?.toUpperCase() ?? ''}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    } else {
      content = Image.file(
        File(item.path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.broken_image_outlined, size: 40),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(aspectRatio: 16 / 10, child: content),
    );
  }
}

/// Плейсхолдер видео без готового превью-кадра.
Widget _videoPlaceholder(BuildContext context, CollectionItem item) {
  return Container(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.movie_outlined, size: 48),
        const SizedBox(height: 8),
        Text('Видео · ${item.format?.toUpperCase() ?? ''}',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
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
        if (item.isImage)
          _MetaRow(
            label: 'Размер',
            value: '${item.width ?? '?'} × ${item.height ?? '?'}',
          ),
        if (item.isAudio && item.bpm != null)
          _MetaRow(label: 'BPM', value: '${item.bpm}'),
        if (item.palette != null) _PaletteBlock(paletteJson: item.palette!),
        if (item.isVideo || item.isAudio) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: Icon(
              item.isVideo
                  ? Icons.play_circle_outline
                  : Icons.headphones_outlined,
              size: 18,
            ),
            label: const Text('Открыть системным плеером'),
            onPressed: () =>
                context.read<CollectionState>().openItemExternally(item),
          ),
        ],
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

/// Интерактивная палитра: клик по цвету показывает его HEX-код,
/// который можно скопировать в буфер обмена.
class _PaletteBlock extends StatefulWidget {
  const _PaletteBlock({required this.paletteJson});

  final String paletteJson;

  @override
  State<_PaletteBlock> createState() => _PaletteBlockState();
}

class _PaletteBlockState extends State<_PaletteBlock> {
  /// Выбранный цвет (индекс в списке) — под палитрой показывается его код.
  int? _selectedIndex;

  late List<Color> _colors;

  @override
  void initState() {
    super.initState();
    _colors = _parseColors(widget.paletteJson);
  }

  @override
  void didUpdateWidget(_PaletteBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paletteJson != widget.paletteJson) {
      _colors = _parseColors(widget.paletteJson);
      _selectedIndex = null;
    }
  }

  /// HEX-код выбранного цвета в формате #RRGGBB.
  String? get _selectedHex {
    final idx = _selectedIndex;
    if (idx == null || idx < 0 || idx >= _colors.length) return null;
    final argb = _colors[idx].toARGB32() & 0xFFFFFF;
    return argb.toRadixString(16).padLeft(6, '0').toUpperCase();
  }

  Future<void> _copyHex() async {
    final hex = _selectedHex;
    if (hex == null) return;
    await Clipboard.setData(ClipboardData(text: '#$hex'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Скопировано: #$hex'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_colors.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < _colors.length; i++)
                _ColorSwatch(
                  color: _colors[i],
                  selected: _selectedIndex == i,
                  hex: _hexOf(_colors[i]),
                  onTap: () => setState(() {
                    _selectedIndex = _selectedIndex == i ? null : i;
                  }),
                ),
            ],
          ),
          // Код выбранного цвета + кнопка копирования.
          if (_selectedHex != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: _colors[_selectedIndex!],
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '#$_selectedHex',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Копировать код цвета',
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    visualDensity: VisualDensity.compact,
                    onPressed: _copyHex,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _hexOf(Color color) {
    final argb = color.toARGB32() & 0xFFFFFF;
    return argb.toRadixString(16).padLeft(6, '0').toUpperCase();
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

/// Кликабельный квадратик цвета с подсказкой HEX-кода.
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.hex,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final String hex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: '#$hex\nКликните, чтобы увидеть код',
        waitDuration: const Duration(milliseconds: 400),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outlineVariant,
                width: selected ? 2.5 : 1,
              ),
            ),
            child: selected
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
          ),
        ),
      ),
    );
  }
}

/// Блок BPM для аудиофайлов: поле ввода + автоматический тег «BPM <n>».
class _BpmBlock extends StatefulWidget {
  const _BpmBlock({required this.item});

  final CollectionItem item;

  @override
  State<_BpmBlock> createState() => _BpmBlockState();
}

class _BpmBlockState extends State<_BpmBlock> {
  late final TextEditingController _controller;
  int _lastItemId = -1;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.item.bpm?.toString() ?? '',
    );
    _lastItemId = widget.item.id;
  }

  @override
  void didUpdateWidget(_BpmBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.id != _lastItemId) {
      _controller.text = widget.item.bpm?.toString() ?? '';
      _lastItemId = widget.item.id;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save(String value) {
    final parsed = int.tryParse(value.trim());
    final state = context.read<CollectionState>();
    state.setSelectedItemBpm(
      parsed == null || parsed <= 0 ? null : parsed.clamp(1, 400),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('BPM', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(width: 6),
            Tooltip(
              message:
                  'Ударов в минуту. Сохраняется автоматически и добавляется '
                  'тег «BPM <значение>» — по нему можно фильтровать.',
              child: Icon(
                Icons.info_outline,
                size: 14,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  hintText: 'Например: 120',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: _save,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () => _save(_controller.text),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ],
    );
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
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final tag = _controller.text.trim();
    if (tag.isNotEmpty) {
      context.read<CollectionState>().addTagToSelectedItem(tag);
      _controller.clear();
      // Возвращаем фокус в поле — можно сразу ввести следующий тег.
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      decoration: InputDecoration(
        labelText: 'Добавить тег (Enter или кнопка)',
        isDense: true,
        prefixIcon: const Icon(Icons.add, size: 18),
        // Кнопка подтверждения — тег добавляется и мышью, без Enter.
        suffixIcon: IconButton(
          tooltip: 'Добавить тег',
          icon: const Icon(Icons.check_circle_outline, size: 20),
          onPressed: _submit,
        ),
      ),
      onSubmitted: (_) => _submit(),
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
          // Авто-расширение поля вниз при заполнении текстом.
          // minLines — стартовая высота; maxLines: null позволяет расти
          // неограниченно по мере ввода.
          minLines: 6,
          maxLines: null,
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
