import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_desktop/features/cash_movements/presentation/widgets/movement_form_dialog.dart';
import 'package:frontend_desktop/features/checks/domain/entities/third_party_check.dart';

// Test harness simulating the exact Patched Check Selector widget structure from REMEDIATION_REPORT.md
class PatchedCheckSelectorWidget extends StatefulWidget {
  final List<ThirdPartyCheck> initialWallet;
  final Function(List<PaymentItem>) onPaymentsChanged;

  const PatchedCheckSelectorWidget({
    super.key,
    required this.initialWallet,
    required this.onPaymentsChanged,
  });

  @override
  State<PatchedCheckSelectorWidget> createState() => _PatchedCheckSelectorWidgetState();
}

class _PatchedCheckSelectorWidgetState extends State<PatchedCheckSelectorWidget> {
  final List<PaymentItem> _payments = [];
  final TextEditingController _paymentAmountController = TextEditingController();
  int? _currentCheckId;
  final String _currentPaymentMethod = 'check';

  @override
  void dispose() {
    _paymentAmountController.dispose();
    super.dispose();
  }

  void _addPayment() {
    final amount = double.tryParse(_paymentAmountController.text) ?? 0;
    if (amount <= 0) return;

    ThirdPartyCheck? checkObj;
    if (_currentPaymentMethod == 'check') {
      if (_currentCheckId == null) return;

      // Layer 3 Guard: Reject duplicate check addition
      final isAlreadyAdded = _payments.any((p) => p.method == 'check' && p.checkId == _currentCheckId);
      if (isAlreadyAdded) return;

      checkObj = widget.initialWallet.firstWhere((c) => c.id == _currentCheckId);
    }

    final finalAmount = (_currentPaymentMethod == 'check' && checkObj != null)
        ? checkObj.amount
        : amount;

    setState(() {
      _payments.add(PaymentItem(
        method: _currentPaymentMethod,
        amount: finalAmount,
        checkId: _currentCheckId,
        checkObj: checkObj,
      ));
      _paymentAmountController.clear();
      _currentCheckId = null;
    });

    widget.onPaymentsChanged(_payments);
  }

  void _removePayment(int index) {
    setState(() {
      _payments.removeAt(index);
    });
    widget.onPaymentsChanged(_payments);
  }

