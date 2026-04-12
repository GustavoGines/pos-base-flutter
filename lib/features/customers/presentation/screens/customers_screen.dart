import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/customer_model.dart';
import '../../providers/customer_provider.dart';
import '../widgets/customer_form_dialog.dart';
import '../widgets/payment_dialog.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  Customer? _selectedCustomer;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<CustomerProvider>().fetchCustomers());
  }

  void _onCustomerSelected(Customer customer) {
    setState(() {
      _selectedCustomer = customer;
    });
    // Fetch individual customer details (including transactions)
    if (_selectedCustomer != null) {
      context.read<CustomerProvider>().fetchSingleCustomer(_selectedCustomer!.id);
    }
  }

  void _confirmDelete(BuildContext context, int id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Cliente'),
        content: Text('¿Estás seguro de que deseas eliminar permanentemente a "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await context.read<CustomerProvider>().deleteCustomer(id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cliente eliminado'), backgroundColor: Colors.green));
                  if (_selectedCustomer?.id == id) {
                    setState(() => _selectedCustomer = null);
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CustomerProvider>(
      builder: (context, provider, _) {
        // Mantener actualizado el cliente seleccionado 
        if (_selectedCustomer != null) {
          final updated = provider.customers.where((c) => c.id == _selectedCustomer!.id).firstOrNull;
          if (updated != null) {
            _selectedCustomer = updated;
          }
        }

        return Scaffold(
          appBar: const GlobalAppBar(currentRoute: '/cuentas-corrientes'),
          body: Row(
            children: [
              // ── Panel Izquierdo: Lista de Clientes ──
              Container(
                width: 380,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(right: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Column(
                  children: [
                    // Buscador y Botón Nuevo
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              decoration: InputDecoration(
                                hintText: 'Buscar nombre o DNI...',
                                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                                prefixIcon: const Icon(Icons.search, size: 20),
                                filled: true,
                                fillColor: Colors.white,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                              ),
                              onChanged: (val) {
                                provider.setSearchQuery(val);
                                setState(() => _selectedCustomer = null);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: 'Nuevo Cliente',
                            child: IconButton.filled(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) => const CustomerFormDialog(),
                                );
                              },
                              icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                              style: IconButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.all(12),
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                    // Cargando
                    if (provider.isLoading) 
                       const LinearProgressIndicator(),

                    // Lista Expandida
                    Expanded(
                      child: provider.customers.isEmpty && !provider.isLoading
                          ? _EmptyStateList()
                          : ListView.separated(
                              itemCount: provider.customers.length,
                              separatorBuilder: (context, index) => const Divider(height: 1, indent: 64),
                              itemBuilder: (context, index) {
                                final customer = provider.customers[index];
                                final isDebtor = customer.balance > 0;
                                final isSelected = _selectedCustomer?.id == customer.id;

                                return ListTile(
                                  selected: isSelected,
                                  selectedTileColor: Colors.blue.shade50,
                                  onTap: () => _onCustomerSelected(customer),
                                  leading: CircleAvatar(
                                    backgroundColor: isSelected ? Colors.blue.shade600 : Colors.blue.shade100,
                                    foregroundColor: isSelected ? Colors.white : Colors.blue.shade800,
                                    child: const Icon(Icons.person, size: 20),
                                  ),
                                  title: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          customer.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          maxLines: 1, overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        '\$${customer.balance.toCurrency()}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: isDebtor ? Colors.red.shade700 : Colors.green.shade700,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text('DNI: ${customer.documentNumber}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                            if (customer.phone != null && customer.phone!.isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              Text('· 📞 ${customer.phone}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                            ]
                                          ],
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            InkWell(
                                              onTap: () => showDialog(context: context, barrierDismissible: false, builder: (_) => CustomerFormDialog(customer: customer)),
                                              child: const Padding(padding: EdgeInsets.all(4.0), child: Icon(Icons.edit, size: 16, color: Colors.blueGrey)),
                                            ),
                                            InkWell(
                                              onTap: () => _confirmDelete(context, customer.id, customer.name),
                                              child: const Padding(padding: EdgeInsets.all(4.0), child: Icon(Icons.delete_outline, size: 16, color: Colors.blueGrey)),
                                            ),
                                          ],
                                        )
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),

              // ── Panel Derecho: Detalle del Cliente ──
              Expanded(
                child: Container(
                  color: Colors.grey.shade100,
                  child: _selectedCustomer == null
                      ? const _EmptyStateDetail()
                      : _CustomerDetailPanel(customer: _selectedCustomer!),
                ),
              ),
            ],
          ),
        );
      },
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
          Icon(Icons.people_outline, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No hay clientes registrados', style: TextStyle(color: Colors.grey.shade500)),
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
          Icon(Icons.account_box_outlined, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('Seleccione un cliente de la lista', style: TextStyle(color: Colors.grey.shade500, fontSize: 18)),
          const SizedBox(height: 8),
          Text('Podrá ver su estado de cuenta y registrar pagos', style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
        ],
      ),
    );
  }
}

class _CustomerDetailPanel extends StatelessWidget {
  final Customer customer;

  const _CustomerDetailPanel({required this.customer});

  @override
  Widget build(BuildContext context) {
    final isDebtor = customer.balance > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      CircleAvatar(
                        backgroundColor: isDebtor ? Colors.red.shade50 : Colors.green.shade50,
                        foregroundColor: isDebtor ? Colors.red.shade700 : Colors.green.shade700,
                        radius: 20,
                        child: const Icon(Icons.person, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Text(customer.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.badge_outlined, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Text('DNI: ${customer.documentNumber}', style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                      if (customer.phone != null && customer.phone!.isNotEmpty) ...[
                        const SizedBox(width: 16),
                        Icon(Icons.phone_outlined, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text(customer.phone!, style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                      ],
                      if (customer.creditLimit > 0) ...[
                        const SizedBox(width: 16),
                        Icon(Icons.credit_score_outlined, size: 14, color: Colors.blueGrey.shade600),
                        const SizedBox(width: 4),
                        Text('Límite de Crédito: \$${customer.creditLimit.toCurrency()}', style: TextStyle(color: Colors.blueGrey.shade800, fontWeight: FontWeight.w500)),
                      ]
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Saldo Actual', style: TextStyle(fontSize: 14, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                  Text(
                    '\$${customer.balance.toCurrency()}',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: isDebtor ? Colors.red.shade700 : Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Lista de transacciones o movimientos (Ledger)
        Expanded(
          child: Container(
            color: Colors.grey.shade100,
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Libro Mayor de Cuentas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                const SizedBox(height: 16),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
                      border: Border.all(color: Colors.black12),
                    ),
                    child: customer.transactions.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.history_toggle_off, size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              Text('No hay movimientos registrados.', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                            ],
                          ),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: customer.transactions.length,
                            separatorBuilder: (ctx, i) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final trx = customer.transactions[index];
                              final isPayment = trx.type == 'payment';

                              final localDate = trx.createdAt.toLocal();

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                leading: CircleAvatar(
                                  radius: 20,
                                  backgroundColor: isPayment ? Colors.green.shade50 : Colors.red.shade50,
                                  child: Icon(
                                    isPayment ? Icons.arrow_downward : Icons.shopping_cart_outlined,
                                    color: isPayment ? Colors.green.shade700 : Colors.red.shade700,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  trx.description ?? (isPayment ? 'Abono en Caja' : 'Factura Impaga de Pos'),
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    '${localDate.day}/${localDate.month}/${localDate.year} ${localDate.hour}:${localDate.minute.toString().padLeft(2, '0')}', 
                                    style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13)
                                  ),
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${isPayment ? '+' : '-'}\$${trx.amount.toCurrency()}',
                                      style: TextStyle(
                                        color: isPayment ? Colors.green.shade700 : Colors.red.shade700,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Acumulado: \$${trx.balanceAfter.toCurrency()}',
                                      style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade500, fontWeight: FontWeight.normal),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Footer Actions (Botón Registrar Pago)
        if (isDebtor)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.black12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.account_balance_wallet, size: 24),
                  label: const Text('REGISTRAR ABONO', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1, fontSize: 15)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => PaymentDialog(customer: customer),
                    );
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}
