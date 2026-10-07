import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/image_url_resolver.dart';
import '../../../core/utils/snack_bar_service.dart';
import '../domain/entities/product.dart';

/// Helper para formatear y compartir productos.
/// En móviles (Android/iOS) utiliza el share sheet nativo con archivo temporal e imagen adjunta.
/// En Desktop/Web (Windows, Linux, macOS, Web) utiliza un enlace directo a `wa.me` con el texto
/// formateado y la URL pública de la imagen para que WhatsApp genere la vista previa (unfurl).
class ProductShareHelper {
  /// Determina si una URL pertenece a un host privado, local o no alcanzable desde internet.
  /// Retorna true para loopback, RFC 1918 (10., 192.168., 172.16-31), link-local,
  /// dominios .test, .local, .localhost, .internal, .lan, etc.
  static bool isPrivateOrLocalUrl(String? urlString) {
    if (urlString == null || urlString.trim().isEmpty) return true;
    final trimmed = urlString.trim();
    final uri = Uri.tryParse(trimmed) ?? Uri.tryParse(Uri.encodeFull(trimmed));
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return true;
    if (uri.scheme != 'http' && uri.scheme != 'https') return true;

    final rawHost = uri.host.toLowerCase().trim();
    final host = rawHost.replaceAll('[', '').replaceAll(']', '');
    if (host.isEmpty) return true;

    // 1. Single-label hostnames without dots are intranet / local names (e.g. 'servidor', 'caja1', 'pos-server')
    // unless they contain ':' (IPv6 literal).
    if (!host.contains('.') && !host.contains(':')) {
      return true;
    }

    // 2. Loopback / localhost / 0.0.0.0
    if (host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '0.0.0.0' ||
        host.startsWith('127.')) {
      return true;
    }

    // 3. Special-use TLDs (RFC 2606, RFC 6761, RFC 6762, RFC 8375)
    if (host.endsWith('.test') ||
        host.endsWith('.local') ||
        host.endsWith('.localhost') ||
        host.endsWith('.internal') ||
        host.endsWith('.lan') ||
        host.endsWith('.invalid') ||
        host.endsWith('.example') ||
        host.endsWith('.localdomain') ||
        host.endsWith('.home.arpa')) {
      return true;
    }

    // 4. IPv4 Private & Link-Local Ranges (Strict 4-octet numeric check)
    final ipv4Parts = host.split('.');
    if (ipv4Parts.length == 4 && ipv4Parts.every((p) => int.tryParse(p) != null)) {
      final o1 = int.parse(ipv4Parts[0]);
      final o2 = int.parse(ipv4Parts[1]);

      // 10.0.0.0/8
      if (o1 == 10) return true;
      // 192.168.0.0/16
      if (o1 == 192 && o2 == 168) return true;
      // 169.254.0.0/16 (Link-Local)
      if (o1 == 169 && o2 == 254) return true;
      // 172.16.0.0/12 (172.16.0.0 to 172.31.255.255)
      if (o1 == 172 && o2 >= 16 && o2 <= 31) return true;
    }

    // 5. IPv6 Local / Loopback / Link-Local / ULA (Requires colons)
    if (host.contains(':')) {
      // Loopback (compressed, uncompressed, zero-padded) and unspecified
      if (host == '::1' ||
          host == '::' ||
          host == '0:0:0:0:0:0:0:1' ||
          host == '0:0:0:0:0:0:0:0' ||
          host.replaceAll(RegExp(r'^[0:]+'), '') == '1') {
        return true;
      }
      // Link-Local (fe80::/10)
      if (host.startsWith('fe80:') ||
          host.startsWith('fe8') ||
          host.startsWith('fe9') ||
          host.startsWith('fea') ||
          host.startsWith('feb')) {
        return true;
      }
      // Unique Local Address (fc00::/7 -> fc00:: to fdff::)
      if (host.startsWith('fc') || host.startsWith('fd')) {
        return true;
      }
    }

    return false;
  }

  /// Construye la URI de wa.me con codificación correcta.
  static Uri buildWhatsAppUri({String? phone, required String text}) {
    final cleanPhone = (phone ?? '').replaceAll(RegExp(r'[^\d]'), '');
    final path = cleanPhone.isNotEmpty ? '/$cleanPhone' : '/';
    return Uri.https('wa.me', path, {'text': text});
  }

