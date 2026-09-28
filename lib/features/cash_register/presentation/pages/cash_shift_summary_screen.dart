import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:flutter/material.dart';
import '../../domain/entities/cash_register_shift.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../providers/cash_register_provider.dart';
import '../../services/z_close_pdf_service.dart';
import 'package:frontend_desktop/core/presentation/widgets/print_format_selector.dart';
import 'package:intl/intl.dart';

class CashShiftSummaryScreen extends StatefulWidget {
  final CashRegisterShift closedShift;
  final bool isFromAudit;

  const CashShiftSummaryScreen({super.key, required this.closedShift, this.isFromAudit = false});

  @override
  State<CashShiftSummaryScreen> createState() => _CashShiftSummaryScreenState();
}

class _CashShiftSummaryScreenState extends State<CashShiftSummaryScreen> {
  final ScrollController _checkScrollController = ScrollController();

  @override
  void dispose() {
    _checkScrollController.dispose();
    super.dispose();
  }

  void _exit(BuildContext context) {
    if (widget.isFromAudit) {
      Navigator.of(context).pop();
      return;
    }
    try {
      context.read<AuthProvider>().logout();
    } catch (_) {}
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  void _printOnly(BuildContext context) async {
    final settingsProvider = context.read<SettingsProvider>();
    final isPremium = settingsProvider.currentPlan.toLowerCase() == 'premium' ||
        settingsProvider.currentPlan.toLowerCase() == 'pro';
    final settings = settingsProvider.settings;
    final printer = context.read<CashRegisterProvider>().printerService;
    
    if (settings != null && printer != null) {
      final localTerminal = context.read<LocalTerminalProvider>();
      
      final format = await PrintFormatSelector.show(context);
      if (format == null) return; // Canceló
      
      if (format == 'a4') {
        if (context.mounted) {
          await ZClosePdfService.printZClose(
            context: context,
            shift: widget.closedShift,
            businessName: settings.companyName ?? 'MI NEGOCIO',
            businessTaxId: settings.taxId,
            isPremium: isPremium,
          );
        }
      } else if (format == 'thermal') {
        await printer.printZCloseTicket(
          shift: widget.closedShift,
          settings: settings,
          localTerminal: localTerminal,
          isPremium: isPremium,
        ).catchError((e) {
          debugPrint('Error printing summary: $e');
        });
      }
    }
    // Si viene del flujo de cierre de caja (no auditoría), hacer logout
    if (!widget.isFromAudit && context.mounted) {
      _exit(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final closedShift = widget.closedShift;
    final isFromAudit = widget.isFromAudit;
    final settingsProvider = context.watch<SettingsProvider>();
    final isPremium = settingsProvider.currentPlan.toLowerCase() == 'premium' ||
        settingsProvider.currentPlan.toLowerCase() == 'pro';
    
    final diff = closedShift.difference ?? 0.0;
    final isNegative = diff < 0;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Resumen de Cierre de Caja'),
        centerTitle: true,
        automaticallyImplyLeading: isFromAudit, // Solo mostrar flecha atrás si viene de Auditoría
      ),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      children: const [
                        Icon(Icons.check_circle_outline, color: Colors.green, size: 28),
                        Text(
                          'Turno Cerrado Correctamente',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.spaceEvenly,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 20,
                        runSpacing: 4,
                        children: [
                          _buildSummaryChip(
                            icon: Icons.computer,
                            text: 'Caja: ${closedShift.cashRegisterName ?? "Principal"}',
                            iconColor: Colors.blue.shade700,
                            textColor: Colors.blue.shade900,
                          ),
                          _buildSummaryChip(
                            icon: Icons.person_outline,
                            text: 'Abrió: ${closedShift.userName ?? "Desconocido"}',
                            iconColor: Colors.blue.shade700,
                            textColor: Colors.blue.shade900,
                          ),
                          if (closedShift.closedByUserName != null)
                            _buildSummaryChip(
                              icon: Icons.lock_person,
                              text: 'Cerró: ${closedShift.closedByUserName}',
                              iconColor: Colors.orange.shade700,
                              textColor: Colors.orange.shade900,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isDesktop = constraints.maxWidth >= 650;

                        final leftColumn = Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _sectionHeader(Icons.account_balance, 'BALANCE DE CAJA'),
                              const SizedBox(height: 6),
                              _buildRow('Fondo Inicial', '\$${closedShift.openingBalance.toCurrency()}'),
                              if (isPremium || (closedShift.totalDeposits ?? 0) > 0)
                                _buildRow('Ingresos Extra', '\$${(closedShift.totalDeposits ?? 0).toCurrency()}'),
                              if (isPremium || (closedShift.totalExpenses ?? 0) > 0)
                                _buildRow('Gastos (Salida)', '-\$${(closedShift.totalExpenses ?? 0).toCurrency()}', isRed: true),
                              if (isPremium || (closedShift.totalWithdrawals ?? 0) > 0)
                                _buildRow('Retiros de Dueño (Salida)', '-\$${(closedShift.totalWithdrawals ?? 0).toCurrency()}', isRed: true),
                              if (isPremium || (closedShift.totalSupplierPayments ?? 0) > 0)
                                _buildRow('Pagos Proveedores (Salida)', '-\$${(closedShift.totalSupplierPayments ?? 0).toCurrency()}', isRed: true),
                              if ((closedShift.totalRefunds ?? 0) > 0)
                                _buildRow('Reintegros (Salida)', '-\$${(closedShift.totalRefunds ?? 0).toCurrency()}', isRed: true),
                              const Divider(height: 12),
                              _buildRow('Efectivo Esperado', '\$${(closedShift.expectedBalance ?? 0).toCurrency()}', bold: true),
                              _buildRow('Efectivo Físico', '\$${(closedShift.actualBalance ?? 0).toCurrency()}', bold: true),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isNegative ? Colors.red.shade50 : Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isNegative ? Colors.red.shade200 : Colors.green.shade200,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      isNegative ? 'FALTANTE:' : 'SOBRANTE:',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: isNegative ? Colors.red.shade700 : Colors.green.shade700,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          '\$${diff.abs().toCurrency()}',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: isNegative ? Colors.red.shade700 : Colors.green.shade700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );

                        final rightColumn = Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _sectionHeader(Icons.point_of_sale, 'DESGLOSE DE VENTAS'),
                              const SizedBox(height: 6),
                              _buildRow('Ventas en Efectivo', '\$${(closedShift.cashSales ?? 0).toCurrency()}'),
                              _buildRow('Ventas con Tarjeta', '\$${(closedShift.cardSales ?? 0).toCurrency()}'),
                              _buildRow('Ventas por Transf.', '\$${(closedShift.transferSales ?? 0).toCurrency()}'),
                              _buildRow('Total Recargos (Tarj/Billeteras)', '\$${(closedShift.totalSurcharge ?? 0).toCurrency()}'),

                              // Cuenta Corriente: sección informativa
                              if ((isPremium || (closedShift.ccSalesCount ?? 0) > 0) && (closedShift.ccSalesCount ?? 0) > 0) ...[
                                const Divider(height: 4),
                                _buildCcSection(closedShift),
                              ],

                              // Cheques: Solo visible si feature habilitada
                              if (isPremium && context.read<SettingsProvider>().settings?.features.checks == true) ...[
                                const Divider(height: 4),
                                _buildCheckSection(closedShift),
                              ],
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.print, size: 20),
                                label: Text(
                                  isFromAudit ? 'Reimprimir Cierre Z' : 'Imprimir Cierre Z y Salir',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  backgroundColor: Colors.blue.shade800,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () => _printOnly(context),
                              ),
                              const SizedBox(height: 2),
                              TextButton(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                ),
                                onPressed: () => _exit(context),
                                child: Text(
                                  isFromAudit ? 'Volver a Auditoría' : 'Continuar sin imprimir',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        );

                        if (isDesktop) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: leftColumn),
                              const SizedBox(width: 20),
                              Expanded(child: rightColumn),
                            ],
                          );
                        } else {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              leftColumn,
                              const SizedBox(height: 20),
                              rightColumn,
                            ],
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.blue.shade800),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade900,
              letterSpacing: 1.0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryChip({
    required IconData icon,
    required String text,
    required Color iconColor,
    required Color textColor,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 270),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: textColor, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool bold = false, bool isRed = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 14,
                  color: isRed ? Colors.red.shade700 : Colors.black87,
                  fontWeight: bold ? FontWeight.bold : FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                style: TextStyle(
                    fontSize: 14,
                    color: isRed ? Colors.red.shade900 : Colors.black,
                    fontWeight: bold ? FontWeight.w900 : FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCcSection(CashRegisterShift shift) {
    final count = shift.ccSalesCount ?? 0;
    final total = shift.ccSales ?? 0.0;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.purple.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.account_balance_wallet_outlined, color: Colors.purple.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cta. Cte. (deuda registrada)',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple.shade800, fontSize: 13)),
                Text('$count venta${count != 1 ? 's' : ''} — no ingresa al arqueo',
                    style: TextStyle(fontSize: 11, color: Colors.purple.shade500)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text('\$${total.toCurrency()}',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple.shade900, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckSection(CashRegisterShift shift) {
    final count = shift.checkCount ?? 0;
    final total = shift.checkSales ?? 0.0;
    final details = shift.checkDetails ?? [];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.indigo.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long, color: Colors.indigo.shade700, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Valores en Cheques',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade800,
                        fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text('\$${total.toCurrency()}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade900,
                          fontSize: 14)),
                ),
              ),
            ],
          ),
          Text('$count cheque${count != 1 ? 's' : ''} recibido${count != 1 ? 's' : ''}',
              style: TextStyle(fontSize: 11, color: Colors.indigo.shade600)),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Divider(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 75),
              child: Scrollbar(
                controller: _checkScrollController,
                thumbVisibility: details.length > 2,
                child: SingleChildScrollView(
                  controller: _checkScrollController,
                  child: Column(
                    children: details.map((c) {
                      final payDate = c['payment_date'] != null
                          ? DateFormat('dd/MM/yyyy').format(
                              DateTime.tryParse(c['payment_date'].toString()) ??
                                  DateTime.now())
                          : '-';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${c['bank_name'] ?? ''} #${c['check_number'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text('Cobro: $payDate',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.grey)),
                            const SizedBox(width: 6),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  '\$${double.tryParse(c['amount'].toString())?.toCurrency() ?? '-'}',
                                  style: const TextStyle(
                                      fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

