import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/core/utils/receipt_printer_service.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import '../providers/quote_provider.dart';
import '../../data/quote_repository.dart';
import '../../services/quote_pdf_service.dart';
import 'package:intl/intl.dart';

class QuoteScreen extends StatefulWidget {
  const QuoteScreen({super.key});

  @override
  State<QuoteScreen> createState() => _QuoteScreenState();
}

class _QuoteScreenState extends State<QuoteScreen> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  String _searchQuery = '';
  List<Product> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounceTimer;

  // Formulario del encabezado del presupuesto
  final _customerNameCtrl = TextEditingController();
  final _customerPhoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime? _validUntil;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocus.requestFocus();
      // Inyectar los factores globales de precios al provider de presupuestos
      final settings = context.read<SettingsProvider>().settings;
      if (settings != null) {
        final ws = settings.globalCardPercentage > 0
            ? 1.0 - (settings.globalCardPercentage / 100)
            : 0.85;
        final card = 1.0 + (settings.globalCardPercentage / 100);
        context.read<QuoteProvider>().setGlobalFactors(wholesale: ws, card: card);
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _customerNameCtrl.dispose();
    _customerPhoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() { _searchQuery = ''; _searchResults = []; _isSearching = false; });
      return;
    }
    setState(() => _searchQuery = q);
    _debounceTimer = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted || _searchQuery.isEmpty) return;
      setState(() => _isSearching = true);
      final results = await context.read<PosProvider>().search(q);
      if (!mounted) return;
      setState(() { _searchResults = results; _isSearching = false; });
    });
  }

  void _addProduct(Product product) {
    if (product.isSoldByWeight) {
      _showWeightDialog(product);
    } else {
      context.read<QuoteProvider>().addToCart(product);
      _searchCtrl.clear();
      setState(() { _searchQuery = ''; _searchResults = []; });
      _searchFocus.requestFocus();
    }
  }

  void _showWeightDialog(Product product) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: ctrl,
        builder: (ctx, val, __) {
          final valid = double.tryParse(val.text.replaceAll(',', '.')) != null &&
              double.parse(val.text.replaceAll(',', '.')) > 0;
          return AlertDialog(
            title: Text('Peso (Kg) - ${product.name}'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Kg', suffixText: 'KG'),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              FilledButton(
                onPressed: valid ? () {
                  final kg = double.parse(ctrl.text.replaceAll(',', '.'));
                  context.read<QuoteProvider>().addToCart(product, quantity: kg);
                  Navigator.pop(ctx);
                  _searchCtrl.clear();
                  setState(() { _searchQuery = ''; _searchResults = []; });
                  _searchFocus.requestFocus();
                } : null,
                child: const Text('Agregar'),
              ),
            ],
          );
        },
      ),
    );
  }

  // -- Generar el presupuesto ------------------------------------------------
  Future<void> _onGenerateQuote() async {
    final provider = context.read<QuoteProvider>();
    if (provider.cart.isEmpty) {
      SnackBarService.error(context, 'Agregue al menos un producto al presupuesto.');
      return;
    }

    // -- Diálogo de confirmación con datos del cliente ---------------------
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _QuoteHeaderDialog(
        nameCtrl: _customerNameCtrl,
        phoneCtrl: _customerPhoneCtrl,
        notesCtrl: _notesCtrl,
        validUntil: _validUntil,
        onValidUntilChanged: (d) => setState(() => _validUntil = d),
        total: provider.cartTotal,
      ),
    );

    if (confirmed != true || !mounted) return;

    final settings = context.read<SettingsProvider>().settings;
    final currentUser = context.read<AuthProvider>().currentUser;
    final userId = currentUser?['id'] != null ? int.tryParse(currentUser!['id'].toString()) : null;
    final vendorName = currentUser?['name'] ?? 'VENDEDOR';

    final quote = await provider.generateQuote(
      customerName: _customerNameCtrl.text.trim().isEmpty ? null : _customerNameCtrl.text.trim(),
      customerPhone: _customerPhoneCtrl.text.trim().isEmpty ? null : _customerPhoneCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      validUntil: _validUntil?.toIso8601String().substring(0, 10),
      userId: userId,
    );

    if (!mounted) return;

    if (quote == null) {
      SnackBarService.error(context, provider.errorMessage ?? 'Error al generar presupuesto.');
      return;
    }

    // -- PDF + WhatsApp -----------------------------------------------------
    await _showQuoteSuccessDialog(quote, settings?.companyName ?? 'Mi Negocio', settings, vendorName);
  }

  Future<void> _showQuoteSuccessDialog(
    Quote quote,
    String businessName,
    dynamic settings,
    String vendorName,
  ) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _QuoteSuccessDialog(
        quote: quote,
        businessName: businessName,
        businessAddress: settings?.address,
        businessPhone: settings?.phone,
        customerPhone: quote.customerPhone,
        vendorName: vendorName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlobalAppBar(currentRoute: '/quotes', title: 'Presupuestos'),
      body: Row(
        children: [
          // -- Panel Izquierdo: Buscador ------------------------------------
          Expanded(
            flex: 5,
            child: Column(
              children: [
                _buildSearchBar(),
                Expanded(child: _buildSearchResults()),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          // -- Panel Derecho: Carrito ---------------------------------------
          Expanded(
            flex: 4,
            child: _buildCart(),
          ),
        ],
      ),
    );
  }

  // ── Helpers de lista de precios (delegado al QuoteProvider) ─────────────────

  /// Para precios de preview en la grilla — lee el motor CartItem
  double _resolvePreviewPrice(Product p) {
    final qProvider = context.read<QuoteProvider>();
    switch (qProvider.activeTier) {
      case PriceTier.wholesale:
        if (p.priceWholesale != null && p.priceWholesale! > 0) return p.priceWholesale!;
        return p.sellingPrice * qProvider.wholesaleFactor;
      case PriceTier.card:
        if (p.priceCard != null && p.priceCard! > 0) return p.priceCard!;
        return p.sellingPrice * qProvider.cardFactor;
      case PriceTier.custom:
        return p.sellingPrice * qProvider.customFactor;
      case PriceTier.base:
        return p.sellingPrice;
    }
  }

  Widget _buildSearchBar() {
    return Consumer<QuoteProvider>(
      builder: (_, qProvider, __) {
        final settings = context.watch<SettingsProvider>();
        final hasMultiPrice = settings.features.multiplePrices;
        final tierColor = qProvider.activePriceListColor;
        final customTiers = settings.settings?.customPriceTiers ?? [];

        return Container(
          padding: const EdgeInsets.all(12),
          color: Colors.grey.shade50,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  onChanged: _onSearchChanged,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Buscar producto por nombre o código...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _isSearching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                        : _searchQuery.isNotEmpty
                            ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
                                _searchCtrl.clear();
                                setState(() { _searchQuery = ''; _searchResults = []; });
                              })
                            : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              if (hasMultiPrice) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: tierColor, width: 1.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _tierToKey(qProvider.activeTier, qProvider.customTierLabel),
                      icon: Icon(Icons.expand_more, color: tierColor, size: 18),
                      style: TextStyle(
                        color: tierColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      onChanged: (v) {
                        if (v == null) return;
                        switch (v) {
                          case 'base':
                            qProvider.setPriceTier(PriceTier.base);
                            break;
                          case 'wholesale':
                            qProvider.setPriceTier(PriceTier.wholesale);
                            break;
                          case 'card':
                            qProvider.setPriceTier(PriceTier.card);
                            break;
                          default:
                            // Lista custom del JSON
                            final t = customTiers.firstWhere(
                              (ct) => ct['name'] == v,
                              orElse: () => {'modifier': 0.0},
                            );
                            final mod = (t['modifier'] as num?)?.toDouble() ?? 0.0;
                            qProvider.setPriceTier(
                              PriceTier.custom,
                              customFactor: 1.0 + (mod / 100),
                              customLabel: v,
                            );
                        }
                      },
                      items: [
                        const DropdownMenuItem(value: 'base',      child: Text('Precio Base')),
                        const DropdownMenuItem(value: 'wholesale', child: Text('Mayorista')),
                        const DropdownMenuItem(value: 'card',      child: Text('Tarjeta')),
                        ...customTiers.map((ct) => DropdownMenuItem(
                          value: ct['name']?.toString() ?? '',
                          child: Text(ct['name']?.toString() ?? ''),
                        )),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _tierToKey(PriceTier tier, String? label) {
    switch (tier) {
      case PriceTier.wholesale: return 'wholesale';
      case PriceTier.card:      return 'card';
      case PriceTier.custom:    return label ?? 'base';
      case PriceTier.base:      return 'base';
    }
  }

  Widget _buildSearchResults() {
    final qProvider = context.watch<QuoteProvider>();
    if (_searchQuery.isEmpty) {
      return _buildQuickAccessGrid();
    }
    if (_searchResults.isEmpty && !_isSearching) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('Sin resultados para "$_searchQuery"', style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => _buildProductTile(_searchResults[i], qProvider),
    );
  }

  Widget _buildQuickAccessGrid() {
    final qProvider = context.watch<QuoteProvider>();
    final products = context.watch<CatalogProvider>().products;
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('Busca productos arriba', style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        childAspectRatio: 0.85,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: products.length,
      itemBuilder: (_, i) => _buildProductCard(products[i], qProvider),
    );
  }

  Widget _buildProductCard(Product p, QuoteProvider qProvider) {
    final tierColor = qProvider.activePriceListColor;
    final tierLabel = qProvider.activePriceListLabel;
    final price = _resolvePreviewPrice(p);
    final isBase = qProvider.activeTier == PriceTier.base;
    return InkWell(
      onTap: () => _addProduct(p),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: !isBase ? tierColor.withValues(alpha: 0.5) : Colors.grey.shade200,
            width: !isBase ? 1.5 : 1.0,
          ),
          borderRadius: BorderRadius.circular(10),
          color: Colors.white,
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(p.isSoldByWeight ? Icons.scale : Icons.inventory_2_outlined,
                size: 28, color: Colors.indigo.shade400),
            const SizedBox(height: 6),
            Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('\$${price.toCurrency()}',
                style: TextStyle(fontSize: 11, color: tierColor, fontWeight: FontWeight.bold)),
            if (!isBase)
              Container(
                margin: const EdgeInsets.only(top: 3),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: tierColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(tierLabel,
                    style: TextStyle(fontSize: 9, color: tierColor, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductTile(Product p, QuoteProvider qProvider) {
    final tierColor = qProvider.activePriceListColor;
    final tierLabel = qProvider.activePriceListLabel;
    final price = _resolvePreviewPrice(p);
    final isBase = qProvider.activeTier == PriceTier.base;
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        backgroundColor: p.isSoldByWeight ? Colors.orange.shade50 : Colors.indigo.shade50,
        child: Icon(p.isSoldByWeight ? Icons.scale : Icons.inventory_2_outlined,
            size: 18,
            color: p.isSoldByWeight ? Colors.orange.shade700 : Colors.indigo.shade700),
      ),
      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      subtitle: Row(
        children: [
          Text('\$${price.toCurrency()}',
              style: TextStyle(color: tierColor, fontSize: 12, fontWeight: FontWeight.bold)),
          if (!isBase)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: tierColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(tierLabel,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: tierColor)),
            ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.add_circle_outline, color: Colors.indigo),
        onPressed: () => _addProduct(p),
      ),
      onTap: () => _addProduct(p),
    );
  }


  // -- Carrito ---------------------------------------------------------------

  Widget _buildCart() {
    return Consumer<QuoteProvider>(
      builder: (_, provider, __) {
        final cart = provider.cart;
        final fmt = NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 2);

        return Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.indigo.shade700,
              ),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Presupuesto',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  if (cart.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('¿Limpiar presupuesto?'),
                          content: const Text('Se borrarán todos los ítems agregados.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: Colors.red),
                              onPressed: () { provider.clearCart(); Navigator.pop(context); },
                              child: const Text('Limpiar'),
                            ),
                          ],
                        ),
                      ),
                      icon: const Icon(Icons.delete_sweep, color: Colors.white70, size: 18),
                      label: const Text('Limpiar', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ),
                ],
              ),
            ),

            // Lista de ítems
            Expanded(
              child: cart.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text('Agregá productos para\ngenerar el presupuesto',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: cart.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => _buildCartItem(cart[i], provider),
                    ),
            ),

            // Total + Botón
            if (cart.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('TOTAL',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(fmt.format(provider.cartTotal),
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 22,
                                color: Colors.indigo.shade700)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.indigo.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: provider.isLoading ? null : _onGenerateQuote,
                        icon: provider.isLoading
                            ? const SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.description_rounded),
                        label: const Text('Generar Presupuesto',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCartItem(CartItem item, QuoteProvider provider) {
    final fmt = NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 2);
    final tierColor = provider.activePriceListColor;
    final tierLabel = provider.activePriceListLabel;
    final isBase = item.activeTier == PriceTier.base;
    return ListTile(
      dense: true,
      title: Text(item.product.name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          overflow: TextOverflow.ellipsis),
      subtitle: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${fmt.format(item.unitPrice)} x ${item.product.isSoldByWeight ? "${item.quantity.toQty()} kg" : item.quantity.toInt()}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          if (!isBase) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: tierColor.withValues(alpha: 0.1),
                border: Border.all(color: tierColor.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                item.customTierLabel ?? tierLabel,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: tierColor,
                ),
              ),
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(fmt.format(item.subtotal),
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            onPressed: () => provider.removeFromCart(item),
          ),
        ],
      ),
      onTap: () {
        final ctrl = TextEditingController(
          text: item.product.isSoldByWeight
              ? item.quantity.toQty()
              : item.quantity.toInt().toString(),
        );
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Editar cantidad - ${item.product.name}'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: item.product.isSoldByWeight ? 'Kg' : 'Cantidad',
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              FilledButton(
                onPressed: () {
                  final qty = double.tryParse(ctrl.text.replaceAll(',', '.'));
                  if (qty != null && qty > 0) {
                    provider.updateQuantity(item, qty);
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('Actualizar'),
              ),
            ],
          ),
        );
      },
    );
  }
}

