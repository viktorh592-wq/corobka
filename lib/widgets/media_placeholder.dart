import 'package:flutter/material.dart';

import '../data/models/item.dart';

/// Плейсхолдер для видео/аудио (вместо Image.file, который не умеет
/// декодировать эти форматы).
class MediaPlaceholder extends StatelessWidget {
  const MediaPlaceholder({super.key, required this.item});

  final CollectionItem item;

  @override
  Widget build(BuildContext context) {
    final isVideo = item.isVideo;
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  isVideo ? Icons.movie_outlined : Icons.audio_file_outlined,
                  size: 40,
                  color: Theme.of(context).colorScheme.outline,
                ),
                // Значок «play» для видео — сразу видно, что это ролик.
                if (isVideo)
                  Positioned.fill(
                    child: Align(
                      alignment: const Alignment(0.45, 0.0),
                      child: Icon(
                        Icons.play_arrow,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              (item.format ?? '').toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
