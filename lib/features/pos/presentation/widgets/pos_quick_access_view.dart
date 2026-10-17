import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import '../../../catalog/domain/entities/product.dart';
import '../../domain/entities/cart_item.dart';
import '../providers/pos_provider.dart';

/// Renders the Quick Access catalog in the POS screen in one of four view modes:
/// - 'list': Row with 44x44 thumbnail, name, barcode, and price.
/// - 'compact': Compact grid card with 24x24 thumbnail.
/// - 'grid_medium': Medium card grid with 28x28 image thumbnail and details.
/// - 'grid_large': Large card grid with 42x42 image thumbnail and prominent visuals.
class PosQuickAccessCatalogView extends StatelessWidget {
  final List<Product> products;
  final String viewMode;
  final ValueChanged<Product>? onSelectProduct;
  final Widget Function(Product product, bool isByWeight, double fontSize)? priceBuilder;

  /// Si es true, destaca el Top 3 de más vendidos del listado (🔥 #1..#3).
  /// Solo tiene sentido en el Acceso Rápido: en resultados de búsqueda el ranking
  /// sería relativo a los resultados y no al catálogo, por eso es opt-in.
  final bool showTopRanks;

  /// Ventas mínimas para que un producto pueda ser considerado "Top" (evita rotular
  /// como Top a productos con 1 o 2 ventas en un POS recién estrenado).
  static const int topMinSales = 5;

  /// Callback para restar un producto del carrito (botón rápido - en tarjetas activas).
  final ValueChanged<Product>? onDecrementProduct;

  /// Callback para fijar/desfijar un producto en el Acceso Rápido.
  final ValueChanged<Product>? onTogglePin;

  /// Callback para vista rápida (clic derecho / long press).
  final ValueChanged<Product>? onQuickLook;

  /// IDs de productos fijados por terminal (para mostrar indicador 📌).
  final Set<int> pinnedProductIds;

  /// Si es true, muestra micro-indicador de atajo numérico [Alt+1..9] en las primeras 9 tarjetas.
  final bool showKeyboardShortcuts;

  const PosQuickAccessCatalogView({
    super.key,
    required this.products,
    required this.viewMode,
    this.onSelectProduct,
    this.priceBuilder,
    this.showTopRanks = false,
    this.onDecrementProduct,
    this.onTogglePin,
    this.onQuickLook,
    this.pinnedProductIds = const {},
    this.showKeyboardShortcuts = false,
  });

  /// Paleta de 6 tonos sobrios para categorías (hash determinístico).
  static const List<Color> _categoryPalette = [
    Color(0xFF3F51B5), // Indigo
    Color(0xFF009688), // Teal
    Color(0xFF2196F3), // Blue
    Color(0xFF673AB7), // DeepPurple
    Color(0xFF00BCD4), // Cyan
    Color(0xFF607D8B), // BlueGrey
  ];

  /// Devuelve un color de acento determinístico para tarjetas sin foto.
  /// - Productos pesables → Naranja
  /// - Categorías → Hash sobre paleta curada de 6 tonos
  /// - Fallback → AzulGrisáceo
  Color _resolveSemanticAccent(Product product) {
    if (product.isSoldByWeight) {
      return Colors.orange.shade700;
    }

    if (product.category?.name != null && product.category!.name.isNotEmpty) {
      final categoryName = product.category!.name.toLowerCase();
      final hash = categoryName.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
      final index = hash % _categoryPalette.length;
      return _categoryPalette[index];
    }

    return Colors.blueGrey.shade600;
  }

  /// Lectura segura de cantidad en carrito (60 FPS).
  /// Devuelve 0.0 si PosProvider no está disponible (para tests aislados).
  double _getCartQuantity(BuildContext context, int productId) {
    try {
      final pos = Provider.of<PosProvider?>(context, listen: true);
      if (pos == null) return 0.0;
      double total = 0.0;
      for (final item in pos.cart) {
        if (item.product.id == productId) {
          total += item.quantity;
        }
      }
      return total;
    } catch (_) {
      return 0.0;
    }
  }