// -- Diálogo de cabecera del presupuesto --------------------------------------

class _QuoteHeaderDialog extends StatefulWidget {
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController notesCtrl;
  final DateTime? validUntil;
  final ValueChanged<DateTime?> onValidUntilChanged;
  final double total;

  const _QuoteHeaderDialog({
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.notesCtrl,
    required this.validUntil,
    required this.onValidUntilChanged,
    required this.total,
  });

  @override
  State<_QuoteHeaderDialog> createState() => _QuoteHeaderDialogState();
}

class _QuoteHeaderDialogState extends State<_QuoteHeaderDialog> {
  late DateTime? _validUntil;

  @override
  void initState() {
    super.initState();
    _validUntil = widget.validUntil;
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 2);
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.description_outlined, color: Colors.indigo.shade700),
          const SizedBox(width: 8),
          const Text('Datos del Presupuesto'),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total del Presupuesto',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(fmt.format(widget.total),
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold,
                            color: Colors.indigo.shade700)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Datos del Cliente (Opcional)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: widget.nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre del cliente',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: widget.phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono (para WhatsApp)',
                  prefixIcon: Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(),
                  helperText: 'Ej: 5491123456789 (con código de país)',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  const Text('Válido hasta:', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(const Duration(days: 7)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        locale: const Locale('es', 'AR'),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.light(
                                primary: Colors.indigo.shade700, // Header bg color
                                onPrimary: Colors.white, // Header text color
                                onSurface: Colors.indigo.shade900, // Body text color
                              ),
                              textButtonTheme: TextButtonThemeData(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.indigo.shade700, // button text color
                                ),
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setState(() => _validUntil = picked);
                        widget.onValidUntilChanged(picked);
                      }
                    },
                    child: Text(
                      _validUntil != null
                          ? DateFormat('dd/MM/yyyy').format(_validUntil!)
                          : 'Seleccionar fecha',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: widget.notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Condiciones / Notas (Opcional)',
                  prefixIcon: Icon(Icons.notes_outlined),
                  border: OutlineInputBorder(),
                  hintText: 'Ej: Precios sujetos a disponibilidad de stock.',
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade700),
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.description_rounded),
          label: const Text('Generar'),
        ),
      ],
    );
  }
}

