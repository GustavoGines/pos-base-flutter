import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pos_provider.dart';
import 'package:frontend_desktop/features/customers/models/customer_model.dart';
import 'package:frontend_desktop/features/customers/providers/customer_provider.dart';
import 'package:frontend_desktop/features/customers/presentation/widgets/customer_form_dialog.dart';
import 'package:frontend_desktop/features/auth/presentation/widgets/admin_pin_dialog.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
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
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Eliminar Cliente',
      message:
          '¿Estás seguro de que deseas eliminar permanentemente a "${c.name}"?',
      confirmLabel: 'Eliminar',
      icon: Icons.person_remove_rounded,
      isDestructive: true,
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
    return AppModalShell(
      title: 'Gestión Rápida de Cliente',
      subtitle: 'Asignar cliente al ticket actual o crear uno nuevo',
      icon: Icons.person_pin_circle_rounded,
      accent: AppModalAccent.blue,
      maxWidth: 680,
      maxHeight: 580,
      expandBody: true,
      topBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Card del Cliente Actualmente Asignado
            Consumer<PosProvider>(
              builder: (context, pos, _) {
                final customer = pos.selectedCustomer;
                if (customer == null) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          color: AppColors.textMuted,
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Cliente Actual: Consumidor Final (Sin asignar)',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primaryBorder),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: AppColors.primary,
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
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              '${customer.documentType == 80 ? "CUIT" : "DNI"}: ${customer.documentNumber} • Saldo C/C: \$${customer.balance.toCurrency()}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primaryDark,
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Editar', style: TextStyle(fontSize: 12)),
                        onPressed: () => _handleEditCustomer(customer),
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.danger,
                        ),
                        icon: const Icon(Icons.person_remove_outlined, size: 16),
                        label: const Text('Quitar', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          pos.selectCustomer(null);
                          SnackBarService.info(
                            context,
                            'Cliente desasociado. Venta a Consumidor Final.',
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 10),

            // Barra de búsqueda y botón nuevo
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (val) {
                      setState(() {});
                      Provider.of<CustomerProvider>(context, listen: false)
                          .fetchCustomers(search: val.trim());
                    },
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre, DNI o CUIT...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    final created = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => const CustomerFormDialog(),
                    );
                    if (created == true && mounted) {
                      await Provider.of<CustomerProvider>(context, listen: false)
                          .fetchCustomers();
                    }
                  },
                  icon: const Icon(Icons.person_add_rounded, size: 18),
                  label: const Text(
                    'Nuevo',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      bodyPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      body: Consumer<CustomerProvider>(
        builder: (context, custProv, _) {
          if (custProv.isLoading && custProv.customers.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final list = custProv.customers;

          if (list.isEmpty) {
            return const Center(
              child: Text(
                'No se encontraron clientes',
                style: TextStyle(color: AppColors.textMuted),
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
                title: Text(
                  c.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  '${c.documentType == 80 ? "CUIT" : "DNI"}: ${c.documentNumber} • Tel: ${c.phone ?? "-"}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      color: AppColors.textSecondary,
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
                        backgroundColor: AppColors.primarySoft,
                        foregroundColor: AppColors.primaryDark,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                      ),
                      onPressed: () {
                        final pos =
                            Provider.of<PosProvider>(context, listen: false);
                        pos.selectCustomer(c);
                        Navigator.of(context).pop();
                        SnackBarService.success(
                          context,
                          '👤 Cliente ${c.name} asignado al ticket.',
                        );
                      },
                      child: const Text(
                        'Asignar',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      footerActions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar (Esc)'),
        ),
      ],
    );
  }
}
