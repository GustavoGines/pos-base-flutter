import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/customer_model.dart';
import '../../providers/customer_provider.dart';

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
  late TextEditingController _creditLimitController;
  
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.customer?.name ?? '');
    _documentController = TextEditingController(text: widget.customer?.documentNumber ?? '');
    _creditLimitController = TextEditingController(text: widget.customer != null ? widget.customer!.creditLimit.toString() : '');
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final payload = {
        'name': _nameController.text.trim(),
        'document_number': _documentController.text.trim(),
        'credit_limit': double.tryParse(_creditLimitController.text.trim()) ?? 0.0,
      };

      bool success;
      if (widget.customer == null) {
        success = await context.read<CustomerProvider>().createCustomer(payload);
      } else {
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
    _creditLimitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.customer != null;

    return AlertDialog(
      title: Text(isEditing ? 'Editar Cliente' : 'Nuevo Cliente (Cta. Cte.)'),
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
                controller: _creditLimitController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Límite de Crédito (\$) (Opcional)', border: OutlineInputBorder()),
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