// -- Diálogo post-generación: PDF + WhatsApp -----------------------------------

class _QuoteSuccessDialog extends StatefulWidget {
  final Quote quote;
  final String businessName;
  final String? businessAddress;
  final String? businessPhone;
  final String? customerPhone;
  final String vendorName;

  const _QuoteSuccessDialog({
    required this.quote,
    required this.businessName,
    this.businessAddress,
    this.businessPhone,
    this.customerPhone,
    required this.vendorName,
  });

  @override
  State<_QuoteSuccessDialog> createState() => _QuoteSuccessDialogState();
}

class _QuoteSuccessDialogState extends State<_QuoteSuccessDialog> {
  bool _generatingPdf = false;
  String? _savedPath;
  final fmt = NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 2);

  Future<void> _printTicket() async {
    try {
      final settings = context.read<SettingsProvider>().settings;
      if (settings != null) {
        await ReceiptPrinterService.instance.printQuoteTicket(
          quote: widget.quote,
          settings: settings,
          localTerminal: context.read<LocalTerminalProvider>(),
          vendorName: widget.vendorName,
        );
      }
      if (mounted) Navigator.pop(context); // Cierra el modal exitosamente al imprimir el ticket
    } catch (e) {
      if (mounted) SnackBarService.error(context, e.toString());
    }
  }

  Future<void> _generateAndSave() async {
    setState(() => _generatingPdf = true);
    try {
      final path = await QuotePdfService.generateAndShare(
        quote: widget.quote,
        businessName: widget.businessName,
        businessAddress: widget.businessAddress,
        businessPhone: widget.businessPhone,
        vendorName: widget.vendorName,
      );
      if (mounted) setState(() { _generatingPdf = false; _savedPath = path; });
    } catch (e) {
      if (mounted) {
        setState(() => _generatingPdf = false);
        SnackBarService.error(context, e.toString());
      }
    }
  }

  Future<void> _preview() async {
    await QuotePdfService.preview(
      context: context,
      quote: widget.quote,
      businessName: widget.businessName,
      businessAddress: widget.businessAddress,
      businessPhone: widget.businessPhone,
      vendorName: widget.vendorName,
    );
  }

  Future<void> _openWhatsApp() async {
    await QuotePdfService.openWhatsApp(
      quote: widget.quote,
      businessName: widget.businessName,
      phone: widget.customerPhone,
      savedPdfPath: _savedPath,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header verde/indigo
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.indigo.shade700,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 48),
                  const SizedBox(height: 8),
                  const Text('¡Presupuesto Generado!',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 4),
                  Text(widget.quote.quoteNumber,
                      style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  Text(fmt.format(widget.quote.total),
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 🖨️ Botón Primario: Imprimir Ticket (Térmica)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _printTicket,
                    icon: const Icon(Icons.print_rounded, size: 28),
                    label: const Text('Imprimir Ticket (Térmica)', style: TextStyle(fontSize: 16)),
                  ),
                  
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  
                  // Botones Secundarios
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            foregroundColor: Colors.indigo.shade700,
                          ),
                          onPressed: _preview,
                          icon: const Icon(Icons.picture_as_pdf_rounded),
                          label: const Text('Ver PDF (A4)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _generatingPdf 
                          ? const Center(child: CircularProgressIndicator()) 
                          : OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                foregroundColor: const Color(0xFF25D366),
                              ),
                              onPressed: () async {
                                if (_savedPath == null) await _generateAndSave();
                                await _openWhatsApp();
                              },
                              icon: const Icon(Icons.rocket_launch_rounded),
                              label: const Text('WhatsApp'),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  // Ya no usamos el método _stepCard, al rediseñar la vista
}

