import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/sales_history_provider.dart';
import '../../domain/entities/sale_record.dart';
import '../../../auth/presentation/widgets/admin_pin_dialog.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/core/constants/app_permissions.dart';
import '../../../users/presentation/providers/users_provider.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import 'package:frontend_desktop/core/utils/receipt_printer_service.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/customers/models/customer_model.dart';
import 'package:frontend_desktop/features/customers/providers/customer_provider.dart';
import 'package:frontend_desktop/features/customers/presentation/widgets/customer_form_dialog.dart';
import 'package:frontend_desktop/core/utils/a4_split_pdf_service.dart';
import 'package:frontend_desktop/core/utils/afip_fiscal_pdf_service.dart';
import 'package:printing/printing.dart';

import 'package:frontend_desktop/core/presentation/widgets/print_format_selector.dart';
import 'package:frontend_desktop/core/presentation/widgets/thermal_receipt_widget.dart';
import 'package:frontend_desktop/core/presentation/widgets/ticket_preview_dialog.dart';

// ─── Helpers de presentación para métodos de pago ────────────────────────────

IconData _iconForCode(String code) {
  if (code.contains('mercadopago_qr')) return Icons.qr_code_scanner;
  if (code.contains('mercadopago_point') || code.contains('point')) return Icons.point_of_sale;
  if (code.contains('efectivo') || code == 'cash') return Icons.payments_outlined;
  if (code.contains('debito') || code == 'card_debit') return Icons.credit_card;
  if (code.contains('credito') || code == 'card_credit') return Icons.credit_score;
  if (code.contains('transferencia') || code == 'transfer') return Icons.qr_code_2;
  if (code.contains('cuenta') || code == 'cuenta_corriente') return Icons.book_outlined;
  return Icons.money;
}

Color _colorForCode(String code) {
  if (code.contains('mercadopago')) return const Color(0xFF009EE3);
  if (code.contains('efectivo') || code == 'cash') return Colors.green.shade700;
  if (code.contains('debito') || code == 'card_debit') return Colors.blue.shade700;
  if (code.contains('credito') || code == 'card_credit') return Colors.indigo.shade700;
  if (code.contains('transferencia') || code == 'transfer') return Colors.teal.shade700;
  if (code.contains('cuenta') || code == 'cuenta_corriente') return Colors.purple.shade700;
  return Colors.blueGrey.shade700;
}

