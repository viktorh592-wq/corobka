import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:korobka/data/settings_repository.dart';
import 'package:korobka/features/collection/collection_state.dart';
import 'package:korobka/features/settings/theme_provider.dart';
import 'package:korobka/theme/app_theme.dart';
import 'package:korobka/theme/liquid_glass_tokens.dart';
import 'package:korobka/widgets/content_area.dart';
import 'package:korobka/widgets/liquid_glass_theme_toggle.dart';

/// Тесты дизайн-системы iOS 27 / Liquid Glass.
///
/// Покрывают требования гайдлайна COROBKA_iOS27_LiquidGlass_UI_GUIDELINE.md:
///   1. Дизайн-система `iosLiquidGlass` доступна и собирается без ошибок.
///   2. Тема по умолчанию — `iosLiquidGlass` (см. ThemeProvider).
///   3. `LiquidGlassThemeToggle` рендерится и переключает тему по тапу.
///   4. Поле поиска имеет ширину 336px (+20% от исходных 280px, §18).
///   5. Централизованные токены (GlassTokens / RadiusTokens / MotionTokens)
///      содержат ожидаемые значения.
void main() {
  /// In-memory реализация [SettingsRepository] для тестов — не требует
  /// platform channels (SharedPreferences).
  SettingsRepository fakeRepository() => _FakeSettingsRepository();

  test(
    'Liquid Glass: ThemeProvider по умолчанию использует iosLiquidGlass',
    () {
      final provider = ThemeProvider(repository: fakeRepository());
      expect(provider.design, AppDesignSystem.iosLiquidGlass,
          reason: 'по умолчанию должна быть дизайн-система Liquid Glass '
              '(см. COROBKA_iOS27_LiquidGlass_UI_GUIDELINE.md §50)');
    },
  );

  test(
    'Liquid Glass: тема строится для светлой и тёмной яркости',
    () {
      final lightTheme =
          AppTheme.themeFor(AppDesignSystem.iosLiquidGlass, Brightness.light);
      final darkTheme =
          AppTheme.themeFor(AppDesignSystem.iosLiquidGlass, Brightness.dark);

      // Scaffold — НЕ прозрачный (§2.1: контент остаётся резким, без
      // глобального frosting).
      expect(lightTheme.scaffoldBackgroundColor, isNot(Colors.transparent));
      expect(darkTheme.scaffoldBackgroundColor, isNot(Colors.transparent));

      // Светлая тема — светлый фон, тёмная — тёмный.
      expect(
        ThemeData.estimateBrightnessForColor(
            lightTheme.scaffoldBackgroundColor),
        Brightness.light,
        reason: 'светлая тема должна иметь светлый scaffold',
      );
      expect(
        ThemeData.estimateBrightnessForColor(
            darkTheme.scaffoldBackgroundColor),
        Brightness.dark,
        reason: 'тёмная тема должна иметь тёмный scaffold',
      );
    },
  );

  test(
    'Liquid Glass: централизованные токены содержат ожидаемые значения',
    () {
      // Радиусы — §8 CORNER SHAPES.
      expect(RadiusTokens.small, inInclusiveRange(10, 12));
      expect(RadiusTokens.medium, inInclusiveRange(14, 18));
      expect(RadiusTokens.large, inInclusiveRange(20, 24));
      expect(RadiusTokens.capsule, 999);

      // Длительности анимаций — §12.
      expect(MotionTokens.microInteraction, inInclusiveRange(100, 160));
      expect(MotionTokens.standardTransition, inInclusiveRange(180, 280));
      expect(MotionTokens.panelTransition, inInclusiveRange(240, 360));

      // Стекло: акцент — iOS-синий #007AFF (сохраняет семантику приложения).
      expect(GlassTokens.accent, const Color(0xFF007AFF));

      // Сила размытия — visible but controlled (§7.2).
      expect(GlassTokens.blurSmall, lessThan(GlassTokens.blurLarge));
    },
  );

  testWidgets(
    'Liquid Glass: LiquidGlassThemeToggle рендерится и переключает тему',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final themeProvider = ThemeProvider(repository: fakeRepository());
      // Принудительно выбираем Liquid Glass + светлую тему.
      await themeProvider.setDesign(AppDesignSystem.iosLiquidGlass);
      await themeProvider.setMode(AppThemeMode.light);

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: themeProvider,
          child: MaterialApp(
            theme: AppTheme.themeFor(
              AppDesignSystem.iosLiquidGlass,
              Brightness.light,
            ),
            home: const Scaffold(
              body: LiquidGlassThemeToggle(),
            ),
          ),
        ),
      );
      await tester.pump();

      // Тоггл отрендерился.
      expect(find.byType(LiquidGlassThemeToggle), findsOneWidget);

      // До тапа — светлая тема.
      expect(themeProvider.mode, AppThemeMode.light);

      // Тап по тогглу переключает на тёмную.
      await tester.tap(find.byType(LiquidGlassThemeToggle));
      await tester.pump();

      expect(themeProvider.mode, AppThemeMode.dark);
    },
  );

  testWidgets(
    'Liquid Glass: поле поиска имеет ширину 336px (+20% от 280px)',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final themeProvider = ThemeProvider(repository: fakeRepository());
      await themeProvider.setDesign(AppDesignSystem.iosLiquidGlass);
      await themeProvider.setMode(AppThemeMode.light);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
            ChangeNotifierProvider<CollectionState>(
              create: (_) => CollectionState(),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.themeFor(
              AppDesignSystem.iosLiquidGlass,
              Brightness.light,
            ),
            home: const Scaffold(
              body: ContentArea(),
            ),
          ),
        ),
      );
      await tester.pump();
      // Несколько кадров, чтобы LayoutBuilder отработал.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Ищем SizedBox шириной 336 — это обёртка поля поиска (см. §18).
      final searchField = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 336.0,
      );
      expect(
        searchField,
        findsOneWidget,
        reason: 'поле поиска должно быть 336px (280 + 20%, см. §18)',
      );
    },
  );
}

/// In-memory реализация [SettingsRepository] для тестов.
class _FakeSettingsRepository implements SettingsRepository {
  String? _themeMode;
  String? _design;
  String? _viewMode;
  String? _rootPath;
  String? _sortMode;
  double? _thumbnailExtent;
  double? _leftPanelWidth;
  double? _rightPanelWidth;

  @override
  Future<void> saveThemeMode(String mode) async => _themeMode = mode;

  @override
  Future<String?> loadThemeMode() async => _themeMode;

  @override
  Future<void> saveDesignSystem(String design) async => _design = design;

  @override
  Future<String?> loadDesignSystem() async => _design;

  @override
  Future<void> saveViewMode(String mode) async => _viewMode = mode;

  @override
  Future<String?> loadViewMode() async => _viewMode;

  @override
  Future<void> saveRootPath(String path) async => _rootPath = path;

  @override
  Future<String?> loadRootPath() async => _rootPath;

  @override
  Future<void> saveSortMode(String mode) async => _sortMode = mode;

  @override
  Future<String?> loadSortMode() async => _sortMode;

  @override
  Future<void> saveThumbnailExtent(double extent) async =>
      _thumbnailExtent = extent;

  @override
  Future<double?> loadThumbnailExtent() async => _thumbnailExtent;

  @override
  Future<void> saveLeftPanelWidth(double width) async =>
      _leftPanelWidth = width;

  @override
  Future<double?> loadLeftPanelWidth() async => _leftPanelWidth;

  @override
  Future<void> saveRightPanelWidth(double width) async =>
      _rightPanelWidth = width;

  @override
  Future<double?> loadRightPanelWidth() async => _rightPanelWidth;
}
