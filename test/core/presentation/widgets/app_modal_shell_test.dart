import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_quick_item_dialog.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

class _ShellFakePosProvider extends ChangeNotifier implements PosProvider {
  @override
  List<CartItem> get cart => const [];

  @override
  double get wholesaleFactor => 0.9;

  @override
  double get cardFactor => 1.1;

  @override
  double get currentCustomFactor => 1.0;

  @override
  String? get customTierLabel => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ShellFakeCatalogProvider extends ChangeNotifier
    implements CatalogProvider {
  @override
  List<Product> get products => const [];

  @override
  List<Category> get categories => const [];

  @override
  List<Brand> get brands => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ShellFakeSettingsProvider extends ChangeNotifier
    implements SettingsProvider {
  @override
  BusinessSettings? get settings => const BusinessSettings(
        features: FeatureFlags(suppliers: false),
      );

  @override
  FeatureFlags get features => const FeatureFlags(suppliers: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'disable_pusher': true});
  });

  group('Fase A - AppTheme & AppModalShell Design System', () {
    test(
      'AppTheme.light define paleta azul corporativa sin tonos violeta default de Material 3',
      () {
        final theme = AppTheme.light();

        expect(theme.colorScheme.primary, AppColors.primary);
        expect(theme.colorScheme.surfaceTint, Colors.transparent);
        expect(theme.dialogTheme.surfaceTintColor, Colors.transparent);
        expect(theme.dialogTheme.backgroundColor, Colors.white);
        expect(theme.chipTheme.selectedColor, AppColors.primarySoft);
        expect(
          theme.switchTheme.trackColor?.resolve({WidgetState.selected}),
          AppColors.primary,
        );
      },
    );

    testWidgets(
      'AppModalShell renderiza AppModalHeader Dark Navy, topBar, AppSectionCard y footer en desktop y 320x480 sin overflow',
      (tester) async {
        for (final size in const [Size(1366, 768), Size(320, 480)]) {
          await tester.binding.setSurfaceSize(size);

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(),
              home: Scaffold(
                body: AppModalShell(
                  title: 'Ventana Moderna',
                  subtitle: 'Subtítulo descriptivo profesional',
                  icon: Icons.straighten_rounded,
                  accent: AppModalAccent.teal,
                  topBar: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    color: AppColors.surfaceMuted,
                    child: const Text('Barra superior fija'),
                  ),
                  bodyPadding: const EdgeInsets.all(16),
                  body: const AppSectionCard(
                    title: 'Sección Principal',
                    icon: Icons.tune_rounded,
                    child: Text('Contenido de prueba dentro de AppSectionCard'),
                  ),
                  footerLeading: const Text('Total: \$1.500'),
                  footerActions: [
                    TextButton(
                      onPressed: () {},
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () {},
                      child: const Text('Guardar'),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(AppModalHeader), findsOneWidget);
          expect(find.byType(AppModalFooter), findsOneWidget);
          expect(find.byType(AppSectionCard), findsOneWidget);
          expect(find.text('Ventana Moderna'), findsOneWidget);
          expect(find.text('Subtítulo descriptivo profesional'), findsOneWidget);
          expect(find.byTooltip('Cerrar (Esc)'), findsOneWidget);
          expect(find.text('Barra superior fija'), findsOneWidget);
          expect(
            find.text('Contenido de prueba dentro de AppSectionCard'),
            findsOneWidget,
          );
          expect(find.text('Total: \$1.500'), findsOneWidget);
          expect(find.text('Guardar'), findsOneWidget);

          final headerContainer = tester.widget<Container>(
            find
                .descendant(
                  of: find.byType(AppModalHeader),
                  matching: find.byType(Container),
                )
                .first,
          );
          final decoration = headerContainer.decoration as BoxDecoration;
          final gradient = decoration.gradient as LinearGradient;
          expect(gradient.colors, [AppColors.navyStart, AppColors.navyEnd]);

          expect(tester.takeException(), isNull);
        }

        addTearDown(() => tester.binding.setSurfaceSize(null));
      },
    );

    testWidgets(
      'AppModalShell con useAlertDialogWrapper preserva find.byType(AlertDialog)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1024, 768));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: AppModalShell(
                title: 'Formulario Compatible',
                icon: Icons.inventory_2_outlined,
                useAlertDialogWrapper: true,
                body: Text('Contenido compatible'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byType(AppModalHeader), findsOneWidget);
        expect(find.text('Formulario Compatible'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'AppConfirmDialog.show renderiza Nivel 3 compacto blanco y resuelve true / false al presionar acciones',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1024, 768));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        bool? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () async {
                    result = await AppConfirmDialog.show(
                      ctx,
                      title: 'Eliminar Producto',
                      message: 'Esta acción eliminará el artículo del catálogo.',
                      confirmLabel: 'Eliminar',
                      isDestructive: true,
                    );
                  },
                  child: const Text('Abrir Confirmación'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir Confirmación'));
        await tester.pumpAndSettle();

        expect(find.byType(AppConfirmDialog), findsOneWidget);
        expect(find.byType(AppModalHeader), findsNothing);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Eliminar Producto'), findsOneWidget);

        await tester.tap(find.text('Eliminar'));
        await tester.pumpAndSettle();
        expect(result, isTrue);

        await tester.tap(find.text('Abrir Confirmación'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(result, isFalse);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PosQuickItemDialog usa AppModalShell + AppModalHeader, transiciona modos y soporta 320x480 sin overflow',
      (tester) async {
        for (final viewport in const [Size(1280, 900), Size(320, 480)]) {
          await tester.binding.setSurfaceSize(viewport);

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<PosProvider>.value(
                  value: _ShellFakePosProvider(),
                ),
                ChangeNotifierProvider<CatalogProvider>.value(
                  value: _ShellFakeCatalogProvider(),
                ),
                ChangeNotifierProvider<SettingsProvider>.value(
                  value: _ShellFakeSettingsProvider(),
                ),
              ],
              child: MaterialApp(
                theme: AppTheme.light(),
                home: const Scaffold(
                  body: PosQuickItemDialog(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(AppModalShell), findsOneWidget);
          expect(find.byType(AppModalHeader), findsOneWidget);
          expect(find.byKey(const ValueKey('title_product')), findsOneWidget);
          expect(find.text('SUBTOTAL LÍNEA'), findsOneWidget);

          await tester.tap(find.text('Servicio / Honorario'));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('title_service')), findsOneWidget);

          await tester.tap(find.text('Combo / Fracción'));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('title_combo')), findsOneWidget);

          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }

        addTearDown(() => tester.binding.setSurfaceSize(null));
      },
    );
  });
}
