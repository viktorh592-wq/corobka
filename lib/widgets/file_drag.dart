import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

/// Нативный drag-and-drop доступен только вне widget-тестов.
///
/// В тестах (flutter test) нативный движок недоступен — инициализация
/// super_native_extensions бросает MissingPluginException
/// (канал `dev.irondash.engine_context` не замокан), что ломает тесты.
/// Поэтому в тестах обёртки возвращают дочерний виджет как есть.
final bool kNativeDragDropSupported =
    !kIsWeb && !Platform.environment.containsKey('FLUTTER_TEST');

/// Формат локальных данных drag-сессии «коробки»: список id элементов.
///
/// Данные доступны только внутри приложения (не передаются внешним
/// программам) — по ним папки понимают, какие элементы перетащены.
const _itemIdsKey = 'korobka.itemIds';

/// Извлекает список id элементов из локальных данных drag-элемента.
List<int>? itemIdsFromLocalData(Object? localData) {
  if (localData is Map && localData[_itemIdsKey] is List) {
    return (localData[_itemIdsKey] as List).cast<int>();
  }
  return null;
}

/// Возвращает true, если drag-сессия пришла из «коробки»
/// (перетаскивание элементов коллекции внутри приложения).
bool isInternalDrag(DropOverEvent event) {
  return event.session.items.any(
    (item) => itemIdsFromLocalData(item.localData) != null,
  );
}

/// Зона приёма drag-and-drop для плиток папок в левой панели.
///
/// Принимает:
/// 1. Перетаскивание элементов изнутри приложения → перемещение
///    в папку ([onMoveItems], id берутся из локальных данных сессии).
/// 2. Файлы из Проводника → импорт в эту папку ([onImportFiles],
///    пути через `Formats.fileUri` / CF_HDROP).
///
/// Подсвечивает плитку при наведении перетаскиваемого объекта
/// (как в Eagle — «брось сюда, чтобы переместить в папку»).
class FolderDropRegion extends StatefulWidget {
  const FolderDropRegion({
    super.key,
    required this.child,
    required this.accept,
    required this.onMoveItems,
    this.onImportFiles,
  });

  final Widget child;

  /// Принимает ли папка перетаскивание (например, в корзине — нет).
  final bool accept;

  /// Перемещение элементов коллекции в папку (id элементов).
  final ValueChanged<List<int>> onMoveItems;

  /// Импорт новых файлов из Проводника в эту папку (null — не принимать).
  final ValueChanged<List<String>>? onImportFiles;

  @override
  State<FolderDropRegion> createState() => _FolderDropRegionState();
}

class _FolderDropRegionState extends State<FolderDropRegion> {
  bool _hovered = false;

  DropOperation _operationFor(DropOverEvent event) {
    if (!widget.accept) return DropOperation.none;
    // Внутреннее перемещение элементов коллекции.
    if (isInternalDrag(event)) return DropOperation.move;
    // Внешние файлы из Проводника (если папка принимает импорт).
    final hasFiles = widget.onImportFiles != null &&
        event.session.items.any((item) => item.canProvide(Formats.fileUri));
    return hasFiles ? DropOperation.copy : DropOperation.none;
  }

