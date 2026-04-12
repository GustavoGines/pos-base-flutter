import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:flutter/material.dart';
import '../../domain/entities/cash_register_shift.dart';
import 'package:provider/provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../providers/cash_register_provider.dart';

class CashShiftSummaryScreen extends StatelessWidget {
  final CashRegisterShift closedShift;

  const CashShiftSummaryScreen({Key? key, required this.closedShift}) : super(key: key);

  void _exit(BuildContext context) {
    try {
      context.read<AuthProvider>().logout();
    } catch (_) {}
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  void _print(BuildContext context) async {
    final settings = context.read<SettingsProvider>().settings;
    final printer = context.read<CashRegisterProvider>().printerService;
    
    if (settings != null && printer != null) {
      await printer.printZCloseTicket(shift: closedShift, settings: settings).catchError((e) {
        debugPrint('Error printing summary: $e');
      });
    }
    if (context.mounted) {
      _exit(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final diff = closedShift.difference ?? 0.0;
    final isNegative = diff < 0;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Resumen de Cierre de Caja'),
        centerTitle: true,
        automaticallyImplyLeading: false, // Bloquear volver atrás
      ),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.green, size: 60),
                  const SizedBox(height: 16),
                  const Text(
                    'Turno Cerrado Correctamente',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.computer, size: 18, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            Text(
                              'Caja: ${closedShift.cashRegisterName ?? "Principal"}',
                              style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.person_outline, size: 18, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            Text(
                              'Abrió: ${closedShift.userName ?? "Desconocido"}',
                              style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        if (closedShift.closedByUserName != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.lock_person, size: 18, color: Colors.orange.shade700),
                              const SizedBox(width: 8),
                              Text(
                                'Cerró: ${closedShift.closedByUserName}',
                                style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  _buildRow('Fondo Inicial', '\$${closedShift.openingBalance.toCurrency()}'),
                  _buildRow('Ventas en Efectivo', '\$${(closedShift.cashSales ?? 0).toCurrency()}'),
                  _buildRow('Ventas con Tarjeta', '\$${(closedShift.cardSales ?? 0).toCurrency()}'),
                  _buildRow('Ventas por Transf.', '\$${(closedShift.transferSales ?? 0).toCurrency()}'),
                  _buildRow('Total Recargos (Tarj/Billeteras)', '\$${(closedShift.totalSurcharge ?? 0).toCurrency()}'),
                  const Divider(),
                  _buildRow('Efectivo Esperado', '\$${(closedShift.expectedBalance ?? 0).toCurrency()}', bold: true),
                  _buildRow('Efectivo Físico', '\$${(closedShift.actualBalance ?? 0).toCurrency()}', bold: true),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isNegative ? Colors.red.shade50 : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isNegative ? 'FALTANTE:' : 'SOBRANTE:',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isNegative ? Colors.red.shade700 : Colors.green.shade700,
                          ),
                        ),
                        Text(
                          '\$${diff.abs().toCurrency()}',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: isNegative ? Colors.red.shade700 : Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.print, size: 28),
                    label: const Text('Imprimir Cierre Z y Salir', style: TextStyle(fontSize: 18)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      backgroundColor: Colors.blue.shade800,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _print(context),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => _exit(context),
                    child: const Text('Continuar sin imprimir', style: TextStyle(color: Colors.grey)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
  }

  Widget _buildRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 16, color: Colors.black87, fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
          Text(value, style: TextStyle(fontSize: 16, color: Colors.black, fontWeight: bold ? FontWeight.w900 : FontWeight.w700)),
        ],
      ),
    );
  }
}
