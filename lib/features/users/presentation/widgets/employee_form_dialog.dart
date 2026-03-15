import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Lista de todos los permisos disponibles con etiquetas y descripciones
const List<Map<String, String>> kAllPermissions = [
  {
    'key': 'void_sales',
    'label': 'Anular Ventas',
    'description': 'Cancelar o anular ventas registradas',
    'icon': 'cancel',
  },
  {
    'key': 'manage_catalog',
    'label': 'Modificar Catálogo',
    'description': 'Editar productos, precios y categorías',
    'icon': 'inventory_2',
  },
  {
    'key': 'adjust_stock',
    'label': 'Ajustar Stock',
    'description': 'Registrar entradas y salidas de inventario',
    'icon': 'move_to_inbox',
  },
  {
    'key': 'view_global_history',
    'label': 'Ver Historial Global',
    'description': 'Ver ventas de días/meses anteriores y estadísticas',
    'icon': 'history',
  },
];

class EmployeeFormDialog extends StatefulWidget {
  final Map<String, dynamic>? employee; // null = crear nuevo

  const EmployeeFormDialog({Key? key, this.employee}) : super(key: key);

  @override
  State<EmployeeFormDialog> createState() => _EmployeeFormDialogState();
}

class _EmployeeFormDialogState extends State<EmployeeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  String _role = 'cashier';
  Set<String> _permissions = {};

  bool get _isEditing => widget.employee != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _nameCtrl.text = widget.employee!['name'] ?? '';
      _role = widget.employee!['role'] ?? 'cashier';
      final perms = widget.employee!['permissions'];
      if (perms != null) {
        _permissions = Set<String>.from(perms as List);
      }
    }
    // Admins tienen todos los permisos implícitamente
    if (_role == 'admin') {
      _permissions = kAllPermissions.map((p) => p['key']!).toSet();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  void _onRoleChanged(String? val) {
    if (val == null) return;
    setState(() {
      _role = val;
      if (_role == 'admin') {
        _permissions = kAllPermissions.map((p) => p['key']!).toSet();
      }
    });
  }

  Map<String, dynamic>? _submit() {
    if (!_formKey.currentState!.validate()) return null;
    final data = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'role': _role,
      'permissions': _permissions.toList(),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.shade800,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_add_rounded, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    _isEditing ? 'Editar Empleado' : 'Nuevo Empleado',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
            ),
            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Nombre
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del Empleado',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'El nombre es requerido' : null,
                      ),
                      const SizedBox(height: 16),
                      // Rol
                      DropdownButtonFormField<String>(
                        value: _role,
                        decoration: const InputDecoration(
                          labelText: 'Rol',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.shield_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'cashier', child: Text('Cajero')),
                          DropdownMenuItem(value: 'admin', child: Text('Administrador')),
                        ],
                        onChanged: _onRoleChanged,
                      ),
                      const SizedBox(height: 16),
                      // PIN
                      TextFormField(
                        controller: _pinCtrl,
                        decoration: InputDecoration(
                          labelText: _isEditing ? 'Nuevo PIN (opcional)' : 'PIN de Acceso (4 dígitos)',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock_outline),
                          hintText: _isEditing ? 'Dejar vacío para no cambiar' : '****',
                        ),
                        obscureText: true,
                        maxLength: 4,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (v) {
                          if (!_isEditing && (v == null || v.isEmpty)) return 'El PIN es requerido';
                          if (v != null && v.isNotEmpty && v.length != 4) return 'El PIN debe tener 4 dígitos';
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      // Permisos
                      Row(
                        children: [
                          const Icon(Icons.key_rounded, size: 18, color: Colors.blueGrey),
                          const SizedBox(width: 6),
                          const Text('Permisos Específicos', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                          if (isAdmin) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text('Acceso Total', style: TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.bold)),
                            ),
                          ]
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...kAllPermissions.map((perm) {
                        final key = perm['key']!;
                        final checked = isAdmin || _permissions.contains(key);
                        return CheckboxListTile(
                          dense: true,
                          value: checked,
                          onChanged: isAdmin ? null : (val) {
                            setState(() {
                              if (val == true) _permissions.add(key);
                              else _permissions.remove(key);
                            });
                          },
                          title: Text(perm['label']!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text(perm['description']!, style: const TextStyle(fontSize: 12)),
                          secondary: Icon(
                            _iconFromName(perm['icon']!),
                            color: checked ? Colors.blue.shade700 : Colors.grey,
                          ),
                          activeColor: Colors.blue.shade700,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          tileColor: checked ? Colors.blue.shade50 : null,
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      }),
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
                      child: const Text('Cancelar'),
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
                      label: Text(_isEditing ? 'Guardar Cambios' : 'Crear Empleado'),
                      style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade800),
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

  IconData _iconFromName(String name) {
    switch (name) {
      case 'cancel': return Icons.cancel_outlined;
      case 'inventory_2': return Icons.inventory_2_outlined;
      case 'move_to_inbox': return Icons.move_to_inbox_outlined;
      case 'history': return Icons.history_rounded;
      default: return Icons.settings;
    }
  }
}
