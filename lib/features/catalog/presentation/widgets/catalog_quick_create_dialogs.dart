import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/presentation/widgets/searchable_select_field.dart';
import 'package:frontend_desktop/core/utils/search_text_utils.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/rubros_manager_dialog.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/presentation/widgets/supplier_form_dialog.dart';

/// Diálogos reutilizables de alta rápida para Categoría, Marca y Proveedor.
/// Pensados para invocarse desde selectores (Ficha de Producto, Asignación en Lote
/// y Carga Rápida en Grilla) devolviendo el ID recién creado para auto-seleccionarlo.
class CatalogQuickCreateDialogs {
  const CatalogQuickCreateDialogs._();

  static Future<int?> showCreateCategory(
    BuildContext context, {
    String? initialName,
    String subtitle = 'Creá una categoría rápida para asignarla al instante',
  }) async {
    SettingsProvider? settingsProv;
    try {
      settingsProv = context.read<SettingsProvider?>();
    } catch (_) {}
    final isPremium = settingsProv?.features.multiRubro ?? false;
    final provider = context.read<CatalogProvider>();

    if (isPremium && provider.rubros.isEmpty) {
      await provider.loadRubros();
    }

    if (!context.mounted) return null;

    final initialRubros = sortByAlphabeticalName(provider.rubros, (r) => r.name);
    final initialRubroId =
        initialRubros.isNotEmpty ? initialRubros.first.id : null;

    return showDialog<int?>(
      context: context,
      builder: (_) => _QuickCreateCategoryDialog(
        initialName: initialName?.trim() ?? '',
        subtitle: subtitle,
        isMultiRubro: isPremium,
        initialRubroId: initialRubroId,
      ),
    );
  }

  static Future<int?> showCreateBrand(
    BuildContext context, {
    String? initialName,
    String subtitle = 'Creá una marca rápida para asignarla al instante',
  }) async {
    return showDialog<int?>(
      context: context,
      builder: (_) => _QuickCreateBrandDialog(
        initialName: initialName?.trim() ?? '',
        subtitle: subtitle,
      ),
    );
  }

  static Future<int?> showCreateSupplier(
    BuildContext context, {
    String? initialQuery,
  }) async {
    final trimmed = initialQuery?.trim() ?? '';
    Map<String, dynamic>? initialData;
    if (trimmed.isNotEmpty) {
      final digitsOnly = trimmed.replaceAll(RegExp(r'\D'), '');
      final looksLikeCuit = RegExp(r'^[\d\-\s]+$').hasMatch(trimmed) &&
          digitsOnly.length >= 7 &&
          digitsOnly.length <= 13;
      initialData = looksLikeCuit ? {'cuit': trimmed} : {'name': trimmed};
    }

    return showDialog<int>(
      context: context,
      builder: (_) => SupplierFormDialog(initialData: initialData),
    );
  }
}

class _QuickCreateCategoryDialog extends StatefulWidget {
  final String initialName;
  final String subtitle;
  final bool isMultiRubro;
  final int? initialRubroId;

  const _QuickCreateCategoryDialog({
    required this.initialName,
    required this.subtitle,
    required this.isMultiRubro,
    this.initialRubroId,
  });

  @override
  State<_QuickCreateCategoryDialog> createState() =>
      _QuickCreateCategoryDialogState();
}