Color _bgForCode(String code) {
  if (code.contains('mercadopago')) return const Color(0xFFE1F5FE);
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

  // SH-2: Controller centralizado para poder limpiar el campo de búsqueda
  // programáticamente (ej: al cambiar de período).
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cashProv = context.read<CashRegisterProvider>();
      if (cashProv.availableRegisters == null) {
        cashProv.loadRegisters();
      }
      final shiftId = cashProv.currentShift?.id;
      final provider = context.read<SalesHistoryProvider>();
      // Reseteamos filtros que hayan quedado sucios en el singleton de sesiones anteriores
      provider.setMethodFilter(null);
      provider.loadSales(period: 'shift', shiftId: shiftId);
      context.read<UsersProvider>().loadUsers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSaleSelected(SaleRecord sale) {
    setState(() => _selectedSale = sale);
  }

  List<SaleRecord> _applyFilters(SalesHistoryProvider provider) {
    return provider.sales.where((sale) {
      // Filtro de estado
      if (_statusFilter == 'Activas' && sale.isVoided) return false;
      if (_statusFilter == 'Anuladas' && !sale.isVoided) return false;

      // SH-1: Búsqueda multi-campo — ID y nombre de producto.
      // (customerName omitido: SaleRecord no tiene campo de cliente todavía —
      //  se podrá agregar cuando se implemente el módulo de Clientes.)
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        // Búsqueda por ID (limpiando ceros iniciales del escáner)
        final cleanId = q.replaceFirst(RegExp(r'^0+'), '');
        final idQ = cleanId.isEmpty ? q : cleanId;
        final matchesId = sale.id.toString().contains(idQ);
        // Búsqueda por nombre de producto en los ítems del ticket
        final matchesProduct =
            sale.items.any((i) => i.productName.toLowerCase().contains(q));
        if (!matchesId && !matchesProduct) return false;
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
              // ── Panel Izquierdo: Filtros y Lista ───────────────────
              Container(
                width: 360,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(right: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Column(
                  children: [
                    _FiltersPanel(
                      provider: provider,
                      statusFilter: _statusFilter,
                      searchController: _searchController,
                      onStatusChanged: (v) => setState(() {
                        _statusFilter = v;
                        _selectedSale = null;
                      }),
                      onSearchChanged: (v) => setState(() => _searchQuery = v.trim()),
                      onPeriodChanged: (period) {
                        provider.setMethodFilter(null);
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                          _selectedSale = null;
                        });
                        final shiftId = context.read<CashRegisterProvider>().currentShift?.id;
                        provider.loadSales(period: period, shiftId: shiftId);
                      },
                      onSaleDeselect: () => setState(() => _selectedSale = null),
                    ),

                    // Lista
                    if (provider.isLoading) const LinearProgressIndicator(),
                    Expanded(
                      child: filteredSales.isEmpty && !provider.isLoading
                          ? _EmptyStateList()
                          : IgnorePointer(
                              ignoring: provider.isLoading,
                              child: ListView.separated(
                                itemCount: filteredSales.length,
                                separatorBuilder: (context, index) =>
                                    const Divider(height: 1),
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
                    ),
                  ],
                ),
              ),

              // ── Panel Derecho: Resumen Financiero y Detalle ──────────
              Expanded(
                child: Column(
                  children: [
                    // ── Panel Superior Derecho: Resumen Financiero ─────
                    if (!provider.isLoading)
                      _FinancialSummaryPanel(provider: provider),

                    // ── Detalle del Ticket ─────────────────────────────
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
  final TextEditingController searchController;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onPeriodChanged;
  final VoidCallback onSaleDeselect;

  const _FiltersPanel({
    required this.provider,
    required this.statusFilter,
    required this.searchController,
    required this.onStatusChanged,
    required this.onSearchChanged,
    required this.onPeriodChanged,
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
              const Spacer(),
              if (provider.isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueGrey),
                )
              else
                IconButton(
                  tooltip: 'Actualizar ventas',
                  icon: const Icon(Icons.refresh, color: Colors.blueGrey, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    onPeriodChanged(provider.currentPeriod);
                  },
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
              showSelectedIcon: false,
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
                onPeriodChanged(set.first);
              },
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: Colors.blue.shade100,
                textStyle: const TextStyle(fontSize: 11),
                padding: const EdgeInsets.symmetric(horizontal: 6),
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
                    // MC-08: Filtro por Caja cuando se visualizan períodos globales (Hoy/Mes/Año)
                    if (provider.currentPeriod != 'shift')
                      Consumer<CashRegisterProvider>(
                        builder: (context, cashProv, _) {
                          final registers = cashProv.availableRegisters ?? [];
                          if (registers.isEmpty) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text('Caja:',
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
                                      value: registers.any((r) => r.id == provider.selectedRegisterId)
                                          ? provider.selectedRegisterId
                                          : null,
                                      isExpanded: true,
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      items: [
                                        const DropdownMenuItem<int?>(
                                          value: null,
                                          child: Text('Todas las cajas'),
                                        ),
                                        ...registers.map((r) => DropdownMenuItem<int?>(
                                              value: r.id,
                                              child: Text(r.name),
                                            )),
                                      ],
                                      onChanged: (val) {
                                        provider.setSelectedRegisterId(val);
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
                  controller: searchController,
                  decoration: InputDecoration(
                    // SH-1: hint actualizado para reflejar la búsqueda multi-campo.
                    hintText: 'Buscar por ticket, producto o cliente...',
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
    final byMethod = provider.totalByMethod;         // total cobrado al cliente
    final byMethodBase = provider.totalByMethodBase; // neto del negocio
    final byMethodSurcharge = provider.totalByMethodSurcharge; // recargo bancario
    final methodNames = provider.methodNames;
    final selectedMethod = provider.methodFilter;
    final hasSurcharges = provider.totalSurcharges > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (byMethod.isNotEmpty) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Chip "Todos"
                  _MethodChip(
                    label: 'Todos',
                    amount: provider.totalVentas + provider.totalSurcharges,
                    netAmount: hasSurcharges ? provider.totalNetVentas : null,
                    surchargeAmount: hasSurcharges ? provider.totalSurcharges : null,
                    icon: Icons.account_balance_wallet_outlined,
                    color: Colors.blueGrey.shade700,
                    bgColor: Colors.blueGrey.shade50,
                    isSelected: selectedMethod == null,
                    onTap: () => provider.setMethodFilter(null),
                    isTotal: true,
                  ),
                  const SizedBox(width: 8),
                  ...byMethod.entries.map((entry) {
                    final code = entry.key;
                    final total = entry.value;              // cobrado al cliente
                    final base = byMethodBase[code] ?? total; // neto negocio
                    final surcharge = byMethodSurcharge[code]; // recargo bancario
                    final name = methodNames[code] ?? code;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: _MethodChip(
                        label: name,
                        amount: total,
                        netAmount: (surcharge != null && surcharge > 0) ? base : null,
                        surchargeAmount: (surcharge != null && surcharge > 0) ? surcharge : null,
                        icon: _iconForCode(code),
                        color: _colorForCode(code),
                        bgColor: _bgForCode(code),
                        isSelected: selectedMethod == code,
                        onTap: () => provider.setMethodFilter(
                            selectedMethod == code ? null : code),
                      ),
                    );
                  }),
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
  final double amount;          // total cobrado al cliente
  final double? netAmount;      // neto del negocio (null = sin recargo)
  final double? surchargeAmount; // recargo bancario (null = sin recargo)
  final IconData icon;
  final Color color;
  final Color bgColor;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isTotal;

  const _MethodChip({
    required this.label,
    required this.amount,
    this.netAmount,
    this.surchargeAmount,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.isSelected,
    required this.onTap,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasSurcharge = surchargeAmount != null && surchargeAmount! > 0;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        constraints: const BoxConstraints(minWidth: 125, minHeight: 78),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 4, offset: const Offset(0, 2))]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 14, color: isSelected ? Colors.white : color),
            ),
            const SizedBox(width: 4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white70 : color,
                  ),
                ),
                // Total cobrado al cliente
                Text(
                  '\$${amount.toCurrency()}',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: isTotal ? 20 : 17,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : color,
                  ),
                ),
                // Desglose neto + recargo bancario
                  if (hasSurcharge) ...[
                    Text(
                      'Neto: \$${netAmount!.toCurrency()}',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11,
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.8)
                            : color.withValues(alpha: 0.75),
                      ),
                    ),
                    Text(
                      'Rec: +\$${surchargeAmount!.toCurrency()}',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11,
                        color: isSelected
                            ? Colors.orange.shade200
                            : Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: isSelected ? Colors.blue.shade50 : Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fila 1: ID y Fecha/Hora a la izq | Total a la der
            Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: sale.isVoided
                                ? Colors.grey.shade300
                                : (isSelected ? Colors.blue.shade600 : Colors.blue.shade100),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('#${sale.id}',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: sale.isVoided
                                      ? Colors.grey.shade600
                                      : (isSelected ? Colors.white : Colors.blue.shade800))),
                        ),
                        const SizedBox(width: 6),
                        Text('$dateStr $timeStr Hs',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5, fontWeight: FontWeight.w600)),
                        if (sale.cashRegisterName != null && sale.cashRegisterName!.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(left: 5),
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.indigo.shade100),
                            ),
                            child: Text(
                              sale.cashRegisterName!,
                              style: TextStyle(
                                color: Colors.indigo.shade700,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '\$${sale.total.toCurrency()}',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: sale.isVoided ? Colors.grey : Colors.green.shade800,
                    decoration: sale.isVoided ? TextDecoration.lineThrough : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Fila 2: Métodos de Pago (+ ANULADA) a la izq | Ítems y Cajero a la der
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Izquierda: Métodos de pago y estado ANULADA
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ...sale.payments.map((p) => Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _bgForCode(p.methodCode),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: _colorForCode(p.methodCode)
                                          .withValues(alpha: 0.4)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(_iconForCode(p.methodCode),
                                        size: 10,
                                        color: _colorForCode(p.methodCode)),
                                    const SizedBox(width: 3),
                                    Text(
                                      hasMultiplePayments
                                          ? '\$${p.totalAmount.toCurrency()}'
                                          : p.methodName,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: _colorForCode(p.methodCode),
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            )),
                        if (sale.isVoided)
                          Container(
                            margin: const EdgeInsets.only(left: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: Colors.grey.shade400,
                                borderRadius: BorderRadius.circular(12)),
                            child: const Text('ANULADA',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                  ),
                ),
                  
                // Derecha: Ítems y Cajero
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 12, color: Colors.grey.shade500),
                        const SizedBox(width: 3),
                        Text(
                            '${sale.items.length} ítem${sale.items.length != 1 ? 's' : ''}',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w500)),
                        if (sale.userName != null) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Text('•', style: TextStyle(color: Colors.grey)),
                          ),
                          Icon(Icons.person_outline, size: 12, color: Colors.blueGrey.shade400),
                          const SizedBox(width: 3),
                          Container(
                            constraints: const BoxConstraints(maxWidth: 85),
                            child: Text(
                              (sale.cashierName == null || sale.userName == sale.cashierName)
                                  ? sale.userName!
                                  : '${sale.userName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: Colors.blueGrey.shade700,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ],
                    ),
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

class _TicketDetailPanel extends StatefulWidget {
  final SaleRecord sale;
  final SalesHistoryProvider provider;

  const _TicketDetailPanel({required this.sale, required this.provider});

  @override
  State<_TicketDetailPanel> createState() => _TicketDetailPanelState();
}

class _TicketDetailPanelState extends State<_TicketDetailPanel> {
  Map<String, dynamic>? _electronicInvoice;

  @override
  void initState() {
    super.initState();
    _resolveInvoice();
  }

  @override
  void didUpdateWidget(covariant _TicketDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sale.id != widget.sale.id ||
        oldWidget.sale.status != widget.sale.status ||
        oldWidget.sale.electronicInvoice != widget.sale.electronicInvoice) {
      _resolveInvoice();
    }
  }

  Future<void> _resolveInvoice() async {
    if (widget.sale.electronicInvoice != null) {
      if (mounted) {
        setState(() {
          _electronicInvoice = widget.sale.electronicInvoice;
        });
      }
      return;
    }

    if (widget.sale.hasCae ||
        widget.sale.invoiceStatus == 'invoiced' ||
        widget.sale.status == 'completed' ||
        widget.sale.status == 'active') {
      try {
        final inv =
            await context.read<PosProvider>().fetchElectronicInvoice(widget.sale.id);
        if (mounted) {
          setState(() {
            _electronicInvoice = inv;
          });
        }
      } catch (_) {
      }
    } else {
      if (mounted) {
        setState(() {
          _electronicInvoice = null;
        });
      }
    }
  }

  Future<void> _handleVoid(BuildContext context) async {
    final sale = widget.sale;
    final provider = widget.provider;
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
                  text: '\$${sale.total.toCurrency()}',
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

    final currentShiftId = context.read<CashRegisterProvider>().currentShift?.id;
    if (currentShiftId == null) {
      SnackBarService.error(context, 'Debe haber un turno de caja abierto en esta terminal para anular una venta.');
      return;
    }

    await AdminPinDialog.protectAction(
      context,
      action: 'Anular Ticket #${sale.id}',
      permissionKey: AppPermissions.voidSales,
      onAuthorized: () async {
        final ok = await provider.voidSale(sale.id, shiftId: currentShiftId);
        if (context.mounted) {
          if (ok) {
            SnackBarService.success(
                context, 'Ticket #${sale.id} anulado con éxito. Stock restaurado.');
            context.read<CatalogProvider>().fetchCriticalAlerts();
          } else {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Error de ARCA / Anulación', style: TextStyle(color: Colors.red)),
                content: Text(provider.errorMessage ?? 'Error al anular el ticket.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('CERRAR'),
                  )
                ],
              ),
            );
          }
        }
      },
    );
  }

  Future<void> _handlePrintInternalCopy(BuildContext context) async {
    final sale = widget.sale;
    final settings = context.read<SettingsProvider>().settings;
    final localTerminal = context.read<LocalTerminalProvider>();
    if (settings == null) {
      SnackBarService.error(context, 'Configuración de impresora no disponible.');
      return;
    }

    try {
      final format = await PrintFormatSelector.show(context);
      if (format == null) return;
      final isA4 = format == 'a4';

      if (isA4) {
        final saleJson = {
          'id': sale.id,
          'electronic_invoice': null,
          'total': sale.totalWithShipping,
          'total_amount': sale.totalWithShipping,
          'subtotal_list': sale.subtotalList,
          'discount_amount': sale.totalSavings,
          'discount_label': sale.hasSavings ? 'Ahorro / Descuento' : null,
          'shipping_cost': sale.shippingCost,
          'surcharge_amount': sale.surchargeTotal,
          'iibb_perception_amount': sale.iibbPerceptionAmount,
          'iibb_perception_rate': sale.iibbPerceptionRate,
          'tendered_amount': sale.tenderedAmount ?? sale.grandTotal,
          'change_amount': sale.changeAmount ?? 0,
          'customer_name': sale.customerName ?? 'Consumidor Final',
          'customer': {
            'name': sale.customerName ?? 'Consumidor Final',
            if (sale.customerDocumentNumber != null && sale.customerDocumentNumber!.isNotEmpty)
              'document_number': sale.customerDocumentNumber,
          },
          'created_at': sale.createdAt.toIso8601String(),
          'cashier': {'name': sale.cashierName ?? sale.userName ?? 'Cajero'},
          'cashier_name': sale.cashierName ?? sale.userName ?? 'Cajero',
          'user': {'name': sale.userName ?? 'Cajero'},
          'userName': sale.userName ?? 'Cajero',
          'items': sale.items.map((i) => {
            'subtotal': i.subtotal,
            'quantity': i.quantity,
            'unit_price': i.unitPrice,
            'iva_rate': i.ivaRate,
            'regular_price': i.regularPrice > 0 ? i.regularPrice : i.unitPrice,
            'regular_subtotal': (i.regularPrice > 0 ? i.regularPrice : i.unitPrice) * i.quantity,
            'discount_amount': i.discountSavings,
            'has_discount': i.hasDiscount,
            'discount_label': i.discountLabel ?? '',
            'product_name': i.productName,
            'product': {
              'name': i.productName,
              'internal_code': i.internalCode,
              'iva_rate': i.ivaRate,
              'is_sold_by_weight': i.isSoldByWeight,
              'selling_price': i.regularPrice > 0 ? i.regularPrice : i.unitPrice,
            }
          }).toList(),
          'payments': sale.payments.map((p) => {
            'amount': p.totalAmount > 0 ? p.totalAmount : p.baseAmount,
            'payment_method': {
              'name': p.methodName,
            }
          }).toList(),
        };

        final hasDeliveredNote = sale.deliveryNote != null &&
            sale.deliveryNote!['status']?.toString().toLowerCase() ==
                'delivered';
        if (hasDeliveredNote) {
          saleJson['requires_dispatch'] = true;
        }
        final pdfBytes = hasDeliveredNote
            ? await A4SplitPdfService.generateA4SplitReceiptAndDispatch(
                sale: saleJson,
                deliveryNote: sale.deliveryNote!,
                businessName: settings.companyName ?? 'MI NEGOCIO',
                businessAddress: settings.address,
                phone: settings.phone ?? '',
                cuit: settings.taxId ?? '',
                taxCondition: settings.taxCondition,
                iibb: settings.iibb,
                activityStartDate: settings.activityStartDate,
                vendorName: sale.userName,
                paperSize: localTerminal.pdfPaperSize,
                businessSettings: settings,
              )
            : await A4SplitPdfService.generateA4SingleReceipt(
                sale: saleJson,
                businessName: settings.companyName ?? 'MI NEGOCIO',
                businessAddress: settings.address,
                phone: settings.phone ?? '',
                cuit: settings.taxId ?? '',
                taxCondition: settings.taxCondition,
                iibb: settings.iibb,
                activityStartDate: settings.activityStartDate,
                vendorName: sale.userName,
                paperSize: localTerminal.pdfPaperSize,
                businessSettings: settings,
              );

        if (context.mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => Dialog(
              child: SizedBox(
                width: 800,
                height: 600,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('Vista Previa de Copia Interna',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    Expanded(
                      child: PdfPreview(
                        build: (format) async => pdfBytes,
                        canChangePageFormat: false,
                        canChangeOrientation: false,
                        pdfFileName: 'Copia_Ticket_${sale.id}.pdf',
                        canDebug: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      } else {
        final itemsParaImprimir = sale.items.map((item) {
          return CartItem(
            product: Product(
              id: item.productId ?? 0,
              name: item.productName,
              sellingPrice: item.regularPrice > 0 ? item.regularPrice : item.unitPrice,
              costPrice: item.unitPrice,
              ivaRate: item.ivaRate,
              isSoldByWeight: item.isSoldByWeight,
              stock: 0,
              internalCode: item.internalCode,
              barcode: '',
              active: true,
            ),
            quantity: item.quantity,
            promotionalPrice:
                item.regularPrice > item.unitPrice + 0.01 ? item.unitPrice : null,
            promotionalLabel: item.discountLabel,
          );
        }).toList();

        final paymentDetails = sale.payments.map((p) => {
          'name': p.methodName,
          'amount': p.totalAmount > 0 ? p.totalAmount : p.baseAmount,
          '_isCash': p.isCash,
        }).toList()
          ..sort((a, b) {
            final aCash = a['_isCash'] as bool;
            final bCash = b['_isCash'] as bool;
            if (aCash == bCash) return 0;
            return aCash ? -1 : 1;
          });

        final hasDeliveredNote = sale.deliveryNote != null &&
            sale.deliveryNote!['status']?.toString().toLowerCase() ==
                'delivered';
        final isNarrow = localTerminal.printerFormat == 'thermal_58';
        final paperWidth =
            isNarrow ? ThermalPaperWidth.mm58 : ThermalPaperWidth.mm80;
        if (context.mounted) {
          final confirmed = await TicketPreviewDialog.show(
            context,
            title:
                'Vista Previa — Ticket #${sale.id} (${isNarrow ? "58mm" : "80mm"})',
            paperWidth: paperWidth,
            receiptWidget: ThermalReceiptWidget(
              paperWidth: paperWidth,
              businessSettings: settings,
              items: itemsParaImprimir,
              payments: paymentDetails,
              total: sale.totalWithShipping,
              surchargeAmount: sale.surchargeTotal,
              discountAmount: sale.totalSavings,
              discountLabel: sale.hasSavings ? 'Ahorro / Descuento' : null,
              shippingCost: sale.shippingCost,
              tenderedAmount: sale.tenderedAmount ?? sale.grandTotal,
              changeAmount: sale.changeAmount ?? 0.0,
              iibbPerceptionAmount: sale.iibbPerceptionAmount ?? 0.0,
              iibbPerceptionRate: sale.iibbPerceptionRate ?? 0.0,
              electronicInvoice: null,
              deliveryNote: hasDeliveredNote ? sale.deliveryNote : null,
              saleNumber: sale.id.toString(),
              cashierName: sale.cashierName ?? sale.userName,
              customerName: sale.customerName,
              customerDoc: sale.customerDocumentNumber,
              customerAddress: sale.customerAddress ??
                  (sale.deliveryNote?['delivery_address'] as String?),
              dateTime: sale.createdAt,
            ),
          );
          if (!confirmed) return;
        }

        ReceiptPrinterService.instance.reconfigure(localTerminal);
        ReceiptPrinterService.instance.electronicInvoice = null;
        if (hasDeliveredNote) {
          await ReceiptPrinterService.instance.printSplitTicket(
            electronicInvoice: null,
            items: itemsParaImprimir,
            total: sale.totalWithShipping,
            shippingCost: sale.shippingCost,
            settings: settings,
            localTerminal: localTerminal,
            deliveryNote: sale.deliveryNote!,
            paymentDetails: paymentDetails,
            receiptNumber: sale.id.toString(),
            deliveryNoteNumber: sale.deliveryNote!['id']?.toString(),
            userName: sale.userName,
            cashierName: sale.cashierName,
            customerName: sale.customerName,
            customerDoc: sale.customerDocumentNumber,
            customerAddress: sale.customerAddress ??
                (sale.deliveryNote?['delivery_address'] as String?),
            surchargeAmount: sale.surchargeTotal,
            discountAmount: sale.totalSavings,
            discountLabel: sale.hasSavings ? 'Ahorro / Descuento' : null,
            tenderedAmount: sale.tenderedAmount ?? sale.grandTotal,
            changeAmount: sale.changeAmount ?? 0.0,
            paperSizeOverride: isNarrow ? '58mm' : '80mm',
            iibbPerceptionAmount: sale.iibbPerceptionAmount ?? 0.0,
          );
        } else {
          await ReceiptPrinterService.instance.printSaleTicket(
            items: itemsParaImprimir,
            total: sale.totalWithShipping,
            shippingCost: sale.shippingCost,
            settings: settings,
            localTerminal: localTerminal,
            paymentDetails: paymentDetails,
            receiptNumber: sale.id.toString(),
            userName: sale.userName,
            cashierName: sale.cashierName,
            customerName: sale.customerName,
            customerDoc: sale.customerDocumentNumber,
            customerAddress: sale.customerAddress ??
                (sale.deliveryNote?['delivery_address'] as String?),
            surchargeAmount: sale.surchargeTotal,
            discountAmount: sale.totalSavings,
            discountLabel: sale.hasSavings ? 'Ahorro / Descuento' : null,
            tenderedAmount: sale.tenderedAmount ?? sale.grandTotal,
            changeAmount: sale.changeAmount ?? 0.0,
            paperSizeOverride: isNarrow ? '58mm' : '80mm',
            iibbPerceptionAmount: sale.iibbPerceptionAmount ?? 0.0,
          );
        }
        if (context.mounted) {
          SnackBarService.success(
              context, 'Copia Interna #${sale.id} enviada a la impresora.');
        }
      }
    } catch (e) {
      if (context.mounted) {
        SnackBarService.error(context, 'Error de impresión: $e');
      }
    }
  }

  Future<void> _handlePrintAfipInvoice(BuildContext context, {bool isCreditNote = false}) async {
    final sale = widget.sale;
    final settings = context.read<SettingsProvider>().settings;
    final localTerminal = context.read<LocalTerminalProvider>();
    if (settings == null) {
      SnackBarService.error(context, 'Configuración de impresora no disponible.');
      return;
    }

    Map<String, dynamic>? invoice = _electronicInvoice ?? sale.electronicInvoice;
    if (invoice == null || invoice['cae'] == null) {
      try {
        final posProvider = context.read<PosProvider>();
        invoice = await posProvider.fetchElectronicInvoice(sale.id);
        if (mounted && invoice != null) {
          setState(() => _electronicInvoice = invoice);
        }
      } catch (_) {}
    }

    if (invoice == null || (invoice['cae'] ?? '').toString().trim().isEmpty) {
      if (context.mounted) {
        SnackBarService.error(context,
            'Esta venta no posee comprobante fiscal electrónico autorizado.');
      }
      return;
    }

    if (isCreditNote) {
      if (invoice['credit_note_cae'] == null) {
        if (context.mounted) {
          SnackBarService.error(context, 'Esta venta no posee Nota de Crédito autorizada.');
        }
        return;
      }
      invoice = Map<String, dynamic>.from(invoice);
      final origPos = invoice['point_of_sale'] ?? 1;
      final origNum = invoice['voucher_number'] ?? 0;
      final origLetter = invoice['voucher_letter']?.toString().toUpperCase() ?? 'B';
      final origFormatted = invoice['formatted_number']?.toString() ??
          '${origPos.toString().padLeft(5, '0')}-${origNum.toString().padLeft(8, '0')}';
      invoice['associated_formatted_number'] = origFormatted;
      invoice['associated_voucher_label'] = 'Factura $origLetter Nº $origFormatted';
      invoice['voucher_type'] = invoice['credit_note_voucher_type'];
      invoice['voucher_number'] = invoice['credit_note_number'];
      invoice['cae'] = invoice['credit_note_cae'];
      invoice['cae_expiration'] = invoice['credit_note_expiration'];
      invoice['issued_at'] = invoice['credit_note_issued_at'];
      final pos = invoice['point_of_sale'] ?? 1;
      final num = invoice['credit_note_number'] ?? 0;
      invoice['formatted_number'] = '${pos.toString().padLeft(5, '0')}-${num.toString().padLeft(8, '0')}';
      invoice['qr_data'] = invoice['credit_note_qr_data'];
    }

    try {
      final format = await PrintFormatSelector.show(context);
      if (format == null) return;
      final isA4 = format == 'a4';

      if (isA4) {
        final salePayload = {
          'id': sale.id,
          'electronic_invoice': invoice,
          'total': sale.totalWithShipping,
          'total_amount': sale.totalWithShipping,
          'subtotal_list': sale.subtotalList,
          'discount_amount': sale.totalSavings,
          'discount_label': sale.hasSavings ? 'Ahorro / Descuento' : null,
          'shipping_cost': sale.shippingCost,
          'surcharge_amount': sale.surchargeTotal,
          'tendered_amount': sale.tenderedAmount ?? sale.grandTotal,
          'change_amount': sale.changeAmount ?? 0.0,
          'customer_name': invoice['receiver_name'] ?? 'Consumidor Final',
          'customer': {
            'name': invoice['receiver_name'] ?? 'Consumidor Final',
            'tax_id': invoice['doc_number'] ?? '---',
            'address': invoice['receiver_address'] ?? '---',
          },
          'created_at': sale.createdAt.toIso8601String(),
          'cashier': {'name': sale.cashierName ?? sale.userName ?? 'Cajero'},
          'cashier_name': sale.cashierName ?? sale.userName ?? 'Cajero',
          'user': {'name': sale.userName ?? 'Cajero'},
          'userName': sale.userName ?? 'Cajero',
          'iibb_perception_amount': sale.iibbPerceptionAmount,
          'iibb_perception_rate': sale.iibbPerceptionRate,
          'items': sale.items.map((i) => {
            'subtotal': i.subtotal,
            'quantity': i.quantity,
            'unit_price': i.unitPrice,
            'iva_rate': i.ivaRate,
            'regular_price': i.regularPrice > 0 ? i.regularPrice : i.unitPrice,
            'regular_subtotal': (i.regularPrice > 0 ? i.regularPrice : i.unitPrice) * i.quantity,
            'discount_amount': i.discountSavings,
            'has_discount': i.hasDiscount,
            'discount_label': i.discountLabel ?? '',
            'product_name': i.productName,
            'product': {
              'name': i.productName,
              'internal_code': i.internalCode,
              'iva_rate': i.ivaRate,
              'is_sold_by_weight': i.isSoldByWeight,
              'selling_price': i.regularPrice > 0 ? i.regularPrice : i.unitPrice,
            }
          }).toList(),
          'payments': sale.payments.map((p) => {
            'amount': p.totalAmount > 0 ? p.totalAmount : p.baseAmount,
            'payment_method': {
              'name': p.methodName,
            }
          }).toList(),
        };

        final hasDeliveredNote = !isCreditNote &&
            sale.deliveryNote != null &&
            sale.deliveryNote!['status']?.toString().toLowerCase() ==
                'delivered';

        final pdfBytes = await AfipFiscalPdfService.generateFiscalInvoice(
          sale: salePayload,
          electronicInvoice: invoice,
          deliveryNote: hasDeliveredNote ? sale.deliveryNote : null,
          businessSettings: settings,
          paperSize: localTerminal.pdfPaperSize,
        );

        if (context.mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => Dialog(
              child: SizedBox(
                width: 800,
                height: 600,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            '${isCreditNote ? "Nota de Crédito" : "Factura"} ARCA #${invoice?['formatted_number'] ?? sale.id}',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    Expanded(
                      child: PdfPreview(
                        build: (format) async => pdfBytes,
                        canChangePageFormat: false,
                        canChangeOrientation: false,
                        pdfFileName: 'Factura_ARCA_${sale.id}.pdf',
                        canDebug: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      } else {
        final itemsParaImprimir = sale.items.map((item) {
          return CartItem(
            product: Product(
              id: item.productId ?? 0,
              name: item.productName,
              sellingPrice: item.regularPrice > 0 ? item.regularPrice : item.unitPrice,
              costPrice: item.unitPrice,
              ivaRate: item.ivaRate,
              isSoldByWeight: item.isSoldByWeight,
              stock: 0,
              internalCode: item.internalCode,
              barcode: '',
              active: true,
            ),
            quantity: item.quantity,
            promotionalPrice:
                item.regularPrice > item.unitPrice + 0.01 ? item.unitPrice : null,
            promotionalLabel: item.discountLabel,
          );
        }).toList();

        final paymentDetails = sale.payments.map((p) => {
          'name': p.methodName,
          'amount': p.totalAmount > 0 ? p.totalAmount : p.baseAmount,
          '_isCash': p.isCash,
        }).toList()
          ..sort((a, b) {
            final aCash = a['_isCash'] as bool;
            final bCash = b['_isCash'] as bool;
            if (aCash == bCash) return 0;
            return aCash ? -1 : 1;
          });

        final hasDeliveredNote = !isCreditNote &&
            sale.deliveryNote != null &&
            sale.deliveryNote!['status']?.toString().toLowerCase() ==
                'delivered';
        final isNarrow = localTerminal.printerFormat == 'thermal_58';
        final paperWidth =
            isNarrow ? ThermalPaperWidth.mm58 : ThermalPaperWidth.mm80;
        if (context.mounted) {
          final confirmed = await TicketPreviewDialog.show(
            context,
            title:
                'Vista Previa — ${isCreditNote ? "Nota de Crédito" : "Factura"} ARCA (${isNarrow ? "58mm" : "80mm"})',
            paperWidth: paperWidth,
            receiptWidget: ThermalReceiptWidget(
              paperWidth: paperWidth,
              businessSettings: settings,
              items: itemsParaImprimir,
              payments: paymentDetails,
              total: sale.totalWithShipping,
              surchargeAmount: sale.surchargeTotal,
              discountAmount: sale.totalSavings,
              discountLabel: sale.hasSavings ? 'Ahorro / Descuento' : null,
              shippingCost: sale.shippingCost,
              tenderedAmount: sale.tenderedAmount ?? sale.grandTotal,
              changeAmount: sale.changeAmount ?? 0.0,
              iibbPerceptionAmount: sale.iibbPerceptionAmount ?? 0.0,
              iibbPerceptionRate: sale.iibbPerceptionRate ?? 0.0,
              electronicInvoice: invoice,
              deliveryNote: hasDeliveredNote ? sale.deliveryNote : null,
              saleNumber: sale.id.toString(),
              cashierName: sale.cashierName ?? sale.userName,
              customerName:
                  invoice['receiver_name']?.toString() ?? sale.customerName,
              customerDoc:
                  invoice['doc_number']?.toString() ?? sale.customerDocumentNumber,
              customerAddress:
                  invoice['receiver_address']?.toString() ??
                      sale.customerAddress ??
                      (sale.deliveryNote?['delivery_address'] as String?),
              dateTime: sale.createdAt,
            ),
          );
          if (!confirmed) return;
        }

        ReceiptPrinterService.instance.reconfigure(localTerminal);
        if (hasDeliveredNote) {
          await ReceiptPrinterService.instance.printSplitTicket(
            electronicInvoice: invoice,
            items: itemsParaImprimir,
            total: sale.totalWithShipping,
            shippingCost: sale.shippingCost,
            settings: settings,
            localTerminal: localTerminal,
            deliveryNote: sale.deliveryNote!,
            paymentDetails: paymentDetails,
            receiptNumber: sale.id.toString(),
            deliveryNoteNumber: sale.deliveryNote!['id']?.toString(),
            userName: sale.userName,
            cashierName: sale.cashierName,
            customerName:
                invoice['receiver_name']?.toString() ?? sale.customerName,
            customerDoc:
                invoice['doc_number']?.toString() ?? sale.customerDocumentNumber,
            customerAddress:
                invoice['receiver_address']?.toString() ??
                    sale.customerAddress ??
                    (sale.deliveryNote?['delivery_address'] as String?),
            surchargeAmount: sale.surchargeTotal,
            discountAmount: sale.totalSavings,
            discountLabel: sale.hasSavings ? 'Ahorro / Descuento' : null,
            tenderedAmount: sale.tenderedAmount ?? sale.grandTotal,
            changeAmount: sale.changeAmount ?? 0.0,
            paperSizeOverride: isNarrow ? '58mm' : '80mm',
            iibbPerceptionAmount: sale.iibbPerceptionAmount ?? 0.0,
          );
        } else {
          await ReceiptPrinterService.instance.printSaleTicket(
            electronicInvoice: invoice,
            items: itemsParaImprimir,
            total: sale.totalWithShipping,
            shippingCost: sale.shippingCost,
            settings: settings,
            localTerminal: localTerminal,
            paymentDetails: paymentDetails,
            receiptNumber: sale.id.toString(),
            userName: sale.userName,
            cashierName: sale.cashierName,
            customerName:
                invoice['receiver_name']?.toString() ?? sale.customerName,
            customerDoc:
                invoice['doc_number']?.toString() ?? sale.customerDocumentNumber,
            customerAddress:
                invoice['receiver_address']?.toString() ??
                    sale.customerAddress ??
                    (sale.deliveryNote?['delivery_address'] as String?),
            surchargeAmount: sale.surchargeTotal,
            discountAmount: sale.totalSavings,
            discountLabel: sale.hasSavings ? 'Ahorro / Descuento' : null,
            tenderedAmount: sale.tenderedAmount ?? sale.grandTotal,
            changeAmount: sale.changeAmount ?? 0.0,
            paperSizeOverride: isNarrow ? '58mm' : '80mm',
            iibbPerceptionAmount: sale.iibbPerceptionAmount ?? 0.0,
          );
        }
        if (context.mounted) {
          SnackBarService.success(
              context, 'Factura ARCA #${sale.id} enviada a la impresora.');
        }
      }
    } catch (e) {
      if (context.mounted) {
        SnackBarService.error(context, 'Error de impresión fiscal: $e');
      }
    }
  }

  Future<void> _handleEmitArcaInvoice(BuildContext context) async {
    final sale = widget.sale;
    final authorizedInvoice = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _EmitArcaInvoiceDialog(sale: sale),
    );

    if (authorizedInvoice != null && mounted) {
      setState(() {
        _electronicInvoice = authorizedInvoice;
      });
      if (context.mounted) {
        SnackBarService.success(
          context,
          'Factura ARCA ${authorizedInvoice['voucher_letter'] ?? ''}-${authorizedInvoice['formatted_number'] ?? ''} autorizada exitosamente (CAE: ${authorizedInvoice['cae'] ?? ''})',
        );
        context.read<SalesHistoryProvider>().loadSales();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sale = widget.sale;
    final provider = widget.provider;
    final hasCae = sale.hasCae ||
        (_electronicInvoice != null &&
            (_electronicInvoice!['cae'] != null &&
                _electronicInvoice!['cae'].toString().trim().isNotEmpty));
    final dateStr =
        DateFormat('dd/MM/yyyy HH:mm:ss').format(sale.createdAt);
    final hasSurcharge = sale.surchargeTotal > 0;

    return Column(
      children: [
        // ── Cabecera ──────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
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
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      runSpacing: 6,
                      children: [
                        Icon(Icons.calendar_today_outlined,
                            size: 16, color: Colors.grey.shade600),
                        const SizedBox(width: 8),
                        Text(dateStr,
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 16)),
                        if (sale.userName != null) ...[
                          const SizedBox(width: 24),
                          Icon(Icons.person_outline,
                              size: 16, color: Colors.blueGrey.shade600),
                          const SizedBox(width: 6),
                          Text(
                            (sale.cashierName == null || sale.userName == sale.cashierName)
                                ? 'Cajero: ${sale.userName}'
                                : 'Generó: ${sale.userName} | Cobró: ${sale.cashierName}',
                            style: TextStyle(
                                color: Colors.blueGrey.shade800,
                                fontWeight: FontWeight.w500,
                                fontSize: 16),
                          ),
                        ]
                      ],
                    ),
                  ],
                ),
              ),

              // Totales + métodos de pago
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        // Desglose de pagos (Lado a lado)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.end,
                          children: sale.payments.map((p) => _PaymentBadge(payment: p)).toList(),
                        ),
                        // Total cobrado al cliente (prominente) y Neto
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '\$${sale.grandTotal.toCurrency()}',
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
                            // Desglose neto vs recargo bancario (Opción B)
                            if (hasSurcharge)
                              Text(
                                'Neto: \$${sale.netTotal.toCurrency()}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Tabla de ítems ────────────────────────────────────────────────────
        Expanded(
          child: LayoutBuilder(
            builder: (context, tableConstraints) {
              final availableTableWidth =
                  (tableConstraints.maxWidth - 48).clamp(320.0, double.infinity);
              final maxProductColWidth =
                  (availableTableWidth * 0.46).clamp(180.0, 520.0);

              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2))
                    ],
                    border: Border.all(color: Colors.black12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: availableTableWidth),
                        child: DataTable(
                          headingRowHeight: 40,
                          dataRowMinHeight: 40,
                          dataRowMaxHeight: 54,
                          columnSpacing: 24,
                          headingRowColor:
                              WidgetStateProperty.all(Colors.grey.shade100),
                          columns: const [
                            DataColumn(
                                label: Text('Producto',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                            DataColumn(
                                label: Text('Cant/Peso',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                            DataColumn(
                                label: Text('P. Unitario',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                            DataColumn(
                                label: Text('Subtotal',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                          ],
                          rows: sale.items.map((item) {
                            final textStyle = TextStyle(
                              fontSize: 14,
                              color: sale.isVoided ? Colors.grey : Colors.black87,
                              decoration: sale.isVoided ? TextDecoration.lineThrough : null,
                            );
                            return DataRow(cells: [
                              DataCell(
                                ConstrainedBox(
                                  constraints: BoxConstraints(maxWidth: maxProductColWidth),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        item.productName,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: textStyle.copyWith(fontWeight: FontWeight.w500),
                                      ),
                                      if (item.hasDiscount && item.discountLabel != null)
                                        Text(
                                          '(${item.discountLabel}) Reg: \$${item.regularPrice.toCurrency()}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontStyle: FontStyle.italic,
                                            color: Colors.green.shade700,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              DataCell(Text(
                                  item.isSoldByWeight
                                      ? '${item.quantity.toQty()} Kg'
                                      : '${item.quantity.toInt()} u',
                                  style: textStyle)),
                              DataCell(Text(
                                  '\$${item.unitPrice.toCurrency()}',
                                  style: textStyle)),
                              DataCell(Text('\$${item.subtotal.toCurrency()}',
                                  style: textStyle.copyWith(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold))),
                            ]);
                          }).toList(),
                        ), // End DataTable
                      ), // End ConstrainedBox
                    ), // End horizontal SingleChildScrollView
                  ), // End ClipRRect
                ), // End Container
              ); // End vertical SingleChildScrollView
            },
          ), // End LayoutBuilder
        ), // End Expanded

        // ── Footer de acciones ────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.black12)),
          ),
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 16,
            children: [
              if (!hasCae &&
                  (sale.status == 'completed' ||
                      sale.status == 'pending' ||
                      sale.status == 'active'))
                FilledButton.icon(
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Emitir a ARCA'),
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16)),
                  onPressed: () => _handleEmitArcaInvoice(context),
                ),
              OutlinedButton.icon(
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Imprimir Copia Interna'),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16)),
                onPressed: () => _handlePrintInternalCopy(context),
              ),
              if (hasCae)
                FilledButton.icon(
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Imprimir Factura ARCA'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                  ),
                  onPressed: () => _handlePrintAfipInvoice(context),
                ),
              if (sale.isVoided && _electronicInvoice != null && _electronicInvoice!['credit_note_cae'] != null)
                FilledButton.icon(
                  icon: const Icon(Icons.assignment_return_outlined),
                  label: const Text('Imprimir Nota de Crédito'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.purple.shade700,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                  onPressed: () => _handlePrintAfipInvoice(context, isCreditNote: true),
                ),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconForCode(payment.methodCode), size: 18, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(payment.methodName,
                  style: TextStyle(
                      fontSize: 13,
                      color: color,
                      fontWeight: FontWeight.w600)),
              Text(
                '\$${payment.totalAmount.toCurrency()}',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color),
              ),
              if (hasSurcharge)
                Text(
                  'base \$${payment.baseAmount.toCurrency()} + recargo \$${payment.surchargeAmount.toCurrency()}',
                  style: TextStyle(
                      fontSize: 12,
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

// ─── Diálogo para Emitir Comprobante Fiscal ARCA desde Registro de Ventas ────

class _EmitArcaInvoiceDialog extends StatefulWidget {
  final SaleRecord sale;

  const _EmitArcaInvoiceDialog({required this.sale});

  @override
  State<_EmitArcaInvoiceDialog> createState() => _EmitArcaInvoiceDialogState();
}

class _EmitArcaInvoiceDialogState extends State<_EmitArcaInvoiceDialog> {
  static const double _cfAnonymousLimit = 340000.0;

  late int _voucherType; // 1 = Factura A, 6 = Factura B, 11 = Factura C
  late int _docType; // 80 = CUIT, 86 = CUIL, 96 = DNI, 99 = Consumidor Final
  late String _taxCondition;
  late TextEditingController _docNumberCtrl;
  late TextEditingController _receiverNameCtrl;
  late TextEditingController _receiverAddressCtrl;

  Customer? _selectedCustomer;
  String? _remoteMatchedName;
  String? _remoteMatchedSource;
  bool _isLookingUpPadron = false;
  bool _autoMatchedCustomerByDoc = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  bool get _exceedsAnonymousLimit => widget.sale.total >= _cfAnonymousLimit;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>().settings;
    final issuerCond = (settings?.taxCondition ?? '').trim().toLowerCase();
    final isIssuerMonotributo =
        issuerCond.contains('monotributo') || issuerCond.contains('exento');

    final sale = widget.sale;
    final initialDocNum =
        (sale.customerDocumentNumber ?? '').replaceAll(RegExp(r'\D'), '');
    final initialTaxCond =
        (sale.customerTaxCondition ?? '').trim().toLowerCase();

    if (isIssuerMonotributo) {
      _voucherType = 11;
    } else if (initialTaxCond == 'responsable_inscripto' ||
        initialTaxCond == 'monotributo') {
      _voucherType = 1;
    } else {
      _voucherType = 6;
    }

    if (_voucherType == 1) {
      _docType = 80;
      _taxCondition = initialTaxCond == 'monotributo'
          ? 'monotributo'
          : 'responsable_inscripto';
    } else {
      _taxCondition = initialTaxCond == 'exento' ? 'exento' : 'consumidor_final';
      if (sale.customerDocumentType != null &&
          [80, 86, 96, 99].contains(sale.customerDocumentType)) {
        _docType = sale.customerDocumentType!;
      } else if (initialDocNum.length == 11) {
        _docType = 80;
      } else if (initialDocNum.length >= 7 && initialDocNum.length <= 8) {
        _docType = 96;
      } else {
        // Si supera el límite anónimo ($340.000), preseleccionamos DNI (96) para guiar al cajero
        _docType = _exceedsAnonymousLimit ? 96 : 99;
      }
    }

    _docNumberCtrl = TextEditingController(text: initialDocNum);
    _receiverNameCtrl = TextEditingController(
      text: (sale.customerName != null &&
              sale.customerName!.trim().isNotEmpty &&
              sale.customerName!.trim().toLowerCase() != 'consumidor final')
          ? sale.customerName!.trim()
          : '',
    );
    _receiverAddressCtrl = TextEditingController(
      text: sale.customerAddress ?? '',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final custProv = context.read<CustomerProvider>();
        if (custProv.customers.isEmpty && !custProv.isLoading) {
          custProv.fetchCustomers();
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _docNumberCtrl.dispose();
    _receiverNameCtrl.dispose();
    _receiverAddressCtrl.dispose();
    super.dispose();
  }

  void _applyCustomer(Customer c) {
    final settings = context.read<SettingsProvider>().settings;
    final issuerCond = (settings?.taxCondition ?? '').trim().toLowerCase();
    final isIssuerMonotributo =
        issuerCond.contains('monotributo') || issuerCond.contains('exento');

    setState(() {
      _selectedCustomer = c;
      _autoMatchedCustomerByDoc = false;
      _errorMessage = null;
      _docNumberCtrl.text = c.documentNumber.replaceAll(RegExp(r'\D'), '');
      _receiverNameCtrl.text = c.name;
      _receiverAddressCtrl.text = c.fiscalAddress ?? c.deliveryAddress ?? '';
      _docType = c.documentType;
      _taxCondition = c.taxCondition;

      if (isIssuerMonotributo) {
        _voucherType = 11;
      } else if (c.taxCondition == 'responsable_inscripto' ||
          c.taxCondition == 'monotributo') {
        _voucherType = 1;
        _docType = 80;
      } else {
        _voucherType = 6;
        if (_docType == 99 && _docNumberCtrl.text.isNotEmpty) {
          _docType = _docNumberCtrl.text.length == 11 ? 80 : 96;
        }
      }
    });
  }

  void _onVoucherTypeChanged(int newType) {
    setState(() {
      _voucherType = newType;
      _errorMessage = null;
      if (newType == 1) {
        _docType = 80;
        if (_taxCondition != 'responsable_inscripto' &&
            _taxCondition != 'monotributo') {
          _taxCondition = 'responsable_inscripto';
        }
      } else if (newType == 6) {
        if (_taxCondition == 'responsable_inscripto' ||
            _taxCondition == 'monotributo') {
          _taxCondition = 'consumidor_final';
        }
        if (_docNumberCtrl.text.trim().isEmpty) {
          _docType = _exceedsAnonymousLimit ? 96 : 99;
        }
      }
    });
  }

  void _onDocNumberChanged(String val) {
    final clean = val.replaceAll(RegExp(r'\D'), '');
    Customer? matched;
    try {
      final custProv = context.read<CustomerProvider>();
      matched = AfipModulo11.findMatchingCustomer(custProv.customers, clean);
    } catch (_) {}

    final settings = context.read<SettingsProvider>().settings;
    final issuerCond = (settings?.taxCondition ?? '').trim().toLowerCase();
    final isIssuerMonotributo =
        issuerCond.contains('monotributo') || issuerCond.contains('exento');

    setState(() {
      _errorMessage = null;
      _docType = AfipModulo11.inferDocType(
        clean,
        currentDocType: _docType,
        isFacturaA: _voucherType == 1,
        requiresIdentification: _exceedsAnonymousLimit,
      );

      if (matched != null) {
        _selectedCustomer = matched;
        _remoteMatchedName = null;
        _remoteMatchedSource = null;
        _autoMatchedCustomerByDoc = true;
        _receiverNameCtrl.text = matched.name;
        final addr = matched.fiscalAddress ?? matched.deliveryAddress ?? '';
        if (addr.isNotEmpty) {
          _receiverAddressCtrl.text = addr;
        }
        _taxCondition = matched.taxCondition;
        if (isIssuerMonotributo) {
          _voucherType = 11;
        } else if (matched.taxCondition == 'responsable_inscripto' ||
            matched.taxCondition == 'monotributo') {
          if (clean.length == 11) {
            _voucherType = 1;
            _docType = 80;
          } else {
            _voucherType = 6;
            _taxCondition = 'consumidor_final';
          }
        } else {
          _voucherType = 6;
        }
      } else if (_autoMatchedCustomerByDoc) {
        _selectedCustomer = null;
        _remoteMatchedName = null;
        _remoteMatchedSource = null;
        _autoMatchedCustomerByDoc = false;
        _receiverNameCtrl.clear();
        _receiverAddressCtrl.clear();
        _taxCondition =
            _voucherType == 1 ? 'responsable_inscripto' : 'consumidor_final';
      }
    });

    if (matched == null &&
        (clean.length == 7 ||
            clean.length == 8 ||
            (clean.length == 11 && AfipModulo11.validateCuit(clean)))) {
      _lookupRemoteRecipient(clean);
    }
  }

  Future<void> _lookupRemoteRecipient(String clean) async {
    setState(() => _isLookingUpPadron = true);
    try {
      final custProv = context.read<CustomerProvider>();
      final data = await custProv.lookupFiscalRecipient(clean);
      if (!mounted) return;
      final currentClean = _docNumberCtrl.text.replaceAll(RegExp(r'\D'), '');
      if (currentClean != clean) return;

      if (data != null && data['found'] == true) {
        final name = (data['name'] ?? '').toString().trim();
        final address = (data['address'] ?? '').toString().trim();
        final taxCond = (data['tax_condition'] ?? 'consumidor_final').toString();
        final source = (data['source'] ?? 'arca_padron').toString();

        if (name.isNotEmpty) {
          setState(() {
            if (_receiverNameCtrl.text.trim().isEmpty ||
                _autoMatchedCustomerByDoc) {
              _receiverNameCtrl.text = name;
              if (address.isNotEmpty) {
                _receiverAddressCtrl.text = address;
              }
              _remoteMatchedName = name;
              _remoteMatchedSource = source;
              _autoMatchedCustomerByDoc = true;
              if (_voucherType == 1) {
                _taxCondition = taxCond == 'monotributo'
                    ? 'monotributo'
                    : 'responsable_inscripto';
              } else if (_voucherType == 6) {
                _taxCondition =
                    taxCond == 'exento' ? 'exento' : 'consumidor_final';
              } else {
                _taxCondition = taxCond;
              }
            }
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isLookingUpPadron = false);
      }
    }
  }

  bool get _isFormValid {
    final cleanDoc = _docNumberCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
    if (_voucherType == 1) {
      if (_docType != 80) return false;
      if (!AfipModulo11.validateCuit(cleanDoc)) return false;
      if (_receiverNameCtrl.text.trim().isEmpty) return false;
      return true;
    }
    // Factura B o C
    if (_exceedsAnonymousLimit && (_docType == 99 || cleanDoc.isEmpty)) {
      return false;
    }
    if (_docType == 80 || _docType == 86) {
      return AfipModulo11.validateCuit(cleanDoc);
    }
    if (_docType == 96) {
      return AfipModulo11.validateDni(cleanDoc);
    }
    return true;
  }

  Future<void> _openCustomerSearch() async {
    final customerProvider = context.read<CustomerProvider>();
    if (customerProvider.customers.isEmpty && !customerProvider.isLoading) {
      try {
        await customerProvider.fetchCustomers();
      } catch (_) {}
    }
    if (!mounted) return;

    final picked = await showDialog<Customer>(
      context: context,
      builder: (ctx) => const _QuickCustomerPickerDialog(),
    );
    if (picked != null && mounted) {
      _applyCustomer(picked);
    }
  }

  Future<void> _submit() async {
    if (!_isFormValid || _isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final cleanDoc = _docNumberCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
    final payload = <String, dynamic>{
      'voucher_type': _voucherType,
      'doc_type': _docType,
      'doc_number': _docType == 99 ? '0' : cleanDoc,
      'receiver_name': _receiverNameCtrl.text.trim().isNotEmpty
          ? _receiverNameCtrl.text.trim()
          : 'Consumidor Final',
      'receiver_address': _receiverAddressCtrl.text.trim(),
      'receiver_tax_condition': _taxCondition,
      if (_selectedCustomer != null) 'customer_id': _selectedCustomer!.id,
    };

    try {
      final posProvider = context.read<PosProvider>();
      final result =
          await posProvider.issueFiscalInvoice(widget.sale.id, payload);
      if (!mounted) return;

      if (result != null &&
          result['success'] == true &&
          result['invoice'] != null) {
        Navigator.pop(
          context,
          Map<String, dynamic>.from(result['invoice'] as Map),
        );
      } else {
        setState(() {
          _errorMessage =
              result?['message']?.toString() ?? 'No se pudo autorizar el comprobante en ARCA.';
          _isSubmitting = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final issuerCond = (settings?.taxCondition ?? '').trim().toLowerCase();
    final isIssuerInscripto = issuerCond.contains('inscripto');
    final isIssuerMonotributo =
        issuerCond.contains('monotributo') || issuerCond.contains('exento');
    final cleanDoc = _docNumberCtrl.text.trim().replaceAll(RegExp(r'\D'), '');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cabecera
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.verified_outlined,
                          color: Colors.indigo.shade700, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Emitir Comprobante ARCA — Ticket #${widget.sale.id}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Total a facturar: \$${widget.sale.grandTotal.toCurrency()}',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed:
                          _isSubmitting ? null : () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Aviso de Tope Consumidor Final Anónimo ($340.000)
                if (_exceedsAnonymousLimit &&
                    _voucherType != 1 &&
                    !_isFormValid) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.amber.shade900, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'El monto supera el tope de Consumidor Final anónimo (\$${_cfAnonymousLimit.toCurrency()}). '
                            'ARCA exige identificar al comprador con su DNI o CUIT.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Selector de Tipo de Comprobante (A / B / C)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Clase de Comprobante:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                      segments: [
                        ButtonSegment<int>(
                          value: 1,
                          enabled: !isIssuerMonotributo,
                          label: const Text('Factura A',
                              style: TextStyle(fontSize: 12)),
                        ),
                        ButtonSegment<int>(
                          value: 6,
                          enabled: !isIssuerMonotributo,
                          label: const Text('Factura B',
                              style: TextStyle(fontSize: 12)),
                        ),
                        ButtonSegment<int>(
                          value: 11,
                          enabled: !isIssuerInscripto,
                          label: const Text('Factura C',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ],
                      selected: {_voucherType},
                      onSelectionChanged: (s) => _onVoucherTypeChanged(s.first),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Barra de selección rápida de cliente registrado
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.person_outline,
                          size: 18, color: Colors.indigo.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedCustomer != null
                              ? 'Cliente vinculado: ${_selectedCustomer!.name}'
                              : 'Podés buscar un cliente registrado o escribir el DNI/CUIT abajo',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: _selectedCustomer != null
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: _selectedCustomer != null
                                ? Colors.indigo.shade900
                                : Colors.grey.shade700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.person_search, size: 16),
                        label: Text(_selectedCustomer == null
                            ? 'Buscar Cliente'
                            : 'Cambiar'),
                        onPressed: _isSubmitting ? null : _openCustomerSearch,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Tipo Doc + Número de Documento
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 155,
                      child: DropdownButtonFormField<int>(
                        key: ValueKey('arca_emit_doc_type_$_docType'),
                        initialValue: _docType,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Tipo Doc.',
                          isDense: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        items: [
                          const DropdownMenuItem(
                              value: 80, child: Text('CUIT (80)')),
                          if (_voucherType != 1) ...[
                            const DropdownMenuItem(
                                value: 86, child: Text('CUIL (86)')),
                            const DropdownMenuItem(
                                value: 96, child: Text('DNI (96)')),
                            if (!_exceedsAnonymousLimit)
                              const DropdownMenuItem(
                                  value: 99, child: Text('Sin Doc. (99)')),
                          ],
                        ],
                        onChanged: _voucherType == 1
                            ? null
                            : (val) {
                                if (val != null) {
                                  setState(() {
                                    _docType = val;
                                    _errorMessage = null;
                                  });
                                }
                              },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _docNumberCtrl,
                        enabled: !_isSubmitting,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(11),
                        ],
                        decoration: InputDecoration(
                          labelText: _docType == 80
                              ? 'N° de CUIT (11 dígitos)'
                              : (_docType == 96
                                  ? 'N° de DNI (7 u 8 dígitos)'
                                  : 'N° de Documento / CUIT'),
                          hintText:
                              _docType == 80 ? 'Ej: 20396063299' : 'Ej: 39606329',
                          isDense: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          suffixIcon: cleanDoc.isEmpty
                              ? null
                              : Icon(
                                  _isFormValid
                                      ? Icons.check_circle
                                      : Icons.error_outline,
                                  color:
                                      _isFormValid ? Colors.green : Colors.red,
                                  size: 20,
                                ),
                        ),
                        onChanged: _onDocNumberChanged,
                        onFieldSubmitted: (_) => _submit(),
                      ),
                    ),
                  ],
                ),

                // Feedback de validación del documento
                if (_docType == 80 || _docType == 86) ...[
                  if (cleanDoc.isNotEmpty &&
                      !AfipModulo11.validateCuit(cleanDoc))
                    const Padding(
                      padding: EdgeInsets.only(top: 4, left: 4),
                      child: Text(
                        'El CUIT/CUIL ingresado no es válido (verifica los 11 dígitos / Módulo 11).',
                        style: TextStyle(color: Colors.red, fontSize: 11.5),
                      ),
                    )
                  else if (cleanDoc.isNotEmpty &&
                      AfipModulo11.validateCuit(cleanDoc))
                    const Padding(
                      padding: EdgeInsets.only(top: 4, left: 4),
                      child: Text(
                        'CUIT/CUIL válido (Módulo 11 OK)',
                        style: TextStyle(color: Colors.green, fontSize: 11.5),
                      ),
                    ),
                ] else if (_docType == 96 &&
                    cleanDoc.isNotEmpty &&
                    !AfipModulo11.validateDni(cleanDoc)) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 4, left: 4),
                    child: Text(
                      'El DNI debe tener entre 7 y 8 dígitos numéricos.',
                      style: TextStyle(color: Colors.red, fontSize: 11.5),
                    ),
                  ),
                ],
                if (_isLookingUpPadron) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Text(
                      '⏳ Consultando padrón ARCA...',
                      style: TextStyle(
                        color: Colors.blueGrey.shade600,
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ] else if (_autoMatchedCustomerByDoc &&
                    (_selectedCustomer != null ||
                        _remoteMatchedName != null)) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Text(
                      _selectedCustomer != null
                          ? '✓ Cliente encontrado en padrón local: ${_selectedCustomer!.name}'
                          : (_remoteMatchedSource == 'arca_padron'
                              ? '✓ Padrón ARCA: $_remoteMatchedName'
                              : '✓ Historial de facturación: $_remoteMatchedName'),
                      style: TextStyle(
                        color: Colors.indigo.shade700,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),

                // Nombre / Razón Social
                TextFormField(
                  controller: _receiverNameCtrl,
                  enabled: !_isSubmitting,
                  decoration: InputDecoration(
                    labelText: _voucherType == 1
                        ? 'Razón Social / Nombre del Receptor *'
                        : 'Apellido y Nombre / Razón Social (Opcional)',
                    hintText: _voucherType == 1
                        ? 'Obligatorio para Factura A'
                        : 'Consumidor Final',
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),

                // Condición frente al IVA + Domicilio
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('arca_emit_tax_cond_$_taxCondition'),
                        initialValue: _taxCondition,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Condición frente al IVA',
                          isDense: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        items: _voucherType == 1
                            ? const [
                                DropdownMenuItem(
                                    value: 'responsable_inscripto',
                                    child: Text('IVA Resp. Inscripto',
                                        style: TextStyle(fontSize: 12.5))),
                                DropdownMenuItem(
                                    value: 'monotributo',
                                    child: Text('Resp. Monotributo',
                                        style: TextStyle(fontSize: 12.5))),
                              ]
                            : const [
                                DropdownMenuItem(
                                    value: 'consumidor_final',
                                    child: Text('Consumidor Final',
                                        style: TextStyle(fontSize: 12.5))),
                                DropdownMenuItem(
                                    value: 'exento',
                                    child: Text('IVA Sujeto Exento',
                                        style: TextStyle(fontSize: 12.5))),
                              ],
                        onChanged: _isSubmitting
                            ? null
                            : (val) {
                                if (val != null) {
                                  setState(() => _taxCondition = val);
                                }
                              },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _receiverAddressCtrl,
                        enabled: !_isSubmitting,
                        decoration: InputDecoration(
                          labelText: 'Domicilio (Opcional)',
                          isDense: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),

                // Mensaje de error de ARCA en línea (sin cerrar el modal)
                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline,
                            color: Colors.red.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.red.shade800,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Botones de acción
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _isSubmitting ? null : () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_outlined),
                      label: Text(_isSubmitting
                          ? 'Autorizando en ARCA...'
                          : 'Autorizar Factura en ARCA'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.indigo.shade700,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                      ),
                      onPressed:
                          (_isFormValid && !_isSubmitting) ? _submit : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickCustomerPickerDialog extends StatefulWidget {
  const _QuickCustomerPickerDialog();

  @override
  State<_QuickCustomerPickerDialog> createState() =>
      _QuickCustomerPickerDialogState();
}

class _QuickCustomerPickerDialogState
    extends State<_QuickCustomerPickerDialog> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 460,
        height: 540,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Seleccionar Cliente para Facturar',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, DNI o CUIT...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('NUEVO CLIENTE'),
                onPressed: () async {
                  await showDialog(
                    context: context,
                    builder: (ctx) => const CustomerFormDialog(),
                  );
                },
              ),
            ),
            Expanded(
              child: Consumer<CustomerProvider>(
                builder: (ctx, provider, _) {
                  if (provider.isLoading && provider.customers.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final q = _searchCtrl.text.trim().toLowerCase();
                  final list = provider.customers.where((c) {
                    return c.name.toLowerCase().contains(q) ||
                        c.documentNumber.toLowerCase().contains(q);
                  }).toList();

                  if (list.isEmpty) {
                    return const Center(
                      child: Text('No se encontraron clientes.'),
                    );
                  }

                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final c = list[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.indigo.shade50,
                          child: Text(
                            c.name.trim().isNotEmpty
                                ? c.name.trim()[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              color: Colors.indigo.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          c.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Doc: ${c.documentNumber} • ${c.taxCondition.replaceAll('_', ' ').toUpperCase()}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        onTap: () => Navigator.pop(context, c),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
