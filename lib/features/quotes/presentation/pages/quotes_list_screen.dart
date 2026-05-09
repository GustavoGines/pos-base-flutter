import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import '../providers/quote_provider.dart';
import '../../data/quote_repository.dart';
import '../../services/quote_pdf_service.dart';
import 'quote_screen.dart';

class QuotesListScreen extends StatefulWidget {
  const QuotesListScreen({super.key});

  @override
  State<QuotesListScreen> createState() => _QuotesListScreenState();
}

class _QuotesListScreenState extends State<QuotesListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchCtrl = TextEditingController();
  
  final _tabs = const [
    Tab(text: 'Todos'),
    Tab(text: 'Pendientes'),
    Tab(text: 'Aprobados'),
    Tab(text: 'Rechazados'),
    Tab(text: 'Vencidos'),
  ];

  final _statusMap = [
    null,
    'pending',
    'approved',
    'rejected',
    'expired'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadData();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final provider = context.read<QuoteProvider>();
    final status = _statusMap[_tabController.index];
    await provider.loadQuotes(
      search: _searchCtrl.text.trim(),
      status: status,
    );
  }

  void _openQuoteCreation() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QuoteScreen()),
    ).then((_) => _loadData());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: const GlobalAppBar(currentRoute: '/quotes', title: 'Historial de Presupuestos'),
      body: Column(
        children: [
          // Header y Filtros
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Gestión de Presupuestos',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800),
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Nuevo Presupuesto'),
                      onPressed: _openQuoteCreation,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.indigo.shade600,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Buscar por número o cliente...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onSubmitted: (_) => _loadData(),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 3,
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        tabs: _tabs,
                        labelColor: Colors.indigo.shade700,
                        unselectedLabelColor: Colors.grey.shade600,
                        indicatorColor: Colors.indigo.shade700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Grilla
          Expanded(
            child: Consumer<QuoteProvider>(
              builder: (context, provider, _) {
                if (provider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (provider.errorMessage != null) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(provider.errorMessage!, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _loadData, child: const Text('Reintentar')),
                      ],
                    ),
                  );
                }

                if (provider.quotes.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.description_outlined, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text('No se encontraron presupuestos', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: provider.quotes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final quote = provider.quotes[index];
                    return _QuoteCard(quote: quote, onRefresh: _loadData);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  final Quote quote;
  final VoidCallback onRefresh;

  const _QuoteCard({required this.quote, required this.onRefresh});

  Color _getStatusColor(String status) {
    switch (status) {
      case 'approved': return Colors.green.shade600;
      case 'rejected': return Colors.red.shade600;
      case 'expired': return Colors.orange.shade600;
      case 'pending': default: return Colors.blue.shade600;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'approved': return 'Cobrado';
      case 'rejected': return 'Rechazado';
      case 'expired': return 'Vencido';
      case 'pending': default: return 'Pendiente';
    }
  }

  void _showQuoteDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _QuoteActionSheet(quote: quote, onRefresh: onRefresh),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final dateObj = quote.createdAt != null ? DateTime.tryParse(quote.createdAt!) : null;
    final dateStr = dateObj != null ? dateFormat.format(dateObj) : '-';
    
    // Check auto-expiration based on current date
    String displayStatus = quote.status;
    if (displayStatus == 'pending' && quote.validUntil != null) {
      final validDate = DateTime.tryParse(quote.validUntil!);
      if (validDate != null && DateTime.now().isAfter(validDate.add(const Duration(days: 1)))) {
        displayStatus = 'expired';
      }
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () => _showQuoteDetails(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icono
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getStatusColor(displayStatus).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.description, color: _getStatusColor(displayStatus)),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(quote.quoteNumber, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getStatusColor(displayStatus).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _getStatusColor(displayStatus).withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            _getStatusLabel(displayStatus),
                            style: TextStyle(color: _getStatusColor(displayStatus), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      quote.customerName?.isNotEmpty == true ? quote.customerName! : 'Consumidor Final',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$dateStr • ${quote.items.length} artículos',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Monto y Flecha
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$${quote.total.toCurrency()}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Icon(Icons.chevron_right, color: Colors.grey.shade400),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _QuoteActionSheet extends StatelessWidget {
  final Quote quote;
  final VoidCallback onRefresh;

  const _QuoteActionSheet({required this.quote, required this.onRefresh});

  Future<void> _handleCharge(BuildContext context) async {
    final posProvider = context.read<PosProvider>();
    posProvider.loadQuoteToCart(quote);
    Navigator.pop(context); // close sheet
    Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false); // goto POS
    SnackBarService.success(context, 'Presupuesto cargado. Listo para facturar.');
  }

  Future<void> _handlePdfPreview(BuildContext context) async {
    final settings = context.read<SettingsProvider>().settings;
    final currentUser = context.read<AuthProvider>().currentUser;
    final vendorName = currentUser?['name'] ?? 'VENDEDOR';
    
    await QuotePdfService.preview(
      context: context,
      quote: quote,
      businessName: settings?.companyName ?? 'Mi Negocio',
      businessAddress: settings?.address,
      businessPhone: settings?.phone,
      vendorName: vendorName,
    );
  }

  Future<void> _handleWhatsApp(BuildContext context) async {
    final settings = context.read<SettingsProvider>().settings;
    
    // Generar PDF y guardar
    final path = await QuotePdfService.generateAndShare(
      quote: quote,
      businessName: settings?.companyName ?? 'Mi Negocio',
      businessAddress: settings?.address,
      businessPhone: settings?.phone,
      vendorName: null,
    );
    
    // Abrir WP
    await QuotePdfService.openWhatsApp(
      quote: quote,
      businessName: settings?.companyName ?? 'Mi Negocio',
      phone: quote.customerPhone,
      savedPdfPath: path,
    );
  }

  Future<void> _handleReject(BuildContext context) async {
    final provider = context.read<QuoteProvider>();
    await provider.updateQuoteStatus(quote.id, 'rejected');
    onRefresh();
    Navigator.pop(context);
    SnackBarService.success(context, 'Presupuesto marcado como rechazado.');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(24),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Presupuesto ${quote.quoteNumber}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Cliente: ${quote.customerName?.isNotEmpty == true ? quote.customerName : 'Consumidor Final'}',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            
            // Acciones Principales
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: const Icon(Icons.shopping_cart_checkout),
                    label: const Text('Cobrar en Caja', style: TextStyle(fontSize: 16)),
                    onPressed: quote.status != 'approved' ? () => _handleCharge(context) : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Acciones Secundarias
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Ver PDF'),
                    onPressed: () => _handlePdfPreview(context),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      foregroundColor: Colors.green.shade700,
                    ),
                    icon: const Icon(Icons.chat),
                    label: const Text('WhatsApp'),
                    onPressed: () => _handleWhatsApp(context),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            if (quote.status == 'pending' || quote.status == 'expired')
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade600,
                  minimumSize: const Size.fromHeight(50),
                ),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Marcar como Rechazado (No compró)'),
                onPressed: () => _handleReject(context),
              )
          ],
        ),
      ),
    );
  }
}