  /// Formatea la información del producto para compartir como texto plano o caption.
  /// Usa texto plano sin emojis para máxima compatibilidad con WhatsApp Desktop/Windows.
        static String formatProductShareText(Product product) {
    final buffer = StringBuffer();
    buffer.writeln('*${product.name}*');
    buffer.writeln('- Precio: \$${product.sellingPrice.toCurrency()}');
    if (product.priceWholesale != null && product.priceWholesale! > 0) {
      buffer.writeln('- Mayorista: \$${product.priceWholesale!.toCurrency()}');
    }
    if (product.priceCard != null && product.priceCard! > 0) {
      buffer.writeln('- Tarjeta: \$${product.priceCard!.toCurrency()}');
    }

    if (product.category != null && product.category!.name.trim().isNotEmpty) {
      buffer.writeln('- Categoría: ${product.category!.name.trim()}');
    }
    if (product.brand != null && product.brand!.name.trim().isNotEmpty) {
      buffer.writeln('- Marca: ${product.brand!.name.trim()}');
    }
    if (product.supplier != null && product.supplier!.name.trim().isNotEmpty) {
      buffer.writeln('- Proveedor: ${product.supplier!.name.trim()}');
    }
    if (product.isSoldByWeight) {
      buffer.writeln('- Producto por peso');
    }
    return buffer.toString().trim();
  }

