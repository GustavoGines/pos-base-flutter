import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:frontend_desktop/core/constants/app_permissions.dart';
import 'package:frontend_desktop/core/presentation/widgets/compact_date_range_picker_dialog.dart';
import 'package:frontend_desktop/core/presentation/widgets/searchable_select_field.dart';
import 'package:frontend_desktop/core/services/remote_scanner_service.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import '../../../auth/presentation/widgets/admin_pin_dialog.dart';
import '../../data/models/product_batch_model.dart';
import '../../data/models/production_order_model.dart';
import '../../domain/entities/product.dart';
import '../providers/catalog_provider.dart';
import 'expired_batches_sweep_dialog.dart';
import 'print_labels_dialog.dart';

class _DraftIngredientLine {
  final int productId;
  final String name;
  final String unitType;
  final double currentStock;
  final double unitCost;
  final bool trackBatches;
  final TextEditingController qtyCtrl;

  _DraftIngredientLine({
    required this.productId,
    required this.name,
    required this.unitType,
    required this.currentStock,
    required this.unitCost,
    required this.trackBatches,
    required double initialQty,
  }) : qtyCtrl = TextEditingController(text: initialQty.toQty());

  void dispose() => qtyCtrl.dispose();
}

/// Workspace de Producción Propia (Cocina / Pastelería) y Reporte de Mermas.
/// Permite hornear / elaborar lotes desde recetas (o sub-recetas multi-nivel),
/// descontando materias primas automáticamente por FEFO y emitiendo etiqueta térmica de lote.
class ProductionOrdersDialog extends StatefulWidget {
  final CatalogProvider provider;
  final Product? initialProduct;
  final int initialTabIndex;
  final int? filterIngredientProductId;
  final int? initialExplicitBatchId;
  final String? initialExplicitBatchCode;
  final double? initialExplicitBatchAvailableQty;

  const ProductionOrdersDialog({
    super.key,
    required this.provider,
    this.initialProduct,
    this.initialTabIndex = 0,
    this.filterIngredientProductId,
    this.initialExplicitBatchId,
    this.initialExplicitBatchCode,
    this.initialExplicitBatchAvailableQty,
  });

  @override
  State<ProductionOrdersDialog> createState() => _ProductionOrdersDialogState();
}

