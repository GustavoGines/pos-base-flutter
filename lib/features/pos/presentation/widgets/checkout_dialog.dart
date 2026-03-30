import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pos_provider.dart';
import '../../../cash_register/presentation/providers/cash_register_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../customers/presentation/widgets/customer_form_dialog.dart';
import '../../../customers/providers/customer_provider.dart';
import '../../../customers/models/customer_model.dart';
import '../../../../core/utils/snack_bar_service.dart';

class CheckoutDialog extends StatefulWidget {
  final double total;
  final int? saleId;

  const CheckoutDialog({Key? key, required this.total, this.saleId}) : super(key: key);

  @override
  State<CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<CheckoutDialog> {
  String _paymentMethod = 'cash';
  final _amountCtrl = TextEditingController();
  final _focusNode = FocusNode();
  bool _printReceipt = true;

  // ── Cuenta Corriente ────────────────────────────────────────────
  Customer? _selectedCustomer;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_onAmountChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_paymentMethod == 'cash') _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _amountCtrl.removeListener(_onAmountChanged);
    _amountCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onAmountChanged() => setState(() {});

  double get _tendered {
    if (_amountCtrl.text.isEmpty) return 0.0;
    return double.tryParse(_amountCtrl.text) ?? 0.0;
  }

  double get _change => _tendered - widget.total;

  bool get _canSubmit {
    if (_paymentMethod == 'cash') return _tendered >= widget.total;
    if (_paymentMethod == 'cuenta_corriente') return _selectedCustomer != null;
    return true;
  }

  double get _availableCredit {
    if (_selectedCustomer == null) return 0;
    return (_selectedCustomer!.creditLimit) - (_selectedCustomer!.balance);
  }

