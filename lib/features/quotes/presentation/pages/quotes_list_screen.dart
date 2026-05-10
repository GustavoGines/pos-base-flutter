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

// ─── Utilidades de estado ────────────────────────────────────────────────────

/// Calcula el estado "visual" de un presupuesto, incluyendo la expiración
/// por fecha (que en BD sigue siendo 'pending' pero ya venció).
String resolveDisplayStatus(Quote quote) {
  if (quote.status != 'pending') return quote.status;
  if (quote.validUntil != null) {
    final validDate = DateTime.tryParse(quote.validUntil!);
    if (validDate != null && DateTime.now().isAfter(validDate)) {
      return 'expired';
    }
  }
  return 'pending';
}

Color statusColor(String status) {
  switch (status) {
    case 'approved':  return const Color(0xFF388E3C); // verde
    case 'rejected':  return const Color(0xFFD32F2F); // rojo
    case 'expired':   return const Color(0xFFF57C00); // naranja
    case 'pending':
    default:          return const Color(0xFF1565C0); // azul
  }
}

String statusLabel(String status) {
  switch (status) {
    case 'approved':  return 'Cobrado';
    case 'rejected':  return 'Rechazado';
    case 'expired':   return 'Vencido';
    case 'pending':
    default:          return 'Pendiente';
  }
}

// ─── Pantalla principal ──────────────────────────────────────────────────────

class QuotesListScreen extends StatefulWidget {
  const QuotesListScreen({super.key});

  @override
  State<QuotesListScreen> createState() => _QuotesListScreenState();
}

