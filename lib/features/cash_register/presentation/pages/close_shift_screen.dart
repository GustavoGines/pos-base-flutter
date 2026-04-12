import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cash_register_provider.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'cash_shift_summary_screen.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';

class CloseShiftScreen extends StatefulWidget {
  const CloseShiftScreen({Key? key}) : super(key: key);

  @override
  State<CloseShiftScreen> createState() => _CloseShiftScreenState();
}

class _CloseShiftScreenState extends State<CloseShiftScreen> {
  final _countedCashController = TextEditingController();

  @override
  void dispose() {
    _countedCashController.dispose();
    super.dispose();
  }

  Future<void> _handleCloseShift() async {
    final countedCash = double.tryParse(_countedCashController.text.replaceAll(',', '.'));
    if (countedCash == null || countedCash < 0) {
      SnackBarService.error(context, 'Ingrese un monto de efectivo contado válido.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Cierre de Caja'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('¿Está seguro de que desea cerrar el turno actual?'),
            const SizedBox(height: 12),
            Text(
              'Efectivo contado: \$${countedCash.toCurrency()}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar Turno', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final provider = context.read<CashRegisterProvider>();
    final currentUser = context.read<AuthProvider>().currentUser;
    final closerUserId = currentUser?['id'] as int?;
    final closedShift = await provider.closeShift(countedCash, closerUserId: closerUserId);
    
    if (mounted) {
      if (closedShift != null) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => CashShiftSummaryScreen(closedShift: closedShift)),
          (route) => false,
        );
      } else {
        SnackBarService.error(context, provider.errorMessage ?? 'Error al cerrar el turno.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CashRegisterProvider>(
      builder: (context, provider, _) {
        final shift = provider.currentShift;
        if (shift == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Cierre de Caja'),
              centerTitle: true,
            ),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.info_outline, size: 64, color: Colors.blueGrey),
                  const SizedBox(height: 16),
                  const Text('No hay ningún turno activo en este momento.', style: TextStyle(fontSize: 18, color: Colors.blueGrey)),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: () {
                      // Navigate back. This will usually return to LicenseLockScreen or Home.
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Volver al inicio'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Cierre de Caja (Z)'),
            centerTitle: true,
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: Colors.red.shade100,
                              child: Icon(Icons.point_of_sale, size: 30, color: Colors.red.shade700),
                            ),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Cierre de Turno', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                                Text(
                                  'Abierta: ${_formatDate(shift.openedAt)}',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        const Divider(),
                        
                        // Resumen del turno
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text('Resumen del Turno', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                        _summaryRow(
                          icon: Icons.open_in_new,
                          label: 'Saldo inicial de caja:',
                          value: '\$${shift.openingBalance.toCurrency()}',
                          color: Colors.blueGrey,
                        ),

                        const SizedBox(height: 24),
                        const Divider(),

                        // Campo de efectivo contado
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12.0),
                          child: Text('Arqueo físico de la caja', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                        TextField(
                          controller: _countedCashController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _handleCloseShift(),
                          decoration: const InputDecoration(
                            labelText: 'Efectivo contado en la caja física',
                            prefixIcon: Icon(Icons.calculate),
                            prefixText: '\$ ',
                            border: OutlineInputBorder(),
                            helperText: 'Cuente todo el efectivo físico del cajón (incluye el saldo inicial)',
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Error message
                        if (provider.errorMessage != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    provider.errorMessage!,
                                    style: TextStyle(color: Colors.red.shade700),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: 16),

                        // Botón de cierre
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.lock_outline),
                            label: provider.isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Cerrar Turno y Generar Z', style: TextStyle(fontSize: 16)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade600,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: provider.isLoading ? null : _handleCloseShift,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _summaryRow({required IconData icon, required String label, required String value, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? Colors.grey.shade700),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final localDt = dt.toLocal();
    return '${localDt.day.toString().padLeft(2, '0')}/${localDt.month.toString().padLeft(2, '0')}/${localDt.year} ${localDt.hour.toString().padLeft(2, '0')}:${localDt.minute.toString().padLeft(2, '0')}';
  }
}
