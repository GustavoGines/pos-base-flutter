import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';

class PosRenameCartItemResult {
  final String? customDescription;
  final String? customDetails;
  final double? newUnitPrice;
  final bool clearManualUnitPrice;
  final double? newCostPrice;
  final bool clearManualCostPrice;
  final double? newQuantity;
  final bool updateCatalogInDb;
  final bool sellingPriceChanged;
  final bool costPriceChanged;

  const PosRenameCartItemResult({
    this.customDescription,
    this.customDetails,
    this.newUnitPrice,
    this.clearManualUnitPrice = false,
    this.newCostPrice,
    this.clearManualCostPrice = false,
    this.newQuantity,
    this.updateCatalogInDb = false,
    this.sellingPriceChanged = false,
    this.costPriceChanged = false,
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
  late final TextEditingController _costController;
  late final TextEditingController _marginController;
  final _descFocus = FocusNode();
  final _priceFocus = FocusNode();

  bool _isUpdatingCalc = false;
  bool _costExplicitlyEdited = false;
  bool _priceExplicitlyEdited = false;
  bool _updateCatalogInDb = false;

  bool get _isTempOrUnregistered =>
      widget.item.isTemporary ||
      widget.item.saveToCatalog ||
      widget.item.product.id <= 0;

  double get _catalogBaseSellingPrice => widget.item.product.sellingPrice;
  double get _catalogDefaultCartPrice => widget.item.defaultCalculatedUnitPrice;
  double get _catalogBaseCostPrice => widget.item.product.costPrice;

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

    final initialSelling = widget.item.unitPrice;
    final initialCost = widget.item.effectiveCostPrice;

    _priceController = TextEditingController(
      text: initialSelling > 0 ? initialSelling.toArsInput() : '',
    );
    _costController = TextEditingController(
      text: initialCost > 0 ? initialCost.toArsInput() : '',
    );
    _marginController = TextEditingController(
      text: (initialCost > 0 && initialSelling > 0)
          ? (((initialSelling - initialCost) / initialCost) * 100.0)
              .toCleanMargin()
          : '',
    );

    if (widget.item.manualUnitPrice != null) {
      _priceExplicitlyEdited = true;
    }
    if (widget.item.manualCostPrice != null) {
      _costExplicitlyEdited = true;
    }

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
    _costController.dispose();
    _marginController.dispose();
    _descFocus.dispose();
    _priceFocus.dispose();
    super.dispose();
  }

  double _parseArs(String text) => ArsThousandsInputFormatter.parse(text);

  double _parseDouble(String text) {
    final normalized = text.trim().replaceAll(',', '.');
    return double.tryParse(normalized) ?? 0.0;
  }

  /// Regla "Costo como Ancla":
  /// Cuando el usuario modifica el Precio de Venta, el Costo jamás se toca;
  /// únicamente se recalcula el indicador de % Margen.
  void _onSellingPriceChanged(String val) {
    if (_isUpdatingCalc) return;
    _isUpdatingCalc = true;
    _priceExplicitlyEdited = true;

    final price = _parseArs(val);
    final cost = _parseArs(_costController.text);

    if (cost > 0 && price > 0) {
      final calcMargin = ((price - cost) / cost) * 100.0;
      _marginController.text = calcMargin.toCleanMargin();
    } else if (val.trim().isEmpty) {
      _marginController.clear();
    }

    _isUpdatingCalc = false;
    setState(() {});
  }

  /// Cuando el usuario edita explícitamente el Costo:
  /// Si hay un % de Margen cargado, recalcula el Precio de Venta manteniendo ese margen.
  /// Si no había margen y hay Precio de Venta, calcula el nuevo % de Margen.
  void _onCostPriceChanged(String val) {
    if (_isUpdatingCalc) return;
    _isUpdatingCalc = true;
    _costExplicitlyEdited = true;

    final cost = _parseArs(val);
    final marginStr = _marginController.text.trim();
    final margin = _parseDouble(marginStr);
    final price = _parseArs(_priceController.text);

    if (cost > 0) {
      if (marginStr.isNotEmpty && margin > -100) {
        final calcSelling = cost * (1.0 + (margin / 100.0));
        _priceController.text = calcSelling.toArsInput();
        _priceExplicitlyEdited = true;
      } else if (price > 0) {
        final calcMargin = ((price - cost) / cost) * 100.0;
        _marginController.text = calcMargin.toCleanMargin();
      }
    } else if (val.trim().isEmpty) {
      _marginController.clear();
    }

    _isUpdatingCalc = false;
    setState(() {});
  }

  /// Cuando el usuario edita el % de Margen:
  /// El Costo actúa como ancla fija y se recalcula el Precio de Venta.
  void _onMarginChanged(String val) {
    if (_isUpdatingCalc) return;
    _isUpdatingCalc = true;

    final marginStr = val.trim();
    final margin = _parseDouble(marginStr);
    final cost = _parseArs(_costController.text);
    final price = _parseArs(_priceController.text);

    if (marginStr.isNotEmpty && margin > -100) {
      if (cost > 0) {
        final calcSelling = cost * (1.0 + (margin / 100.0));
        _priceController.text = calcSelling.toArsInput();
        _priceExplicitlyEdited = true;
      } else if (price > 0) {
        final calcCost = price / (1.0 + (margin / 100.0));
        _costController.text = calcCost.toArsInput();
        _costExplicitlyEdited = true;
      }
    }

    _isUpdatingCalc = false;
    setState(() {});
  }

  void _restoreCatalogName() {
    setState(() {
      _descController.text = widget.item.product.name;
    });
  }

  void _restoreCatalogPrices() {
    _isUpdatingCalc = true;
    final origPrice = _catalogDefaultCartPrice;
    final origCost = _catalogBaseCostPrice;
    _priceController.text = origPrice > 0 ? origPrice.toArsInput() : '';
    _costController.text = origCost > 0 ? origCost.toArsInput() : '';
    _marginController.text = (origCost > 0 && origPrice > 0)
        ? (((origPrice - origCost) / origCost) * 100.0).toCleanMargin()
        : '';
    _priceExplicitlyEdited = false;
    _costExplicitlyEdited = false;
    _updateCatalogInDb = false;
    _isUpdatingCalc = false;
    setState(() {});
  }

  bool get _hasSellingPriceChanged {
    final parsedPrice = _parseArs(_priceController.text);
    if (parsedPrice <= 0) return false;
    if (_updateCatalogInDb && !_isTempOrUnregistered) {
      return (parsedPrice - _catalogBaseSellingPrice).abs() >= 0.005;
    }
    return _priceExplicitlyEdited ||
        (parsedPrice - _catalogDefaultCartPrice).abs() >= 0.005;
  }

  bool get _hasCostPriceChanged {
    if (!_costExplicitlyEdited) return false;
    final costText = _costController.text.trim();
    if (costText.isEmpty) return _catalogBaseCostPrice > 0.005;
    final parsedCost = _parseArs(costText);
    return (parsedCost - _catalogBaseCostPrice).abs() >= 0.005;
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
    final parsedPriceVal = _parseArs(_priceController.text);
    final parsedPrice = parsedPriceVal > 0 ? parsedPriceVal : null;
    final costText = _costController.text.trim();
    final parsedCost = costText.isNotEmpty ? _parseArs(costText) : null;

    final sellingChanged = _hasSellingPriceChanged;
    final costChanged = _hasCostPriceChanged;
    final shouldUpdateDb = !_isTempOrUnregistered &&
        _updateCatalogInDb &&
        (sellingChanged || costChanged);

    Navigator.of(context).pop(
      PosRenameCartItemResult(
        customDescription: cleanDesc,
        customDetails: cleanDetails.isNotEmpty ? cleanDetails : null,
        newUnitPrice: (parsedPrice != null && parsedPrice > 0)
            ? parsedPrice
            : null,
        clearManualUnitPrice:
            !_isTempOrUnregistered && !sellingChanged && !shouldUpdateDb,
        newCostPrice: costChanged ? (parsedCost ?? 0.0) : null,
        clearManualCostPrice:
            !_isTempOrUnregistered && !costChanged && !shouldUpdateDb,
        updateCatalogInDb: shouldUpdateDb,
        sellingPriceChanged: sellingChanged,
        costPriceChanged: costChanged,
      ),
    );
  }

  String _buildDbImpactSummary() {
    final parsedPrice = _parseArs(_priceController.text);
    final parsedCost = _parseArs(_costController.text);
    final sellingChanged =
        parsedPrice > 0 && (parsedPrice - _catalogBaseSellingPrice).abs() >= 0.005;
    final costChanged = _hasCostPriceChanged;

    if (!sellingChanged && !costChanged) {
      return 'Modificá el Precio de Venta y/o el Costo arriba para actualizar la Base de Datos.';
    }
    if (sellingChanged && !costChanged) {
      final costInfo = _catalogBaseCostPrice > 0
          ? 'El Costo (\$${_catalogBaseCostPrice.toArsInput()}) queda 100% intacto.'
          : 'El Costo no se modifica.';
      return 'Se guardará el nuevo Precio de Venta (\$${parsedPrice.toArsInput()}) en la Base de Datos. $costInfo';
    }
    if (sellingChanged && costChanged) {
      return 'Se guardarán en la Base de Datos el nuevo Precio de Venta (\$${parsedPrice.toArsInput()}) y el nuevo Costo (\$${parsedCost.toArsInput()}).';
    }
    return 'Se guardará el nuevo Costo (\$${parsedCost.toArsInput()}) en la Base de Datos (el Precio de Venta se mantiene en \$${_catalogBaseSellingPrice.toArsInput()}).';
  }

  @override
  Widget build(BuildContext context) {
    final originalName = widget.item.product.name;
    final showRestorePrices = !_isTempOrUnregistered &&
        (_hasSellingPriceChanged ||
            _hasCostPriceChanged ||
            widget.item.hasManualPriceOverride);

    return Focus(
      autofocus: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: SingleChildScrollView(
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
                            Text(
                              _isTempOrUnregistered
                                  ? 'Editar Ítem Rápido en Carrito'
                                  : 'Alias de Facturación / Ticket (Solo esta venta)',
                              style: const TextStyle(
                                fontSize: 15.5,
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
                  const SizedBox(height: 14),

                  // ── Sección de Precio de Venta, Costo y % Margen ──
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.price_change_outlined,
                              size: 17,
                              color: Colors.indigo.shade700,
                            ),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                'Precio de Venta y Rentabilidad',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ),
                            if (showRestorePrices)
                              TextButton.icon(
                                onPressed: _restoreCatalogPrices,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: const Icon(Icons.restore_rounded, size: 15),
                                label: Text(
                                  'Restaurar (\$${_catalogDefaultCartPrice.toArsInput()})',
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Precio de Venta Unitario
                            Expanded(
                              flex: 5,
                              child: TextFormField(
                                controller: _priceController,
                                focusNode: _priceFocus,
                                keyboardType: TextInputType.number,
                                inputFormatters: const [
                                  ArsThousandsInputFormatter(),
                                ],
                                onChanged: _onSellingPriceChanged,
                                onFieldSubmitted: (_) => _submit(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Precio Venta (\$)',
                                  prefixText: '\$ ',
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  isDense: true,
                                ),
                                validator: (val) {
                                  final parsed = _parseArs(val ?? '');
                                  if (parsed <= 0) {
                                    return 'Precio inválido';
                                  }
                                  if (_updateCatalogInDb &&
                                      !_isTempOrUnregistered) {
                                    final effectiveCost = _hasCostPriceChanged
                                        ? _parseArs(_costController.text)
                                        : _catalogBaseCostPrice;
                                    if (effectiveCost > 0 &&
                                        parsed < effectiveCost - 0.005) {
                                      return 'Menor al costo (\$${effectiveCost.toArsInput()})';
                                    }
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 8),

                            // 2. Precio de Costo (Ancla)
                            Expanded(
                              flex: 4,
                              child: TextFormField(
                                controller: _costController,
                                enabled: !widget.item.product.isCombo,
                                keyboardType: TextInputType.number,
                                inputFormatters: const [
                                  ArsThousandsInputFormatter(),
                                ],
                                onChanged: _onCostPriceChanged,
                                onFieldSubmitted: (_) => _submit(),
                                style: const TextStyle(fontSize: 13.5),
                                decoration: InputDecoration(
                                  labelText: widget.item.product.isCombo
                                      ? 'Costo Receta'
                                      : 'Costo (\$)',
                                  prefixText: '\$ ',
                                  hintText: '0',
                                  filled: true,
                                  fillColor: widget.item.product.isCombo
                                      ? Colors.grey.shade100
                                      : Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // 3. % de Margen
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: _marginController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true, signed: true),
                                onChanged: _onMarginChanged,
                                onFieldSubmitted: (_) => _submit(),
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.teal.shade800,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Margen %',
                                  suffixText: '%',
                                  hintText: '0',
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Switch: Solo esta venta vs Actualizar en Catálogo (Base de Datos)
                        if (!_isTempOrUnregistered) ...[
                          const SizedBox(height: 10),
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              setState(() {
                                _updateCatalogInDb = !_updateCatalogInDb;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: _updateCatalogInDb
                                    ? const Color(0xFFEFF6FF)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _updateCatalogInDb
                                      ? const Color(0xFF3B82F6)
                                      : const Color(0xFFCBD5E1),
                                  width: _updateCatalogInDb ? 1.4 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: Checkbox(
                                      value: _updateCatalogInDb,
                                      activeColor: const Color(0xFF2563EB),
                                      onChanged: (val) {
                                        setState(() {
                                          _updateCatalogInDb = val ?? false;
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '💾 Actualizar precio/costo permanentemente en el Catálogo (BD)',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: _updateCatalogInDb
                                                ? const Color(0xFF1D4ED8)
                                                : const Color(0xFF334155),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _updateCatalogInDb
                                              ? _buildDbImpactSummary()
                                              : 'Desmarcado: cualquier cambio de precio o costo aplica SOLO a esta venta.',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: _updateCatalogInDb
                                                ? const Color(0xFF1E40AF)
                                                : const Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
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

                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancelar (Esc)'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _submit,
                        icon: Icon(
                          _updateCatalogInDb
                              ? Icons.save_rounded
                              : Icons.check_rounded,
                          size: 18,
                        ),
                        label: Text(
                          _updateCatalogInDb
                              ? 'Aplicar y Guardar en BD (Enter)'
                              : 'Aplicar en Comprobante (Enter)',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _updateCatalogInDb
                              ? const Color(0xFF2563EB)
                              : const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
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
