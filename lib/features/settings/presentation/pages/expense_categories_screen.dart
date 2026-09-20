import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../cash_movements/providers/expense_category_provider.dart';
import '../../../../core/presentation/widgets/global_app_bar.dart';

class ExpenseCategoriesScreen extends StatefulWidget {
  const ExpenseCategoriesScreen({super.key});

  @override
  State<ExpenseCategoriesScreen> createState() => _ExpenseCategoriesScreenState();
}

class _ExpenseCategoriesScreenState extends State<ExpenseCategoriesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ExpenseCategoryProvider>().fetchCategories();
    });
  }

  void _showFormDialog({int? id, String? initialName, bool initialIsActive = true}) {
    final nameCtrl = TextEditingController(text: initialName);
    bool isActive = initialIsActive;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(id == null ? 'Nueva Categoría' : 'Editar Categoría'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              if (id != null)
                SwitchListTile(
                  title: const Text('Activa'),
                  value: isActive,
                  onChanged: (val) => setState(() => isActive = val),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                
                final prov = context.read<ExpenseCategoryProvider>();
                try {
                  if (id == null) {
                    await prov.createCategory(nameCtrl.text.trim());
                  } else {
                    await prov.updateCategory(id, nameCtrl.text.trim(), isActive);
                  }
                  if (mounted) Navigator.pop(ctx);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlobalAppBar(title: 'Categorías de Gastos', currentRoute: '/settings/expense-categories', showBackButton: true),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormDialog(),
        child: const Icon(Icons.add),
      ),
      body: Consumer<ExpenseCategoryProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) return const Center(child: CircularProgressIndicator());
          
          if (provider.categories.isEmpty) {
            return const Center(child: Text('No hay categorías creadas.'));
          }

          return ListView.builder(
            itemCount: provider.categories.length,
            itemBuilder: (context, index) {
              final cat = provider.categories[index];
              return ListTile(
                title: Text(cat.name),
                subtitle: Text(cat.isActive ? 'Activa' : 'Inactiva', style: TextStyle(color: cat.isActive ? Colors.green : Colors.grey)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () => _showFormDialog(id: cat.id, initialName: cat.name, initialIsActive: cat.isActive),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Confirmar'),
                            content: const Text('¿Eliminar esta categoría?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                              FilledButton(onPressed: () => Navigator.pop(c, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Eliminar')),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          try {
                            await context.read<ExpenseCategoryProvider>().deleteCategory(cat.id);
                          } catch (e) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                          }
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
