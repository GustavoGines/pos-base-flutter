import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/catalog_provider.dart';
import '../../domain/entities/category.dart';

/// Dialog de gestión ABM (Alta/Baja/Modificación) de Categorías.
///
/// Permite:
///  - Ver la lista de categorías actuales
///  - Crear nuevas categorías rápidamente
///  - Editar el nombre de una categoría (inline)
///  - Eliminar (con protección del backend si tiene productos)
class CategoriesManagerDialog extends StatefulWidget {
  const CategoriesManagerDialog({Key? key}) : super(key: key);

  @override
  State<CategoriesManagerDialog> createState() => _CategoriesManagerDialogState();
}

class _CategoriesManagerDialogState extends State<CategoriesManagerDialog> {
  final _newNameCtrl = TextEditingController();
  final _newFocusNode = FocusNode();
  bool _adding = false;

  // Para edición inline
  int? _editingId;
  final _editCtrl = TextEditingController();

  @override
  void dispose() {
    _newNameCtrl.dispose();
    _editCtrl.dispose();
    _newFocusNode.dispose();
    super.dispose();
  }

  Future<void> _createCategory(CatalogProvider provider) async {
    final name = _newNameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() => _adding = true);
    final ok = await provider.createCategory(name);
    if (!mounted) return;
    setState(() => _adding = false);

    if (ok) {
      _newNameCtrl.clear();
      _showSnack('Categoría "$name" creada', isError: false);
    } else {
      _showSnack(provider.errorMessage ?? 'Error al crear categoría', isError: true);
    }
  }

  Future<void> _saveEdit(CatalogProvider provider, int id) async {
    final name = _editCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _editingId = null);
      return;
    }
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
        backgroundColor: Colors.white,
        title: const Text('Confirmar eliminación', style: TextStyle(color: Colors.black87)),
        content: Text(
          '¿Eliminar la categoría "${cat.name}"?\n\nSi tiene productos asociados, la operación será rechazada.',
          style: const TextStyle(color: Colors.black54),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
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
      // Extraer mensaje limpio del error
      final raw = provider.errorMessage ?? 'Error al eliminar';
      final clean = raw.replaceFirst('Exception: ', '');
      _showSnack(clean, isError: true, duration: const Duration(seconds: 5));
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 480,
        height: 560,
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────
            _buildHeader(),
            // ── Add row ─────────────────────────────────────
            _buildAddRow(),
            Divider(color: Colors.grey.shade200, height: 1),
            // ── List ────────────────────────────────────────
            Expanded(child: _buildCategoryList()),
            // ── Footer ──────────────────────────────────────
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.label_outline, color: Color(0xFF3B82F6), size: 20),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gestión de Categorías',
                    style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
                Text('Crear, editar y eliminar categorías del catálogo',
                    style: TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.black54),
            onPressed: () => Navigator.of(context).pop(true), // true = hubo cambios, recargar
          ),
        ],
      ),
    );
  }

  Widget _buildAddRow() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _newNameCtrl,
              focusNode: _newFocusNode,
              style: const TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                hintText: 'Nombre de nueva categoría...',
                hintStyle: const TextStyle(color: Colors.black54),
                prefixIcon: const Icon(Icons.add, color: Color(0xFF3B82F6)),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF3B82F6)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onSubmitted: (_) {
                final provider = context.read<CatalogProvider>();
                _createCategory(provider);
              },
            ),
          ),
          const SizedBox(width: 10),
          Consumer<CatalogProvider>(
            builder: (ctx, provider, _) => ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: _adding
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check, size: 18),
              label: const Text('Agregar'),
              onPressed: _adding ? null : () => _createCategory(provider),
            ),
          ),
        ],
      ),
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.label_off_outlined, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                const Text('Sin categorías', style: TextStyle(color: Colors.black54)),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: cats.length,
          separatorBuilder: (_, __) => const SizedBox(height: 4),
          itemBuilder: (ctx, i) => _buildCategoryTile(provider, cats[i]),
        );
      },
    );
  }

  Widget _buildCategoryTile(CatalogProvider provider, Category cat) {
    final isEditing = _editingId == cat.id;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isEditing ? Colors.blue.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isEditing ? Colors.blue.shade300 : Colors.grey.shade200,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF3B82F6).withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(Icons.label, color: Color(0xFF3B82F6), size: 16),
        ),
        title: isEditing
            ? TextField(
                controller: _editCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.black87, fontSize: 14),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                ),
                onSubmitted: (_) => _saveEdit(provider, cat.id),
              )
            : Text(cat.name,
                style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: cat.description != null && cat.description!.isNotEmpty
            ? Text(cat.description!, style: const TextStyle(color: Colors.black54, fontSize: 12))
            : null,
        trailing: provider.isLoading && _editingId == cat.id
            ? const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isEditing) ...[
                    // Guardar
                    IconButton(
                      icon: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                      tooltip: 'Guardar',
                      onPressed: () => _saveEdit(provider, cat.id),
                    ),
                    // Cancelar
                    IconButton(
                      icon: const Icon(Icons.cancel, color: Colors.black54, size: 20),
                      tooltip: 'Cancelar',
                      onPressed: () => setState(() => _editingId = null),
                    ),
                  ] else ...[
                    // Editar
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: Color(0xFF3B82F6), size: 18),
                      tooltip: 'Editar',
                      onPressed: () {
                        setState(() {
                          _editingId = cat.id;
                          _editCtrl.text = cat.name;
                        });
                      },
                    ),
                    // Eliminar
                    IconButton(
                      icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 18),
                      tooltip: 'Eliminar',
                      onPressed: () => _deleteCategory(provider, cat),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Consumer<CatalogProvider>(
            builder: (_, p, __) => Text(
              '${p.categories.length} categoría${p.categories.length != 1 ? 's' : ''}',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}
