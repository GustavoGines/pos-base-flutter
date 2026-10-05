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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeLocalTerminalProvider extends ChangeNotifier implements LocalTerminalProvider {
  @override
  String get printerFormat => 'thermal_80';
  @override
  String get printerConnection => 'none';
  @override
  String get pdfPaperSize => 'a4';

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

    testWidgets('Renders fallback Icon(Icons.point_of_sale_rounded) when effectiveLogoUrl is null', (tester) async {
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

      // No Image.network is rendered
      expect(find.byType(Image), findsNothing);

      // Fallback icon is rendered in the header
      expect(find.byIcon(Icons.point_of_sale_rounded), findsOneWidget);
      expect(find.text('Negocio Sin Logo'), findsOneWidget);
    });

    testWidgets('Renders fallback icon when logoUrl is empty or malformed without host', (tester) async {
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

      // Does NOT crash with ArgumentError; renders fallback icon
      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.point_of_sale_rounded), findsOneWidget);
    });

    testWidgets('Image.network errorBuilder renders fallback Icon(Icons.point_of_sale_rounded)', (tester) async {
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

      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);

      final imageWidget = tester.widget<Image>(imageFinder);
      expect(imageWidget.errorBuilder, isNotNull);

      // Exercise errorBuilder directly to verify fallback icon widget structure
      final errorResult = imageWidget.errorBuilder!(tester.element(imageFinder), Exception('HTTP 404'), null);
      expect(errorResult, isA<Icon>());
      final iconResult = errorResult as Icon;
      expect(iconResult.icon, Icons.point_of_sale_rounded);
      expect(iconResult.size, 26.0);
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
  });
}
