import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import '../providers/reports_provider.dart';
import 'package:frontend_desktop/features/customers/providers/customer_provider.dart';

class InternalConsumptionReportView extends StatefulWidget {
  const InternalConsumptionReportView({super.key});

  @override
  State<InternalConsumptionReportView> createState() => _InternalConsumptionReportViewState();
}

class _InternalConsumptionReportViewState extends State<InternalConsumptionReportView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReportsProvider>().fetchInternalConsumption();
      context.read<CustomerProvider>().fetchCustomers();
    });
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final provider = context.read<ReportsProvider>();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: provider.icStartDate, end: provider.icEndDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'SELECCIONÁ EL RANGO DE FECHAS',
      cancelText: 'CANCELAR',
      confirmText: 'APLICAR',
      saveText: 'APLICAR',
      builder: (context, child) => Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
          child: Theme(
            data: ThemeData.light().copyWith(
              colorScheme: ColorScheme.light(
                primary: Colors.indigo.shade700,
                onPrimary: Colors.white,
                secondary: Colors.indigo.shade400,
                onSecondary: Colors.white,
                surface: Colors.white,
                onSurface: Colors.blueGrey.shade900,
              ),
            ),
            child: child!,
          ),
        ),
      ),
    );
    if (picked != null) {
      provider.setIcDateRange(picked.start, picked.end);
      provider.fetchInternalConsumption();
    }
  }

  void _setToday(BuildContext context) {
    final provider = context.read<ReportsProvider>();
    final today = DateTime.now();
    provider.setIcDateRange(today, today);
    provider.fetchInternalConsumption();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ReportsProvider>(
      builder: (context, provider, _) {
        final df = DateFormat('dd/MM/yyyy');
        final data = provider.internalConsumptionData;
        final totalCost = data.fold<double>(0, (sum, item) => sum + (double.tryParse(item['total_cost'].toString()) ?? 0));

        return Column(
          children: [
            // Filtros Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  Icon(Icons.inventory_2, color: Colors.blueGrey.shade700, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'CONSUMO INTERNO',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800, letterSpacing: 1.5),
                  ),
                  const Spacer(),
                  const Text('Período: ', style: TextStyle(color: Colors.blueGrey, fontSize: 13, fontWeight: FontWeight.w500)),
                  OutlinedButton.icon(
                    onPressed: () => _setToday(context),
                    icon: const Icon(Icons.today, size: 15),
                    label: const Text('Hoy', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.indigo.shade600,
                      side: BorderSide(color: Colors.indigo.shade200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _selectDateRange(context),
                    icon: const Icon(Icons.calendar_today, size: 15),
                    label: Text('${df.format(provider.icStartDate)}  →  ${df.format(provider.icEndDate)}', style: const TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.indigo.shade800,
                      side: BorderSide(color: Colors.indigo.shade200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text('Filtrar por: ', style: TextStyle(color: Colors.blueGrey, fontSize: 13, fontWeight: FontWeight.w500)),
                  Consumer<CustomerProvider>(
                    builder: (context, customerProvider, _) {
                      final internalCustomers = customerProvider.customers.where((c) => c.isInternalAccount == true).toList();
                      return Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.indigo.shade200),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int?>(
                              isExpanded: true,
                              value: provider.icCustomerId,
                              hint: const Text('Todos los clientes', style: TextStyle(fontSize: 13)),
                              icon: const Icon(Icons.arrow_drop_down, color: Colors.indigo),
                              style: const TextStyle(fontSize: 13, color: Colors.black87),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Todos los clientes', style: TextStyle(fontWeight: FontWeight.bold))),
                                ...internalCustomers.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))),
                              ],
                              onChanged: (val) {
                                provider.setIcCustomerId(val);
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => provider.fetchInternalConsumption(),
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Actualizar',
                    color: Colors.blueGrey.shade600,
                  ),
                ],
              ),
            ),
            // Contenido
            Expanded(
              child: provider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : provider.error != null
                      ? Center(child: Text(provider.error!, style: const TextStyle(color: Colors.red)))
                      : data.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.inventory_2_outlined, size: 72, color: Colors.grey.shade300),
                                  const SizedBox(height: 16),
                                  Text('No hay consumos internos registrados en este período.', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                                ],
                              ),
                            )
                          : SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Card(
                                          color: Colors.orange.shade50,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            side: BorderSide(color: Colors.orange.shade200),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(24),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.all(12),
                                                      decoration: BoxDecoration(color: Colors.orange.shade100, shape: BoxShape.circle),
                                                      child: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 28),
                                                    ),
                                                    const SizedBox(width: 16),
                                                    Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text('Costo Operativo Total', style: TextStyle(fontSize: 14, color: Colors.orange.shade900)),
                                                        Text('\$${totalCost.toCurrency()}', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.orange.shade900, letterSpacing: -0.5)),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.end,
                                                  children: [
                                                    Text('Artículos Retirados', style: TextStyle(fontSize: 14, color: Colors.orange.shade900)),
                                                    Text(data.fold<double>(0, (s, i) => s + (double.tryParse(i['total_quantity'].toString()) ?? 0)).toQty(), style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.orange.shade900, letterSpacing: -0.5)),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 1000),
                                      child: Card(
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: DataTable(
                                            dataRowMinHeight: 40,
                                            dataRowMaxHeight: 48,
                                            headingRowHeight: 48,
                                            headingRowColor: WidgetStateProperty.all(Colors.grey.shade50),
                                            columns: const [
                                              DataColumn(label: Text('Producto', style: TextStyle(fontWeight: FontWeight.bold))),
                                              DataColumn(label: Text('Cantidad Retirada', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                                              DataColumn(label: Text('Costo Total', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                                            ],
                                            rows: data.map((item) {
                                              final qty = double.tryParse(item['total_quantity'].toString()) ?? 0;
                                              final cost = double.tryParse(item['total_cost'].toString()) ?? 0;
                                              return DataRow(
                                                cells: [
                                                  DataCell(Text(item['product_name'].toString(), style: const TextStyle(fontWeight: FontWeight.w500))),
                                                  DataCell(Text(qty.toQty())),
                                                  DataCell(Text('\$${cost.toCurrency()}', style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.bold))),
                                                ],
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
            ),
          ],
        );
      },
    );
  }
}