class _QuotesListScreenState extends State<QuotesListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchCtrl = TextEditingController();

  // Multi-select
  final Set<int> _selected = {};
  bool _bulkLoading = false;

  static const _tabs = [
    Tab(text: 'Todos'),
    Tab(text: 'Pendientes'),
    Tab(text: 'Aprobados'),
    Tab(text: 'Rechazados'),
    Tab(text: 'Vencidos'),
  ];

  static const _statusMap = <String?>[
    null,
    'pending',
    'approved',
    'rejected',
    'expired',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() { _selected.clear(); });
        _loadData();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    final status = _statusMap[_tabController.index];
    await context.read<QuoteProvider>().loadQuotes(
      search: _searchCtrl.text.trim(),
      status: status,
    );
  }

  void _toggleItem(int id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _selectAll(List<Quote> quotes) {
    setState(() {
      if (_selected.length == quotes.length) {
        _selected.clear();
      } else {
        _selected.addAll(quotes.map((q) => q.id));
      }
    });
  }

  Future<void> _bulkReject(List<Quote> allQuotes) async {
    final toReject = allQuotes.where((q) => _selected.contains(q.id) && q.status == 'pending').toList();
    if (toReject.isEmpty) {
      SnackBarService.error(context, 'Ninguno de los seleccionados puede ser rechazado.');
      return;
    }
    setState(() => _bulkLoading = true);
    final provider = context.read<QuoteProvider>();
    for (final q in toReject) {
      await provider.updateQuoteStatus(q.id, 'rejected');
    }
    if (!mounted) return;
    setState(() { _bulkLoading = false; _selected.clear(); });
    await _loadData();
    if (mounted) SnackBarService.success(context, '${toReject.length} presupuesto(s) rechazados.');
  }

  Future<void> _bulkDelete(List<Quote> allQuotes) async {
    final toDelete = allQuotes.where((q) => _selected.contains(q.id) && q.status != 'approved').toList();
    if (toDelete.isEmpty) {
      SnackBarService.error(context, 'No se pueden eliminar presupuestos ya cobrados.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar seleccionados?'),
        content: Text('Se eliminarán ${toDelete.length} presupuesto(s). Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _bulkLoading = true);
    final provider = context.read<QuoteProvider>();
    for (final q in toDelete) {
      await provider.deleteQuote(q.id);
    }
    if (!mounted) return;
    setState(() { _bulkLoading = false; _selected.clear(); });
    await _loadData();
    if (mounted) SnackBarService.success(context, '${toDelete.length} presupuesto(s) eliminados.');
  }

  void _openQuoteCreation() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QuoteScreen()),
    ).then((_) {
      if (mounted) _loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: const GlobalAppBar(
        currentRoute: '/quotes',
        title: 'Historial de Presupuestos',
      ),
      body: Column(
        children: [
          // ── Header + Filtros ──────────────────────────────────────────────
          _buildHeader(),
          // ── Lista ─────────────────────────────────────────────────────────
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Consumer<QuoteProvider>(
      builder: (_, provider, __) {
        final quotes = provider.quotes;
        final inBulk = _selected.isNotEmpty;

        return Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: inBulk
              // ── Bulk action bar ────────────────────────────────────────────
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.indigo.shade200),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => setState(() => _selected.clear()),
                        tooltip: 'Cancelar selección',
                        visualDensity: VisualDensity.compact,
                      ),
                      Text(
                        '${_selected.length} seleccionado(s)',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade800, fontSize: 15),
                      ),
                      const Spacer(),
                      const SizedBox(width: 4),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(color: Colors.red.shade300),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _bulkLoading ? null : () => _bulkReject(quotes),
                        icon: const Icon(Icons.cancel_outlined, size: 18),
                        label: const Text('Rechazar', style: TextStyle(fontSize: 14)),
                      ),
                      const SizedBox(width: 6),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _bulkLoading ? null : () => _bulkDelete(quotes),
                        icon: _bulkLoading
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Eliminar', style: TextStyle(fontSize: 14)),
                      ),
                    ],
                  ),
                )
              // ── Toolbar normal (todo en una sola fila) ─────────────────────
              : Row(
                  children: [
                    // Título compacto
                    Text(
                      'Presupuestos',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey.shade800,
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Buscador (ancho fijo)
                    SizedBox(
                      width: 250,
                      height: 38,
                      child: TextField(
                        controller: _searchCtrl,
                        style: const TextStyle(fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Buscar...',
                          hintStyle: const TextStyle(fontSize: 15),
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () { _searchCtrl.clear(); _loadData(); },
                                  padding: EdgeInsets.zero,
                                )
                              : null,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _loadData(),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Tabs de filtro — ocupa el espacio restante
                    Expanded(
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        tabs: _tabs,
                        labelColor: Colors.indigo.shade700,
                        unselectedLabelColor: Colors.grey.shade600,
                        indicatorColor: Colors.indigo.shade700,
                        dividerColor: Colors.transparent,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 16),
                        labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        unselectedLabelStyle: const TextStyle(fontSize: 15),
                      ),
                    ),

                    // Botón nuevo
                    FilledButton.icon(
                      onPressed: _openQuoteCreation,
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('Nuevo', style: TextStyle(fontSize: 15)),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.indigo.shade700,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildList() {
    return Consumer<QuoteProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.errorMessage != null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_rounded, size: 64, color: Colors.red.shade300),
                const SizedBox(height: 16),
                Text(
                  'No se pudo cargar los presupuestos',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    provider.errorMessage!.replaceFirst('Exception: ', ''),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
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
                const SizedBox(height: 12),
                Text(
                  'No hay presupuestos en esta categoría',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _openQuoteCreation,
                  icon: const Icon(Icons.add),
                  label: const Text('Crear el primero'),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            // Cabecera de lista fija (Seleccionar todo)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: Checkbox(
                      value: _selected.length == provider.quotes.length && provider.quotes.isNotEmpty,
                      onChanged: (_) => _selectAll(provider.quotes),
                      activeColor: Colors.indigo.shade700,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'Seleccionar todo',
                    style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadData,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: provider.quotes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (ctx, i) {
                    final q = provider.quotes[i];
                    return _QuoteCard(
                      quote: q,
                      onRefresh: _loadData,
                      isSelected: _selected.contains(q.id),
                      onToggle: () => _toggleItem(q.id),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Tarjeta de Presupuesto ──────────────────────────────────────────────────

class _QuoteCard extends StatelessWidget {
  final Quote quote;
  final VoidCallback onRefresh;
  final bool isSelected;
  final VoidCallback onToggle;

  const _QuoteCard({
    required this.quote,
    required this.onRefresh,
    this.isSelected = false,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final display = resolveDisplayStatus(quote);
    final color = statusColor(display);
    final label = statusLabel(display);

    final dateObj = quote.createdAt != null
        ? DateTime.tryParse(quote.createdAt!)
        : null;
    final dateStr = dateObj != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(dateObj)
        : '-';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? Colors.indigo.shade400 : Colors.grey.shade200,
          width: isSelected ? 2 : 1,
        ),
      ),
      color: isSelected ? Colors.indigo.shade50 : null,
      child: InkWell(
        onTap: () => _showActionSheet(context, display),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Row(
            children: [
              // Checkbox siempre visible
              SizedBox(
                width: 32,
                height: 32,
                child: Checkbox(
                  value: isSelected,
                  onChanged: (_) => onToggle(),
                  activeColor: Colors.indigo.shade700,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 4),

              // Ícono de estado
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.description_rounded, color: color, size: 17),
              ),
              const SizedBox(width: 10),

              // Número + estado
              SizedBox(
                width: 170,
                child: Row(
                  children: [
                    Text(
                      quote.quoteNumber,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(width: 8),
                    _StatusBadge(label: label, color: color),
                  ],
                ),
              ),

              // Cliente
              Expanded(
                flex: 2,
                child: Text(
                  quote.customerName?.isNotEmpty == true ? quote.customerName! : 'Consumidor Final',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Fecha + artículos
              Expanded(
                flex: 2,
                child: Text(
                  '$dateStr  •  ${quote.items.length} art.',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Monto
              SizedBox(
                width: 110,
                child: Text(
                  '\$${quote.total.toCurrency()}',
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),

              // Botón ⋮
              IconButton(
                icon: Icon(Icons.more_vert, color: Colors.grey.shade500, size: 20),
                padding: const EdgeInsets.only(left: 4),
                constraints: const BoxConstraints(),
                onPressed: () => _showActionSheet(context, display),
                tooltip: 'Acciones',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showActionSheet(BuildContext context, String displayStatus) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuoteActionSheet(
        quote: quote,
        displayStatus: displayStatus,
        onRefresh: onRefresh,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ─── Panel de Acciones (Bottom Sheet) ────────────────────────────────────────

class _QuoteActionSheet extends StatefulWidget {
  final Quote quote;
  final String displayStatus;
  final VoidCallback onRefresh;

  const _QuoteActionSheet({
    required this.quote,
    required this.displayStatus,
    required this.onRefresh,
  });

  @override
  State<_QuoteActionSheet> createState() => _QuoteActionSheetState();
}

class _QuoteActionSheetState extends State<_QuoteActionSheet> {
  bool _loadingWhatsApp = false;
  bool _loadingReject  = false;
  bool _loadingEdit    = false;
  bool _loadingDelete  = false;

  bool _loadingCharge = false;

  // ── Cobrar en caja (con fetch de productos actualizados) ──────────────────
  Future<void> _handleCharge() async {
    setState(() => _loadingCharge = true);
    try {
      // Necesitamos el presupuesto CON productos hidratados (el listado no los trae).
      // Esto también garantiza que los precios del carrito sean los del catálogo HOY.
      final fullQuote = await context.read<QuoteProvider>().repository
          .getQuoteById(widget.quote.id);

      if (!mounted) return;

      if (fullQuote == null) {
        SnackBarService.error(context, 'No se pudo recuperar el presupuesto.');
        setState(() => _loadingCharge = false);
        return;
      }

      // Verificar que tenga ítems con producto válido
      final validItems = fullQuote.items.where((i) => i.product != null).length;
      if (validItems == 0) {
        SnackBarService.error(
          context,
          'Algunos productos de este presupuesto ya no existen en el catálogo.',
        );
        setState(() => _loadingCharge = false);
        return;
      }

      final settings = context.read<SettingsProvider>().settings;
      context.read<PosProvider>().loadQuoteToCart(fullQuote, settings: settings);
      Navigator.pop(context);       // cierra el sheet
      Navigator.pushNamed(context, '/home'); // va al POS sin destruir el historial
    } catch (e) {
      if (mounted) {
        setState(() => _loadingCharge = false);
        SnackBarService.error(context, 'Error al cargar el presupuesto: $e');
      }
    }
  }

  // ── Vista previa PDF ──────────────────────────────────────────────────────
  Future<void> _handlePdfPreview() async {
    final settings = context.read<SettingsProvider>().settings;
    final vendorName = context.read<AuthProvider>().currentUser?['name'] ?? 'VENDEDOR';

    if (!mounted) return;
    await QuotePdfService.preview(
      context: context,
      quote: widget.quote,
      businessName: settings?.companyName ?? 'Mi Negocio',
      businessAddress: settings?.address,
      businessPhone: settings?.phone,
      vendorName: vendorName,
    );
  }

  // ── WhatsApp ──────────────────────────────────────────────────────────────
  Future<void> _handleWhatsApp() async {
    setState(() => _loadingWhatsApp = true);

    final settings = context.read<SettingsProvider>().settings;
    final businessName = settings?.companyName ?? 'Mi Negocio';

    try {
      final path = await QuotePdfService.generateAndShare(
        quote: widget.quote,
        businessName: businessName,
        businessAddress: settings?.address,
        businessPhone: settings?.phone,
        vendorName: null,
      );

      if (!mounted) return;

      await QuotePdfService.openWhatsApp(
        quote: widget.quote,
        businessName: businessName,
        phone: widget.quote.customerPhone,
        savedPdfPath: path,
      );
    } catch (e) {
      if (mounted) SnackBarService.error(context, e.toString());
    } finally {
      if (mounted) setState(() => _loadingWhatsApp = false);
    }
  }

  // ── Rechazar ──────────────────────────────────────────────────────────────
  Future<void> _handleReject() async {
    setState(() => _loadingReject = true);
    try {
      await context.read<QuoteProvider>().updateQuoteStatus(widget.quote.id, 'rejected');
      widget.onRefresh();
      if (!mounted) return;
      Navigator.pop(context);
      SnackBarService.success(context, 'Presupuesto marcado como rechazado.');
    } catch (e) {
      if (mounted) {
        setState(() => _loadingReject = false);
        SnackBarService.error(context, e.toString());
      }
    }
  }

  // ── Editar cabecera ───────────────────────────────────────────────────────
  Future<void> _handleEdit() async {
    final nameCtrl  = TextEditingController(text: widget.quote.customerName ?? '');
    final phoneCtrl = TextEditingController(text: widget.quote.customerPhone ?? '');
    final notesCtrl = TextEditingController(text: widget.quote.notes ?? '');
    DateTime? validUntil = widget.quote.validUntil != null
        ? DateTime.tryParse(widget.quote.validUntil!)
        : null;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Editar Presupuesto'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del cliente',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono',
                      prefixIcon: Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notas / Condiciones',
                      prefixIcon: Icon(Icons.notes_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 18, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          validUntil != null
                              ? 'Válido hasta: ${DateFormat('dd/MM/yyyy').format(validUntil!)}'
                              : 'Sin fecha de vencimiento',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: validUntil ?? DateTime.now().add(const Duration(days: 7)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setDialogState(() => validUntil = picked);
                          }
                        },
                        child: const Text('Cambiar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _loadingEdit = true);
    try {
      await context.read<QuoteProvider>().editQuote(
        widget.quote.id,
        customerName: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
        customerPhone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
        notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        validUntil: validUntil?.toIso8601String().substring(0, 10),
      );
      widget.onRefresh();
      if (!mounted) return;
      Navigator.pop(context); // cierra el action sheet
      SnackBarService.success(context, 'Presupuesto actualizado.');
    } catch (e) {
      if (mounted) {
        setState(() => _loadingEdit = false);
        SnackBarService.error(context, e.toString());
      }
    }
  }

  // ── Eliminar ──────────────────────────────────────────────────────────────
  Future<void> _handleDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar presupuesto?'),
        content: Text(
          'Se eliminará permanentemente el presupuesto ${widget.quote.quoteNumber}. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _loadingDelete = true);
    final success = await context.read<QuoteProvider>().deleteQuote(widget.quote.id);
    if (!mounted) return;

    if (success) {
      widget.onRefresh();
      Navigator.pop(context);
      SnackBarService.success(context, 'Presupuesto eliminado.');
    } else {
      setState(() => _loadingDelete = false);
      final msg = context.read<QuoteProvider>().errorMessage ?? 'Error al eliminar.';
      SnackBarService.error(context, msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = statusColor(widget.displayStatus);
    final label = statusLabel(widget.displayStatus);
    final isActionable = widget.displayStatus != 'approved' && widget.displayStatus != 'rejected';
    final fmt = NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 0);

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
            // ── Encabezado del panel ────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.quote.quoteNumber,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _StatusBadge(label: label, color: color),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Resumen ─────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.quote.customerName?.isNotEmpty == true
                              ? widget.quote.customerName!
                              : 'Consumidor Final',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        if (widget.quote.customerPhone?.isNotEmpty == true)
                          Text(
                            widget.quote.customerPhone!,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        if (widget.quote.validUntil != null)
                          Text(
                            'Válido hasta: ${DateFormat('dd/MM/yyyy').format(DateTime.parse(widget.quote.validUntil!))}',
                            style: TextStyle(
                              color: widget.displayStatus == 'expired'
                                  ? Colors.orange.shade700
                                  : Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    fmt.format(widget.quote.total),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                    ),
                  ),
                ],
              ),
            ),

            // ── Aviso para presupuestos vencidos ────────────────────────────
            if (widget.displayStatus == 'expired') ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Este presupuesto venció. Si lo cobrás, los precios se recalcularán automáticamente con los valores actuales del catálogo.',
                        style: TextStyle(
                          color: Colors.orange.shade800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // ── Cobrar en Caja ──────────────────────────────────────────────
            if (isActionable)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _loadingCharge ? null : _handleCharge,
                  icon: _loadingCharge
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.shopping_cart_checkout, size: 22),
                  label: Text(
                    _loadingCharge ? 'Cargando productos...' : 'Cobrar en Caja (ir al POS)',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),

            if (isActionable) const SizedBox(height: 12),

            // ── PDF y WhatsApp ──────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _handlePdfPreview,
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: const Text('Ver PDF'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: const Color(0xFF25D366),
                    ),
                    onPressed: _loadingWhatsApp ? null : _handleWhatsApp,
                    icon: _loadingWhatsApp
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chat_rounded),
                    label: const Text('WhatsApp'),
                  ),
                ),
              ],
            ),

            // ── Editar / Eliminar / Rechazar ────────────────────────────────
            if (widget.displayStatus != 'approved') ...[
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (isActionable) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          foregroundColor: Colors.indigo.shade700,
                        ),
                        onPressed: _loadingEdit ? null : _handleEdit,
                        icon: _loadingEdit
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.edit_outlined),
                        label: const Text('Editar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                      ),
                      onPressed: _loadingDelete ? null : _handleDelete,
                      icon: _loadingDelete
                          ? SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.red.shade700,
                              ),
                            )
                          : const Icon(Icons.delete_outline),
                      label: const Text('Eliminar'),
                    ),
                  ),
                ],
              ),
              if (isActionable) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _loadingReject ? null : _handleReject,
                    icon: _loadingReject
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red),
                          )
                        : const Icon(Icons.cancel_outlined),
                    label: const Text('Marcar como Rechazado'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
