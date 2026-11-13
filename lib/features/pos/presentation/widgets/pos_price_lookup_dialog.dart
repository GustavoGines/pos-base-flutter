import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/services/remote_scanner_service.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/offers/presentation/providers/offer_provider.dart';
import 'package:frontend_desktop/features/pos/domain/services/product_pricing_calculator.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

/// Modal rápido de consulta de precios y stock sin agregar al carrito (`F5`).
/// Pensado para pistoleo continuo de códigos de barras o búsqueda por nombre.
class PosPriceLookupDialog extends StatefulWidget {
  final bool canAddToCart;
  final ValueChanged<String>? onQuickCreateRequested;
  final ValueChanged<String>? onAssociateBarcodeRequested;

  const PosPriceLookupDialog({
    super.key,
    this.canAddToCart = true,
    this.onQuickCreateRequested,
    this.onAssociateBarcodeRequested,
  });

  static Future<Product?> show(
    BuildContext context, {
    bool canAddToCart = true,
    ValueChanged<String>? onQuickCreateRequested,
    ValueChanged<String>? onAssociateBarcodeRequested,
  }) {
    return showDialog<Product>(
      context: context,
      barrierDismissible: true,
      builder: (_) => PosPriceLookupDialog(
        canAddToCart: canAddToCart,
        onQuickCreateRequested: onQuickCreateRequested,
        onAssociateBarcodeRequested: onAssociateBarcodeRequested,
      ),
    );
  }

  @override
  State<PosPriceLookupDialog> createState() => _PosPriceLookupDialogState();
}

class _PosPriceLookupDialogState extends State<PosPriceLookupDialog> {
  static final RegExp _barcodePattern =
      RegExp(r'^(?=.*\d)[A-Za-z0-9\-_]{5,32}$');

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  Timer? _debounce;
  bool _isSearching = false;
  String? _notFoundQuery;
  List<Product> _results = [];
  Product? _selectedProduct;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  bool _looksLikeBarcode(String raw) => _barcodePattern.hasMatch(raw.trim());

  void _triggerQuickCreate() {
    final q = _notFoundQuery?.trim();
    final cb = widget.onQuickCreateRequested;
    if (q == null || q.isEmpty || cb == null) return;
    Navigator.of(context).pop();
    cb(q);
  }

  void _triggerAssociateBarcode() {
    final q = _notFoundQuery?.trim();
    final cb = widget.onAssociateBarcodeRequested;
    if (q == null || q.isEmpty || cb == null) return;
    Navigator.of(context).pop();
    cb(q);
  }

