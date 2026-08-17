import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'features/collection/collection_state.dart';
import 'features/settings/theme_provider.dart';
import 'screens/main_screen.dart';
import 'theme/app_theme.dart';

void main() {
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CollectionState>().initialize();
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