import 'package:flutter/material.dart';

import '../data/models/item.dart';

/// Плейсхолдер для видео/аудио (вместо Image.file, который не умеет
/// декодировать эти форматы).
///
/// Иконка типа файла — крупная и масштабируется под размер карточки,
/// чтобы тип файла читался даже на маленьких превью.
class MediaPlaceholder extends StatelessWidget {
  const MediaPlaceholder({super.key, required this.item});

  final CollectionItem item;

  @override
  Widget build(BuildContext context) {
    final isVideo = item.isVideo;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      // Размер иконки подстраивается под карточку (карточки бывают от ~120px).
      child: LayoutBuilder(
        builder: (context, constraints) {
          final iconSize =
              (constraints.maxWidth * 0.4).clamp(44.0, 104.0).toDouble();
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      isVideo
                          ? Icons.movie_outlined
                          : Icons.audio_file_outlined,
                      size: iconSize,
                      color: scheme.primary.withValues(alpha: 0.75),
                    ),
                    // Значок «play» для видео — сразу видно, что это ролик.
                    if (isVideo)
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment(iconSize * 0.004, 0.0),
                          child: Icon(
                            Icons.play_arrow,
                            size: iconSize * 0.4,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  (item.format ?? '').toUpperCase(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
