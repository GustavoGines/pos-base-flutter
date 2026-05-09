import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/customer_model.dart';
import '../../providers/customer_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';

class _PaymentLine {
  String method;
  TextEditingController amountCtrl;
  TextEditingController checkBankCtrl;
  TextEditingController checkNumberCtrl;
  TextEditingController checkIssuerCuitCtrl;
  TextEditingController checkIssuerNameCtrl;
  TextEditingController checkIssueDateCtrl;
  TextEditingController checkPaymentDateCtrl;

  _PaymentLine({required this.method}) : 
    amountCtrl = TextEditingController(),
    checkBankCtrl = TextEditingController(),
    checkNumberCtrl = TextEditingController(),
    checkIssuerCuitCtrl = TextEditingController(),
    checkIssuerNameCtrl = TextEditingController(),
    checkIssueDateCtrl = TextEditingController(),
    checkPaymentDateCtrl = TextEditingController();

  void dispose() {
    amountCtrl.dispose();
    checkBankCtrl.dispose();
    checkNumberCtrl.dispose();
    checkIssuerCuitCtrl.dispose();
    checkIssuerNameCtrl.dispose();
    checkIssueDateCtrl.dispose();
    checkPaymentDateCtrl.dispose();
  }
}

class PaymentDialog extends StatefulWidget {
  final Customer customer;

  const PaymentDialog({super.key, required this.customer});

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  
  bool _isSubmitting = false;
  String _paymentType = 'general';
  List<int> _selectedSaleIds = [];
  final List<_PaymentLine> _lines = [];

  double _targetAmount = 0.0;

