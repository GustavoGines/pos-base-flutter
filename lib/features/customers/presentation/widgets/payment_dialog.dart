import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/customer_model.dart';
import '../../providers/customer_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';

class PaymentDialog extends StatefulWidget {
  final Customer customer;

  const PaymentDialog({super.key, required this.customer});

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _checkBankCtrl = TextEditingController();
  final _checkNumberCtrl = TextEditingController();
  final _checkIssuerCuitCtrl = TextEditingController();
  final _checkIssuerNameCtrl = TextEditingController();
  final _checkIssueDateCtrl = TextEditingController();
  final _checkPaymentDateCtrl = TextEditingController();
  
  bool _isSubmitting = false;
  String _paymentType = 'general';
  String _paymentMethod = 'cash';
  List<int> _selectedSaleIds = [];

  @override
  void initState() {
    super.initState();
    _descriptionController.text = '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CustomerProvider>().fetchPendingSales(widget.customer.id);
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _checkBankCtrl.dispose();
    _checkNumberCtrl.dispose();
    _checkIssuerCuitCtrl.dispose();
    _checkIssuerNameCtrl.dispose();
    _checkIssueDateCtrl.dispose();
    _checkPaymentDateCtrl.dispose();
    super.dispose();
  }

  void _calculateSelectedAmount() {
    if (_paymentType == 'general') return;
    final provider = context.read<CustomerProvider>();
    double total = 0.0;
    for (var sale in provider.pendingSales) {
      if (_selectedSaleIds.contains(sale['id'])) {
        total += double.tryParse(sale['amount_due'].toString()) ?? 0.0;
      }
    }
    if (total > 0) {
      _amountController.text = total.toCurrency();
    } else {
      _amountController.text = '';
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final cleanAmount = _amountController.text.replaceAll('\$', '').replaceAll('.', '').replaceAll(' ', '').trim();
    final amount = double.tryParse(cleanAmount) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El monto debe ser mayor a 0'), backgroundColor: Colors.red),
      );
      return;
    }

