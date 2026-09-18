import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/supplier_provider.dart';

class SupplierFormDialog extends StatefulWidget {
  final int? supplierId;
  final Map<String, dynamic>? initialData;

  const SupplierFormDialog({super.key, this.supplierId, this.initialData});

  @override
  State<SupplierFormDialog> createState() => _SupplierFormDialogState();
}

class _SupplierFormDialogState extends State<SupplierFormDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  late TextEditingController _nameController;
  late TextEditingController _cuitController;
  late TextEditingController _contactNameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _addressController;
  String _taxCategory = 'Responsable Inscripto';
  bool _isActive = true;

  final List<String> _taxCategories = [
    'Responsable Inscripto',
    'Monotributista',
    'Exento',
    'Consumidor Final',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialData?['name'] ?? '');
    _cuitController = TextEditingController(text: widget.initialData?['cuit'] ?? '');
    _contactNameController = TextEditingController(text: widget.initialData?['contact_name'] ?? '');
    _phoneController = TextEditingController(text: widget.initialData?['phone'] ?? '');
    _emailController = TextEditingController(text: widget.initialData?['email'] ?? '');
    _addressController = TextEditingController(text: widget.initialData?['address'] ?? '');
    
    if (widget.initialData != null) {
      final tc = widget.initialData!['tax_category'] ?? 'Responsable Inscripto';
      _taxCategory = _taxCategories.contains(tc) ? tc : _taxCategories.first;
      final activeVal = widget.initialData!['is_active'];
      _isActive = activeVal == null ? true : (activeVal == 1 || activeVal == true || activeVal == '1');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cuitController.dispose();
    _contactNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final cuit = _cuitController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();

    final data = {
      'name': _nameController.text.trim(),
      'cuit': cuit.isEmpty ? null : cuit,
      'tax_category': _taxCategory,
      'contact_name': _contactNameController.text.trim(),
      'phone': phone.isEmpty ? null : phone,
      'email': email.isEmpty ? null : email,
      'address': _addressController.text.trim(),
      'is_active': _isActive,
    };

    try {
      final provider = context.read<SupplierProvider>();
      if (widget.supplierId == null) {
        await provider.createSupplier(data);
      } else {
        await provider.updateSupplier(widget.supplierId!, data);
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Proveedor guardado exitosamente'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.supplierId != null;

    return AlertDialog(
      title: Text(isEditing ? 'Editar Proveedor' : 'Nuevo Proveedor', style: const TextStyle(fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Razón Social / Nombre *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.business),
                    isDense: true,
                  ),
                  validator: (val) => val == null || val.isEmpty ? 'El nombre es obligatorio' : null,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _cuitController,
                        decoration: const InputDecoration(
                          labelText: 'CUIT',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.badge_outlined),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _taxCategory,
                        decoration: const InputDecoration(
                          labelText: 'Condición IVA',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: _taxCategories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _taxCategory = val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _contactNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del Contacto',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phoneController,
                        decoration: const InputDecoration(
                          labelText: 'Teléfono / WhatsApp',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.phone_outlined),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.email_outlined),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Dirección',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on_outlined),
                    isDense: true,
                  ),
                  minLines: 1,
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Proveedor Activo', style: TextStyle(fontWeight: FontWeight.bold)),
                  value: _isActive,
                  onChanged: (val) => setState(() => _isActive = val),
                  contentPadding: EdgeInsets.zero,
                  activeTrackColor: Colors.blueAccent.withOpacity(0.5), activeThumbColor: Colors.blueAccent,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _isLoading ? null : _save,
          icon: _isLoading 
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save),
          label: const Text('Guardar'),
        ),
      ],
    );
  }
}