  /// Calcula el ranking Top 3 (1, 2, 3) entre los productos con al menos [topMinSales] ventas.
  Map<int, int> _computeTopRanks() {
    if (!showTopRanks) return const {};

    final eligible = products.where((p) => p.salesCount >= topMinSales).toList()
      ..sort((a, b) {
        final cmp = b.salesCount.compareTo(a.salesCount);
        if (cmp != 0) return cmp;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    final ranks = <int, int>{};
    for (var i = 0; i < eligible.length && i < 3; i++) {
      ranks[eligible[i].id] = i + 1;
    }
    return ranks;
  }

  String _formatSalesCount(int count) {
    if (count >= 1000) {
      final k = count / 1000.0;
      return '${k.toStringAsFixed(k >= 10 ? 0 : 1)}k';
    }
    return count.toString();
  }

  Widget _buildSalesBadge(
    Product product, {
    int? topRank,
    bool compact = false,
  }) {
    final isTop = topRank != null;
    final formatted = _formatSalesCount(product.salesCount);
    final label = compact
        ? (isTop ? '#$topRank · $formatted' : '$formatted vend.')
        : (isTop ? '#$topRank · $formatted vend.' : '$formatted vend.');

    final bgColor = isTop
        ? const Color(0xFFFFF3CD)
        : Colors.white.withValues(alpha: 0.92);
    final borderColor = isTop
        ? const Color(0xFFFFB300)
        : Colors.blue.shade200;
    final fgColor = isTop
        ? const Color(0xFFB45309)
        : Colors.blue.shade700;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4.5 : 6.0,
        vertical: compact ? 1.5 : 2.0,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 0.9),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isTop ? Icons.local_fire_department_rounded : Icons.flash_on_rounded,
            size: compact ? 9.5 : 11.0,
            color: isTop ? const Color(0xFFE65100) : Colors.blueAccent,
          ),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 8.0 : 9.0,
              color: fgColor,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topRanks = _computeTopRanks();

    if (viewMode == 'list') {
      return ListView.builder(
        itemCount: products.length,
        itemBuilder: (context, index) {
          final p = products[index];
          return _buildListItem(context, p, topRank: topRanks[p.id]);
        },
      );
    } else if (viewMode == 'compact') {
      return GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 280,
          childAspectRatio: 3.5,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: products.length,
        itemBuilder: (context, index) {
          final p = products[index];
          return _buildCompactItem(context, p, topRank: topRanks[p.id]);
        },
      );
    } else if (viewMode == 'grid_medium') {
      return GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 140,
          childAspectRatio: 0.80,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: products.length,
        itemBuilder: (context, index) {
          final p = products[index];
          final shortcutNumber = (showKeyboardShortcuts && index < 9) ? index + 1 : null;
          return _buildGridItem(
            context,
            p,
            isMedium: true,
            topRank: topRanks[p.id],
            shortcutNumber: shortcutNumber,
          );
        },
      );
    } else {
      // Default: grid_large
      return GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          childAspectRatio: 0.82,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: products.length,
        itemBuilder: (context, index) {
          final p = products[index];
          final shortcutNumber = (showKeyboardShortcuts && index < 9) ? index + 1 : null;
          return _buildGridItem(
            context,
            p,
            isMedium: false,
            topRank: topRanks[p.id],
            shortcutNumber: shortcutNumber,
          );
        },
      );
    }
  }

  Widget _buildListItem(BuildContext context, Product product, {int? topRank}) {
    final isByWeight = product.isSoldByWeight;
    final uri = product.imageUrl != null && product.imageUrl!.isNotEmpty
        ? Uri.tryParse(product.imageUrl!)
        : null;
    final hasImage = uri != null && uri.hasScheme && uri.hasAuthority && uri.host.isNotEmpty;
    final hasBarcode = product.barcode != null && product.barcode!.isNotEmpty;

    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: ListTile(
        onTap: () => onSelectProduct?.call(product),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isByWeight ? Colors.orange.shade50 : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300, width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: hasImage
                ? CachedNetworkImage(
                    imageUrl: product.imageUrl!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const Center(
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, url, error) => Icon(
                      isByWeight ? Icons.scale_rounded : Icons.inventory_2_outlined,
                      color: isByWeight ? Colors.orange.shade600 : Colors.blue.shade600,
                      size: 22,
                    ),
                  )
                : Icon(
                    isByWeight ? Icons.scale_rounded : Icons.inventory_2_outlined,
                    color: isByWeight ? Colors.orange.shade600 : Colors.blue.shade600,
                    size: 22,
                  ),
          ),
        ),
        title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: (hasBarcode || isByWeight || product.salesCount > 0)
            ? Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (hasBarcode)
                      Text(product.barcode!, style: const TextStyle(fontSize: 12)),
                    if (isByWeight)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '⚖️ Por Kg',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: Colors.orange.shade900,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (product.salesCount > 0)
                      _buildSalesBadge(product, topRank: topRank, compact: false),
                  ],
                ),
              )
            : null,
        trailing: _renderPrice(context, product, isByWeight, 16),
      ),
    );
  }

  Widget _buildCompactItem(BuildContext context, Product product, {int? topRank}) {
    final isByWeight = product.isSoldByWeight;
    final uri = product.imageUrl != null && product.imageUrl!.isNotEmpty
        ? Uri.tryParse(product.imageUrl!)
        : null;
    final hasImage = uri != null && uri.hasScheme && uri.hasAuthority && uri.host.isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => onSelectProduct?.call(product),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isByWeight ? Colors.orange.shade50 : Colors.blue.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isByWeight ? Colors.orange.shade200 : Colors.blue.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isByWeight ? Colors.orange.shade50 : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: hasImage
                    ? CachedNetworkImage(
                        imageUrl: product.imageUrl!,
                        width: 24,
                        height: 24,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => const Center(
                          child: SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          ),
                        ),
                        errorWidget: (context, url, error) => Icon(
                          isByWeight ? Icons.scale_rounded : Icons.inventory_2_outlined,
                          color: isByWeight ? Colors.orange.shade600 : Colors.blue.shade600,
                          size: 16,
                        ),
                      )
                    : Icon(
                        isByWeight ? Icons.scale_rounded : Icons.inventory_2_outlined,
                        color: isByWeight ? Colors.orange.shade600 : Colors.blue.shade600,
                        size: 16,
                      ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                product.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _renderPrice(context, product, isByWeight, 13),
                    if (product.salesCount > 0) ...[
                      const SizedBox(height: 1),
                      _buildSalesBadge(product, topRank: topRank, compact: true),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridItem(
    BuildContext context,
    Product product, {
    required bool isMedium,
    int? topRank,
    int? shortcutNumber,
  }) {
    final isByWeight = product.isSoldByWeight;
    final uri = product.imageUrl != null && product.imageUrl!.isNotEmpty
        ? Uri.tryParse(product.imageUrl!)
        : null;
    final hasImage = uri != null && uri.hasScheme && uri.hasAuthority && uri.host.isNotEmpty;

    final cartQty = _getCartQuantity(context, product.id);
    final isPinned = pinnedProductIds.contains(product.id);
    final accentColor = _resolveSemanticAccent(product);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onSelectProduct?.call(product),
      onSecondaryTap: () => onQuickLook?.call(product),
      onLongPress: () => onQuickLook?.call(product),
      child: Card(
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: cartQty > 0
                ? const Color(0xFF1E88E5)
                : Colors.grey.shade200,
            width: cartQty > 0 ? 2.0 : 1.0,
          ),
        ),
        child: Container(
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasImage) ...[
                // ─── VARIANTE A: TARJETA CON FOTO ───
                Expanded(
                  flex: 5,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        color: Colors.white,
                        child: CachedNetworkImage(
                          imageUrl: product.imageUrl!,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.contain,
                          placeholder: (context, url) => const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (context, url, error) => Center(
                            child: Icon(
                              isByWeight ? Icons.scale_rounded : Icons.inventory_2_outlined,
                              color: isByWeight ? Colors.orange.shade600 : Colors.blue.shade600,
                              size: isMedium ? 30 : 42,
                            ),
                          ),
                        ),
                      ),
                      if (isByWeight || isPinned || shortcutNumber != null)
                        Positioned(
                          top: 4,
                          left: 4,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.topLeft,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (shortcutNumber != null)
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isMedium ? 3.0 : 4.0,
                                      vertical: 1.0,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade100.withValues(alpha: 0.95),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.blue.shade300, width: 0.8),
                                    ),
                                    child: Text(
                                      'Alt+$shortcutNumber',
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontSize: isMedium ? 6.5 : 7.5,
                                        color: Colors.blue.shade900,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                if (shortcutNumber != null) const SizedBox(width: 3),
                                if (isByWeight)
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isMedium ? 4.0 : 5.5,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade100.withValues(alpha: 0.95),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.orange.shade300, width: 0.8),
                                    ),
                                    child: Text(
                                      isMedium ? '⚖️ Kg' : '⚖️ Por Kg',
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontSize: isMedium ? 7.5 : 8.5,
                                        color: Colors.orange.shade900,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                if (isByWeight) const SizedBox(width: 4),
                                if (isPinned)
                                  const Icon(Icons.push_pin, size: 14, color: Colors.blueGrey),
                              ],
                            ),
                          ),
                        ),
                      if (product.salesCount > 0)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.topRight,
                            child: _buildSalesBadge(
                              product,
                              topRank: topRank,
                              compact: isMedium,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMedium ? 5.0 : 8.0,
                      vertical: isMedium ? 4.0 : 6.0,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            textAlign: TextAlign.start,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: isMedium ? 11 : 12,
                              height: 1.15,
                              color: const Color(0xFF1E293B),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: _renderPrice(context, product, isByWeight, isMedium ? 11 : 12),
                            ),
                            if (cartQty > 0) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E88E5).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isByWeight ? cartQty.toStringAsFixed(2) : cartQty.toInt().toString(),
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Color(0xFF1E88E5),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                              InkWell(
                                onTap: () => onDecrementProduct?.call(product),
                                borderRadius: BorderRadius.circular(4),
                                child: const Padding(
                                  padding: EdgeInsets.all(2),
                                  child: Icon(Icons.remove_circle_outline, size: 18, color: Color(0xFF1E88E5)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                // ─── VARIANTE B: TARJETA SIN FOTO (TIPOGRÁFICA) ───
                Container(height: 4, color: accentColor),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMedium ? 5.0 : 8.0,
                      vertical: isMedium ? 4.0 : 6.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header semántico compacto
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            children: [
                              if (shortcutNumber != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade100.withValues(alpha: 0.95),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.blue.shade300, width: 0.8),
                                  ),
                                  child: Text(
                                    'Alt+$shortcutNumber',
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 7,
                                      color: Colors.blue.shade900,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              if (shortcutNumber != null) const SizedBox(width: 3),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isByWeight ? Icons.scale_rounded : Icons.inventory_2_outlined,
                                      size: 13,
                                      color: accentColor,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      product.category?.name ?? (isByWeight ? 'Por Peso' : (product.internalCode.isNotEmpty ? product.internalCode : 'N/A')),
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: accentColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              if (isPinned)
                                const Icon(Icons.push_pin, size: 12, color: Colors.blueGrey),
                              const SizedBox(width: 4),
                              if (product.salesCount > 0)
                                _buildSalesBadge(product, topRank: topRank, compact: true),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Nombre expandido (3 líneas)
                        Expanded(
                          child: Text(
                            product.name,
                            textAlign: TextAlign.start,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: isMedium ? 10 : 11,
                              height: 1.2,
                              color: const Color(0xFF1E293B),
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Código interno sutil
                        if (product.internalCode.isNotEmpty)
                          Text(
                            product.internalCode,
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.grey.shade500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: 4),
                        // Footer: Precio + Stock + Acción
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: _renderPrice(context, product, isByWeight, isMedium ? 10 : 11),
                            ),
                            if (!product.isCombo &&
                                product.minStock != null &&
                                product.stock <= product.minStock!)
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade700,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            if (cartQty > 0) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E88E5).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isByWeight ? cartQty.toStringAsFixed(2) : cartQty.toInt().toString(),
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Color(0xFF1E88E5),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                              InkWell(
                                onTap: () => onDecrementProduct?.call(product),
                                borderRadius: BorderRadius.circular(4),
                                child: const Padding(
                                  padding: EdgeInsets.all(2),
                                  child: Icon(Icons.remove_circle_outline, size: 18, color: Color(0xFF1E88E5)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _renderPrice(BuildContext context, Product product, bool isByWeight, double fontSize) {
    if (priceBuilder != null) {
      return priceBuilder!(product, isByWeight, fontSize);
    }
    double displayPrice = product.sellingPrice;
    try {
      final pos = Provider.of<PosProvider>(context, listen: false);
      if (pos.activeTier == PriceTier.wholesale) {
        displayPrice = (product.priceWholesale != null && product.priceWholesale! > 0)
            ? product.priceWholesale!
            : product.sellingPrice * pos.wholesaleFactor;
      } else if (pos.activeTier == PriceTier.card) {
        displayPrice = (product.priceCard != null && product.priceCard! > 0)
            ? product.priceCard!
            : product.sellingPrice * pos.cardFactor;
      } else if (pos.activeTier == PriceTier.custom) {
        displayPrice = product.sellingPrice * pos.currentCustomFactor;
      }
    } catch (_) {}

    return Text(
      isByWeight ? '\$${displayPrice.toCurrency()}/Kg' : '\$${displayPrice.toCurrency()}',
      style: TextStyle(
        color: isByWeight ? Colors.orange.shade800 : Colors.green.shade700,
        fontWeight: FontWeight.bold,
        fontSize: fontSize,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
