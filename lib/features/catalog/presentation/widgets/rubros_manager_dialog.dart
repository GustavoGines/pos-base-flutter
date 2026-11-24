import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/config/business_vertical_profile.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
import '../providers/catalog_provider.dart';
import '../../domain/entities/rubro.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';

Widget _buildRubroVerticalDropdown({
  required String? value,
  required ValueChanged<String?>? onChanged,
  bool isDense = false,
  String labelText = 'Comportamiento del rubro (opcional)',
}) {
  return DropdownButtonFormField<String?>(
    key: ValueKey('rubro_vertical_${labelText}_${value ?? 'auto'}'),
    initialValue: BusinessVerticalProfile.allVerticalCodes.contains(value)
        ? value
        : null,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: labelText,
      prefixIcon: isDense
          ? null
          : const Icon(Icons.store_mall_directory_outlined),
      border: isDense
          ? null
          : OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      isDense: isDense,
      contentPadding: isDense
          ? const EdgeInsets.symmetric(vertical: 4)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    items: [
      const DropdownMenuItem<String?>(
        value: null,
        child: Text(
          'Automático (según negocio / nombre)',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      ...BusinessVerticalProfile.allVerticalCodes.map(
        (code) => DropdownMenuItem<String?>(
          value: code,
          child: Text(
            BusinessVerticalProfile.selectorLabels[code] ?? code,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    ],
    onChanged: onChanged,
  );
}

/// Diálogo de gestión ABM de Rubros Comerciales (Exclusivo Plan Premium).
class RubrosManagerDialog extends StatefulWidget {
  const RubrosManagerDialog({super.key});

  /// Abre un diálogo rápido para crear un Rubro en línea y devuelve su ID.
  static Future<int?> showQuickCreateDialog(
    BuildContext context, {
    String? initialName,
  }) {
    return showDialog<int?>(
      context: context,
      builder: (_) => _QuickCreateRubroDialog(initialName: initialName),
    );
  }

  @override
  State<RubrosManagerDialog> createState() => _RubrosManagerDialogState();
}

class _QuickCreateRubroDialog extends StatefulWidget {
  final String? initialName;

  const _QuickCreateRubroDialog({this.initialName});

  @override
  State<_QuickCreateRubroDialog> createState() =>
      _QuickCreateRubroDialogState();
}

class _QuickCreateRubroDialogState extends State<_QuickCreateRubroDialog> {
  late final TextEditingController _nameCtrl;
  final TextEditingController _descCtrl = TextEditingController();
  String? _selectedVerticalType;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Ingresá el nombre del rubro.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final provider = context.read<CatalogProvider>();
    final desc = _descCtrl.text.trim();
    final newId = await provider.createRubro(
      name,
      description: desc.isEmpty ? null : desc,
      verticalType: _selectedVerticalType,
    );

    if (!mounted) return;
    if (newId != null) {
      Navigator.pop(context, newId);
      return;
    }

    setState(() {
      _saving = false;
      _error = provider.errorMessage ?? 'No se pudo crear el rubro.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppModalShell(
      title: 'Nuevo Rubro Comercial',
      subtitle: 'Creá un rubro para agrupar categorías del catálogo',
      icon: Icons.create_new_folder_outlined,
      accent: AppModalAccent.blue,
      compact: true,
      maxWidth: 460,
      onClose: () {
        if (!_saving) Navigator.pop(context);
      },
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            enabled: !_saving,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nombre *',
              hintText: 'Ej: Panadería, Bebidas, Tecnología...',
              prefixIcon: Icon(Icons.folder_outlined),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _saving ? null : _submit(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            enabled: !_saving,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Descripción (opcional)',
              prefixIcon: Icon(Icons.description_outlined),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _saving ? null : _submit(),
          ),
          const SizedBox(height: 12),
          _buildRubroVerticalDropdown(
            value: _selectedVerticalType,
            onChanged: _saving
                ? null
                : (val) => setState(() => _selectedVerticalType = val),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(color: colorScheme.error, fontSize: 12.5),
            ),
          ],
        ],
      ),
      footerActions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _submit,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check, size: 16),
          label: Text(_saving ? 'Creando...' : 'Crear Rubro'),
        ),
      ],
    );
  }
}