    if (_paymentType == 'specific' && _selectedSaleIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes seleccionar al menos un ticket'), backgroundColor: Colors.red),
      );
      return;
    }

    Map<String, dynamic>? checkDetailsPayload;
    if (_paymentMethod == 'cheque') {
      if (_checkBankCtrl.text.trim().isEmpty ||
          _checkNumberCtrl.text.trim().isEmpty ||
          _checkIssuerCuitCtrl.text.trim().isEmpty ||
          _checkIssuerNameCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Complete los datos obligatorios del cheque (Banco, Número, CUIT, Firmante).'), backgroundColor: Colors.red),
        );
        return;
      }
      checkDetailsPayload = {
        'bank_name': _checkBankCtrl.text.trim(),
        'check_number': _checkNumberCtrl.text.trim(),
        'issuer_cuit': _checkIssuerCuitCtrl.text.trim(),
        'issuer_name': _checkIssuerNameCtrl.text.trim(),
        'issue_date': _checkIssueDateCtrl.text.trim().isNotEmpty ? _checkIssueDateCtrl.text.trim() : DateTime.now().toString().split(' ')[0],
        'payment_date': _checkPaymentDateCtrl.text.trim().isNotEmpty ? _checkPaymentDateCtrl.text.trim() : DateTime.now().toString().split(' ')[0],
      };
    }

    setState(() => _isSubmitting = true);

    try {
      final success = await context.read<CustomerProvider>().registerPayment(
        customerId: widget.customer.id, 
        amount: amount, 
        paymentMethod: _paymentMethod,
        description: _descriptionController.text.trim(),
        saleIds: _paymentType == 'specific' ? _selectedSaleIds : const [],
        checkDetails: checkDetailsPayload,
      );

      if (success && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pago registrado correctamente'), backgroundColor: Colors.green),
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
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CustomerProvider>();
    final settings = context.watch<SettingsProvider>().settings;

    return AlertDialog(
      title: Text('Registrar Pago - ${widget.customer.name}'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200)
                  ),
                  child: Column(
                    children: [
                      const Text('Deuda Actual', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        '\$ ${widget.customer.balance.toCurrency()}', 
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red.shade700)
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                const Text('Tipo de Abono', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'general', label: Text('Abono General')),
                    ButtonSegment(value: 'specific', label: Text('Tickets Específicos')),
                  ],
                  selected: {_paymentType},
                  onSelectionChanged: (Set<String> newSelection) {
                    setState(() {
                      _paymentType = newSelection.first;
                      if (_paymentType == 'specific') {
                        _amountController.text = '';
                        _descriptionController.text = '';
                        _calculateSelectedAmount();
                      } else {
                        _descriptionController.text = '';
                        _amountController.text = '';
                      }
                    });
                  },
                ),
                const SizedBox(height: 16),

                if (_paymentType == 'specific') ...[
                  const Text('Tickets Pendientes', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: provider.pendingSales.isEmpty
                        ? const Center(child: Text('No hay tickets pendientes'))
                        : ListView.builder(
                            itemCount: provider.pendingSales.length,
                            itemBuilder: (context, index) {
                              final sale = provider.pendingSales[index];
                              final saleId = sale['id'] as int;
                              final amountDue = double.tryParse(sale['amount_due'].toString()) ?? 0.0;
                              final dateStr = sale['created_at']?.toString() ?? '';
                              final date = dateStr.isNotEmpty ? DateTime.parse(dateStr).toLocal().toString().split(' ')[0] : '';
                              
                              final isSelected = _selectedSaleIds.contains(saleId);
                              
                              return CheckboxListTile(
                                title: Text('Ticket #$saleId'),
                                subtitle: Text('Fecha: $date'),
                                secondary: Text('\$${amountDue.toCurrency()}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                                value: isSelected,
                                onChanged: (bool? val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedSaleIds.add(saleId);
                                    } else {
                                      _selectedSaleIds.remove(saleId);
                                    }
                                    _calculateSelectedAmount();
                                  });
                                },
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 16),
                ],

                DropdownButtonFormField<String>(
                  value: _paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Método de Pago *',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                    const DropdownMenuItem(value: 'card', child: Text('Tarjeta')),
                    const DropdownMenuItem(value: 'transfer', child: Text('Transferencia')),
                    if (settings?.features.checks == true)
                      const DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _paymentMethod = val);
                  },
                ),
                const SizedBox(height: 16),

                if (_paymentMethod == 'cheque')
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Detalles del Cheque', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: TextField(controller: _checkBankCtrl, decoration: InputDecoration(labelText: 'Banco', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: true, fillColor: Colors.white))),
                            const SizedBox(width: 8),
                            Expanded(child: TextField(controller: _checkNumberCtrl, decoration: InputDecoration(labelText: 'Nro Cheque', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: true, fillColor: Colors.white))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: TextField(controller: _checkIssuerCuitCtrl, decoration: InputDecoration(labelText: 'CUIT Firmante', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: true, fillColor: Colors.white))),
                            const SizedBox(width: 8),
                            Expanded(child: TextField(controller: _checkIssuerNameCtrl, decoration: InputDecoration(labelText: 'Nombre Firmante', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: true, fillColor: Colors.white))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: TextField(controller: _checkIssueDateCtrl, decoration: InputDecoration(labelText: 'Emisión (YYYY-MM-DD)', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: true, fillColor: Colors.white))),
                            const SizedBox(width: 8),
                            Expanded(child: TextField(controller: _checkPaymentDateCtrl, decoration: InputDecoration(labelText: 'Cobro (YYYY-MM-DD)', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: true, fillColor: Colors.white))),
                          ],
                        ),
                      ],
                    ),
                  ),

                TextFormField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  readOnly: _paymentType == 'specific',
                  decoration: const InputDecoration(
                    labelText: 'Monto a Pagar *', 
                    prefixText: '\$ ',
                    border: OutlineInputBorder()
                  ),
                  validator: (val) => val == null || val.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción / Nota', 
                    border: OutlineInputBorder()
                  ),
                ),
              ],
            ),
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
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
          child: _isSubmitting 
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text('Confirmar Pago', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
