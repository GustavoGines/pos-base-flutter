import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/supplier_provider.dart';
import '../../../cash_movements/presentation/widgets/movement_form_dialog.dart';
import '../../../cash_register/presentation/providers/cash_register_provider.dart';

class SupplierInvoiceFormDialog extends StatefulWidget {
  final int supplierId;
  final String supplierName;

  const SupplierInvoiceFormDialog({
    super.key,
    required this.supplierId,
    required this.supplierName,
  });

  @override
  State<SupplierInvoiceFormDialog> createState() => _SupplierInvoiceFormDialogState();
}

class _SupplierInvoiceFormDialogState extends State<SupplierInvoiceFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _invoiceNumberController = TextEditingController();
  final _descriptionController = TextEditingController(text: 'Mercadería');

  bool _isLoading = false;
  bool _payNow = false;

  @override
  void dispose() {
    _amountController.dispose();
    _invoiceNumberController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final data = {
        'amount': double.parse(_amountController.text),
        'invoice_number': _invoiceNumberController.text.trim(),
        'description': _descriptionController.text.trim(),
      };

      final provider = context.read<SupplierProvider>();
      final success = await provider.createInvoice(widget.supplierId, data);

      if (success && mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Factura cargada correctamente. Deuda actualizada.')));

        if (_payNow) {
          final cashProv = context.read<CashRegisterProvider>();
          if (cashProv.currentShift != null && cashProv.currentShift!.isOpen) {
             showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => MovementFormDialog(
                initialSupplierId: widget.supplierId,
                initialType: 'expense',
                initialCategory: 'Pago a Proveedor',
                initialAmount: double.parse(_amountController.text),
              ),
            );
          } else {
             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se puede abonar ahora porque no hay turno de caja abierto.'.toString()), backgroundColor: Colors.red));
          }
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().toString()), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        width: 450,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cargar Factura / Remito',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Proveedor: ${widget.supplierName}',
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 24),

              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Monto Total',
                  prefixText: '\$ ',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Requerido';
                  if (double.tryParse(val) == null || double.parse(val) <= 0) return 'Monto inválido';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _invoiceNumberController,
                      decoration: const InputDecoration(labelText: 'Nº Factura / Remito (Opcional)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Detalle / Concepto'),
              ),
              
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: CheckboxListTile(
                  title: const Text('¿Abonar parte de esta factura ahora?', style: TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: const Text('Abre la caja para registrar un pago a proveedor.', style: TextStyle(fontSize: 12)),
                  value: _payNow,
                  onChanged: (val) => setState(() => _payNow = val ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                ),
              ),

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _submit,
                    icon: _isLoading 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.receipt_long),
                    label: const Text('Registrar Compra'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
