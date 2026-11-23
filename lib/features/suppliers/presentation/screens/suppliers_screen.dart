import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/supplier_provider.dart';
import '../widgets/supplier_form_dialog.dart';
import '../../../../core/presentation/widgets/app_modal_shell.dart';
import '../../../../core/presentation/widgets/global_app_bar.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../cash_register/presentation/providers/cash_register_provider.dart';
import '../../../cash_movements/presentation/widgets/movement_form_dialog.dart';
import '../widgets/supplier_invoice_form_dialog.dart';
import '../widgets/supplier_document_detail_dialog.dart';
import 'supplier_current_account_screen.dart';
import '../../../catalog/presentation/providers/catalog_provider.dart';
import '../../../catalog/presentation/widgets/supplier_quick_grid_dialog.dart';
import '../../../../core/constants/app_permissions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../auth/presentation/widgets/admin_pin_dialog.dart';
import '../../../settings/presentation/providers/settings_provider.dart';

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
    // Solo el cobro de saldo a favor en efectivo (deposit) exige turno de caja físico abierto.
    // Los pagos a proveedores (balance > 0) pueden realizarse con Fondos Propios / Transferencia aunque la caja esté cerrada.
    if (balance < 0 && (cashProv.currentShift == null || !cashProv.currentShift!.isOpen)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Para ingresar un cobro de saldo a favor en caja, debes abrir un turno en el POS.'), backgroundColor: Colors.orange),
      );
      return;
    }
    Future.microtask(() async {
      await showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => MovementFormDialog(
          initialSupplierId: supplierId,
          initialType: balance > 0 ? 'supplier_payment' : 'deposit',
          initialCategory: balance > 0 ? 'Pago a Proveedor' : 'Cobro de Saldo a Favor',
          initialAmount: balance.abs(),
        ),
      );
      // Refresh supplier list after payment dialog closes
      if (mounted) {
        context.read<SupplierProvider>().fetchSuppliers();
      }
    });
  }

  void _openInvoiceForm(int supplierId, String supplierName) {
    Future.microtask(() async {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => SupplierInvoiceFormDialog(
          supplierId: supplierId,
          supplierName: supplierName,
        ),
      );
      if (mounted) {
        context.read<SupplierProvider>().fetchSuppliers();
      }
    });
  }

  Future<void> _openSupplierCatalog(int supplierId, String supplierName) async {
    final pin = await AdminPinDialog.verifyAndGetPin(
      context,
      action: 'Catálogo de $supplierName',
      permissionKey: AppPermissions.manageCatalog,
    );
    if (pin == null || !mounted) return;
    try {
      context.read<CatalogProvider?>()?.setSupplierFilter(
            supplierId,
            supplierName: supplierName,
            reload: false,
          );
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushNamed(context, '/catalog');
  }

  void _openSupplierQuickGrid(int supplierId, String supplierName) {
    CatalogProvider? catalogProv;
    try {
      catalogProv = context.read<CatalogProvider?>();
    } catch (_) {}
    if (catalogProv == null) {
      Navigator.pushNamed(context, '/catalog');
      return;
    }
    Future.microtask(() async {
      if (!mounted) return;
      final pin = await AdminPinDialog.verifyAndGetPin(
        context,
        action: 'Carga Rápida en Grilla',
        permissionKey: AppPermissions.manageCatalog,
      );
      if (pin != null && mounted) {
        showDialog<int>(
          context: context,
          barrierDismissible: false,
          builder: (_) => SupplierQuickGridDialog(
            provider: catalogProv!,
            initialSupplierId: supplierId,
            initialSupplierName: supplierName,
            alreadyAuthorized: true,
            authorizedAdminPin: pin == 'ALREADY_AUTHORIZED' ? null : pin,
          ),
        );
      }
    });
  }

  void _openForm([int? id, Map<String, dynamic>? initialData]) {
    Future.microtask(() {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => SupplierFormDialog(
          supplierId: id,
          initialData: initialData,
        ),
      );
    });
  }

  Future<void> _deleteSupplier(int id, String name) async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Eliminar Proveedor',
      message: '¿Está seguro que desea eliminar a $name?',
      confirmLabel: 'Eliminar',
      cancelLabel: 'Cancelar',
      icon: Icons.delete_outline,
      isDestructive: true,
    );

    if (confirm == true && mounted) {
      await AdminPinDialog.protectAction(
        context,
        action: 'Eliminar Proveedor $name',
        permissionKey: AppPermissions.manageCatalog,
        onAuthorized: () async {
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
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isRI = false;
    try {
      isRI = context.watch<SettingsProvider>().isResponsableInscripto;
    } catch (_) {}

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: const GlobalAppBar(
        currentRoute: '/suppliers',
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: AppColors.border),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, headerConstraints) {
                final isNarrow = headerConstraints.maxWidth < 900;
                final searchBar = SizedBox(
                  width: isNarrow ? headerConstraints.maxWidth : 460,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Buscar por nombre o CUIT...',
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: AppColors.textMuted,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.borderStrong),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.borderStrong),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppColors.primary,
                                width: 1.5,
                              ),
                            ),
                            filled: true,
                            fillColor: AppColors.surfaceMuted,
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              ),
                            );
                          }
                          return IconButton(
                            tooltip: 'Actualizar base de datos',
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.surfaceAlt,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: const BorderSide(color: AppColors.border),
                              ),
                            ),
                            icon: const Icon(
                              Icons.refresh_rounded,
                              color: AppColors.primary,
                            ),
                            onPressed: () {
                              provider.fetchSuppliers(search: _searchController.text.trim());
                            },
                          );
                        },
                      ),
                    ],
                  ),
                );

                final actionButtons = Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => const SupplierDocumentsHistoryDialog(),
                        );
                      },
                      icon: const Icon(Icons.receipt_long, size: 18),
                      label: const Text('Historial de Comprobantes'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.navyEnd,
                        side: const BorderSide(color: AppColors.borderStrong),
                        backgroundColor: AppColors.surfaceMuted,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _openForm(),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Nuevo Proveedor'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      searchBar,
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: actionButtons,
                      ),
                    ],
                  );
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(child: searchBar),
                    const SizedBox(width: 12),
                    actionButtons,
                  ],
                );
              },
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

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final availableWidth = constraints.maxWidth;
                    // Responsivo: 1 columna para <400px, 2 para <800px, 3+ para más
                    final crossAxisCount = (availableWidth / 380).floor().clamp(1, 4);
                    final cardWidth = (availableWidth - 32 - 12 * (crossAxisCount - 1)) / crossAxisCount;
                    // Altura dinámica: cuando la tarjeta es angosta (<330px), los botones pasan a una segunda fila
                    // por lo que la tarjeta requiere mayor altura (254px) contemplando la barra superior de estado (3px).
                    final isTight = cardWidth < 330;
                    final mainAxisExtent = isTight ? 254.0 : 204.0;
                    
                    return GridView.builder(
                      padding: const EdgeInsets.all(16).copyWith(bottom: 80),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisExtent: mainAxisExtent,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: provider.suppliers.length,
                      itemBuilder: (context, index) {
                        final supplier = provider.suppliers[index];
                        final statusAccent = supplier.balance > 0
                            ? const Color(0xFFEF4444)
                            : (supplier.balance < 0
                                ? AppColors.emerald
                                : AppColors.borderStrong);
                        return Card(
                          elevation: 0,
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: AppColors.border, width: 1.2),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _openForm(supplier.id, supplier.toJson()),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(height: 3, color: statusAccent),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                              // Cabecera: Avatar, Nombre, CUIT y Menú de acciones
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: supplier.isActive
                                          ? AppColors.primarySoft
                                          : AppColors.surfaceAlt,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: supplier.isActive
                                            ? AppColors.primaryBorder.withValues(alpha: 0.7)
                                            : AppColors.border,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.storefront_rounded,
                                      color: supplier.isActive
                                          ? AppColors.primary
                                          : AppColors.textMuted,
                                      size: 21,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          supplier.name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15.5,
                                            decoration: supplier.isActive ? null : TextDecoration.lineThrough,
                                            color: supplier.isActive ? AppColors.textPrimary : AppColors.textMuted,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if ((supplier.cuit != null && supplier.cuit!.isNotEmpty) ||
                                            (isRI && supplier.taxCategory != null && supplier.taxCategory!.isNotEmpty))
                                          Row(
                                            children: [
                                              if (supplier.cuit != null && supplier.cuit!.isNotEmpty)
                                                Flexible(
                                                  child: Text(
                                                    'CUIT: ${supplier.cuit}',
                                                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              if (isRI && supplier.taxCategory != null && supplier.taxCategory!.isNotEmpty) ...[
                                                if (supplier.cuit != null && supplier.cuit!.isNotEmpty)
                                                  const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: supplier.taxCategory == 'Responsable Inscripto'
                                                        ? const Color(0xFFEEF2FF)
                                                        : AppColors.surfaceAlt,
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(
                                                      color: supplier.taxCategory == 'Responsable Inscripto'
                                                          ? const Color(0xFFC7D2FE)
                                                          : AppColors.borderStrong,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    supplier.taxCategory == 'Responsable Inscripto'
                                                        ? 'RI'
                                                        : (supplier.taxCategory == 'Monotributista'
                                                            ? 'Monotributo'
                                                            : supplier.taxCategory!),
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: supplier.taxCategory == 'Responsable Inscripto'
                                                          ? const Color(0xFF3730A3)
                                                          : AppColors.textSecondary,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                  // Menú de opciones Dark Navy cohesivo con GlobalAppBar
                                  PopupMenuButton<int>(
                                    icon: const Icon(Icons.more_vert, color: AppColors.textMuted),
                                    tooltip: 'Opciones',
                                    position: PopupMenuPosition.under,
                                    elevation: 14,
                                    color: GlobalAppBar.kNavDropdownBg,
                                    surfaceTintColor: Colors.transparent,
                                    shadowColor: const Color(0x73020617),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      side: const BorderSide(
                                        color: GlobalAppBar.kNavDropdownBorder,
                                        width: 1.5,
                                      ),
                                    ),
                                    onSelected: (val) {
                                      if (val == 0) _openForm(supplier.id, supplier.toJson());
                                      if (val == 1) _deleteSupplier(supplier.id, supplier.name);
                                      if (val == 3) _openSupplierQuickGrid(supplier.id, supplier.name);
                                    },
                                    itemBuilder: (context) => [
                                      _buildDarkPopupOption(
                                        value: 0,
                                        icon: Icons.edit_outlined,
                                        label: 'Editar Proveedor',
                                        accent: const Color(0xFF60A5FA),
                                      ),
                                      _buildDarkPopupOption(
                                        value: 3,
                                        icon: Icons.grid_on_rounded,
                                        label: 'Carga en Grilla',
                                        accent: AppColors.indigoLight,
                                      ),
                                      const PopupMenuItem<int>(
                                        enabled: false,
                                        height: 10,
                                        padding: EdgeInsets.symmetric(horizontal: 12),
                                        child: Divider(
                                          height: 1,
                                          thickness: 1,
                                          color: Color(0xFF263859),
                                        ),
                                      ),
                                      _buildDarkPopupOption(
                                        value: 1,
                                        icon: Icons.delete_outline,
                                        label: 'Eliminar',
                                        accent: const Color(0xFFFB7185),
                                        isDanger: true,
                                      ),
                                    ],
                                  )
                                ],
                              ),
                              const SizedBox(height: 4),
                              // Dirección y Contacto (flexible para no hacer overflow)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (supplier.address != null && supplier.address!.isNotEmpty)
                                      Row(
                                        children: [
                                          const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textMuted),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(supplier.address!, 
                                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                          ),
                                        ],
                                      ),
                                    if (supplier.phone != null && supplier.phone!.isNotEmpty)
                                      Row(
                                        children: [
                                          const Icon(Icons.phone_outlined, size: 14, color: AppColors.textMuted),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              supplier.phone!,
                                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              // Caja inferior: Saldo / Deuda
                              Builder(
                                builder: (context) {
                                  final balanceWidget = Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: supplier.balance > 0
                                          ? const Color(0xFFFEF2F2)
                                          : (supplier.balance < 0
                                              ? const Color(0xFFECFDF5)
                                              : AppColors.surfaceMuted),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: supplier.balance > 0
                                            ? const Color(0xFFFECACA)
                                            : (supplier.balance < 0
                                                ? const Color(0xFFA7F3D0)
                                                : AppColors.border),
                                      ),
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Row(
                                        children: [
                                          Text('Saldo actual: ', style: TextStyle(color: supplier.balance > 0 ? Colors.red.shade900 : (supplier.balance < 0 ? Colors.green.shade900 : AppColors.textPrimary), fontSize: 12.5)),
                                          Text(
                                            '\$${supplier.balance.toCurrency()}',
                                            style: TextStyle(
                                              color: supplier.balance > 0 ? Colors.red.shade700 : (supplier.balance < 0 ? Colors.green.shade700 : AppColors.textPrimary),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );

                                  final buttonsWidget = Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (supplier.balance != 0) ...[
                                        IconButton(
                                          tooltip: supplier.balance > 0 ? 'Pagar Saldo' : 'Devolución de Saldo a Favor',
                                          visualDensity: VisualDensity.compact,
                                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                          style: IconButton.styleFrom(
                                            backgroundColor: supplier.balance > 0 ? Colors.red.shade50 : Colors.green.shade50,
                                            foregroundColor: supplier.balance > 0 ? Colors.red.shade700 : Colors.green.shade700,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          icon: const Icon(Icons.payments_outlined, size: 20),
                                          onPressed: () => _openPaymentForm(supplier.id, supplier.balance),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      IconButton(
                                        tooltip: 'Catálogo del Proveedor',
                                        visualDensity: VisualDensity.compact,
                                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                        style: IconButton.styleFrom(
                                          backgroundColor: AppColors.tealSoft,
                                          foregroundColor: AppColors.tealDark,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            side: const BorderSide(color: Color(0xFF99F6E4)),
                                          ),
                                        ),
                                        icon: const Icon(Icons.inventory_2_outlined, size: 19),
                                        onPressed: () => _openSupplierCatalog(supplier.id, supplier.name),
                                      ),
                                      const SizedBox(width: 6),
                                      IconButton(
                                        tooltip: 'Registrar Compra (Remito / Factura)',
                                        visualDensity: VisualDensity.compact,
                                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                        style: IconButton.styleFrom(
                                          backgroundColor: const Color(0xFFDBEAFE),
                                          foregroundColor: AppColors.primaryDark,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            side: const BorderSide(color: AppColors.primaryBorder),
                                          ),
                                        ),
                                        icon: const Icon(Icons.receipt_long_rounded, size: 19),
                                        onPressed: () => _openInvoiceForm(supplier.id, supplier.name),
                                      ),
                                      const SizedBox(width: 6),
                                      IconButton(
                                        tooltip: 'Ver Cuenta Corriente',
                                        visualDensity: VisualDensity.compact,
                                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                        style: IconButton.styleFrom(
                                          backgroundColor: const Color(0xFFE0E7FF),
                                          foregroundColor: AppColors.indigo,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            side: const BorderSide(color: Color(0xFFC7D2FE)),
                                          ),
                                        ),
                                        icon: const Icon(Icons.history_edu, size: 19),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => SupplierCurrentAccountScreen(supplierId: supplier.id, supplierName: supplier.name),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  );

                                  if (isTight) {
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        balanceWidget,
                                        const SizedBox(height: 8),
                                        buttonsWidget,
                                      ],
                                    );
                                  } else {
                                    return Row(
                                      children: [
                                        Expanded(child: balanceWidget),
                                        const SizedBox(width: 8),
                                        buttonsWidget,
                                      ],
                                    );
                                  }
                                },
                              ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );   // GridView.builder
              },
            );   // LayoutBuilder
          },
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<int> _buildDarkPopupOption({
    required int value,
    required IconData icon,
    required String label,
    required Color accent,
    bool isDanger = false,
  }) {
    return PopupMenuItem<int>(
      value: value,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: accent.withValues(alpha: 0.32),
              ),
            ),
            child: Icon(icon, size: 16.5, color: accent),
          ),
          const SizedBox(width: 11),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: isDanger ? FontWeight.w700 : FontWeight.w500,
                color: isDanger
                    ? const Color(0xFFFCA5A5)
                    : const Color(0xFFF1F5F9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