class _QuickCreateCategoryDialogState
    extends State<_QuickCreateCategoryDialog> {
  late final TextEditingController _nameCtrl;
  int? _selectedRubroId;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _selectedRubroId = widget.initialRubroId;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _openCreateRubro({String? suggestedName}) async {
    final newRubroId = await RubrosManagerDialog.showQuickCreateDialog(
      context,
      initialName: suggestedName,
    );
    if (newRubroId != null && mounted) {
      setState(() => _selectedRubroId = newRubroId);
    }
  }

  Future<void> _submit(CatalogProvider p) async {
    if (p.isLoading) return;
    final cleanName = _nameCtrl.text.trim();
    if (cleanName.isEmpty) return;
    final newId = await p.createCategory(
      cleanName,
      rubroId: widget.isMultiRubro ? _selectedRubroId : null,
    );
    if (newId != null && mounted) {
      Navigator.pop(context, newId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppModalShell(
      title: 'Nueva Categoría',
      subtitle: widget.subtitle,
      icon: Icons.label_outline,
      accent: AppModalAccent.blue,
      compact: true,
      maxWidth: 440,
      onClose: () => Navigator.pop(context),
      body: Consumer<CatalogProvider>(
        builder: (_, p, __) {
          final sortedRubros =
              sortByAlphabeticalName(p.rubros, (r) => r.name);
          final resolvedRubroId = (widget.isMultiRubro &&
                  sortedRubros.isNotEmpty &&
                  !sortedRubros.any((r) => r.id == _selectedRubroId))
              ? sortedRubros.first.id
              : _selectedRubroId;
          _selectedRubroId = resolvedRubroId;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('quick_create_category_name_field'),
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label_outline),
                ),
                autofocus: true,
                onSubmitted: (_) => _submit(p),
              ),
              if (widget.isMultiRubro) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: SearchableSelectField<int?>(
                        value: resolvedRubroId,
                        showClearButton: false,
                        labelText: 'Rubro Padre',
                        hintText: sortedRubros.isEmpty
                            ? 'Sin rubros creados aún'
                            : null,
                        dialogTitle: 'Seleccionar Rubro Padre',
                        searchHintText: 'Buscar rubro...',
                        emptySearchText: 'No hay rubros registrados',
                        prefixIcon: Icons.category_outlined,
                        border: const OutlineInputBorder(),
                        options: sortedRubros
                            .map((r) => SearchableSelectOption<int?>(
                                  value: r.id,
                                  label: r.name,
                                ))
                            .toList(),
                        onChanged: (val) =>
                            setState(() => _selectedRubroId = val),
                        onCreateNew: (query) =>
                            _openCreateRubro(suggestedName: query),
                        createLabelBuilder: (query) => query.trim().isEmpty
                            ? 'Crear nuevo rubro'
                            : 'Crear rubro "${query.trim()}"',
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: 'Crear nuevo rubro',
                      onPressed: () => _openCreateRubro(),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
      footerActions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        Consumer<CatalogProvider>(
          builder: (_, p, __) => FilledButton(
            key: const ValueKey('quick_create_category_submit_btn'),
            onPressed: p.isLoading ? null : () => _submit(p),
            child: const Text('Crear'),
          ),
        ),
      ],
    );
  }
}

class _QuickCreateBrandDialog extends StatefulWidget {
  final String initialName;
  final String subtitle;

  const _QuickCreateBrandDialog({
    required this.initialName,
    required this.subtitle,
  });

  @override
  State<_QuickCreateBrandDialog> createState() =>
      _QuickCreateBrandDialogState();
}

class _QuickCreateBrandDialogState extends State<_QuickCreateBrandDialog> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(CatalogProvider p) async {
    if (p.isLoading) return;
    final cleanName = _nameCtrl.text.trim();
    if (cleanName.isEmpty) return;
    final newId = await p.createBrand(cleanName);
    if (newId != null && mounted) {
      Navigator.pop(context, newId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CatalogProvider>(
      builder: (_, p, __) => AppModalShell(
        title: 'Nueva Marca',
        subtitle: widget.subtitle,
        icon: Icons.branding_watermark_outlined,
        accent: AppModalAccent.blue,
        compact: true,
        maxWidth: 440,
        onClose: () => Navigator.pop(context),
        body: TextField(
          key: const ValueKey('quick_create_brand_name_field'),
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Nombre',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.branding_watermark_outlined),
          ),
          autofocus: true,
          onSubmitted: (_) => _submit(p),
        ),
        footerActions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('quick_create_brand_submit_btn'),
            onPressed: p.isLoading ? null : () => _submit(p),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }
}
