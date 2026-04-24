import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/check_provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:intl/intl.dart';

class CheckWalletScreen extends StatefulWidget {
  const CheckWalletScreen({super.key});

  @override
  State<CheckWalletScreen> createState() => _CheckWalletScreenState();
}

class _CheckWalletScreenState extends State<CheckWalletScreen> {
  String _activeFilter = 'activos'; // activos, salientes, conflictos
  String _searchQuery = '';
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CheckProvider>().loadChecks();
    });
  }

  void _updateStatus(int checkId, String status, {String? note}) {
    context.read<CheckProvider>().updateCheckStatus(checkId, status, endorsementNote: note).then((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Estado actualizado a ${_translateStatus(status)}')));
      }
    });
  }

  void _confirmAction(BuildContext context, int checkId, String actionLabel, String status, {Color confirmColor = Colors.blue}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(status == 'rejected' ? 'Rechazar Cheque' : 'Depositar Cheque'),
        content: Text(status == 'rejected' 
          ? '¿Marcar este cheque como RECHAZADO? Esta acción lo moverá a la pestaña de Conflictos.' 
          : '¿Confirmar $actionLabel de este cheque?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _updateStatus(checkId, status);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  void _showEndorseDialog(int checkId) {
    final TextEditingController noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final isButtonEnabled = noteController.text.trim().length >= 3;
          return AlertDialog(
            title: const Text('Endosar Cheque'),
            content: TextField(
              controller: noteController,
              onChanged: (val) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Entregado a (Nombre/Nota)',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
                onPressed: isButtonEnabled
                    ? () {
                        Navigator.pop(ctx);
                        _updateStatus(checkId, 'endorsed', note: noteController.text.trim());
                      }
                    : null,
                child: const Text('Endosar'),
              ),
            ],
          );
        }
      ),
    );
  }

  String _translateStatus(String status) {
    switch (status) {
      case 'in_wallet': return 'En Cartera';
      case 'deposited': return 'Depositado';
      case 'endorsed': return 'Endosado';
      case 'rejected': return 'Rechazado';
      default: return status;
    }
  }

  Widget _buildStatusBadge(String status, String? note) {
    Color bgColor;
    Color textColor;
    switch (status) {
      case 'in_wallet':
        bgColor = Colors.green.shade50;
        textColor = Colors.green.shade800;
        break;
      case 'deposited':
      case 'endorsed':
        bgColor = Colors.grey.shade100;
        textColor = Colors.grey.shade800;
        break;
      case 'rejected':
        bgColor = Colors.red.shade50;
        textColor = Colors.red.shade800;
        break;
      default:
        bgColor = Colors.blue.shade50;
        textColor = Colors.blue.shade800;
    }

    return SizedBox(
      width: 120,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
            child: Text(_translateStatus(status), style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 11)),
          ),
          if (status == 'endorsed' && note != null && note.isNotEmpty)
            Tooltip(
              message: 'A: $note',
              child: Padding(
                padding: const EdgeInsets.only(top: 2, left: 4),
                child: Text(
                  'A: $note',
                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_balance_wallet_outlined, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No se encontraron cheques. ¡Comenzá a recibir pagos desde el Checkout!',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CheckProvider>();
    final inWalletChecks = provider.checks.where((c) => c.status == 'in_wallet').toList();
    final totalInWallet = inWalletChecks.fold(0.0, (sum, c) => sum + c.amount);

    return Scaffold(
      appBar: const GlobalAppBar(
        currentRoute: '/checks',
        title: 'Cartera de Cheques',
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : provider.error != null
              ? Center(child: Text('Error: ${provider.error}'))
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1600),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      // KPIs
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.account_balance_wallet, color: Colors.green.shade700, size: 32),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Total en Cartera', style: TextStyle(fontSize: 16, color: Colors.black54)),
                                  Text(
                                    '\$${totalInWallet.toCurrency()}',
                                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          FilterChip(
                            label: const Text('Activos (En Cartera)'),
                            selected: _activeFilter == 'activos',
                            onSelected: (val) => setState(() => _activeFilter = 'activos'),
                            selectedColor: Colors.blue.shade100,
                          ),
                          const SizedBox(width: 12),
                          FilterChip(
                            label: const Text('Salientes (Depositados/Endosados)'),
                            selected: _activeFilter == 'salientes',
                            onSelected: (val) => setState(() => _activeFilter = 'salientes'),
                            selectedColor: Colors.green.shade100,
                          ),
                          const SizedBox(width: 12),
                          FilterChip(
                            label: const Text('Conflictos (Rechazados)'),
                            selected: _activeFilter == 'conflictos',
                            onSelected: (val) => setState(() => _activeFilter = 'conflictos'),
                            selectedColor: Colors.red.shade100,
                          ),
                          const Spacer(),
                          Container(
                            constraints: const BoxConstraints(maxWidth: 350),
                            child: TextField(
                              decoration: InputDecoration(
                                hintText: 'Nro, Firmante o Banco...',
                                prefixIcon: const Icon(Icons.search, size: 20),
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Data Table
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final filteredChecks = provider.checks.where((c) {
                              if (_activeFilter == 'activos' && c.status != 'in_wallet') return false;
                              if (_activeFilter == 'salientes' && c.status != 'deposited' && c.status != 'endorsed') return false;
                              if (_activeFilter == 'conflictos' && c.status != 'rejected') return false;
                              
                              if (_searchQuery.isNotEmpty) {
                                if (!c.checkNumber.toLowerCase().contains(_searchQuery) &&
                                    !c.bankName.toLowerCase().contains(_searchQuery) &&
                                    !c.issuerName.toLowerCase().contains(_searchQuery)) {
                                  return false;
                                }
                              }
                              return true;
                            }).toList();

                            if (filteredChecks.isEmpty) {
                              return _buildEmptyState();
                            }

                            return Card(
                              elevation: 1,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  return SingleChildScrollView(
                                    scrollDirection: Axis.vertical,
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(minWidth: constraints.maxWidth),
                                        child: DataTable(
                                          columns: const [
                                            DataColumn(label: Text('Banco', style: TextStyle(fontWeight: FontWeight.bold))),
                                            DataColumn(label: Text('Nro Cheque', style: TextStyle(fontWeight: FontWeight.bold))),
                                            DataColumn(label: Text('Firmante', style: TextStyle(fontWeight: FontWeight.bold))),
                                            DataColumn(label: Text('Entregado Por', style: TextStyle(fontWeight: FontWeight.bold))),
                                            DataColumn(label: Text('Emisión', style: TextStyle(fontWeight: FontWeight.bold))),
                                            DataColumn(label: Text('Cobro', style: TextStyle(fontWeight: FontWeight.bold))),
                                            DataColumn(label: SizedBox(width: 100, child: Text('Importe', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold))), numeric: true),
                                            DataColumn(label: SizedBox(width: 120, child: Text('Estado', style: TextStyle(fontWeight: FontWeight.bold)))),
                                            DataColumn(label: SizedBox(width: 140, child: Text('Acciones', style: TextStyle(fontWeight: FontWeight.bold)))),
                                          ],
                                          rows: filteredChecks.map((c) {
                                  // Consider ready to deposit if today >= paymentDate
                                  final isReadyToDeposit = c.status == 'in_wallet' && c.paymentDate.isBefore(DateTime.now().add(const Duration(days: 1)));
                                  
                                  Color dateColor;
                                  FontWeight dateWeight;
                                  if (c.status == 'rejected') {
                                    dateColor = Colors.red.shade800;
                                    dateWeight = FontWeight.bold;
                                  } else if (isReadyToDeposit) {
                                    dateColor = Colors.green.shade800;
                                    dateWeight = FontWeight.bold;
                                  } else {
                                    dateColor = Colors.grey.shade800;
                                    dateWeight = FontWeight.normal;
                                  }
                                  
                                  return DataRow(
                                    cells: [
                                      DataCell(Text(c.bankName)),
                                      DataCell(Text(c.checkNumber)),
                                      DataCell(Text(c.issuerName)),
                                      DataCell(Text(c.customerName ?? 'Consumidor Final')),
                                      DataCell(Text(DateFormat('dd/MM/yyyy').format(c.issueDate))),
                                      DataCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: dateColor.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            DateFormat('dd/MM/yyyy').format(c.paymentDate),
                                            style: TextStyle(
                                              color: dateColor,
                                              fontWeight: dateWeight,
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16),
                                          child: Text('\$${c.amount.toCurrency()}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                        ),
                                      ),
                                      DataCell(SizedBox(width: 120, child: _buildStatusBadge(c.status, c.endorsementNote))),
                                      DataCell(
                                        SizedBox(
                                          width: 140,
                                          child: c.status == 'in_wallet' 
                                              ? Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      tooltip: 'Depositar',
                                                      icon: const Icon(Icons.account_balance, color: Colors.green, size: 24),
                                                      onPressed: () => _confirmAction(context, c.id, 'depósito', 'deposited', confirmColor: Colors.green.shade700),
                                                    ),
                                                    IconButton(
                                                      tooltip: 'Endosar',
                                                      icon: const Icon(Icons.handshake, color: Colors.purple, size: 24),
                                                      onPressed: () => _showEndorseDialog(c.id),
                                                    ),
                                                    IconButton(
                                                      tooltip: 'Rechazar',
                                                      icon: const Icon(Icons.cancel, color: Colors.red, size: 24),
                                                      onPressed: () => _confirmAction(context, c.id, 'rechazo', 'rejected', confirmColor: Colors.red.shade700),
                                                    ),
                                                  ],
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);
}
}
