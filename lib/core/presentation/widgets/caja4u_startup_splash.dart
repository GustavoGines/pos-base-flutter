import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Pantalla de inicio animada de Caja4U (Windows y Android).
///
/// Se monta como capa superior sobre el arranque real del sistema y se retira
/// con un fundido cuando se cumplen ambas condiciones:
///  1. Pasó [minDisplayDuration] (la animación llegó a mostrar la marca completa).
///  2. El sistema terminó de cargar ([isReady] == `true`), con éxito o con error.
///
/// El usuario puede saltarla en cualquier momento con un clic/toque o una tecla.
/// La animación es un WebP animado que se reproduce una sola vez y queda fija en
/// el último cuadro; no requiere plugins de video en ninguna plataforma.
class Caja4uStartupSplash extends StatefulWidget {
  const Caja4uStartupSplash({
    super.key,
    required this.isReady,
    required this.onDismissed,
    this.minDisplayDuration = defaultMinDisplayDuration,
    this.fadeOutDuration = defaultFadeOutDuration,
    this.assetPath = animatedAsset,
    this.fallbackAssetPath = fallbackAsset,
  });

  /// Color de fondo de marca. Coincide con el fondo de la animación y con el
  /// splash nativo de Android (`@color/caja4u_splash_background`).
  static const Color backgroundColor = Color(0xFF121C33);

  static const String animatedAsset = 'assets/splash_caja4u.webp';
  static const String fallbackAsset = 'assets/caja4u_logo_full.png';

  /// Indica si la capa del splash animado está actualmente cubriendo la app.
  /// `LoginScreen` la observa para iniciar su transición coreografiada recién
  /// cuando el splash termina de retirarse (y en tests aislados vale `false`).
  static final ValueNotifier<bool> isOverlayActiveNotifier =
      ValueNotifier<bool>(false);

  /// La animación dura ~4,1 s y "by Dev4U" termina de escribirse a los ~2,7 s;
  /// 4,4 s desde el primer cuadro asegura que se lea completo antes de empalmar.
  static const Duration defaultMinDisplayDuration = Duration(milliseconds: 4400);
  static const Duration defaultFadeOutDuration = Duration(milliseconds: 240);

  /// Tamaño unificado de la animación según la ventana.
  /// `LoginScreen` usa exactamente este mismo tamaño para igualar al píxel la
  /// escala del logo al momento del empalme.
  static double logoSizeForViewport(Size viewport) =>
      (viewport.shortestSide * 0.44).clamp(240.0, 360.0);

  /// Demora antes de mostrar la indicación para saltar la animación.
  static const Duration skipHintDelay = Duration(milliseconds: 1200);

  /// `true` cuando el sistema terminó de inicializar (con éxito o con error).
  final bool isReady;

  /// Se invoca una única vez, cuando terminó el fundido de salida.
  final VoidCallback onDismissed;

  final Duration minDisplayDuration;
  final Duration fadeOutDuration;
  final String assetPath;
  final String fallbackAssetPath;

  @override
  State<Caja4uStartupSplash> createState() => _Caja4uStartupSplashState();
}

