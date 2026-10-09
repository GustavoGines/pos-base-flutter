import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_permissions.dart';

/// Categoría lógica que agrupa permisos relacionados
class PermissionCategory {
  final String title;
  final List<PermissionItem> items;
  const PermissionCategory({required this.title, required this.items});
}

class PermissionItem {
  final String key;
  final String label;
  final String description;
  final IconData icon;
  const PermissionItem({
    required this.key,
    required this.label,
    required this.description,
    this.icon = Icons.security,
  });
}

const List<PermissionCategory> kCategorizedPermissions = [
  PermissionCategory(
    title: '🛡️ Configuración y Administración',
    items: [
      PermissionItem(
        key: AppPermissions.manageSettings,
        label: 'Configuración General',
        description: 'Parámetros del negocio, cajas físicas y métodos de pago.',
        icon: Icons.settings_outlined,
      ),
      PermissionItem(
        key: AppPermissions.manageUsers,
        label: 'Gestión de Personal',
        description: 'Crear, editar o remover empleados y asignarles permisos.',
        icon: Icons.manage_accounts_outlined,
      ),
      PermissionItem(
        key: AppPermissions.manageTrash,
        label: 'Papelera de Reciclaje',
        description:
            'Restaurar o destruir de forma definitiva registros eliminados.',
        icon: Icons.delete_forever_outlined,
      ),
    ],
  ),
  PermissionCategory(
    title: '📊 Reportes y Auditoría',
    items: [
      PermissionItem(
        key: AppPermissions.viewReports,
        label: 'Reportes Gerenciales',
        description:
            'Acceso a balances, gráficos de venta y análisis de rentabilidad.',
        icon: Icons.bar_chart_rounded,
      ),
      PermissionItem(
        key: AppPermissions.manageShifts,
        label: 'Auditoría y Turnos',
        description:
            'Acceso a Auditoría General y autorización de diferencias de caja.',
        icon: Icons.access_time_rounded,
      ),
    ],
  ),
  PermissionCategory(
    title: '💵 Caja Chica y Gastos',
    items: [
      PermissionItem(
        key: AppPermissions.viewExpenses,
        label: 'Visualizar Movimientos',
        description:
            'Ver listado de movimientos de caja chica y exportar informes.',
        icon: Icons.account_balance_wallet_outlined,
      ),
      PermissionItem(
        key: AppPermissions.createExpenses,
        label: 'Registrar Movimientos de Caja',
        description:
            'Crear ingresos extra, egresos operativos o retiros de dinero.',
        icon: Icons.add_circle_outline,
      ),
      PermissionItem(
        key: AppPermissions.deleteCashMovements,
        label: 'Anular Movimientos',
        description:
            'Eliminar registros de caja chica o ingresos/egresos manuales.',
        icon: Icons.delete_sweep_outlined,
      ),
      PermissionItem(
        key: AppPermissions.manageExpenseCategories,
        label: 'Categorías de Gastos',
        description: 'Administrar categorías de egresos operativos.',
        icon: Icons.category_outlined,
      ),
    ],
  ),
  PermissionCategory(
    title: '👥 Clientes y Cuentas Corrientes',
    items: [
      PermissionItem(
        key: AppPermissions.manageCustomers,
        label: 'Directorio de Clientes',
        description:
            'Alta, modificación de límites de crédito y baja de clientes.',
        icon: Icons.people_alt_outlined,
      ),
      PermissionItem(
        key: AppPermissions.viewCustomersAccount,
        label: 'Ver Cuentas Corrientes',
        description:
            'Consultar saldos deudores y comprobantes impagos de clientes.',
        icon: Icons.receipt_long_outlined,
      ),
      PermissionItem(
        key: AppPermissions.collectCustomerDebt,
        label: 'Cobrar Cuentas Corrientes',
        description: 'Registrar cobros y amortizaciones de deudas de clientes.',
        icon: Icons.payments_outlined,
      ),
    ],
  ),
  PermissionCategory(
    title: '🛒 Punto de Venta y Cotizaciones',
    items: [
      PermissionItem(
        key: AppPermissions.applyDiscounts,
        label: 'Rebajas y Precios Especiales',
        description:
            'Modificar precios de lista en caja o aplicar descuentos libres.',
        icon: Icons.percent_outlined,
      ),
      PermissionItem(
        key: AppPermissions.voidSales,
        label: 'Anulación de Ventas Emitidas',
        description: 'Cancelar tickets cerrados y restituir mercadería.',
        icon: Icons.cancel_outlined,
      ),
      PermissionItem(
        key: AppPermissions.manageQuotes,
        label: 'Presupuestos y Cotizaciones',
        description: 'Crear, modificar y convertir presupuestos a ventas.',
        icon: Icons.request_quote_outlined,
      ),
    ],
  ),
  PermissionCategory(
    title: '🏷️ Catálogo y Precios',
    items: [
      PermissionItem(
        key: AppPermissions.manageCatalog,
        label: 'Gestión de Catálogo',
        description:
            'Crear y editar productos, categorías, marcas y precios de lista.',
        icon: Icons.inventory_2_outlined,
      ),
      PermissionItem(
        key: AppPermissions.bulkPriceUpdate,
        label: 'Aumento Masivo de Precios',
        description: 'Ejecutar o revertir incrementos porcentuales por lote.',
        icon: Icons.trending_up_outlined,
      ),
    ],
  ),
  PermissionCategory(
    title: '📦 Stock e Inventario',
    items: [
      PermissionItem(
        key: AppPermissions.adjustStock,
        label: 'Ajuste Manual de Inventario',
        description:
            'Cargar o descontar existencias físicas por mermas o roturas.',
        icon: Icons.move_to_inbox_outlined,
      ),
      PermissionItem(
        key: AppPermissions.viewKardex,
        label: 'Kardex de Mercadería',
        description:
            'Auditoría detallada de entradas y salidas de existencias.',
        icon: Icons.history_edu_outlined,
      ),
    ],
  ),
  PermissionCategory(
    title: '🚚 Proveedores y Logística',
    items: [
      PermissionItem(
        key: AppPermissions.viewSuppliers,
        label: 'Directorio de Proveedores',
        description:
            'Ver listado de proveedores y estados de cuenta comercial.',
        icon: Icons.local_shipping_outlined,
      ),
      PermissionItem(
        key: AppPermissions.createSupplierInvoice,
        label: 'Cargar Facturas y Remitos',
        description:
            'Registrar comprobantes de compra que incrementan stock y deuda.',
        icon: Icons.receipt_outlined,
      ),
      PermissionItem(
        key: AppPermissions.paySuppliers,
        label: 'Pagos a Proveedores',
        description: 'Emitir órdenes de pago desde caja chica o bancos.',
        icon: Icons.point_of_sale_outlined,
      ),
      PermissionItem(
        key: AppPermissions.manageDeliveryNotes,
        label: 'Remitos y Despachos',
        description:
            'Gestionar remitos de entrega física de almacén o corralón.',
        icon: Icons.description_outlined,
      ),
    ],
  ),
  PermissionCategory(
    title: '🏦 Cartera de Cheques',
    items: [
      PermissionItem(
        key: AppPermissions.viewChecks,
        label: 'Cartera de Cheques',
        description: 'Visualizar cheques de terceros recibidos en caja.',
        icon: Icons.fact_check_outlined,
      ),
      PermissionItem(
        key: AppPermissions.endorseChecks,
        label: 'Endosar o Depositar Cheques',
        description:
            'Cambiar el estado de cheques (endoso a proveedor, banco o rechazo).',
        icon: Icons.published_with_changes_outlined,
      ),
    ],
  ),
];

