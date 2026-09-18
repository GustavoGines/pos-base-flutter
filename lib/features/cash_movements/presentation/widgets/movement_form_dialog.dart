import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/cash_movement_provider.dart';
import '../../../suppliers/providers/supplier_provider.dart';
import '../../../checks/presentation/providers/check_provider.dart';
import '../../../checks/domain/entities/third_party_check.dart';
import '../../../auth/presentation/widgets/admin_pin_dialog.dart';

class PaymentItem {
  final String method;
  final double amount;
  final int? checkId;
  final ThirdPartyCheck? checkObj;

  PaymentItem({
    required this.method,
    required this.amount,
    this.checkId,
    this.checkObj,
  });
}

class MovementFormDialog extends StatefulWidget {
  const MovementFormDialog({Key? key}) : super(key: key);

  @override
  State<MovementFormDialog> createState() => _MovementFormDialogState();
}

class _MovementFormDialogState extends State<MovementFormDialog> {
  final _formKey = GlobalKey<FormState>();
  
  String _type = 'expense';
  String _category = 'Mercadería';
  
  final _descriptionController = TextEditingController();
  final _receiptController = TextEditingController();
  
  int? _selectedSupplierId;
  bool _isLoading = false;

  // Pagos mixtos
  final List<PaymentItem> _payments = [];
  String _currentPaymentMethod = 'cash';
  int? _currentCheckId;
  final _paymentAmountController = TextEditingController();

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

  double get _totalAmount => _payments.fold(0.0, (sum, item) => sum + item.amount);

  void _addPayment() {
    final amount = double.tryParse(_paymentAmountController.text) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingrese un monto válido.')));
      return;
    }
    
    ThirdPartyCheck? checkObj;
    if (_currentPaymentMethod == 'check') {
      if (_currentCheckId == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seleccione un cheque.')));
        return;
      }
      final checks = context.read<CheckProvider>().checks;
      checkObj = checks.firstWhere((c) => c.id == _currentCheckId);
    }

    setState(() {
      _payments.add(PaymentItem(
        method: _currentPaymentMethod,
        amount: amount,
        checkId: _currentCheckId,
        checkObj: checkObj,
      ));
      _paymentAmountController.clear();
      _currentCheckId = null;
    });
  }

  void _removePayment(int index) {
    setState(() {
      _payments.removeAt(index);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_payments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Agregue al menos un método de pago.')));
      return;
    }

    if (_type == 'withdrawal') {
      final pin = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AdminPinDialog(actionDescription: 'Autorizar Retiro de Caja'),
      );

      if (pin == null) return;
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
        'payments': _payments.map((p) => {
          'amount': p.amount,
          'payment_method': p.method,
          'check_id': p.checkId,
        }).toList()
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
    final availableChecks = checkProv.checks.where((c) => c.status == 'in_wallet').toList();

    return AlertDialog(
      title: const Text('Registrar Movimiento de Caja'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // DATOS GENERALES
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _type,
                        decoration: const InputDecoration(labelText: 'Tipo de Movimiento'),
                        items: const [
                          DropdownMenuItem(value: 'expense', child: Text('Gasto (Salida)')),
                          DropdownMenuItem(value: 'withdrawal', child: Text('Retiro de Dueño (Salida)')),
                          DropdownMenuItem(value: 'deposit', child: Text('Ingreso Extra (Entrada)')),
                        ],
                        onChanged: (val) => setState(() {
                          _type = val!;
                          if (_type == 'deposit') _category = 'Otros';
                        }),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _type == 'deposit'
                          ? TextFormField(
                              initialValue: 'Ingreso Extra',
                              enabled: false,
                              decoration: const InputDecoration(labelText: 'Categoría'),
                            )
                          : DropdownButtonFormField<String>(
                              value: _category,
                              decoration: const InputDecoration(labelText: 'Categoría'),
                              items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                              onChanged: (val) => setState(() => _category = val!),
                            ),
                    ),
                  ],
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
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(labelText: 'Detalle / Descripción'),
                        validator: (val) {
                          if (_category == 'Otros' && (val == null || val.isEmpty)) {
                            return 'Requerido para la categoría "Otros"';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _receiptController,
                        decoration: const InputDecoration(labelText: 'Nº Comprobante (Opc.)'),
                      ),
                    ),
                  ],
                ),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Divider(),
                ),
                
                // PAGOS MIXTOS
                Text('Métodos de Pago', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                
                // Lista de pagos agregados
                if (_payments.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _payments.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final p = _payments[index];
                        return ListTile(
                          dense: true,
                          title: Text(p.method.toUpperCase()),
                          subtitle: p.checkObj != null 
                              ? Text('Cheque Nº ${p.checkObj!.checkNumber} - ${p.checkObj!.bankName}') 
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('\$ ${p.amount}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                onPressed: () => _removePayment(index),
                              )
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                // Agregar nuevo pago
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              value: _currentPaymentMethod,
                              decoration: const InputDecoration(labelText: 'Método', isDense: true),
                              items: const [
                                DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                                DropdownMenuItem(value: 'transfer', child: Text('Transf.')),
                                DropdownMenuItem(value: 'check', child: Text('Cheque')),
                              ],
                              onChanged: (val) => setState(() {
                                _currentPaymentMethod = val!;
                                _currentCheckId = null;
                                _paymentAmountController.clear();
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _paymentAmountController,
                              decoration: const InputDecoration(labelText: 'Monto', prefixText: '\$', isDense: true),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              enabled: _currentPaymentMethod != 'check',
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _addPayment,
                            child: const Text('Agregar'),
                          ),
                        ],
                      ),
                      if (_currentPaymentMethod == 'check') ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          value: _currentCheckId,
                          decoration: const InputDecoration(labelText: 'Seleccionar Cheque en Cartera', isDense: true),
                          items: availableChecks.map((c) => DropdownMenuItem(
                            value: c.id,
                            child: Text('Nº ${c.checkNumber} (\$ ${c.amount}) - ${c.bankName}'),
                          )).toList(),
                          onChanged: (val) {
                            setState(() {
                              _currentCheckId = val;
                              if (val != null) {
                                final check = availableChecks.firstWhere((c) => c.id == val);
                                _paymentAmountController.text = check.amount.toString();
                              }
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'TOTAL: ${NumberFormat.currency(symbol: '\$').format(_totalAmount)}',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _isLoading ? null : _submit,
          icon: _isLoading 
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save),
          label: const Text('Procesar Movimiento'),
        ),
      ],
    );
  }
}