  /// Comparte el producto según la plataforma (estrategia híbrida):
  /// - En Móvil (Android/iOS): Descarga la imagen en archivo temporal y la comparte
  ///   con caption mediante `Share.shareXFiles`.
  /// - En Desktop/Web (Windows, Linux, macOS, Web): Abre un deep link de `wa.me` con el texto
  ///   formateado y la URL pública de la imagen (para unfurling en WhatsApp).
  ///   Si la URL es local/privada o no está disponible, envía el texto limpio, muestra un aviso discreto
  ///   y copia el texto al portapapeles.
  ///   Si el lanzamiento falla, realiza fallback a portapapeles y notifica al usuario.
  static Future<void> shareProduct(
    Product product, {
    BuildContext? context,
    String? phone,
    bool? isMobile,
    http.Client? httpClient,
    Future<Directory> Function()? getTempDir,
    Future<void> Function(List<XFile> files, {String? text, String? subject})? shareFilesFn,
    Future<void> Function(String text, {String? subject})? shareTextFn,
    Future<bool> Function(Uri uri, {LaunchMode mode})? launchUrlFn,
    Future<bool> Function(Uri uri)? canLaunchUrlFn,
    Future<void> Function(String text)? copyToClipboardFn,
    void Function(String message, {bool isError})? onShowNotice,
  }) async {
    final text = formatProductShareText(product);
    final rawUrl = product.imageUrl?.trim();
    final imageUrl = (rawUrl != null && rawUrl.isNotEmpty) ? (resolveImageUrl(rawUrl) ?? rawUrl) : null;

    final effectiveIsMobile = isMobile ?? (shareFilesFn != null ? true : AppConfig.isMobile);

        // Helper para notificaciones visuales
    void notify(String msg, {bool isError = false}) {
      if (onShowNotice != null) {
        onShowNotice(msg, isError: isError);
        return;
      }
      final ctx = context ?? AppConfig.navigatorKey.currentContext;
      if (ctx != null) {
        if (isError) {
          SnackBarService.error(ctx, msg);
        } else {
          SnackBarService.info(ctx, msg, duration: const Duration(seconds: 10));
        }
      } else {
        debugPrint('[ProductShareHelper] $msg');
      }
    }

    // Helper para portapapeles
    Future<void> copyClipboard(String textToCopy) async {
      try {
        if (copyToClipboardFn != null) {
          await copyToClipboardFn(textToCopy);
        } else {
          await Clipboard.setData(ClipboardData(text: textToCopy));
        }
      } catch (e) {
        debugPrint('[ProductShareHelper] Error al copiar al portapapeles: $e');
      }
    }

    // En Desktop siempre copiamos el texto al portapapeles preventivamente
    // para que el usuario pueda hacer Ctrl+V en el pie de la foto en WhatsApp
    final isDesktopPlatform = !effectiveIsMobile;
    if (isDesktopPlatform) {
      await copyClipboard(text);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 1. Caso SIN IMAGEN: Compartir texto plano
    // ─────────────────────────────────────────────────────────────────────────
    if (imageUrl == null || imageUrl.isEmpty) {
      try {
        if (shareTextFn != null) {
          await shareTextFn(text);
        } else {
          await Share.share(text);
        }
        if (isDesktopPlatform) {
          notify('Texto del producto copiado al portapapeles');
        }
      } catch (e) {
        debugPrint('Error al compartir texto de producto: $e');
        // Fallback a wa.me si falla el share nativo
        if (isDesktopPlatform) {
          final waUri = buildWhatsAppUri(phone: phone, text: text);
          try {
            final canLaunch = canLaunchUrlFn != null
                ? await canLaunchUrlFn(waUri)
                : (launchUrlFn != null ? true : await canLaunchUrl(waUri));
            if (canLaunch) {
              final launched = launchUrlFn != null
                  ? await launchUrlFn(waUri, mode: LaunchMode.externalApplication)
                  : await launchUrl(waUri, mode: LaunchMode.externalApplication);
              if (!launched) {
                notify('No se pudo abrir WhatsApp. Texto copiado al portapapeles.', isError: true);
              }
            } else {
              notify('No se pudo abrir WhatsApp. Texto copiado al portapapeles.', isError: true);
            }
          } catch (_) {
            notify('No se pudo abrir WhatsApp. Texto copiado al portapapeles.', isError: true);
          }
        }
      }
      return;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 2. Caso CON IMAGEN: Descargar y compartir archivo con caption (Móvil y Desktop)
    // ─────────────────────────────────────────────────────────────────────────
    final client = httpClient ?? http.Client();
    try {
      final uri = Uri.tryParse(imageUrl);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        final response = await client.get(uri).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          final tempDir = getTempDir != null ? await getTempDir() : await getTemporaryDirectory();

          String ext = 'jpg';
          final pathLower = uri.path.toLowerCase();
          if (pathLower.endsWith('.png')) {
            ext = 'png';
          } else if (pathLower.endsWith('.webp')) {
            ext = 'webp';
          } else if (pathLower.endsWith('.jpeg')) {
            ext = 'jpeg';
          }

          final sep = Platform.pathSeparator;
          final dirPath = tempDir.path.endsWith('/') || tempDir.path.endsWith('\\')
              ? tempDir.path
              : '${tempDir.path}$sep';
          final filePath = '${dirPath}producto_${product.id}.$ext';
          final tempFile = File(filePath);
          if (tempFile.existsSync()) {
            try {
              tempFile.deleteSync();
            } catch (_) {}
          }
          await tempFile.writeAsBytes(response.bodyBytes);

          final xFile = XFile(tempFile.path);

          if (isDesktopPlatform) {
            notify('Foto lista y texto copiado al portapapeles. Pegalo con Ctrl+V en el pie de la foto.');
          }

          if (shareFilesFn != null) {
            await shareFilesFn([xFile], text: text);
          } else {
            await Share.shareXFiles([xFile], text: text, subject: 'Detalles del Producto');
          }
          return;
        }
      } else if (!kIsWeb) {
        // Manejo de archivo local directo si existe
        final localFile = File(imageUrl);
        if (localFile.existsSync()) {
          final xFile = XFile(localFile.path);

          if (isDesktopPlatform) {
            notify('Foto lista y texto copiado al portapapeles. Pegalo con Ctrl+V en el pie de la foto.');
          }

          if (shareFilesFn != null) {
            await shareFilesFn([xFile], text: text);
          } else {
            await Share.shareXFiles([xFile], text: text, subject: 'Detalles del Producto');
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('Error al descargar o compartir imagen del producto: $e');
    } finally {
      if (httpClient == null) {
        client.close();
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 3. FALLBACK: Compartir texto si la descarga de imagen falló
    // ─────────────────────────────────────────────────────────────────────────
    try {
      if (shareTextFn != null) {
        await shareTextFn(text);
      } else {
        await Share.share(text);
      }
      if (isDesktopPlatform) {
        notify('No se pudo adjuntar la foto. Texto copiado al portapapeles.');
      }
    } catch (e) {
      debugPrint('Error al compartir texto del producto (fallback): $e');
      if (isDesktopPlatform) {
        // Último recurso: wa.me
        final waUri = buildWhatsAppUri(phone: phone, text: text);
        try {
          final canLaunch = canLaunchUrlFn != null
              ? await canLaunchUrlFn(waUri)
              : (launchUrlFn != null ? true : await canLaunchUrl(waUri));
          if (canLaunch) {
            final launched = launchUrlFn != null
                ? await launchUrlFn(waUri, mode: LaunchMode.externalApplication)
                : await launchUrl(waUri, mode: LaunchMode.externalApplication);
            if (!launched) {
              notify('No se pudo abrir WhatsApp. Texto copiado al portapapeles.', isError: true);
            }
          } else {
            notify('No se pudo abrir WhatsApp. Texto copiado al portapapeles.', isError: true);
          }
        } catch (_) {
          notify('No se pudo abrir WhatsApp. Texto copiado al portapapeles.', isError: true);
        }
      }
    }
  }
}