  bool _handleKey(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.f3 &&
        _notFoundQuery != null &&
        widget.onQuickCreateRequested != null) {
      _triggerQuickCreate();
      return true;
    }
    return false;
  }

  List<Product> _searchLocalCatalog(String rawQuery) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return const [];

    try {
      final catalog = context.read<CatalogProvider>();
      final seenIds = <int>{};
      final combined = <Product>[];
      for (final source in [
        catalog.products,
        catalog.pinnedExtraProducts,
        catalog.weightOnlyProducts,
      ]) {
        for (final p in source) {
          if (seenIds.add(p.id) && p.active) {
            combined.add(p);
          }
        }
      }

      final exact = <Product>[];
      final partial = <Product>[];
      for (final p in combined) {
        final barcode = p.barcode?.trim().toLowerCase() ?? '';
        final code = p.internalCode.trim().toLowerCase();
        final name = p.name.trim().toLowerCase();
        if (barcode == q || code == q) {
          exact.add(p);
        } else if (name.contains(q) ||
            barcode.contains(q) ||
            code.contains(q)) {
          partial.add(p);
        }
      }
      return [...exact, ...partial].take(20).toList();
    } catch (_) {
      return const [];
    }
  }

  Product? _findExactBarcodeOrCode(List<Product> items, String rawQuery) =>
      RemoteScannerService.findExactProductMatch(items, rawQuery);

  void _handleRemoteBarcodeScan(String barcode) {
    final clean = barcode.trim();
    if (clean.isEmpty || !mounted) return;
    _searchCtrl.text = clean;
    _searchCtrl.selection = TextSelection.collapsed(offset: clean.length);
    _onSubmitted(clean);
  }

  void _onQueryChanged(String rawValue) {
    _debounce?.cancel();
    final q = rawValue.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
        _notFoundQuery = null;
      });
      return;
    }

    final local = _searchLocalCatalog(q);
    final exactLocal = _findExactBarcodeOrCode(local, q);
    setState(() {
      _results = local;
      _notFoundQuery = null;
      _isSearching = true;
      if (exactLocal != null) {
        _selectedProduct = exactLocal;
      } else if (local.length == 1) {
        _selectedProduct = local.first;
      }
    });

    _debounce = Timer(const Duration(milliseconds: 240), () async {
      await _executeRemoteSearch(q, selectOnSingleOrExact: exactLocal == null);
    });
  }

  Future<void> _onSubmitted(String rawValue) async {
    _debounce?.cancel();
    final q = rawValue.trim();
    if (q.isEmpty) return;

    final local = _searchLocalCatalog(q);
    final exactLocal = _findExactBarcodeOrCode(local, q);
    if (exactLocal != null) {
      _selectAndSelectTextForNextScan(exactLocal, local);
      return;
    }

    setState(() {
      _isSearching = true;
      _notFoundQuery = null;
    });
    await _executeRemoteSearch(q, selectOnSingleOrExact: true, fromSubmit: true);
  }

  Future<void> _executeRemoteSearch(
    String query, {
    bool selectOnSingleOrExact = true,
    bool fromSubmit = false,
  }) async {
    try {
      final catalog = context.read<CatalogProvider>();
      final remote = await catalog.searchProductsRemote(query, perPage: 20);
      if (!mounted) return;
      if (_searchCtrl.text.trim() != query) return;

      final mergedById = <int, Product>{};
      for (final p in _searchLocalCatalog(query)) {
        mergedById[p.id] = p;
      }
      for (final p in remote) {
        if (p.active) mergedById[p.id] = p;
      }
      final merged = mergedById.values.toList();
      final exact = _findExactBarcodeOrCode(merged, query);

      if (selectOnSingleOrExact && (exact != null || merged.length == 1)) {
        final chosen = exact ?? merged.first;
        if (fromSubmit) {
          _selectAndSelectTextForNextScan(chosen, merged);
        } else {
          setState(() {
            _results = merged;
            _selectedProduct = chosen;
            _isSearching = false;
            _notFoundQuery = null;
          });
        }
        return;
      }

      setState(() {
        _results = merged;
        _isSearching = false;
        _notFoundQuery = merged.isEmpty ? query : null;
        if (fromSubmit && merged.isNotEmpty) {
          _selectedProduct = merged.first;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          if (_results.isEmpty) _notFoundQuery = query;
        });
      }
    }
  }

  void _selectAndSelectTextForNextScan(Product product, List<Product> results) {
    setState(() {
      _results = results;
      _selectedProduct = product;
      _isSearching = false;
      _notFoundQuery = null;
    });
    _searchFocus.requestFocus();
    _searchCtrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchCtrl.text.length,
    );
  }

  void _resetLookup() {
    _debounce?.cancel();
    setState(() {
      _searchCtrl.clear();
      _results = [];
      _selectedProduct = null;
      _notFoundQuery = null;
      _isSearching = false;
    });
    _searchFocus.requestFocus();
  }

  String _formatIngredientQty(double qty) {
    if ((qty - qty.roundToDouble()).abs() < 0.0005) {
      return '${qty.round()}u';
    }
    return '${qty.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}u';
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    final offerProv = context.watch<OfferProvider>();
    final isResponsableInscripto =
        context.watch<SettingsProvider?>()?.settings?.isResponsableInscripto ??
            false;

    final product = _selectedProduct;
    final double dialogWidth =
        600.0.clamp(320.0, MediaQuery.of(context).size.width - 48);

    double? wholesalePrice;
    double? cardPrice;
    double? customPrice;
    double? promoPrice;
    String? promoName;

    if (product != null) {
      final discounted = offerProv.getDiscountedPrice(product);
      if (discounted != null &&
          discounted > 0 &&
          discounted < product.sellingPrice) {
        promoPrice = ProductPricingCalculator.roundMoney(discounted);
        promoName = offerProv
            .getActiveOfferForProduct(product.id, basePrice: product.sellingPrice)
            ?.name;
      }

      wholesalePrice = ProductPricingCalculator.calculate(
        product: product,
        activeTier: PriceTier.wholesale,
        wholesaleFactor: pos.wholesaleFactor,
        promotionalPrice: promoPrice,
        hasExplicitOffer: promoPrice != null,
        cardSurchargeOnOffersMode: pos.cardSurchargeOnOffersMode,
      ).tierCalculatedUnitPrice;

      cardPrice = ProductPricingCalculator.calculate(
        product: product,
        activeTier: PriceTier.card,
        cardFactor: pos.cardFactor,
        promotionalPrice: promoPrice,
        hasExplicitOffer: promoPrice != null,
        cardSurchargeOnOffersMode: pos.cardSurchargeOnOffersMode,
      ).finalUnitPrice;

      if ((pos.currentCustomFactor - 1.0).abs() > 0.0001) {
        customPrice = ProductPricingCalculator.calculate(
          product: product,
          activeTier: PriceTier.custom,
          customFactor: pos.currentCustomFactor,
          promotionalPrice: promoPrice,
          hasExplicitOffer: promoPrice != null,
          cardSurchargeOnOffersMode: pos.cardSurchargeOnOffersMode,
        ).finalUnitPrice;
      }
    }

    return RemoteScannerListener(
      debugLabel: 'PosPriceLookupDialog',
      onBarcodeScanned: _handleRemoteBarcodeScan,
      child: Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: SizedBox(
          width: dialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Fijo (Sticky): Header + Campo de escaneo/búsqueda
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 18, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2FE),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.qr_code_scanner_rounded,
                            color: Color(0xFF0284C7),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Consultar Precio sin Agregar (F5)',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Pistoleá el código de barras o buscá por nombre para verificar lista, oferta y stock',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded, size: 20),
                          tooltip: 'Cerrar (Esc)',
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Campo de escaneo/búsqueda (mantiene foco continuo en Enter USB)
                    TextField(
                      controller: _searchCtrl,
                      focusNode: _searchFocus,
                      autofocus: true,
                      onChanged: _onQueryChanged,
                      onEditingComplete: () {},
                      onSubmitted: _onSubmitted,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText:
                            'Escaneá código de barras o escribí nombre / SKU...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _isSearching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : (_searchCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded),
                                    tooltip: 'Limpiar',
                                    onPressed: _resetLookup,
                                  )
                                : null),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF0284C7),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),

              // Centro Scrolleable
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Lista de coincidencias múltiples
                      if (_results.length > 1) ...[
                  Container(
                    constraints: const BoxConstraints(maxHeight: 155),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Material(
                        type: MaterialType.transparency,
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _results.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, thickness: 0.6),
                          itemBuilder: (ctx, idx) {
                            final item = _results[idx];
                            final isSelected = product?.id == item.id;
                            return ListTile(
                              dense: true,
                              selected: isSelected,
                              selectedTileColor: const Color(0xFFE0F2FE),
                              title: Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '${(item.barcode != null && item.barcode!.trim().isNotEmpty) ? item.barcode! : (item.internalCode.trim().isNotEmpty ? item.internalCode : 'Sin código')} · Stock: ${item.stock.toUnitStockDisplay(isSoldByWeight: item.isSoldByWeight)}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: Text(
                                '\$${item.sellingPrice.toCurrency()}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              onTap: () =>
                                  _selectAndSelectTextForNextScan(item, _results),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],

                if (_notFoundQuery != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.search_off_rounded,
                                color: Colors.amber.shade900),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'No se encontró ningún producto activo para "$_notFoundQuery".',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (widget.onQuickCreateRequested != null ||
                            (widget.onAssociateBarcodeRequested != null &&
                                _looksLikeBarcode(_notFoundQuery!))) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (widget.onQuickCreateRequested != null)
                                ElevatedButton.icon(
                                  onPressed: _triggerQuickCreate,
                                  icon: const Icon(Icons.flash_on_rounded,
                                      size: 17),
                                  label: const Text('Producto Rápido (F3)'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF4F46E5),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                  ),
                                ),
                              if (widget.onAssociateBarcodeRequested != null &&
                                  _looksLikeBarcode(_notFoundQuery!))
                                OutlinedButton.icon(
                                  onPressed: _triggerAssociateBarcode,
                                  icon: const Icon(
                                      Icons.qr_code_scanner_rounded,
                                      size: 16),
                                  label:
                                      const Text('Asociar código a existente'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF92400E),
                                    side:
                                        BorderSide(color: Colors.amber.shade400),
                                    backgroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ] else if (product == null && _results.isEmpty && !_isSearching) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code_2_rounded,
                            size: 28, color: Color(0xFF64748B)),
                        SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            'Listo para escanear. No modifica tu carrito actual.',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (product != null) ...[
                  if (_results.length > 1) const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFBAE6FD)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Nombre y badges
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (product.isCombo)
                              _LookupBadge(
                                label: 'Combo / Pack',
                                color: Colors.deepPurple.shade700,
                                bgColor: Colors.deepPurple.shade50,
                              ),
                            if (product.isSoldByWeight)
                              _LookupBadge(
                                label: 'Venta por Peso (Kg)',
                                color: Colors.indigo.shade700,
                                bgColor: Colors.indigo.shade50,
                              ),
                            if (product.isService)
                              _LookupBadge(
                                label: 'Servicio',
                                color: Colors.teal.shade800,
                                bgColor: Colors.teal.shade50,
                              ),
                            if (isResponsableInscripto)
                              _LookupBadge(
                                label: product.ivaRate <= 0
                                    ? 'Exento 0%'
                                    : 'IVA ${product.ivaRate == product.ivaRate.roundToDouble() ? product.ivaRate.round() : product.ivaRate}%',
                                color: Colors.blueGrey.shade800,
                                bgColor: Colors.blueGrey.shade100,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          product.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                            if (product.barcode != null &&
                                product.barcode!.trim().isNotEmpty)
                              'EAN: ${product.barcode}',
                            if (product.internalCode.trim().isNotEmpty)
                              'Cód: ${product.internalCode}',
                          ].join(' · '),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Precio Principal + Oferta activa
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: promoPrice != null
                                        ? Colors.purple.shade300
                                        : const Color(0xFFBAE6FD),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      promoPrice != null
                                          ? 'PRECIO OFERTA HOY${promoName != null ? ' ($promoName)' : ''}'
                                          : 'PRECIO LISTA / MOSTRADOR',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        color: promoPrice != null
                                            ? Colors.purple.shade800
                                            : const Color(0xFF0369A1),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        if (promoPrice != null) ...[
                                          Text(
                                            '\$${product.sellingPrice.toCurrency()}',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.grey.shade500,
                                              decoration:
                                                  TextDecoration.lineThrough,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                        ],
                                        Flexible(
                                          child: Text(
                                            '\$${(promoPrice ?? product.sellingPrice).toCurrency()}${product.isSoldByWeight ? ' /Kg' : ''}',
                                            style: TextStyle(
                                              fontSize: 30,
                                              fontWeight: FontWeight.w900,
                                              color: promoPrice != null
                                                  ? const Color(0xFF7B1FA2)
                                                  : const Color(0xFF0F172A),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 14),
                              decoration: BoxDecoration(
                                color: product.isService
                                    ? Colors.teal.shade50
                                    : (product.stock > 0
                                        ? Colors.green.shade50
                                        : Colors.red.shade50),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: product.isService
                                      ? Colors.teal.shade200
                                      : (product.stock > 0
                                          ? Colors.green.shade200
                                          : Colors.red.shade200),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    'STOCK',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.blueGrey.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    product.isService
                                        ? 'Servicio'
                                        : product.stock.toUnitStockDisplay(
                                            isSoldByWeight:
                                                product.isSoldByWeight,
                                          ),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: product.isService
                                          ? Colors.teal.shade800
                                          : (product.stock > 0
                                              ? Colors.green.shade800
                                              : Colors.red.shade800),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Listas de precios
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (wholesalePrice != null)
                              _PriceTierCard(
                                label: 'Mayorista',
                                priceText:
                                    '\$${wholesalePrice.toCurrency()}${product.isSoldByWeight ? '/Kg' : ''}',
                              ),
                            if (cardPrice != null)
                              _PriceTierCard(
                                label: 'Tarjeta',
                                priceText:
                                    '\$${cardPrice.toCurrency()}${product.isSoldByWeight ? '/Kg' : ''}',
                              ),
                            if (customPrice != null)
                              _PriceTierCard(
                                label: (pos.customTierLabel ?? '').trim().isNotEmpty
                                    ? pos.customTierLabel!
                                    : 'Lista Pers.',
                                priceText:
                                    '\$${customPrice.toCurrency()}${product.isSoldByWeight ? '/Kg' : ''}',
                              ),
                          ],
                        ),

                        if (product.isCombo &&
                            product.comboIngredients != null &&
                            product.comboIngredients!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Composición del Combo:',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.deepPurple.shade800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: product.comboIngredients!.map((ing) {
                              final qty =
                                  (ing['quantity'] as num?)?.toDouble() ?? 1.0;
                              final name =
                                  ing['name']?.toString() ?? 'Ingrediente';
                              return Chip(
                                label: Text(
                                  '${_formatIngredientQty(qty)} $name',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                backgroundColor: Colors.deepPurple.shade50,
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              // Footer Fijo (Sticky)
              Container(
                padding: const EdgeInsets.fromLTRB(18, 12, 22, 14),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  borderRadius:
                      BorderRadius.vertical(bottom: Radius.circular(18)),
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _resetLookup,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Limpiar / Otra consulta'),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cerrar (Esc)'),
                        ),
                        if (product != null && widget.canAddToCart)
                          ElevatedButton.icon(
                            onPressed: () =>
                                Navigator.of(context).pop(product),
                            icon: const Icon(Icons.add_shopping_cart_rounded,
                                size: 18),
                            label: const Text('Agregar al carrito'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0284C7),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _LookupBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color bgColor;

  const _LookupBadge({
    required this.label,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _PriceTierCard extends StatelessWidget {
  final String label;
  final String priceText;

  const _PriceTierCard({
    required this.label,
    required this.priceText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            priceText,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}
