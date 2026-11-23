import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
import '../providers/catalog_provider.dart';
import '../../domain/entities/brand.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';

/// Dialog de gestión ABM de Marcas.
/// Estilo consistente con CategoriesManagerDialog.
class BrandsManagerDialog extends StatefulWidget {
  const BrandsManagerDialog({super.key});

  @override
  State<BrandsManagerDialog> createState() => _BrandsManagerDialogState();
}

class _BrandsManagerDialogState extends State<BrandsManagerDialog> {
  final _newNameCtrl  = TextEditingController();
  final _newFocusNode = FocusNode();
  bool _adding = false;

  int? _editingId;
  final _editCtrl = TextEditingController();

  /// ID de la última marca creada en esta sesión del dialog.
  /// Se retorna al cerrar para que el caller pueda auto-seleccionarla.
  int? _lastCreatedId;

  @override
  void dispose() {
    _newNameCtrl.dispose();
    _editCtrl.dispose();
    _newFocusNode.dispose();
    super.dispose();
  }

  // ── Acciones ────────────────────────────────────────────────────

  Future<void> _createBrand(CatalogProvider provider) async {
    final name = _newNameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _adding = true);
    final ok = await provider.createBrand(name);
    if (!mounted) return;
    setState(() {
      _adding = false;
      if (ok != null) _lastCreatedId = ok;
    });
    if (ok != null) {
      _newNameCtrl.clear();
      _newFocusNode.requestFocus();
      _showSnack('Marca "$name" creada', isError: false);
    } else {
      _showSnack(provider.errorMessage ?? 'Error al crear marca', isError: true);
    }
  }

  Future<void> _saveEdit(CatalogProvider provider, int id) async {
    final name = _editCtrl.text.trim();
    if (name.isEmpty) { setState(() => _editingId = null); return; }
    final ok = await provider.updateBrand(id, name);
    if (!mounted) return;
    if (ok) {
      _showSnack('Marca actualizada', isError: false);
    } else {
      _showSnack(provider.errorMessage ?? 'Error al actualizar', isError: true);
    }
    setState(() => _editingId = null);
  }

  Future<void> _deleteBrand(CatalogProvider provider, Brand brand) async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Confirmar eliminación',
      message:
          '¿Eliminar la marca "${brand.name}"?\n\nSi tiene productos asociados, la operación será rechazada.',
      confirmLabel: 'Eliminar',
      cancelLabel: 'Cancelar',
      icon: Icons.delete_outline,
      isDestructive: true,
    );
    if (confirm != true || !mounted) return;
    final ok = await provider.deleteBrand(brand.id);
    if (!mounted) return;
    if (ok) {
      _showSnack('Marca "${brand.name}" eliminada', isError: false);
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
    return AppModalShell(
      title: 'Gestión de Marcas',
      subtitle: 'Administrá las marcas disponibles para tus productos',
      icon: Icons.branding_watermark_outlined,
      accent: AppModalAccent.blue,
      maxWidth: 540,
      maxHeight: 540,
      expandBody: true,
      onClose: () => Navigator.of(context).pop(_lastCreatedId),
      bodyPadding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      body: Column(
        children: [
          // ── Fila agregar ──────────────────────────────────
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newNameCtrl,
                  focusNode: _newFocusNode,
                  decoration: InputDecoration(
                    hintText: 'Nombre de nueva marca...',
                    prefixIcon: const Icon(Icons.add, color: AppColors.primary),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onSubmitted: (_) => _createBrand(context.read<CatalogProvider>()),
                ),
              ),
              const SizedBox(width: 10),
              Consumer<CatalogProvider>(
                builder: (ctx, provider, _) => FilledButton.icon(
                  icon: _adding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: Text(_adding ? 'Guardando...' : 'Agregar'),
                  onPressed: _adding ? null : () => _createBrand(provider),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.grey.shade200, height: 1),

          // ── Lista de marcas ───────────────────────────
          Expanded(child: _buildBrandList()),
        ],
      ),
      footerLeading: Consumer<CatalogProvider>(
        builder: (_, p, __) => Text(
          '${p.brands.length} marca${p.brands.length != 1 ? 's' : ''}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ),
      footerActions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_lastCreatedId),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  Widget _buildBrandList() {
    return Consumer<CatalogProvider>(
      builder: (ctx, provider, _) {
        final brands = provider.brands;
        if (provider.isLoading && brands.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (brands.isEmpty) {
          return Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.branding_watermark_outlined, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              const Text('Sin marcas creadas', style: TextStyle(color: Colors.black45)),
            ]),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: brands.length,
          separatorBuilder: (_, __) => Divider(color: Colors.grey.shade100, height: 1),
          itemBuilder: (ctx, i) => _buildBrandTile(provider, brands[i]),
        );
      },
    );
  }

  Widget _buildBrandTile(CatalogProvider provider, Brand brand) {
    final isEditing = _editingId == brand.id;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        child: Icon(Icons.branding_watermark_outlined,
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
              onSubmitted: (_) => _saveEdit(provider, brand.id),
            )
          : Text(brand.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      trailing: provider.isLoading && _editingId == brand.id
          ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: isEditing
                  ? [
                      IconButton(
                        icon: const Icon(Icons.check_rounded, color: Colors.green, size: 20),
                        tooltip: 'Guardar',
                        onPressed: () => _saveEdit(provider, brand.id),
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
                          _editingId = brand.id;
                          _editCtrl.text = brand.name;
                        }),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline,
                            color: Colors.red.shade400, size: 18),
                        tooltip: 'Eliminar',
                        onPressed: () => _deleteBrand(provider, brand),
                      ),
                    ],
            ),
    );
  }
}
