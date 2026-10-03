import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/catalog_provider.dart';
import '../../domain/entities/category.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';

/// Dialog de gestión ABM de Categorías.
/// Soporta asignación de Rubro padre en Plan Premium, y oculta el selector en Plan Básico.
class CategoriesManagerDialog extends StatefulWidget {
  const CategoriesManagerDialog({super.key});

  @override
  State<CategoriesManagerDialog> createState() => _CategoriesManagerDialogState();
}

class _CategoriesManagerDialogState extends State<CategoriesManagerDialog> {
  final _newNameCtrl = TextEditingController();
  final _newFocusNode = FocusNode();
  bool _adding = false;
  int? _newRubroId;

  int? _editingId;
  final _editCtrl = TextEditingController();
  int? _editRubroId;

  /// ID de la última categoría creada en esta sesión del dialog.
  int? _lastCreatedId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CatalogProvider>().loadRubros();
    });
  }

  @override
  void dispose() {
    _newNameCtrl.dispose();
    _editCtrl.dispose();
    _newFocusNode.dispose();
    super.dispose();
  }

  // ── Acciones ────────────────────────────────────────────────────

  Future<void> _createCategory(CatalogProvider provider, bool isPremium) async {
    final name = _newNameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _adding = true);
    final ok = await provider.createCategory(
      name,
      rubroId: isPremium ? _newRubroId : null,
    );
    if (!mounted) return;
    setState(() {
      _adding = false;
      if (ok != null) _lastCreatedId = ok;
    });
    if (ok != null) {
      _newNameCtrl.clear();
      _newFocusNode.requestFocus();
      _showSnack('Categoría "$name" creada', isError: false);
    } else {
      _showSnack(provider.errorMessage ?? 'Error al crear categoría', isError: true);
    }
  }

  Future<void> _saveEdit(CatalogProvider provider, int id, bool isPremium) async {
    final name = _editCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _editingId = null);
      return;
    }
    final ok = await provider.updateCategory(
      id,
      name,
      rubroId: isPremium ? _editRubroId : null,
    );
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
    if (isError) {
      SnackBarService.error(context, msg, duration: duration);
    } else {
      SnackBarService.success(context, msg, duration: duration);
    }
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isPremium = context.watch<SettingsProvider>().features.multiRubro;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      title: Row(
        children: [
          Icon(Icons.label_rounded, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          const Expanded(child: Text('Gestión de Categorías', overflow: TextOverflow.ellipsis)),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SizedBox(
        width: 500,
        height: 440,
        child: Column(
          children: [
            // ── Formulario nueva categoría (Responsive con LayoutBuilder) ──
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 380;
                final catalogProv = context.watch<CatalogProvider>();
                final rubros = catalogProv.rubros;

                // Auto-seleccionar primer rubro en Premium si no se seleccionó
                if (isPremium && _newRubroId == null && rubros.isNotEmpty) {
                  _newRubroId = rubros.first.id;
                }

                if (!isPremium) {
                  // Plan Básico: Input simple de nombre + botón
                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _newNameCtrl,
                          focusNode: _newFocusNode,
                          decoration: InputDecoration(
                            hintText: 'Nombre de nueva categoría...',
                            prefixIcon: Icon(Icons.add, color: Theme.of(context).colorScheme.primary),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                          onSubmitted: (_) => _createCategory(catalogProv, false),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          icon: _adding
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.check, size: 16),
                          label: Text(_adding ? 'Guardando...' : 'Agregar'),
                          onPressed: _adding ? null : () => _createCategory(catalogProv, false),
                        ),
                      ],
                    );
                  }

                  return Row(
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
                          onSubmitted: (_) => _createCategory(catalogProv, false),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        icon: _adding
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check, size: 18),
                        label: Text(_adding ? 'Guardando...' : 'Agregar'),
                        onPressed: _adding ? null : () => _createCategory(catalogProv, false),
                      ),
                    ],
                  );
                }

                // Plan Premium: Nombre + Selector de Rubro Padre
                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _newNameCtrl,
                        focusNode: _newFocusNode,
                        decoration: InputDecoration(
                          hintText: 'Nombre de categoría...',
                          prefixIcon: Icon(Icons.add, color: Theme.of(context).colorScheme.primary),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                        onSubmitted: (_) => _createCategory(catalogProv, true),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int?>(
                        isExpanded: true,
                        // ignore: deprecated_member_use
                        value: rubros.any((r) => r.id == _newRubroId)
                            ? _newRubroId
                            : (rubros.isNotEmpty ? rubros.first.id : null),
                        decoration: InputDecoration(
                          labelText: 'Rubro Padre',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          isDense: true,
                        ),
                        items: rubros
                            .map((r) => DropdownMenuItem<int?>(
                                  value: r.id,
                                  child: Text(r.name, overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (val) => setState(() => _newRubroId = val),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        icon: _adding
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check, size: 16),
                        label: Text(_adding ? 'Guardando...' : 'Agregar'),
                        onPressed: _adding ? null : () => _createCategory(catalogProv, true),
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: TextField(
                        controller: _newNameCtrl,
                        focusNode: _newFocusNode,
                        decoration: InputDecoration(
                          hintText: 'Nombre de categoría...',
                          prefixIcon: Icon(Icons.add, color: Theme.of(context).colorScheme.primary),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                        onSubmitted: (_) => _createCategory(catalogProv, true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: DropdownButtonFormField<int?>(
                        isExpanded: true,
                        // ignore: deprecated_member_use
                        value: rubros.any((r) => r.id == _newRubroId)
                            ? _newRubroId
                            : (rubros.isNotEmpty ? rubros.first.id : null),
                        decoration: InputDecoration(
                          labelText: 'Rubro Padre',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          isDense: true,
                        ),
                        items: rubros
                            .map((r) => DropdownMenuItem<int?>(
                                  value: r.id,
                                  child: Text(r.name, overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (val) => setState(() => _newRubroId = val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      onPressed: _adding ? null : () => _createCategory(catalogProv, true),
                      child: _adding
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Agregar'),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Divider(color: Colors.grey.shade200, height: 1),

            // ── Lista de categorías ───────────────────────────
            Expanded(child: _buildCategoryList(isPremium)),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      actions: [
        Consumer<CatalogProvider>(
          builder: (_, p, __) => Text(
            '${p.categories.length} categoría${p.categories.length != 1 ? 's' : ''}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_lastCreatedId),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  Widget _buildCategoryList(bool isPremium) {
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
          itemBuilder: (ctx, i) => _buildCategoryTile(provider, cats[i], isPremium),
        );
      },
    );
  }

  Widget _buildCategoryTile(CatalogProvider provider, Category cat, bool isPremium) {
    final isEditing = _editingId == cat.id;
    final rubroName = cat.rubro?.name ??
        (cat.rubroId != null
            ? provider.rubros.where((r) => r.id == cat.rubroId).firstOrNull?.name
            : null);

    return ListTile(
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        child: Icon(Icons.label_rounded,
            color: Theme.of(context).colorScheme.primary, size: 14),
      ),
      title: isEditing
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _editCtrl,
                  autofocus: true,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                  ),
                  onSubmitted: (_) => _saveEdit(provider, cat.id, isPremium),
                ),
                if (isPremium) ...[
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int?>(
                    isExpanded: true,
                    // ignore: deprecated_member_use
                    value: provider.rubros.any((r) => r.id == _editRubroId)
                        ? _editRubroId
                        : (provider.rubros.isNotEmpty ? provider.rubros.first.id : null),
                    decoration: const InputDecoration(
                      labelText: 'Rubro Padre',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    ),
                    items: provider.rubros
                        .map((r) => DropdownMenuItem<int?>(
                              value: r.id,
                              child: Text(r.name, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (val) => setState(() => _editRubroId = val),
                  ),
                ],
              ],
            )
          : Text(
              cat.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
      subtitle: isPremium && !isEditing && rubroName != null
          ? Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Rubro: $rubroName',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.purple.shade700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            )
          : null,
      trailing: provider.isLoading && _editingId == cat.id
          ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: isEditing
                  ? [
                      IconButton(
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.check_rounded, color: Colors.green, size: 20),
                        tooltip: 'Guardar',
                        onPressed: () => _saveEdit(provider, cat.id, isPremium),
                      ),
                      IconButton(
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                        icon: Icon(Icons.close_rounded, color: Colors.grey.shade500, size: 20),
                        tooltip: 'Cancelar',
                        onPressed: () => setState(() => _editingId = null),
                      ),
                    ]
                  : [
                      IconButton(
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                        icon: Icon(Icons.edit_outlined,
                            color: Theme.of(context).colorScheme.primary, size: 18),
                        tooltip: 'Editar',
                        onPressed: () => setState(() {
                          _editingId = cat.id;
                          _editCtrl.text = cat.name;
                          _editRubroId = cat.rubroId ?? cat.rubro?.id;
                        }),
                      ),
                      IconButton(
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
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
