import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/cash_movement_provider.dart';
import '../../../suppliers/providers/supplier_provider.dart';
import '../../../checks/presentation/providers/check_provider.dart';
import '../../../auth/presentation/widgets/admin_pin_dialog.dart';

class MovementFormDialog extends StatefulWidget {
  const MovementFormDialog({Key? key}) : super(key: key);

  @override
  State<MovementFormDialog> createState() => _MovementFormDialogState();
}

class _MovementFormDialogState extends State<MovementFormDialog> {
  final _formKey = GlobalKey<FormState>();
  
  String _type = 'expense';
  String _category = 'Mercadería';
  String _paymentMethod = 'cash';
  
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _receiptController = TextEditingController();
  
  int? _selectedSupplierId;
  int? _selectedCheckId;
  
  bool _isLoading = false;

  final List<String> _categories = [
    'Mercadería',
    'Servicios',
    'Sueldos',
    'Limpieza',
    'Impuestos',
    'Pago a Proveedor',
    'Otros'
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SupplierProvider>().fetchSuppliers();
      context.read<CheckProvider>().loadChecks();
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_type == 'withdrawal') {
      final pin = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AdminPinDialog(reason: 'Autorizar Retiro de Caja'),
      );

      if (pin == null) return; // Cancelado
      await _executeSubmit(adminPin: pin);
    } else {
      await _executeSubmit();
    }
  }

  Future<void> _executeSubmit({String? adminPin}) async {
    setState(() => _isLoading = true);

    try {
      final provider = context.read<CashMovementProvider>();
      
      final data = {
        'type': _type,
        'category': _category,
        'description': _descriptionController.text,
        'receipt_number': _receiptController.text,
        'supplier_id': _selectedSupplierId,
        'payments': [
          {
            'amount': double.parse(_amountController.text),
            'payment_method': _paymentMethod,
            'check_id': _selectedCheckId,
          }
        ]
      };

      await provider.createMovement(data, adminPin: adminPin);
      
      if (_category == 'Pago a Proveedor') {
        context.read<SupplierProvider>().fetchSuppliers();
      }
      
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Movimiento registrado correctamente.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final supplierProv = context.watch<SupplierProvider>();
    final checkProv = context.watch<CheckProvider>();

    return AlertDialog(
      title: const Text('Registrar Movimiento de Caja'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Tipo de Movimiento'),
                items: const [
                  DropdownMenuItem(value: 'expense', child: Text('Gasto (Salida)')),
                  DropdownMenuItem(value: 'withdrawal', child: Text('Retiro de Dueño (Salida)')),
                  DropdownMenuItem(value: 'deposit', child: Text('Ingreso Extra (Entrada)')),
                ],
                onChanged: (val) => setState(() {
                  _type = val!;
                  if (_type == 'deposit') _category = 'Otros'; // Reset category if deposit
                }),
              ),
              const SizedBox(height: 16),
              if (_type != 'deposit')
                DropdownButtonFormField<String>(
                  value: _category,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (val) => setState(() => _category = val!),
                ),
              if (_type == 'deposit')
                TextFormField(
                  initialValue: 'Ingreso Extra',
                  enabled: false,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                ),
              const SizedBox(height: 16),
              
              if (_category == 'Pago a Proveedor')
                DropdownButtonFormField<int>(
                  value: _selectedSupplierId,
                  decoration: const InputDecoration(labelText: 'Seleccionar Proveedor'),
                  items: supplierProv.suppliers.map((s) => DropdownMenuItem(
                    value: s.id,
                    child: Text(s.name),
                  )).toList(),
                  onChanged: (val) => setState(() => _selectedSupplierId = val),
                  validator: (val) => val == null ? 'Debe seleccionar un proveedor' : null,
                ),
                
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(labelText: 'Monto Total', prefixText: '\$'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Requerido';
                  if (double.tryParse(val) == null) return 'Monto inválido';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              DropdownButtonFormField<String>(
                value: _paymentMethod,
                decoration: const InputDecoration(labelText: 'Método de Pago'),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                  DropdownMenuItem(value: 'transfer', child: Text('Transferencia')),
                  DropdownMenuItem(value: 'check', child: Text('Cheque de Terceros')),
                ],
                onChanged: (val) => setState(() => _paymentMethod = val!),
              ),
              
              if (_paymentMethod == 'check') ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: _selectedCheckId,
                  decoration: const InputDecoration(labelText: 'Seleccionar Cheque (En Cartera)'),
                  items: checkProv.checks
                      .where((c) => c.status == 'in_wallet')
                      .map((c) => DropdownMenuItem(
                            value: c.id,
                            child: Text('Nº $'{c.checkNumber} - $'{c.bankName} (\$ $'{c.amount})'),
                          ))
                      .toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedCheckId = val;
                      if (val != null) {
                        final check = checkProv.checks.firstWhere((c) => c.id == val);
                        _amountController.text = check.amount.toString();
                      }
                    });
                  },
                  validator: (val) => val == null ? 'Debe seleccionar un cheque' : null,
                ),
              ],
              
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Detalle / Descripción'),
                validator: (val) {
                  if (_category == 'Otros' && (val == null || val.isEmpty)) {
                    return 'Requerido para la categoría "Otros"';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _receiptController,
                decoration: const InputDecoration(labelText: 'Nº Comprobante / Recibo (Opcional)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading 
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Guardar'),
        ),
      ],
    );
  }
}
