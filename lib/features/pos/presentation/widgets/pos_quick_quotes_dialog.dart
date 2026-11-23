import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pos_provider.dart';
import 'package:frontend_desktop/features/quotes/presentation/providers/quote_provider.dart';
import 'package:frontend_desktop/features/quotes/presentation/widgets/quote_success_dialog.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/customers/providers/customer_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/core/presentation/widgets/plan_upgrade_dialog.dart';

class PosQuickQuotesDialog extends StatefulWidget {
  const PosQuickQuotesDialog({super.key});

  @override
  State<PosQuickQuotesDialog> createState() => _PosQuickQuotesDialogState();
}

class _PosQuickQuotesDialogState extends State<PosQuickQuotesDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late int _lastTabIndex;
  final TextEditingController _customerNameCtrl = TextEditingController();
  final TextEditingController _customerPhoneCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();
  final TextEditingController _searchQuotesCtrl = TextEditingController();

  bool _isSaving = false;

  void _onTabChanged() {
    if (!mounted) return;
    if (_lastTabIndex != _tabController.index) {
      _lastTabIndex = _tabController.index;
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    final pos = Provider.of<PosProvider>(context, listen: false);
    _lastTabIndex = pos.cart.isNotEmpty ? 0 : 1;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: _lastTabIndex,
    );
    _tabController.addListener(_onTabChanged);

    if (pos.selectedCustomer != null) {
      _customerNameCtrl.text = pos.selectedCustomer!.name;
      _customerPhoneCtrl.text = pos.selectedCustomer!.phone ?? '';
    }

    // Cargar presupuestos recientes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Provider.of<QuoteProvider>(context, listen: false).loadQuotes();
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
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
        final cleanMsg = e.toString().replaceAll('Exception: ', '').trim();
        if (cleanMsg.contains('FEATURE_NOT_LICENSED') ||
            cleanMsg.contains('módulo requerido') ||
            cleanMsg.contains('quotes')) {
          Navigator.of(context).pop();
          PlanUpgradeDialog.show(
            context,
            featureName: 'Presupuestos Rápidos',
            description:
                'La creación de presupuestos no está incluida en tu plan actual. Actualizá tu plan para emitir y guardar cotizaciones.',
          );
        } else {
          SnackBarService.error(context, cleanMsg);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    final showSaveFooter = _tabController.index == 0 && pos.cart.isNotEmpty;
    final itemCount = pos.cart.length;
    final itemWord = itemCount == 1 ? 'ítem' : 'ítems';

    return AppModalShell(
      title: 'Presupuestos Rápidos',
      subtitle: 'Generar o cargar presupuestos sin alterar stock físico',
      icon: Icons.request_quote_rounded,
      accent: AppModalAccent.indigo,
      maxWidth: 640,
      maxHeight: 560,
      expandBody: true,
      topBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        decoration: const BoxDecoration(
          color: AppColors.surfaceMuted,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Container(
          height: 40,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            indicator: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            labelColor: AppColors.indigo,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            tabs: const [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.save_outlined, size: 17),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Guardar Carrito',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.download_rounded, size: 17),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Recuperar Presupuesto',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bodyPadding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSaveTab(),
          _buildRecallTab(),
        ],
      ),
      footerLeading: showSaveFooter
          ? Text(
              '$itemCount $itemWord · Total \$${pos.cartSubtotal.toCurrency()}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            )
          : null,
      footerActions: showSaveFooter
          ? [
              TextButton(
                onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancelar (Esc)'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
                onPressed: _isSaving ? null : _handleSaveQuote,
                icon: _isSaving
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.save_rounded, size: 18),
                label: Text(
                  _isSaving ? 'Guardando...' : 'Generar y Guardar Presupuesto',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar (Esc)'),
              ),
            ],
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
                Icon(Icons.shopping_cart_outlined,
                    size: 50, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                const Text(
                  'El carrito está vacío',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Agregá productos al ticket actual para guardarlos como presupuesto.',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final productWord = pos.cart.length == 1 ? 'producto' : 'productos';

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.indigo.shade100),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${pos.cart.length} $productWord en el ticket',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade900,
                      ),
                    ),
                    Text(
                      'Total: \$${pos.cartSubtotal.toCurrency()}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.indigo.shade900,
                        fontSize: 16,
                      ),
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
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _customerPhoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Teléfono / WhatsApp (Opcional)',
                  prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Observaciones / Notas (Opcional)',
                  prefixIcon: const Icon(Icons.note_alt_outlined, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
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
                                  final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
                                  final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
                                  pos.loadQuoteToCart(q, settings: settingsProvider.settings, availableCustomers: customerProvider.customers);
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
