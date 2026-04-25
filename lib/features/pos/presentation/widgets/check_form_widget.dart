import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/utils/currency_formatter.dart';

/// Formulario de captura de datos de un cheque de tercero.
///
/// Se renderiza dinámicamente en el [CheckoutDialog] cuando el cajero
/// selecciona un método de pago cuyo [code] sea 'cheque'.
///
/// El [amount] se pre-carga desde el monto asignado a esa línea de pago y
/// es de solo lectura: el importe del cheque es siempre el que el cajero
/// ya ingresó en el desglose de pago.
class CheckFormWidget extends StatefulWidget {
  /// Monto pre-cargado desde la línea de pago (read-only).
  final double amount;

  /// Callback que se invoca cada vez que los datos del formulario cambian.
  /// Entrega un [Map] listo para incluir como [check_details] en el payload,
  /// o [null] si el formulario está incompleto/inválido.
  final ValueChanged<Map<String, dynamic>?> onChanged;

  const CheckFormWidget({
    Key? key,
    required this.amount,
    required this.onChanged,
  }) : super(key: key);

  @override
  State<CheckFormWidget> createState() => _CheckFormWidgetState();
}

class _CheckFormWidgetState extends State<CheckFormWidget> {
  final _bankCtrl        = TextEditingController();
  final _checkNumberCtrl = TextEditingController();
  final _cuitCtrl        = TextEditingController();
  final _issuerCtrl      = TextEditingController();
  final _issueDateCtrl   = TextEditingController();
  final _paymentDateCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Notificar al padre cada vez que cualquier campo cambie
    for (final ctrl in [
      _bankCtrl, _checkNumberCtrl, _cuitCtrl,
      _issuerCtrl, _issueDateCtrl, _paymentDateCtrl,
    ]) {
      ctrl.addListener(_notify);
    }
  }

  @override
  void dispose() {
    for (final ctrl in [
      _bankCtrl, _checkNumberCtrl, _cuitCtrl,
      _issuerCtrl, _issueDateCtrl, _paymentDateCtrl,
    ]) {
      ctrl.removeListener(_notify);
      ctrl.dispose();
    }
    super.dispose();
  }

  bool get _isValid =>
      _bankCtrl.text.trim().isNotEmpty &&
      _checkNumberCtrl.text.trim().isNotEmpty &&
      _cuitCtrl.text.trim().isNotEmpty &&
      _issuerCtrl.text.trim().isNotEmpty &&
      _isDateValid(_issueDateCtrl.text) &&
      _isDateValid(_paymentDateCtrl.text);

  bool _isDateValid(String v) {
    final parts = v.split('-');
    if (parts.length != 3) return false;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return false;
    return y > 2000 && m >= 1 && m <= 12 && d >= 1 && d <= 31;
  }

  void _notify() {
    widget.onChanged(_isValid
        ? {
            'bank_name':    _bankCtrl.text.trim(),
            'check_number': _checkNumberCtrl.text.trim(),
            'issuer_cuit':  _cuitCtrl.text.trim(),
            'issuer_name':  _issuerCtrl.text.trim(),
            'issue_date':   _issueDateCtrl.text.trim(),
            'payment_date': _paymentDateCtrl.text.trim(),
            // 'amount' lo toma el backend del total_amount del SalePayment
          }
        : null);
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
      locale: const Locale('es', 'AR'),
    );
    if (picked != null) {
      ctrl.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  InputDecoration _dec(String label, {IconData? icon}) => InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, size: 18, color: Colors.teal.shade600) : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.teal.shade500, width: 2),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Encabezado ─────────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.receipt_long, size: 18, color: Colors.teal.shade700),
              const SizedBox(width: 6),
              Text(
                'Datos del Cheque',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade800,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              // Importe (read-only, viene del desglose de pago)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.teal.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Importe: \$${widget.amount.toCurrency()}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.teal.shade900,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Fila 1: Banco + Nro ──────────────────────────────────
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _bankCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: _dec('Banco', icon: Icons.account_balance_outlined),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _checkNumberCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _dec('Nro. Cheque', icon: Icons.tag),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Fila 2: CUIT + Firmante ──────────────────────────────
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _cuitCtrl,
                  keyboardType: TextInputType.number,
                  decoration: _dec('CUIT Firmante', icon: Icons.fingerprint),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _issuerCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: _dec('Nombre Firmante', icon: Icons.person_outline),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Fila 3: Fecha Emisión + Fecha Cobro ──────────────────
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _pickDate(_issueDateCtrl),
                  child: AbsorbPointer(
                    child: TextField(
                      controller: _issueDateCtrl,
                      decoration: _dec('Fecha Emisión (AAAA-MM-DD)',
                          icon: Icons.calendar_today_outlined),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => _pickDate(_paymentDateCtrl),
                  child: AbsorbPointer(
                    child: TextField(
                      controller: _paymentDateCtrl,
                      decoration: _dec('Fecha de Cobro (AAAA-MM-DD)',
                          icon: Icons.event_available_outlined),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ── Indicador de validez ──────────────────────────────────
          if (!_isValid) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.teal.shade400),
                const SizedBox(width: 4),
                Text(
                  'Completá todos los campos para habilitar el cobro',
                  style: TextStyle(fontSize: 11, color: Colors.teal.shade600),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
