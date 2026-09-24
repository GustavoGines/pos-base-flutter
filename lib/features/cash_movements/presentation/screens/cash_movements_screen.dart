import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/presentation/widgets/global_app_bar.dart';
import '../../providers/cash_movement_provider.dart';
import '../widgets/movement_form_dialog.dart';
import '../../../../core/utils/receipt_printer_service.dart';
import '../../services/cash_movement_pdf_service.dart';
import 'package:frontend_desktop/core/presentation/widgets/print_format_selector.dart';
import '../../../../core/providers/local_terminal_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/widgets/admin_pin_dialog.dart';
import '../widgets/expense_categories_dialog.dart';

class CashMovementsScreen extends StatefulWidget {
  const CashMovementsScreen({super.key});

  @override
  State<CashMovementsScreen> createState() => _CashMovementsScreenState();
}

class _CashMovementsScreenState extends State<CashMovementsScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CashMovementProvider>().fetchMovements(refresh: true, all: false);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      final provider = context.read<CashMovementProvider>();
      if (!provider.isLoading && provider.hasMore) {
        provider.fetchMovements();
      }
    }
  }

  void _showFormDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const MovementFormDialog(),
    );
  }

  void _selectDateRange() async {
    final provider = context.read<CashMovementProvider>();
    final initialStart = provider.startDate ?? DateTime.now().subtract(const Duration(days: 30));
    final initialEnd = provider.endDate ?? DateTime.now();

    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 500,
              maxHeight: 600,
            ),
            child: Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.light(
                  primary: Colors.blue,
                  onPrimary: Colors.white,
                  onSurface: Colors.black,
                ),
              ),
              child: child!,
            ),
          ),
        );
      },
    );
    if (picked != null) {
      provider.fetchMovements(
        refresh: true,
        startDate: picked.start,
        endDate: picked.end,
      );
    }
  }

  Future<void> _reprintTicket(dynamic movement) async {
    final localTerminal = context.read<LocalTerminalProvider>();
    final settingsProv = context.read<SettingsProvider>();
    final authProv = context.read<AuthProvider>();
    
    if (localTerminal.printerConnection.toLowerCase() == 'none' && !localTerminal.printerFormat.startsWith('a4')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay impresora configurada.')));
      return;
    }

    final format = await PrintFormatSelector.show(context);
    if (format == null) return;
    if (!mounted) return;
    
    final isA4 = format == 'a4';
    final settings = settingsProv.settings;
    
    final isSupplierPayment = (movement.category == 'Pago a Proveedor' || movement.category == 'Cobro de Saldo a Favor') && movement.supplier != null;
    
    final List<Map<String, dynamic>> payments = [
      {'payment_method': movement.paymentMethod, 'amount': movement.amount}
    ];

    try {
      if (isA4) {
        if (isSupplierPayment) {
          await CashMovementPdfService.printSupplierPayment(
            context: context,
            type: movement.type,
            supplierName: movement.supplier!['name'],
            supplierCuit: movement.supplier!['tax_id'],
            totalAmount: movement.amount,
            balanceBefore: null,
            payments: payments,
            businessName: settings?.companyName ?? 'MI NEGOCIO',
            businessTaxId: settings?.taxId,
            movementIds: [movement.id],
            description: movement.description,
            receiptNumber: movement.receiptNumber,
            cashierName: movement.user?['name'] ?? authProv.currentUser?['name'],
            paperSize: localTerminal.pdfPaperSize,
          );
        } else {
          await CashMovementPdfService.printGenericMovement(
            context: context,
            type: movement.type,
            category: movement.category,
            totalAmount: movement.amount,
            payments: payments,
            businessName: settings?.companyName ?? 'MI NEGOCIO',
            businessTaxId: settings?.taxId,
            movementIds: [movement.id],
            description: movement.description,
            receiptNumber: movement.receiptNumber,
            cashierName: movement.user?['name'] ?? authProv.currentUser?['name'],
            paperSize: localTerminal.pdfPaperSize,
          );
        }
      } else {
        if (isSupplierPayment) {
          await ReceiptPrinterService.instance.printSupplierPaymentTicket(
            type: movement.type,
            supplierName: movement.supplier!['name'],
            supplierCuit: movement.supplier!['tax_id'],
            totalAmount: movement.amount,
            balanceBefore: null,
            payments: payments,
            settings: settings!,
            localTerminal: localTerminal,
            movementIds: [movement.id],
            description: movement.description,
            receiptNumber: movement.receiptNumber,
            cashierName: movement.user?['name'] ?? authProv.currentUser?['name'],
            openDrawer: false,
          );
        } else {
          await ReceiptPrinterService.instance.printCashMovementTicket(
            type: movement.type,
            category: movement.category,
            totalAmount: movement.amount,
            payments: payments,
            settings: settings!,
            localTerminal: localTerminal,
            movementIds: [movement.id],
            description: movement.description,
            receiptNumber: movement.receiptNumber,
            cashierName: movement.user?['name'] ?? authProv.currentUser?['name'],
            openDrawer: false,
          );
        }
      }
    } catch (e) {
      debugPrint('Error reimprimiendo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al reimprimir comprobante.')));
      }
    }
  }

  Future<void> _voidMovement(dynamic movement) async {
    final auth = context.read<AuthProvider>();
    String adminPin = '';

    if (!auth.isAdmin && !auth.hasPermission('anular_gastos')) {
      final pin = await showDialog<String>(
        context: context,
        builder: (_) => const AdminPinDialog(actionDescription: 'Anular Movimiento de Caja'),
      );
      if (pin == null) return;
      adminPin = pin;
    }
    
    if (mounted) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirmar Anulación'),
          content: Text('¿Está seguro de anular este movimiento de \$${movement.amount}?\n\nEsta acción revertirá los saldos y enviará el registro a la papelera.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.delete_forever, size: 18),
              label: const Text('Anular'),
            ),
          ],
        ),
      );

      if (confirm == true && mounted) {
        try {
          await context.read<CashMovementProvider>().deleteMovement(movement.id, adminPin: adminPin);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Movimiento anulado correctamente.')));
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al anular movimiento.'), backgroundColor: Colors.red));
          }
        }
      }
    }
  }

  Future<void> _exportExcel() async {
    final prov = context.read<CashMovementProvider>();
    String urlStr = '${prov.baseUrl}/cash-movements/export';
    if (prov.currentAllFilter) {
      urlStr += '?all=1';
      if (prov.currentCategoryFilter != null) {
         urlStr += '&category=${prov.currentCategoryFilter}';
      }
      if (prov.startDate != null && prov.endDate != null) {
         final sd = "${prov.startDate!.year}-${prov.startDate!.month.toString().padLeft(2, '0')}-${prov.startDate!.day.toString().padLeft(2, '0')}";
         final ed = "${prov.endDate!.year}-${prov.endDate!.month.toString().padLeft(2, '0')}-${prov.endDate!.day.toString().padLeft(2, '0')}";
         urlStr += '&start_date=$sd&end_date=$ed';
      }
    } else {
      if (prov.currentCategoryFilter != null) {
         urlStr += '?category=${prov.currentCategoryFilter}';
      }
    }

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generando archivo Excel...')));
      }
      
      final response = await prov.client.get(
        Uri.parse(urlStr),
        headers: {'Accept': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'},
      );

      if (response.statusCode == 200) {
        final docsDir = await getApplicationDocumentsDirectory();
        final exportDir = Directory('${docsDir.path}\\Sistema_POS\\Exportaciones');
        if (!await exportDir.exists()) {
          await exportDir.create(recursive: true);
        }

        final fileName = 'Movimientos_Caja_${DateTime.now().millisecondsSinceEpoch}.xlsx';
        final file = File('${exportDir.path}\\$fileName');
        await file.writeAsBytes(response.bodyBytes);

        if (Platform.isWindows) {
          try {
            await Process.run('explorer.exe', ['/select,', file.path]);
          } catch (_) {}
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al exportar: HTTP ${response.statusCode}')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al descargar Excel: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Builder(builder: (context) {
        final TabController tabController = DefaultTabController.of(context);
        tabController.addListener(() {
          if (!tabController.indexIsChanging) {
             final provider = context.read<CashMovementProvider>();
             provider.fetchMovements(refresh: true, all: tabController.index == 1);
          }
        });
        
        return Scaffold(
          appBar: GlobalAppBar(
            currentRoute: '/cash-movements',
            bottom: TabBar(
              tabs: const [
                Tab(text: 'Turno Actual', icon: Icon(Icons.access_time)),
                Tab(text: 'Historial Completo', icon: Icon(Icons.history)),
              ],
              labelColor: Colors.blue.shade700,
              unselectedLabelColor: Colors.blueGrey.shade400,
              indicatorColor: Colors.blue.shade700,
            ),
          ),
          body: Consumer<CashMovementProvider>(
            builder: (context, provider, child) {
               return _buildBody(context, provider);
            }
          ),
        );
      }),
    );
  }

  Widget _buildBody(BuildContext context, CashMovementProvider provider) {
    if (provider.isLoading && provider.movements.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          children: [
        // Header
        Container(
          padding: const EdgeInsets.all(24),
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // KPIs
              Row(
                children: [
                  Expanded(child: _buildKpiCard('Total Ingresos', provider.kpiTotalIn, Colors.green, Icons.arrow_upward)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildKpiCard('Total Egresos', provider.kpiTotalOut, Colors.red, Icons.arrow_downward)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildKpiCard('Balance Neto', provider.kpiNet, Colors.blue, Icons.account_balance_wallet)),
                ]
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 16,
                children: [
                  Text(provider.currentAllFilter ? 'Historial Completo de Caja' : 'Movimientos del Turno Actual', style: Theme.of(context).textTheme.headlineSmall),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          ExpenseCategoriesDialog.show(context);
                        },
                        icon: const Icon(Icons.category),
                        label: const Text('Categorías de Gasto'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _exportExcel,
                        icon: const Icon(Icons.table_chart, color: Colors.green),
                        label: const Text('Exportar Excel', style: TextStyle(color: Colors.green)),
                      ),
                      ElevatedButton.icon(
                        onPressed: _showFormDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('Nuevo Movimiento'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Filtros Avanzados
              Row(
                children: [
                  const Text('Filtrar por Categoría: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 250,
                    child: DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(),
                      ),
                      initialValue: provider.currentCategoryFilter,
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Todas')),
                        const DropdownMenuItem(value: 'Venta', child: Text('Ventas')),
                        const DropdownMenuItem(value: 'Pago a Proveedor', child: Text('Pago a Proveedor')),
                        const DropdownMenuItem(value: 'Ingreso Manual', child: Text('Ingresos Manuales')),
                        const DropdownMenuItem(value: 'Gasto', child: Text('Gastos')),
                        if (provider.currentCategoryFilter != null && !['Venta', 'Pago a Proveedor', 'Ingreso Manual', 'Gasto'].contains(provider.currentCategoryFilter))
                          DropdownMenuItem(value: provider.currentCategoryFilter, child: Text(provider.currentCategoryFilter!)),
                      ],
                      onChanged: (val) {
                        if (val == null) {
                          provider.fetchMovements(refresh: true, clearCategory: true);
                        } else {
                          provider.fetchMovements(refresh: true, category: val);
                        }
                      },
                    ),
                  ),
                  if (provider.currentAllFilter) ...[
                    const SizedBox(width: 16),
                    const Text('Fechas: ', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.date_range, size: 18),
                      label: Text(
                        provider.startDate != null && provider.endDate != null
                            ? '${DateFormat('dd/MM/yyyy').format(provider.startDate!)} - ${DateFormat('dd/MM/yyyy').format(provider.endDate!)}'
                            : 'Seleccionar Rango',
                      ),
                      onPressed: _selectDateRange,
                    ),
                    if (provider.startDate != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Limpiar Fechas',
                        icon: const Icon(Icons.clear, color: Colors.red),
                        onPressed: () {
                          provider.fetchMovements(refresh: true, clearDates: true);
                        },
                      ),
                    ],
                  ],
                ],
              ),
            ],
          ),
        ),
        if (provider.movements.isEmpty)
           Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text('No hay movimientos con los filtros actuales.', style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: provider.movements.length + (provider.hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == provider.movements.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final movement = provider.movements[index];
                  final isExpenseOrWithdrawal = movement.type == 'expense' || movement.type == 'withdrawal' || movement.type == 'supplier_payment';
                  final amountColor = isExpenseOrWithdrawal ? Colors.red.shade700 : Colors.green.shade700;
                  final amountPrefix = isExpenseOrWithdrawal ? '-' : '+';
                  
                  String subtitle = movement.category;
                  if (movement.description != null && movement.description!.isNotEmpty) {
                    subtitle += ' | ${movement.description}';
                  }
                  
                  String authorInfo = movement.user?['name'] ?? 'Cajero';
                  if (movement.authorizer != null) {
                    authorInfo += ' (Aut: ${movement.authorizer?['name'] ?? 'Admin'})';
                  }

                  String methodLabel = movement.paymentMethod.toUpperCase();
                  IconData methodIcon = Icons.payments_outlined;
                  if (movement.paymentMethod == 'cash') {
                    methodLabel = 'Efectivo';
                    methodIcon = Icons.payments_outlined;
                  } else if (movement.paymentMethod == 'transfer') {
                    methodLabel = 'Transferencia';
                    methodIcon = Icons.account_balance_outlined;
                  } else if (movement.paymentMethod == 'check') {
                    methodLabel = 'Cheque';
                    methodIcon = Icons.fact_check_outlined;
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isExpenseOrWithdrawal ? Colors.red.shade50 : Colors.green.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isExpenseOrWithdrawal ? Icons.arrow_downward : Icons.arrow_upward,
                            color: amountColor,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      subtitle,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.grey.shade300),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(methodIcon, size: 12, color: Colors.grey.shade700),
                                        const SizedBox(width: 4),
                                        Text(
                                          methodLabel,
                                          style: TextStyle(color: Colors.grey.shade700, fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 12,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.person_outline, size: 14, color: Colors.grey.shade600),
                                      const SizedBox(width: 4),
                                      Text(
                                        authorInfo,
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                  if (movement.supplier != null)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.storefront, size: 14, color: Colors.blue.shade700),
                                        const SizedBox(width: 4),
                                        Text(
                                          movement.supplier?['name'] ?? '',
                                          style: TextStyle(color: Colors.blue.shade700, fontSize: 13, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '$amountPrefix ${NumberFormat.currency(symbol: '\$').format(movement.amount)}',
                              style: TextStyle(
                                color: amountColor,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.access_time, size: 14, color: Colors.grey.shade500),
                                const SizedBox(width: 4),
                                Text(
                                  DateFormat('dd/MM/yyyy HH:mm').format(movement.createdAt.toLocal()),
                                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(width: 12),
                                if (movement.receiptFileUrl != null && movement.receiptFileUrl!.isNotEmpty)
                                  InkWell(
                                    onTap: () => launchUrl(Uri.parse(movement.receiptFileUrl!)),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 4),
                                      child: Icon(Icons.attachment, color: Colors.blue, size: 20),
                                    ),
                                  ),
                                InkWell(
                                  onTap: () => _reprintTicket(movement),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Icon(Icons.print_outlined, color: Colors.grey.shade600, size: 20),
                                  ),
                                ),
                                if (movement.type == 'income' || movement.type == 'expense' || movement.type == 'supplier_payment')
                                  InkWell(
                                    onTap: () => _voidMovement(movement),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                      child: Icon(Icons.delete_outline, color: Colors.red.shade600, size: 20),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
      ],
        ),
      ),
    );
  }

  Widget _buildKpiCard(String title, double value, MaterialColor color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.shade100,
            radius: 24,
            child: Icon(icon, color: color.shade700, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color.shade900, fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    NumberFormat.currency(symbol: '\$').format(value),
                    style: TextStyle(color: color.shade700, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
