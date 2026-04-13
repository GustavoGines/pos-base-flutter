import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
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

  void _addProduct(Product product, {double? overridePrice}) {
    if (product.isSoldByWeight) {
      _showWeightDialog(product, overridePrice: overridePrice);
    } else {
      context.read<QuoteProvider>().addToCart(product, overridePrice: overridePrice);
      _searchCtrl.clear();
      setState(() { _searchQuery = ''; _searchResults = []; });
      _searchFocus.requestFocus();
    }
  }

  void _showWeightDialog(Product product, {double? overridePrice}) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: ctrl,
        builder: (ctx, val, __) {
          final valid = double.tryParse(val.text.replaceAll(',', '.')) != null &&
              double.parse(val.text.replaceAll(',', '.')) > 0;
          return AlertDialog(
            title: Text('Peso (Kg) � ${product.name}'),
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
                  context.read<QuoteProvider>().addToCart(product, quantity: kg, overridePrice: overridePrice);
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

    // -- Di�logo de confirmaci�n con datos del cliente ---------------------
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
    final userId = null; // TODO: pasar el userId real cuando se integre AuthProvider

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
    await _showQuoteSuccessDialog(quote, settings?.companyName ?? 'Mi Negocio', settings);
  }

  Future<void> _showQuoteSuccessDialog(
    quote_repository_Quote quote,
    String businessName,
    dynamic settings,
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

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.grey.shade50,
      child: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        onChanged: _onSearchChanged,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Buscar producto por nombre o c�digo...',
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
    );
  }

  Widget _buildSearchResults() {
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
      itemBuilder: (_, i) => _buildProductTile(_searchResults[i]),
    );
  }

  Widget _buildQuickAccessGrid() {
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
      itemBuilder: (_, i) => _buildProductCard(products[i]),
    );
  }

  Widget _buildProductCard(Product p) {
    final hasMultiplePrices = context.watch<SettingsProvider>().features.multiplePrices;
    return InkWell(
      onTap: () => _addProduct(p),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
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
            Text('\$${p.sellingPrice.toCurrency()}',
                style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.bold)),
            if (hasMultiplePrices && (p.priceWholesale != null || p.priceCard != null))
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => _showPriceSelector(p),
                child: Text('Ver precios', style: TextStyle(fontSize: 10, color: Colors.indigo.shade600)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductTile(Product p) {
    final hasMultiplePrices = context.watch<SettingsProvider>().features.multiplePrices;
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        backgroundColor: p.isSoldByWeight ? Colors.orange.shade50 : Colors.indigo.shade50,
        child: Icon(p.isSoldByWeight ? Icons.scale : Icons.inventory_2_outlined,
            size: 18,
            color: p.isSoldByWeight ? Colors.orange.shade700 : Colors.indigo.shade700),
      ),
      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      subtitle: Text('\$${p.sellingPrice.toCurrency()}',
          style: TextStyle(color: Colors.green.shade700, fontSize: 12)),
      trailing: hasMultiplePrices && (p.priceWholesale != null || p.priceCard != null)
          ? TextButton(
              onPressed: () => _showPriceSelector(p),
              child: const Text('Precios'),
            )
          : IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Colors.indigo),
              onPressed: () => _addProduct(p),
            ),
      onTap: () => _addProduct(p),
    );
  }

  /// Selector de lista de precios para ferreter�as
  void _showPriceSelector(Product p) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Seleccion� la lista de precio a aplicar:',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            _priceOption(ctx, p, 'Precio Venta (Cliente Final)', p.sellingPrice, Colors.green),
            if (p.priceWholesale != null)
              _priceOption(ctx, p, 'Precio Mayorista', p.priceWholesale!, Colors.indigo),
            if (p.priceCard != null)
              _priceOption(ctx, p, 'Precio Tarjeta', p.priceCard!, Colors.teal),
          ],
        ),
      ),
    );
  }

  Widget _priceOption(BuildContext ctx, Product p, String label, double price, Color color) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.1),
        child: Icon(Icons.sell_outlined, color: color, size: 20),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: Text('\$${price.toCurrency()}',
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15)),
      onTap: () {
        Navigator.pop(ctx);
        _addProduct(p, overridePrice: price);
      },
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
                          title: const Text('�Limpiar presupuesto?'),
                          content: const Text('Se borrar�n todos los �tems agregados.'),
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

            // Lista de �tems
            Expanded(
              child: cart.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text('Agreg� productos para\ngenerar el presupuesto',
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

            // Total + Bot�n
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

  Widget _buildCartItem(QuoteCartItem item, QuoteProvider provider) {
    final fmt = NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 2);
    return ListTile(
      dense: true,
      title: Text(item.product.name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          overflow: TextOverflow.ellipsis),
      subtitle: Text('${fmt.format(item.unitPrice)} � ${item.product.isSoldByWeight ? "${item.quantity.toQty()} kg" : item.quantity.toInt()}',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
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
        // Editar cantidad
        final ctrl = TextEditingController(
          text: item.product.isSoldByWeight
              ? item.quantity.toQty()
              : item.quantity.toInt().toString(),
        );
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Editar cantidad � ${item.product.name}'),
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

// -- Typedef alias para evitar conflicto de nombres ----------------------------
typedef quote_repository_Quote = Quote;

// -- Di�logo de cabecera del presupuesto --------------------------------------

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
                  labelText: 'Tel�fono (para WhatsApp)',
                  prefixIcon: Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(),
                  helperText: 'Ej: 5491123456789 (con c�digo de pa�s)',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  const Text('V�lido hasta:', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(const Duration(days: 7)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
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

// -- Di�logo post-generaci�n: PDF + WhatsApp -----------------------------------

class _QuoteSuccessDialog extends StatefulWidget {
  final Quote quote;
  final String businessName;
  final String? businessAddress;
  final String? businessPhone;
  final String? customerPhone;

  const _QuoteSuccessDialog({
    required this.quote,
    required this.businessName,
    this.businessAddress,
    this.businessPhone,
    this.customerPhone,
  });

  @override
  State<_QuoteSuccessDialog> createState() => _QuoteSuccessDialogState();
}

class _QuoteSuccessDialogState extends State<_QuoteSuccessDialog> {
  bool _generatingPdf = false;
  String? _savedPath;
  final fmt = NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 2);

  Future<void> _generateAndSave() async {
    setState(() => _generatingPdf = true);
    try {
      final path = await QuotePdfService.generateAndShare(
        quote: widget.quote,
        businessName: widget.businessName,
        businessAddress: widget.businessAddress,
        businessPhone: widget.businessPhone,
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
            // Header verde
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
                  const Text('�Presupuesto Generado!',
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
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Paso 1: PDF
                  _stepCard(
                    step: '1',
                    icon: Icons.picture_as_pdf_outlined,
                    color: Colors.red,
                    title: 'Generar y guardar PDF',
                    subtitle: _savedPath != null ? 'Guardado en: ${_savedPath!.split(RegExp(r'[/\\]')).last}' : 'Clic para generar el comprobante',
                    action: _generatingPdf
                        ? const SizedBox(width: 24, height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : FilledButton.icon(
                            onPressed: _generateAndSave,
                            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: Text(_savedPath != null ? 'Guardar de nuevo' : 'Guardar PDF'),
                          ),
                  ),
                  const SizedBox(height: 12),
                  // Paso 1b: Preview
                  _stepCard(
                    step: '?',
                    icon: Icons.preview_outlined,
                    color: Colors.blueGrey,
                    title: 'Ver preview (impresi�n)',
                    subtitle: 'Abre el visor de impresi�n del sistema',
                    action: OutlinedButton.icon(
                      onPressed: _preview,
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Ver / Imprimir'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Paso 2: WhatsApp
                  _stepCard(
                    step: '2',
                    icon: Icons.chat_outlined,
                    color: const Color(0xFF25D366),
                    title: 'Compartir por WhatsApp',
                    subtitle: _savedPath != null
                        ? 'Abre WhatsApp con mensaje prearmado.\nArrastr� el PDF guardado al chat.'
                        : 'Primero guard� el PDF (Paso 1)',
                    action: FilledButton.icon(
                      onPressed: _savedPath != null ? _openWhatsApp : null,
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text('Abrir WhatsApp'),
                    ),
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

  Widget _stepCard({
    required String step,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required Widget action,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.15),
            radius: 18,
            child: Text(step, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          action,
        ],
      ),
    );
  }
}

