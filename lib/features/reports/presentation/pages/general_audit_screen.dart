import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../../../../core/presentation/widgets/global_app_bar.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/cash_register/presentation/providers/cash_register_provider.dart';
import '../../../../features/cash_register/domain/entities/cash_register_shift.dart';

class GeneralAuditScreen extends StatelessWidget {
  const GeneralAuditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        appBar: const GlobalAppBar(
          currentRoute: '/general-audit',
          title: 'Auditoría General',
          showBackButton: true,
          bottom: TabBar(
            labelColor: Colors.blueAccent,
            unselectedLabelColor: Colors.blueGrey,
            indicatorColor: Colors.blueAccent,
            tabs: [
              Tab(icon: Icon(Icons.point_of_sale), text: 'Turnos y Cajas'),
              Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Movimientos de Stock'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ShiftAuditTab(),
            _StockMovementsTab(),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 1: AUDITORÍA DE CAJAS
// ─────────────────────────────────────────────────────────────────────────────
class _ShiftAuditTab extends StatefulWidget {
  const _ShiftAuditTab();

  @override
  State<_ShiftAuditTab> createState() => _ShiftAuditTabState();
}

class _ShiftAuditTabState extends State<_ShiftAuditTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CashRegisterProvider>().loadAllShifts();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CashRegisterProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.shiftsHistory.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.errorMessage != null && provider.shiftsHistory.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orange.shade400),
                const SizedBox(height: 16),
                Text(provider.errorMessage!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => provider.loadAllShifts(),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          );
        }

        final shifts = provider.shiftsHistory;
        if (shifts.isEmpty) {
          return const Center(
            child: Text('No hay turnos registrados.', style: TextStyle(color: Colors.grey, fontSize: 16)),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Historial Global de Turnos (Cierres Z)',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Registro completo auditado (Solo para administradores)',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.blueGrey),
                    onPressed: () => provider.loadAllShifts(),
                    tooltip: 'Recargar Turnos',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Contenedor principal que ocupa todo el ancho disponible
              SizedBox(
                width: double.infinity,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15, offset: const Offset(0, 5)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: MediaQuery.of(context).size.width - 48, // 48 is the horizontal padding (24*2)
                        ),
                        child: DataTable(
                          showCheckboxColumn: false,
                          headingRowColor: WidgetStateProperty.all(Colors.blueGrey.shade50),
                          columnSpacing: 32, // Espaciado más generoso
                          dataRowMinHeight: 65,
                          dataRowMaxHeight: 65,
                          columns: const [
                            DataColumn(label: Text('# ID', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Abrió', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Cerró', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('🏢 Terminal', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Apertura', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Cierre', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Monto Inicial', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Ventas', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Diferencia', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Estado', style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                          rows: shifts.map((shift) => _buildDataRow(shift, context)).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  DataRow _buildDataRow(CashRegisterShift shift, BuildContext context) {
    final diff = shift.difference ?? 0.0;
    // El entity usa 'userName' para quien abrió y 'closedByUserName' para quien cerró
    final userLabel = shift.userName ?? 'Admin';
    final currencyFormat = NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 0);

    return DataRow(
      onSelectChanged: (selected) {
        if (selected == true) {
          _showShiftDetail(context, shift);
        }
      },
      cells: [
        DataCell(Text(shift.id.toString(), style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey))),
        DataCell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.login, size: 14, color: Colors.green),
            const SizedBox(width: 6),
            Text(userLabel, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        )),
        DataCell(
          shift.closedByUserName != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.logout, size: 14, color: Colors.red),
                    const SizedBox(width: 6),
                    Text(shift.closedByUserName!, style: const TextStyle(fontWeight: FontWeight.w500)),
                  ],
                )
              : const Text('-', style: TextStyle(color: Colors.grey)),
        ),
        DataCell(Text(shift.cashRegisterName ?? 'Caja ${shift.cashRegisterId}')),
        DataCell(Text(DateFormat('dd/MM HH:mm').format(shift.openedAt.toLocal()))),
        DataCell(Text(shift.closedAt != null ? DateFormat('dd/MM HH:mm').format(shift.closedAt!.toLocal()) : 'En curso...')),
        DataCell(Text(currencyFormat.format(shift.openingBalance))),
        DataCell(Text(currencyFormat.format(shift.cashSales ?? 0))),
        DataCell(Text(
          shift.isOpen ? '-' : currencyFormat.format(diff),
          style: TextStyle(
            color: shift.isOpen ? Colors.grey : (diff == 0 ? Colors.green : Colors.red),
            fontWeight: FontWeight.bold,
          ),
        )),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: shift.isOpen ? Colors.green.shade50 : Colors.blueGrey.shade50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              shift.isOpen ? 'Abierto' : 'Cerrado',
              style: TextStyle(
                color: shift.isOpen ? Colors.green.shade700 : Colors.blueGrey.shade700,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showShiftDetail(BuildContext context, CashRegisterShift shift) {
    final currencyFormat = NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 0);
    final isClosed = !shift.isOpen;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.receipt_long, color: Colors.blue.shade700),
            const SizedBox(width: 10),
            Text('Detalle del Turno #${shift.id}'),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: shift.isOpen ? Colors.green.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: shift.isOpen ? Colors.green.shade200 : Colors.grey.shade300),
              ),
              child: Text(
                shift.isOpen ? 'ABIERTO' : 'CERRADO',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: shift.isOpen ? Colors.green.shade700 : Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailHeader(shift),
                const Divider(height: 32),
                _sectionTitle('Desglose de Ventas'),
                _detailRow('Ventas en Efectivo', currencyFormat.format(shift.cashSales ?? 0)),
                _detailRow('Ventas con Tarjeta', currencyFormat.format(shift.cardSales ?? 0)),
                _detailRow('Ventas por Transferencia', currencyFormat.format(shift.transferSales ?? 0)),
                _detailRow('Ventas con Cheque', currencyFormat.format(shift.checkSales ?? 0)),
                if (shift.totalSurcharge != null && shift.totalSurcharge! > 0)
                   _detailRow('Recargos Aplicados', currencyFormat.format(shift.totalSurcharge!), isBold: true, color: Colors.orange.shade800),
                const Divider(height: 32),
                _sectionTitle('Balance de Caja'),
                _detailRow('Monto Inicial', currencyFormat.format(shift.openingBalance)),
                _detailRow('Total Ventas (Neto)', currencyFormat.format(shift.totalSales ?? 0), isBold: true),
                if (isClosed) ...[
                  const SizedBox(height: 8),
                  _detailRow('Esperado en Caja', currencyFormat.format(shift.expectedBalance ?? 0)),
                  _detailRow('Declarado (Real)', currencyFormat.format(shift.actualBalance ?? 0)),
                  const Divider(height: 16),
                  _detailRow(
                    'Diferencia',
                    currencyFormat.format(shift.difference ?? 0),
                    isBold: true,
                    color: (shift.difference ?? 0) == 0 ? Colors.green : Colors.red,
                  ),
                ],
                const Divider(height: 32),
                _sectionTitle('Auditoría de Ventas'),
                const SizedBox(height: 12),
                _ShiftSalesList(shiftId: shift.id),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _detailHeader(CashRegisterShift shift) {
    return Column(
      children: [
        Row(
          children: [
            _headerItem('Caja', shift.cashRegisterName ?? '-', Icons.desktop_windows),
            const SizedBox(width: 24),
            _headerItem('Apertura', shift.userName ?? '-', Icons.person),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _headerItem('Fecha Inicio', DateFormat('dd/MM/yyyy HH:mm').format(shift.openedAt.toLocal()), Icons.calendar_today),
            const SizedBox(width: 24),
            if (shift.closedAt != null)
              _headerItem('Fecha Cierre', DateFormat('dd/MM/yyyy HH:mm').format(shift.closedAt!.toLocal()), Icons.event_available),
          ],
        ),
      ],
    );
  }

  Widget _headerItem(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade900, letterSpacing: 1.1)),
    );
  }

  Widget _detailRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: isBold ? FontWeight.bold : FontWeight.w500, color: color)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 2: KARDEX (Movimientos de Stock)
