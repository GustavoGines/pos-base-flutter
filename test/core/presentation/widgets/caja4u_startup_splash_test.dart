import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/core/presentation/widgets/caja4u_startup_splash.dart';
import 'package:frontend_desktop/features/auth/presentation/pages/login_screen.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/main.dart' show FadePageRouteTransitionsBuilder;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Monta el splash dentro de un host mínimo que permite cambiar `isReady`
/// y retirarlo al terminar, igual que hace `AppBootstrap` en producción.
class _SplashHost extends StatefulWidget {
  const _SplashHost({
    required this.initiallyReady,
    required this.onDismissed,
    this.assetPath = Caja4uStartupSplash.animatedAsset,
    this.minDisplayDuration = Caja4uStartupSplash.defaultMinDisplayDuration,
  });

  final bool initiallyReady;
  final VoidCallback onDismissed;
  final String assetPath;
  final Duration minDisplayDuration;

  @override
  State<_SplashHost> createState() => _SplashHostState();
}

class _SplashHostState extends State<_SplashHost> {
  late bool ready = widget.initiallyReady;
  bool dismissed = false;

  void markReady() => setState(() => ready = true);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(
            key: ValueKey('underlying_app'),
            color: Colors.white,
          ),
          if (!dismissed)
            Caja4uStartupSplash(
              isReady: ready,
              assetPath: widget.assetPath,
              minDisplayDuration: widget.minDisplayDuration,
              onDismissed: () {
                widget.onDismissed();
                setState(() => dismissed = true);
              },
            ),
        ],
      ),
    );
  }
}

const Duration _min = Caja4uStartupSplash.defaultMinDisplayDuration;
const Duration _fade = Caja4uStartupSplash.defaultFadeOutDuration;
final Finder _splash = find.byType(Caja4uStartupSplash);
final Finder _waiting = find.byKey(const ValueKey('caja4u_splash_waiting'));

Future<void> _setSurface(WidgetTester tester, Size logicalSize) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = logicalSize;
  addTearDown(tester.view.reset);
}