  // ── Selector de cliente ─────────────────────────────────────────
  Future<void> _openCustomerPicker() async {
    final customerProvider = context.read<CustomerProvider>();
    // Asegurar que la lista esté cargada antes de abrir el picker
    if (customerProvider.customers.isEmpty && !customerProvider.isLoading) {
      try {
        await customerProvider.fetchCustomers();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No se pudo cargar la lista de clientes: ${e.toString().replaceAll("Exception: ", "")}'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return; // No abrir el dialog si falló la carga
      }
    }

    if (!mounted) return;

    await showDialog<Customer>(
      context: context,
      builder: (ctx) => _CustomerPickerDialog(
        onSelected: (c) {
          setState(() => _selectedCustomer = c);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Future<void> _processCheckout() async {
    // ── Validaciones de negocio para Cuenta Corriente ─────────────
    if (_paymentMethod == 'cuenta_corriente') {
      if (_selectedCustomer == null) {
        SnackBarService.error(context, 'Debe seleccionar un cliente para fiar.');
        return;
      }
      if (widget.total > _availableCredit) {
        SnackBarService.error(context,
          'El cliente no tiene límite de crédito suficiente. '
          'Disponible: \$${_availableCredit.toStringAsFixed(2)}');
        return;
      }
    }

    final isPending = widget.saleId != null;
    final posProvider = context.read<PosProvider>();
    final currentUser = context.read<AuthProvider>().currentUser;
    final userName = currentUser?['name'] as String?;
    final settings = context.read<SettingsProvider>().settings;

    final double finalTendered = _paymentMethod == 'cash' ? _tendered : widget.total;
    final double finalChange = _paymentMethod == 'cash' ? _change : 0.0;

    bool success;

    if (isPending) {
      success = await posProvider.payPendingSale(
        saleId: widget.saleId!,
        saleTotal: widget.total,
        paymentMethod: _paymentMethod,
        tenderedAmount: finalTendered,
        changeAmount: finalChange,
        userName: userName,
        settings: _printReceipt ? settings : null,
      );
    } else {
      final shiftId = context.read<CashRegisterProvider>().currentShift?.id;
      final userId = currentUser?['id'] as int?;

      if (shiftId == null) {
        SnackBarService.error(context, 'No hay turno de caja abierto');
        return;
      }

      success = await posProvider.processCheckout(
        shiftId: shiftId,
        paymentMethod: _paymentMethod,
        tenderedAmount: finalTendered,
        changeAmount: finalChange,
        userId: userId,
        customerId: _selectedCustomer?.id,
        userName: userName,
        settings: _printReceipt ? settings : null,
      );
    }

    if (mounted) {
      if (success) {
        if (posProvider.printerWarning != null) {
          SnackBarService.warning(context, posProvider.printerWarning!);
        }
        Navigator.of(context).pop(true);
      } else {
        SnackBarService.error(context, posProvider.errorMessage ?? 'Error al procesar el pago');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPending = widget.saleId != null;
    final settingsProvider = context.watch<SettingsProvider>();
    final canUseCuentaCorriente = settingsProvider.hasFeature('cuentas_corrientes');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Título ─────────────────────────────────────────────
              if (isPending) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.receipt_long_outlined, color: Colors.blue.shade700, size: 22),
                    const SizedBox(width: 8),
                    Text('Cobrar Orden #${widget.saleId}',
                        style: TextStyle(fontSize: 18, color: Colors.blue.shade700, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
              ] else
                const Text('Total a Pagar', style: TextStyle(fontSize: 18, color: Colors.black54)),
              const SizedBox(height: 8),
              Text(
                '\$${widget.total.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 32),

              // ── Método de Pago ──────────────────────────────────────
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Método de Pago', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildMethodBtn('cash', 'Efectivo', Icons.payments_outlined),
                  const SizedBox(width: 10),
                  _buildMethodBtn('card', 'Tarjeta', Icons.credit_card),
                  const SizedBox(width: 10),
                  _buildMethodBtn('transfer', 'Transf.', Icons.qr_code_2),
                  const SizedBox(width: 10),
                  _buildMethodBtn(
                    'cuenta_corriente', 'Cta. Cte.',
                    canUseCuentaCorriente ? Icons.account_balance_wallet_outlined : Icons.lock_outline,
                    isLocked: !canUseCuentaCorriente,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Selector de Cliente (solo Cuenta Corriente) ─────────
              if (_paymentMethod == 'cuenta_corriente') ...[
                GestureDetector(
                  onTap: _openCustomerPicker,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: _selectedCustomer != null
                          ? Colors.purple.shade50
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedCustomer != null
                            ? Colors.purple.shade300
                            : Colors.orange.shade400,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _selectedCustomer != null ? Icons.person : Icons.person_search_outlined,
                          color: _selectedCustomer != null ? Colors.purple.shade700 : Colors.orange.shade700,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _selectedCustomer == null
                              ? Text('Seleccionar Cliente',
                                  style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.bold))
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_selectedCustomer!.name,
                                        style: TextStyle(color: Colors.purple.shade700, fontWeight: FontWeight.bold)),
                                    Text(
                                      'Crédito disponible: \$${_availableCredit.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _availableCredit >= widget.total
                                            ? Colors.green.shade700
                                            : Colors.red.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        Icon(Icons.chevron_right, color: Colors.grey.shade500),
                      ],
                    ),
                  ),
                ),
                // Advertencia de crédito insuficiente
                if (_selectedCustomer != null && _availableCredit < widget.total)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red.shade700),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Crédito insuficiente. Disponible: \$${_availableCredit.toStringAsFixed(2)}',
                            style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
              ],

              // ── Calculadora (Solo Efectivo) ─────────────────────────
              if (_paymentMethod == 'cash') ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Abona con:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _amountCtrl,
                  focusNode: _focusNode,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    prefixStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black54),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _change >= 0 ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _change >= 0 ? Colors.green.shade200 : Colors.red.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Vuelto:', style: TextStyle(fontSize: 18, color: _change >= 0 ? Colors.green.shade700 : Colors.red.shade700)),
                      Text(
                        _change >= 0 ? '\$${_change.toStringAsFixed(2)}' : '-\$${_change.abs().toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _change >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Imprimir comprobante ────────────────────────────────
              CheckboxListTile(
                title: const Text('Imprimir Comprobante', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Desactive para ahorrar papel si el cliente no requiere copia física',
                    style: TextStyle(fontSize: 12)),
                value: _printReceipt,
                activeColor: const Color(0xFF3B82F6),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (val) {
                  if (val != null) setState(() => _printReceipt = val);
                },
              ),
              const SizedBox(height: 24),

              // ── Botones de Acción ───────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar', style: TextStyle(color: Colors.black54, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: Consumer<PosProvider>(
                      builder: (ctx, provider, _) {
                        return ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF22C55E),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            disabledBackgroundColor: Colors.grey.shade300,
                          ),
                          onPressed: (_canSubmit && !provider.isLoading) ? _processCheckout : null,
                          child: provider.isLoading
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Text(
                                  isPending ? 'CONFIRMAR COBRO' : 'CONFIRMAR PAGO',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMethodBtn(String value, String label, IconData icon, {bool isLocked = false}) {
    final isSelected = _paymentMethod == value;
    final Color iconColor = isLocked
        ? Colors.grey.shade400
        : (isSelected ? const Color(0xFF3B82F6) : Colors.black54);
    final Color labelColor = isLocked
        ? Colors.grey.shade400
        : (isSelected ? const Color(0xFF3B82F6) : Colors.black87);
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (isLocked) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.workspace_premium_rounded, color: Colors.amber, size: 18),
                    SizedBox(width: 8),
                    Text('Opción exclusiva para el Plan PRO'),
                  ],
                ),
                backgroundColor: Colors.blueGrey.shade900,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 3),
              ),
            );
            return;
          }
          setState(() {
            _paymentMethod = value;
            if (value != 'cash') _amountCtrl.clear();
            if (value != 'cuenta_corriente') _selectedCustomer = null;
            if (value == 'cash') _focusNode.requestFocus();
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isLocked
                ? Colors.grey.shade50
                : (isSelected ? const Color(0xFF3B82F6).withOpacity(0.1) : Colors.white),
            border: Border.all(
              color: isLocked
                  ? Colors.grey.shade200
                  : (isSelected ? const Color(0xFF3B82F6) : Colors.grey.shade300),
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, color: iconColor, size: 26),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: labelColor,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Diálogo picker de cliente ──────────────────────────────────────────────
class _CustomerPickerDialog extends StatefulWidget {
  final void Function(Customer) onSelected;

  const _CustomerPickerDialog({required this.onSelected});

  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Customer> _filter(List<Customer> all) {
    if (_query.isEmpty) return all;
    return all.where((c) =>
        c.name.toLowerCase().contains(_query) ||
        c.documentNumber.toLowerCase().contains(_query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 400,
        height: 480,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(Icons.person_search, color: Colors.purple.shade700),
                  const SizedBox(width: 10),
                  Text('Seleccionar Cliente',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.purple.shade700)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
            // Buscador
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o DNI...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Agregar Nuevo Cliente'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple.shade50,
                  foregroundColor: Colors.purple.shade700,
                  elevation: 0,
                  minimumSize: const Size(double.infinity, 45),
                ),
                onPressed: () {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const CustomerFormDialog(),
                  ).then((_) {
                    if (context.mounted) {
                      context.read<CustomerProvider>().fetchCustomers();
                    }
                  });
                },
              ),
            ),
            const SizedBox(height: 8),
            // Lista — Consumer para que se reconstruya cuando fetchCustomers() termina
            Expanded(
              child: Consumer<CustomerProvider>(
                builder: (_, provider, __) {
                  if (provider.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final filtered = _filter(provider.customers);
                  if (filtered.isEmpty) {
                    return const Center(
                      child: Text('Sin clientes encontrados', style: TextStyle(color: Colors.black45)),
                    );
                  }
                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = filtered[i];
                      final available = c.creditLimit - c.balance;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.purple.shade100,
                          child: Text(c.name[0].toUpperCase(),
                              style: TextStyle(color: Colors.purple.shade700, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('DNI: ${c.documentNumber} · Crédito: \$${available.toStringAsFixed(2)}'),
                        trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
                        onTap: () => widget.onSelected(c),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
