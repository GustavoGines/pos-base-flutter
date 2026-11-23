import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

// --- FAKE PROVIDERS FOR GLOBAL APP BAR TESTING ---
class FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings? _settings;

  FakeSettingsProvider({BusinessSettings? settings}) : _settings = settings;

  @override
  BusinessSettings? get settings => _settings;
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;
  @override
  String get currentPlan => _settings?.licensePlanType ?? 'basic';
  @override
  FeatureFlags get features => _settings?.features ?? const FeatureFlags(fastPos: true);
  @override
  bool hasFeature(String featureName) => _settings?.hasFeature(featureName) ?? false;
  @override
  bool get isLicenseActive => true;
  @override
  List<String> get allowedAddons => _settings?.licenseFeatures ?? [];
  @override
  int get assignedRegisterId => 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeLocalTerminalProvider extends ChangeNotifier implements LocalTerminalProvider {
  @override
  bool get autoOpenCashDrawer => false;
  @override
  String get printerFormat => 'thermal_80';
  @override
  String get printerConnection => 'none';
  @override
  String get pdfPaperSize => 'a4';
  @override
  String get scaleComPort => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  Map<String, dynamic>? get currentUser => {'id': 1, 'name': 'Admin Test', 'role': 'admin'};
  @override
  bool get isAdmin => true;
  @override
  bool hasPermission(String permission) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeInventoryAlertsProvider extends ChangeNotifier implements InventoryAlertsProvider {
  @override
  List<dynamic> get alerts => [];
  @override
  int get totalAlertsCount => 0;
  @override
  List<dynamic> get reactiveAlerts => [];
  @override
  List<dynamic> get predictiveCriticalAlerts => [];

  @override
  Future<void> fetchAlerts({int threshold = 3}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget buildTestAppBar({
  required FakeSettingsProvider settingsProv,
  String currentRoute = '/pos',
  String title = 'Sistema POS',
  bool showBackButton = false,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
      ChangeNotifierProvider<LocalTerminalProvider>.value(value: FakeLocalTerminalProvider()),
      ChangeNotifierProvider<AuthProvider>.value(value: FakeAuthProvider()),
      ChangeNotifierProvider<InventoryAlertsProvider>.value(value: FakeInventoryAlertsProvider()),
    ],
    child: MaterialApp(
      home: Scaffold(
        appBar: GlobalAppBar(
          currentRoute: currentRoute,
          title: title,
          showBackButton: showBackButton,
        ),
        body: const Center(child: Text('Content')),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GlobalAppBar Business Logo Widget Tests', () {
    testWidgets('Renders Image.network when SettingsProvider provides a valid effectiveLogoUrl', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const validLogoUrl = 'http://pos-backend.test/storage/business/logo_header.png';
      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          companyName: 'Supermercado Central',
          logoUrl: validLogoUrl,
        ),
      );

      await tester.pumpWidget(buildTestAppBar(settingsProv: settingsProv));
      await tester.pump();

      // Look for Image.network widget
      final imageFinder = find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is NetworkImage && (widget.image as NetworkImage).url == validLogoUrl,
      );
      expect(imageFinder, findsOneWidget);

      // Verify dimensions: 26x26
      final imageWidget = tester.widget<Image>(imageFinder);
      expect(imageWidget.width, 26.0);
      expect(imageWidget.height, 26.0);

      // Company name is displayed
      expect(find.text('Supermercado Central'), findsOneWidget);
    });

    testWidgets('Renders fallback Image.asset(assets/app_logo.png) when effectiveLogoUrl is null', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          companyName: 'Negocio Sin Logo',
          logoUrl: null,
          logoPath: null,
        ),
      );

      await tester.pumpWidget(buildTestAppBar(settingsProv: settingsProv));
      await tester.pump();

      // No Image.network is rendered; fallback asset logo is rendered in the header
      expect(
        find.byWidgetPredicate((w) => w is Image && w.image is NetworkImage),
        findsNothing,
      );
      final assetLogoFinder = find.byWidgetPredicate(
        (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == 'assets/app_logo.png',
      );
      expect(assetLogoFinder, findsOneWidget);
      expect(find.text('Negocio Sin Logo'), findsOneWidget);
    });

    testWidgets('Renders fallback asset logo when logoUrl is empty or malformed without host', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          companyName: 'Negocio URL Inválida',
          logoUrl: 'http://',
        ),
      );

      await tester.pumpWidget(buildTestAppBar(settingsProv: settingsProv));
      await tester.pump();

      // Does NOT crash with ArgumentError; renders fallback asset logo
      expect(tester.takeException(), isNull);
      expect(
        find.byWidgetPredicate((w) => w is Image && w.image is NetworkImage),
        findsNothing,
      );
      final assetLogoFinder = find.byWidgetPredicate(
        (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == 'assets/app_logo.png',
      );
      expect(assetLogoFinder, findsOneWidget);
    });

    testWidgets('Image.network errorBuilder renders fallback Image.asset(assets/app_logo.png)', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const brokenLogoUrl = 'http://pos-backend.test/storage/business/broken.png';
      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          companyName: 'Comercio Broken Image',
          logoUrl: brokenLogoUrl,
        ),
      );

      await tester.pumpWidget(buildTestAppBar(settingsProv: settingsProv));
      await tester.pump();

      final networkImageFinder = find.byWidgetPredicate(
        (w) => w is Image && w.image is NetworkImage && (w.image as NetworkImage).url == brokenLogoUrl,
      );
      expect(networkImageFinder, findsOneWidget);

      final imageWidget = tester.widget<Image>(networkImageFinder);
      expect(imageWidget.errorBuilder, isNotNull);

      // Exercise errorBuilder directly to verify fallback asset logo widget structure
      final errorResult = imageWidget.errorBuilder!(tester.element(networkImageFinder), Exception('HTTP 404'), null);
      expect(errorResult, isA<ClipRRect>());
      final clipResult = errorResult as ClipRRect;
      expect(clipResult.child, isA<Image>());
      final fallbackImage = clipResult.child as Image;
      expect(fallbackImage.image, isA<AssetImage>());
      expect((fallbackImage.image as AssetImage).assetName, 'assets/app_logo.png');
      expect(fallbackImage.width, 26.0);
      expect(fallbackImage.height, 26.0);
    });

    testWidgets('Back button renders when showBackButton is true and triggers maybePop', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(companyName: 'Test Empresa'),
      );

      await tester.pumpWidget(buildTestAppBar(settingsProv: settingsProv, showBackButton: true));
      await tester.pump();

      final backButton = find.byTooltip('Volver');
      expect(backButton, findsOneWidget);

      await tester.tap(backButton);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Responsive stress: Narrow screen (380x600) renders cleanly with zero overflow', (tester) async {
      tester.view.physicalSize = const Size(380, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          companyName: 'Empresa Nombre Largo',
          logoUrl: 'http://pos-backend.test/storage/business/logo.png',
        ),
      );

      await tester.pumpWidget(buildTestAppBar(settingsProv: settingsProv, showBackButton: true));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('Uses Caja4U dark navy background (#121C33) and renders contextual breadcrumb on wide screens', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(companyName: 'Dev4U'),
      );

      await tester.pumpWidget(
        buildTestAppBar(
          settingsProv: settingsProv,
          currentRoute: '/settings',
          title: 'Configuración del Sistema',
          showBackButton: true,
        ),
      );
      await tester.pump();

      final appBarMaterialFinder = find.descendant(
        of: find.byType(GlobalAppBar),
        matching: find.byWidgetPredicate(
          (w) => w is Material && w.color == const Color(0xFF121C33),
        ),
      );
      expect(appBarMaterialFinder, findsOneWidget);
      expect(find.text('Dev4U'), findsOneWidget);
      expect(find.text('Configuración del Sistema'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('SharedUserMenu omite cabecera redundante en escritorio (1280x800) y la muestra en vista compacta (380x600)', (tester) async {
      // 1. Escritorio (1280x800): nombre visible en la barra, sin repetir en el dropdown
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(companyName: 'Dev4U'),
      );

      await tester.pumpWidget(buildTestAppBar(settingsProv: settingsProv));
      await tester.pump();

      await tester.tap(find.text('Admin Test'));
      await tester.pumpAndSettle();

      expect(find.text('Personal y Accesos'), findsOneWidget);
      expect(find.text('SESIÓN ACTIVA'), findsNothing);
      expect(find.text('Admin Test'), findsOneWidget); // Solo en el botón de la barra

      // Cerrar menú
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // 2. Vista compacta (380x600): botón solo con ícono -> muestra cabecera dentro del dropdown
      tester.view.physicalSize = const Size(380, 600);
      await tester.pumpWidget(buildTestAppBar(settingsProv: settingsProv));
      await tester.pump();

      expect(find.text('Admin Test'), findsNothing);
      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();

      expect(find.text('Personal y Accesos'), findsOneWidget);
      expect(find.text('Admin Test'), findsOneWidget);
      expect(find.text('SESIÓN ACTIVA'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Desplegables de navegación y usuario usan estilo Dark Navy cohesivo (#16233F) y destacan ruta activa',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final settingsProv = FakeSettingsProvider(
          settings: const BusinessSettings(
            companyName: 'Dev4U',
            features: FeatureFlags(
              fastPos: true,
              quotes: true,
              suppliers: true,
            ),
          ),
        );

        await tester.pumpWidget(
          buildTestAppBar(
            settingsProv: settingsProv,
            currentRoute: '/catalog',
            title: 'Catálogo de Productos',
          ),
        );
        await tester.pump();

        // 1. Validar PopupMenuButton de SharedUserMenu con fondo Dark Navy
        final popupBtn = tester.widget<PopupMenuButton<String>>(
          find.byType(PopupMenuButton<String>),
        );
        expect(popupBtn.color, const Color(0xFF16233F));

        // 2. Abrir desplegable "Gestión" y validar estilo Dark Navy + ruta activa
        await tester.tap(find.text('Gestión'));
        await tester.pumpAndSettle();

        final gestionAnchor = tester.widget<MenuAnchor>(
          find.byWidgetPredicate(
            (w) =>
                w is MenuAnchor &&
                w.style?.backgroundColor?.resolve({}) ==
                    GlobalAppBar.kNavDropdownBg,
          ).first,
        );
        expect(
          gestionAnchor.style?.backgroundColor?.resolve({}),
          const Color(0xFF16233F),
        );

        expect(find.text('Registro de Ventas'), findsOneWidget);
        expect(find.text('Presupuestos'), findsOneWidget);
        expect(find.text('Catálogo de Productos'), findsWidgets);
        expect(find.text('Proveedores'), findsOneWidget);

        // El ítem de la ruta activa (/catalog) resalta en kBrandMint y negrita
        final catalogMenuText = tester.widget<Text>(
          find.descendant(
            of: find.byType(MenuItemButton),
            matching: find.text('Catálogo de Productos'),
          ),
        );
        expect(catalogMenuText.style?.color, GlobalAppBar.kBrandMint);
        expect(catalogMenuText.style?.fontWeight, FontWeight.w700);

        final salesMenuText = tester.widget<Text>(
          find.descendant(
            of: find.byType(MenuItemButton),
            matching: find.text('Registro de Ventas'),
          ),
        );
        expect(salesMenuText.style?.color, const Color(0xFFF1F5F9));
        expect(salesMenuText.style?.fontWeight, FontWeight.w500);

        // Cerrar menú Gestión y abrir SharedUserMenu para validar color de ítem
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Admin Test'));
        await tester.pumpAndSettle();

        final userMenuText = tester.widget<Text>(
          find.text('Personal y Accesos'),
        );
        expect(userMenuText.style?.color, const Color(0xFFF1F5F9));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Rutas principales del menú central NUNCA muestran breadcrumb duplicado al lado de la empresa y sí muestran sub-etiqueta activa',
      (tester) async {
        tester.view.physicalSize = const Size(1366, 768);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final settingsProv = FakeSettingsProvider(
          settings: const BusinessSettings(
            companyName: 'Dev4U',
            features: FeatureFlags(
              fastPos: true,
              quotes: true,
              suppliers: true,
              checks: true,
              expenses: true,
              currentAccounts: true,
              advancedReports: true,
              logistics: true,
            ),
          ),
        );

        final cases = <(String, String, String?)>[
          ('/pos', 'Terminal POS', null),
          ('/sales-history', 'Registro de Ventas', '• Ventas'),
          ('/quotes', 'Historial de Presupuestos', '• Presupuestos'),
          ('/catalog', 'Catálogo de Productos', '• Catálogo'),
          ('/suppliers', 'Gestión de Proveedores', '• Proveedores'),
          ('/cash-movements', 'Gastos y Mov. de Caja', '• Gastos'),
          ('/cuentas-corrientes', 'Cuentas Corrientes', '• Ctas. Ctes.'),
          ('/checks', 'Cartera de Cheques', '• Cheques'),
          ('/reports', 'Reportes Gerenciales', '• Reportes'),
          ('/delivery-notes', 'Dashboard Logístico', '• Logística'),
        ];

        for (final (route, redundantTitle, expectedSubLabel) in cases) {
          await tester.pumpWidget(
            buildTestAppBar(
              settingsProv: settingsProv,
              currentRoute: route,
              title: redundantTitle,
            ),
          );
          await tester.pump();

          expect(find.text('Dev4U'), findsOneWidget, reason: 'route=$route');
          expect(
            find.byIcon(Icons.chevron_right_rounded),
            findsNothing,
            reason: 'No debe haber breadcrumb junto a la empresa en $route',
          );
          if (expectedSubLabel != null) {
            expect(
              find.text(expectedSubLabel),
              findsOneWidget,
              reason: 'Debe mostrar $expectedSubLabel en barra central para $route',
            );
          }
          expect(tester.takeException(), isNull, reason: 'Sin overflow en $route');
        }
      },
    );

    testWidgets(
      'Pantallas secundarias (menú de usuario y sub-flujos) SÍ muestran breadcrumb con Tooltip sin overflow',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final settingsProv = FakeSettingsProvider(
          settings: const BusinessSettings(
            companyName: 'Dev4U',
            features: FeatureFlags(
              fastPos: true,
              quotes: true,
              suppliers: true,
              checks: true,
              logistics: true,
            ),
          ),
        );

        final secondaryCases = <(String, String)>[
          ('/settings', 'Configuración'),
          ('/settings/registers', 'Cajas Físicas'),
          ('/users', 'Personal y Permisos'),
          ('/general-audit', 'Auditoría General'),
          ('/trash', 'Papelera'),
          ('/quotes/new', 'Nuevo Presupuesto'),
          ('/suppliers/account', 'Cta. Cte.: Distribuidora Central'),
        ];

        for (final (route, breadcrumbTitle) in secondaryCases) {
          await tester.pumpWidget(
            buildTestAppBar(
              settingsProv: settingsProv,
              currentRoute: route,
              title: breadcrumbTitle,
              showBackButton: true,
            ),
          );
          await tester.pump();

          expect(find.text('Dev4U'), findsOneWidget, reason: 'route=$route');
          expect(
            find.byIcon(Icons.chevron_right_rounded),
            findsOneWidget,
            reason: 'Debe mostrar chevron breadcrumb en $route',
          );
          expect(
            find.text(breadcrumbTitle),
            findsOneWidget,
            reason: 'Debe mostrar "$breadcrumbTitle" en $route',
          );
          expect(
            find.byTooltip(breadcrumbTitle),
            findsOneWidget,
            reason: 'Debe incluir Tooltip con título completo en $route',
          );
          expect(tester.takeException(), isNull, reason: 'Sin overflow en $route');
        }
      },
    );
  });
}
