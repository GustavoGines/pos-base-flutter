import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/sales_history_provider.dart';
import '../../domain/entities/sale_record.dart';
import '../../../auth/presentation/widgets/admin_pin_dialog.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../users/presentation/providers/users_provider.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import 'package:frontend_desktop/core/utils/receipt_printer_service.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';

// ─── Helpers de presentación para métodos de pago ────────────────────────────

IconData _iconForCode(String code) {
  if (code.contains('efectivo') || code == 'cash') return Icons.payments_outlined;
  if (code.contains('debito') || code == 'card_debit') return Icons.credit_card;
  if (code.contains('credito') || code == 'card_credit') return Icons.credit_score;
  if (code.contains('transferencia') || code == 'transfer') return Icons.qr_code_2;
  if (code.contains('cuenta') || code == 'cuenta_corriente') return Icons.book_outlined;
  return Icons.money;
}

Color _colorForCode(String code) {
  if (code.contains('efectivo') || code == 'cash') return Colors.green.shade700;
  if (code.contains('debito') || code == 'card_debit') return Colors.blue.shade700;
  if (code.contains('credito') || code == 'card_credit') return Colors.indigo.shade700;
  if (code.contains('transferencia') || code == 'transfer') return Colors.teal.shade700;
  if (code.contains('cuenta') || code == 'cuenta_corriente') return Colors.purple.shade700;
  return Colors.blueGrey.shade700;
}

