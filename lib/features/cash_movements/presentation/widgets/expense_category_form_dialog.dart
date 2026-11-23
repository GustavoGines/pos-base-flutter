import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import '../../providers/expense_category_provider.dart';
import '../../models/expense_category_model.dart';

class ExpenseCategoryFormDialog {
  static Future<ExpenseCategory?> show(
    BuildContext context, {
    int? id,
    String? initialName,
    bool initialIsActive = true,
  }) async {
    final nameCtrl = TextEditingController(text: initialName);
    bool isActive = initialIsActive;

    return showDialog<ExpenseCategory>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AppModalShell(
          title: id == null ? 'Nueva Categoría' : 'Editar Categoría',
          subtitle: 'Definí el nombre para clasificar movimientos de egresos',
          icon: Icons.label_outline,
          accent: AppModalAccent.slate,
          compact: true,
          maxWidth: 440,
          onClose: () => Navigator.pop(ctx),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre de la categoría'),
                autofocus: true,
                textCapitalization: TextCapitalization.words,
              ),
              if (id != null)
                SwitchListTile(
                  title: const Text('Activa'),
                  value: isActive,
                  onChanged: (val) => setState(() => isActive = val),
                ),
            ],
          ),
          footerActions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                
                final prov = ctx.read<ExpenseCategoryProvider>();
                try {
                  if (id == null) {
                    final newCat = await prov.createCategory(nameCtrl.text.trim());
                    if (ctx.mounted) Navigator.pop(ctx, newCat);
                  } else {
                    await prov.updateCategory(id, nameCtrl.text.trim(), isActive);
                    if (ctx.mounted) Navigator.pop(ctx);
                  }
                } catch (e) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.toString())));
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    ).whenComplete(() => nameCtrl.dispose());
  }
}