  @override
  void initState() {
    super.initState();
    _descriptionController.text = '';
    
    if (widget.customer.balance > 0) {
      _targetAmount = widget.customer.balance.abs();
    }
    _addLine(initialAmount: _targetAmount);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CustomerProvider>().fetchPendingSales(widget.customer.id);
    });
  }

  void _addLine({double initialAmount = 0.0}) {
    final line = _PaymentLine(method: 'cash');
    if (initialAmount > 0) {
      line.amountCtrl.text = initialAmount.toStringAsFixed(2);
    }
    line.amountCtrl.addListener(_onAmountChanged);
    _lines.add(line);
    setState(() {});
  }

  void _removeLine(_PaymentLine line) {
    if (_lines.length <= 1) return;
    line.amountCtrl.removeListener(_onAmountChanged);
    line.dispose();
    _lines.remove(line);
    setState(() {});
  }

  void _onAmountChanged() => setState(() {});

  @override
  void dispose() {
    _descriptionController.dispose();
    for (var line in _lines) {
      line.amountCtrl.removeListener(_onAmountChanged);
      line.dispose();
    }
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
    
    setState(() {
      _targetAmount = total;
      if (_lines.length == 1) {
        _lines[0].amountCtrl.text = total > 0 ? total.toStringAsFixed(2) : '';
      }
    });
  }

  double get _totalEntered {
    return _lines.fold(0.0, (sum, line) {
      final clean = line.amountCtrl.text.replaceAll(r'$', '').replaceAll('.', '').replaceAll(' ', '').trim();
      return sum + (double.tryParse(clean) ?? 0.0);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_paymentType == 'specific' && _selectedSaleIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes seleccionar al menos un ticket'), backgroundColor: Colors.red),
      );
      return;
    }

    final List<Map<String, dynamic>> paymentsPayload = [];
    double totalPaid = 0.0;

    for (var line in _lines) {
      final cleanAmount = line.amountCtrl.text.replaceAll(r'$', '').replaceAll('.', '').replaceAll(' ', '').trim();
      final amount = double.tryParse(cleanAmount) ?? 0.0;
      if (amount <= 0) continue;

      Map<String, dynamic>? checkDetailsPayload;
      if (line.method == 'cheque') {
        if (line.checkBankCtrl.text.trim().isEmpty ||
            line.checkNumberCtrl.text.trim().isEmpty ||
            line.checkIssuerCuitCtrl.text.trim().isEmpty ||
            line.checkIssuerNameCtrl.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Complete los datos obligatorios de todos los cheques.'), backgroundColor: Colors.red),
          );
          return;
        }
        checkDetailsPayload = {
          'bank_name': line.checkBankCtrl.text.trim(),
          'check_number': line.checkNumberCtrl.text.trim(),
          'issuer_cuit': line.checkIssuerCuitCtrl.text.trim(),
          'issuer_name': line.checkIssuerNameCtrl.text.trim(),
          'issue_date': line.checkIssueDateCtrl.text.trim().isNotEmpty ? line.checkIssueDateCtrl.text.trim() : DateTime.now().toString().split(' ')[0],
          'payment_date': line.checkPaymentDateCtrl.text.trim().isNotEmpty ? line.checkPaymentDateCtrl.text.trim() : DateTime.now().toString().split(' ')[0],
        };
      }

      paymentsPayload.add({
        'method': line.method,
        'amount': amount,
        if (checkDetailsPayload != null) 'check_details': checkDetailsPayload,
      });
      totalPaid += amount;
    }

    if (totalPaid <= 0 || paymentsPayload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El monto total debe ser mayor a 0'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final success = await context.read<CustomerProvider>().registerPayment(
        customerId: widget.customer.id, 
        payments: paymentsPayload,
        description: _descriptionController.text.trim(),
        saleIds: _paymentType == 'specific' ? _selectedSaleIds : const [],
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
    final totalEntered = _totalEntered;
    final isSpecific = _paymentType == 'specific';

    return AlertDialog(
      title: Text('Registrar Pago - ${widget.customer.name}'),
      content: SizedBox(
        width: 600,
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
                    color: Colors.blueGrey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blueGrey.shade200)
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Deuda Total', style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            '\$ ${widget.customer.balance.toCurrency()}', 
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700)
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('Objetivo a Pagar', style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            '\$ ${_targetAmount.toCurrency()}', 
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.teal.shade700)
                          ),
                        ],
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
                        _calculateSelectedAmount();
                      } else {
                        _targetAmount = widget.customer.balance.abs();
                        if (_lines.length == 1) {
                           _lines[0].amountCtrl.text = _targetAmount > 0 ? _targetAmount.toStringAsFixed(2) : '';
                        }
                      }
                    });
                  },
                ),
                const SizedBox(height: 16),

                if (isSpecific) ...[
                  const Text('Tickets Pendientes', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    height: 180,
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

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Métodos de Pago', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar Método'),
                      onPressed: () => _addLine(),
                    )
                  ],
                ),
                const Divider(),
                
                ..._lines.asMap().entries.map((entry) {
                  final line = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<String>(
                                value: line.method,
                                decoration: InputDecoration(
                                  labelText: 'Método',
                                  isDense: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                items: [
                                  const DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                                  const DropdownMenuItem(value: 'card', child: Text('Tarjeta')),
                                  const DropdownMenuItem(value: 'transfer', child: Text('Transferencia')),
                                  if (settings?.features.checks == true)
                                    const DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                                ],
                                onChanged: (val) {
                                  if (val != null) setState(() => line.method = val);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: line.amountCtrl,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'Monto', 
                                  prefixText: '\$ ',
                                  isDense: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))
                                ),
                                validator: (val) => val == null || val.isEmpty ? 'Req.' : null,
                              ),
                            ),
                            if (_lines.length > 1)
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                onPressed: () => _removeLine(line),
                                tooltip: 'Eliminar',
                              )
                            else
                              const SizedBox(width: 48), // Padding para alinear
                          ],
                        ),
                        if (line.method == 'cheque')
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(top: 8),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Detalles del Cheque', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue)),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(child: TextField(controller: line.checkBankCtrl, decoration: InputDecoration(labelText: 'Banco', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: true, fillColor: Colors.white))),
                                    const SizedBox(width: 8),
                                    Expanded(child: TextField(controller: line.checkNumberCtrl, decoration: InputDecoration(labelText: 'Nro Cheque', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: true, fillColor: Colors.white))),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(child: TextField(controller: line.checkIssuerCuitCtrl, decoration: InputDecoration(labelText: 'CUIT Firmante', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: true, fillColor: Colors.white))),
                                    const SizedBox(width: 8),
                                    Expanded(child: TextField(controller: line.checkIssuerNameCtrl, decoration: InputDecoration(labelText: 'Nombre Firmante', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: true, fillColor: Colors.white))),
                                  ],
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                }),
                
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  margin: const EdgeInsets.only(top: 8, bottom: 16),
                  decoration: BoxDecoration(
                    color: totalEntered >= _targetAmount ? Colors.green.shade50 : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: totalEntered >= _targetAmount ? Colors.green.shade200 : Colors.orange.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Ingresado:', style: TextStyle(fontWeight: FontWeight.bold, color: totalEntered >= _targetAmount ? Colors.green.shade800 : Colors.orange.shade800)),
                      Text('\$ ${totalEntered.toCurrency()}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: totalEntered >= _targetAmount ? Colors.green.shade700 : Colors.orange.shade700)),
                    ],
                  ),
                ),

                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción / Nota (Opcional)', 
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
