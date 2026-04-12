import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cash_register_provider.dart';
import '../../domain/entities/cash_register_shift.dart';
import 'package:intl/intl.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';

class ShiftAuditScreen extends StatefulWidget {
  const ShiftAuditScreen({Key? key}) : super(key: key);

  @override
  State<ShiftAuditScreen> createState() => _ShiftAuditScreenState();
}

class _ShiftAuditScreenState extends State<ShiftAuditScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CashRegisterProvider>().loadAllShifts();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: GlobalAppBar(
        currentRoute: '/shift-audit',
        title: 'Auditoría de Cajas',
        extraAction: IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Recargar Historial',
          onPressed: () {
            context.read<CashRegisterProvider>().loadAllShifts();
          },
        ),
      ),
      body: Consumer<CashRegisterProvider>(
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
                const Text(
                  'Historial Global de Turnos (Cierres Z)',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Registro completo auditado (Solo para administradores)',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: DataTable(
                      showCheckboxColumn: false,
                      headingRowColor: MaterialStateProperty.all(Colors.blueGrey.shade50),
                      columnSpacing: 24,
                      dataRowMinHeight: 60,
                      dataRowMaxHeight: 60,
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
                      rows: shifts.map((shift) => _buildDataRow(shift)).toList(),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  DataRow _buildDataRow(CashRegisterShift shift) {
    final diff = shift.difference ?? 0.0;
    
    String userLabel = _getUserName(shift);

    return DataRow(
      onSelectChanged: (_) => _showShiftDetails(context, shift),
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
            : const Text('---', style: TextStyle(color: Colors.grey)),
        ),
        DataCell(
          Chip(
            avatar: const Icon(Icons.computer, size: 14, color: Colors.indigo),
            label: Text(
              shift.cashRegisterName ?? 'Principal',
              style: const TextStyle(fontSize: 12),
            ),
            backgroundColor: Colors.indigo.shade50,
            side: BorderSide.none,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
        DataCell(Text(_formatDate(shift.openedAt))),
        DataCell(Text(shift.closedAt != null ? _formatDate(shift.closedAt!) : '---')),
        DataCell(Text('\$${shift.openingBalance.toCurrency()}')),
        DataCell(Text('\$${((shift.cashSales ?? 0) + (shift.cardSales ?? 0) + (shift.transferSales ?? 0)).toCurrency()}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
        DataCell(_buildDifferenceBadge(diff, shift.status)),
        DataCell(_buildStatusBadge(shift.status)),
      ],
    );
  }

  String _getUserName(CashRegisterShift shift) {
    return shift.userName ?? 'Desconocido';
  }

  void _showShiftDetails(BuildContext context, CashRegisterShift shift) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.receipt_long, color: Colors.blueGrey),
            const SizedBox(width: 10),
            Text('Detalles del Turno #${shift.id}'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Terminal Header Chip ---
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.indigo.shade100),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.computer, size: 16, color: Colors.indigo.shade600),
                      const SizedBox(width: 8),
                      Text(
                        'Terminal: ${shift.cashRegisterName ?? "Caja Principal"}',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade800),
                      ),
                    ],
                  ),
                ),
                _buildDetailRow('Abrió:', _getUserName(shift)),
                if (shift.closedByUserName != null)
                  _buildDetailRow('Cerró:', shift.closedByUserName!),
                _buildDetailRow('Apertura:', _formatDate(shift.openedAt)),
                _buildDetailRow('Cierre:', shift.closedAt != null ? _formatDate(shift.closedAt!) : 'En curso'),
                const Divider(height: 32),
                _buildDetailRow('Fondo Inicial (Apertura):', '\$${shift.openingBalance.toCurrency()}', isBold: true),
                _buildDetailRow('Ventas Netas Totales:', '\$${((shift.cashSales ?? 0) + (shift.cardSales ?? 0) + (shift.transferSales ?? 0)).toCurrency()}'),
                Padding(
                  padding: const EdgeInsets.only(left: 16.0),
                  child: Column(
                    children: [
                      _buildDetailRow('• En Efectivo', '\$${(shift.cashSales ?? 0).toCurrency()}'),
                      _buildDetailRow('• Con Tarjeta', '\$${(shift.cardSales ?? 0).toCurrency()}'),
                      _buildDetailRow('• Transf.', '\$${(shift.transferSales ?? 0).toCurrency()}'),
                    ],
                  ),
                ),
                const Divider(height: 32),
                _buildDetailRow('Efectivo Esperado Múltiple:', '\$${(shift.expectedBalance ?? (shift.openingBalance + (shift.cashSales ?? 0))).toCurrency()}', isBold: true),
                _buildDetailRow('Dinero Físico Contado:', '\$${(shift.actualBalance ?? 0.0).toCurrency()}', isBold: true),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Diferencia:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    _buildDifferenceBadge(shift.difference ?? 0.0, shift.status),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.blueGrey)),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              fontSize: isBold ? 16 : 14,
              color: isBold ? Colors.black87 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDifferenceBadge(double diff, String status) {
    if (status == 'open') return const Text('---');
    
    Color bgColor;
    Color textColor;
    String prefix;

    if (diff == 0) {
      bgColor = Colors.green.shade100;
      textColor = Colors.green.shade800;
      prefix = 'Cuadre Exacto';
    } else if (diff > 0) {
      bgColor = Colors.teal.shade100;
      textColor = Colors.teal.shade800;
      prefix = '+ \$${diff.toCurrency()} (Sobrante)';
    } else {
      bgColor = Colors.red.shade100;
      textColor = Colors.red.shade800;
      prefix = '- \$${diff.abs().toCurrency()} (Faltante)';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
      child: Text(prefix, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }

  Widget _buildStatusBadge(String status) {
    final isOpen = status == 'open';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isOpen ? Colors.blue.shade100 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isOpen ? 'ABIERTO' : 'CERRADO Z',
        style: TextStyle(
          color: isOpen ? Colors.blue.shade700 : Colors.grey.shade700,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return DateFormat('dd/MM/yyyy HH:mm').format(dt);
  }
}