void main() {
  group('Caja4uStartupSplash · ciclo de vida', () {
    testWidgets('no se retira antes del tiempo mínimo aunque el sistema ya esté listo',
        (tester) async {
      int dismissCount = 0;
      await tester.pumpWidget(
        _SplashHost(initiallyReady: true, onDismissed: () => dismissCount++),
      );

      await tester.pump(_min - const Duration(milliseconds: 100));
      expect(_splash, findsOneWidget);
      expect(dismissCount, 0);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(_fade + const Duration(milliseconds: 50));
      expect(_splash, findsNothing);
      expect(dismissCount, 1);
    });

    testWidgets('si el sistema sigue cargando, espera y muestra el indicador de conexión',
        (tester) async {
      int dismissCount = 0;
      await tester.pumpWidget(
        _SplashHost(initiallyReady: false, onDismissed: () => dismissCount++),
      );

      expect(_waiting, findsNothing);
      await tester.pump(_min);
      await tester.pump(const Duration(seconds: 5));
      expect(_splash, findsOneWidget, reason: 'No debe retirarse sin la señal de listo');
      expect(_waiting, findsOneWidget);
      expect(find.text('Conectando con el servidor...'), findsOneWidget);

      tester.state<_SplashHostState>(find.byType(_SplashHost)).markReady();
      await tester.pump();
      await tester.pump(_fade + const Duration(milliseconds: 50));
      expect(_splash, findsNothing);
      expect(dismissCount, 1);
    });

    testWidgets('un clic/toque la salta de inmediato, aunque el sistema no esté listo',
        (tester) async {
      int dismissCount = 0;
      await tester.pumpWidget(
        _SplashHost(initiallyReady: false, onDismissed: () => dismissCount++),
      );
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.byKey(const ValueKey('caja4u_splash_tap_area')));
      await tester.pump();
      await tester.pump(_fade + const Duration(milliseconds: 50));

      expect(_splash, findsNothing);
      expect(dismissCount, 1);
    });

    testWidgets('una tecla la salta y la tecla no llega a la pantalla de abajo',
        (tester) async {
      int dismissCount = 0;
      await tester.pumpWidget(
        _SplashHost(initiallyReady: false, onDismissed: () => dismissCount++),
      );
      await tester.pump(const Duration(milliseconds: 500));

      final bool handled = await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(_fade + const Duration(milliseconds: 50));

      expect(handled, isTrue, reason: 'El splash debe consumir la tecla');
      expect(_splash, findsNothing);
      expect(dismissCount, 1);
    });

    testWidgets('después de retirarse ya no intercepta el teclado', (tester) async {
      await tester.pumpWidget(_SplashHost(initiallyReady: true, onDismissed: () {}));
      await tester.pump(_min);
      await tester.pump(_fade + const Duration(milliseconds: 50));
      expect(_splash, findsNothing);

      final bool handled = await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(handled, isFalse);
    });

    testWidgets('múltiples saltos (doble clic + tecla) notifican una sola vez',
        (tester) async {
      int dismissCount = 0;
      await tester.pumpWidget(
        _SplashHost(initiallyReady: true, onDismissed: () => dismissCount++),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final tapArea = find.byKey(const ValueKey('caja4u_splash_tap_area'));
      await tester.tap(tapArea);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(tapArea, warnIfMissed: false);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump(_min + _fade);

      expect(dismissCount, 1);
    });

    testWidgets('la indicación para saltar aparece tras la demora configurada',
        (tester) async {
      await tester.pumpWidget(_SplashHost(initiallyReady: false, onDismissed: () {}));
      final hint = find.byKey(const ValueKey('caja4u_splash_skip_hint'));

      double hintOpacity() => tester
          .widget<AnimatedOpacity>(
              find.ancestor(of: hint, matching: find.byType(AnimatedOpacity)).first)
          .opacity;

      expect(hintOpacity(), 0);
      await tester.pump(Caja4uStartupSplash.skipHintDelay);
      expect(hintOpacity(), 1);
    });
  });

  group('Caja4uStartupSplash · diseño responsivo (sin overflow)', () {
    const surfaces = <String, Size>{
      'Celular chico 320x568': Size(320, 568),
      'Celular 360x800': Size(360, 800),
      'Celular apaisado 800x360': Size(800, 360),
      'Tablet 800x1280': Size(800, 1280),
      'Ventana mínima Windows 1000x700': Size(1000, 700),
      'Ventana inicial Windows 1280x720': Size(1280, 720),
      'Full HD 1920x1080': Size(1920, 1080),
      '4K 3840x2160': Size(3840, 2160),
    };

    for (final entry in surfaces.entries) {
      testWidgets(entry.key, (tester) async {
        await _setSurface(tester, entry.value);
        await tester.pumpWidget(_SplashHost(initiallyReady: false, onDismissed: () {}));
        // Recorremos todos los estados visuales: inicio, indicación y espera de red.
        await tester.pump(Caja4uStartupSplash.skipHintDelay);
        await tester.pump(_min);
        await tester.pump(const Duration(milliseconds: 400));

        expect(tester.takeException(), isNull);
        expect(_waiting, findsOneWidget);

        final logoSize = tester.getSize(
          find.byKey(const ValueKey('caja4u_splash_animation')),
        );
        expect(logoSize.width, logoSize.height, reason: 'El logo debe ser cuadrado');
        expect(logoSize.width, inInclusiveRange(160.0, 520.0));
        expect(logoSize.width, lessThanOrEqualTo(entry.value.shortestSide));
      });
    }
  });

  group('Caja4uStartupSplash · tolerancia a fallos', () {
    testWidgets('si falta la animación usa el logo estático sin romper el arranque',
        (tester) async {
      await tester.pumpWidget(_SplashHost(
        initiallyReady: false,
        onDismissed: () {},
        assetPath: 'assets/no_existe_splash.webp',
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('caja4u_splash_fallback')), findsOneWidget);
    });
  });

  group('Recursos de la pantalla de inicio', () {
    test('el WebP animado existe, es válido, se reproduce una sola vez y pesa < 1,5 MB',
        () {
      final file = File('assets/splash_caja4u.webp');
      expect(file.existsSync(), isTrue);

      final Uint8List bytes = file.readAsBytesSync();
      expect(bytes.length, lessThan(1500 * 1024));
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WEBP');

      final String header = String.fromCharCodes(bytes.sublist(0, 64));
      expect(header.contains('VP8X'), isTrue, reason: 'Debe ser WebP extendido');

      final int animIndex = _indexOf(bytes, 'ANIM'.codeUnits);
      expect(animIndex, greaterThan(0), reason: 'Debe ser un WebP ANIMADO');
      // Chunk ANIM: tamaño (4) + color de fondo (4) + loop count (2, little endian).
      final int loopOffset = animIndex + 4 + 4 + 4;
      final int loopCount = bytes[loopOffset] | (bytes[loopOffset + 1] << 8);
      expect(loopCount, 1, reason: '1 = se reproduce una vez y queda en el último cuadro');
    });

    test('el WebP está incluido en el bundle de assets', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final data = await rootBundle.load(Caja4uStartupSplash.animatedAsset);
      expect(data.lengthInBytes, greaterThan(100 * 1024));
      final fallback = await rootBundle.load(Caja4uStartupSplash.fallbackAsset);
      expect(fallback.lengthInBytes, greaterThan(0));
    });

    testWidgets('el motor de Flutter lo decodifica: ~4 s a 24 fps, 640x640, sin repetir',
        (tester) async {
      await tester.runAsync(() async {
        final bytes = File('assets/splash_caja4u.webp').readAsBytesSync();
        final codec = await ui.instantiateImageCodec(bytes);
        addTearDown(codec.dispose);

        expect(codec.frameCount, inInclusiveRange(90, 100));
        expect(codec.repetitionCount, 0, reason: '0 repeticiones = se reproduce una vez');

        final first = await codec.getNextFrame();
        expect(first.image.width, 640);
        expect(first.image.height, 640);
        expect(first.duration.inMilliseconds, inInclusiveRange(40, 43));
        first.image.dispose();
      });
    });

    test('Android: splash nativo con color de marca en todas las variantes de tema', () {
      const res = 'android/app/src/main/res';
      final colors = File('$res/values/colors.xml').readAsStringSync();
      expect(colors, contains('<color name="caja4u_splash_background">#121C33</color>'));
      expect(File('$res/drawable-xxhdpi/splash_icon.png').existsSync(), isTrue);

      for (final dir in ['drawable', 'drawable-v21']) {
        final xml = File('$res/$dir/launch_background.xml').readAsStringSync();
        expect(xml, contains('@color/caja4u_splash_background'), reason: dir);
        expect(xml, contains('@drawable/splash_icon'), reason: dir);
      }

      for (final dir in ['values', 'values-night', 'values-v31', 'values-night-v31']) {
        final xml = File('$res/$dir/styles.xml').readAsStringSync();
        expect(xml, contains('name="LaunchTheme"'), reason: dir);
        expect(xml, contains('name="NormalTheme"'), reason: dir);
        expect(xml, isNot(contains('?android:colorBackground')),
            reason: '$dir: evita el destello blanco/negro entre splash nativo y Flutter');
      }

      for (final dir in ['values-v31', 'values-night-v31']) {
        final xml = File('$res/$dir/styles.xml').readAsStringSync();
        expect(xml, contains('android:windowSplashScreenBackground'), reason: dir);
        expect(xml, contains('android:windowSplashScreenAnimatedIcon'), reason: dir);
      }
    });
  });

  group('Integración Splash -> LoginScreen (fondo, logo y transición)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PackageInfo.setMockInitialValues(
        appName: 'Caja4U',
        packageName: 'com.dev4u.caja4u',
        version: '2.1.0',
        buildNumber: '1',
        buildSignature: '',
      );
      Caja4uStartupSplash.isOverlayActiveNotifier.value = false;
    });

    tearDown(() {
      Caja4uStartupSplash.isOverlayActiveNotifier.value = false;
    });

    Widget wrapWithLoginProviders(Widget child) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuthProvider()),
          ChangeNotifierProvider<SettingsProvider>(create: (_) => _FakeSettingsProvider()),
          ChangeNotifierProvider<CashRegisterProvider>(
              create: (_) => _FakeCashRegisterProvider()),
        ],
        child: child,
      );
    }

    testWidgets('LoginScreen conserva el logo Caja4U y coincide con el fondo del splash (#121C33)',
        (tester) async {
      await _setSurface(tester, const Size(1280, 800));
      await tester.pumpWidget(
        wrapWithLoginProviders(const MaterialApp(home: LoginScreen())),
      );
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, Caja4uStartupSplash.backgroundColor);

      final logoFinder = find.byWidgetPredicate(
        (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == 'assets/caja4u_logo_full.png',
      );
      expect(logoFinder, findsOneWidget);
    });

    testWidgets(
        'la transición coreografiada del Login espera al splash: el logo viaja arriba y el login se abre recién al terminar',
        (tester) async {
      await _setSurface(tester, const Size(1280, 900));
      final authProv = _FakeAuthProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<SettingsProvider>(create: (_) => _FakeSettingsProvider()),
            ChangeNotifierProvider<CashRegisterProvider>(
                create: (_) => _FakeCashRegisterProvider()),
          ],
          child: const _SplashToLoginHost(),
        ),
      );

      Finder loginLogoFinder() => find.descendant(
            of: find.byType(LoginScreen),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Image &&
                  w.image is AssetImage &&
                  (w.image as AssetImage).assetName == 'assets/caja4u_logo_full.png',
            ),
          );

      Finder keypadOpacityFinder() => find.ancestor(
            of: find.text('Ingreso al sistema'),
            matching: find.byType(Opacity),
          );

      // 1. Mientras el splash está cubriendo la pantalla, LoginScreen queda en estado inicial (t=0):
      //    logo abajo/centrado y teclado oculto (opacity == 0).
      await tester.pump(const Duration(seconds: 2));
      expect(_splash, findsOneWidget);
      final double logoStartY = tester.getTopLeft(loginLogoFinder()).dy;
      expect(tester.widget<Opacity>(keypadOpacityFinder().first).opacity, 0.0);

      // 2. Presionar una tecla numérica salta el splash pero NO escribe el dígito en el PIN.
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.pump();
      expect(authProv.verifyCalls, 0);

      // 3. Termina el fade-out del splash: recién ahora arranca el viaje del logo hacia arriba.
      await tester.pump(_fade + const Duration(milliseconds: 20));
      expect(_splash, findsNothing);

      // A mitad de la transición (410ms), el logo ya se desplazó hacia arriba respecto a logoStartY.
      await tester.pump(const Duration(milliseconds: 410));
      final double logoMidY = tester.getTopLeft(loginLogoFinder()).dy;
      expect(logoMidY, lessThan(logoStartY));

      // Al finalizar la transición (820ms+), el logo quedó arriba y el teclado quedó visible.
      await tester.pump(const Duration(milliseconds: 500));
      final double logoEndY = tester.getTopLeft(loginLogoFinder()).dy;
      expect(logoEndY, lessThan(logoMidY));
      expect(tester.widget<Opacity>(keypadOpacityFinder().first).opacity, 1.0);
    });

    for (final surface in const [Size(360, 800), Size(1280, 720), Size(1920, 1080)]) {
      testWidgets(
          'paridad exacta de posición y tamaño al empalmar splash -> login en ${surface.width.toInt()}x${surface.height.toInt()}',
          (tester) async {
        await _setSurface(tester, surface);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuthProvider()),
              ChangeNotifierProvider<SettingsProvider>(create: (_) => _FakeSettingsProvider()),
              ChangeNotifierProvider<CashRegisterProvider>(
                  create: (_) => _FakeCashRegisterProvider()),
            ],
            child: const _SplashToLoginHost(),
          ),
        );
        await tester.pump();
        await tester.pump();

        final splashRect = tester.getRect(
          find.byKey(const ValueKey('caja4u_splash_animation')),
        );
        final loginLogoFinder = find.descendant(
          of: find.byType(LoginScreen),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Image &&
                w.image is AssetImage &&
                (w.image as AssetImage).assetName == 'assets/caja4u_logo_full.png',
          ),
        );
        final loginStartRect = tester.getRect(loginLogoFinder);

        // El centro de ambos logos coincide al píxel en el centro de la pantalla.
        expect(splashRect.center.dx, closeTo(surface.width / 2, 1.0));
        expect(splashRect.center.dy, closeTo(surface.height / 2, 1.0));
        expect(loginStartRect.center.dx, closeTo(splashRect.center.dx, 1.5));
        expect(loginStartRect.center.dy, closeTo(splashRect.center.dy, 1.5));

        // El tamaño visual de la marca en el Login al empezar coincide al píxel con el del splash.
        final double expectedStartWidth = 184.0 * (splashRect.width * 0.0041885);
        expect(loginStartRect.width, closeTo(expectedStartWidth, 1.0));

        // Al terminar el splash y correr la transición del Login, se acomoda a 184x156 en la tarjeta.
        await tester.pump(_min);
        await tester.pump(_fade + const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 900));
        final loginEndRect = tester.getRect(loginLogoFinder);
        expect(loginEndRect.width, closeTo(184.0, 0.5));
        expect(loginEndRect.height, closeTo(156.0, 0.5));
        expect(loginEndRect.center.dy, lessThan(loginStartRect.center.dy));
      });
    }
  });

  group('Pulido profesional · by Dev4U completo, PIN fluido y transición de rutas', () {
    testWidgets(
        'defaultMinDisplayDuration cubre by Dev4U (>=4.4s) y reinicia conteo al pintar Frame 0',
        (tester) async {
      expect(
        Caja4uStartupSplash.defaultMinDisplayDuration.inMilliseconds,
        greaterThanOrEqualTo(4400),
      );

      int dismissCount = 0;
      const customMin = Duration(milliseconds: 300);

      await tester.pumpWidget(
        _SplashHost(
          initiallyReady: true,
          minDisplayDuration: customMin,
          onDismissed: () => dismissCount++,
        ),
      );

      // Avanza 220ms antes de que termine de decodificarse el primer frame real.
      await tester.pump(const Duration(milliseconds: 220));
      expect(dismissCount, 0);

      // Espera decodificación real del WebP hasta que Image.asset pinte el primer RawImage.
      bool firstFramePainted = false;
      for (int i = 0; i < 40; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 10));
        if (find.byType(RawImage).evaluate().isNotEmpty) {
          firstFramePainted = true;
          break;
        }
      }
      expect(firstFramePainted, isTrue);

      // Desde el primer frame pintado, avanzamos 200ms (el total desde mount ya superó 420ms > 300ms):
      // como el temporizador se sincronizó al Frame 0, el splash sigue visible.
      await tester.pump(const Duration(milliseconds: 200));
      expect(dismissCount, 0);
      expect(_splash, findsOneWidget);

      // Completados los 300ms desde Frame 0 + fade-out, el splash se retira limpiamente.
      await tester.pump(const Duration(milliseconds: 120) + _fade);
      expect(dismissCount, 1);
      expect(_splash, findsNothing);
    });

    testWidgets(
        'LoginScreen conserva los 4 puntos durante validación, marca verde al aceptar y navega a /home',
        (tester) async {
      await _setSurface(tester, const Size(1280, 800));
      SharedPreferences.setMockInitialValues({});
      PackageInfo.setMockInitialValues(
        appName: 'Caja4U',
        packageName: 'com.caja4u',
        version: '2.1.0',
        buildNumber: '1',
        buildSignature: '',
      );
      Caja4uStartupSplash.isOverlayActiveNotifier.value = false;

      final completer = Completer<bool>();
      final authProv = _FakeAuthProvider(onVerify: (_) => completer.future);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<SettingsProvider>(create: (_) => _FakeSettingsProvider()),
            ChangeNotifierProvider<CashRegisterProvider>(
              create: (_) => _FakeCashRegisterProvider(),
            ),
          ],
          child: MaterialApp(
            onGenerateRoute: (settings) {
              if (settings.name == '/home') {
                return PageRouteBuilder<void>(
                  settings: settings,
                  transitionDuration: const Duration(milliseconds: 460),
                  pageBuilder: (_, __, ___) => const Scaffold(body: Text('HOME_OK')),
                  transitionsBuilder: (_, animation, __, child) =>
                      FadeTransition(opacity: animation, child: child),
                );
              }
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => const LoginScreen(),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      for (final digit in const ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit).first);
        await tester.pump(const Duration(milliseconds: 30));
      }

      // Mientras valida PIN: no reemplaza los puntos por CircularProgressIndicator;
      // conserva los 4 puntos en azul y muestra la barra lineal sutil debajo.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final blueDots = find.byWidgetPredicate(
        (w) =>
            w is AnimatedContainer &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle &&
            (w.decoration as BoxDecoration).color == const Color(0xFF3B82F6),
      );
      expect(blueDots, findsNWidgets(4));

      // Al aprobar el PIN: puntos y barra cambian a esmeralda (#10B981) antes de completar el empalme a /home.
      completer.complete(true);
      await tester.pump();

      final greenDots = find.byWidgetPredicate(
        (w) =>
            w is AnimatedContainer &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle &&
            (w.decoration as BoxDecoration).color == const Color(0xFF10B981),
      );
      expect(greenDots, findsNWidgets(4));
      expect(
        find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == const Color(0xFF10B981),
        ),
        findsWidgets,
      );

      await tester.pumpAndSettle();
      expect(find.text('HOME_OK'), findsOneWidget);
    });

    testWidgets(
        'FadePageRouteTransitionsBuilder aplica FadeTransition y ScaleTransition en Windows y Android',
        (tester) async {
      const builder = FadePageRouteTransitionsBuilder();

      for (final platform in const [TargetPlatform.windows, TargetPlatform.android]) {
        final key = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: key,
            theme: ThemeData(
              platform: platform,
              pageTransitionsTheme: PageTransitionsTheme(
                builders: {platform: builder},
              ),
            ),
            home: const Scaffold(body: Text('FIRST_PAGE')),
          ),
        );

        unawaited(
          key.currentState!.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('SECOND_PAGE')),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        expect(find.text('SECOND_PAGE'), findsOneWidget);
        expect(
          find.ancestor(of: find.text('SECOND_PAGE'), matching: find.byType(FadeTransition)),
          findsWidgets,
        );
        expect(
          find.ancestor(of: find.text('SECOND_PAGE'), matching: find.byType(ScaleTransition)),
          findsWidgets,
        );

        await tester.pumpAndSettle();
        expect(find.text('SECOND_PAGE'), findsOneWidget);
      }
    });
  });
}