  Future<void> _handleDrop(PerformDropEvent event) async {
    if (_hovered && mounted) setState(() => _hovered = false);
    if (!widget.accept) return;

    // 1. Перемещение элементов изнутри приложения.
    for (final item in event.session.items) {
      final ids = itemIdsFromLocalData(item.localData);
      if (ids != null && ids.isNotEmpty) {
        widget.onMoveItems(ids);
        return;
      }
    }

    // 2. Внешние файлы из Проводника → импорт в эту папку.
    final import = widget.onImportFiles;
    if (import == null) return;
    for (final item in event.session.items) {
      final reader = item.dataReader;
      if (reader == null || !reader.canProvide(Formats.fileUri)) continue;
      reader.getValue<Uri>(
        Formats.fileUri,
        (value) async {
          if (value == null) return;
          try {
            import([value.toFilePath()]);
          } catch (e) {
            debugPrint('FolderDropRegion: ошибка импорта: $e');
          }
        },
        onError: (error) {
          debugPrint('FolderDropRegion: не удалось прочитать путь: $error');
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // В тестах нативный drag-and-drop недоступен — рисуем только плитку.
    if (!kNativeDragDropSupported) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.transparent, width: 2),
        ),
        child: widget.child,
      );
    }
    return DropRegion(
      formats: const [Formats.fileUri],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropEnter: (event) {
        // onDropEnter вызывается только для региона, чей onDropOver
        // вернул операцию приёма — можно подсвечивать без проверок.
        if (mounted) setState(() => _hovered = true);
      },
      onDropLeave: (event) {
        if (mounted) setState(() => _hovered = false);
      },
      onDropOver: _operationFor,
      onPerformDrop: _handleDrop,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          // Подсветка папки — сюда можно бросить файлы.
          color: _hovered
              ? Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.55)
              : null,
          border: Border.all(
            color: _hovered
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

/// Обёртка карточки, которую можно перетащить НАРУЖУ из приложения.
///
/// Использует нативный drag-and-drop (super_drag_and_drop): файл можно
/// перетащить в Проводник Windows, в папку любой программы или в любое
/// другое ПО — как из обычной файловой панели. Файл передаётся как
/// «виртуальный файл» с реальным содержимым на диске и исходным именем.
///
/// Одновременно в [DragItem.localData] передаются id элементов коллекции,
/// поэтому бросание на папки внутри приложения продолжает работать как
/// перемещение (см. [itemIdsFromLocalData] и DropRegion в left_panel).
///
/// Перетаскивание работает и для одиночного элемента, и для массового
/// выделения: [paths] — список путей файлов, [ids] — список их id.
class NativeFileDraggable extends StatelessWidget {
  const NativeFileDraggable({
    super.key,
    required this.paths,
    required this.ids,
    required this.child,
  });

  /// Пути файлов на диске (в том же порядке, что и [ids]).
  final List<String> paths;

  /// Идентификаторы элементов коллекции.
  final List<int> ids;

  final Widget child;

  /// Сборка drag-элемента для одного файла.
  ///
  /// Содержимое файла передаётся «виртуальным файлом»: байты читаются
  /// потоково по запросу принимающего ПО, поэтому большие видео не
  /// загружаются в память целиком. [isFirst] — элемент, несущий
  /// локальные данные с id выделения. Возвращает null, если файл
  /// недоступен (перемещён/удалён с диска) — drag не начнётся.
  DragItem? _buildDragItem(String path, bool isFirst) {
    final name = path.split(Platform.pathSeparator).last;
    final format = _fileFormatForName(name);

    final file = File(path);
    final int size;
    try {
      size = file.lengthSync();
    } catch (e) {
      debugPrint('drag-out: файл недоступен $path: $e');
      return null;
    }

    final item = DragItem(
      suggestedName: name,
      // Локальные данные — только для приёмников внутри приложения.
      localData: isFirst ? {_itemIdsKey: ids} : null,
    );

    item.addVirtualFile(
      format: format,
      provider: (sinkProvider, progress) {
        final sink = sinkProvider(fileSize: size);
        // Стримим содержимое файла по запросу получателя.
        file.openRead().listen(
              sink.add,
              onError: (Object e) {
                debugPrint('drag-out: ошибка чтения $path: $e');
                sink.close();
              },
              onDone: () => sink.close(),
              cancelOnError: true,
            );
      },
    );
    return item;
  }

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty || paths.length != ids.length) return child;
    // В тестах нативный drag-and-drop недоступен.
    if (!kNativeDragDropSupported) return child;

    return DragItemWidget(
      dragItemProvider: (request) => _buildDragItem(paths.first, true),
      allowedOperations: () => const [
        DropOperation.copy,
        DropOperation.move,
      ],
      child: DraggableWidget(
        // Для массового выделения добавляем в сессию по одному
        // drag-элементу на каждый файл выделения.
        onDragConfiguration: (configuration, session) async {
          if (paths.length <= 1) return configuration;

          final first = configuration.items.first;
          final items = <DragConfigurationItem>[first];
          for (var i = 1; i < paths.length; i++) {
            final item = _buildDragItem(paths[i], false);
            if (item == null) continue;
            items.add(DragConfigurationItem(
              item: item,
              image: first.image,
              liftImage: first.liftImage,
            ));
          }
          return DragConfiguration(
            items: items,
            allowedOperations: configuration.allowedOperations,
            options: configuration.options,
          );
        },
        child: child,
      ),
    );
  }
}

/// Сопоставление расширения файла с [FileFormat] super_drag_and_drop.
///
/// Формат определяет MIME-дескриптор виртуального файла, по которому
/// принимающее ПО (Проводник, Photoshop, браузер и т.д.) распознаёт
/// тип содержимого.
FileFormat _fileFormatForName(String name) {
  final ext = name.contains('.')
      ? name.substring(name.lastIndexOf('.') + 1).toLowerCase()
      : '';

  switch (ext) {
    // Изображения.
    case 'png':
      return Formats.png;
    case 'jpg':
    case 'jpeg':
      return Formats.jpeg;
    case 'gif':
      return Formats.gif;
    case 'webp':
      return Formats.webp;
    case 'bmp':
      return Formats.bmp;
    case 'tif':
    case 'tiff':
      return Formats.tiff;
    case 'svg':
      return Formats.svg;
    case 'ico':
      return Formats.ico;
    case 'heic':
      return Formats.heic;
    case 'heif':
      return Formats.heif;

    // Видео.
    case 'mp4':
    case 'm4v':
      return Formats.mp4;
    case 'mov':
      return Formats.mov;
    case 'avi':
      return Formats.avi;
    case 'mkv':
      return Formats.mkv;
    case 'webm':
      return Formats.webm;
    case 'mpeg':
    case 'mpg':
      return Formats.mpeg;
    case 'wmv':
      return Formats.wmv;
    case 'flv':
      return Formats.flv;
    case 'ts':
      return Formats.ts;

    // Аудио.
    case 'mp3':
      return Formats.mp3;
    case 'wav':
      return Formats.wav;
    case 'ogg':
      return Formats.ogg;
    case 'oga':
      return Formats.oga;
    case 'aac':
      return Formats.aac;

    // Документы и архивы.
    case 'pdf':
      return Formats.pdf;
    case 'zip':
      return Formats.zip;
    case 'rar':
      return Formats.rar;
    case '7z':
      return Formats.sevenZip;
    case 'json':
      return Formats.json;
    case 'csv':
      return Formats.csv;

    default:
      // Универсальный формат: получатель получит файл с исходным
      // именем и двоичным содержимым.
      return Formats.plainTextFile;
  }
}
