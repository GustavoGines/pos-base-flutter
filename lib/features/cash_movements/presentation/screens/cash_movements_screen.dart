import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../../core/presentation/widgets/global_app_bar.dart';
import '../../providers/cash_movement_provider.dart';
import '../widgets/movement_form_dialog.dart';
import '../../../../core/theme/app_colors.dart';

class CashMovementsScreen extends StatefulWidget {
  const CashMovementsScreen({Key? key}) : super(key: key);

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

  void _showMovementForm() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const MovementFormDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlobalAppBar(title: 'Movimientos de Caja (Gastos)'),
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
                  Icon(Icons.account_balance_wallet_outlined, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text('No hay movimientos registrados en el turno actual.'),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _showMovementForm,
                    icon: const Icon(Icons.add),
                    label: const Text('Registrar Movimiento'),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Historial del Turno',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    ElevatedButton.icon(
                      onPressed: _showMovementForm,
                      icon: const Icon(Icons.add),
                      label: const Text('Nuevo Movimiento'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
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
                      
                      String subtitle = 'Categoría: $'{movement.category}';
                      if (movement.description != null && movement.description!.isNotEmpty) {
                        subtitle += ' | $'{movement.description}';
                      }
                      
                      String authorInfo = 'Registrado por: $'{movement.user?['name'] ?? 'Cajero'}';
                      if (movement.authorizer != null) {
                        authorInfo += ' (Aut: $'{movement.authorizer?['name'] ?? 'Admin'})';
                      }

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isExpenseOrWithdrawal ? Colors.red.shade50 : Colors.green.shade50,
                          child: Icon(
                            isExpenseOrWithdrawal ? Icons.arrow_downward : Icons.arrow_upward,
                            color: amountColor,
                          ),
                        ),
                        title: Text(
                          '$amountPrefix $'{NumberFormat.currency(symbol: '\$').format(movement.amount)}',
                          style: TextStyle(
                            color: amountColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(subtitle),
                            const SizedBox(height: 2),
                            Text(
                              authorInfo,
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                            ),
                            if (movement.supplier != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Proveedor: $'{movement.supplier?['name'] ?? ''}',
                                style: TextStyle(color: Colors.blue.shade700, fontSize: 12),
                              ),
                            ]
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              DateFormat('HH:mm').format(movement.createdAt.toLocal()),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              movement.paymentMethod.toUpperCase(),
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                            ),
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