class _SplashToLoginHost extends StatefulWidget {
  const _SplashToLoginHost();

  @override
  State<_SplashToLoginHost> createState() => _SplashToLoginHostState();
}

class _SplashToLoginHostState extends State<_SplashToLoginHost> {
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    Caja4uStartupSplash.isOverlayActiveNotifier.value = true;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            ignoring: !_dismissed,
            child: FocusScope(
              canRequestFocus: _dismissed,
              child: const MaterialApp(home: LoginScreen()),
            ),
          ),
          if (!_dismissed)
            Caja4uStartupSplash(
              isReady: true,
              onDismissed: () {
                if (mounted) setState(() => _dismissed = true);
                Caja4uStartupSplash.isOverlayActiveNotifier.value = false;
              },
            ),
        ],
      ),
    );
  }
}

class _FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  _FakeAuthProvider({this.onVerify});

  final Future<bool> Function(String pin)? onVerify;
  int verifyCalls = 0;

  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;
  @override
  Map<String, dynamic>? get currentUser => null;
  @override
  bool get requiresPinChange => false;

  @override
  Future<bool> verifyPin(String pin) async {
    verifyCalls++;
    if (onVerify != null) {
      return onVerify!(pin);
    }
    return false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  @override
  String get currentApiUrl => 'http://127.0.0.1/api';
  @override
  int get assignedRegisterId => 1;
  @override
  Future<void> loadSettings({bool isSilent = false}) async {}
  @override
  Future<void> syncLicenseWithServer(String baseUrl, {bool isSilent = false}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCashRegisterProvider extends ChangeNotifier implements CashRegisterProvider {
  @override
  CashRegisterShift? get currentShift => null;
  @override
  Future<void> checkCurrentShift({int? registerId}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

int _indexOf(Uint8List haystack, List<int> needle) {
  for (int i = 0; i <= haystack.length - needle.length; i++) {
    bool match = true;
    for (int j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}
