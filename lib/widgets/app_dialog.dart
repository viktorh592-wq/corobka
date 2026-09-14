import 'package:flutter/material.dart';

/// Единое модальное окно приложения «коробка».
///
/// От обычного [AlertDialog] отличается тем, что в правом верхнем углу
/// заголовка всегда есть кнопка-«крестик» для закрытия (поведение
/// классических десктопных диалогов). Крестик закрывает окно без
/// результата — как кнопка «Отмена».
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.content,
    this.actions,
  });

  /// Заголовок окна.
  final String title;

  /// Содержимое окна (опционально).
  final Widget? content;

  /// Кнопки действий внизу окна (опционально).
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 18, 8, 0),
      title: Row(
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
      content: content,
      actions: actions,
    );
  }
}
