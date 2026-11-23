import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';

/// Resolución opcional de `LocalTerminalProvider` que retorna `null` en entornos
/// de test o vistas donde dicho provider no fue inyectado en el árbol.
LocalTerminalProvider? tryGetLocalTerminalProvider(
  BuildContext context, {
  bool listen = false,
}) {
  try {
    return Provider.of<LocalTerminalProvider>(context, listen: listen);
  } on ProviderNotFoundException catch (_) {
    try {
      return Provider.of<LocalTerminalProvider?>(context, listen: listen);
    } on ProviderNotFoundException catch (_) {
      return null;
    }
  }
}

typedef SearchHistoryPriceInfo = ({
  double price,
  double? crossedOutPrice,
  bool hasActiveOffer,
});

/// Panel flotante reutilizable para mostrar términos recientes y productos
/// consultados por módulo, protegido con [TextFieldTapRegion] para que los clics
/// internos en `✕` y `Limpiar` no desenfoquen ni destruyan el overlay antes
/// de ejecutarse.
class PosSearchHistoryPopover extends StatelessWidget {
  final List<String> terms;
  final List<Product> products;
  final bool showProducts;
  final int highlightedIndex;
  final Object? tapGroupId;
  final double maxWidth;
  final double maxHeight;
  final IconData productActionIcon;
  final ValueChanged<String> onSelectTerm;
  final ValueChanged<String> onRemoveTerm;
  final ValueChanged<Product> onSelectProduct;
  final ValueChanged<int> onRemoveProduct;
  final VoidCallback onClearAll;
  final VoidCallback onDismiss;
  final SearchHistoryPriceInfo Function(Product product)? priceResolver;
  final Key? containerKey;

  const PosSearchHistoryPopover({
    super.key,
    required this.terms,
    required this.products,
    this.showProducts = true,
    this.highlightedIndex = -1,
    this.tapGroupId,
    this.maxWidth = 580.0,
    this.maxHeight = 380.0,
    this.productActionIcon = Icons.add_circle_outline_rounded,
    required this.onSelectTerm,
    required this.onRemoveTerm,
    required this.onSelectProduct,
    required this.onRemoveProduct,
    required this.onClearAll,
    required this.onDismiss,
    this.priceResolver,
    this.containerKey,
  });

