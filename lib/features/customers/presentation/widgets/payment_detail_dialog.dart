import 'package:flutter/material.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/features/customers/models/customer_model.dart';
import 'package:intl/intl.dart';

/// Modal con los detalles de un abono registrado en Cuenta Corriente.
class PaymentDetailDialog extends StatelessWidget {
  final CustomerTransaction transaction;
  final String customerName;

  const PaymentDetailDialog({
    super.key,
    required this.transaction,
    required this.customerName,
  });

  static Future<void> show(
    BuildContext context, {
    required CustomerTransaction transaction,
    required String customerName,
  }) {
    return showDialog(
      context: context,
      builder: (_) => PaymentDetailDialog(
        transaction: transaction,
        customerName: customerName,
      ),
    );
  }

  /// Devuelve ícono y etiqueta legible del método de pago.
  (IconData, String) _methodInfo(String? method) {
    switch (method?.toLowerCase()) {
      case 'efectivo':
      case 'cash':
        return (Icons.payments_outlined, 'Efectivo');
      case 'transferencia':
      case 'transfer':
        return (Icons.swap_horiz_rounded, 'Transferencia Bancaria');
      case 'tarjeta':
      case 'card':
        return (Icons.credit_card_outlined, 'Tarjeta');
      case 'cheque':
        return (Icons.receipt_outlined, 'Cheque');
      case 'cuenta_corriente':
        return (Icons.account_balance_wallet_outlined, 'Cuenta Corriente');
      default:
        return (Icons.payment_outlined, method ?? 'No especificado');
    }
  }

  @override
  Widget build(BuildContext context) {
    final localDate = transaction.createdAt.toLocal();
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(localDate);
    final isRefund = transaction.type == 'refund';
    // CC-09: En un reintegro de saldo a favor (refund), balanceAfter = balanceBefore + amount,
    // por lo que el saldo previo real es balanceAfter - amount.
    final balanceBefore = isRefund
        ? (transaction.balanceAfter - transaction.amount)
        : (transaction.balanceAfter + transaction.amount);
    final (methodIcon, methodLabel) = _methodInfo(transaction.paymentMethod);

    return AppModalShell(
      title: isRefund ? 'Reintegro Registrado' : 'Abono Registrado',
      subtitle: customerName,
      icon: isRefund ? Icons.replay_rounded : Icons.check_circle_outline,
      accent: isRefund ? AppModalAccent.amber : AppModalAccent.emerald,
      compact: true,
      maxWidth: 460,
      bodyPadding: EdgeInsets.zero,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Monto central destacado ──
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: isRefund ? Colors.amber.shade50 : Colors.green.shade50,
              border: const Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              children: [
                Text(
                  '${isRefund ? '-' : '+'}\$${transaction.amount.toCurrency()}',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: isRefund ? Colors.amber.shade800 : Colors.green.shade700,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isRefund ? 'Reintegro de saldo a favor' : 'Abono recibido',
                  style: TextStyle(
                    fontSize: 14,
                    color: isRefund ? Colors.amber.shade800 : Colors.green.shade600,
                  ),
                ),
              ],
            ),
          ),

          // ── Detalles ──
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Método de pago
                _detailRow(
                  icon: methodIcon,
                  label: 'Método de Pago',
                  value: methodLabel,
                  color: Colors.blueGrey.shade700,
                ),
                const SizedBox(height: 16),

                  // Fecha
                  _detailRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Fecha y Hora',
                    value: dateStr,
                  ),
                  const SizedBox(height: 16),

                  // Saldo antes / después
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(balanceBefore < 0 ? 'Saldo a favor anterior:' : 'Deuda anterior:', 
                                 style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                            Text(
                              '\$${balanceBefore.abs().toCurrency()}',
                              style: TextStyle(
                                color: balanceBefore > 0 ? Colors.red.shade600 : (balanceBefore < 0 ? Colors.green.shade600 : Colors.grey.shade600),
                                fontWeight: FontWeight.w600, fontSize: 14
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Divider(height: 1),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(transaction.balanceAfter < 0 ? 'Saldo a favor actual:' : 'Deuda actual:', 
                                 style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                            Text(
                              '\$${transaction.balanceAfter.abs().toCurrency()}',
                              style: TextStyle(
                                color: transaction.balanceAfter > 0
                                    ? Colors.orange.shade700
                                    : (transaction.balanceAfter < 0 ? Colors.green.shade700 : Colors.grey.shade600),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        if (transaction.balanceAfter <= 0) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  transaction.balanceAfter < 0 ? Icons.savings_outlined : Icons.verified_outlined, 
                                  size: 16, 
                                  color: Colors.green.shade700
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  transaction.balanceAfter < 0 ? 'Saldo a favor' : 'Cuenta saldada ✓',
                                  style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Descripción / nota (si existe)
                  if (transaction.description != null && transaction.description!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _detailRow(
                      icon: Icons.notes_outlined,
                      label: 'Nota',
                      value: transaction.description!,
                    ),
                  ],
              ],
            ),
          ),
        ],
      ),
      footerActions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green.shade600,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          ),
          child: const Text('Cerrar', style: TextStyle(fontSize: 14.5)),
        ),
      ],
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String value,
    Color? color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color ?? Colors.blueGrey.shade500),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}
