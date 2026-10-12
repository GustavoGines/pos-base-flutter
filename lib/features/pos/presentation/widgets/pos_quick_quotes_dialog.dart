import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pos_provider.dart';
import 'package:frontend_desktop/features/quotes/presentation/providers/quote_provider.dart';
import 'package:frontend_desktop/features/quotes/presentation/widgets/quote_success_dialog.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';

class PosQuickQuotesDialog extends StatefulWidget {
  const PosQuickQuotesDialog({super.key});

  @override
  State<PosQuickQuotesDialog> createState() => _PosQuickQuotesDialogState();
}

class _PosQuickQuotesDialogState extends State<PosQuickQuotesDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _customerNameCtrl = TextEditingController();
  final TextEditingController _customerPhoneCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();
  final TextEditingController _searchQuotesCtrl = TextEditingController();

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final pos = Provider.of<PosProvider>(context, listen: false);
    _tabController = TabController(length: 2, vsync: this, initialIndex: pos.cart.isNotEmpty ? 0 : 1);

    if (pos.selectedCustomer != null) {
      _customerNameCtrl.text = pos.selectedCustomer!.name;
      _customerPhoneCtrl.text = pos.selectedCustomer!.phone ?? '';
    }

    // Cargar presupuestos recientes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<QuoteProvider>(context, listen: false).loadQuotes();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _customerNameCtrl.dispose();
    _customerPhoneCtrl.dispose();
    _notesCtrl.dispose();
    _searchQuotesCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSaveQuote() async {
    final pos = Provider.of<PosProvider>(context, listen: false);
    final quoteProv = Provider.of<QuoteProvider>(context, listen: false);

    if (pos.cart.isEmpty) {
      SnackBarService.warning(context, 'El carrito está vacío. Agregá productos para presupuestar.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final quote = await pos.saveCurrentCartAsQuote(
        quoteRepository: quoteProv.repository,
        customerName: _customerNameCtrl.text.trim().isNotEmpty ? _customerNameCtrl.text.trim() : null,
        customerPhone: _customerPhoneCtrl.text.trim().isNotEmpty ? _customerPhoneCtrl.text.trim() : null,
        notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
      );

      if (quote != null && mounted) {
        final settings = context.read<SettingsProvider>().settings;
        final auth = context.read<AuthProvider>();
        final vendorName = auth.currentUser?['name'] ?? 'Vendedor';
        final businessName = settings?.companyName ?? 'Mi Negocio';

        Navigator.of(context).pop();

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => QuoteSuccessDialog(
            quote: quote,
            businessName: businessName,
            businessAddress: settings?.address,
            businessPhone: settings?.phone,
            customerPhone: quote.customerPhone,
            vendorName: vendorName,
          ),
        );
      } else if (mounted) {
        SnackBarService.error(context, 'No se pudo generar el presupuesto.');
      }
    } catch (e) {
      if (mounted) {
        SnackBarService.error(context, 'Error al guardar presupuesto: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        width: 620,
        height: 520,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Cabecera
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3F51B5).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.request_quote_rounded, color: Color(0xFF3F51B5), size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Presupuestos Rápidos',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Generar o cargar presupuestos sin alterar stock físico',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // TabBar
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4),
                  ],
                ),
                labelColor: const Color(0xFF3F51B5),
                unselectedLabelColor: Colors.grey.shade600,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                tabs: const [
                  Tab(text: '💾 Guardar Carrito'),
                  Tab(text: '📥 Recuperar Presupuesto'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // TabBarView
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildSaveTab(),
                  _buildRecallTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveTab() {
    return Consumer<PosProvider>(
      builder: (context, pos, _) {
        if (pos.cart.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_cart_outlined, size: 50, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                const Text(
                  'El carrito está vacío',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Agregá productos al ticket actual para guardarlos como presupuesto.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.indigo.shade100),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${pos.cart.length} productos en el ticket',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                    ),
                    Text(
                      'Total: \$${pos.cartSubtotal.toCurrency()}',
                      style: TextStyle(fontWeight: FontWeight.w900, color: Colors.indigo.shade900, fontSize: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _customerNameCtrl,
                decoration: InputDecoration(
                  labelText: 'Nombre del Cliente (Opcional)',
                  prefixIcon: const Icon(Icons.person_outline, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _customerPhoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Teléfono / WhatsApp (Opcional)',
                  prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Observaciones / Notas (Opcional)',
                  prefixIcon: const Icon(Icons.note_alt_outlined, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3F51B5),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _isSaving ? null : _handleSaveQuote,
                  icon: _isSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.save_rounded, size: 20),
                  label: Text(_isSaving ? 'Guardando...' : 'Generar y Guardar Presupuesto',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecallTab() {
    return Consumer<QuoteProvider>(
      builder: (context, quoteProv, _) {
        if (quoteProv.isLoading && quoteProv.quotes.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final query = _searchQuotesCtrl.text.toLowerCase().trim();
        final list = quoteProv.quotes.where((q) {
          if (query.isEmpty) return true;
          return q.quoteNumber.toLowerCase().contains(query) ||
              (q.customerName?.toLowerCase().contains(query) ?? false);
        }).toList();

        return Column(
          children: [
            TextField(
              controller: _searchQuotesCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar por # número o cliente...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Text(
                        'No hay presupuestos disponibles',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    )
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, index) {
                        final q = list[index];
                        final isDraft = q.status == 'draft' || q.status == 'pending';
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          title: Row(
                            children: [
                              Text(
                                '#${q.quoteNumber}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isDraft ? Colors.amber.shade50 : Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: isDraft ? Colors.amber.shade300 : Colors.green.shade300),
                                ),
                                child: Text(
                                  isDraft ? 'Pendiente' : q.status.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isDraft ? Colors.amber.shade900 : Colors.green.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            '${q.customerName ?? "Consumidor Final"} • ${q.items.length} ítems',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '\$${q.total.toCurrency()}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.tonal(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () {
                                  final pos = Provider.of<PosProvider>(context, listen: false);
                                  pos.loadQuoteToCart(q);
                                  Navigator.of(context).pop();
                                  SnackBarService.success(context, '📥 Presupuesto #${q.quoteNumber} cargado al carrito.');
                                },
                                child: const Text('Cargar', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