  /// Helper estándar para posicionar el popover debajo de un buscador dentro de
  /// [OverlayPortal.overlayChildLayoutBuilder] sin empujar el layout inferior.
  static Widget buildAnchoredOverlay({
    required OverlayChildLayoutInfo info,
    required Widget child,
    double maxWidth = 580.0,
    double verticalGap = 6.0,
    double minHeight = 160.0,
    double maxOverlayHeight = 380.0,
  }) {
    final Offset targetBottomLeft = MatrixUtils.transformPoint(
      info.childPaintTransform,
      Offset(0, info.childSize.height),
    );
    final double rawAvailableWidth =
        info.overlaySize.width > 16.0 ? info.overlaySize.width - 16.0 : info.overlaySize.width;
    final double safeUpperWidth =
        rawAvailableWidth > maxWidth ? maxWidth : (rawAvailableWidth < 160.0 ? 160.0 : rawAvailableWidth);
    final double safeLowerWidth = safeUpperWidth < 280.0 ? safeUpperWidth : 280.0;
    final double width =
        info.childSize.width.clamp(safeLowerWidth, safeUpperWidth);
    final double rawMaxLeft = info.overlaySize.width - width - 8.0;
    final double maxLeft = rawMaxLeft < 8.0 ? 8.0 : rawMaxLeft;
    final double left = targetBottomLeft.dx.clamp(8.0, maxLeft);
    final double top = targetBottomLeft.dy + verticalGap;
    final double rawAvailableHeight = info.overlaySize.height - top - 16.0;
    final double effectiveMinHeight =
        minHeight > maxOverlayHeight ? maxOverlayHeight : minHeight;
    final double computedMaxHeight = rawAvailableHeight <= effectiveMinHeight
        ? effectiveMinHeight
        : (rawAvailableHeight > maxOverlayHeight
            ? maxOverlayHeight
            : rawAvailableHeight);

    return Positioned(
      top: top,
      left: left,
      width: width,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: computedMaxHeight),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleProducts = showProducts ? products : const <Product>[];

    Widget card = Focus(
      canRequestFocus: false,
      descendantsAreFocusable: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        ),
        child: Container(
          key: containerKey,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF94A3B8),
              width: 1.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x330F172A),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
              BoxShadow(
                color: Color(0x140F172A),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (terms.isNotEmpty) ...[
                          _buildSectionTitle('TÉRMINOS RECIENTES'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (int i = 0; i < terms.length; i++)
                                _buildTermChip(
                                  terms[i],
                                  isHighlighted: highlightedIndex == i,
                                ),
                            ],
                          ),
                        ],
                        if (terms.isNotEmpty && visibleProducts.isNotEmpty)
                          const Divider(height: 20, color: Color(0xFFE2E8F0)),
                        if (visibleProducts.isNotEmpty) ...[
                          _buildSectionTitle('PRODUCTOS CONSULTADOS'),
                          const SizedBox(height: 6),
                          for (int i = 0; i < visibleProducts.length; i++)
                            _buildProductRow(
                              visibleProducts[i],
                              isHighlighted:
                                  highlightedIndex == (terms.length + i),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    card = TextFieldTapRegion(child: card);

    if (tapGroupId != null) {
      card = TapRegion(
        groupId: tapGroupId,
        onTapOutside: (_) => onDismiss(),
        child: card,
      );
    }

    return card;
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
      color: const Color(0xFF1E293B),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF0D9488),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.history_rounded,
              size: 15,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Búsquedas recientes',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Tooltip(
            message: 'Vaciar el historial de búsquedas recientes',
            child: Material(
              color: Colors.white.withValues(alpha: 0.10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('search_history_clear_btn'),
                canRequestFocus: false,
                hoverColor: Colors.white.withValues(alpha: 0.20),
                splashColor: Colors.white.withValues(alpha: 0.28),
                onTap: onClearAll,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.delete_sweep_outlined,
                        size: 14,
                        color: Colors.white,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Borrar historial',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: Color(0xFF64748B),
      ),
    );
  }

