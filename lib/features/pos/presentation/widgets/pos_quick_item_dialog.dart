import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/core/utils/scale_serial_service.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

class PosQuickItemDialog extends StatefulWidget {
  final PriceTier activeTier;
  final double wholesaleFactor;
  final double cardFactor;
  final double customFactor;
  final String? customTierLabel;

  const PosQuickItemDialog({
    super.key,
    this.activeTier = PriceTier.base,
    this.wholesaleFactor = 1.0,
    this.cardFactor = 1.0,
    this.customFactor = 1.0,
    this.customTierLabel,
  });

  static Future<CartItem?> show(
    BuildContext context, {
    PriceTier activeTier = PriceTier.base,
    double wholesaleFactor = 1.0,
    double cardFactor = 1.0,
    double customFactor = 1.0,
    String? customTierLabel,
  }) {
    return showDialog<CartItem>(
      context: context,
      barrierDismissible: true,
      builder: (_) => PosQuickItemDialog(
        activeTier: activeTier,
        wholesaleFactor: wholesaleFactor,
        cardFactor: cardFactor,
        customFactor: customFactor,
        customTierLabel: customTierLabel,
      ),
    );
  }

  @override
  State<PosQuickItemDialog> createState() => _PosQuickItemDialogState();
}

class _PosQuickItemDialogState extends State<PosQuickItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _detailsController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _priceController = TextEditingController();
  final _costController = TextEditingController();
  final _marginController = TextEditingController();

  final _nameFocus = FocusNode();
  final _priceFocus = FocusNode();
  final _quantityFocus = FocusNode();

  bool _isComboMode = false;
  bool _isServiceMode = false;
  bool _saveToCatalog = false;
  bool _isSoldByWeight = false;
  bool _isReadingScale = false;
  double _ivaRate = 21.0;
  bool _isUpdatingCalc = false;
  String? _priceAnchor; // 'cost' | 'selling'
  bool _costIsAuto = false;
  bool _priceIsAuto = false;

  Future<void> _readWeightFromScale(String comPort) async {
    final trimmedPort = comPort.trim();
    if (trimmedPort.isEmpty) {
      showTerminalPeripheralsDialog(context);
      return;
    }
    if (_isReadingScale) return;
    setState(() => _isReadingScale = true);
    try {
      final result = await ScaleSerialService.instance.readWeight(trimmedPort);
      if (!mounted) return;
      if (result.success && result.weightKg != null) {
        final weightStr = result.weightKg!.toStringAsFixed(3);
        setState(() {
          _quantityController.text = weightStr;
          _quantityController.selection = TextSelection.fromPosition(
            TextPosition(offset: weightStr.length),
          );
        });
        SnackBarService.success(context, 'Lectura exitosa: $weightStr Kg');
      } else {
        SnackBarService.error(
          context,
          result.errorMessage ?? 'No se pudo obtener el peso de la balanza.',
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarService.error(context, 'Error al comunicar con la balanza: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isReadingScale = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleDialogKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _nameFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleDialogKey);
    _nameController.dispose();
    _detailsController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    _costController.dispose();
    _marginController.dispose();
    _nameFocus.dispose();
    _priceFocus.dispose();
    _quantityFocus.dispose();
    super.dispose();
  }

  double _parseArs(String text) => ArsThousandsInputFormatter.parse(text);

  double _parseDouble(String text) {
    final normalized = text.trim().replaceAll(',', '.');
    return double.tryParse(normalized) ?? 0.0;
  }

  void _onSellingPriceChanged(String val) {
    if (_isUpdatingCalc) return;
    _isUpdatingCalc = true;
    _priceIsAuto = false;
    final price = _parseArs(val);
    final marginStr = _marginController.text.trim();
    final costStr = _costController.text.trim();
    final margin = _parseDouble(marginStr);
    final cost = _parseArs(costStr);

    if (val.trim().isEmpty) {
      if (_costIsAuto) {
        _costController.clear();
        _costIsAuto = false;
      }
      if (_priceAnchor == 'selling') {
        _priceAnchor = costStr.isNotEmpty ? 'cost' : null;
      }
    } else if (price > 0) {
      if (costStr.isEmpty || _costIsAuto) {
        _priceAnchor = 'selling';
        if (marginStr.isNotEmpty && margin > -100) {
          final calcCost = price / (1.0 + (margin / 100.0));
          _costController.text = calcCost.toArsInput();
          _costIsAuto = true;
        }
      } else if (cost > 0) {
        final calcMargin = ((price - cost) / cost) * 100.0;
        _marginController.text = calcMargin.toCleanMargin();
        _priceAnchor = 'selling';
      }
    }
    _isUpdatingCalc = false;
    setState(() {});
  }

  void _onMarginChanged(String val) {
    if (_isUpdatingCalc) return;
    _isUpdatingCalc = true;
    final marginStr = val.trim();
    final priceStr = _priceController.text.trim();
    final costStr = _costController.text.trim();

    if (marginStr.isEmpty) {
      if (_costIsAuto) {
        _costController.clear();
        _costIsAuto = false;
      }
      if (_priceIsAuto) {
        _priceController.clear();
        _priceIsAuto = false;
      }
      _isUpdatingCalc = false;
      setState(() {});
      return;
    }

    final margin = _parseDouble(marginStr);
    final price = _parseArs(priceStr);
    final cost = _parseArs(costStr);

    if ((_priceAnchor == 'selling' || costStr.isEmpty || _costIsAuto) &&
        price > 0 &&
        !_priceIsAuto &&
        margin > -100) {
      final calcCost = price / (1.0 + (margin / 100.0));
      _costController.text = calcCost.toArsInput();
      _costIsAuto = true;
    } else if (cost > 0) {
      final calcPrice = cost * (1.0 + (margin / 100.0));
      _priceController.text = calcPrice.toArsInput();
      _priceIsAuto = true;
    }
    _isUpdatingCalc = false;
    setState(() {});
  }

  void _onCostChanged(String val) {
    if (_isUpdatingCalc) return;
    _isUpdatingCalc = true;
    _costIsAuto = false;
    final costStr = val.trim();
    final priceStr = _priceController.text.trim();
    final marginStr = _marginController.text.trim();
    final cost = _parseArs(costStr);
    final price = _parseArs(priceStr);
    final margin = _parseDouble(marginStr);

    if (costStr.isEmpty) {
      if (_priceIsAuto) {
        _priceController.clear();
        _priceIsAuto = false;
      }
      if (_priceAnchor == 'cost') {
        _priceAnchor = priceStr.isNotEmpty ? 'selling' : null;
      }
    } else if (cost > 0) {
      if (priceStr.isEmpty || _priceIsAuto) {
        _priceAnchor = 'cost';
        if (marginStr.isNotEmpty) {
          final calcPrice = cost * (1.0 + (margin / 100.0));
          _priceController.text = calcPrice.toArsInput();
          _priceIsAuto = true;
        }
      } else if (price > 0) {
        final calcMargin = ((price - cost) / cost) * 100.0;
        _marginController.text = calcMargin.toCleanMargin();
        _priceAnchor = 'cost';
      }
    }
    _isUpdatingCalc = false;
    setState(() {});
  }

  bool _isSubmitted = false;

  /// Atajos globales del diálogo, independientes del campo que tenga el foco:
  /// - Esc → Cancelar y cerrar.
  /// - Enter / NumpadEnter → Agregar al carrito (Shift+Enter: salto de línea en Notas).
  ///   Si se presiona en la Descripción con el precio aún vacío, salta al Precio.
  bool _handleDialogKey(KeyEvent event) {
    if (!mounted || _isSubmitted) return false;
    if (event is! KeyDownEvent) return false;
    // Si hay un menú desplegable (ej. IVA) abierto encima, no interceptar.
    if (ModalRoute.of(context)?.isCurrent != true) return false;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return true;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed) return false;

      if (_nameFocus.hasFocus &&
          _nameController.text.trim().isNotEmpty &&
          _priceController.text.trim().isEmpty) {
        _priceFocus.requestFocus();
        return true;
      }
      _submit();
      return true;
    }
    return false;
  }

  void _submit() {
    if (_isSubmitted) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _isSubmitted = true;

    final name = _nameController.text.trim();
    final details = _detailsController.text.trim();
    final qty = _parseDouble(_quantityController.text);
    final sellingPrice = _parseArs(_priceController.text);
    final costPrice = _parseArs(_costController.text);

    final product = Product(
      id: 0, // ID 0 identifica producto temporal o alta on-the-fly pendiente de persistir
      name: name,
      internalCode: _isComboMode
          ? 'COMBO-POS'
          : (_isServiceMode ? 'SERV-POS' : 'TEMP-POS'),
      costPrice: costPrice >= 0 ? costPrice : 0.0,
      sellingPrice: sellingPrice,
      stock: 0.0,
      active: true,
      isSoldByWeight: _isServiceMode ? false : _isSoldByWeight,
      isCombo: _isComboMode,
      isService: _isServiceMode,
      unitType: (!_isServiceMode && _isSoldByWeight) ? 'kg' : 'un',
      ivaRate: _ivaRate,
      needsCatalogReview: _saveToCatalog,
    );

    final cartItem = CartItem(
      product: product,
      quantity: qty > 0 ? qty : 1.0,
      activeTier: PriceTier.base, // El precio ingresado en mostrador ya es el precio final pactado
      wholesaleFactor: 1.0,
      cardFactor: 1.0,
      customFactor: 1.0,
      isTemporary: !_saveToCatalog,
      saveToCatalog: _saveToCatalog,
      customDescription: name,
      customDetails: details.isNotEmpty ? details : null,
    );

    Navigator.of(context).pop(cartItem);
  }

  @override
  Widget build(BuildContext context) {
    final isResponsableInscripto =
        context.watch<SettingsProvider?>()?.settings?.isResponsableInscripto ?? false;
    final qty = _parseDouble(_quantityController.text);
    final unitPrice = _parseArs(_priceController.text);
    final previewSubtotal = ((qty > 0 ? qty : 0.0) * (unitPrice > 0 ? unitPrice : 0.0));

    return Focus(
      autofocus: false,
      child: Dialog(
        alignment: Alignment.center,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _isComboMode
                                ? Colors.deepPurple.shade50
                                : (_isServiceMode
                                    ? Colors.teal.shade50
                                    : Colors.amber.shade50),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: Icon(
                              _isComboMode
                                  ? Icons.layers_rounded
                                  : (_isServiceMode
                                      ? Icons.work_outline_rounded
                                      : Icons.flash_on_rounded),
                              key: ValueKey<String>(
                                _isComboMode
                                    ? 'icon_combo'
                                    : (_isServiceMode ? 'icon_service' : 'icon_product'),
                              ),
                              color: _isComboMode
                                  ? Colors.deepPurple.shade700
                                  : (_isServiceMode
                                      ? Colors.teal.shade700
                                      : Colors.amber.shade800),
                              size: 24,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                layoutBuilder: (currentChild, previousChildren) => Stack(
                                  alignment: Alignment.centerLeft,
                                  children: <Widget>[
                                    ...previousChildren,
                                    if (currentChild != null) currentChild,
                                  ],
                                ),
                                child: Text(
                                  _isComboMode
                                      ? 'Combo / Oferta Rápida en Mostrador'
                                      : (_isServiceMode
                                          ? 'Servicio / Honorario en Mostrador'
                                          : 'Producto Rápido en Mostrador'),
                                  key: ValueKey<String>(
                                    _isComboMode
                                        ? 'title_combo'
                                        : (_isServiceMode ? 'title_service' : 'title_product'),
                                  ),
                                  style: const TextStyle(
                                    fontSize: 17.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Se imprime en Ticket Térmico, PDF A4 y Factura Fiscal ARCA/AFIP',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
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

                    // Selector Modo: Producto Rápido vs Servicio vs Combo Rápido
                    SegmentedButton<String>(
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                        backgroundColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            if (_isComboMode) return Colors.deepPurple.shade50;
                            if (_isServiceMode) return Colors.teal.shade50;
                            return const Color(0xFFEFF6FF);
                          }
                          return const Color(0xFFF8FAFC);
                        }),
                        foregroundColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            if (_isComboMode) return Colors.deepPurple.shade800;
                            if (_isServiceMode) return Colors.teal.shade800;
                            return const Color(0xFF1D4ED8);
                          }
                          return const Color(0xFF475569);
                        }),
                        side: WidgetStatePropertyAll(
                          BorderSide(color: Colors.blueGrey.shade200),
                        ),
                      ),
                      segments: const [
                        ButtonSegment<String>(
                          value: 'product',
                          icon: Icon(Icons.bolt_rounded, size: 16),
                          label: Text(
                            'Producto Rápido',
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                        ButtonSegment<String>(
                          value: 'service',
                          icon: Icon(Icons.work_outline_rounded, size: 16),
                          label: Text(
                            'Servicio / Honorario',
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                        ButtonSegment<String>(
                          value: 'combo',
                          icon: Icon(Icons.inventory_2_outlined, size: 16),
                          label: Text(
                            'Combo / Promoción',
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                      selected: {
                        _isComboMode
                            ? 'combo'
                            : (_isServiceMode ? 'service' : 'product')
                      },
                      onSelectionChanged: (selection) {
                        final mode = selection.first;
                        setState(() {
                          _isComboMode = mode == 'combo';
                          _isServiceMode = mode == 'service';
                          if (_isServiceMode) {
                            _isSoldByWeight = false;
                            _costController.clear();
                            _marginController.clear();
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Nombre / Descripción para Factura y Ticket
                    TextFormField(
                      controller: _nameController,
                      focusNode: _nameFocus,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) => _priceFocus.requestFocus(),
                      decoration: InputDecoration(
                        labelText: _isComboMode
                            ? 'Nombre del Combo / Promoción *'
                            : (_isServiceMode
                                ? 'Descripción del Servicio / Honorario *'
                                : 'Descripción del Producto *'),
                        hintText: _isComboMode
                            ? 'Ej: Combo Asado Familiar / Promo 2x1...'
                            : (_isServiceMode
                                ? 'Ej: Honorarios Monotributo / Consulta Profesional...'
                                : 'Ej: Mercadería recién ingresada / Artículo varios...'),
                        prefixIcon: const Icon(Icons.description_outlined, size: 20),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        isDense: true,
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Ingresa una descripción para el comprobante';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Notas / Detalles / Sub-ítems del Combo
                    TextFormField(
                      controller: _detailsController,
                      minLines: 1,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: _isComboMode
                            ? 'Detalle de artículos incluidos (Opcional — sale en ticket/factura)'
                            : (_isServiceMode
                                ? 'Período / Expediente / Detalle para Factura (Opcional)'
                                : 'Notas adicionales para Factura / Ticket (Opcional)'),
                        hintText: _isComboMode
                            ? 'Ej: Incluye 1 Coca-Cola 2.25L + 2 Doc. Empanadas'
                            : (_isServiceMode
                                ? 'Ej: Período Mensual Noviembre 2026 / Expte. N° 4182'
                                : 'Ej: Marca / Medida / Observación solicitada por el cliente'),
                        prefixIcon: const Icon(Icons.notes_rounded, size: 20),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Fila: Precio Unitario + Cantidad + Unidad
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: TextFormField(
                            controller: _priceController,
                            focusNode: _priceFocus,
                            keyboardType: TextInputType.number,
                            inputFormatters: const [
                              ArsThousandsInputFormatter(),
                            ],
                            textInputAction: TextInputAction.next,
                            onChanged: _onSellingPriceChanged,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: _isServiceMode
                                  ? 'Importe / Honorario Unit. *'
                                  : 'Precio Venta Unit. *',
                              prefixText: '\$ ',
                              prefixIcon: const Icon(Icons.attach_money_rounded, size: 20),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              isDense: true,
                            ),
                            validator: (val) {
                              final p = _parseArs(val ?? '');
                              if (p <= 0) {
                                return 'Ingresa un precio > 0';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _quantityController,
                            focusNode: _quantityFocus,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setState(() {}),
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: _isSoldByWeight ? 'Peso (Kg) *' : 'Cantidad *',
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              isDense: true,
                              suffixIcon: _isSoldByWeight
                                  ? Consumer<LocalTerminalProvider>(
                                      builder: (ctx, localTerminal, _) {
                                        final comPort = localTerminal.scaleComPort;
                                        final isConfigured = comPort.trim().isNotEmpty;
                                        return IconButton(
                                          tooltip: isConfigured
                                              ? 'Leer peso desde Balanza ($comPort)'
                                              : 'Configurar puerto COM de Balanza',
                                          onPressed: _isReadingScale
                                              ? null
                                              : () => _readWeightFromScale(comPort),
                                          icon: _isReadingScale
                                              ? const SizedBox(
                                                  width: 15,
                                                  height: 15,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                )
                                              : Icon(
                                                  Icons.scale_rounded,
                                                  size: 18,
                                                  color: isConfigured
                                                      ? Colors.indigo.shade700
                                                      : Colors.blueGrey.shade400,
                                                ),
                                        );
                                      },
                                    )
                                  : null,
                            ),
                            validator: (val) {
                              final q = _parseDouble(val ?? '');
                              if (q <= 0) {
                                return '> 0';
                              }
                              return null;
                            },
                          ),
                        ),
                        if (isResponsableInscripto) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<double>(
                              isExpanded: true,
                              initialValue: _ivaRate,
                              decoration: InputDecoration(
                                labelText: 'IVA AFIP',
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                isDense: true,
                              ),
                              items: const [
                                DropdownMenuItem(value: 21.0, child: Text('21%', overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 10.5, child: Text('10.5%', overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 27.0, child: Text('27%', overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 0.0, child: Text('0% Ex.', overflow: TextOverflow.ellipsis)),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => _ivaRate = v);
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Panel Contextual con Expansión Suave hacia abajo: Costo y Margen (Productos/Combos) vs Ficha Fiscal (Servicios)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                          child: !_isServiceMode
                              ? Container(
                                  key: const ValueKey<String>('quick_item_cost_panel'),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(minHeight: 32),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.calculate_outlined, size: 16, color: Color(0xFF475569)),
                                            const SizedBox(width: 6),
                                            const Expanded(
                                              child: Text(
                                                'Costo y Margen (Opcional · Cálculo Automático)',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF475569),
                                                ),
                                              ),
                                            ),
                                            if (!_isComboMode) ...[
                                              ChoiceChip(
                                                label: const Text('Por Peso (Kg)', style: TextStyle(fontSize: 11)),
                                                selected: _isSoldByWeight,
                                                visualDensity: VisualDensity.compact,
                                                onSelected: (v) => setState(() => _isSoldByWeight = v),
                                              ),
                                              if (_isSoldByWeight) ...[
                                                const SizedBox(width: 6),
                                                Consumer<LocalTerminalProvider>(
                                                  builder: (ctx, localTerminal, _) {
                                                    final comPort = localTerminal.scaleComPort;
                                                    final isConfigured = comPort.trim().isNotEmpty;
                                                    return OutlinedButton.icon(
                                                      onPressed: _isReadingScale
                                                          ? null
                                                          : () => _readWeightFromScale(comPort),
                                                      icon: const Icon(Icons.scale_rounded, size: 14),
                                                      label: Text(
                                                        isConfigured ? 'Leer Balanza' : 'Config. Balanza',
                                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                                      ),
                                                      style: OutlinedButton.styleFrom(
                                                        visualDensity: VisualDensity.compact,
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                        foregroundColor: isConfigured ? Colors.indigo.shade700 : Colors.blueGrey,
                                                        side: BorderSide(
                                                          color: isConfigured ? Colors.indigo.shade300 : Colors.blueGrey.shade300,
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ],
                                            ] else
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.deepPurple.shade50,
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: Colors.deepPurple.shade200),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.layers_outlined, size: 13, color: Colors.deepPurple.shade700),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Pack / Promo',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w700,
                                                        color: Colors.deepPurple.shade800,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextFormField(
                                              controller: _costController,
                                              keyboardType: TextInputType.number,
                                              inputFormatters: const [
                                                ArsThousandsInputFormatter(),
                                              ],
                                              onChanged: _onCostChanged,
                                              decoration: InputDecoration(
                                                labelText: 'Precio de Costo (Opcional)',
                                                hintText: '0',
                                                prefixText: '\$ ',
                                                filled: true,
                                                fillColor: Colors.white,
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                isDense: true,
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: TextFormField(
                                              controller: _marginController,
                                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              onChanged: _onMarginChanged,
                                              decoration: InputDecoration(
                                                labelText: '% Ganancia s/Costo',
                                                hintText: 'Ej: 30',
                                                suffixText: '%',
                                                filled: true,
                                                fillColor: Colors.white,
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                isDense: true,
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                )
                              : Container(
                                  key: const ValueKey<String>('quick_item_service_panel'),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.shade50.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.teal.shade200),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(minHeight: 32),
                                        child: Row(
                                          children: [
                                            Icon(Icons.verified_outlined, size: 16, color: Colors.teal.shade800),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                'Modalidad Servicio / Honorario (AFIP Concepto 2)',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.teal.shade900,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.teal.shade300),
                                              ),
                                              child: Text(
                                                'Sin Stock Físico',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.teal.shade800,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(minHeight: 42),
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            'No descuenta inventario ni requiere costo de reposición. En Facturas A, B y C informa automáticamente el período facturado reglamentario ante ARCA/AFIP.',
                                            style: TextStyle(
                                              fontSize: 11.8,
                                              height: 1.35,
                                              color: Colors.teal.shade900,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                    ),

                    // Toggle: Guardar permanentemente en el catálogo vs Solo por esta venta
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        color: _saveToCatalog
                            ? const Color(0xFFEFF6FF)
                            : const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _saveToCatalog
                              ? const Color(0xFF93C5FD)
                              : const Color(0xFFFDE68A),
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: SwitchListTile(
                          dense: true,
                          value: _saveToCatalog,
                          onChanged: (val) => setState(() => _saveToCatalog = val),
                          title: Text(
                            _saveToCatalog
                                ? (_isServiceMode
                                    ? 'Guardar Servicio / Honorario en el Catálogo'
                                    : 'Guardar permanentemente en el Catálogo')
                                : 'Ítem Temporal (Solo para esta venta)',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: _saveToCatalog
                                  ? const Color(0xFF1E3A8A)
                                  : const Color(0xFF92400E),
                            ),
                          ),
                          subtitle: Text(
                            _saveToCatalog
                                ? (_isServiceMode
                                    ? 'Quedará disponible en el Catálogo como Servicio sin requerir ni descontar stock físico.'
                                    : 'Se creará automáticamente en Productos (marcado "Pendiente de revisión" para completar código/rubro luego).')
                                : 'No altera el catálogo de productos ni bloquea stock. Queda registrado en el historial, ticket y factura.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: _saveToCatalog
                                  ? const Color(0xFF1D4ED8)
                                  : const Color(0xFFB45309),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                  // Footer con Subtotal + Botones
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'SUBTOTAL LÍNEA',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          Text(
                            '\$${previewSubtotal.toArsInput()}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancelar (Esc)'),
                          ),
                          ElevatedButton.icon(
                            onPressed: _submit,
                            icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                            label: const Text('Agregar al Carrito (Enter)'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}
