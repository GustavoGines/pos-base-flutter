import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pos_provider.dart';
import '../../../cash_register/presentation/providers/cash_register_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../../core/utils/snack_bar_service.dart';

/// Diálogo de cobro reutilizable para:
///  - Ventas normales: [saleId] es null → llama a [posProvider.processCheckout]
///  - Pago de preventas: [saleId] es el ID de la venta → llama a [posProvider.payPendingSale]
class CheckoutDialog extends StatefulWidget {
  final double total;
  final int? saleId; // null = venta normal; non-null = cobro de preventa

  const CheckoutDialog({Key? key, required this.total, this.saleId}) : super(key: key);

  @override
  State<CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<CheckoutDialog> {
  String _paymentMethod = 'cash';
  final _amountCtrl = TextEditingController();
  final _focusNode = FocusNode();
  bool _printReceipt = true;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_onAmountChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_paymentMethod == 'cash') {
        _focusNode.requestFocus();
      }
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
    return true;
  }

  Future<void> _processCheckout() async {
    if (!_canSubmit) return;

    final posProvider = context.read<PosProvider>();
    final currentUser = context.read<AuthProvider>().currentUser;
    final userName = currentUser?['name'] as String?;
    final settings = context.read<SettingsProvider>().settings;

    final double finalTendered = _paymentMethod == 'cash' ? _tendered : widget.total;
    final double finalChange = _paymentMethod == 'cash' ? _change : 0.0;

    bool success;

    if (widget.saleId != null) {
      // ── Cobro de preventa ──────────────────────────────────────
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
      // ── Venta normal ───────────────────────────────────────────
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
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Título ────────────────────────────────────────────
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

              // ── Método de Pago ─────────────────────────────────────
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Método de Pago', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildMethodBtn('cash', 'Efectivo', Icons.payments_outlined),
                  const SizedBox(width: 12),
                  _buildMethodBtn('card', 'Tarjeta', Icons.credit_card),
                  const SizedBox(width: 12),
                  _buildMethodBtn('transfer', 'Transf.', Icons.qr_code_2),
                ],
              ),
              const SizedBox(height: 32),

              // ── Calculadora (Solo Efectivo) ────────────────────────
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
              ],

              const SizedBox(height: 16),

              // ── Eco-Friendly UX (Impresión Térmica) ────────────────
              CheckboxListTile(
                title: const Text('Imprimir Comprobante', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Desactive para ahorrar papel si el cliente no requiere copia física', style: TextStyle(fontSize: 12)),
                value: _printReceipt,
                activeColor: const Color(0xFF3B82F6),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _printReceipt = val);
                  }
                },
              ),

              const SizedBox(height: 24),

              // ── Botones de Acción ──────────────────────────────────
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

  Widget _buildMethodBtn(String value, String label, IconData icon) {
    final isSelected = _paymentMethod == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _paymentMethod = value;
            if (value != 'cash') {
              _amountCtrl.clear();
            } else {
              _focusNode.requestFocus();
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF3B82F6).withOpacity(0.1) : Colors.white,
            border: Border.all(
              color: isSelected ? const Color(0xFF3B82F6) : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? const Color(0xFF3B82F6) : Colors.black54, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF3B82F6) : Colors.black87,
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
