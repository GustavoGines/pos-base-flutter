import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';

class PosRenameCartItemResult {
  final String? customDescription;
  final String? customDetails;
  final double? newUnitPrice;
  final double? newQuantity;

  const PosRenameCartItemResult({
    this.customDescription,
    this.customDetails,
    this.newUnitPrice,
    this.newQuantity,
  });
}

class PosRenameCartItemDialog extends StatefulWidget {
  final CartItem item;

  const PosRenameCartItemDialog({
    super.key,
    required this.item,
  });

  static Future<PosRenameCartItemResult?> show(
    BuildContext context, {
    required CartItem item,
  }) {
    return showDialog<PosRenameCartItemResult>(
      context: context,
      barrierDismissible: true,
      builder: (_) => PosRenameCartItemDialog(item: item),
    );
  }

  @override
  State<PosRenameCartItemDialog> createState() =>
      _PosRenameCartItemDialogState();
}

class _PosRenameCartItemDialogState extends State<PosRenameCartItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _descController;
  late final TextEditingController _detailsController;
  late final TextEditingController _priceController;
  final _descFocus = FocusNode();

  bool get _isTempOrUnregistered =>
      widget.item.isTemporary ||
      widget.item.saveToCatalog ||
      widget.item.product.id <= 0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleDialogKey);
    _descController = TextEditingController(
      text: widget.item.effectiveDisplayName,
    );
    _detailsController = TextEditingController(
      text: widget.item.customDetails ?? '',
    );
    _priceController = TextEditingController(
      text: widget.item.unitPrice.toStringAsFixed(2),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _descFocus.requestFocus();
        _descController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _descController.text.length,
        );
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleDialogKey);
    _descController.dispose();
    _detailsController.dispose();
    _priceController.dispose();
    _descFocus.dispose();
    super.dispose();
  }

  void _restoreCatalogName() {
    setState(() {
      _descController.text = widget.item.product.name;
    });
  }

  bool _isSubmitted = false;

  /// Atajos globales del diálogo, independientes del campo que tenga el foco:
  /// - Esc → Cancelar y cerrar.
  /// - Enter / NumpadEnter → Aplicar (Shift+Enter: salto de línea en Notas).
  bool _handleDialogKey(KeyEvent event) {
    if (!mounted || _isSubmitted) return false;
    if (event is! KeyDownEvent) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return true;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed) return false;
      _submit();
      return true;
    }
    return false;
  }

  void _submit() {
    if (_isSubmitted) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _isSubmitted = true;
    final cleanDesc = _descController.text.trim();
    final cleanDetails = _detailsController.text.trim();
    final parsedPrice = double.tryParse(
      _priceController.text.trim().replaceAll(',', '.'),
    );

    Navigator.of(context).pop(
      PosRenameCartItemResult(
        customDescription: cleanDesc,
        customDetails: cleanDetails.isNotEmpty ? cleanDetails : null,
        newUnitPrice: (_isTempOrUnregistered && parsedPrice != null && parsedPrice > 0)
            ? parsedPrice
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final originalName = widget.item.product.name;

    return Focus(
      autofocus: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.edit_note_rounded,
                          color: Colors.indigo.shade700,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Alias de Facturación / Ticket (Solo esta venta)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _isTempOrUnregistered
                                  ? 'Ítem Rápido de Mostrador'
                                  : 'Catálogo original: $originalName (Stock e ID intactos)',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, size: 20),
                        tooltip: 'Cerrar (Esc)',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Campo de descripción personalizada
                  TextFormField(
                    controller: _descController,
                    focusNode: _descFocus,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Descripción a imprimir en Factura A/B/C y Ticket *',
                      hintText: originalName,
                      prefixIcon: const Icon(Icons.drive_file_rename_outline, size: 20),
                      suffixIcon: !_isTempOrUnregistered
                          ? IconButton(
                              onPressed: _restoreCatalogName,
                              tooltip: 'Restaurar nombre original del catálogo',
                              icon: const Icon(Icons.restore_rounded, size: 19),
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      isDense: true,
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'La descripción no puede quedar vacía';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Notas / Detalles adicionales
                  TextFormField(
                    controller: _detailsController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Notas / Detalle adicional en línea (Opcional)',
                      hintText: 'Ej: N° de serie, color... (Shift+Enter: nueva línea)',
                      prefixIcon: const Icon(Icons.notes_rounded, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      isDense: true,
                    ),
                  ),

                  if (_isTempOrUnregistered) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Precio Unitario (\$)',
                        prefixText: '\$ ',
                        prefixIcon: const Icon(Icons.attach_money_rounded, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        isDense: true,
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF475569)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Este cambio aplica únicamente a este comprobante (Ticket Térmico, PDF A4 y Factura Electrónica ARCA/AFIP). El nombre del producto en tu catálogo no se modifica.',
                            style: TextStyle(fontSize: 11.5, color: Color(0xFF475569)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancelar (Esc)'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _submit,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Aplicar en Comprobante (Enter)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
