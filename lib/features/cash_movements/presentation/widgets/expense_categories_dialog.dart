import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
import '../../providers/expense_category_provider.dart';
import 'expense_category_form_dialog.dart';

class ExpenseCategoriesDialog extends StatefulWidget {
  const ExpenseCategoriesDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => const ExpenseCategoriesDialog(),
    );
  }

  @override
  State<ExpenseCategoriesDialog> createState() => _ExpenseCategoriesDialogState();
}

class _ExpenseCategoriesDialogState extends State<ExpenseCategoriesDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ExpenseCategoryProvider>().fetchCategories();
    });
  }

  Future<void> _showFormDialog({int? id, String? initialName, bool initialIsActive = true}) async {
    await ExpenseCategoryFormDialog.show(
      context,
      id: id,
      initialName: initialName,
      initialIsActive: initialIsActive,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppModalShell(
      title: 'Categorías de Gastos',
      subtitle: 'Administrá las categorías de egresos de caja',
      icon: Icons.category_outlined,
      accent: AppModalAccent.slate,
      maxWidth: 520,
      maxHeight: 600,
      expandBody: true,
      headerTrailing: IconButton.filled(
        onPressed: () => _showFormDialog(),
        style: IconButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        icon: const Icon(Icons.add, size: 20),
        tooltip: 'Nueva Categoría',
      ),
      bodyPadding: EdgeInsets.zero,
      body: Consumer<ExpenseCategoryProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) return const Center(child: CircularProgressIndicator());
          
          if (provider.categories.isEmpty) {
            return const Center(child: Text('No hay categorías creadas.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: provider.categories.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final cat = provider.categories[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                title: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.bold)),
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
                        final confirm = await AppConfirmDialog.show(
                          context,
                          title: 'Confirmar',
                          message: '¿Eliminar esta categoría?',
                          confirmLabel: 'Eliminar',
                          cancelLabel: 'Cancelar',
                          icon: Icons.delete_outline,
                          isDestructive: true,
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
      footerActions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