class _Caja4uStartupSplashState extends State<Caja4uStartupSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  Timer? _minDisplayTimer;
  Timer? _skipHintTimer;

  bool _minDisplayElapsed = false;
  bool _playbackSyncedToFirstFrame = false;
  bool _showSkipHint = false;
  bool _isDismissing = false;
  bool _dismissNotified = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: widget.fadeOutDuration,
      value: 1.0,
    );

    _scheduleMinDisplayTimer();

    _skipHintTimer = Timer(Caja4uStartupSplash.skipHintDelay, () {
      if (mounted && !_isDismissing) setState(() => _showSkipHint = true);
    });

    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  void _scheduleMinDisplayTimer() {
    _minDisplayTimer?.cancel();
    _minDisplayTimer = Timer(widget.minDisplayDuration, () {
      if (!mounted) return;
      setState(() => _minDisplayElapsed = true);
      _maybeDismiss();
    });
  }

  void _onFirstAnimationFramePainted() {
    if (_playbackSyncedToFirstFrame || _isDismissing || _minDisplayElapsed) {
      return;
    }
    _playbackSyncedToFirstFrame = true;
    // Reinicia el temporizador cuando el primer cuadro del WebP se pinta en
    // pantalla, evitando que la decodificación inicial recorte el "by Dev4U".
    _scheduleMinDisplayTimer();
  }

  @override
  void didUpdateWidget(covariant Caja4uStartupSplash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isReady && !oldWidget.isReady) _maybeDismiss();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _minDisplayTimer?.cancel();
    _skipHintTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (_isDismissing) return false;
    if (event is KeyDownEvent) {
      _skip();
      return true; // Consumimos la tecla: no debe llegar a la pantalla de abajo.
    }
    return false;
  }

  void _skip() => _startDismiss();

  void _maybeDismiss() {
    if (_minDisplayElapsed && widget.isReady) _startDismiss();
  }

  void _startDismiss() {
    if (_isDismissing || !mounted) return;
    _isDismissing = true;
    _minDisplayTimer?.cancel();
    _skipHintTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    setState(() => _showSkipHint = false);

    _fadeController.reverse().whenCompleteOrCancel(() {
      if (_dismissNotified) return;
      _dismissNotified = true;
      widget.onDismissed();
    });
  }

  bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final bool waitingForSystem =
        _minDisplayElapsed && !widget.isReady && !_isDismissing;

    return FadeTransition(
      opacity: _fadeController,
      child: GestureDetector(
        key: const ValueKey('caja4u_splash_tap_area'),
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        child: ColoredBox(
          color: Caja4uStartupSplash.backgroundColor,
          child: DefaultTextStyle(
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white60,
              letterSpacing: 0.4,
              decoration: TextDecoration.none,
              fontWeight: FontWeight.normal,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double logoSize =
                    Caja4uStartupSplash.logoSizeForViewport(constraints.biggest);
                final double indicatorTop =
                    ((constraints.maxHeight / 2) + (logoSize * 0.36))
                        .clamp(0.0, (constraints.maxHeight - 96).clamp(0.0, double.infinity));

                return RepaintBoundary(
                  child: ExcludeSemantics(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(
                          child: _buildAnimatedLogo(logoSize),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          top: indicatorTop,
                          child: AnimatedOpacity(
                            opacity: waitingForSystem ? 1 : 0,
                            duration: const Duration(milliseconds: 300),
                            child: waitingForSystem
                                ? const _WaitingIndicator()
                                : const SizedBox.shrink(),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 24,
                          child: AnimatedOpacity(
                            opacity: _showSkipHint ? 1 : 0,
                            duration: const Duration(milliseconds: 400),
                            child: Text(
                              _isMobile
                                  ? 'Tocá para continuar'
                                  : 'Hacé clic o presioná una tecla para continuar',
                              key: const ValueKey('caja4u_splash_skip_hint'),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white38,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedLogo(double size) {
    return Semantics(
      label: 'Caja4U Punto de Venta',
      image: true,
      child: SizedBox.square(
        dimension: size,
        // Difumina los bordes del cuadro para que la animación se funda con el
        // fondo de la ventana, sin que se note el recuadro del video original.
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => const RadialGradient(
            radius: 0.5,
            colors: [Colors.white, Colors.white, Colors.transparent],
            stops: [0.0, 0.80, 1.0],
          ).createShader(bounds),
          child: Image.asset(
            widget.assetPath,
            key: const ValueKey('caja4u_splash_animation'),
            width: size,
            height: size,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            excludeFromSemantics: true,
            frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
              if (frame != null || wasSynchronouslyLoaded) {
                if (!_playbackSyncedToFirstFrame) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _onFirstAnimationFramePainted();
                  });
                }
                return child;
              }
              return SizedBox.square(dimension: size);
            },
            errorBuilder: (_, __, ___) => Padding(
              padding: EdgeInsets.all(size * 0.12),
              child: Image.asset(
                widget.fallbackAssetPath,
                key: const ValueKey('caja4u_splash_fallback'),
                fit: BoxFit.contain,
                excludeFromSemantics: true,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.point_of_sale_rounded,
                  size: size * 0.4,
                  color: const Color(0xFF10B981),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Indicador discreto que aparece solo si la animación terminó y el sistema
/// todavía está cargando (por ejemplo, servidor lento o red caída).
class _WaitingIndicator extends StatelessWidget {
  const _WaitingIndicator();

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('caja4u_splash_waiting'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: const SizedBox(
            width: 160,
            height: 3,
            child: LinearProgressIndicator(
              backgroundColor: Colors.white12,
              color: Color(0xFF10B981),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Conectando con el servidor...',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
