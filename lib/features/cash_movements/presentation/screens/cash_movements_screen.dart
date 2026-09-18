import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../../core/presentation/widgets/global_app_bar.dart';
import '../../providers/cash_movement_provider.dart';
import '../widgets/movement_form_dialog.dart';

class CashMovementsScreen extends StatefulWidget {
  const CashMovementsScreen({super.key});

  @override
  State<CashMovementsScreen> createState() => _CashMovementsScreenState();
}

class _CashMovementsScreenState extends State<CashMovementsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CashMovementProvider>().fetchMovements();
    });
  }

  void _showFormDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const MovementFormDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlobalAppBar(currentRoute: '/cash-movements'),
      body: Consumer<CashMovementProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.movements.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text('No hay movimientos en este turno.', style: TextStyle(color: Colors.grey.shade600)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _showFormDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Registrar Movimiento'),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                color: Colors.white,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Historial de Caja (Turno Actual)', style: Theme.of(context).textTheme.headlineSmall),
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
              ),
              Expanded(
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: ListView.separated(
                    itemCount: provider.movements.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final movement = provider.movements[index];
                      final isExpenseOrWithdrawal = movement.type == 'expense' || movement.type == 'withdrawal';
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

                      // Mapeo al Español
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

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: isExpenseOrWithdrawal ? Colors.red.shade50 : Colors.green.shade50,
                          radius: 24,
                          child: Icon(
                            isExpenseOrWithdrawal ? Icons.arrow_downward : Icons.arrow_upward,
                            color: amountColor,
                            size: 22,
                          ),
                        ),
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                subtitle,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ),
                            Text(
                              '$amountPrefix ${NumberFormat.currency(symbol: '\$').format(movement.amount)}',
                              style: TextStyle(
                                color: amountColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.person_outline, size: 14, color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(
                                  'Registrado por: $authorInfo',
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                ),
                              ],
                            ),
                            if (movement.supplier != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.storefront, size: 14, color: Colors.blue.shade700),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Proveedor: ${movement.supplier?['name'] ?? ''}',
                                    style: TextStyle(color: Colors.blue.shade700, fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 10),
                            Row(
                              children: [
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
                                        style: TextStyle(color: Colors.grey.shade700, fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                Row(
                                  children: [
                                    Icon(Icons.access_time, size: 12, color: Colors.grey.shade500),
                                    const SizedBox(width: 4),
                                    Text(
                                      DateFormat('HH:mm').format(movement.createdAt.toLocal()),
                                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