  void submitForm() {
    // Auto-add guard (Layer 4)
    final pendingAmount = double.tryParse(_paymentAmountController.text) ?? 0;
    if (pendingAmount > 0) {
      if (_currentPaymentMethod == 'check') {
        if (_currentCheckId != null &&
            !_payments.any((p) => p.method == 'check' && p.checkId == _currentCheckId)) {
          _addPayment();
        }
      } else {
        _addPayment();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Layer 1: Reactive check subtraction
    final selectedCheckIds = _payments
        .where((p) => p.method == 'check' && p.checkId != null)
        .map((p) => p.checkId!)
        .toSet();

    final availableChecks = widget.initialWallet
        .where((c) => c.status == 'in_wallet' && !selectedCheckIds.contains(c.id))
        .toList();

    return Column(
      children: [
        // Display payment items
        for (int i = 0; i < _payments.length; i++)
          ListTile(
            key: ValueKey('payment_row_${_payments[i].checkId}'),
            title: Text('${_payments[i].method.toUpperCase()} - \$${_payments[i].amount}'),
            subtitle: Text('ID: ${_payments[i].checkId}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _removePayment(i),
            ),
          ),

        // Dropdown section
        if (_currentPaymentMethod == 'check') ...[
          availableChecks.isEmpty
              ? DropdownButtonFormField<int>(
                  key: const ValueKey('check_dropdown_empty'),
                  initialValue: null,
                  decoration: const InputDecoration(
                      labelText: 'Seleccionar Cheque en Cartera',
                      isDense: true),
                  items: const [
                    DropdownMenuItem(
                        value: null,
                        child: Text('No hay cheques disponibles'))
                  ],
                  onChanged: null,
                )
              : DropdownButtonFormField<int>(
                  key: ValueKey('check_dropdown_${selectedCheckIds.length}_$_currentCheckId'),
                  initialValue: availableChecks.any((c) => c.id == _currentCheckId)
                      ? _currentCheckId
                      : null,
                  decoration: const InputDecoration(
                      labelText: 'Seleccionar Cheque en Cartera',
                      isDense: true),
                  items: availableChecks
                      .map((c) => DropdownMenuItem<int>(
                            value: c.id,
                            child: Text('Nº ${c.checkNumber} (\$${c.amount}) - ${c.bankName}'),
                          ))
                      .toList(),
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

        ElevatedButton(
          key: const ValueKey('btn_agregar'),
          onPressed: _addPayment,
          child: const Text('Agregar'),
        ),
        ElevatedButton(
          key: const ValueKey('btn_submit'),
          onPressed: submitForm,
          child: const Text('Procesar Movimiento'),
        ),
      ],
    );
  }
}

void main() {
  testWidgets('Widget Stress: Selecting all wallet checks transitions dropdown to disabled without null assertion', (tester) async {
    final wallet = [
      ThirdPartyCheck(
        id: 101,
        bankName: 'Santander',
        checkNumber: '001',
        amount: 20000.0,
        issueDate: DateTime(2026, 9, 1),
        paymentDate: DateTime(2026, 9, 30),
        issuerName: 'Juan',
        issuerCuit: '20-11111111-1',
        status: 'in_wallet',
      ),
      ThirdPartyCheck(
        id: 102,
        bankName: 'Galicia',
        checkNumber: '002',
        amount: 30000.0,
        issueDate: DateTime(2026, 9, 1),
        paymentDate: DateTime(2026, 9, 30),
        issuerName: 'Pedro',
        issuerCuit: '20-22222222-2',
        status: 'in_wallet',
      ),
    ];

    List<PaymentItem> currentPayments = [];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PatchedCheckSelectorWidget(
            initialWallet: wallet,
            onPaymentsChanged: (p) => currentPayments = p,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Select Check 101
    final dropdownFinder = find.byType(DropdownButtonFormField<int>);
    expect(dropdownFinder, findsOneWidget);

    await tester.tap(dropdownFinder);
    await tester.pumpAndSettle();

    final item101 = find.textContaining('001').last;
    await tester.tap(item101);
    await tester.pumpAndSettle();

    // Tap Agregar
    await tester.tap(find.byKey(const ValueKey('btn_agregar')));
    await tester.pumpAndSettle();

    expect(currentPayments.length, 1);
    expect(currentPayments.first.checkId, 101);

    // 2. Select Check 102 (last remaining check)
    await tester.tap(dropdownFinder);
    await tester.pumpAndSettle();

    final item102 = find.textContaining('002').last;
    await tester.tap(item102);
    await tester.pumpAndSettle();

    // Tap Agregar
    await tester.tap(find.byKey(const ValueKey('btn_agregar')));
    await tester.pumpAndSettle();

    expect(currentPayments.length, 2);

    // 3. VERIFY DROPDOWN STATE AFTER EXHAUSTION:
    // It should now render "No hay cheques disponibles" without throwing any Flutter assertion error!
    expect(find.text('No hay cheques disponibles'), findsOneWidget);

    // 4. VERIFY RECOVERY UPON REMOVAL:
    // Click trash button on Check 101
    final deleteButtons = find.byIcon(Icons.delete);
    expect(deleteButtons, findsNWidgets(2));

    await tester.tap(deleteButtons.first);
    await tester.pumpAndSettle();

    // Now Check 101 is restored to availableChecks!
    expect(currentPayments.length, 1);
    expect(currentPayments.first.checkId, 102);
    expect(find.text('No hay cheques disponibles'), findsNothing);

    // Check 101 is selectable again
    await tester.tap(dropdownFinder);
    await tester.pumpAndSettle();
    expect(find.textContaining('001'), findsWidgets);
  });

  testWidgets('Widget Stress: Homogeneous checks with identical bank and amount render and select independently', (tester) async {
    final wallet = [
      ThirdPartyCheck(
        id: 201,
        bankName: 'Banco Macro',
        checkNumber: 'CHK-991',
        amount: 50000.0,
        issueDate: DateTime(2026, 9, 1),
        paymentDate: DateTime(2026, 9, 30),
        issuerName: 'Cliente A',
        issuerCuit: '20-11111111-1',
        status: 'in_wallet',
      ),
      ThirdPartyCheck(
        id: 202,
        bankName: 'Banco Macro', // Same bank
        checkNumber: 'CHK-992',
        amount: 50000.0, // Same amount
        issueDate: DateTime(2026, 9, 1),
        paymentDate: DateTime(2026, 9, 30),
        issuerName: 'Cliente B',
        issuerCuit: '20-22222222-2',
        status: 'in_wallet',
      ),
    ];

    List<PaymentItem> currentPayments = [];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PatchedCheckSelectorWidget(
            initialWallet: wallet,
            onPaymentsChanged: (p) => currentPayments = p,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Select Check 201
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('CHK-991').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('btn_agregar')));
    await tester.pumpAndSettle();

    expect(currentPayments.length, 1);
    expect(currentPayments.first.checkId, 201);

    // Now select Check 202 (which has the exact same bank and amount)
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('CHK-992').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('btn_agregar')));
    await tester.pumpAndSettle();

    // Both checks added cleanly
    expect(currentPayments.length, 2);
    expect(currentPayments[0].checkId, 201);
    expect(currentPayments[1].checkId, 202);
    expect(currentPayments[0].amount + currentPayments[1].amount, 100000.0);
  });

  testWidgets('Widget Stress: Auto-submit on uncommitted check commits it exactly once and avoids duplicate', (tester) async {
    final wallet = [
      ThirdPartyCheck(
        id: 301,
        bankName: 'Santander',
        checkNumber: 'CHK-301',
        amount: 40000.0,
        issueDate: DateTime(2026, 9, 1),
        paymentDate: DateTime(2026, 9, 30),
        issuerName: 'Cliente C',
        issuerCuit: '20-33333333-3',
        status: 'in_wallet',
      ),
    ];

    List<PaymentItem> currentPayments = [];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PatchedCheckSelectorWidget(
            initialWallet: wallet,
            onPaymentsChanged: (p) => currentPayments = p,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Operator selects Check 301 in dropdown
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('CHK-301').last);
    await tester.pumpAndSettle();

    // Operator DOES NOT tap "Agregar", but directly taps "Procesar Movimiento" (submit)
    await tester.tap(find.byKey(const ValueKey('btn_submit')));
    await tester.pumpAndSettle();

    expect(currentPayments.length, 1);
    expect(currentPayments.first.checkId, 301);

    // Operator taps "Procesar Movimiento" a second time
    await tester.tap(find.byKey(const ValueKey('btn_submit')));
    await tester.pumpAndSettle();

    // No duplicate added
    expect(currentPayments.length, 1);
  });
}