class EmployeeFormDialog extends StatefulWidget {
  final Map<String, dynamic>? employee; // null = crear nuevo

  const EmployeeFormDialog({super.key, this.employee});

  @override
  State<EmployeeFormDialog> createState() => _EmployeeFormDialogState();
}

class _EmployeeFormDialogState extends State<EmployeeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  String _role = 'cashier';
  Set<String> _permissions = {};
  Set<String> _cashierPermissionsBackup = {};

  bool get _isEditing => widget.employee != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _nameCtrl.text = widget.employee!['name']?.toString() ?? '';
      final rawRole = widget.employee!['role']?.toString().toLowerCase().trim();
      _role = (rawRole == 'admin') ? 'admin' : 'cashier';
      final perms = widget.employee!['permissions'];
      if (perms is Iterable) {
        _permissions =
            perms.whereType<String>().where((s) => s.trim().isNotEmpty).toSet();
      } else if (perms is Map) {
        _permissions = perms.entries
            .where((e) => e.value == true || e.value == 1 || e.value == 'true')
            .map((e) => e.key.toString().trim())
            .where((s) => s.isNotEmpty)
            .toSet();
      } else if (perms is String) {
        try {
          final parsed = jsonDecode(perms);
          if (parsed is Iterable) {
            _permissions = parsed
                .whereType<String>()
                .where((s) => s.trim().isNotEmpty)
                .toSet();
          } else if (parsed is Map) {
            _permissions = parsed.entries
                .where(
                    (e) => e.value == true || e.value == 1 || e.value == 'true')
                .map((e) => e.key.toString().trim())
                .where((s) => s.isNotEmpty)
                .toSet();
          }
        } catch (_) {}
      }
    }
    _cashierPermissionsBackup = Set<String>.from(_permissions);
    // Admins tienen todos los permisos implícitamente
    if (_role == 'admin') {
      _permissions = AppPermissions.all.toSet();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  void _onRoleChanged(String? val) {
    if (val == null || val == _role) return;
    setState(() {
      if (val == 'admin') {
        _cashierPermissionsBackup = Set<String>.from(_permissions);
        _permissions = AppPermissions.all.toSet();
      } else if (_role == 'admin') {
        _permissions = Set<String>.from(_cashierPermissionsBackup);
      }
      _role = val;
    });
  }

  Map<String, dynamic>? _submit() {
    if (!_formKey.currentState!.validate()) return null;
    final data = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'role': _role,
      'permissions': _role == 'admin'
          ? AppPermissions.all.toList()
          : _permissions.toList(),
    };
    if (_pinCtrl.text.isNotEmpty) {
      data['pin'] = _pinCtrl.text.trim();
    }
    return data;
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _role == 'admin';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.shade800,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_add_rounded,
                      color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isEditing ? 'Editar Empleado' : 'Nuevo Empleado',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            // Body
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 4,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Nombre
                              TextFormField(
                                controller: _nameCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Nombre del Empleado',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                        ? 'El nombre es requerido'
                                        : null,
                              ),
                              const SizedBox(height: 16),
                              // Rol
                              DropdownButtonFormField<String>(
                                initialValue: _role,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Rol',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.shield_outlined),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'cashier', child: Text('Cajero')),
                                  DropdownMenuItem(
                                      value: 'admin',
                                      child: Text('Administrador')),
                                ],
                                onChanged: _onRoleChanged,
                              ),
                              const SizedBox(height: 16),
                              // PIN
                              TextFormField(
                                controller: _pinCtrl,
                                decoration: InputDecoration(
                                  labelText: _isEditing
                                      ? 'Nuevo PIN (opcional)'
                                      : 'PIN de Acceso (4 dígitos)',
                                  border: const OutlineInputBorder(),
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  hintText: _isEditing
                                      ? 'Dejar vacío para no cambiar'
                                      : '****',
                                ),
                                obscureText: true,
                                maxLength: 4,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                validator: (v) {
                                  if (!_isEditing && (v == null || v.isEmpty)) {
                                    return 'El PIN es requerido';
                                  }
                                  if (v != null &&
                                      v.isNotEmpty &&
                                      v.length != 4) {
                                    return 'El PIN debe tener 4 dígitos';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 32),
                      Container(width: 1, color: Colors.grey.shade300),
                      const SizedBox(width: 32),
                      Expanded(
                        flex: 6,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Permisos
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  const Icon(Icons.key_rounded,
                                      size: 18, color: Colors.blueGrey),
                                  const SizedBox(width: 6),
                                  const Text('Permisos Específicos',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blueGrey)),
                                  if (isAdmin) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text('Acceso Total',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.blue,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ]
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isAdmin
                                    ? 'Los administradores poseen todos los permisos del sistema por defecto.'
                                    : 'Seleccione las operaciones que este cajero podrá ejecutar sin requerir PIN de supervisor.',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black54),
                              ),
                              const SizedBox(height: 12),
                              if (!isAdmin)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton.icon(
                                        onPressed: () {
                                          setState(() {
                                            _permissions
                                                .addAll(AppPermissions.all);
                                          });
                                        },
                                        icon: const Icon(
                                            Icons.check_box_outlined,
                                            size: 18),
                                        label: const Text('Marcar Todos',
                                            style: TextStyle(fontSize: 12)),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      TextButton.icon(
                                        onPressed: () {
                                          setState(() {
                                            _permissions.clear();
                                          });
                                        },
                                        icon: const Icon(
                                            Icons.check_box_outline_blank,
                                            size: 18,
                                            color: Colors.redAccent),
                                        label: const Text('Desmarcar Todos',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.redAccent)),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ...kCategorizedPermissions.map((category) {
                                int selectedCount = category.items
                                    .where((i) => _permissions.contains(i.key))
                                    .length;
                                bool? isCategoryFullySelected = isAdmin
                                    ? true
                                    : (selectedCount == 0
                                        ? false
                                        : (selectedCount ==
                                                category.items.length
                                            ? true
                                            : null));

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    border:
                                        Border.all(color: Colors.grey.shade200),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Theme(
                                    data: Theme.of(context).copyWith(
                                        dividerColor: Colors.transparent),
                                    child: ExpansionTile(
                                      key: PageStorageKey<String>(
                                          'perm_cat_${category.title}'),
                                      initiallyExpanded: true,
                                      tilePadding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 4),
                                      childrenPadding:
                                          const EdgeInsets.only(bottom: 8),
                                      title: Row(
                                        children: [
                                          Checkbox(
                                            value: isCategoryFullySelected,
                                            tristate: true,
                                            activeColor: Colors.blue.shade900,
                                            visualDensity: const VisualDensity(
                                                horizontal: -4, vertical: -4),
                                            onChanged: isAdmin
                                                ? null
                                                : (val) {
                                                    setState(() {
                                                      if (isCategoryFullySelected ==
                                                          true) {
                                                        for (var item
                                                            in category.items) {
                                                          _permissions
                                                              .remove(item.key);
                                                        }
                                                      } else {
                                                        for (var item
                                                            in category.items) {
                                                          _permissions
                                                              .add(item.key);
                                                        }
                                                      }
                                                    });
                                                  },
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              category.title,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: Colors.blue.shade900,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      children: category.items.map((item) {
                                        final checked = isAdmin ||
                                            _permissions.contains(item.key);
                                        return Material(
                                          color: Colors.transparent,
                                          child: CheckboxListTile(
                                            dense: true,
                                            value: checked,
                                            onChanged: isAdmin
                                                ? null
                                                : (val) {
                                                    setState(() {
                                                      if (val == true) {
                                                        _permissions
                                                            .add(item.key);
                                                      } else {
                                                        _permissions
                                                            .remove(item.key);
                                                      }
                                                    });
                                                  },
                                            title: Text(
                                              item.label,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13),
                                            ),
                                            subtitle: Text(
                                              item.description,
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.black54),
                                            ),
                                            secondary: Icon(
                                              item.icon,
                                              color: checked
                                                  ? Colors.blue.shade700
                                                  : Colors.grey,
                                              size: 20,
                                            ),
                                            activeColor: Colors.blue.shade700,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                            controlAffinity:
                                                ListTileControlAffinity.leading,
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Footer buttons
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Cancelar'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        final data = _submit();
                        if (data != null) Navigator.of(context).pop(data);
                      },
                      icon: const Icon(Icons.save_rounded),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                            _isEditing ? 'Guardar Cambios' : 'Crear Empleado'),
                      ),
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.blue.shade800),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lista aplanada de todos los permisos para compatibilidad hacia atrás
final List<Map<String, String>> kAllPermissions = List.unmodifiable(
  kCategorizedPermissions.expand((category) => category.items).map((item) => {
        'key': item.key,
        'label': item.label,
        'description': item.description,
        'icon': 'security',
      }),
);

