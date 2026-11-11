import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/compact_date_range_picker_dialog.dart';
import '../../models/customer_model.dart';
import '../../providers/customer_provider.dart';
import '../widgets/customer_form_dialog.dart';
import '../widgets/payment_dialog.dart';
import '../widgets/sale_detail_dialog.dart';
import '../widgets/payment_detail_dialog.dart';
import '../../../../features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/widgets/admin_pin_dialog.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/features/sales_history/data/datasources/sales_history_remote_datasource.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  Customer? _selectedCustomer;
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<CustomerProvider>().fetchCustomers());
  }

  void _onCustomerSelected(Customer customer) {
    final now = DateTime.now();
    setState(() {
      _selectedCustomer = customer;
      _dateRange = DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: DateTime(now.year, now.month, now.day),
      );
    });
    // Fetch individual customer details (including transactions)
    if (_selectedCustomer != null) {
      context.read<CustomerProvider>().fetchSingleCustomer(_selectedCustomer!.id);
    }
  }

  void _confirmDelete(BuildContext context, int id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Cliente'),
        content: Text('¿Estás seguro de que deseas eliminar permanentemente a "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              
              final isAuthorized = await AdminPinDialog.verify(
                context, 
                action: 'Eliminar cliente de la base de datos'
              );
              if (!isAuthorized) return;

              try {
                if (!context.mounted) return;
                await context.read<CustomerProvider>().deleteCustomer(id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cliente eliminado'), backgroundColor: Colors.green));
                  if (_selectedCustomer?.id == id) {
                    setState(() => _selectedCustomer = null);
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CustomerProvider>(
      builder: (context, provider, _) {
        // Mantener actualizado el cliente seleccionado 
        if (_selectedCustomer != null) {
          final updated = provider.customers.where((c) => c.id == _selectedCustomer!.id).firstOrNull;
          if (updated != null) {
            _selectedCustomer = updated;
          }
        }

        return Scaffold(
          appBar: const GlobalAppBar(currentRoute: '/cuentas-corrientes'),
          body: LayoutBuilder(
            builder: (context, constraints) {
              double ratio = context.read<LocalTerminalProvider>().customersSplitRatio;
              return StatefulBuilder(
                builder: (context, setSplitState) {
                  final totalWidth = constraints.maxWidth;
                  final availableWidth = (totalWidth - 16.0).clamp(0.0, double.infinity);
                  final minLeftWidth = 320.0.clamp(0.0, availableWidth * 0.5);
                  final maxAllowedLeft = (totalWidth - 540.0).clamp(
                    minLeftWidth,
                    totalWidth * 0.42 < minLeftWidth ? minLeftWidth : totalWidth * 0.42,
                  );
                  final maxLeftWidth = maxAllowedLeft < minLeftWidth ? minLeftWidth : maxAllowedLeft;

                  final minLeftRatio = totalWidth > 0 ? (minLeftWidth / totalWidth) : 0.30;
                  final computedMaxRatio = totalWidth > 0 ? (maxLeftWidth / totalWidth) : 0.30;

                  return Row(
                    children: [
                      // ── Panel Izquierdo: Lista de Clientes ──
                      Container(
                        width: (totalWidth * ratio).clamp(minLeftWidth, maxLeftWidth),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border(right: BorderSide(color: Colors.grey.shade300)),
                        ),
                        child: Column(
                  children: [
                    // Buscador y Botón Nuevo
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Directorio de Clientes',
                              style: TextStyle(
                                fontSize: 18, 
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                            child: TextField(
                              decoration: InputDecoration(
                                hintText: 'Buscar nombre o DNI...',
                                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                                prefixIcon: const Icon(Icons.search, size: 20),
                                filled: true,
                                fillColor: Colors.white,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                              ),
                              onChanged: (val) {
                                provider.setSearchQuery(val);
                                setState(() => _selectedCustomer = null);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Consumer<CustomerProvider>(
                            builder: (context, provider, child) {
                              if (provider.isLoading) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12.0),
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
                                  ),
                                );
                              }
                              return IconButton(
                                icon: const Icon(Icons.refresh, color: Colors.blueGrey),
                                onPressed: () {
                                  // As the TextField handles the state in onChanged, we can just call fetchCustomers
                                  provider.fetchCustomers(search: provider.searchQuery);
                                },
                              );
                            },
                          ),
                          IconButton.filled(
                            onPressed: () {
                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => const CustomerFormDialog(),
                              );
                            },
                            icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                            style: IconButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.all(12),
                            ),
                          )
                        ],
                      ),
                    ],
                  ),
                ),
                // Cargando
                    if (provider.isLoading) 
                       const LinearProgressIndicator(),

                    // Lista Expandida
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: provider.customers.isEmpty && !provider.isLoading
                            ? _EmptyStateList()
                            : ListView.separated(
                              itemCount: provider.customers.length,
                              separatorBuilder: (context, index) => const Divider(height: 1, indent: 64),
                              itemBuilder: (context, index) {
                                final customer = provider.customers[index];
                                // 3 estados: deuda (>0), crédito a favor (<0), al día (=0)
                                final balanceState = customer.balance > 0 ? 1 : customer.balance < 0 ? -1 : 0;
                                final isSelected = _selectedCustomer?.id == customer.id;

                                return ListTile(
                                  selected: isSelected,
                                  selectedTileColor: Colors.blue.shade50,
                                  onTap: () => _onCustomerSelected(customer),
                                  leading: CircleAvatar(
                                    backgroundColor: isSelected ? Colors.blue.shade600 : Colors.blue.shade100,
                                    foregroundColor: isSelected ? Colors.white : Colors.blue.shade800,
                                    child: const Icon(Icons.person, size: 20),
                                  ),
                                  title: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          customer.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          maxLines: 1, overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        '\$${customer.balance.abs().toCurrency()}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: balanceState > 0
                                              ? Colors.red.shade700
                                              : balanceState < 0
                                                  ? Colors.green.shade600
                                                  : Colors.grey.shade500,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${customer.documentType == 80 ? "CUIT" : (customer.documentType == 86 ? "CUIL" : "DNI")}: ${customer.documentNumber}'
                                            '${customer.phone != null && customer.phone!.isNotEmpty ? " · 📞 ${customer.phone}" : ""}',
                                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            InkWell(
                                              onTap: () => showDialog(context: context, barrierDismissible: false, builder: (_) => CustomerFormDialog(customer: customer)),
                                              child: const Padding(padding: EdgeInsets.all(4.0), child: Icon(Icons.edit, size: 16, color: Colors.blueGrey)),
                                            ),
                                            InkWell(
                                              onTap: () => _confirmDelete(context, customer.id, customer.name),
                                              child: const Padding(padding: EdgeInsets.all(4.0), child: Icon(Icons.delete_outline, size: 16, color: Colors.blueGrey)),
                                            ),
                                          ],
                                        )
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                      ),
                    ),
                  ],
                ),
              ),

                      // ── Divisor Arrastrable (Persistente) ──
                      Tooltip(
                        message: 'Arrastrar para ajustar ancho · Doble clic para restablecer',
                        waitDuration: const Duration(milliseconds: 600),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeColumn,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onPanUpdate: (details) {
                              if (totalWidth <= 0) return;
                              setSplitState(() {
                                ratio += details.delta.dx / totalWidth;
                                if (ratio < minLeftRatio) ratio = minLeftRatio;
                                if (ratio > computedMaxRatio) ratio = computedMaxRatio;
                              });
                            },
                            onPanEnd: (details) {
                              context.read<LocalTerminalProvider>().setCustomersSplitRatio(ratio);
                            },
                            onDoubleTap: () {
                              final resetRatio = 0.30.clamp(minLeftRatio, computedMaxRatio);
                              setSplitState(() {
                                ratio = resetRatio;
                              });
                              context.read<LocalTerminalProvider>().setCustomersSplitRatio(resetRatio);
                              SnackBarService.info(context, 'Tamaño del directorio restablecido al diseño ideal');
                            },
                            child: Container(
                              width: 16,
                              color: Colors.grey.shade100,
                              child: Center(
                                child: Container(
                                  width: 4,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade400,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // ── Panel Derecho: Detalle del Cliente ──
                      Expanded(
                        child: Container(
                          color: Colors.grey.shade100,
                          child: _selectedCustomer == null
                              ? const _EmptyStateDetail()
                              : _CustomerDetailPanel(
                                  customer: _selectedCustomer!,
                                  dateRange: _dateRange,
                                  onDateRangeChanged: (r) => setState(() => _dateRange = r),
                                ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
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
          Icon(Icons.people_outline, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No hay clientes registrados', style: TextStyle(color: Colors.grey.shade500)),
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
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.people_alt_outlined, size: 80, color: Colors.blue.shade300),
          ),
          const SizedBox(height: 24),
          Text(
            'Gestión de Clientes',
            style: TextStyle(
              color: Colors.blueGrey.shade800,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Seleccione un cliente de la lista para ver su estado de cuenta,\nregistrar pagos o modificar sus datos fiscales.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.blueGrey.shade400,
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerDetailPanel extends StatefulWidget {
  final Customer customer;
  final DateTimeRange? dateRange;
  final ValueChanged<DateTimeRange?> onDateRangeChanged;

  const _CustomerDetailPanel({
    required this.customer,
    this.dateRange,
    required this.onDateRangeChanged,
  });

  @override
  State<_CustomerDetailPanel> createState() => _CustomerDetailPanelState();
}

class _CustomerDetailPanelState extends State<_CustomerDetailPanel> {
  /// 'all' = Todo (Cta. Cte. + Cobros en Caja), 'cc' = Solo Cta. Cte., 'direct' = Solo Cobros en Caja
  String _historyFilter = 'all';
  /// 'all' = Todos, 'fiscal' = Solo Facturas Fiscales ARCA/AFIP, 'non_fiscal' = Solo No Fiscales / Internos
  String _fiscalFilter = 'all';

  bool _matchesFiscalFilter(CustomerTransaction trx) {
    if (_fiscalFilter == 'all') return true;
    final isSaleMovement = trx.type == 'charge' || trx.type == 'sale' || trx.type == 'direct_sale';
    if (_fiscalFilter == 'fiscal') {
      return isSaleMovement && trx.isFiscal;
    }
    if (_fiscalFilter == 'non_fiscal') {
      return !trx.isFiscal;
    }
    return true;
  }

  Widget _buildFiscalFilterChip({
    required String value,
    required String label,
    required int count,
    required Color activeColor,
  }) {
    final isSelected = _fiscalFilter == value;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() {
        _fiscalFilter = isSelected ? 'all' : value;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : Colors.blueGrey.shade200,
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? activeColor : Colors.blueGrey.shade700,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? activeColor : Colors.blueGrey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.blueGrey.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String value,
    required String label,
    required int count,
    required Color activeColor,
  }) {
    final isSelected = _historyFilter == value;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _historyFilter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : Colors.blueGrey.shade200,
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? activeColor : Colors.blueGrey.shade700,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? activeColor : Colors.blueGrey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.blueGrey.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.customer;
    final dateRange = widget.dateRange;
    final onDateRangeChanged = widget.onDateRangeChanged;

    List<CustomerTransaction> sourceList;
    if (_historyFilter == 'cc') {
      sourceList = customer.transactions;
    } else if (_historyFilter == 'direct') {
      sourceList = customer.directSales;
    } else {
      sourceList = [...customer.transactions, ...customer.directSales]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    final filteredTransactions = sourceList.where((trx) {
      if (!_matchesFiscalFilter(trx)) return false;
      if (dateRange == null) return true;
      final local = trx.createdAt.toLocal();
      final start = DateTime(dateRange.start.year, dateRange.start.month, dateRange.start.day);
      final end = DateTime(dateRange.end.year, dateRange.end.month, dateRange.end.day, 23, 59, 59, 999);
      return !local.isBefore(start) && !local.isAfter(end);
    }).toList();

    final int fiscalCount = sourceList.where((t) => (t.type == 'charge' || t.type == 'sale' || t.type == 'direct_sale') && t.isFiscal).length;
    final int nonFiscalCount = sourceList.where((t) => !t.isFiscal).length;

    // ── Analítica 360° del Cliente (Período filtrado vs Histórico) ──
    bool isWithinDateRange(DateTime dt) {
      if (dateRange == null) return true;
      final local = dt.toLocal();
      final start = DateTime(dateRange.start.year, dateRange.start.month, dateRange.start.day);
      final end = DateTime(dateRange.end.year, dateRange.end.month, dateRange.end.day, 23, 59, 59, 999);
      return !local.isBefore(start) && !local.isAfter(end);
    }

    double periodCcPurchases = 0.0;
    double periodCcPayments = 0.0;
    double allTimeCcPurchases = 0.0;
    for (final trx in customer.transactions) {
      final isPurchase = trx.type == 'charge' || trx.type == 'sale';
      if (isPurchase && _matchesFiscalFilter(trx)) {
        allTimeCcPurchases += trx.amount;
        if (isWithinDateRange(trx.createdAt)) {
          periodCcPurchases += trx.amount;
        }
      } else if (trx.type == 'payment' && isWithinDateRange(trx.createdAt)) {
        periodCcPayments += trx.amount;
      }
    }

    double periodDirectPurchases = 0.0;
    double allTimeDirectPurchases = 0.0;
    for (final sale in customer.directSales) {
      if (!_matchesFiscalFilter(sale)) continue;
      allTimeDirectPurchases += sale.amount;
      if (isWithinDateRange(sale.createdAt)) {
        periodDirectPurchases += sale.amount;
      }
    }

    final double periodTotalPurchased = periodCcPurchases + periodDirectPurchases;
    final double periodTotalPaid = periodCcPayments + periodDirectPurchases;
    final double allTimeTotalPurchased = allTimeCcPurchases + allTimeDirectPurchases;

    // ── Top 5 Productos Más Comprados (Dinámico según filtros activos: Fecha, Cta.Cte./Caja, Fiscal/No Fiscal) ──
    final bool hasItemBreakdownData = customer.transactions.any((t) => t.itemsBreakdown.isNotEmpty) ||
        customer.directSales.any((s) => s.itemsBreakdown.isNotEmpty);

    List<CustomerTopProduct> computeTopProductsFrom(Iterable<CustomerTransaction> trxs) {
      final Map<String, CustomerTopProduct> agg = {};
      for (final trx in trxs) {
        if (trx.type != 'charge' && trx.type != 'sale' && trx.type != 'direct_sale') continue;
        final Set<String> seenInOrder = {};
        for (final item in trx.itemsBreakdown) {
          final key = item.name.trim();
          if (key.isEmpty) continue;
          final prev = agg[key];
          final addOrder = seenInOrder.add(key) ? 1 : 0;
          if (prev == null) {
            agg[key] = CustomerTopProduct(
              name: key,
              totalQuantity: item.totalQuantity,
              totalAmount: item.totalAmount,
              ordersCount: addOrder > 0 ? 1 : item.ordersCount,
            );
          } else {
            agg[key] = CustomerTopProduct(
              name: prev.name,
              totalQuantity: prev.totalQuantity + item.totalQuantity,
              totalAmount: prev.totalAmount + item.totalAmount,
              ordersCount: prev.ordersCount + addOrder,
            );
          }
        }
      }
      final list = agg.values.toList()
        ..sort((a, b) {
          final cmpQty = b.totalQuantity.compareTo(a.totalQuantity);
          if (cmpQty != 0) return cmpQty;
          return b.totalAmount.compareTo(a.totalAmount);
        });
      return list.take(5).toList();
    }

    List<CustomerTopProduct> activeTopProducts;
    String topProductsTitle = 'Más comprados:';

    if (hasItemBreakdownData) {
      final periodFilteredTop = computeTopProductsFrom(filteredTransactions);
      final String filterSuffix = _fiscalFilter == 'fiscal'
          ? ' (Fiscales)'
          : (_fiscalFilter == 'non_fiscal'
              ? ' (No Fiscales)'
              : (_historyFilter == 'cc'
                  ? ' (Cta. Cte.)'
                  : (_historyFilter == 'direct' ? ' (Caja)' : '')));

      if (periodFilteredTop.isNotEmpty) {
        activeTopProducts = periodFilteredTop;
        topProductsTitle = 'Más comprados$filterSuffix:';
      } else if (dateRange != null) {
        // Si en el rango de fechas actual aún no hay compras con ese filtro, mostramos el histórico de ese filtro
        final allTimeMatchingFilter = sourceList.where(_matchesFiscalFilter);
        final historicalFilteredTop = computeTopProductsFrom(allTimeMatchingFilter);
        activeTopProducts = historicalFilteredTop;
        topProductsTitle = 'Más comprados${filterSuffix.isNotEmpty ? filterSuffix : " (Histórico)"}:';
      } else {
        activeTopProducts = const [];
      }
    } else {
      activeTopProducts = (_fiscalFilter == 'all' && _historyFilter == 'all')
          ? customer.topProducts
          : const [];
    }

    final now = DateTime.now();
    final bool isCurrentMonthRange = dateRange != null &&
        dateRange.start.year == now.year &&
        dateRange.start.month == now.month &&
        dateRange.start.day == 1 &&
        dateRange.end.year == now.year &&
        dateRange.end.month == now.month &&
        dateRange.end.day == now.day;
    // ── 3 estados del saldo ──────────────────────────────────────────
    final balance    = customer.balance;
    final isDebtor   = balance > 0;   // Tiene deuda pendiente
    final isCredit   = balance < 0;   // Saldo a favor (pagó de más)
    final isCleared  = balance == 0;  // Al día

    final String balanceLabel = isDebtor ? 'Deuda a Pagar'
        : isCredit ? 'Saldo a Favor'
        : 'Cuenta al Día';

    final Color balanceColor = isDebtor ? Colors.red.shade700
        : isCredit ? Colors.green.shade600
        : Colors.grey.shade500;

    final IconData balanceIcon = isDebtor ? Icons.warning_amber_rounded
        : isCredit ? Icons.savings_outlined
        : Icons.check_circle_outline;

    final Color avatarBg = isDebtor ? Colors.red.shade50
        : isCredit ? Colors.green.shade50
        : Colors.grey.shade100;

    final Color avatarFg = isDebtor ? Colors.red.shade700
        : isCredit ? Colors.green.shade700
        : Colors.grey.shade500;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Cabecera del Detalle ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // ── Nombre + datos del cliente ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          backgroundColor: avatarBg,
                          foregroundColor: avatarFg,
                          radius: 20,
                          child: const Icon(Icons.person, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              Text(
                                customer.name,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: Colors.blue.shade200),
                                ),
                                child: Text(
                                  customer.taxCondition == 'consumidor_final' ? 'Consumidor Final' :
                                  customer.taxCondition == 'responsable_inscripto' ? 'Resp. Inscripto' :
                                  customer.taxCondition == 'monotributo' ? 'Monotributo' :
                                  customer.taxCondition == 'exento' ? 'IVA Exento' : 'IVA No Definido',
                                  style: TextStyle(fontSize: 11.5, color: Colors.blue.shade700, fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (customer.appliesIibbPerception)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.shade50,
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(color: Colors.purple.shade200),
                                  ),
                                  child: Text(
                                    'Sujeto IIBB',
                                    style: TextStyle(fontSize: 11.5, color: Colors.purple.shade700, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              if (customer.isInternalAccount)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(color: Colors.orange.shade200),
                                  ),
                                  child: Text(
                                    'Consumo Interno',
                                    style: TextStyle(fontSize: 11.5, color: Colors.orange.shade800, fontWeight: FontWeight.w700),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 14,
                      runSpacing: 6,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.badge_outlined, size: 14, color: Colors.blueGrey.shade500),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                '${customer.documentType == 80 ? "CUIT" : (customer.documentType == 86 ? "CUIL" : "DNI")}: ${customer.documentNumber}',
                                style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 13, fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (customer.phone != null && customer.phone!.isNotEmpty) ...[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.phone_outlined, size: 14, color: Colors.blueGrey.shade500),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  customer.phone!,
                                  style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (customer.deliveryAddress != null && customer.deliveryAddress!.isNotEmpty) ...[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.location_on_outlined, size: 14, color: Colors.blueGrey.shade500),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  customer.deliveryAddress!,
                                  style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ] else if (customer.fiscalAddress != null && customer.fiscalAddress!.isNotEmpty) ...[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.location_city_outlined, size: 14, color: Colors.blueGrey.shade500),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  customer.fiscalAddress!,
                                  style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (customer.creditLimit > 0) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.credit_score_outlined, size: 13.5, color: Colors.blueGrey.shade700),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    'Límite: \$${customer.creditLimit.toCurrency()} · Disp: \$${(customer.creditLimit - customer.balance).clamp(0, double.infinity).toCurrency()}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blueGrey.shade800,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // ── Bloque de saldo 3 estados ──
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Badge contextual con ícono + etiqueta
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: balanceColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: balanceColor.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(balanceIcon, size: 13.5, color: balanceColor),
                        const SizedBox(width: 5),
                        Text(
                          balanceLabel,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: balanceColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Monto — siempre sin signo, la etiqueta lo explica
                  Text(
                    isCleared ? '\$0' : '\$${balance.abs().toCurrency()}',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: balanceColor,
                      letterSpacing: -1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Lista de transacciones o movimientos (Ledger)
        Expanded(
          child: Container(
            color: const Color(0xFFF8FAFC),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        const Text(
                          'Historial del Cliente',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(width: 2),
                        _buildFilterChip(
                          value: 'all',
                          label: '📋 Todo',
                          count: customer.transactions.length + customer.directSales.length,
                          activeColor: Colors.indigo.shade700,
                        ),
                        _buildFilterChip(
                          value: 'cc',
                          label: '📒 Cta. Cte.',
                          count: customer.transactions.length,
                          activeColor: Colors.deepPurple.shade700,
                        ),
                        _buildFilterChip(
                          value: 'direct',
                          label: '🧾 Cobros en Caja',
                          count: customer.directSales.length,
                          activeColor: Colors.teal.shade700,
                        ),
                        Container(
                          width: 1,
                          height: 18,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          color: const Color(0xFFCBD5E1),
                        ),
                        _buildFiscalFilterChip(
                          value: 'fiscal',
                          label: '🏛️ Fiscales',
                          count: fiscalCount,
                          activeColor: Colors.blue.shade800,
                        ),
                        _buildFiscalFilterChip(
                          value: 'non_fiscal',
                          label: '📄 No Fiscales',
                          count: nonFiscalCount,
                          activeColor: Colors.blueGrey.shade700,
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isCurrentMonthRange) ...[
                          OutlinedButton.icon(
                            icon: const Icon(Icons.today_rounded, size: 15),
                            label: const Text(
                              'Mes Actual',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.blueGrey.shade700,
                              side: BorderSide(color: Colors.blueGrey.shade200),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () {
                              final today = DateTime.now();
                              onDateRangeChanged(
                                DateTimeRange(
                                  start: DateTime(today.year, today.month, 1),
                                  end: DateTime(today.year, today.month, today.day),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 6),
                        ],
                        OutlinedButton.icon(
                          icon: const Icon(Icons.date_range_rounded, size: 16),
                          label: Text(
                            dateRange == null
                                ? 'Filtrar por Fecha'
                                : '${isCurrentMonthRange ? "Mes Actual: " : ""}${DateFormat('dd/MM/yy').format(dateRange.start)} - ${DateFormat('dd/MM/yy').format(dateRange.end)}',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: dateRange != null ? Colors.indigo.shade50 : Colors.white,
                            foregroundColor: Colors.indigo.shade800,
                            side: BorderSide(color: dateRange != null ? Colors.indigo.shade300 : Colors.blueGrey.shade200),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () async {
                            final picked = await showCompactDateRangePicker(
                              context: context,
                              initialDateRange: dateRange,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(const Duration(days: 1)),
                              helpText: 'Filtrar Historial por Fecha',
                            );
                            if (picked != null) {
                              onDateRangeChanged(picked);
                            }
                          },
                        ),
                        if (dateRange != null) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'Ver todo el historial',
                            icon: const Icon(Icons.clear, size: 18, color: Colors.red),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => onDateRangeChanged(null),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // ── Tarjeta Ejecutiva: KPIs del Período + Ranking de Productos ──
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.025),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Fila 1: 3 Pilares Ejecutivos (Comprado, Abonado, Histórico)
                      Wrap(
                        spacing: 18,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Pilar 1: Comprado en el Período
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.indigo.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.shopping_bag_outlined, size: 17, color: Colors.indigo.shade700),
                              ),
                              const SizedBox(width: 9),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        dateRange != null ? 'COMPRADO (PERÍODO)' : 'TOTAL COMPRADO',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.4,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                      if (periodTotalPurchased > 0) ...[
                                        const SizedBox(width: 6),
                                        Text(
                                          '· Cta. Cte.: \$${periodCcPurchases.toCurrency()} | Caja: \$${periodDirectPurchases.toCurrency()}',
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  Text(
                                    '\$${periodTotalPurchased.toCurrency()}',
                                    style: const TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          Container(width: 1, height: 28, color: const Color(0xFFE2E8F0)),

                          // Pilar 2: Abonado en el Período
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.payments_outlined, size: 17, color: Colors.green.shade700),
                              ),
                              const SizedBox(width: 9),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'ABONADO (PERÍODO)',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.4,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  Text(
                                    '\$${periodTotalPaid.toCurrency()}',
                                    style: TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.green.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          if (dateRange != null && allTimeTotalPurchased > 0) ...[
                            Container(width: 1, height: 28, color: const Color(0xFFE2E8F0)),

                            // Pilar 3: Histórico Acumulado
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.insights_rounded, size: 17, color: Color(0xFF475569)),
                                ),
                                const SizedBox(width: 9),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'HISTÓRICO ACUMULADO',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.4,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                    Text(
                                      '\$${allTimeTotalPurchased.toCurrency()}',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF334155),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),

                      // Fila 2: Ranking compacto en 1 sola línea adaptativa (100% visible del #1 al #5, reactivo a filtros)
                      if (activeTopProducts.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 7),
                          child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                        ),
                        LayoutBuilder(
                          builder: (context, rankingConstraints) {
                            final useEqualRow = rankingConstraints.maxWidth >= 640;
                            Widget buildRankBadge(int i) {
                              final item = activeTopProducts[i];
                              final qtyStr = item.totalQuantity % 1 == 0
                                  ? item.totalQuantity.toInt().toString()
                                  : item.totalQuantity.toStringAsFixed(2);
                              final isTop1 = i == 0;
                              return Tooltip(
                                message: '${i + 1}. ${item.name}\nCantidad acumulada: $qtyStr · Total: \$${item.totalAmount.toCurrency()}',
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                                  decoration: BoxDecoration(
                                    color: isTop1 ? Colors.amber.shade50 : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isTop1 ? Colors.amber.shade300 : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: useEqualRow ? MainAxisSize.max : MainAxisSize.min,
                                    children: [
                                      Text(
                                        '#${i + 1} ',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                          color: isTop1 ? Colors.amber.shade900 : const Color(0xFF64748B),
                                        ),
                                      ),
                                      if (useEqualRow)
                                        Expanded(
                                          child: Text(
                                            item.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: isTop1 ? const Color(0xFF78350F) : const Color(0xFF1E293B),
                                            ),
                                          ),
                                        )
                                      else
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(maxWidth: 140),
                                          child: Text(
                                            item.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: isTop1 ? const Color(0xFF78350F) : const Color(0xFF1E293B),
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: isTop1 ? Colors.amber.shade100 : const Color(0xFFE2E8F0),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '${qtyStr}x · \$${item.totalAmount.toCurrency()}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: isTop1 ? const Color(0xFF78350F) : const Color(0xFF334155),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }

                            if (useEqualRow) {
                              return Row(
                                children: [
                                  Icon(Icons.workspace_premium_rounded, size: 15, color: Colors.amber.shade800),
                                  const SizedBox(width: 4),
                                  Text(
                                    topProductsTitle,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  for (int i = 0; i < activeTopProducts.length; i++) ...[
                                    if (i > 0) const SizedBox(width: 5),
                                    Expanded(child: buildRankBadge(i)),
                                  ],
                                ],
                              );
                            }

                            return Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.workspace_premium_rounded, size: 15, color: Colors.amber.shade800),
                                    const SizedBox(width: 4),
                                    Text(
                                      topProductsTitle,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF475569),
                                      ),
                                    ),
                                  ],
                                ),
                                for (int i = 0; i < activeTopProducts.length; i++)
                                  buildRankBadge(i),
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),

                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
                      border: Border.all(color: Colors.black12),
                    ),
                    child: filteredTransactions.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.history_toggle_off, size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              Text(
                                dateRange != null
                                    ? 'No hay movimientos registrados en este rango de fechas.'
                                    : 'No hay movimientos registrados.',
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
                              ),
                              if (dateRange != null && sourceList.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: () => onDateRangeChanged(null),
                                  icon: const Icon(Icons.history_rounded, size: 16),
                                  label: Text('Ver todo el historial (${sourceList.length} mov.)'),
                                ),
                              ],
                            ],
                          ),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: filteredTransactions.length,
                            separatorBuilder: (ctx, i) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final trx = filteredTransactions[index];
                              final isPayment = trx.type == 'payment';
                              final isRefund = trx.type == 'refund';
                              final isDirectSale = trx.type == 'direct_sale';
                              final isCharge = trx.type == 'charge' || trx.type == 'sale';
                              final hasTicket = (isCharge || isDirectSale) && trx.saleId != null;
                              final isClickable = isPayment || isRefund || hasTicket;

                              final localDate = trx.createdAt.toLocal();
                              final dateStr =
                                  '${localDate.day.toString().padLeft(2, '0')}/${localDate.month.toString().padLeft(2, '0')}/${localDate.year}  '
                                  '${localDate.hour.toString().padLeft(2, '0')}:${localDate.minute.toString().padLeft(2, '0')}';

                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: isClickable
                                      ? () {
                                          if (isPayment || isRefund) {
                                            PaymentDetailDialog.show(
                                              context,
                                              transaction: trx,
                                              customerName: customer.name,
                                            );
                                          } else if (hasTicket) {
                                            final ds = context.read<SalesHistoryRemoteDataSource>();
                                            SaleDetailDialog.show(
                                              context,
                                              saleId: trx.saleId!,
                                              dataSource: ds,
                                            );
                                          }
                                        }
                                      : null,
                                  hoverColor: isPayment
                                      ? Colors.green.shade50
                                      : isRefund
                                          ? Colors.amber.shade50
                                          : isDirectSale
                                              ? Colors.teal.shade50
                                              : Colors.indigo.shade50,
                                  splashColor: isPayment
                                      ? Colors.green.shade100
                                      : isRefund
                                          ? Colors.amber.shade100
                                          : isDirectSale
                                              ? Colors.teal.shade100
                                              : Colors.indigo.shade100,
                                  highlightColor: isPayment
                                      ? Colors.green.shade100.withValues(alpha: 0.5)
                                      : isRefund
                                          ? Colors.amber.shade100.withValues(alpha: 0.5)
                                          : isDirectSale
                                              ? Colors.teal.shade100.withValues(alpha: 0.5)
                                              : Colors.indigo.shade100.withValues(alpha: 0.5),
                                  mouseCursor: isClickable
                                      ? SystemMouseCursors.click
                                      : SystemMouseCursors.basic,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24, vertical: 14),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        // ── Avatar ──
                                        CircleAvatar(
                                          radius: 22,
                                          backgroundColor: isPayment
                                              ? Colors.green.shade100
                                              : isRefund
                                                  ? Colors.amber.shade100
                                                  : isDirectSale
                                                      ? Colors.teal.shade100
                                                      : Colors.red.shade100,
                                          child: Icon(
                                            isPayment
                                                ? Icons.arrow_downward_rounded
                                                : isRefund
                                                    ? Icons.replay_rounded
                                                    : isDirectSale
                                                        ? Icons.receipt_long_rounded
                                                        : Icons.shopping_cart_outlined,
                                            color: isPayment
                                                ? Colors.green.shade700
                                                : isRefund
                                                    ? Colors.amber.shade800
                                                    : isDirectSale
                                                        ? Colors.teal.shade700
                                                        : Colors.red.shade700,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 16),

                                        // ── Descripción + fecha ──
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      trx.description ??
                                                          (isPayment
                                                              ? 'Abono en Caja'
                                                              : isRefund
                                                                  ? 'Reintegro de Saldo'
                                                                  : isDirectSale
                                                                      ? 'Cobro Directo en Caja'
                                                                      : 'Factura Cta. Cte.'),
                                                      style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 14),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (isClickable) ...[
                                                    const SizedBox(width: 6),
                                                    Icon(
                                                      (isPayment || isRefund)
                                                          ? Icons.info_outline_rounded
                                                          : Icons.receipt_long_outlined,
                                                      size: 15,
                                                      color: isPayment
                                                          ? Colors.green.shade400
                                                          : isRefund
                                                              ? Colors.amber.shade700
                                                              : isDirectSale
                                                                  ? Colors.teal.shade600
                                                                  : Colors.indigo.shade400,
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 3),
                                              Wrap(
                                                crossAxisAlignment: WrapCrossAlignment.center,
                                                spacing: 8,
                                                runSpacing: 4,
                                                children: [
                                                  Text(
                                                    dateStr,
                                                    style: TextStyle(
                                                        color: Colors.blueGrey.shade400,
                                                        fontSize: 12),
                                                  ),
                                                  if (hasTicket)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                      decoration: BoxDecoration(
                                                        color: trx.isFiscal
                                                            ? Colors.blue.shade50
                                                            : const Color(0xFFF1F5F9),
                                                        borderRadius: BorderRadius.circular(4),
                                                        border: Border.all(
                                                          color: trx.isFiscal
                                                              ? Colors.blue.shade200
                                                              : const Color(0xFFCBD5E1),
                                                        ),
                                                      ),
                                                      child: Text(
                                                        trx.isFiscal
                                                            ? '🏛️ ${trx.fiscalVoucherLabel ?? "Fiscal ARCA"}'
                                                            : '📄 No Fiscal',
                                                        style: TextStyle(
                                                          fontSize: 10.5,
                                                          fontWeight: FontWeight.w700,
                                                          color: trx.isFiscal
                                                              ? Colors.blue.shade800
                                                              : const Color(0xFF475569),
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),

                                        const SizedBox(width: 12),

                                        // ── Monto + acumulado / badge ──
                                        Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              isDirectSale
                                                  ? '\$${trx.amount.toCurrency()}'
                                                  : '${isPayment ? '+' : '-'}\$${trx.amount.toCurrency()}',
                                              style: TextStyle(
                                                color: isPayment
                                                    ? Colors.green.shade700
                                                    : isRefund
                                                        ? Colors.amber.shade800
                                                        : isDirectSale
                                                            ? Colors.teal.shade800
                                                            : Colors.red.shade700,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            if (isDirectSale)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                decoration: BoxDecoration(
                                                  color: Colors.teal.shade50,
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: Colors.teal.shade200),
                                                ),
                                                child: Text(
                                                  'PAGADO EN CAJA',
                                                  style: TextStyle(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: Colors.teal.shade800,
                                                    letterSpacing: 0.3,
                                                  ),
                                                ),
                                              )
                                            else
                                              Text(
                                                'Acum: \$${trx.balanceAfter.toCurrency()}',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color:
                                                        Colors.blueGrey.shade400),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Footer Actions ──
        if (isDebtor)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.account_balance_wallet, size: 20),
                  label: const Text('REGISTRAR ABONO',
                      style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8, fontSize: 14)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    final cashProv = context.read<CashRegisterProvider>();
                    if (cashProv.currentShift == null || !cashProv.currentShift!.isOpen) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Debe abrir un turno de caja para registrar abonos.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => PaymentDialog(customer: customer),
                    );
                  },
                ),
              ],
            ),
          ),

        // Aviso cuando hay saldo a favor (pagó de más / anulación post-pago)
        if (isCredit)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              border: const Border(top: BorderSide(color: Colors.black12)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: Colors.green.shade700),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Este cliente tiene \$${balance.abs().toCurrency()} a su favor. '
                    'Se descontará automáticamente en su próxima compra, o podés devolverlo en efectivo.',
                    style: TextStyle(
                        color: Colors.green.shade800, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text('DEVOLVER SALDO'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                  ),
                  onPressed: () {
                    final cashProv = context.read<CashRegisterProvider>();
                    if (cashProv.currentShift == null || !cashProv.currentShift!.isOpen) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Debe abrir un turno de caja para procesar devoluciones.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => PaymentDialog(customer: customer, isRefund: true),
                    );
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}
