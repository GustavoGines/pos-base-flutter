import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pos_provider.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import '../widgets/checkout_dialog.dart';
import '../../../auth/presentation/widgets/admin_pin_dialog.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({Key? key}) : super(key: key);

  @override
  _PosScreenState createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
      // Asegurarse de cargar los productos de acceso rápido desde la BD
      Provider.of<CatalogProvider>(context, listen: false).loadProducts();
    });
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onProductScannedOrSearched(String query) async {
    if (query.trim().isEmpty) return;
    
    final posProvider = Provider.of<PosProvider>(context, listen: false);
    
    // Simula búsqueda en red o local invocando el usecase
    final results = await posProvider.search(query.trim());
    
    if (results.isNotEmpty) {
      // Tomamos el primero si matcheó el código de barras exacto, o mostramos lista.
      // Aquí asumimos auto-selección del primero para agilizar lectura láser.
      _handleProductSelection(results.first);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Producto no encontrado')),
      );
    }

    _searchController.clear();
    _searchFocusNode.requestFocus();
  }

  void _handleProductSelection(Product product) {
    final posProvider = Provider.of<PosProvider>(context, listen: false);
    
    final success = posProvider.requestAddToCart(product);
    if (!success) {
      // Es producto por peso, pedir peso por Modal
      _showWeightModal(product, posProvider);
    }
  }

  void _showWeightModal(Product product, PosProvider provider) {
    final weightController = TextEditingController();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text('Ingresar Peso en Kg - ${product.name}'),
          content: TextField(
            controller: weightController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Peso (Ej: 1.5)',
              border: OutlineInputBorder(),
              suffixText: 'KG',
              helperText: 'Use punto decimal para gramos (ej: 0.5 = 500g)',
            ),
            onSubmitted: (value) {
               _processWeight(value, product, provider, context);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                _processWeight(weightController.text, product, provider, context);
              },
              child: const Text('Agregar'),
            )
          ],
        );
      }
    ).then((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _processWeight(String value, Product product, PosProvider provider, BuildContext dialogContext) {
    // Reemplaza comas por puntos en caso de que teclados latinos obligen coma
    String sanitizedValue = value.replaceAll(',', '.');
    final weight = double.tryParse(sanitizedValue);
    
    // Validación básica: El peso debe ser positivo y menor a una exageración (Ej: >1000Kg es raro en POS base)
    if (weight != null && weight > 0 && weight < 1000) {
      provider.submitWeighedProduct(product, weight);
      Navigator.pop(dialogContext);
    } else {
      SnackBarService.error(dialogContext, 'Por favor, ingrese un peso válido en Kg.');
    }
  }

  void _handleCheckout() async {
    final posProvider = Provider.of<PosProvider>(context, listen: false);
    final cashRegisterProvider = Provider.of<CashRegisterProvider>(context, listen: false);
    
    final currentShift = cashRegisterProvider.currentShift;
    if (currentShift == null || !currentShift.isOpen) {
      SnackBarService.error(context, 'No hay turno de caja abierto.');
      return;
    }

    // Abrimos el CheckoutDialog y esperamos a ver si sale exitoso (true)
    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Forzar uso de botones
      builder: (_) => CheckoutDialog(total: posProvider.cartTotal),
    );
    
    if (success == true) {
      SnackBarService.success(context, '¡Venta registrada con éxito!');
    }
    
    _searchFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Punto de Venta (POS)'),
        centerTitle: false,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.receipt_long_outlined, color: Colors.blueAccent),
            label: const Text('Ventas del Día', style: TextStyle(color: Colors.blueAccent)),
            onPressed: () async {
              final authorized = await AdminPinDialog.verify(context, action: 'Ver Ventas', permissionKey: 'view_global_history');
              if (authorized && context.mounted) {
                Navigator.of(context).pushNamed('/sales-history');
              }
            },
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            icon: const Icon(Icons.inventory_2_outlined, color: Colors.deepPurple),
            label: const Text('Catálogo', style: TextStyle(color: Colors.deepPurple)),
            onPressed: () async {
              final authorized = await AdminPinDialog.verify(context, action: 'Gestionar Catálogo', permissionKey: 'manage_catalog');
              if (authorized && context.mounted) {
                Navigator.of(context).pushNamed('/catalog');
              }
            },
          ),
          const SizedBox(width: 8),
          
          // --- Menú Desplegable del Usuario ---
          Consumer<AuthProvider>(
            builder: (context, auth, _) {
              final userName = auth.currentUser?['name'] ?? 'Sesión';
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: PopupMenuButton<String>(
                  offset: const Offset(0, 45),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tooltip: 'Opciones de Usuario',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.blueGrey.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_outline, size: 20, color: Colors.blueGrey),
                        const SizedBox(width: 8),
                        Text(
                          userName,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down, color: Colors.blueGrey),
                      ],
                    ),
                  ),
                  onSelected: (value) async {
                    switch (value) {
                      case 'shift_audit':
                        final auditAuth = await AdminPinDialog.verify(context, action: 'Ver Auditoría de Turnos', permissionKey: 'view_global_history');
                        if (auditAuth && context.mounted) {
                          Navigator.of(context).pushNamed('/shift-audit');
                        }
                        break;
                      case 'settings':
                        final authorized = await AdminPinDialog.verify(context, action: 'Acceder a Configuración');
                        if (authorized && context.mounted) {
                          Navigator.of(context).pushNamed('/settings');
                        }
                        break;
                      case 'logout':
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Row(
                              children: [
                                Icon(Icons.swap_horiz_rounded, color: Colors.blueGrey),
                                SizedBox(width: 8),
                                Text('Cambiar Usuario'),
                              ],
                            ),
                            content: const Text('¿Deseas cerrar la sesión actual y volver a la pantalla de ingreso de PIN?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                              FilledButton.icon(
                                onPressed: () => Navigator.pop(ctx, true),
                                icon: const Icon(Icons.logout_rounded),
                                label: const Text('Cambiar'),
                                style: FilledButton.styleFrom(backgroundColor: Colors.blueGrey.shade700),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true && context.mounted) {
                          context.read<AuthProvider>().logout();
                          Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                        }
                        break;
                      case 'close_shift':
                        Navigator.of(context).pushNamed('/close-shift');
                        break;
                    }
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'shift_audit',
                      child: ListTile(
                        leading: Icon(Icons.history_edu),
                        title: Text('Auditoría de Turnos (Z)'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'settings',
                      child: ListTile(
                        leading: Icon(Icons.settings_outlined),
                        title: Text('Configuración del Sistema'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'logout',
                      child: ListTile(
                        leading: Icon(Icons.swap_horiz_rounded),
                        title: Text('Cambiar Usuario / Bloquear'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem<String>(
                      value: 'close_shift',
                      child: ListTile(
                        leading: Icon(Icons.lock_outline, color: Colors.redAccent),
                        title: Text('Cerrar Turno / Caja', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Row(
              children: [
                // PANEL IZQUIERDO: CARRITO (35% Width)
                SizedBox(
                  width: constraints.maxWidth * 0.35,
                  child: _buildCartPanel(),
                ),
                
                const VerticalDivider(width: 1, thickness: 1),

                // PANEL DERECHO: BÚSQUEDA Y GRILLA RÁPIDA (65% Width)
                Expanded(
                  child: _buildRightPanel(),
                )
              ],
            );
          }
        ),
      ),
    );
  }

  Widget _buildCartPanel() {
    return Consumer<PosProvider>(
      builder: (context, pos, child) {
        return Column(
          children: [
            // Header del carrito
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.blue.shade50,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Ticket Actual', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Icon(Icons.shopping_cart),
                ],
              ),
            ),
            
            // Lista de ítems
            Expanded(
              child: pos.cart.isEmpty
                  ? const Center(child: Text('El carrito está vacío', style: TextStyle(color: Colors.grey)))
                  : ListView.separated(
                      itemCount: pos.cart.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = pos.cart[index];
                        return ListTile(
                          title: Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${item.quantity} x \$${item.product.sellingPrice.toStringAsFixed(2)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('\$${item.subtotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16)),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => pos.removeFromCart(item),
                              )
                            ],
                          ),
                          onTap: () {
                            if (!item.product.isSoldByWeight) {
                               // Quick edit quantity logic could go here
                            }
                          },
                        );
                      },
                    ),
            ),

            // Footer (Total y Cobrar)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))
                ]
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        const Text('TOTAL:', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '\$${pos.cartTotal.toStringAsFixed(2)}', 
                            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green),
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: pos.cart.isEmpty
                                ? Colors.grey.shade400
                                : pos.isLoading
                                    ? Colors.blue.shade300
                                    : Colors.blue.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: pos.isLoading ? 0 : 4,
                          ),
                          onPressed: pos.cart.isEmpty || pos.isLoading ? null : _handleCheckout,
                          child: pos.isLoading
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Text('Procesando...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  ],
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.point_of_sale_rounded, size: 22),
                                    SizedBox(width: 8),
                                    Text('COBRAR', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                                  ],
                                ),
                        ),
                      ),
                    )
                  ],
                ),
              ),
            )
          ],
        );
      }
    );
  }

  Widget _buildRightPanel() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Barra de búsqueda con foco fijo (Escáner de código de barras)
          TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              hintText: 'Escanear código de barras o buscar producto...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  _searchFocusNode.requestFocus();
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: Colors.grey.shade100,
            ),
            onSubmitted: _onProductScannedOrSearched,
          ),
          
          const SizedBox(height: 24),
          const Text('Acceso Rápido (Favoritos / Sin Código)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // Grilla de productos rápidos
          Expanded(
            child: Consumer<CatalogProvider>(
              builder: (context, catalog, child) {
                if (catalog.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (catalog.products.isEmpty) {
                  return const Center(child: Text('No hay productos en el catálogo.'));
                }

                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    childAspectRatio: 0.85,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: catalog.products.length,
                  itemBuilder: (context, index) {
                    final product = catalog.products[index];
                    return InkWell(
                      onTap: () {
                        _handleProductSelection(product);
                      },
                      child: Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            gradient: LinearGradient(
                              colors: [Colors.blue.shade50, Colors.white],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Center(
                                    child: Text(
                                      product.name, 
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '\$${product.sellingPrice.toStringAsFixed(2)}',
                                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (product.isSoldByWeight)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 4.0),
                                    child: Text('Por Peso (Kg)', style: TextStyle(color: Colors.orange, fontSize: 11)),
                                  )
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              }
            ),
          )
        ],
      ),
    );
  }
}
