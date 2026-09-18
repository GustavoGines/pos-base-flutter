import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/supplier_provider.dart';
import '../widgets/supplier_form_dialog.dart';
import '../../../../core/presentation/widgets/global_app_bar.dart';
import '../../../cash_register/presentation/providers/cash_register_provider.dart';
import '../../../cash_movements/presentation/widgets/movement_form_dialog.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SupplierProvider>().fetchSuppliers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _openPaymentForm(int supplierId, double balance) {
    final cashProv = context.read<CashRegisterProvider>();
    if (cashProv.currentShift == null || !cashProv.currentShift!.isOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Para registrar un pago, debes abrir un turno de caja en el POS.'), backgroundColor: Colors.orange),
      );
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => MovementFormDialog(
        initialSupplierId: supplierId,
        initialType: balance > 0 ? 'expense' : 'deposit',
        initialCategory: balance > 0 ? 'Pago a Proveedor' : 'Cobro de Saldo a Favor',
      ),
    );
  }

  void _openForm([int? id, Map<String, dynamic>? initialData]) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => SupplierFormDialog(
        supplierId: id,
        initialData: initialData,
      ),
    );
  }

  Future<void> _deleteSupplier(int id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Proveedor'),
        content: Text('¿Está seguro que desea eliminar a $name?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await context.read<SupplierProvider>().deleteSupplier(id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Proveedor eliminado con éxito'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlobalAppBar(
        currentRoute: '/suppliers',
        title: 'Gestión de Proveedores',
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Izquierda: Buscador y Refresh
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Buscar por nombre o CUIT...',
                            prefixIcon: const Icon(Icons.search, color: Colors.grey),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(vertical: 0),
                          ),
                          onChanged: (val) {
                            if (_debounce?.isActive ?? false) _debounce!.cancel();
                            _debounce = Timer(const Duration(milliseconds: 400), () {
                              context.read<SupplierProvider>().setSearchQuery(val);
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Consumer<SupplierProvider>(
                        builder: (context, provider, child) {
                          if (provider.isLoading) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12.0),
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.brown),
                              ),
                            );
                          }
                          return IconButton(
                            tooltip: 'Actualizar base de datos',
                            icon: const Icon(Icons.refresh, color: Colors.brown),
                            onPressed: () {
                              provider.fetchSuppliers(search: _searchController.text.trim());
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
                // Derecha: Botón Nuevo Proveedor
                ElevatedButton.icon(
                  onPressed: () => _openForm(),
                  icon: const Icon(Icons.add),
                  label: const Text('Nuevo Proveedor'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Consumer<SupplierProvider>(
              builder: (context, provider, child) {
                if (provider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (provider.suppliers.isEmpty) {
                  return const Center(
                    child: Text('No hay proveedores registrados.', style: TextStyle(fontSize: 16)),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(16).copyWith(bottom: 80),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 400, // Ancho máximo de cada tarjeta
                    mainAxisExtent: 170, // Alto fijo de la tarjeta
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: provider.suppliers.length,
                  itemBuilder: (context, index) {
                    final supplier = provider.suppliers[index];
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openForm(supplier.id, supplier.toJson()),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Cabecera: Avatar, Nombre, CUIT y Menú de acciones
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: supplier.isActive ? Colors.blue.shade50 : Colors.grey.shade200,
                                    foregroundColor: supplier.isActive ? Colors.blue.shade700 : Colors.grey.shade600,
                                    child: const Icon(Icons.storefront),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          supplier.name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold, 
                                            fontSize: 16,
                                            decoration: supplier.isActive ? null : TextDecoration.lineThrough,
                                            color: supplier.isActive ? Colors.black87 : Colors.grey,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (supplier.cuit != null && supplier.cuit!.isNotEmpty)
                                          Text('CUIT: ${supplier.cuit}', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                      ],
                                    ),
                                  ),
                                  // Menú de opciones
                                  PopupMenuButton<int>(
                                    icon: const Icon(Icons.more_vert, color: Colors.grey),
                                    tooltip: 'Opciones',
                                    onSelected: (val) {
                                      if (val == 0) _openForm(supplier.id, supplier.toJson());
                                      if (val == 1) _deleteSupplier(supplier.id, supplier.name);
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(value: 0, child: Row(children: [Icon(Icons.edit, size: 20, color: Colors.blue), SizedBox(width: 8), Text('Editar')])),
                                      const PopupMenuItem(value: 1, child: Row(children: [Icon(Icons.delete, size: 20, color: Colors.red), SizedBox(width: 8), Text('Eliminar')])),
                                    ],
                                  )
                                ],
                              ),
                              const Spacer(),
                              // Contacto (Teléfono / Email)
                              if (supplier.phone != null && supplier.phone!.isNotEmpty)
                                Row(
                                  children: [
                                    Icon(Icons.phone_outlined, size: 14, color: Colors.grey.shade500),
                                    const SizedBox(width: 6),
                                    Text(supplier.phone!, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                                  ],
                                ),
                              const SizedBox(height: 12),
                              // Caja inferior: Saldo / Deuda
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: supplier.balance > 0 ? Colors.red.shade50 : (supplier.balance < 0 ? Colors.green.shade50 : Colors.grey.shade50),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: supplier.balance > 0 ? Colors.red.shade100 : (supplier.balance < 0 ? Colors.green.shade100 : Colors.grey.shade200)),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('Saldo actual:', style: TextStyle(color: supplier.balance > 0 ? Colors.red.shade900 : (supplier.balance < 0 ? Colors.green.shade900 : Colors.black87), fontSize: 13)),
                                          Text(
                                            '\$${supplier.balance.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              color: supplier.balance > 0 ? Colors.red.shade700 : (supplier.balance < 0 ? Colors.green.shade700 : Colors.black87),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (supplier.balance != 0) ...[
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip: supplier.balance > 0 ? 'Abonar / Pagar Deuda' : 'Cobrar Saldo a Favor',
                                      style: IconButton.styleFrom(
                                        backgroundColor: supplier.balance > 0 ? Colors.red.shade50 : Colors.green.shade50,
                                        foregroundColor: supplier.balance > 0 ? Colors.red.shade700 : Colors.green.shade700,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      icon: const Icon(Icons.payments_outlined),
                                      onPressed: () => _openPaymentForm(supplier.id, supplier.balance),
                                    ),
                                  ]
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