Color _bgForCode(String code) {
  if (code.contains('efectivo') || code == 'cash') return Colors.green.shade50;
  if (code.contains('debito') || code == 'card_debit') return Colors.blue.shade50;
  if (code.contains('credito') || code == 'card_credit') return Colors.indigo.shade50;
  if (code.contains('transferencia') || code == 'transfer') return Colors.teal.shade50;
  if (code.contains('cuenta') || code == 'cuenta_corriente') return Colors.purple.shade50;
  return Colors.blueGrey.shade50;
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  SaleRecord? _selectedSale;
  String _searchQuery = '';
  String _statusFilter = 'Todas'; // 'Todas', 'Activas', 'Anuladas'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SalesHistoryProvider>().loadSales();
      context.read<UsersProvider>().loadUsers();
    });
  }

  void _onSaleSelected(SaleRecord sale) {
    setState(() => _selectedSale = sale);
  }

  List<SaleRecord> _applyFilters(SalesHistoryProvider provider) {
    return provider.sales.where((sale) {
      // Filtro de estado
      if (_statusFilter == 'Activas' && sale.isVoided) return false;
      if (_statusFilter == 'Anuladas' && !sale.isVoided) return false;

      // Filtro de búsqueda por ticket ID
      if (_searchQuery.isNotEmpty) {
        final clean = _searchQuery.replaceFirst(RegExp(r'^0+'), '');
        final q = clean.isEmpty ? _searchQuery : clean;
        if (!sale.id.toString().contains(q)) return false;
      }

      // Filtro por método de pago (chip seleccionado)
      if (provider.methodFilter != null) {
        final hasMethod =
            sale.payments.any((p) => p.methodCode == provider.methodFilter);
        if (!hasMethod) return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SalesHistoryProvider>(
      builder: (context, provider, _) {
        // Mantener referencia actualizada del ticket seleccionado
        if (_selectedSale != null) {
          final updated =
              provider.sales.where((s) => s.id == _selectedSale!.id).firstOrNull;
          if (updated != null) _selectedSale = updated;
        }

        final filteredSales = _applyFilters(provider);

        return Scaffold(
          appBar: const GlobalAppBar(currentRoute: '/sales-history'),
          body: Row(
            children: [
              // ── Panel Izquierdo ─────────────────────────────────────────────
              Container(
                width: 400,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(right: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Column(
                  children: [
                    _FiltersPanel(
                      provider: provider,
                      statusFilter: _statusFilter,
                      onStatusChanged: (v) => setState(() {
                        _statusFilter = v;
                        _selectedSale = null;
                      }),
                      onSearchChanged: (v) => setState(() => _searchQuery = v.trim()),
                      onSaleDeselect: () => setState(() => _selectedSale = null),
                    ),

                    // ── Resumen financiero dinámico ────────────────────────
                    if (!provider.isLoading)
                      _FinancialSummaryPanel(provider: provider),

                    // Lista
                    if (provider.isLoading) const LinearProgressIndicator(),
                    Expanded(
                      child: filteredSales.isEmpty && !provider.isLoading
                          ? _EmptyStateList()
                          : ListView.separated(
                              itemCount: filteredSales.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1, indent: 64),
                              itemBuilder: (ctx, i) {
                                final sale = filteredSales[i];
                                return _SaleListTile(
                                  sale: sale,
                                  isSelected: _selectedSale?.id == sale.id,
                                  onTap: () => _onSaleSelected(sale),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),

              // ── Panel Derecho: Detalle ──────────────────────────────────────
              Expanded(
                child: Container(
                  color: Colors.grey.shade100,
                  child: _selectedSale == null
                      ? const _EmptyStateDetail()
                      : _TicketDetailPanel(
                          sale: _selectedSale!,
                          provider: provider,
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Panel de filtros ─────────────────────────────────────────────────────────

class _FiltersPanel extends StatelessWidget {
  final SalesHistoryProvider provider;
  final String statusFilter;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSaleDeselect;

  const _FiltersPanel({
    required this.provider,
    required this.statusFilter,
    required this.onStatusChanged,
    required this.onSearchChanged,
    required this.onSaleDeselect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Título section
          Row(
            children: [
              Icon(Icons.receipt_long, color: Colors.blueGrey.shade700, size: 18),
              const SizedBox(width: 8),
              Text(
                'REGISTRO DE VENTAS',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey.shade800,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Período
          const Text('Período:',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 12)),
          const SizedBox(height: 6),
          Consumer<AuthProvider>(builder: (context, auth, _) {
            final canViewGlobal = auth.hasPermission('view_global_history');
            return SegmentedButton<String>(
              segments: [
                const ButtonSegment(value: 'shift', label: Text('Turno')),
                if (canViewGlobal) ...const [
                  ButtonSegment(value: 'today', label: Text('Hoy')),
                  ButtonSegment(value: 'month', label: Text('Mes')),
                  ButtonSegment(value: 'year', label: Text('Año')),
                ],
              ],
              selected: {canViewGlobal ? provider.currentPeriod : 'shift'},
              onSelectionChanged: (set) {
                provider.loadSales(period: set.first);
                onSaleDeselect();
              },
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: Colors.blue.shade100,
                textStyle: const TextStyle(fontSize: 12),
              ),
            );
          }),

          // Cajero (solo admins)
          Consumer2<AuthProvider, UsersProvider>(
            builder: (context, auth, users, _) {
              if (!auth.hasPermission('view_global_history')) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Cajero:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey,
                            fontSize: 12)),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int?>(
                          value: provider.selectedUserId,
                          isExpanded: true,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          items: [
                            const DropdownMenuItem(
                                value: null, child: Text('Todos los cajeros')),
                            ...users.users.map((u) => DropdownMenuItem(
                                  value: u['id'] as int,
                                  child: Text(u['name'] ?? ''),
                                )),
                          ],
                          onChanged: (val) {
                            provider.setSelectedUserId(val);
                            onSaleDeselect();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 12),

          // Búsqueda + estado
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Buscar ticket #...',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300)),
                  ),
                  onChanged: onSearchChanged,
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Todas', icon: Icon(Icons.checklist, size: 16)),
                  ButtonSegment(
                      value: 'Activas', icon: Icon(Icons.check_circle_outline, size: 16)),
                  ButtonSegment(
                      value: 'Anuladas', icon: Icon(Icons.cancel_outlined, size: 16)),
                ],
                selected: {statusFilter},
                onSelectionChanged: (set) => onStatusChanged(set.first),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: Colors.white,
                  textStyle: const TextStyle(fontSize: 11),
                ),
                showSelectedIcon: false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Resumen financiero dinámico ─────────────────────────────────────────────

class _FinancialSummaryPanel extends StatelessWidget {
  final SalesHistoryProvider provider;
  const _FinancialSummaryPanel({required this.provider});

  @override
  Widget build(BuildContext context) {
    final byMethod = provider.totalByMethod;
    final methodNames = provider.methodNames;
    final selectedMethod = provider.methodFilter;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Chips filtrables por método
          if (byMethod.isNotEmpty) ...[
            Wrap(
              spacing: 6.0,
              runSpacing: 8.0,
              children: [
                // "Todos" chip
                _MethodChip(
                  label: 'Todos',
                  amount: provider.totalVentas,
                  icon: Icons.account_balance_wallet_outlined,
                  color: Colors.blueGrey.shade700,
                  bgColor: Colors.blueGrey.shade50,
                  isSelected: selectedMethod == null,
                  onTap: () => provider.setMethodFilter(null),
                  isTotal: true,
                ),
                ...byMethod.entries.map((entry) {
                  final code = entry.key;
                  final amount = entry.value;
                  final name = methodNames[code] ?? code;
                  return _MethodChip(
                    label: name,
                    amount: amount,
                    icon: _iconForCode(code),
                    color: _colorForCode(code),
                    bgColor: _bgForCode(code),
                    isSelected: selectedMethod == code,
                    onTap: () => provider.setMethodFilter(
                        selectedMethod == code ? null : code),
                  );
                }),
              ],
            ),
            // Recargos si hay
            if (provider.totalSurcharges > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 12, color: Colors.orange.shade600),
                    const SizedBox(width: 4),
                    Text(
                      'Recargos incluidos: \$${provider.totalSurcharges.toStringAsFixed(2)}',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade700,
                          fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _MethodChip extends StatelessWidget {
  final String label;
  final double amount;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isTotal;

  const _MethodChip({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.isSelected,
    required this.onTap,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? color : bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2))]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: isSelected ? Colors.white : color),
            const SizedBox(width: 5),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white70 : color,
                  ),
                ),
                Text(
                  '\$${amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: isTotal ? 13 : 12,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Lista de ventas ─────────────────────────────────────────────────────────

class _SaleListTile extends StatelessWidget {
  final SaleRecord sale;
  final bool isSelected;
  final VoidCallback onTap;

  const _SaleListTile(
      {required this.sale, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(sale.createdAt);
    final dateStr = DateFormat('dd/MM').format(sale.createdAt);
    final hasMultiplePayments = sale.payments.length > 1;

    return ListTile(
      selected: isSelected,
      selectedTileColor: Colors.blue.shade50,
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: sale.isVoided
            ? Colors.grey.shade300
            : (isSelected ? Colors.blue.shade600 : Colors.blue.shade100),
        foregroundColor: sale.isVoided
            ? Colors.grey.shade600
            : (isSelected ? Colors.white : Colors.blue.shade800),
        child: Text('#${sale.id}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '\$${sale.total.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: sale.isVoided ? Colors.grey : Colors.green.shade800,
              decoration: sale.isVoided ? TextDecoration.lineThrough : null,
            ),
          ),
          if (sale.isVoided)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(12)),
              child: const Text('ANULADA',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold)),
            )
          else
            Text('$timeStr Hs',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 3),
          // Métodos de pago como mini-chips
          if (sale.payments.isNotEmpty)
            Row(
              children: [
                ...sale.payments.take(3).map((p) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: _bgForCode(p.methodCode),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color:
                                  _colorForCode(p.methodCode).withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_iconForCode(p.methodCode),
                                size: 10, color: _colorForCode(p.methodCode)),
                            const SizedBox(width: 3),
                            Text(
                              hasMultiplePayments
                                  ? '\$${p.totalAmount.toStringAsFixed(0)}'
                                  : p.methodName,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: _colorForCode(p.methodCode),
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    )),
                if (sale.payments.length > 3)
                  Text('+${sale.payments.length - 3}',
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey.shade500)),
              ],
            ),
          const SizedBox(height: 3),
          Row(
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(
                  '${sale.items.length} ítem${sale.items.length != 1 ? 's' : ''}',
                  style:
                      TextStyle(color: Colors.grey.shade600, fontSize: 11)),
              const Spacer(),
              Text(dateStr,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
            ],
          ),
          if (sale.userName != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.person_outline,
                    size: 13, color: Colors.blueGrey.shade400),
                const SizedBox(width: 4),
                Text('${sale.userName}',
                    style: TextStyle(
                        color: Colors.blueGrey.shade500,
                        fontSize: 10,
                        fontStyle: FontStyle.italic)),
              ],
            ),
          ]
        ],
      ),
    );
  }
}

class _EmptyStateList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No hay ventas en este período.',
              style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

class _EmptyStateDetail extends StatelessWidget {
  const _EmptyStateDetail();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('Seleccioná un ticket de la lista',
              style:
                  TextStyle(color: Colors.grey.shade500, fontSize: 18)),
          const SizedBox(height: 8),
          Text('Podés ver su detalle y anularlo',
              style:
                  TextStyle(color: Colors.grey.shade400, fontSize: 14)),
        ],
      ),
    );
  }
}

// ─── Panel Derecho: Detalle del Ticket ───────────────────────────────────────

class _TicketDetailPanel extends StatelessWidget {
  final SaleRecord sale;
  final SalesHistoryProvider provider;

  const _TicketDetailPanel({required this.sale, required this.provider});

  Future<void> _handleVoid(BuildContext context) async {
    final authorized = await AdminPinDialog.verify(context,
        action: 'Anular Ticket #${sale.id}', permissionKey: 'void_sales');
    if (!authorized) return;
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
          const SizedBox(width: 10),
          const Text('Anular Ticket'),
        ]),
        content: Text.rich(
          TextSpan(
            style: Theme.of(ctx).textTheme.bodyMedium,
            children: [
              const TextSpan(text: '¿Está seguro de anular el ticket '),
              TextSpan(
                  text: '#${sale.id}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const TextSpan(text: ' por un total de '),
              TextSpan(
                  text: '\$${sale.total.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.red)),
              const TextSpan(text: '?\n\nEsta acción es irreversible. '),
              const TextSpan(
                  text:
                      'El stock de todos los productos será devuelto al inventario automáticamente.',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, Anular Ticket'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    final ok = await provider.voidSale(sale.id);
    if (context.mounted) {
      if (ok) {
        SnackBarService.success(
            context, 'Ticket #${sale.id} anulado con éxito. Stock restaurado.');
      } else {
        SnackBarService.error(
            context, provider.errorMessage ?? 'Error al anular el ticket.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr =
        DateFormat('dd/MM/yyyy HH:mm:ss').format(sale.createdAt);
    final hasSurcharge = sale.surchargeTotal > 0;

    return Column(
      children: [
        // ── Cabecera ──────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.black12)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ticket info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Ticket #${sale.id}',
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold)),
                        if (sale.isVoided) ...[
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: Colors.red.shade100,
                                borderRadius: BorderRadius.circular(4)),
                            child: Text('ANULADA',
                                style: TextStyle(
                                    color: Colors.red.shade800,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 13, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Text(dateStr,
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 13)),
                      if (sale.userName != null) ...[
                        const SizedBox(width: 16),
                        Icon(Icons.person_outline,
                            size: 13, color: Colors.blueGrey.shade600),
                        const SizedBox(width: 4),
                        Text('${sale.userName}',
                            style: TextStyle(
                                color: Colors.blueGrey.shade800,
                                fontWeight: FontWeight.w500,
                                fontSize: 13)),
                      ]
                    ]),
                  ],
                ),
              ),

              // Totales + métodos de pago
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Total con tachado si anulada
                  Text(
                    '\$${sale.total.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: sale.isVoided
                          ? Colors.grey.shade500
                          : Colors.green.shade700,
                      decoration:
                          sale.isVoided ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  // Recargos
                  if (hasSurcharge)
                    Text(
                      'incl. \$${sale.surchargeTotal.toStringAsFixed(2)} recargos',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade700,
                          fontStyle: FontStyle.italic),
                    ),
                  const SizedBox(height: 8),
                  // Desglose de pagos
                  ...sale.payments.map((p) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: _PaymentBadge(payment: p),
                      )),
                ],
              ),
            ],
          ),
        ),

        // ── Tabla de ítems ────────────────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ],
                border: Border.all(color: Colors.black12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: DataTable(
                  headingRowColor:
                      WidgetStateProperty.all(Colors.grey.shade50),
                  columns: const [
                    DataColumn(
                        label: Text('Producto',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Cant/Peso',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('P. Unitario',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Subtotal',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: sale.items.map((item) {
                    final textStyle = TextStyle(
                      color: sale.isVoided ? Colors.grey : Colors.black87,
                      decoration: sale.isVoided ? TextDecoration.lineThrough : null,
                    );
                    return DataRow(cells: [
                      DataCell(Text(item.productName, style: textStyle)),
                      DataCell(Text(
                          item.isSoldByWeight
                              ? '${item.quantity.toStringAsFixed(3)} Kg'
                              : '${item.quantity.toStringAsFixed(0)} u',
                          style: textStyle)),
                      DataCell(Text(
                          '\$${item.unitPrice.toStringAsFixed(2)}',
                          style: textStyle)),
                      DataCell(Text('\$${item.subtotal.toStringAsFixed(2)}',
                          style: textStyle.copyWith(
                              fontWeight: FontWeight.bold))),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ),
        ),

        // ── Footer de acciones ────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.black12)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.print_outlined),
                label: const Text('Imprimir Copia'),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16)),
                onPressed: () async {
                  final settings =
                      context.read<SettingsProvider>().settings;
                  if (settings != null) {
                    try {
                      final itemsParaImprimir = sale.items.map((item) {
                        return CartItem(
                          product: Product(
                            id: item.productId ?? 0,
                            name: item.productName,
                            sellingPrice: item.unitPrice,
                            costPrice: item.unitPrice,
                            isSoldByWeight: item.isSoldByWeight,
                            stock: 0,
                            internalCode: '',
                            barcode: '',
                            active: true,
                          ),
                          quantity: item.quantity,
                        );
                      }).toList();

                      await ReceiptPrinterService.instance.printSaleTicket(
                        items: itemsParaImprimir,
                        total: sale.total,
                        settings: settings,
                        paymentMethod: sale.paymentMethodLabel,
                        receiptNumber: sale.id.toString(),
                        userName: sale.userName,
                      );
                      if (context.mounted) {
                        SnackBarService.success(context,
                            'Ticket #${sale.id} enviado a la impresora.');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        SnackBarService.error(
                            context, 'Error de impresión: $e');
                      }
                    }
                  } else {
                    SnackBarService.error(
                        context, 'Configuración de impresora no disponible.');
                  }
                },
              ),
              const SizedBox(width: 16),
              if (!sale.isVoided) ...[
                FilledButton.icon(
                  icon: provider.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.cancel),
                  label: const Text('ANULAR FACTURA',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, letterSpacing: 1)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 16),
                  ),
                  onPressed: provider.isLoading
                      ? null
                      : () => _handleVoid(context),
                ),
              ] else ...[
                FilledButton.icon(
                  icon: const Icon(Icons.block),
                  label: const Text('ESTE TICKET ESTÁ ANULADO',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.grey.shade400,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 16),
                  ),
                  onPressed: null,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Badge visual de un pago individual en el detalle del ticket.
class _PaymentBadge extends StatelessWidget {
  final SalePayment payment;
  const _PaymentBadge({required this.payment});

  @override
  Widget build(BuildContext context) {
    final color = _colorForCode(payment.methodCode);
    final bg = _bgForCode(payment.methodCode);
    final hasSurcharge = payment.surchargeAmount > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconForCode(payment.methodCode), size: 14, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(payment.methodName,
                  style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w600)),
              Text(
                '\$${payment.totalAmount.toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color),
              ),
              if (hasSurcharge)
                Text(
                  'base \$${payment.baseAmount.toStringAsFixed(2)} + recargo \$${payment.surchargeAmount.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.orange.shade700,
                      fontStyle: FontStyle.italic),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
