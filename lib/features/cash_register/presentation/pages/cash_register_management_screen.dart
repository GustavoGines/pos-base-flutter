import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/presentation/widgets/global_app_bar.dart';
import '../../domain/entities/cash_register.dart';
import '../providers/cash_register_provider.dart';

class CashRegisterManagementScreen extends StatefulWidget {
  const CashRegisterManagementScreen({Key? key}) : super(key: key);

  @override
  _CashRegisterManagementScreenState createState() => _CashRegisterManagementScreenState();
}

class _CashRegisterManagementScreenState extends State<CashRegisterManagementScreen> {
  bool _isLoading = false;
  String _baseUrl = 'http://127.0.0.1:8000/api';

  @override
  void initState() {
    super.initState();
    _initUrl().then((_) => _fetchRegisters());
  }

  Future<void> _initUrl() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _baseUrl = prefs.getString('pos_api') ?? 'http://127.0.0.1:8000/api';
      });
    }
  }

  Future<void> _fetchRegisters() async {
    // We reuse the provider to keep state in sync
    await context.read<CashRegisterProvider>().loadRegisters();
  }

  Future<void> _showCreateEditModal({CashRegister? register}) async {
    final nameCtrl = TextEditingController(text: register?.name ?? '');
    
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(register == null ? 'Nueva Caja Física' : 'Editar Caja'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Nombre o Ubicación', prefixIcon: Icon(Icons.computer)),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(ctx);
                if (register == null) {
                  await _createRegister(name);
                } else {
                  await _updateRegister(register.id, name);
                }
              }
            },
            child: const Text('Guardar'),
          )
        ],
      ),
    );
  }

  Future<void> _createRegister(String name) async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/registers'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'name': name}),
      );
      if (response.statusCode == 201) {
        _fetchRegisters();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Caja creada')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${response.statusCode}')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateRegister(int id, String name) async {
    setState(() => _isLoading = true);
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/registers/$id'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'name': name}),
      );
      if (response.statusCode == 200) {
        _fetchRegisters();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Caja actualizada')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${response.statusCode} - no se puede editar Caja Principal')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteRegister(int id) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Caja'),
        content: const Text('¿Está seguro de eliminar esta caja física?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Eliminar')
          ),
        ],
      )
    );

    if (confirmar != true) return;

    setState(() => _isLoading = true);
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/registers/$id'),
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode == 200) {
        _fetchRegisters();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Caja eliminada')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${response.statusCode} - Caja principal protegida')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: const GlobalAppBar(
        currentRoute: '/settings/registers',
        title: 'Gestión de Cajas Físicas',
        showBackButton: true,
      ),
      body: Consumer<CashRegisterProvider>(
        builder: (ctx, provider, _) {
          final registers = provider.availableRegisters;
          
          if (_isLoading || provider.isLoading || registers == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Cabecera superior interactiva
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Tus Cajas Activas', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800)),
                            const SizedBox(height: 4),
                            Text('${registers.length} terminales enlazadas en esta red.', style: const TextStyle(color: Colors.grey)),
                          ],
                        ),
                        FilledButton.icon(
                          onPressed: () => _showCreateEditModal(),
                          icon: const Icon(Icons.add),
                          label: const Text('Nueva Caja'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.indigo.shade600,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // Tabla de Cajas Estilo Card
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                              border: const Border(bottom: BorderSide(color: Colors.black12)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.computer, color: Colors.blueGrey),
                                const SizedBox(width: 12),
                                Text('Terminales Registradas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800)),
                              ],
                            ),
                          ),
                          if (registers.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(32.0),
                              child: Center(child: Text('No hay cajas registradas (Verifique su licencia).', style: TextStyle(color: Colors.grey))),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: registers.length,
                              separatorBuilder: (ctx, i) => const Divider(height: 1),
                              itemBuilder: (ctx, i) {
                                final reg = registers[i];
                                final isPrincipal = reg.id == 1;

                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                                  child: ListTile(
                                    leading: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: isPrincipal ? Colors.green.shade50 : Colors.indigo.shade50,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        isPrincipal ? Icons.star : Icons.point_of_sale, 
                                        color: isPrincipal ? Colors.green.shade600 : Colors.indigo.shade600,
                                      ),
                                    ),
                                    title: Text(reg.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    subtitle: Text(
                                      isPrincipal ? 'Caja Principal (Obligatoria)' : 'ID de terminal: ${reg.id}',
                                      style: TextStyle(color: isPrincipal ? Colors.green.shade700 : Colors.black54),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent),
                                          tooltip: 'Editar',
                                          onPressed: () => _showCreateEditModal(register: reg),
                                        ),
                                        if (!isPrincipal)
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                            tooltip: 'Eliminar o Desactivar',
                                            onPressed: () => _deleteRegister(reg.id),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
