import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cash_register_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';

class CashRegisterScreen extends StatefulWidget {
  final Function(double, int?) onOpenShift;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onContinueToPos;

  const CashRegisterScreen({
    Key? key,
    required this.onOpenShift,
    required this.isLoading,
    this.errorMessage,
    required this.onContinueToPos,
  }) : super(key: key);

  @override
  _CashRegisterScreenState createState() => _CashRegisterScreenState();
}

class _CashRegisterScreenState extends State<CashRegisterScreen> {
  final _amountController = TextEditingController();
  int? _selectedRegisterId;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        context.read<CashRegisterProvider>().loadRegisters();
        // Pre-asignar la terminal local solo si el usuario la configuró explícitamente
        final assignedId = context.read<SettingsProvider>().assignedRegisterId;
        if (assignedId > 0) {
          setState(() {
            _selectedRegisterId = assignedId;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amountController.text);
    if (amount != null && amount >= 0) {
      widget.onOpenShift(amount, _selectedRegisterId);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingrese un monto inicial válido.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Apertura de Caja'),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.point_of_sale, size: 64, color: Colors.blue),
                  const SizedBox(height: 24),
                  const Text(
                    'Iniciar Turno de Caja',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ingrese el monto inicial (cambio) disponible en la caja física antes de comenzar a vender.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  
                  // -- SELECTOR DINÁMICO DE CAJA --
                  Consumer2<CashRegisterProvider, SettingsProvider>(
                    builder: (ctx, cashProv, settingsProv, _) {
                      final registers = cashProv.availableRegisters;
                      final assignedId = settingsProv.assignedRegisterId;

                      if (registers == null) {
                        return const Padding(
                          padding: EdgeInsets.only(bottom: 24),
                          child: CircularProgressIndicator(),
                        );
                      }

                      // Buscar la caja asignada a esta terminal
                      // Solo bloquea si el usuario CONFIGURÓ explícitamente una terminal (id > 0)
                      final assignedRegister = assignedId > 0
                          ? registers.cast().firstWhere(
                              (r) => r.id == assignedId,
                              orElse: () => null,
                            )
                          : null;

                      if (assignedRegister != null) {
                        // Terminal asignada: bloquear selector y mostrar banner informativo
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_selectedRegisterId != assignedRegister.id) {
                            setState(() => _selectedRegisterId = assignedRegister.id);
                          }
                        });
                        return Container(
                          margin: const EdgeInsets.only(bottom: 24),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.indigo.shade200),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.desktop_windows, color: Colors.indigo.shade700),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '💻 Terminal Asignada',
                                    style: TextStyle(fontSize: 12, color: Colors.indigo.shade400),
                                  ),
                                  Text(
                                    assignedRegister.name,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo.shade900,
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Icon(Icons.lock, size: 16, color: Colors.indigo.shade300),
                            ],
                          ),
                        );
                      }

                      // Fallback: Dropdown libre (no debería llegar aquí si assignedId está bien configurado)
                      if (_selectedRegisterId == null && registers.isNotEmpty) {
                        _selectedRegisterId = registers.first.id;
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: DropdownButtonFormField<int>(
                          value: _selectedRegisterId,
                          decoration: const InputDecoration(
                            labelText: 'Caja Física',
                            prefixIcon: Icon(Icons.computer),
                            border: OutlineInputBorder(),
                          ),
                          items: registers.map((reg) {
                            return DropdownMenuItem<int>(
                              value: reg.id,
                              child: Text(reg.name),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedRegisterId = val;
                            });
                          },
                        ),
                      );
                    },
                  ),
                  
                  TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'Monto Inicial (Efectivo)',
                      prefixIcon: Icon(Icons.attach_money),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (widget.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        widget.errorMessage ?? '',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: widget.isLoading ? null : _submit,
                      child: widget.isLoading
                          ? const CircularProgressIndicator()
                          : const Text('Abrir Caja y Continuar'),
                    ),
                  ),

                  // ── Bypass Admin ──────────────────────────────────────
                  Consumer<AuthProvider>(
                    builder: (ctx, authProv, _) {
                      final role = authProv.currentUser?['role'] as String? ?? '';
                      if (role != 'admin') return const SizedBox.shrink();
                      return Column(
                        children: [
                          const SizedBox(height: 20),
                          const Divider(),
                          const SizedBox(height: 8),
                          Text(
                            'Solo Administradores',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500, letterSpacing: 0.5),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: widget.onContinueToPos,
                            icon: Icon(Icons.admin_panel_settings, size: 18, color: Colors.blueGrey.shade600),
                            label: Text(
                              'Entrar sin abrir turno →',
                              style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 13),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
