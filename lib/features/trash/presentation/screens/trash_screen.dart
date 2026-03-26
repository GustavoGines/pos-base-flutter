import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/presentation/widgets/global_app_bar.dart';
import '../../providers/trash_provider.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TrashProvider>().fetchTrash('customers');
    });
  }

  void _confirmAction(bool isRestore, TrashItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(isRestore ? Icons.restore : Icons.delete_forever, 
                 color: isRestore ? Colors.green : Colors.red),
            const SizedBox(width: 8),
            Text(isRestore ? 'Restaurar Elemento' : 'Eliminar Permanentemente'),
          ],
        ),
        content: Text(isRestore 
          ? '¿Deseas restaurar "${item.title}"? Volverá a estar disponible en el sistema.' 
          : '¿Estás seguro de ELIMINAR PERMANENTEMENTE "${item.title}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: isRestore ? Colors.green.shade600 : Colors.red.shade700
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final provider = context.read<TrashProvider>();
              final success = isRestore 
                  ? await provider.restoreItem(item.id)
                  : await provider.forceDeleteItem(item.id);
                  
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? 'Acción completada exitosamente' : 'Error al procesar la solicitud'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  )
                );
              }
            },
            child: Text(isRestore ? 'Restaurar' : 'Eliminar'),
          ),
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlobalAppBar(
        currentRoute: '/trash',
        title: 'Papelera de Reciclaje',
        showBackButton: true,
      ),
      body: Consumer<TrashProvider>(
        builder: (context, provider, _) {
          return Row(
            children: [
              // Panel Izquierdo
              Container(
                width: 280,
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      color: Colors.blueGrey.shade50,
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.delete_outline, size: 48, color: Colors.blueGrey),
                          SizedBox(height: 16),
                          Text('Papelera', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                          Text('Elementos eliminados del sistema.', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                    _buildNavTile(provider, 'Clientes', 'customers', Icons.people_outline),
                    _buildNavTile(provider, 'Productos', 'products', Icons.inventory_2_outlined),
                  ],
                ),
              ),
              
              // Panel Derecho
              Expanded(
                child: Container(
                  color: Colors.grey.shade50,
                  child: provider.isLoading 
                    ? const Center(child: CircularProgressIndicator())
                    : provider.items.isEmpty 
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_delete_outlined, size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              Text('La papelera está vacía', style: TextStyle(color: Colors.grey.shade500, fontSize: 18)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(32),
                          itemCount: provider.items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = provider.items[index];
                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.grey.shade200)
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                leading: CircleAvatar(
                                  backgroundColor: Colors.red.shade50,
                                  child: Icon(
                                    provider.currentType == 'customers' ? Icons.person : Icons.inventory_2, 
                                    color: Colors.red.shade300
                                  )
                                ),
                                title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('${item.subtitle} • Eliminado el: ${item.deletedAt.day}/${item.deletedAt.month}/${item.deletedAt.year}', style: TextStyle(color: Colors.grey.shade600)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton.icon(
                                      icon: const Icon(Icons.restore, color: Colors.green),
                                      label: const Text('Restaurar', style: TextStyle(color: Colors.green)),
                                      onPressed: () => _confirmAction(true, item),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                                      label: const Text('Destruir', style: TextStyle(color: Colors.red)),
                                      onPressed: () => _confirmAction(false, item),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        )
                ),
              ),
            ],
          );
        }
      ),
    );
  }

  Widget _buildNavTile(TrashProvider provider, String title, String type, IconData icon) {
    final isActive = provider.currentType == type;
    return ListTile(
      selected: isActive,
      selectedTileColor: Colors.blue.shade50,
      leading: Icon(icon, color: isActive ? Colors.blue.shade700 : Colors.blueGrey),
      title: Text(title, style: TextStyle(
        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        color: isActive ? Colors.blue.shade900 : Colors.blueGrey.shade700
      )),
      onTap: () {
        if (!isActive) provider.fetchTrash(type);
      },
    );
  }
}
