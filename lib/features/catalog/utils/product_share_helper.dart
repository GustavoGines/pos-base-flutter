import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/image_url_resolver.dart';
import '../domain/entities/product.dart';

/// Helper para formatear y compartir productos mediante el plugin nativo `share_plus`.
class ProductShareHelper {
  /// Formatea la información del producto para compartir como texto plano o caption.
  static String formatProductShareText(Product product) {
    final buffer = StringBuffer();
    buffer.writeln('📦 *${product.name}*');
    buffer.writeln('💰 Precio: \$${product.sellingPrice.toCurrency()}');
    if (product.priceWholesale != null && product.priceWholesale! > 0) {
      buffer.writeln('🏷️ Mayorista: \$${product.priceWholesale!.toCurrency()}');
    }
    if (product.priceCard != null && product.priceCard! > 0) {
      buffer.writeln('💳 Tarjeta: \$${product.priceCard!.toCurrency()}');
    }
    if (product.barcode != null && product.barcode!.trim().isNotEmpty) {
      buffer.writeln('🏷️ Código de Barras: ${product.barcode!.trim()}');
    }
    if (product.internalCode.trim().isNotEmpty) {
      buffer.writeln('🔢 Código Interno: ${product.internalCode.trim()}');
    }
    if (product.category != null && product.category!.name.trim().isNotEmpty) {
      buffer.writeln('📂 Categoría: ${product.category!.name.trim()}');
    }
    if (product.brand != null && product.brand!.name.trim().isNotEmpty) {
      buffer.writeln('🏭 Marca: ${product.brand!.name.trim()}');
    }
    if (product.supplier != null && product.supplier!.name.trim().isNotEmpty) {
      buffer.writeln('🚚 Proveedor: ${product.supplier!.name.trim()}');
    }
    if (product.isSoldByWeight) {
      buffer.writeln('⚖️ Venta por Peso');
    }
    return buffer.toString().trim();
  }

  /// Comparte el producto.
  /// Si el producto cuenta con `imageUrl`, intenta descargar la imagen, guardarla
  /// en un archivo temporal y compartir mediante `Share.shareXFiles`.
  /// Si la descarga falla o no tiene imagen, realiza un fallback elegante compartiendo solo el texto.
  static Future<void> shareProduct(
    Product product, {
    http.Client? httpClient,
    Future<Directory> Function()? getTempDir,
    Future<void> Function(List<XFile> files, {String? text, String? subject})? shareFilesFn,
    Future<void> Function(String text, {String? subject})? shareTextFn,
  }) async {
    final text = formatProductShareText(product);
    final rawUrl = product.imageUrl?.trim();
    final imageUrl = (rawUrl != null && rawUrl.isNotEmpty) ? (resolveImageUrl(rawUrl) ?? rawUrl) : null;

    // 1. Caso sin imagen o en Web: compartir directamente solo texto
    if (kIsWeb || imageUrl == null || imageUrl.isEmpty) {
      try {
        if (shareTextFn != null) {
          await shareTextFn(text, subject: product.name);
        } else {
          await Share.share(text, subject: product.name);
        }
      } catch (e) {
        debugPrint('Error al compartir texto de producto: $e');
      }
      return;
    }

    // 2. Caso con imagen: descargar y escribir a archivo temporal único
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
          if (shareFilesFn != null) {
            await shareFilesFn([xFile], text: text, subject: product.name);
          } else {
            await Share.shareXFiles([xFile], text: text, subject: product.name);
          }
          return;
        }
      } else if (!kIsWeb) {
        // Manejo de archivo local directo si existe
        final localFile = File(imageUrl);
        if (localFile.existsSync()) {
          final xFile = XFile(localFile.path);
          if (shareFilesFn != null) {
            await shareFilesFn([xFile], text: text, subject: product.name);
          } else {
            await Share.shareXFiles([xFile], text: text, subject: product.name);
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('Error al descargar imagen del producto para compartir: $e');
    } finally {
      if (httpClient == null) {
        client.close();
      }
    }

    // 3. Fallback: compartir texto si la imagen falló o no pudo descargarse
    try {
      if (shareTextFn != null) {
        await shareTextFn(text, subject: product.name);
      } else {
        await Share.share(text, subject: product.name);
      }
    } catch (e) {
      debugPrint('Error al compartir texto del producto (fallback): $e');
    }
  }
}
