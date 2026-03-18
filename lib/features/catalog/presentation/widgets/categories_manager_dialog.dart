import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/catalog_provider.dart';
import '../../domain/entities/category.dart';

/// Dialog de gestión ABM de Categorías.
/// Estilo consistente con ProductFormDialog y BulkPriceUpdateDialog del sistema.
class CategoriesManagerDialog extends StatefulWidget {
  const CategoriesManagerDialog({Key? key}) : super(key: key);

  @override
  State<CategoriesManagerDialog> createState() => _CategoriesManagerDialogState();
}

class _CategoriesManagerDialogState extends State<CategoriesManagerDialog> {
  final _newNameCtrl  = TextEditingController();
  final _newFocusNode = FocusNode();
  bool _adding = false;

  int? _editingId;
  final _editCtrl = TextEditingController();

  @override
  void dispose() {
    _newNameCtrl.dispose();
    _editCtrl.dispose();
    _newFocusNode.dispose();
    super.dispose();
  }

  // ── Acciones ────────────────────────────────────────────────────

  Future<void> _createCategory(CatalogProvider provider) async {
    final name = _newNameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _adding = true);
    final ok = await provider.createCategory(name);
    if (!mounted) return;
    setState(() => _adding = false);
    if (ok) {
      _newNameCtrl.clear();
      _newFocusNode.requestFocus();
      _showSnack('Categoría "$name" creada', isError: false);
    } else {
      _showSnack(provider.errorMessage ?? 'Error al crear categoría', isError: true);
    }
  }

  Future<void> _saveEdit(CatalogProvider provider, int id) async {
    final name = _editCtrl.text.trim();
    if (name.isEmpty) { setState(() => _editingId = null); return; }
    final ok = await provider.updateCategory(id, name);
    if (!mounted) return;
    if (ok) {
      _showSnack('Categoría actualizada', isError: false);
    } else {
      _showSnack(provider.errorMessage ?? 'Error al actualizar', isError: true);
    }
    setState(() => _editingId = null);
  }

  Future<void> _deleteCategory(CatalogProvider provider, Category cat) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text(
          '¿Eliminar la categoría "${cat.name}"?\n\nSi tiene productos asociados, la operación será rechazada.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final ok = await provider.deleteCategory(cat.id);
    if (!mounted) return;
    if (ok) {
      _showSnack('Categoría "${cat.name}" eliminada', isError: false);
    } else {
      final raw = provider.errorMessage ?? 'Error al eliminar';
      _showSnack(raw.replaceFirst('Exception: ', ''), isError: true, duration: const Duration(seconds: 5));
    }
  }

  void _showSnack(String msg, {required bool isError, Duration? duration}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade700 : const Color(0xFF1E7E34),
      behavior: SnackBarBehavior.floating,
      duration: duration ?? const Duration(seconds: 3),
    ));
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.label_rounded, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          const Text('Gestión de Categorías'),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            // ── Fila agregar ──────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newNameCtrl,
                    focusNode: _newFocusNode,
                    decoration: InputDecoration(
                      hintText: 'Nombre de nueva categoría...',
                      prefixIcon: Icon(Icons.add, color: Theme.of(context).colorScheme.primary),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onSubmitted: (_) => _createCategory(context.read<CatalogProvider>()),
                  ),
                ),
                const SizedBox(width: 10),
                Consumer<CatalogProvider>(
                  builder: (ctx, provider, _) => FilledButton.icon(
                    icon: _adding
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check, size: 18),
                    label: Text(_adding ? 'Guardando...' : 'Agregar'),
                    onPressed: _adding ? null : () => _createCategory(provider),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(color: Colors.grey.shade200, height: 1),

            // ── Lista de categorías ───────────────────────────
            Expanded(child: _buildCategoryList()),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      actions: [
        Row(
          children: [
            Consumer<CatalogProvider>(
              builder: (_, p, __) => Text(
                '${p.categories.length} categoría${p.categories.length != 1 ? 's' : ''}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoryList() {
    return Consumer<CatalogProvider>(
      builder: (ctx, provider, _) {
        final cats = provider.categories;
        if (provider.isLoading && cats.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (cats.isEmpty) {
          return Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.label_off_outlined, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              const Text('Sin categorías creadas', style: TextStyle(color: Colors.black45)),
            ]),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: cats.length,
          separatorBuilder: (_, __) => Divider(color: Colors.grey.shade100, height: 1),
          itemBuilder: (ctx, i) => _buildCategoryTile(provider, cats[i]),
        );
      },
    );
  }

  Widget _buildCategoryTile(CatalogProvider provider, Category cat) {
    final isEditing = _editingId == cat.id;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        child: Icon(Icons.label_rounded,
            color: Theme.of(context).colorScheme.primary, size: 16),
      ),
      title: isEditing
          ? TextField(
              controller: _editCtrl,
              autofocus: true,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (_) => _saveEdit(provider, cat.id),
            )
          : Text(cat.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: (!isEditing && cat.description != null && cat.description!.isNotEmpty)
          ? Text(cat.description!,
              style: const TextStyle(fontSize: 12, color: Colors.black45))
          : null,
      trailing: provider.isLoading && _editingId == cat.id
          ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: isEditing
                  ? [
                      IconButton(
                        icon: const Icon(Icons.check_rounded, color: Colors.green, size: 20),
                        tooltip: 'Guardar',
                        onPressed: () => _saveEdit(provider, cat.id),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: Colors.grey.shade500, size: 20),
                        tooltip: 'Cancelar',
                        onPressed: () => setState(() => _editingId = null),
                      ),
                    ]
                  : [
                      IconButton(
                        icon: Icon(Icons.edit_outlined,
                            color: Theme.of(context).colorScheme.primary, size: 18),
                        tooltip: 'Editar',
                        onPressed: () => setState(() {
                          _editingId = cat.id;
                          _editCtrl.text = cat.name;
                        }),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline,
                            color: Colors.red.shade400, size: 18),
                        tooltip: 'Eliminar',
                        onPressed: () => _deleteCategory(provider, cat),
                      ),
                    ],
            ),
    );
  }
}