class _ProductionOrdersDialogState extends State<ProductionOrdersDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  // ── Catalog cache para combos/recetas e insumos ──
  List<Product> _eligibleTargets = [];
  final Map<int, Product> _remoteTargetPool = {};
  Product? _sourceTransformProduct;
  bool _loadingCatalog = true;
  bool _usingTransformFallback = false;

  // ── Modo Planilla Rápida Matutina vs Individual ──
  bool _batchMode = false;
  bool _batchOnlyRecipes = true;
  bool _batchOnlySelected = false;
  final TextEditingController _batchSearchCtrl = TextEditingController();
  final Map<int, TextEditingController> _batchQtyCtrls = {};
  final Map<int, TextEditingController> _batchValidityDaysCtrls = {};
  final TextEditingController _batchGlobalDaysCtrl = TextEditingController();
  int? _batchDefaultValidityDays;
  DateTime? _batchGlobalExpirationDate;

  // ── Tab 1: Nueva Elaboración (Individual) ──
  Product? _selectedTarget;
  final TextEditingController _qtyProducedCtrl = TextEditingController(text: '1');
  final TextEditingController _batchCodeCtrl = TextEditingController();
  final TextEditingController _singleValidityDaysCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();
  DateTime _manufacturedAt = DateTime.now();
  DateTime? _expirationDate;
  bool _allowDeficit = true;
  bool _submittingOrder = false;
  final List<_DraftIngredientLine> _ingredientLines = [];

  // ── Tab 2: Historial Órdenes ──
  List<ProductionOrderModel> _orders = [];
  bool _loadingOrders = true;
  String? _ordersError;
  String _statusFilter = '';
  final TextEditingController _ordersSearchCtrl = TextEditingController();

  // ── Tab 3: Reporte de Mermas ──
  DateTimeRange _wasteRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );
  Map<String, dynamic>? _wasteData;
  bool _loadingWaste = true;
  String? _wasteError;
  final TextEditingController _wasteSearchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _batchSearchCtrl.dispose();
    for (final c in _batchQtyCtrls.values) {
      c.dispose();
    }
    for (final c in _batchValidityDaysCtrls.values) {
      c.dispose();
    }
    _batchGlobalDaysCtrl.dispose();
    _qtyProducedCtrl.dispose();
    _batchCodeCtrl.dispose();
    _singleValidityDaysCtrl.dispose();
    _notesCtrl.dispose();
    _ordersSearchCtrl.dispose();
    _wasteSearchCtrl.dispose();
    for (final line in _ingredientLines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _loadCatalogTargets(),
      _loadOrders(),
      _loadWasteReport(),
    ]);
  }

  bool _isEligibleTargetProduct(Product p) {
    if (p.isCombo || p.isService || !p.active) return false;
    if (widget.filterIngredientProductId == null) return true;
    if (_usingTransformFallback) {
      return p.id != widget.filterIngredientProductId;
    }
    return p.recipeIngredients?.any((raw) {
          final ingId = (raw['ingredient_product_id'] as num?)?.toInt() ??
              (raw['id'] as num?)?.toInt();
          return ingId == widget.filterIngredientProductId;
        }) ??
        false;
  }

  Future<void> _loadCatalogTargets() async {
    setState(() => _loadingCatalog = true);
    try {
      List<Product> results = const [];
      try {
        results = await widget.provider.fetchAllActiveProductsForProduction();
      } catch (_) {
        results = const [];
      }
      final combined = <int, Product>{
        for (final p in widget.provider.products) p.id: p,
        for (final p in results) p.id: p,
        for (final p in _remoteTargetPool.values) p.id: p,
        if (widget.initialProduct != null) widget.initialProduct!.id: widget.initialProduct!,
      };
      if (widget.filterIngredientProductId != null) {
        _sourceTransformProduct = combined[widget.filterIngredientProductId!] ??
            await widget.provider.resolveProductById(widget.filterIngredientProductId!);
      }
      _usingTransformFallback = false;
      var targets = combined.values
          .where(_isEligibleTargetProduct)
          .toList();
      // Fallback en modo Transformación/Re-elaboración: si ninguna receta previa incluye aún este lote/producto,
      // habilitar todos los productos elegibles activos distintos del insumo origen para permitir re-elaboración directa.
      if (targets.isEmpty && widget.filterIngredientProductId != null) {
        _usingTransformFallback = true;
        targets = combined.values
            .where(_isEligibleTargetProduct)
            .toList();
      }
      targets.sort((a, b) {
        if (a.hasProductionRecipe != b.hasProductionRecipe) {
          return a.hasProductionRecipe ? -1 : 1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      if (mounted) {
        setState(() {
          _eligibleTargets = targets;
          _loadingCatalog = false;
          for (final p in targets) {
            final existingCtrl = _batchValidityDaysCtrls[p.id];
            if (existingCtrl != null &&
                existingCtrl.text.trim().isEmpty &&
                p.vencimientoDias != null &&
                p.vencimientoDias! > 0) {
              existingCtrl.text = p.vencimientoDias.toString();
            }
          }
        });
        final preselect = widget.initialProduct ??
            targets.cast<Product?>().firstWhere(
                  (p) => p != null && p.hasProductionRecipe,
                  orElse: () => targets.isNotEmpty ? targets.first : null,
                );
        if (preselect != null) {
          _selectTargetProduct(preselect);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCatalog = false);
    }
  }

  void _selectTargetProduct(Product? target) {
    for (final l in _ingredientLines) {
      l.dispose();
    }
    _ingredientLines.clear();

    _selectedTarget = target;
    if (target == null) {
      _singleValidityDaysCtrl.clear();
      _expirationDate = null;
      setState(() {});
      return;
    }

    final yieldQty = target.recipeYieldQuantity > 0 ? target.recipeYieldQuantity : 1.0;
    _qtyProducedCtrl.text = yieldQty.toQty();
    if (target.vencimientoDias != null && target.vencimientoDias! > 0) {
      _singleValidityDaysCtrl.text = target.vencimientoDias.toString();
      _expirationDate = _manufacturedAt.add(Duration(days: target.vencimientoDias!));
    } else {
      _singleValidityDaysCtrl.clear();
      _expirationDate = null;
    }

    if (target.recipeIngredients != null) {
      for (final raw in target.recipeIngredients!) {
        final ingId = (raw['ingredient_product_id'] as num?)?.toInt() ??
            (raw['id'] as num?)?.toInt() ??
            0;
        if (ingId <= 0) continue;
        final baseQty = double.tryParse(raw['quantity']?.toString() ?? '1') ?? 1.0;
        final wastePct = double.tryParse(raw['waste_pct']?.toString() ?? '0') ?? 0.0;
        final adjustedQty = baseQty * (1.0 + (wastePct / 100.0));
        _ingredientLines.add(
          _DraftIngredientLine(
            productId: ingId,
            name: raw['name']?.toString() ?? 'Insumo',
            unitType: raw['unit_type']?.toString() ?? 'un',
            currentStock: double.tryParse(raw['stock']?.toString() ?? '0') ?? 0.0,
            unitCost: double.tryParse(raw['cost_price']?.toString() ?? '0') ?? 0.0,
            trackBatches: raw['track_batches'] == true || raw['track_batches'] == 1,
            initialQty: adjustedQty,
          ),
        );
      }
    }
    if (widget.filterIngredientProductId != null &&
        _sourceTransformProduct != null &&
        !_ingredientLines.any((l) => l.productId == widget.filterIngredientProductId)) {
      final src = _sourceTransformProduct!;
      final explicitAvail = widget.initialExplicitBatchAvailableQty;
      final defaultQty = (explicitAvail != null && explicitAvail > 0)
          ? math.min(1.0, explicitAvail)
          : 1.0;
      _ingredientLines.add(
        _DraftIngredientLine(
          productId: src.id,
          name: src.name,
          unitType: src.unitType,
          currentStock: explicitAvail ?? src.stock,
          unitCost: src.costPrice,
          trackBatches: src.trackBatches,
          initialQty: defaultQty,
        ),
      );
    }
    setState(() {});
  }

  void _rescaleRecipeQuantities(double newProducedQty) {
    final target = _selectedTarget;
    if (target == null ||
        target.recipeIngredients == null ||
        target.recipeIngredients!.isEmpty ||
        newProducedQty <= 0) {
      return;
    }
    final yieldQty = target.recipeYieldQuantity > 0 ? target.recipeYieldQuantity : 1.0;
    final factor = newProducedQty / yieldQty;

    for (final line in _ingredientLines) {
      final raw = target.recipeIngredients!.cast<Map<String, dynamic>?>().firstWhere(
            (r) =>
                r != null &&
                ((r['ingredient_product_id'] as num?)?.toInt() ??
                        (r['id'] as num?)?.toInt()) ==
                    line.productId,
            orElse: () => null,
          );
      if (raw != null) {
        final baseQty = double.tryParse(raw['quantity']?.toString() ?? '1') ?? 1.0;
        final wastePct = double.tryParse(raw['waste_pct']?.toString() ?? '0') ?? 0.0;
        final scaled = baseQty * (1.0 + (wastePct / 100.0)) * factor;
        line.qtyCtrl.text = (scaled * 1000).round() / 1000 == scaled.roundToDouble()
            ? scaled.round().toString()
            : ((scaled * 1000).round() / 1000).toString();
      }
    }
    setState(() {});
  }

  Future<void> _addExtraIngredientDialog() async {
    final pool = <int, Product>{
      for (final p in widget.provider.products) p.id: p,
      for (final p in _eligibleTargets) p.id: p,
      for (final p in _remoteTargetPool.values) p.id: p,
    };
    if (pool.length <= 40) {
      try {
        final all = await widget.provider.fetchAllActiveProductsForProduction();
        for (final p in all) {
          pool[p.id] = p;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    bool isEligibleIngredient(Product p) =>
        !p.isCombo &&
        !p.isService &&
        p.active &&
        p.id != _selectedTarget?.id &&
        !_ingredientLines.any((l) => l.productId == p.id);

    SearchableSelectOption<int> buildOption(Product p) => SearchableSelectOption<int>(
          value: p.id,
          label: p.name,
          subtitle: 'Stock: ${p.stock.toQty()} ${p.unitType} • Costo: \$${p.costPrice.toCurrency()}',
          badgeText: p.trackBatches ? 'CON LOTES' : null,
          searchKeywords: [
            p.internalCode,
            if (p.barcode != null && p.barcode!.isNotEmpty) p.barcode!,
          ],
        );

    final options = pool.values.where(isEligibleIngredient).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final pickedId = await SearchableSelectField.showPickerModal<int>(
      context,
      title: 'Agregar Insumo / Semi-Elaborado',
      searchHintText: 'Buscar o pistolear insumo (barras / PLU / nombre)...',
      options: options.map(buildOption).toList(),
      onRemoteSearch: (q) async {
        final remote = await widget.provider.searchProductsRemote(q, perPage: 80);
        final matched = <SearchableSelectOption<int>>[];
        for (final p in remote) {
          pool[p.id] = p;
          if (isEligibleIngredient(p)) {
            matched.add(buildOption(p));
          }
        }
        return matched;
      },
    );

    if (pickedId != null && mounted) {
      final p = pool[pickedId];
      if (p != null) {
        setState(() {
          _ingredientLines.add(
            _DraftIngredientLine(
              productId: p.id,
              name: p.name,
              unitType: p.unitType,
              currentStock: p.stock,
              unitCost: p.costPrice,
              trackBatches: p.trackBatches,
              initialQty: 1.0,
            ),
          );
        });
      }
    }
  }

  double get _estimatedTotalCost {
    if (_ingredientLines.isEmpty) {
      final producedQty =
          double.tryParse(_qtyProducedCtrl.text.replaceAll(',', '.').trim()) ?? 1.0;
      final targetCost = _selectedTarget?.costPrice ?? 0.0;
      return (producedQty > 0 ? producedQty : 0.0) * targetCost;
    }
    double sum = 0.0;
    for (final line in _ingredientLines) {
      final q = double.tryParse(line.qtyCtrl.text.replaceAll(',', '.').trim()) ?? 0.0;
      if (q > 0) sum += q * line.unitCost;
    }
    return sum;
  }

  TextEditingController _ctrlForBatchProduct(int productId) {
    return _batchQtyCtrls.putIfAbsent(productId, () => TextEditingController());
  }

  TextEditingController _validityCtrlForBatchProduct(Product p) {
    return _batchValidityDaysCtrls.putIfAbsent(
      p.id,
      () => TextEditingController(
        text: (p.vencimientoDias != null && p.vencimientoDias! > 0)
            ? p.vencimientoDias.toString()
            : (_batchDefaultValidityDays != null && _batchDefaultValidityDays! > 0
                ? _batchDefaultValidityDays.toString()
                : ''),
      ),
    );
  }

  int? _parseBatchValidityDays(Product p) {
    final existingCtrl = _batchValidityDaysCtrls[p.id];
    if (existingCtrl != null) {
      final parsed = int.tryParse(existingCtrl.text.trim());
      return (parsed != null && parsed > 0) ? parsed : null;
    }
    if (p.vencimientoDias != null && p.vencimientoDias! > 0) {
      return p.vencimientoDias;
    }
    return (_batchDefaultValidityDays != null && _batchDefaultValidityDays! > 0)
        ? _batchDefaultValidityDays
        : null;
  }

  List<Product> _computeBatchFilteredTargets() {
    final query = _batchSearchCtrl.text.trim().toLowerCase();
    final recipeCount = _eligibleTargets.where((p) => p.hasProductionRecipe).length;
    final list = _eligibleTargets.where((p) {
      final hasQty = _parseBatchQty(p.id) > 0.0005;
      if (_batchOnlySelected && !hasQty) {
        return false;
      }
      if (query.isEmpty && !hasQty && _batchOnlyRecipes && recipeCount > 0 && !p.hasProductionRecipe) {
        return false;
      }
      if (query.isNotEmpty &&
          !p.name.toLowerCase().contains(query) &&
          !p.internalCode.toLowerCase().contains(query) &&
          !(p.barcode?.toLowerCase().contains(query) ?? false)) {
        return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      final aHasQty = _parseBatchQty(a.id) > 0.0005;
      final bHasQty = _parseBatchQty(b.id) > 0.0005;
      if (aHasQty != bHasQty) return aHasQty ? -1 : 1;
      if (a.hasProductionRecipe != b.hasProductionRecipe) {
        return a.hasProductionRecipe ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  void _applyQuickBatchValidityDays(int days, {bool syncGlobalInput = true}) {
    final query = _batchSearchCtrl.text.trim().toLowerCase();
    final targetsToUpdate =
        (query.isNotEmpty || _batchOnlySelected) ? _computeBatchFilteredTargets() : _eligibleTargets;
    setState(() {
      _batchDefaultValidityDays = days;
      _batchGlobalExpirationDate = _manufacturedAt.add(Duration(days: days));
      if (syncGlobalInput) {
        _batchGlobalDaysCtrl.text = days.toString();
        _batchGlobalDaysCtrl.selection = TextSelection.collapsed(
          offset: _batchGlobalDaysCtrl.text.length,
        );
      }
      for (final p in targetsToUpdate) {
        final ctrl = _validityCtrlForBatchProduct(p);
        ctrl.text = days.toString();
      }
    });
  }

  Future<void> _pickBatchGlobalExpirationDate() async {
    final initial = _batchGlobalExpirationDate ??
        _manufacturedAt.add(Duration(days: _batchDefaultValidityDays ?? 3));
    final picked = await showCompactDatePicker(
      context: context,
      initialDate: initial.isBefore(_manufacturedAt) ? _manufacturedAt : initial,
      firstDate: _manufacturedAt,
      helpText: 'Fecha de Vencimiento para Toda la Tanda',
    );
    if (picked == null || !mounted) return;
    final baseMfg = DateTime(_manufacturedAt.year, _manufacturedAt.month, _manufacturedAt.day);
    final pickedDay = DateTime(picked.year, picked.month, picked.day);
    final diffDays = math.max(1, pickedDay.difference(baseMfg).inDays);
    _applyQuickBatchValidityDays(diffDays);
  }

  Future<void> _pickRowBatchExpirationDate(Product p) async {
    final currentDays = _parseBatchValidityDays(p);
    final initial = (currentDays != null && currentDays > 0)
        ? _manufacturedAt.add(Duration(days: currentDays))
        : _manufacturedAt.add(const Duration(days: 3));
    final picked = await showCompactDatePicker(
      context: context,
      initialDate: initial.isBefore(_manufacturedAt) ? _manufacturedAt : initial,
      firstDate: _manufacturedAt,
      helpText: 'Vencimiento: ${p.name}',
    );
    if (picked == null || !mounted) return;
    final baseMfg = DateTime(_manufacturedAt.year, _manufacturedAt.month, _manufacturedAt.day);
    final pickedDay = DateTime(picked.year, picked.month, picked.day);
    final diffDays = math.max(1, pickedDay.difference(baseMfg).inDays);
    setState(() {
      _validityCtrlForBatchProduct(p).text = diffDays.toString();
    });
  }

  Future<Product?> _resolveProductByBarcodeOrQuery(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty) return null;

    final localPool = <int, Product>{
      for (final p in _eligibleTargets) p.id: p,
      for (final p in widget.provider.products) p.id: p,
      for (final p in _remoteTargetPool.values) p.id: p,
    };

    Product? match = RemoteScannerService.findExactProductMatch(
      localPool.values,
      code,
    );

    if (match == null) {
      try {
        final remote = await widget.provider.searchProductsRemote(code, perPage: 40);
        for (final p in remote) {
          localPool[p.id] = p;
          if (_isEligibleTargetProduct(p)) {
            _remoteTargetPool[p.id] = p;
            if (!_eligibleTargets.any((e) => e.id == p.id)) {
              _eligibleTargets.add(p);
            }
          }
        }
        match = RemoteScannerService.findExactProductMatch(
              localPool.values,
              code,
            ) ??
            (remote.length == 1 ? remote.first : null);
      } catch (_) {}
    }

    if (match != null && _isEligibleTargetProduct(match)) {
      _remoteTargetPool[match.id] = match;
      if (!_eligibleTargets.any((e) => e.id == match!.id)) {
        _eligibleTargets.add(match);
      }
    }
    return match;
  }

  Future<void> _handleBatchPlanillaBarcodeSubmit(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty || !mounted) return;

    if (_batchSearchCtrl.text.trim() != code) {
      _batchSearchCtrl.text = code;
      _batchSearchCtrl.selection = TextSelection.collapsed(offset: code.length);
    }

    final found = await _resolveProductByBarcodeOrQuery(code);
    if (!mounted) return;

    if (found == null) {
      setState(() {});
      SnackBarService.warning(
        context,
        'No se encontró producto para el código "$code".',
      );
      return;
    }

    if (!_isEligibleTargetProduct(found)) {
      setState(() {});
      SnackBarService.warning(
        context,
        '"${found.name}" es combo o servicio y no se elabora en planilla.',
      );
      return;
    }

    final current = _parseBatchQty(found.id);
    final bump =
        (current <= 0.0005 && found.recipeYieldQuantity > 0)
            ? found.recipeYieldQuantity
            : 1.0;
    _bumpBatchQty(found.id, bump);
    SnackBarService.success(
      context,
      '+${bump.toQty()} ${found.unitType} cargado para "${found.name}".',
    );
  }

  Future<void> _handleBarcodeScanned(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty || !mounted) return;

    if (_tabCtrl.index == 0) {
      if (_batchMode && widget.filterIngredientProductId == null) {
        await _handleBatchPlanillaBarcodeSubmit(code);
        return;
      }

      final found = await _resolveProductByBarcodeOrQuery(code);
      if (!mounted) return;
      if (found == null) {
        SnackBarService.warning(
          context,
          'No se encontró producto activo para el código "$code".',
        );
        return;
      }
      if (!_isEligibleTargetProduct(found)) {
        SnackBarService.warning(
          context,
          '"${found.name}" no es elegible para elaboración directa.',
        );
        return;
      }
      _selectTargetProduct(found);
      SnackBarService.success(
        context,
        'Seleccionado para elaborar: "${found.name}".',
      );
      return;
    }

    if (_tabCtrl.index == 1) {
      setState(() {
        _ordersSearchCtrl.text = code;
        _ordersSearchCtrl.selection = TextSelection.collapsed(offset: code.length);
      });
      await _resolveProductByBarcodeOrQuery(code);
      if (mounted) setState(() {});
      return;
    }

    if (_tabCtrl.index == 2) {
      setState(() {
        _wasteSearchCtrl.text = code;
        _wasteSearchCtrl.selection = TextSelection.collapsed(offset: code.length);
      });
      await _resolveProductByBarcodeOrQuery(code);
      if (mounted) setState(() {});
    }
  }

  double _parseBatchQty(int productId) {
    final ctrl = _batchQtyCtrls[productId];
    if (ctrl == null) return 0.0;
    return double.tryParse(ctrl.text.replaceAll(',', '.').trim()) ?? 0.0;
  }

  void _bumpBatchQty(int productId, double delta) {
    final ctrl = _ctrlForBatchProduct(productId);
    final current = _parseBatchQty(productId);
    final next = math.max(0.0, current + delta);
    ctrl.text = next <= 0 ? '' : next.toQty();
    setState(() {});
  }

  double _estimateProductCostForQty(Product p, double qty) {
    if (qty <= 0) return 0.0;
    final ingList = p.recipeIngredients;
    if (ingList == null || ingList.isEmpty) {
      return qty * p.costPrice;
    }
    final yieldQty = p.recipeYieldQuantity > 0 ? p.recipeYieldQuantity : 1.0;
    final scale = qty / yieldQty;
    double sum = 0.0;
    for (final raw in ingList) {
      final baseQty = double.tryParse(raw['quantity']?.toString() ?? '0') ?? 0.0;
      final wastePct = double.tryParse(raw['waste_pct']?.toString() ?? '0') ?? 0.0;
      final cost = double.tryParse(raw['cost_price']?.toString() ?? '0') ?? 0.0;
      sum += baseQty * (1.0 + wastePct / 100.0) * scale * cost;
    }
    return sum;
  }

  ProductBatchModel _batchModelFromOrder(ProductionOrderModel order) {
    return ProductBatchModel(
      id: order.producedBatchId!,
      productId: order.productId,
      batchCode: order.producedBatchCode ?? order.orderNumber,
      sourceType: 'production_order',
      productionOrderId: order.id,
      manufacturedAt: order.manufacturedAt ??
          DateFormat('yyyy-MM-dd').format(_manufacturedAt),
      expirationDate: order.producedBatchExpiration,
      isExpired: false,
      initialQuantity: order.quantityProduced,
      remainingQuantity: order.producedBatchRemaining ?? order.quantityProduced,
      reservedQuantity: 0,
      availableToSell: order.producedBatchRemaining ?? order.quantityProduced,
      unitCost: order.unitCost,
      status: order.producedBatchStatus ?? 'active',
    );
  }

  Future<void> _openPrintLabelsForOrders(List<ProductionOrderModel> orders) async {
    final productsToPrint = <Product>[];
    final batchesMap = <int, ProductBatchModel>{};
    final initialQtyMap = <int, int>{};

    for (final order in orders) {
      if (order.producedBatchId == null) continue;
      final match = _eligibleTargets.cast<Product?>().firstWhere(
            (p) => p?.id == order.productId,
            orElse: () => null,
          );
      if (match == null) continue;
      if (!batchesMap.containsKey(match.id)) {
        productsToPrint.add(match);
      }
      batchesMap[match.id] = _batchModelFromOrder(order);
      initialQtyMap[match.id] = match.isSoldByWeight
          ? 1
          : order.quantityProduced.ceil().clamp(1, 500);
    }

    if (productsToPrint.isEmpty || !mounted) return;
    await showDialog(
      context: context,
      builder: (_) => PrintLabelsDialog(
        products: productsToPrint,
        batchByProductId: batchesMap,
        initialQuantities: initialQtyMap,
      ),
    );
  }

  Future<void> _submitOrder({bool openPrintOnSuccess = false}) async {
    final target = _selectedTarget;
    if (target == null) {
      SnackBarService.warning(context, 'Seleccioná el producto terminado a elaborar.');
      return;
    }
    final producedQty = double.tryParse(_qtyProducedCtrl.text.replaceAll(',', '.').trim());
    if (producedQty == null || producedQty <= 0) {
      SnackBarService.warning(context, 'Ingresá una cantidad producida mayor a 0.');
      return;
    }

    final payloadIngredients = <Map<String, dynamic>>[];
    for (final line in _ingredientLines) {
      final q = double.tryParse(line.qtyCtrl.text.replaceAll(',', '.').trim());
      if (q == null || q <= 0) {
        SnackBarService.warning(context, 'Cantidad inválida en "${line.name}".');
        return;
      }
      final ingMap = <String, dynamic>{
        'ingredient_product_id': line.productId,
        'quantity': q,
      };
      if (widget.initialExplicitBatchId != null &&
          widget.filterIngredientProductId == line.productId) {
        ingMap['batch_id'] = widget.initialExplicitBatchId;
      }
      payloadIngredients.add(ingMap);
    }

    final validityDays = int.tryParse(_singleValidityDaysCtrl.text.trim());
    setState(() => _submittingOrder = true);
    ProductionOrderModel? createdOrder;
    final ok = await AdminPinDialog.protectAction(
      context,
      action: 'Registrar Producción (${target.name})',
      permissionKey: AppPermissions.adjustStock,
      onAuthorized: () async {
        createdOrder = await widget.provider.createProductionOrder({
          'product_id': target.id,
          'quantity_produced': producedQty,
          if (_batchCodeCtrl.text.trim().isNotEmpty)
            'batch_code': _batchCodeCtrl.text.trim(),
          'manufactured_at': DateFormat('yyyy-MM-dd').format(_manufacturedAt),
          if (_expirationDate != null)
            'expiration_date': DateFormat('yyyy-MM-dd').format(_expirationDate!),
          if (validityDays != null && validityDays > 0)
            'vencimiento_dias': validityDays,
          if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
          'allow_deficit': _allowDeficit,
          if (payloadIngredients.isNotEmpty) 'ingredients': payloadIngredients,
        });
      },
    );

    if (!mounted) return;
    setState(() => _submittingOrder = false);

    if (!ok) return;

    if (createdOrder == null) {
      SnackBarService.error(
        context,
        widget.provider.errorMessage ?? 'No se pudo registrar la producción.',
      );
      return;
    }

    final order = createdOrder!;
    SnackBarService.success(
      context,
      'Orden ${order.orderNumber} creada: +${order.quantityProduced.toQty()} ${target.unitType} (Lote ${order.producedBatchCode ?? '-'}).',
    );
    _batchCodeCtrl.clear();
    _notesCtrl.clear();
    await Future.wait([_loadOrders(), _loadCatalogTargets()]);
    if (!mounted) return;
    _tabCtrl.animateTo(1);

    if (openPrintOnSuccess && order.producedBatchId != null) {
      await _openPrintLabelsForOrders([order]);
    }
  }

  Future<void> _submitBatchPlanilla({bool openPrintOnSuccess = false}) async {
    final itemsPayload = <Map<String, dynamic>>[];
    for (final p in _eligibleTargets) {
      final qty = _parseBatchQty(p.id);
      if (qty > 0.0005) {
        final days = _parseBatchValidityDays(p);
        itemsPayload.add({
          'product_id': p.id,
          'quantity_produced': qty,
          if (days != null && days > 0) ...{
            'vencimiento_dias': days,
            'expiration_date': DateFormat('yyyy-MM-dd')
                .format(_manufacturedAt.add(Duration(days: days))),
          },
        });
      }
    }

    if (itemsPayload.isEmpty) {
      SnackBarService.warning(
        context,
        'Ingresá la cantidad producida en al menos un producto de la planilla.',
      );
      return;
    }

    setState(() => _submittingOrder = true);
    Map<String, dynamic>? batchResult;
    final ok = await AdminPinDialog.protectAction(
      context,
      action: 'Planilla de Producción (${itemsPayload.length} productos)',
      permissionKey: AppPermissions.adjustStock,
      onAuthorized: () async {
        batchResult = await widget.provider.createBatchProductionOrders({
          'manufactured_at': DateFormat('yyyy-MM-dd').format(_manufacturedAt),
          'allow_deficit': _allowDeficit,
          if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
          'items': itemsPayload,
        });
      },
    );

    if (!mounted) return;
    setState(() => _submittingOrder = false);

    if (!ok) return;

    if (batchResult == null) {
      SnackBarService.error(
        context,
        widget.provider.errorMessage ?? 'No se pudo procesar la planilla de producción.',
      );
      return;
    }

    final createdOrders =
        List<ProductionOrderModel>.from((batchResult!['orders'] as List?) ?? const []);
    SnackBarService.success(
      context,
      'Planilla procesada: ${createdOrders.length} orden(es) y lotes generados.',
    );

    for (final c in _batchQtyCtrls.values) {
      c.clear();
    }
    _notesCtrl.clear();
    await Future.wait([_loadOrders(), _loadCatalogTargets()]);
    if (!mounted) return;
    _tabCtrl.animateTo(1);

    if (openPrintOnSuccess && createdOrders.isNotEmpty) {
      await _openPrintLabelsForOrders(createdOrders);
    }
  }

  Future<void> _loadOrders() async {
    setState(() {
      _loadingOrders = true;
      _ordersError = null;
    });
    try {
      final res = await widget.provider.fetchProductionOrders(
        status: _statusFilter.isNotEmpty ? _statusFilter : null,
      );
      if (mounted) {
        setState(() {
          _orders = List<ProductionOrderModel>.from(res['data'] as List);
          _loadingOrders = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _ordersError = e.toString().replaceFirst('Exception: ', '');
          _loadingOrders = false;
        });
      }
    }
  }

  Future<void> _confirmVoidOrder(ProductionOrderModel order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Anular ${order.orderNumber}'),
        content: Text(
          'Se devolverán los ingredientes consumidos a sus lotes originales y se retirará el stock generado del lote ${order.producedBatchCode ?? ''}.\n\nSolo es posible si el lote producido no tuvo ventas ni consumo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Anular Orden'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await AdminPinDialog.protectAction(
      context,
      action: 'Anular Orden de Producción ${order.orderNumber}',
      permissionKey: AppPermissions.adjustStock,
      onAuthorized: () async {
        final res = await widget.provider.voidProductionOrder(order.id);
        if (mounted) {
          if (res != null) {
            SnackBarService.success(context, 'Orden ${order.orderNumber} anulada y stock revertido.');
            await Future.wait([_loadOrders(), _loadCatalogTargets()]);
          } else {
            SnackBarService.error(
              context,
              widget.provider.errorMessage ?? 'No se pudo anular la orden.',
            );
          }
        }
      },
    );
  }

  Future<void> _loadWasteReport() async {
    setState(() {
      _loadingWaste = true;
      _wasteError = null;
    });
    try {
      final res = await widget.provider.fetchWasteReport(
        startDate: DateFormat('yyyy-MM-dd').format(_wasteRange.start),
        endDate: DateFormat('yyyy-MM-dd').format(_wasteRange.end),
      );
      if (mounted) {
        setState(() {
          _wasteData = res;
          _loadingWaste = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _wasteError = e.toString().replaceFirst('Exception: ', '');
          _loadingWaste = false;
        });
      }
    }
  }

  Widget _buildCreateTab() {
    if (_loadingCatalog) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            if (widget.filterIngredientProductId == null)
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: false,
                    icon: Icon(Icons.bakery_dining_outlined, size: 17),
                    label: Text('Individual (Detallado)'),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    icon: Icon(Icons.view_list_outlined, size: 17),
                    label: Text('Planilla Rápida Matutina'),
                  ),
                ],
                selected: {_batchMode},
                onSelectionChanged: (s) {
                  if (s.isNotEmpty) setState(() => _batchMode = s.first);
                },
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.recycling_outlined, size: 17, color: Colors.teal.shade800),
                    const SizedBox(width: 6),
                    Text(
                      'Modo Transformación / Re-elaboración de lote',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.teal.shade900,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: (_batchMode && widget.filterIngredientProductId == null)
              ? _buildBatchPlanillaView()
              : _buildSingleCreateView(),
        ),
      ],
    );
  }

  Widget _buildBatchPlanillaView() {
    final recipeCount = _eligibleTargets.where((p) => p.hasProductionRecipe).length;
    final selectedProducts = <Product>[];
    double estTotalCost = 0.0;
    for (final p in _eligibleTargets) {
      final q = _parseBatchQty(p.id);
      if (q > 0.0005) {
        selectedProducts.add(p);
        estTotalCost += _estimateProductCostForQty(p, q);
      }
    }
    final selectedCount = selectedProducts.length;
    if (selectedCount == 0 && _batchOnlySelected) {
      _batchOnlySelected = false;
    }
    final filteredTargets = _computeBatchFilteredTargets();

    return LayoutBuilder(
      builder: (context, viewConstraints) {
        final topBar = Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 195,
              child: TextField(
                controller: _batchSearchCtrl,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Buscar / barras...',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  prefixIcon: const Icon(Icons.qr_code_scanner, size: 17),
                  suffixIcon: _batchSearchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _batchSearchCtrl.clear();
                            setState(() {});
                          },
                        )
                      : null,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: _handleBatchPlanillaBarcodeSubmit,
              ),
            ),
            if (recipeCount > 0)
              FilterChip(
                label: Text('Solo con receta ($recipeCount)', style: const TextStyle(fontSize: 11.5)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                selected: _batchOnlyRecipes,
                onSelected: (v) => setState(() => _batchOnlyRecipes = v),
              ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              ),
              icon: const Icon(Icons.calendar_today_outlined, size: 14),
              label: Text('Elab: ${DateFormat('dd/MM/yy').format(_manufacturedAt)}', style: const TextStyle(fontSize: 11.5)),
              onPressed: () async {
                final picked = await showCompactDatePicker(
                  context: context,
                  initialDate: _manufacturedAt,
                  helpText: 'Fecha de Elaboración de la Tanda',
                );
                if (picked != null) {
                  setState(() {
                    _manufacturedAt = picked;
                    if (_batchDefaultValidityDays != null && _batchDefaultValidityDays! > 0) {
                      _batchGlobalExpirationDate =
                          picked.add(Duration(days: _batchDefaultValidityDays!));
                    }
                  });
                }
              },
            ),
            SizedBox(
              width: 130,
              child: TextField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nota (opc)',
                  hintText: 'Horneada...',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                ),
              ),
            ),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Todos:',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                ),
                ...[1, 2, 3, 5, 7].map((d) {
                  final selected = _batchDefaultValidityDays == d;
                  return InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _applyQuickBatchValidityDays(d),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: selected ? Colors.deepPurple.shade50 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: selected ? Colors.deepPurple.shade300 : Colors.grey.shade300,
                        ),
                      ),
                      child: Text(
                        '${d}d',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? Colors.deepPurple.shade800 : Colors.grey.shade800,
                        ),
                      ),
                    ),
                  );
                }),
                SizedBox(
                  width: 64,
                  child: TextField(
                    key: const ValueKey('batch_global_validity_days_field'),
                    controller: _batchGlobalDaysCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: 'Días',
                      suffixText: 'd',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 7, vertical: 6),
                    ),
                    onChanged: (v) {
                      final d = int.tryParse(v.trim());
                      if (d != null && d > 0) {
                        _applyQuickBatchValidityDays(d, syncGlobalInput: false);
                      } else if (v.trim().isEmpty) {
                        setState(() {
                          _batchDefaultValidityDays = null;
                          _batchGlobalExpirationDate = null;
                        });
                      }
                    },
                  ),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('batch_global_expiration_btn'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  ),
                  icon: const Icon(Icons.event_available_outlined, size: 14),
                  label: Text(
                    _batchGlobalExpirationDate != null
                        ? 'Vence: ${DateFormat('dd/MM/yy').format(_batchGlobalExpirationDate!)}'
                        : 'Fecha vto. todos',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  onPressed: _pickBatchGlobalExpirationDate,
                ),
              ],
            ),
          ],
        );

        final bool useScrollFallback = viewConstraints.maxHeight < 395;

        final listBody = filteredTargets.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No hay productos elaborados con el filtro seleccionado.',
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
              )
            : ListView.separated(
                shrinkWrap: useScrollFallback,
                physics: useScrollFallback
                    ? const NeverScrollableScrollPhysics()
                    : null,
                itemCount: filteredTargets.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, idx) {
                    final p = filteredTargets[idx];
                    final ctrl = _ctrlForBatchProduct(p.id);
                    final validityCtrl = _validityCtrlForBatchProduct(p);
                    final qty = _parseBatchQty(p.id);
                    final validityDays = _parseBatchValidityDays(p);
                    final isActive = qty > 0.0005;
                    final estExp = (validityDays != null && validityDays > 0)
                        ? _manufacturedAt.add(Duration(days: validityDays))
                        : null;
                    final bumps = p.isSoldByWeight ? const [1.0, 5.0] : const [1.0, 6.0, 12.0];

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.teal.shade50.withValues(alpha: 0.65)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isActive ? Colors.teal.shade300 : Colors.grey.shade300,
                        ),
                      ),
                      child: LayoutBuilder(
                        builder: (context, rowConstraints) {
                          final isNarrow = rowConstraints.maxWidth < 680;
                          final infoColumn = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      p.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isActive) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.teal.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'CARGADO',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.teal.shade900,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (p.hasProductionRecipe) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.deepOrange.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'RECETA',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.deepOrange.shade800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(
                                    'Stock: ${p.stock.toQty()} ${p.unitType} • ',
                                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                                  ),
                                  Flexible(
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(4),
                                      onTap: _submittingOrder ? null : () => _pickRowBatchExpirationDate(p),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.event_outlined,
                                              size: 12,
                                              color: estExp != null ? Colors.deepPurple.shade600 : Colors.orange.shade800,
                                            ),
                                            const SizedBox(width: 3),
                                            Flexible(
                                              child: Text(
                                                estExp != null
                                                    ? 'Vence: ${DateFormat('dd/MM').format(estExp)} (${validityDays}d)'
                                                    : 'Sin vto. (elegir fecha)',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: estExp != null ? Colors.deepPurple.shade700 : Colors.orange.shade800,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );

                          final controlsWrap = Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ...bumps.map(
                                (inc) => OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: _submittingOrder ? null : () => _bumpBatchQty(p.id, inc),
                                  child: Text('+${inc.toQty()}', style: const TextStyle(fontSize: 11.5)),
                                ),
                              ),
                              SizedBox(
                                width: 72,
                                child: TextField(
                                  controller: ctrl,
                                  enabled: !_submittingOrder,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: InputDecoration(
                                    labelText: p.unitType,
                                    hintText: '0',
                                    isDense: true,
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              SizedBox(
                                width: 78,
                                child: TextField(
                                  key: ValueKey('batch_validity_${p.id}'),
                                  controller: validityCtrl,
                                  enabled: !_submittingOrder,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Validez',
                                    hintText: 'Días',
                                    suffixText: 'd',
                                    isDense: true,
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              if (isActive)
                                IconButton(
                                  tooltip: 'Limpiar',
                                  icon: const Icon(Icons.close, size: 17),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                  onPressed: _submittingOrder
                                      ? null
                                      : () {
                                          ctrl.clear();
                                          setState(() {});
                                        },
                                ),
                            ],
                          );

                          if (isNarrow) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                infoColumn,
                                const SizedBox(height: 8),
                                controlsWrap,
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(child: infoColumn),
                              const SizedBox(width: 8),
                              controlsWrap,
                            ],
                          );
                        },
                      ),
                    );
                  },
                );

        final footerBar = Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.teal.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => setState(() => _allowDeficit = !_allowDeficit),
                child: Row(
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: Checkbox(
                        value: _allowDeficit,
                        visualDensity: VisualDensity.compact,
                        onChanged: (v) => setState(() => _allowDeficit = v == true),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Permitir elaborar aunque falte algún insumo (genera déficit conciliable)',
                        style: TextStyle(fontSize: 11.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 6,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$selectedCount producto(s) con cantidad cargada',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: Colors.teal.shade900,
                        ),
                      ),
                      Text(
                        'Costo insumos estimado total: \$${estTotalCost.toCurrency()}',
                        style: TextStyle(fontSize: 11.5, color: Colors.teal.shade800),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.check_circle_outline, size: 17),
                        label: Text(
                          _submittingOrder ? 'Procesando...' : 'Registrar Horneada ($selectedCount)',
                        ),
                        onPressed: _submittingOrder || selectedCount == 0
                            ? null
                            : () => _submitBatchPlanilla(openPrintOnSuccess: false),
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.qr_code_2, size: 17),
                        label: Text(
                          _submittingOrder ? 'Procesando...' : 'Registrar e Imprimir L#',
                        ),
                        onPressed: _submittingOrder || selectedCount == 0
                            ? null
                            : () => _submitBatchPlanilla(openPrintOnSuccess: true),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );

        final Widget? selectedStrip = selectedProducts.isEmpty
            ? null
            : SizedBox(
                key: const ValueKey('batch_selected_strip'),
                height: 30,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: selectedProducts.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, idx) {
                    if (idx == 0) {
                      return InkWell(
                        key: const ValueKey('batch_only_selected_chip'),
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => setState(() {
                          _batchOnlySelected = !_batchOnlySelected;
                          if (_batchOnlySelected && _batchSearchCtrl.text.isNotEmpty) {
                            _batchSearchCtrl.clear();
                          }
                        }),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: _batchOnlySelected ? Colors.teal.shade700 : Colors.teal.shade100,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.teal.shade400),
                          ),
                          child: Text(
                            'Cargados ($selectedCount)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _batchOnlySelected ? Colors.white : Colors.teal.shade900,
                            ),
                          ),
                        ),
                      );
                    }
                    final sp = selectedProducts[idx - 1];
                    final q = _parseBatchQty(sp.id);
                    final vDays = _parseBatchValidityDays(sp);
                    final expShort = (vDays != null && vDays > 0)
                        ? DateFormat('dd/MM').format(_manufacturedAt.add(Duration(days: vDays)))
                        : null;
                    final chipText =
                        '${sp.name}: ${q.toQty()} ${sp.unitType} • ${vDays != null ? '${vDays}d ($expShort)' : 'Sin vto.'}';
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.teal.shade300),
                      ),
                      padding: const EdgeInsets.only(left: 9, right: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              setState(() {
                                _batchSearchCtrl.clear();
                                _batchOnlySelected = false;
                              });
                            },
                            child: Text(
                              chipText,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.teal.shade900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: _submittingOrder
                                ? null
                                : () {
                                    _ctrlForBatchProduct(sp.id).clear();
                                    setState(() {});
                                  },
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(Icons.close, size: 14, color: Colors.teal.shade800),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );

        if (useScrollFallback) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                topBar,
                if (selectedStrip != null) ...[
                  const SizedBox(height: 5),
                  selectedStrip,
                ],
                const SizedBox(height: 6),
                listBody,
                const SizedBox(height: 6),
                footerBar,
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            topBar,
            if (selectedStrip != null) ...[
              const SizedBox(height: 5),
              selectedStrip,
            ],
            const SizedBox(height: 6),
            Expanded(child: listBody),
            const SizedBox(height: 6),
            footerBar,
          ],
        );
      },
    );
  }

  Widget _buildSingleCreateView() {
    final producedQty =
        double.tryParse(_qtyProducedCtrl.text.replaceAll(',', '.').trim()) ?? 1.0;
    final totalCost = _estimatedTotalCost;
    final estUnitCost = producedQty > 0 ? (totalCost / producedQty) : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.filterIngredientProductId != null && _sourceTransformProduct != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.transform, size: 17, color: Colors.teal.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Re-elaboración desde ${_sourceTransformProduct!.name}'
                      '${widget.initialExplicitBatchCode != null && widget.initialExplicitBatchCode!.isNotEmpty ? ' • Lote ${widget.initialExplicitBatchCode}' : (widget.initialExplicitBatchId != null ? ' • Lote #${widget.initialExplicitBatchId}' : '')}'
                      '${widget.initialExplicitBatchAvailableQty != null ? ' (Disp: ${widget.initialExplicitBatchAvailableQty!.toQty()} ${_sourceTransformProduct!.unitType})' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.teal.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SearchableSelectField<int>(
            value: _selectedTarget?.id,
            labelText: 'Producto terminado / semi-elaborado a producir *',
            prefixIcon: Icons.bakery_dining_outlined,
            searchHintText: 'Buscar por nombre, código o barras...',
            helperText: 'Los productos con receta configurada aparecen primero.',
            options: _eligibleTargets
                .map(
                  (p) => SearchableSelectOption<int>(
                    value: p.id,
                    label: p.name,
                    subtitle: 'Stock actual: ${p.stock.toQty()} ${p.unitType}'
                        '${p.vencimientoDias != null ? ' • Vida útil: ${p.vencimientoDias}d' : ''}',
                    badgeText: p.hasProductionRecipe ? 'RECETA' : null,
                    searchKeywords: [
                      p.internalCode,
                      if (p.barcode != null && p.barcode!.isNotEmpty) p.barcode!,
                    ],
                  ),
                )
                .toList(),
            onRemoteSearch: (q) async {
              final remote = await widget.provider.searchProductsRemote(q, perPage: 80);
              final matched = <SearchableSelectOption<int>>[];
              for (final p in remote) {
                if (!_isEligibleTargetProduct(p)) continue;
                _remoteTargetPool[p.id] = p;
                matched.add(
                  SearchableSelectOption<int>(
                    value: p.id,
                    label: p.name,
                    subtitle: 'Stock actual: ${p.stock.toQty()} ${p.unitType}'
                        '${p.vencimientoDias != null ? ' • Vida útil: ${p.vencimientoDias}d' : ''}',
                    badgeText: p.hasProductionRecipe ? 'RECETA' : null,
                    searchKeywords: [
                      p.internalCode,
                      if (p.barcode != null && p.barcode!.isNotEmpty) p.barcode!,
                    ],
                  ),
                );
              }
              return matched;
            },
            onChanged: (id) {
              if (id == null) {
                _selectTargetProduct(null);
              } else {
                final found = _eligibleTargets.cast<Product?>().firstWhere(
                      (e) => e?.id == id,
                      orElse: () => _remoteTargetPool[id],
                    );
                if (found != null) {
                  if (!_eligibleTargets.any((e) => e.id == found.id)) {
                    _eligibleTargets.add(found);
                  }
                  _selectTargetProduct(found);
                }
              }
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _qtyProducedCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Cant. a producir (${_selectedTarget?.unitType ?? 'un'}) *',
                    isDense: true,
                    prefixIcon: const Icon(Icons.production_quantity_limits),
                  ),
                  onChanged: (v) {
                    final parsed = double.tryParse(v.replaceAll(',', '.').trim());
                    if (parsed != null && parsed > 0) {
                      _rescaleRecipeQuantities(parsed);
                    } else {
                      setState(() {});
                    }
                  },
                ),
              ),
              SizedBox(
                width: 210,
                child: TextField(
                  controller: _batchCodeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Código de Lote (opcional)',
                    hintText: 'Auto si vacío',
                    isDense: true,
                    prefixIcon: Icon(Icons.qr_code_2),
                  ),
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text('Elab: ${DateFormat('dd/MM/yy').format(_manufacturedAt)}'),
                onPressed: () async {
                  final picked = await showCompactDatePicker(
                    context: context,
                    initialDate: _manufacturedAt,
                    helpText: 'Fecha de Elaboración',
                  );
                  if (picked != null) {
                    setState(() {
                      _manufacturedAt = picked;
                      final typedDays = int.tryParse(_singleValidityDaysCtrl.text.trim());
                      final effectiveDays = (typedDays != null && typedDays > 0)
                          ? typedDays
                          : _selectedTarget?.vencimientoDias;
                      if (effectiveDays != null && effectiveDays > 0) {
                        _expirationDate = picked.add(Duration(days: effectiveDays));
                      }
                    });
                  }
                },
              ),
              SizedBox(
                width: 128,
                child: TextField(
                  key: const ValueKey('single_validity_days_field'),
                  controller: _singleValidityDaysCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Validez',
                    hintText: 'Días',
                    suffixText: 'días',
                    isDense: true,
                  ),
                  onChanged: (v) {
                    final d = int.tryParse(v.trim());
                    setState(() {
                      if (d != null && d > 0) {
                        _expirationDate = _manufacturedAt.add(Duration(days: d));
                      } else if (v.trim().isEmpty) {
                        _expirationDate = null;
                      }
                    });
                  },
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_available_outlined, size: 16),
                label: Text(
                  _expirationDate != null
                      ? 'Vence: ${DateFormat('dd/MM/yy').format(_expirationDate!)}'
                      : 'Vencimiento (opc)',
                ),
                onPressed: () async {
                  final picked = await showCompactDatePicker(
                    context: context,
                    initialDate:
                        _expirationDate ?? DateTime.now().add(const Duration(days: 3)),
                    helpText: 'Vencimiento del Lote Producido',
                  );
                  if (picked != null) {
                    setState(() {
                      _expirationDate = picked;
                      final diff = picked
                          .difference(DateTime(
                            _manufacturedAt.year,
                            _manufacturedAt.month,
                            _manufacturedAt.day,
                          ))
                          .inDays;
                      _singleValidityDaysCtrl.text = diff > 0 ? diff.toString() : '';
                    });
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Validez rápida:',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
              ),
              ...[1, 2, 3, 5, 7].map(
                (d) => ChoiceChip(
                  label: Text('${d}d', style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  selected: int.tryParse(_singleValidityDaysCtrl.text.trim()) == d,
                  onSelected: (_) {
                    setState(() {
                      _singleValidityDaysCtrl.text = d.toString();
                      _expirationDate = _manufacturedAt.add(Duration(days: d));
                    });
                  },
                ),
              ),
              if (_expirationDate != null || _singleValidityDaysCtrl.text.trim().isNotEmpty)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.close, size: 14),
                  label: const Text('Sin vto.', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    setState(() {
                      _singleValidityDaysCtrl.clear();
                      _expirationDate = null;
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Insumos y Materias Primas (descuenta lo que vence antes)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Agregar insumo'),
                onPressed: _addExtraIngredientDialog,
              ),
            ],
          ),
          if (_ingredientLines.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Text(
                'Este producto no tiene receta cargada. Podés registrarlo directo con su costo actual o tocar "Agregar insumo" para descontar materias primas.',
                style: TextStyle(fontSize: 12.5, color: Colors.black54),
              ),
            )
          else
            ...List.generate(_ingredientLines.length, (i) {
              final line = _ingredientLines[i];
              final req =
                  double.tryParse(line.qtyCtrl.text.replaceAll(',', '.').trim()) ?? 0.0;
              final shortStock = line.currentStock < req;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: shortStock
                      ? Colors.amber.shade50.withValues(alpha: 0.65)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: shortStock ? Colors.amber.shade300 : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  line.name,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                              ),
                              if (line.trackBatches) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'CON LOTES',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.teal.shade800,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            'Disponible: ${line.currentStock.toQty()} ${line.unitType} • Costo: \$${line.unitCost.toCurrency()}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: shortStock ? Colors.deepOrange.shade800 : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: line.qtyCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: line.unitType,
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Quitar insumo',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        setState(() {
                          line.dispose();
                          _ingredientLines.removeAt(i);
                        });
                      },
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Permitir elaborar aunque falte stock en algún insumo (genera saldo en déficit)',
              style: TextStyle(fontSize: 12.5),
            ),
            value: _allowDeficit,
            onChanged: (v) => setState(() => _allowDeficit = v),
          ),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(
              labelText: 'Notas del horneado / turno (opcional)',
              isDense: true,
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.teal.shade200),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Costo total insumos estim.: \$${totalCost.toCurrency()}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.teal.shade900,
                      ),
                    ),
                    Text(
                      'Costo unitario del lote resultante: \$${estUnitCost.toCurrency()} / ${_selectedTarget?.unitType ?? 'un'}',
                      style: TextStyle(fontSize: 12, color: Colors.teal.shade800),
                    ),
                  ],
                ),
                FilledButton.icon(
                  icon: _submittingOrder
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(_submittingOrder ? 'Procesando...' : 'Registrar Producción y Lote'),
                  onPressed: _submittingOrder ? null : () => _submitOrder(openPrintOnSuccess: false),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.qr_code_2, size: 18),
                  label: const Text('Registrar e Imprimir L#'),
                  onPressed: _submittingOrder ? null : () => _submitOrder(openPrintOnSuccess: true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    final q = _ordersSearchCtrl.text.trim().toLowerCase();
    final matchedProdIds = q.isEmpty
        ? const <int>{}
        : _eligibleTargets
            .where((p) =>
                p.name.toLowerCase().contains(q) ||
                p.internalCode.toLowerCase().contains(q) ||
                (p.barcode?.toLowerCase().contains(q) ?? false))
            .map((p) => p.id)
            .toSet();
    final filteredOrders = q.isEmpty
        ? _orders
        : _orders.where((o) {
            if (matchedProdIds.contains(o.productId)) return true;
            if (o.orderNumber.toLowerCase().contains(q)) return true;
            if (o.productName.toLowerCase().contains(q)) return true;
            if ((o.producedBatchCode?.toLowerCase().contains(q) ?? false)) return true;
            if (o.producedBatchId != null && 'l#${o.producedBatchId}' == q) return true;
            if ((o.notes?.toLowerCase().contains(q) ?? false)) return true;
            return false;
          }).toList();

    return Column(
      children: [
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                controller: _ordersSearchCtrl,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Buscar o pistolear orden, lote L#, barras...',
                  isDense: true,
                  prefixIcon: const Icon(Icons.qr_code_scanner, size: 18),
                  suffixIcon: _ordersSearchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _ordersSearchCtrl.clear();
                            setState(() {});
                          },
                        )
                      : null,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (v) async {
                  await _resolveProductByBarcodeOrQuery(v);
                  if (mounted) setState(() {});
                },
              ),
            ),
            ChoiceChip(
              label: const Text('Todas'),
              selected: _statusFilter.isEmpty,
              onSelected: (_) {
                setState(() => _statusFilter = '');
                _loadOrders();
              },
            ),
            ChoiceChip(
              label: const Text('Completadas'),
              selected: _statusFilter == 'completed',
              onSelected: (_) {
                setState(() => _statusFilter = 'completed');
                _loadOrders();
              },
            ),
            ChoiceChip(
              label: const Text('Anuladas'),
              selected: _statusFilter == 'voided',
              onSelected: (_) {
                setState(() => _statusFilter = 'voided');
                _loadOrders();
              },
            ),
            IconButton(
              tooltip: 'Refrescar',
              icon: const Icon(Icons.refresh),
              onPressed: _loadingOrders ? null : _loadOrders,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loadingOrders
              ? const Center(child: CircularProgressIndicator())
              : _ordersError != null
                  ? Center(child: Text(_ordersError!, style: const TextStyle(color: Colors.red)))
                  : filteredOrders.isEmpty
                      ? Center(
                          child: Text(
                            q.isEmpty
                                ? 'No hay órdenes de producción registradas.'
                                : 'Sin coincidencias de órdenes para "$q".',
                          ),
                        )
                      : ListView.separated(
                          itemCount: filteredOrders.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, idx) {
                            final o = filteredOrders[idx];
                            return Card(
                              margin: EdgeInsets.zero,
                              child: ExpansionTile(
                                tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                title: Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: o.isVoided ? Colors.red.shade50 : Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        o.isVoided ? 'ANULADA' : 'COMPLETADA',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                          color: o.isVoided ? Colors.red.shade800 : Colors.green.shade800,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${o.orderNumber} • ${o.productName}',
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                                    ),
                                  ],
                                ),
                                subtitle: Text(
                                  '+${o.quantityProduced.toQty()} ${o.unitType} • Lote: ${o.producedBatchCode ?? '-'} • Costo total: \$${o.totalCost.toCurrency()} (\$${o.unitCost.toCurrency()}/u)',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!o.isVoided && o.producedBatchId != null)
                                      IconButton(
                                        tooltip: 'Imprimir Etiqueta Térmica del Lote',
                                        icon: const Icon(Icons.qr_code_2, color: Colors.deepPurple),
                                        onPressed: () {
                                          final match = _eligibleTargets.cast<Product?>().firstWhere(
                                                (p) => p?.id == o.productId,
                                                orElse: () => null,
                                              );
                                          if (match == null) return;
                                          final batch = ProductBatchModel(
                                            id: o.producedBatchId!,
                                            productId: o.productId,
                                            batchCode: o.producedBatchCode ?? o.orderNumber,
                                            sourceType: 'production_order',
                                            productionOrderId: o.id,
                                            expirationDate: o.producedBatchExpiration,
                                            isExpired: false,
                                            initialQuantity: o.quantityProduced,
                                            remainingQuantity: o.producedBatchRemaining ?? o.quantityProduced,
                                            reservedQuantity: 0,
                                            availableToSell: o.producedBatchRemaining ?? o.quantityProduced,
                                            unitCost: o.unitCost,
                                            status: o.producedBatchStatus ?? 'active',
                                          );
                                          showDialog(
                                            context: context,
                                            builder: (_) => PrintLabelsDialog(
                                              products: [match],
                                              batchByProductId: {match.id: batch},
                                            ),
                                          );
                                        },
                                      ),
                                    if (!o.isVoided)
                                      IconButton(
                                        tooltip: 'Anular Orden y Revertir Insumos',
                                        icon: const Icon(Icons.undo, color: Colors.red),
                                        onPressed: () => _confirmVoidOrder(o),
                                      ),
                                  ],
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        const Divider(),
                                        const Text(
                                          'Trazabilidad de insumos consumidos:',
                                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                        ),
                                        const SizedBox(height: 4),
                                        ...o.consumptions.map(
                                          (c) => Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 2),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '• ${c.ingredientName}${c.batchCode != null ? ' (Lote ${c.batchCode})' : ''}',
                                                    style: const TextStyle(fontSize: 12),
                                                  ),
                                                ),
                                                Text(
                                                  '-${c.quantityUsed.toQty()} ${c.unitType} (\$${c.subtotalCost.toCurrency()})',
                                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }

  Widget _buildWasteReportTab() {
    final rawMovements = (_wasteData?['movements'] as List?) ?? const [];
    final q = _wasteSearchCtrl.text.trim().toLowerCase();
    final matchedProdIds = q.isEmpty
        ? const <int>{}
        : _eligibleTargets
            .where((p) =>
                p.name.toLowerCase().contains(q) ||
                p.internalCode.toLowerCase().contains(q) ||
                (p.barcode?.toLowerCase().contains(q) ?? false))
            .map((p) => p.id)
            .toSet();
    final movements = q.isEmpty
        ? rawMovements
        : rawMovements.where((raw) {
            final m = Map<String, dynamic>.from(raw as Map);
            final prodId = (m['product_id'] as num?)?.toInt();
            if (prodId != null && matchedProdIds.contains(prodId)) return true;
            if ((m['product_name']?.toString().toLowerCase().contains(q) ?? false)) return true;
            if ((m['batch_code']?.toString().toLowerCase().contains(q) ?? false)) return true;
            if (m['batch_id'] != null && 'l#${m['batch_id']}' == q) return true;
            if ((m['notes']?.toString().toLowerCase().contains(q) ?? false)) return true;
            if ((m['user_name']?.toString().toLowerCase().contains(q) ?? false)) return true;
            return false;
          }).toList();

    final totalEvents = (_wasteData?['total_events'] as num?)?.toInt() ?? 0;
    final totalUnits = (_wasteData?['total_units_lost'] as num?)?.toDouble() ?? 0.0;
    final totalCost = (_wasteData?['total_cost_lost'] as num?)?.toDouble() ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.date_range, size: 17),
                  label: Text(
                    '${DateFormat('dd/MM/yy').format(_wasteRange.start)} - ${DateFormat('dd/MM/yy').format(_wasteRange.end)}',
                  ),
                  onPressed: () async {
                    final picked = await showCompactDateRangePicker(
                      context: context,
                      initialDateRange: _wasteRange,
                      helpText: 'Rango de Mermas y Vencimientos',
                    );
                    if (picked != null) {
                      setState(() => _wasteRange = picked);
                      _loadWasteReport();
                    }
                  },
                ),
                SizedBox(
                  width: 245,
                  child: TextField(
                    controller: _wasteSearchCtrl,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Filtrar o pistolear producto / lote...',
                      isDense: true,
                      prefixIcon: const Icon(Icons.qr_code_scanner, size: 18),
                      suffixIcon: _wasteSearchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _wasteSearchCtrl.clear();
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (v) async {
                      await _resolveProductByBarcodeOrQuery(v);
                      if (mounted) setState(() {});
                    },
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                Chip(label: Text('Eventos: $totalEvents')),
                Chip(label: Text('Unidades: ${totalUnits.toQty()}')),
                Chip(
                  backgroundColor: Colors.red.shade50,
                  label: Text(
                    'Costo Perdido: \$${totalCost.toCurrency()}',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade900),
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
                  icon: const Icon(Icons.cleaning_services_outlined, size: 17),
                  label: const Text('Barrido de Vencidos (1 Clic)'),
                  onPressed: () async {
                    final swept = await showDialog<bool>(
                      context: context,
                      builder: (_) => ExpiredBatchesSweepDialog(provider: widget.provider),
                    );
                    if (swept == true && mounted) {
                      await Future.wait([_loadWasteReport(), _loadCatalogTargets()]);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _loadingWaste
              ? const Center(child: CircularProgressIndicator())
              : _wasteError != null
                  ? Center(child: Text(_wasteError!, style: const TextStyle(color: Colors.red)))
                  : movements.isEmpty
                      ? Center(
                          child: Text(
                            q.isEmpty
                                ? 'No hay mermas ni descartes en este período.'
                                : 'Sin coincidencias de mermas para "$q".',
                          ),
                        )
                      : ListView.separated(
                          itemCount: movements.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                          itemBuilder: (_, idx) {
                            final m = Map<String, dynamic>.from(movements[idx] as Map);
                            final qty = double.tryParse(m['quantity']?.toString() ?? '0') ?? 0.0;
                            final lost = double.tryParse(m['total_cost_lost']?.toString() ?? '0') ?? 0.0;
                            final rawDate = (m['date'] ?? m['created_at'])?.toString() ?? '';
                            final parsedDate = DateTime.tryParse(rawDate);
                            final dateLabel = parsedDate != null
                                ? DateFormat('dd/MM/yy HH:mm').format(parsedDate.toLocal())
                                : rawDate;
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.delete_sweep_outlined, color: Colors.deepOrange),
                              title: Text(
                                '${m['product_name'] ?? ''} ${m['batch_code'] != null ? '• Lote ${m['batch_code']}' : ''}',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              subtitle: Text(
                                '${dateLabel.isNotEmpty ? '$dateLabel • ' : ''}Usuario: ${m['user_name'] ?? 'Sistema'}${m['notes'] != null ? ' • ${m['notes']}' : ''}',
                                style: const TextStyle(fontSize: 11.5),
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '-${qty.toQty()} ${m['unit_type'] ?? 'un'}',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                                  ),
                                  Text(
                                    '-\$${lost.toCurrency()}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: Colors.red.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    return RemoteScannerListener(
      debugLabel: 'ProductionOrdersDialog',
      onBarcodeScanned: _handleBarcodeScanned,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 960,
            maxHeight: math.min(760, screenH * 0.90),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.bakery_dining_outlined, color: Colors.deepOrange, size: 28),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Producción Propia (Cocina / Pastelería) y Mermas',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TabBar(
                  controller: _tabCtrl,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: const [
                    Tab(icon: Icon(Icons.add_task, size: 18), text: 'Nueva Elaboración'),
                    Tab(icon: Icon(Icons.history, size: 18), text: 'Órdenes de Producción'),
                    Tab(icon: Icon(Icons.assessment_outlined, size: 18), text: 'Reporte de Mermas'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _buildCreateTab(),
                      _buildHistoryTab(),
                      _buildWasteReportTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
