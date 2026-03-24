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
    setState(() {
      _selectedSale = sale;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SalesHistoryProvider>(
      builder: (context, provider, _) {
        if (_selectedSale != null) {
          final updated = provider.sales.where((s) => s.id == _selectedSale!.id).firstOrNull;
          if (updated != null) {
            _selectedSale = updated;
          }
        }

        final filteredSales = provider.sales.where((sale) {
          if (_statusFilter == 'Activas' && sale.isVoided) return false;
          if (_statusFilter == 'Anuladas' && !sale.isVoided) return false;
          if (_searchQuery.isNotEmpty) {
            // Eliminar ceros a la izquierda para soportar el escáner de código de barras del ticket
            final cleanQuery = _searchQuery.replaceFirst(RegExp(r'^0+'), '');
            final searchQueryToUse = cleanQuery.isEmpty ? _searchQuery : cleanQuery;
            if (!sale.id.toString().contains(searchQueryToUse)) return false;
          }
          return true;
        }).toList();

        return Scaffold(
      appBar: const GlobalAppBar(currentRoute: '/sales-history'),
      body: Row(
            children: [
              // ── Panel Izquierdo: Lista de Ventas y Filtros ────────────────────
              Container(
                width: 380,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(right: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Column(
                  children: [
                    // Filtros Temporales (Top)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Período:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                          const SizedBox(height: 8),
                          Consumer<AuthProvider>(
                            builder: (context, auth, _) {
                              final canViewGlobal = auth.hasPermission('view_global_history');
                              
                              // Si no puede ver el global history y de alguna forma el selected fue alterado
                              // deberíamos forzarlo al turno actual. Por diseño el estado arranca en 'shift'
                              return SegmentedButton<String>(
                                segments: [
                                  const ButtonSegment(value: 'shift', label: Text('Turno')),
                                  if (canViewGlobal) ...const [
                                    ButtonSegment(value: 'today', label: Text('Hoy')),
                                    ButtonSegment(value: 'month', label: Text('Mes')),
                                    ButtonSegment(value: 'year', label: Text('Año')),
                                  ],
                                ],
                                selected: {
                                  canViewGlobal ? provider.currentPeriod : 'shift'
                                },
                                onSelectionChanged: (set) {
                                  provider.loadSales(period: set.first);
                                  setState(() => _selectedSale = null);
                                },
                                style: SegmentedButton.styleFrom(
                                  selectedBackgroundColor: Colors.blue.shade100,
                                  textStyle: const TextStyle(fontSize: 12),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          Consumer2<AuthProvider, UsersProvider>(
                            builder: (context, auth, users, _) {
                              if (!auth.hasPermission('view_global_history')) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const Text('Cajero:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                    const SizedBox(height: 8),
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
                                            const DropdownMenuItem(value: null, child: Text('Todos los cajeros')),
                                            ...users.users.map((u) => DropdownMenuItem(
                                              value: u['id'] as int,
                                              child: Text(u['name'] ?? ''),
                                            )),
                                          ],
                                          onChanged: (val) {
                                            provider.setSelectedUserId(val);
                                            setState(() => _selectedSale = null);
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
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
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                  ),
                                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment(value: 'Todas', icon: Icon(Icons.checklist, size: 16)),
                                  ButtonSegment(value: 'Activas', icon: Icon(Icons.check_circle_outline, size: 16)),
                                  ButtonSegment(value: 'Anuladas', icon: Icon(Icons.cancel_outlined, size: 16)),
                                ],
                                selected: {_statusFilter},
                                onSelectionChanged: (set) => setState(() => _statusFilter = set.first),
                                style: SegmentedButton.styleFrom(
                                  selectedBackgroundColor: Colors.white,
                                  textStyle: const TextStyle(fontSize: 12),
                                ),
                                showSelectedIcon: false,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    // ── Panel de Resumen Financiero ──────────────────────────
                    if (!provider.isLoading)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                _BuildSummaryCard(
                                  label: 'Efectivo',
                                  value: provider.totalCash,
                                  color: Colors.green.shade600,
                                  bgColor: Colors.green.shade50,
                                  icon: Icons.payments_outlined,
                                ),
                                const SizedBox(width: 8),
                                _BuildSummaryCard(
                                  label: 'Transfer.',
                                  value: provider.totalTransfers,
                                  color: Colors.blue.shade600,
                                  bgColor: Colors.blue.shade50,
                                  icon: Icons.qr_code_2,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _BuildSummaryCard(
                                  label: 'Tarjeta',
                                  value: provider.totalCards,
                                  color: Colors.orange.shade700,
                                  bgColor: Colors.orange.shade50,
                                  icon: Icons.credit_card,
                                ),
                                const SizedBox(width: 8),
                                _BuildSummaryCard(
                                  label: 'Total',
                                  value: provider.totalVentas,
                                  color: Colors.blueGrey.shade800,
                                  bgColor: Colors.blueGrey.shade50,
                                  icon: Icons.account_balance_wallet_outlined,
                                  isTotal: true,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                    // Barra de progreso y listado
                    if (provider.isLoading) const LinearProgressIndicator(),
                    Expanded(
                      child: filteredSales.isEmpty && !provider.isLoading
                          ? _EmptyStateList()
                          : ListView.separated(
                              itemCount: filteredSales.length,
                              separatorBuilder: (context, index) => const Divider(height: 1, indent: 64),
                              itemBuilder: (ctx, i) {
                                final sale = filteredSales[i];
                                final isSelected = _selectedSale?.id == sale.id;
                                return _SaleListTile(
                                  sale: sale,
                                  isSelected: isSelected,
                                  onTap: () => _onSaleSelected(sale),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),

              // ── Panel Derecho: Detalle del Ticket Seleccionado ──────────────────
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

// ─── Componentes del Panel Izquierdo ──────────────────────────────────────────

class _BuildSummaryCard extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final Color bgColor;
  final IconData icon;
  final bool isTotal;

  const _BuildSummaryCard({
    required this.label,
    required this.value,
    required this.color,
    required this.bgColor,
    required this.icon,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600, fontWeight: FontWeight.w600)),
                  Text(
                    '\$${value.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: isTotal ? 16 : 14,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _SaleListTile extends StatelessWidget {
  final SaleRecord sale;
  final bool isSelected;
  final VoidCallback onTap;

  const _SaleListTile({required this.sale, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(sale.createdAt);
    final dateStr = DateFormat('dd/MM').format(sale.createdAt);

    return ListTile(
      selected: isSelected,
      selectedTileColor: Colors.blue.shade50,
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: sale.isVoided ? Colors.grey.shade300 : (isSelected ? Colors.blue.shade600 : Colors.blue.shade100),
        foregroundColor: sale.isVoided ? Colors.grey.shade600 : (isSelected ? Colors.white : Colors.blue.shade800),
        child: Text('#${sale.id}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
              decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(12)),
              child: const Text('ANULADA', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
            )
          else
            Text('$timeStr Hs', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text('${sale.items.length} ítem${sale.items.length != 1 ? 's' : ''}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              const Spacer(),
              Text(dateStr, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            ],
          ),
          if (sale.userName != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.person_outline, size: 14, color: Colors.blueGrey.shade400),
                const SizedBox(width: 4),
                Text('Atendido por: ${sale.userName}', style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 11, fontStyle: FontStyle.italic)),
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
          Text('No hay ventas en este período.', style: TextStyle(color: Colors.grey.shade500)),
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
          Text('Seleccione un ticket de la lista', style: TextStyle(color: Colors.grey.shade500, fontSize: 18)),
          const SizedBox(height: 8),
          Text('Podrá ver su detalle y realizar anulaciones', style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
        ],
      ),
    );
  }
}

// ─── Componentes del Panel Derecho (Detalle del Ticket) ───────────────────────

class _TicketDetailPanel extends StatelessWidget {
  final SaleRecord sale;
  final SalesHistoryProvider provider;

  const _TicketDetailPanel({required this.sale, required this.provider});

  Future<void> _handleVoid(BuildContext context) async {
    final authorized = await AdminPinDialog.verify(context, action: 'Anular Ticket #${sale.id}', permissionKey: 'void_sales');
    if (!authorized) return;
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            const SizedBox(width: 10),
            const Text('Anular Ticket'),
          ],
        ),
        content: Text.rich(
          TextSpan(
            style: Theme.of(ctx).textTheme.bodyMedium,
            children: [
              const TextSpan(text: '¿Está seguro de anular el ticket '),
              TextSpan(text: '#${sale.id}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const TextSpan(text: ' por un total de '),
              TextSpan(
                text: '\$${sale.total.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
              ),
              const TextSpan(text: '?\n\nEsta acción es irreversible. '),
              const TextSpan(text: 'El stock de todos los productos será devuelto al inventario automáticamente.', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
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
        SnackBarService.success(context, 'Ticket #${sale.id} anulado con éxito. Stock restaurado.');
      } else {
        SnackBarService.error(context, provider.errorMessage ?? 'Error al anular el ticket.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(sale.createdAt);

    return Column(
      children: [
        // Cabecera del Detalle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.black12)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Ticket #${sale.id}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      if (sale.isVoided) ...[
                        const SizedBox(width: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
                          child: Text('ANULADA', style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Text(dateStr, style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                      if (sale.userName != null) ...[
                        const SizedBox(width: 16),
                        Icon(Icons.person_outline, size: 14, color: Colors.blueGrey.shade600),
                        const SizedBox(width: 4),
                        Text('Atendido por: ${sale.userName}', style: TextStyle(color: Colors.blueGrey.shade800, fontWeight: FontWeight.w500)),
                      ]
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$${sale.total.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: sale.isVoided ? Colors.grey.shade500 : Colors.green.shade700,
                      decoration: sale.isVoided ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.payments_outlined, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Text('Medio: ${_translatePaymentMethod(sale.paymentMethod)}', style: TextStyle(color: Colors.grey.shade700, fontSize: 14)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        // Tabla de ítems
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
                border: Border.all(color: Colors.black12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(Colors.grey.shade50),
                  columns: const [
                    DataColumn(label: Text('Producto', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Cant/Peso', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('P. Unitario', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Subtotal', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: sale.items.map((item) {
                    final isLineVoided = sale.isVoided;
                    final textStyle = TextStyle(
                      color: isLineVoided ? Colors.grey : Colors.black87,
                      decoration: isLineVoided ? TextDecoration.lineThrough : null,
                    );
                    
                    return DataRow(cells: [
                      DataCell(Text(item.productName, style: textStyle)),
                      DataCell(Text(item.isSoldByWeight ? '${item.quantity.toStringAsFixed(3)} Kg' : '${item.quantity.toStringAsFixed(0)} u', style: textStyle)),
                      DataCell(Text('\$${item.unitPrice.toStringAsFixed(2)}', style: textStyle)),
                      DataCell(Text('\$${item.subtotal.toStringAsFixed(2)}', style: textStyle.copyWith(fontWeight: FontWeight.bold))),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ),
        ),

        // Footer Actions (Botón de Anulación)
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
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16)),
                onPressed: () async {
                  final settings = context.read<SettingsProvider>().settings;
                  if (settings != null) {
                    try {
                      // Mapear SaleItemRecord a CartItem para la impresión
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
                        paymentMethod: sale.paymentMethod,
                        receiptNumber: sale.id.toString(),
                        userName: sale.userName,
                      );
                      if (context.mounted) {
                        SnackBarService.success(context, 'Ticket #${sale.id} enviado a la impresora.');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        SnackBarService.error(context, 'Error de impresión: $e');
                      }
                    }
                  } else {
                    SnackBarService.error(context, 'Configuración de impresora no disponible.');
                  }
                },
              ),
              const SizedBox(width: 16),
              if (!sale.isVoided) ...[
                FilledButton.icon(
                  icon: provider.isLoading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.cancel),
                  label: const Text('ANULAR FACTURA', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                  onPressed: provider.isLoading ? null : () => _handleVoid(context),
                ),
              ] else ...[
                 FilledButton.icon(
                  icon: const Icon(Icons.block),
                  label: const Text('ESTE TICKET ESTÁ ANULADO', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.grey.shade400,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
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

  String _translatePaymentMethod(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return 'Efectivo';
      case 'card':
        return 'Tarjeta';
      case 'transfer':
        return 'Transferencia';
      default:
        return method;
    }
  }
}
