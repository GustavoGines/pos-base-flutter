import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pos_provider.dart';
import 'package:frontend_desktop/features/customers/models/customer_model.dart';
import 'package:frontend_desktop/features/customers/providers/customer_provider.dart';
import 'package:frontend_desktop/features/customers/presentation/widgets/customer_form_dialog.dart';
import 'package:frontend_desktop/features/auth/presentation/widgets/admin_pin_dialog.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';

class PosQuickCustomerDialog extends StatefulWidget {
  const PosQuickCustomerDialog({super.key});

  @override
  State<PosQuickCustomerDialog> createState() => _PosQuickCustomerDialogState();
}

class _PosQuickCustomerDialogState extends State<PosQuickCustomerDialog> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final custProv = Provider.of<CustomerProvider>(context, listen: false);
      if (custProv.customers.isEmpty && !custProv.isLoading) {
        custProv.fetchCustomers();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleEditCustomer(Customer c) async {
    final edited = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CustomerFormDialog(customer: c),
    );
    if (edited == true && mounted) {
      await Provider.of<CustomerProvider>(context, listen: false).fetchCustomers(search: _searchCtrl.text.trim());
      if (mounted) {
        final pos = Provider.of<PosProvider>(context, listen: false);
        if (pos.selectedCustomer?.id == c.id) {
          final updated = Provider.of<CustomerProvider>(context, listen: false)
              .customers
              .where((cust) => cust.id == c.id)
              .firstOrNull;
          if (updated != null) {
            pos.selectCustomer(updated);
          }
        }
      }
    }
  }

  Future<void> _handleDeleteCustomer(Customer c) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Cliente'),
        content: Text('¿Estás seguro de que deseas eliminar permanentemente a "${c.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final isAuthorized = await AdminPinDialog.verify(
      context,
      action: 'Eliminar cliente de la base de datos',
    );
    if (!isAuthorized || !mounted) return;

    try {
      await Provider.of<CustomerProvider>(context, listen: false).deleteCustomer(c.id);
      if (mounted) {
        SnackBarService.success(context, 'Cliente "${c.name}" eliminado.');
        final pos = Provider.of<PosProvider>(context, listen: false);
        if (pos.selectedCustomer?.id == c.id) {
          pos.selectCustomer(null);
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarService.error(context, e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        width: 680,
        height: 540,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Cabecera
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1976D2).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.person_pin_circle_rounded, color: Color(0xFF1976D2), size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gestión Rápida de Cliente',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Asignar cliente al ticket actual o crear uno nuevo',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Card del Cliente Actualmente Asignado
            Consumer<PosProvider>(
              builder: (context, pos, _) {
                final customer = pos.selectedCustomer;
                if (customer == null) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.person_outline, color: Colors.grey, size: 20),
                        SizedBox(width: 10),
                        Text(
                          'Cliente Actual: Consumidor Final (Sin asignar)',
                          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blueGrey),
                        ),
                      ],
                    ),
                  );
                }

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Color(0xFF1976D2),
                        radius: 18,
                        child: Icon(Icons.person, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customer.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            Text(
                              '${customer.documentType == 80 ? "CUIT" : "DNI"}: ${customer.documentNumber} • Saldo C/C: \$${customer.balance.toCurrency()}',
                              style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade800),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFF1976D2)),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Editar', style: TextStyle(fontSize: 12)),
                        onPressed: () => _handleEditCustomer(customer),
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                        icon: const Icon(Icons.person_remove_outlined, size: 16),
                        label: const Text('Quitar', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          pos.selectCustomer(null);
                          SnackBarService.info(context, 'Cliente desasociado. Venta a Consumidor Final.');
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 14),

            // Barra de búsqueda y botón nuevo
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (val) {
                      setState(() {});
                      Provider.of<CustomerProvider>(context, listen: false).fetchCustomers(search: val.trim());
                    },
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre, DNI o CUIT...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1976D2),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    final created = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => const CustomerFormDialog(),
                    );
                    if (created == true && mounted) {
                      await Provider.of<CustomerProvider>(context, listen: false).fetchCustomers();
                    }
                  },
                  icon: const Icon(Icons.person_add_rounded, size: 18),
                  label: const Text('Nuevo', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Lista de clientes
            Expanded(
              child: Consumer<CustomerProvider>(
                builder: (context, custProv, _) {
                  if (custProv.isLoading && custProv.customers.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final list = custProv.customers;

                  if (list.isEmpty) {
                    return Center(
                      child: Text(
                        'No se encontraron clientes',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, index) {
                      final c = list[index];
                      return ListTile(
                        dense: true,
                        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text(
                          '${c.documentType == 80 ? "CUIT" : "DNI"}: ${c.documentNumber} • Tel: ${c.phone ?? "-"}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              color: Colors.blueGrey.shade700,
                              tooltip: 'Editar cliente',
                              padding: const EdgeInsets.all(6),
                              constraints: const BoxConstraints(),
                              onPressed: () => _handleEditCustomer(c),
                            ),
                            const SizedBox(width: 2),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              color: Colors.red.shade600,
                              tooltip: 'Eliminar cliente',
                              padding: const EdgeInsets.all(6),
                              constraints: const BoxConstraints(),
                              onPressed: () => _handleDeleteCustomer(c),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade50,
                                foregroundColor: const Color(0xFF1976D2),
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              ),
                              onPressed: () {
                                final pos = Provider.of<PosProvider>(context, listen: false);
                                pos.selectCustomer(c);
                                Navigator.of(context).pop();
                                SnackBarService.success(context, '👤 Cliente ${c.name} asignado al ticket.');
                              },
                              child: const Text('Asignar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
