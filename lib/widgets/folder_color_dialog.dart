import 'package:flutter/material.dart';

import '../features/folders/folder_colors.dart';
import 'app_dialog.dart';
import 'color_sliders.dart';

/// Диалог «Настройка цвета папки».
///
/// Устроен так же, как «Фильтр по цвету»: быстрые пресеты, кастомный
/// цвет (превью + HEX) и HSV-палитра. Отличия — заголовок и то, что
/// пресеты показаны цветными иконками папок (как в Eagle).
///
/// Результат [showDialog]:
///  - `null`      — отмена (крестик / Esc);
///  - пустая ''   — «Сбросить» (вернуть стандартный цвет);
///  - иначе HEX-строка без решётки (например, «F44336»).
Future<String?> showFolderColorDialog(
  BuildContext context, {
  required String folderName,
  String? currentHex,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => FolderColorDialog(
      folderName: folderName,
      initialHex: currentHex,
    ),
  );
}

class FolderColorDialog extends StatefulWidget {
  const FolderColorDialog({
    super.key,
    required this.folderName,
    this.initialHex,
  });

  /// Имя папки — показывается в подзаголовке окна.
  final String folderName;

  /// Текущий цвет папки (HEX без решётки) либо null.
  final String? initialHex;

  @override
  State<FolderColorDialog> createState() => _FolderColorDialogState();
}

class _FolderColorDialogState extends State<FolderColorDialog> {
  late HSVColor _hsv;
  late TextEditingController _hexController;

  /// HEX выбранного пресета (для подсветки рамки), может быть null.
  String? _selectedPresetHex;

  @override
  void initState() {
    super.initState();
    final initial = colorFromHex(widget.initialHex) ?? const Color(0xFF2196F3);
    _hsv = HSVColor.fromColor(initial);
    _hexController = TextEditingController(
      text: '#${hexOfColor(initial)}',
    );
    _selectedPresetHex =
        folderColorPresets.any((p) => p.$1 == widget.initialHex)
            ? widget.initialHex
            : null;
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _syncHsv(HSVColor newHsv) {
    setState(() {
      _hsv = newHsv;
      _hexController.text = '#${hexOfColor(newHsv.toColor())}';
      _selectedPresetHex = null;
    });
  }

  void _onHexChanged(String value) {
    final color = colorFromHex(value);
    if (color != null) {
      setState(() {
        _hsv = HSVColor.fromColor(color);
        final hex = hexOfColor(color);
        _selectedPresetHex =
            folderColorPresets.any((p) => p.$1 == hex) ? hex : null;
      });
    }
  }

  void _apply() {
    Navigator.of(context).pop(hexOfColor(_hsv.toColor()));
  }

  void _reset() {
    // Пустая строка = сброс на стандартный цвет (отличаем от отмены).
    Navigator.of(context).pop('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentColor = _hsv.toColor();

    return AppDialog(
      title: 'Настройка цвета папки',
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Подзаголовок: для какой папки настраивается цвет.
              Text(
                'Папка: «${widget.folderName}»',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 12),

              // ── Быстрые пресеты (цветные папки, как в Eagle) ──
              Text('Пресеты', style: theme.textTheme.labelSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (hex, color) in folderColorPresets)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        setState(() {
                          _hsv = HSVColor.fromColor(color);
                          _hexController.text = '#$hex';
                          _selectedPresetHex = hex;
                        });
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _selectedPresetHex == hex
                                ? theme.colorScheme.primary
                                : Colors.grey.shade400,
                            width: _selectedPresetHex == hex ? 2.5 : 1,
                          ),
                        ),
                        child: Icon(
                          Icons.folder,
                          size: 24,
                          color: color,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Кастомный цвет: HEX + превью ──
              Text('Кастомный цвет', style: theme.textTheme.labelSmall),
              const SizedBox(height: 6),
              Row(
                children: [
                  // Превью выбранного цвета (папка на подложке).
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: currentColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                    child: Icon(Icons.folder, size: 32, color: currentColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _hexController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'HEX',
                        hintText: '#2196F3',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: _onHexChanged,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── HSV-палитра (как в «Фильтре по цвету») ──
              Text('Палитра', style: theme.textTheme.labelSmall),
              const SizedBox(height: 6),
              HueSlider(
                value: _hsv.hue,
                onChanged: (h) => _syncHsv(_hsv.withHue(h)),
              ),
              const SizedBox(height: 8),
              SaturationSlider(
                hsv: _hsv,
                onChanged: (s) => _syncHsv(_hsv.withSaturation(s)),
              ),
              const SizedBox(height: 8),
              ValueSlider(
                hsv: _hsv,
                onChanged: (v) => _syncHsv(_hsv.withValue(v)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _reset,
          child: const Text('Сбросить'),
        ),
        FilledButton(
          onPressed: _apply,
          child: const Text('Применить'),
        ),
      ],
    );
  }
}
