import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'features/collection/collection_state.dart';
import 'features/import/hot_folder_service.dart';
import 'features/settings/theme_provider.dart';
import 'screens/main_screen.dart';
import 'theme/app_theme.dart';

void main() {
  // Гарантируем инициализацию биндингов до обращения к плагинам
  // (shared_preferences, path_provider) из асинхронного кода.
  WidgetsFlutterBinding.ensureInitialized();

  // Инициализация media_kit (libmpv) — нужна для превью-кадров видео.
  // Если нативные библиотеки недоступны (тесты, экзотические системы) —
  // работаем дальше без превью видео, приложение не должно падать.
  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    debugPrint('MediaKit init skipped: $e');
  }

  runApp(const KorobkaApp());
}

class KorobkaApp extends StatelessWidget {
  const KorobkaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => CollectionState()),
      ],
      child: const _AppView(),
    );
  }
}

class _AppView extends StatefulWidget {
  const _AppView();

  @override
  State<_AppView> createState() => _AppViewState();
}

class _AppViewState extends State<_AppView> {
  @override
  void initState() {
    super.initState();
    // Инициализируем коллекцию и загружаем настройки после первого рендера,
    // чтобы не блокировать построение виджет-дерева.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Папка-приёмник: расширение браузера кладёт файлы в
      // «Загрузки/Коробка», приложение подхватывает их само.
      // Запускаем после инициализации коллекции (нужен корневой каталог).
      try {
        await context.read<CollectionState>().initialize();
        await HotFolderService.startFor(context.read<CollectionState>());
      } catch (e) {
        debugPrint('HotFolderService start skipped: $e');
      }
      context.read<ThemeProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();

    return MaterialApp(
      title: 'коробка',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _resolveThemeMode(theme.mode),
      home: const MainScreen(),
    );
  }

  ThemeMode _resolveThemeMode(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }
}