// ─────────────────────────────────────────────────────────────────────────────
class _StockMovementsTab extends StatefulWidget {
  const _StockMovementsTab();

  @override
  State<_StockMovementsTab> createState() => _StockMovementsTabState();
}

class _StockMovementsTabState extends State<_StockMovementsTab> {
  bool _isLoading = true;
  List<dynamic> _movements = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchStockMovements();
  }

  Future<void> _fetchStockMovements() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final client = authProvider.apiClient;
      if (client == null) throw Exception('ApiClient no inicializado');

      final rawBaseUrl = authProvider.repository.remoteDataSource.baseUrl.trim();
      // Normalizar URL para evitar dobles slashes
      final baseUrl = rawBaseUrl.endsWith('/') 
          ? rawBaseUrl.substring(0, rawBaseUrl.length - 1) 
          : rawBaseUrl;

      final response = await client.get(
        Uri.parse('$baseUrl/audit/stock?per_page=100'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _movements = data['data'] ?? [];
          _isLoading = false;
        });
      } else {
        throw Exception('Servidor respondió con error ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        final errorStr = e.toString();
        if (errorStr.contains('Servidor respondió con error')) {
           _errorMessage = 'Error en el servidor backend. Contacte a soporte técnico.';
        } else if (errorStr.contains('NetworkException') || errorStr.contains('SocketException')) {
           _errorMessage = 'Error de conexión: No se pudo alcanzar el servidor. Verifique configuración.';
        } else {
           _errorMessage = errorStr.replaceAll('Exception: ', '');
        }
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error al cargar movimientos: $_errorMessage'),
            const SizedBox(height: 16),
            FilledButton(onPressed: _fetchStockMovements, child: const Text('Reintentar')),
          ],
        ),
      );
    }

    if (_movements.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text('No hay movimientos de stock registrados.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Movimientos de Stock',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Auditoría de todos los ingresos y egresos de mercadería',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.blueGrey),
                onPressed: _fetchStockMovements,
                tooltip: 'Recargar Movimientos',
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15, offset: const Offset(0, 5)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: MediaQuery.of(context).size.width - 48,
                    ),
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(Colors.blueGrey.shade50),
                      columnSpacing: 32,
                      dataRowMinHeight: 65,
                      dataRowMaxHeight: 65,
                      columns: const [
                        DataColumn(label: Text('Fecha y Hora', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Usuario', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Producto', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Movimiento', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Cant.', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Motivo / Referencia', style: TextStyle(fontWeight: FontWeight.bold))),
                      ],
                      rows: _movements.map<DataRow>((mov) {
                        final typeStr = mov['type'].toString().toLowerCase();
                        final isOut = typeStr == 'out' || typeStr == 'sale' || typeStr == 'decrement';
                        final typeLabel = switch (typeStr) {
                          'in'       => 'INGRESO',
                          'out'      => 'EGRESO',
                          'sale'     => 'VENTA',
                          'decrement'=> 'BAJA',
                          'increment'=> 'ALTA',
                          _ => typeStr.toUpperCase(),
                        };
                        
                        // Formatear usuario
                        final userName = mov['user']?['name'] ?? 'Sistema (Auto)';
                        final isSystem = userName.contains('Sistema');

                        return DataRow(cells: [
                          DataCell(Text(DateFormat('dd/MM/yyyy HH:mm').format(
                            DateTime.parse(mov['created_at']).toLocal(),
                          ))),
                          DataCell(Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(isSystem ? Icons.computer : Icons.person, size: 16, color: isSystem ? Colors.blueGrey.shade300 : Colors.blueAccent),
                              const SizedBox(width: 8),
                              Text(userName, style: TextStyle(
                                fontWeight: isSystem ? FontWeight.normal : FontWeight.w500,
                                color: isSystem ? Colors.blueGrey.shade400 : Colors.black87,
                              )),
                            ],
                          )),
                          DataCell(ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 250),
                            child: Text(mov['product']?['name'] ?? 'Desconocido', overflow: TextOverflow.ellipsis),
                          )),
                          DataCell(Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isOut ? Colors.red.shade50 : Colors.green.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: isOut ? Colors.red.shade100 : Colors.green.shade100),
                            ),
                            child: Text(
                              typeLabel,
                              style: TextStyle(
                                color: isOut ? Colors.red.shade700 : Colors.green.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          )),
                          DataCell(Builder(
                            builder: (context) {
                              final formatter = NumberFormat.decimalPattern('es_AR');
                              final rawQty = double.tryParse(mov['quantity'].toString()) ?? 0;
                              final absQty = rawQty.abs();
                              
                              final product = mov['product'];
                              final isByWeight = product?['is_sold_by_weight'] == true || product?['is_sold_by_weight'] == 1;
                              final unitType = product?['unit_type'] ?? (isByWeight ? 'kg' : 'un');
                              
                              // Formatear como entero si no tiene decimales, sino usar el formateador regional
                              final qtyStr = absQty == absQty.toInt() 
                                  ? absQty.toInt().toString() 
                                  : formatter.format(absQty);
                              
                              return Text(
                                '${isOut ? "-" : "+"}$qtyStr $unitType',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: isOut ? Colors.red.shade600 : Colors.green.shade600,
                                ),
                              );
                            },
                          )),
                          DataCell(Text(mov['notes'] ?? '-', style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.blueGrey))),
                        ]);
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShiftSalesList extends StatefulWidget {
  final int shiftId;
  const _ShiftSalesList({required this.shiftId});

  @override
  State<_ShiftSalesList> createState() => _ShiftSalesListState();
}

