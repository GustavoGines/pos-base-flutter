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

  const PosQuickAccessCatalogView({
    super.key,
    required this.products,
    required this.viewMode,
    this.onSelectProduct,
    this.priceBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (viewMode == 'list') {
      return ListView.builder(
        itemCount: products.length,
        itemBuilder: (context, index) => _buildListItem(context, products[index]),
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
        itemBuilder: (context, index) => _buildCompactItem(context, products[index]),
      );
    } else if (viewMode == 'grid_medium') {
      return GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 140,
          childAspectRatio: 0.9,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: products.length,
        itemBuilder: (context, index) => _buildGridItem(context, products[index], isMedium: true),
      );
    } else {
      // Default: grid_large
      return GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          childAspectRatio: 0.85,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: products.length,
        itemBuilder: (context, index) => _buildGridItem(context, products[index], isMedium: false),
      );
    }
  }

  Widget _buildListItem(BuildContext context, Product product) {
    final isByWeight = product.isSoldByWeight;
    final uri = product.imageUrl != null && product.imageUrl!.isNotEmpty
        ? Uri.tryParse(product.imageUrl!)
        : null;
    final hasImage = uri != null && uri.hasScheme && uri.hasAuthority && uri.host.isNotEmpty;

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
        subtitle: product.barcode != null && product.barcode!.isNotEmpty
            ? Text(product.barcode!, style: const TextStyle(fontSize: 12))
            : null,
        trailing: _renderPrice(context, product, isByWeight, 16),
      ),
    );
  }

  Widget _buildCompactItem(BuildContext context, Product product) {
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
                child: _renderPrice(context, product, isByWeight, 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridItem(BuildContext context, Product product, {required bool isMedium}) {
    final isByWeight = product.isSoldByWeight;
    final uri = product.imageUrl != null && product.imageUrl!.isNotEmpty
        ? Uri.tryParse(product.imageUrl!)
        : null;
    final hasImage = uri != null && uri.hasScheme && uri.hasAuthority && uri.host.isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onSelectProduct?.call(product),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              colors: isByWeight ? [Colors.orange.shade50, Colors.white] : [Colors.blue.shade50, Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isMedium ? 4.0 : 8.0, vertical: isMedium ? 4.0 : 8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (hasImage)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                      imageUrl: product.imageUrl!,
                      width: isMedium ? 28 : 42,
                      height: isMedium ? 28 : 42,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      errorWidget: (context, url, error) => Icon(
                        isByWeight ? Icons.scale_rounded : Icons.inventory_2_outlined,
                        color: isByWeight ? Colors.orange.shade600 : Colors.blue.shade600,
                        size: isMedium ? 18 : 24,
                      ),
                    ),
                  )
                else
                  Icon(
                    isByWeight ? Icons.scale_rounded : Icons.inventory_2_outlined,
                    color: isByWeight ? Colors.orange.shade600 : Colors.blue.shade600,
                    size: isMedium ? 18 : 24,
                  ),
                SizedBox(height: isMedium ? 2 : 4),
                Expanded(
                  child: Center(
                    child: Text(
                      product.name,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: isMedium ? 11 : 13),
                      maxLines: isMedium ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                SizedBox(height: isMedium ? 2 : 4),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: isMedium ? 1 : 2),
                  decoration: BoxDecoration(
                    color: isByWeight ? Colors.orange.shade100 : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _renderPrice(context, product, isByWeight, isMedium ? 11 : 13),
                ),
                if (isByWeight) ...[
                  SizedBox(height: isMedium ? 2 : 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('⚖️ Por Kg', style: TextStyle(fontSize: isMedium ? 9 : 10, color: Colors.orange.shade900, fontWeight: FontWeight.w600)),
                  ),
                ],
                if (product.salesCount > 0) ...[
                  SizedBox(height: isMedium ? 2 : 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.blue.withAlpha(25),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue.withAlpha(50)),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flash_on_rounded, size: isMedium ? 8 : 10, color: Colors.blueAccent),
                          const SizedBox(width: 2),
                          Text(
                            "${product.salesCount} vend.",
                            style: TextStyle(fontSize: isMedium ? 8 : 9, color: Colors.blueAccent, fontWeight: FontWeight.bold),
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
