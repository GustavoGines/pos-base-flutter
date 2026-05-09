import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/customer_model.dart';
import '../../providers/customer_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/widgets/admin_pin_dialog.dart';

class CustomerFormDialog extends StatefulWidget {
  final Customer? customer; // Null = Nuevo, No-null = Editar

  const CustomerFormDialog({super.key, this.customer});

  @override
  State<CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _documentController;
  late TextEditingController _phoneController;
  late TextEditingController _creditLimitController;
  late TextEditingController _deliveryAddressController;
  bool _isInternalAccount = false;
  
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.customer?.name ?? '');
    _documentController = TextEditingController(text: widget.customer?.documentNumber ?? '');
    _phoneController = TextEditingController(text: widget.customer?.phone ?? '');
    _creditLimitController = TextEditingController(text: widget.customer != null ? widget.customer!.creditLimit.toString() : '');
    _deliveryAddressController = TextEditingController(text: widget.customer?.deliveryAddress ?? '');
    _isInternalAccount = widget.customer?.isInternalAccount ?? false;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final payload = {
        'name': _nameController.text.trim(),
        'document_number': _documentController.text.trim(),
        'phone': _phoneController.text.trim(),
        'credit_limit': double.tryParse(_creditLimitController.text.trim()) ?? 0.0,
        'delivery_address': _deliveryAddressController.text.trim(),
        'is_internal_account': _isInternalAccount,
      };

      bool success;
      if (widget.customer == null) {
        success = await context.read<CustomerProvider>().createCustomer(payload);
      } else {
        final newCreditLimit = payload['credit_limit'] as double;
        final oldCreditLimit = widget.customer!.creditLimit;
        
        if (newCreditLimit != oldCreditLimit) {
          final isAuthorized = await AdminPinDialog.verify(
            context,
            action: 'Modificar límite de crédito del cliente'
          );
          if (!isAuthorized) {
            setState(() => _isSubmitting = false);
            return;
          }
        }
        
        if (!mounted) return;
        success = await context.read<CustomerProvider>().updateCustomer(widget.customer!.id, payload);
      }

      if (success && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.customer == null ? 'Cliente creado exitosamente' : 'Cliente actualizado exitosamente'), 
            backgroundColor: Colors.green
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _documentController.dispose();
    _phoneController.dispose();
    _creditLimitController.dispose();
    _deliveryAddressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.customer != null;

    return AlertDialog(
      title: Text(isEditing ? 'Editar Cliente' : 'Nuevo Cliente'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nombre *', border: OutlineInputBorder()),
                validator: (val) => val == null || val.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _documentController,
                decoration: const InputDecoration(labelText: 'Documento / DNI *', border: OutlineInputBorder()),
                validator: (val) => val == null || val.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Teléfono (Opcional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _deliveryAddressController,
                decoration: const InputDecoration(labelText: 'Dirección de Entrega (Opcional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _creditLimitController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Límite de Crédito (\$) (Opcional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Cuenta de Consumo Interno (Ej: Repostería / Uso Propio)', style: TextStyle(fontSize: 14)),
                subtitle: const Text('Excluye estas ventas de los reportes de ganancias y facturación.', style: TextStyle(fontSize: 12)),
                value: _isInternalAccount,
                activeColor: Colors.indigo,
                onChanged: (val) => setState(() => _isInternalAccount = val),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
          child: _isSubmitting 
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text('Guardar', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