  Widget _buildTermChip(String term, {required bool isHighlighted}) {
    return Material(
      color: isHighlighted
          ? const Color(0xFFF0FDFA)
          : const Color(0xFFF8FAFC),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isHighlighted
              ? const Color(0xFF0D9488)
              : const Color(0xFFCBD5E1),
          width: isHighlighted ? 1.5 : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            canRequestFocus: false,
            borderRadius:
                const BorderRadius.horizontal(left: Radius.circular(17)),
            hoverColor: const Color(0xFFE2E8F0).withValues(alpha: 0.55),
            onTap: () => onSelectTerm(term),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 5, 8, 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 13.5,
                    color: isHighlighted
                        ? const Color(0xFF0F766E)
                        : const Color(0xFF475569),
                  ),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 185),
                    child: Text(
                      term,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 18, color: const Color(0xFFE2E8F0)),
          _HoverCloseButton(
            buttonKey: ValueKey('remove_term_$term'),
            size: 28,
            iconSize: 14,
            tooltip: 'Quitar término',
            borderRadius:
                const BorderRadius.horizontal(right: Radius.circular(17)),
            onTap: () => onRemoveTerm(term),
          ),
        ],
      ),
    );
  }

  Widget _buildProductRow(Product p, {required bool isHighlighted}) {
    final SearchHistoryPriceInfo resolvedPrice = priceResolver != null
        ? priceResolver!(p)
        : (
            price: p.sellingPrice,
            crossedOutPrice: null,
            hasActiveOffer: false,
          );
    final unitSuffix =
        p.isSoldByWeight ? '/${p.effectiveQuantityUnitLabel}' : '';
    final priceStr = '\$${resolvedPrice.price.toCurrency()}$unitSuffix';
    final unitNorm = p.unitType.trim().toLowerCase();
    final stockUnitSuffix =
        (unitNorm.isEmpty || unitNorm == 'un') ? 'u' : p.unitShortLabel;
    final stockWeightUnit =
        p.effectiveQuantityUnitLabel == 'Kg'
            ? 'kg'
            : p.effectiveQuantityUnitLabel;

    final stockText = p.isService
        ? 'Servicio'
        : (p.stock > 0
            ? 'Stock: ${p.stock.toUnitStockDisplay(isSoldByWeight: p.isSoldByWeight, unitSuffix: stockUnitSuffix, weightUnit: stockWeightUnit)}'
            : 'Sin stock');
    final Color stockBg = p.isService
        ? const Color(0xFFF1F5F9)
        : (p.stock > 0 ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2));
    final Color stockFg = p.isService
        ? const Color(0xFF475569)
        : (p.stock > 0 ? const Color(0xFF15803D) : const Color(0xFFB91C1C));
    final Color stockBorder = p.isService
        ? const Color(0xFFCBD5E1)
        : (p.stock > 0 ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA));

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isHighlighted ? const Color(0xFFF0FDFA) : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: isHighlighted ? const Color(0xFF0D9488) : Colors.transparent,
          width: isHighlighted ? 1.2 : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                canRequestFocus: false,
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(8)),
                hoverColor: const Color(0xFFF1F5F9),
                onTap: () => onSelectProduct(p),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 15,
                        backgroundColor: p.isSoldByWeight
                            ? Colors.orange.shade50
                            : const Color(0xFFEEF2FF),
                        child: Icon(
                          p.isSoldByWeight
                              ? Icons.scale_rounded
                              : Icons.inventory_2_outlined,
                          size: 16,
                          color: p.isSoldByWeight
                              ? Colors.orange.shade700
                              : Colors.indigo.shade700,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Wrap(
                              spacing: 6,
                              runSpacing: 2,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (p.internalCode.isNotEmpty ||
                                    p.category?.name != null)
                                  Text(
                                    [
                                      if (p.internalCode.isNotEmpty)
                                        p.internalCode,
                                      if (p.category?.name != null)
                                        p.category!.name,
                                    ].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: stockBg,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: stockBorder),
                                  ),
                                  child: Text(
                                    stockText,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: stockFg,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (resolvedPrice.crossedOutPrice != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            '\$${resolvedPrice.crossedOutPrice!.toCurrency()}$unitSuffix',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ),
                      Text(
                        priceStr,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: resolvedPrice.hasActiveOffer
                              ? const Color(0xFFB45309)
                              : const Color(0xFF15803D),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        productActionIcon,
                        size: 17,
                        color: const Color(0xFF0F766E),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Container(width: 1, height: 24, color: const Color(0xFFE2E8F0)),
          _HoverCloseButton(
            buttonKey: ValueKey('remove_product_${p.id}'),
            size: 30,
            iconSize: 15,
            tooltip: 'Quitar del historial',
            borderRadius:
                const BorderRadius.horizontal(right: Radius.circular(8)),
            onTap: () => onRemoveProduct(p.id),
          ),
        ],
      ),
    );
  }
}

class _HoverCloseButton extends StatefulWidget {
  final Key? buttonKey;
  final double size;
  final double iconSize;
  final String tooltip;
  final BorderRadius borderRadius;
  final VoidCallback onTap;

  const _HoverCloseButton({
    this.buttonKey,
    required this.size,
    required this.iconSize,
    required this.tooltip,
    required this.borderRadius,
    required this.onTap,
  });

  @override
  State<_HoverCloseButton> createState() => _HoverCloseButtonState();
}

class _HoverCloseButtonState extends State<_HoverCloseButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: widget.buttonKey,
          canRequestFocus: false,
          borderRadius: widget.borderRadius,
          hoverColor: const Color(0xFFFEE2E2),
          splashColor: const Color(0xFFFECACA),
          onHover: (hovered) {
            if (_isHovered != hovered && mounted) {
              setState(() => _isHovered = hovered);
            }
          },
          onTap: widget.onTap,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Center(
              child: Icon(
                Icons.close_rounded,
                size: widget.iconSize,
                color: _isHovered
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF64748B),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