class _RubrosManagerDialogState extends State<RubrosManagerDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _nameFocusNode = FocusNode();
  String? _selectedVerticalType;
  bool _adding = false;

  int? _editingId;
  final _editNameCtrl = TextEditingController();
  final _editDescCtrl = TextEditingController();
  String? _editVerticalType;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CatalogProvider>().loadRubros();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _nameFocusNode.dispose();
    _editNameCtrl.dispose();
    _editDescCtrl.dispose();
    super.dispose();
  }

  Future<void> _createRubro(CatalogProvider provider) async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final desc = _descCtrl.text.trim();

    setState(() => _adding = true);
    final id = await provider.createRubro(
      name,
      description: desc.isNotEmpty ? desc : null,
      verticalType: _selectedVerticalType,
    );
    if (!mounted) return;
    setState(() => _adding = false);

    if (id != null) {
      _nameCtrl.clear();
      _descCtrl.clear();
      setState(() => _selectedVerticalType = null);
      _nameFocusNode.requestFocus();
      _showSnack('Rubro "$name" creado correctamente', isError: false);
    } else {
      _showSnack(provider.errorMessage ?? 'Error al crear rubro', isError: true);
    }
  }

  Future<void> _saveEdit(CatalogProvider provider, int id) async {
    final name = _editNameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _editingId = null);
      return;
    }
    final desc = _editDescCtrl.text.trim();
    final ok = await provider.updateRubro(
      id,
      name,
      description: desc.isNotEmpty ? desc : null,
      verticalType: _editVerticalType,
    );
    if (!mounted) return;
    if (ok) {
      _showSnack('Rubro actualizado', isError: false);
    } else {
      _showSnack(provider.errorMessage ?? 'Error al actualizar', isError: true);
    }
    setState(() => _editingId = null);
  }

  Future<void> _deleteRubro(CatalogProvider provider, Rubro rubro) async {
    if (rubro.isSystem) {
      _showSnack('El rubro principal del sistema no se puede eliminar.', isError: true);
      return;
    }

    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Confirmar eliminación',
      message:
          '¿Eliminar el rubro "${rubro.name}"?\n\nSi tiene categorías asociadas, la operación será rechazada.',
      confirmLabel: 'Eliminar',
      cancelLabel: 'Cancelar',
      icon: Icons.delete_outline,
      isDestructive: true,
    );

    if (confirm != true || !mounted) return;
    final ok = await provider.deleteRubro(rubro.id);
    if (!mounted) return;
    if (ok) {
      _showSnack('Rubro "${rubro.name}" eliminado', isError: false);
    } else {
      final msg = provider.errorMessage ?? 'No se puede eliminar: tiene categorías asociadas';
      _showSnack(msg, isError: true, duration: const Duration(seconds: 5));
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

  @override
  Widget build(BuildContext context) {
    return AppModalShell(
      title: 'Gestión de Rubros',
      subtitle: 'Agrupá las categorías y el ordenamiento de tu catálogo',
      icon: Icons.category_rounded,
      accent: AppModalAccent.blue,
      maxWidth: 560,
      maxHeight: 560,
      expandBody: true,
      bodyPadding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      body: Column(
        children: [
            // ── Formulario nuevo rubro (Anti-overflow con LayoutBuilder) ────
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 380;
                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _nameCtrl,
                        focusNode: _nameFocusNode,
                        decoration: InputDecoration(
                          hintText: 'Nombre del rubro *',
                          prefixIcon: Icon(Icons.add, color: Theme.of(context).colorScheme.primary),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                        onSubmitted: (_) => _createRubro(context.read<CatalogProvider>()),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _descCtrl,
                        decoration: InputDecoration(
                          hintText: 'Descripción (opcional)',
                          prefixIcon: const Icon(Icons.description_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                        onSubmitted: (_) => _createRubro(context.read<CatalogProvider>()),
                      ),
                      const SizedBox(height: 8),
                      _buildRubroVerticalDropdown(
                        value: _selectedVerticalType,
                        onChanged: _adding
                            ? null
                            : (val) =>
                                setState(() => _selectedVerticalType = val),
                      ),
                      const SizedBox(height: 8),
                      Consumer<CatalogProvider>(
                        builder: (ctx, provider, _) => FilledButton.icon(
                          icon: _adding
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.check, size: 16),
                          label: Text(_adding ? 'Guardando...' : 'Agregar Rubro'),
                          onPressed: _adding ? null : () => _createRubro(provider),
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: TextField(
                            controller: _nameCtrl,
                            focusNode: _nameFocusNode,
                            decoration: InputDecoration(
                              hintText: 'Nombre del rubro *',
                              prefixIcon: Icon(Icons.add, color: Theme.of(context).colorScheme.primary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            onSubmitted: (_) => _createRubro(context.read<CatalogProvider>()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 5,
                          child: TextField(
                            controller: _descCtrl,
                            decoration: InputDecoration(
                              hintText: 'Descripción (opcional)',
                              prefixIcon: const Icon(Icons.description_outlined),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            onSubmitted: (_) => _createRubro(context.read<CatalogProvider>()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Consumer<CatalogProvider>(
                          builder: (ctx, provider, _) => FilledButton(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            onPressed: _adding ? null : () => _createRubro(provider),
                            child: _adding
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Agregar'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildRubroVerticalDropdown(
                      value: _selectedVerticalType,
                      onChanged: _adding
                          ? null
                          : (val) =>
                              setState(() => _selectedVerticalType = val),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Divider(color: Colors.grey.shade200, height: 1),

            // ── Lista de rubros ─────────────────────────────────────────────
            Expanded(child: _buildRubroList()),
          ],
        ),
      footerLeading: Consumer<CatalogProvider>(
        builder: (_, p, __) => Text(
          '${p.rubros.length} rubro${p.rubros.length != 1 ? 's' : ''}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ),
      footerActions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  Widget _buildRubroList() {
    return Consumer<CatalogProvider>(
      builder: (ctx, provider, _) {
        final rubros = provider.rubros;
        if (provider.isLoading && rubros.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (rubros.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.category_outlined, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                const Text('Sin rubros creados', style: TextStyle(color: Colors.black45)),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: rubros.length,
          separatorBuilder: (_, __) => Divider(color: Colors.grey.shade100, height: 1),
          itemBuilder: (ctx, i) => _buildRubroTile(provider, rubros[i]),
        );
      },
    );
  }

  Widget _buildRubroTile(CatalogProvider provider, Rubro rubro) {
    final isEditing = _editingId == rubro.id;

    return ListTile(
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: rubro.isSystem
            ? Colors.blue.shade100
            : Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        child: Icon(
          rubro.isSystem ? Icons.star_rounded : Icons.category_rounded,
          color: rubro.isSystem ? Colors.blue.shade800 : Theme.of(context).colorScheme.primary,
          size: 16,
        ),
      ),
      title: isEditing
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _editNameCtrl,
                  autofocus: true,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                  ),
                  onSubmitted: (_) => _saveEdit(provider, rubro.id),
                ),
                TextField(
                  controller: _editDescCtrl,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                  ),
                  onSubmitted: (_) => _saveEdit(provider, rubro.id),
                ),
                const SizedBox(height: 4),
                _buildRubroVerticalDropdown(
                  value: _editVerticalType,
                  isDense: true,
                  labelText: 'Comportamiento del rubro',
                  onChanged: (val) => setState(() => _editVerticalType = val),
                ),
              ],
            )
          : Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                Text(
                  rubro.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
                if (rubro.isSystem)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue.shade300),
                    ),
                    child: Text(
                      'Principal',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ),
                if (rubro.verticalType != null &&
                    BusinessVerticalProfile.shortBadgeLabels
                        .containsKey(rubro.verticalType))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.indigo.shade200),
                    ),
                    child: Text(
                      BusinessVerticalProfile
                          .shortBadgeLabels[rubro.verticalType!]!,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.indigo.shade800,
                      ),
                    ),
                  ),
              ],
            ),
      subtitle: !isEditing && rubro.description != null && rubro.description!.isNotEmpty
          ? Text(
              rubro.description!,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: isEditing
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.check_rounded, color: Colors.green, size: 20),
                  tooltip: 'Guardar',
                  onPressed: () => _saveEdit(provider, rubro.id),
                ),
                IconButton(
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.close_rounded, color: Colors.grey.shade500, size: 20),
                  tooltip: 'Cancelar',
                  onPressed: () => setState(() => _editingId = null),
                ),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.edit_outlined,
                    color: Theme.of(context).colorScheme.primary,
                    size: 18,
                  ),
                  tooltip: 'Editar',
                  onPressed: () => setState(() {
                    _editingId = rubro.id;
                    _editNameCtrl.text = rubro.name;
                    _editDescCtrl.text = rubro.description ?? '';
                    _editVerticalType = rubro.verticalType;
                  }),
                ),
                if (rubro.isSystem)
                  Tooltip(
                    message: 'El rubro principal del sistema no se puede eliminar',
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: Center(
                        child: Icon(Icons.lock_outline, size: 18, color: Colors.grey.shade400),
                      ),
                    ),
                  )
                else
                  IconButton(
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 18),
                    tooltip: 'Eliminar',
                    onPressed: () => _deleteRubro(provider, rubro),
                  ),
              ],
            ),
    );
  }
}