class _ShiftSalesListState extends State<_ShiftSalesList> {
  bool _loading = true;
  List<dynamic> _sales = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchSales();
  }

  Future<void> _fetchSales() async {
    try {
      final auth = context.read<AuthProvider>();
      final client = auth.apiClient;
      if (client == null) return;
      
      final rawBaseUrl = auth.repository.remoteDataSource.baseUrl.trim();
      final baseUrl = rawBaseUrl.endsWith('/') ? rawBaseUrl.substring(0, rawBaseUrl.length - 1) : rawBaseUrl;

      final response = await client.get(
        Uri.parse('$baseUrl/sales?shift_id=${widget.shiftId}&period=shift'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _sales = json.decode(response.body);
            _loading = false;
          });
        }
      } else {
        throw Exception('Error al cargar ventas');
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: Padding(
      padding: EdgeInsets.all(20.0),
      child: CircularProgressIndicator(),
    ));
    if (_error != null) return Text('Error: $_error', style: const TextStyle(color: Colors.red));
    if (_sales.isEmpty) return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Text('No hay ventas registradas en este turno.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
    );

    final fmt = NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 0);

    return Column(
      children: _sales.map((sale) {
        final saleTotal = double.tryParse(sale['total']?.toString() ?? '0') ?? 0.0;
        final saleSurcharge = double.tryParse(sale['total_surcharge']?.toString() ?? '0') ?? 0.0;
        final total = saleTotal + saleSurcharge;
        final priceList = sale['price_list'] ?? 'Minorista';
        final isVoided = sale['status'] == 'voided';
        
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isVoided ? Colors.red.shade50 : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isVoided ? Colors.red.shade100 : Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isVoided ? Colors.red.shade100 : Colors.blue.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isVoided ? Icons.block : Icons.shopping_bag_outlined,
                  size: 16,
                  color: isVoided ? Colors.red.shade700 : Colors.blue.shade700,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Venta #${sale['id']}', 
                      style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 14,
                        decoration: isVoided ? TextDecoration.lineThrough : null,
                        color: isVoided ? Colors.red.shade700 : Colors.black87,
                      )
                    ),
                    Text(
                      DateFormat('HH:mm').format(DateTime.parse(sale['created_at']).toLocal()), 
                      style: const TextStyle(fontSize: 11, color: Colors.grey)
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                   Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isVoided ? Colors.red.shade100 : Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      priceList.toUpperCase(), 
                      style: TextStyle(
                        fontSize: 9, 
                        fontWeight: FontWeight.bold, 
                        color: isVoided ? Colors.red.shade900 : Colors.blue.shade900
                      )
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fmt.format(total), 
                    style: TextStyle(
                      fontWeight: FontWeight.bold, 
                      fontSize: 15,
                      color: isVoided ? Colors.red : Colors.black87
                    )
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
