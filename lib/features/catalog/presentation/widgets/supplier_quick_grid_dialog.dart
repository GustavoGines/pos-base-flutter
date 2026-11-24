import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/config/business_vertical_profile.dart';
import 'package:frontend_desktop/core/constants/app_permissions.dart';
import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/presentation/widgets/searchable_select_field.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/core/utils/search_text_utils.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/features/auth/presentation/widgets/admin_pin_dialog.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/apparel_variant_helper_dialog.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/catalog_quick_create_dialogs.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/hardware_dimension_helper_dialog.dart';
import 'package:frontend_desktop/features/offers/presentation/providers/offer_provider.dart';
import 'package:frontend_desktop/features/pos/domain/services/hardware_calculator_engine.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

class _QuickGridRowModel {
  final TextEditingController supplierSkuCtrl = TextEditingController();
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController technicalSpecCtrl = TextEditingController();
  final TextEditingController costCtrl = TextEditingController();
  final TextEditingController priceCtrl = TextEditingController();
  final TextEditingController stockCtrl = TextEditingController(text: '0');
  final TextEditingController storageLocationCtrl = TextEditingController();
  final TextEditingController barcodeCtrl = TextEditingController();

  String unitType;
  bool isSoldByWeight;
  bool userCustomizedUnit = false;
  bool manualPriceOverride = false;
  Map<String, dynamic>? calcConfig;
  String? errorText;

  _QuickGridRowModel({
    this.unitType = 'un',
    this.isSoldByWeight = false,
  });

  bool get hasAnyInput =>
      supplierSkuCtrl.text.trim().isNotEmpty ||
      nameCtrl.text.trim().isNotEmpty ||
      technicalSpecCtrl.text.trim().isNotEmpty ||
      costCtrl.text.trim().isNotEmpty ||
      priceCtrl.text.trim().isNotEmpty ||
      storageLocationCtrl.text.trim().isNotEmpty ||
      barcodeCtrl.text.trim().isNotEmpty;

  bool get isCompletelyEmpty => !hasAnyInput;

  void dispose() {
    supplierSkuCtrl.dispose();
    nameCtrl.dispose();
    technicalSpecCtrl.dispose();
    costCtrl.dispose();
    priceCtrl.dispose();
    stockCtrl.dispose();
    storageLocationCtrl.dispose();
    barcodeCtrl.dispose();
  }
}

class SupplierQuickGridDialog extends StatefulWidget {
  final CatalogProvider provider;
  final int? initialSupplierId;
  final String? initialSupplierName;
  final bool alreadyAuthorized;
  final String? authorizedAdminPin;
  final ValueChanged<List<Product>>? onProductsCreated;

  const SupplierQuickGridDialog({
    super.key,
    required this.provider,
    this.initialSupplierId,
    this.initialSupplierName,
    this.alreadyAuthorized = false,
    this.authorizedAdminPin,
    this.onProductsCreated,
  });

  @override
  State<SupplierQuickGridDialog> createState() =>
      _SupplierQuickGridDialogState();
}

class _SupplierQuickGridDialogState extends State<SupplierQuickGridDialog> {
  final List<_QuickGridRowModel> _rows = [];
  final TextEditingController _marginCtrl = TextEditingController(text: '35');
  final ScrollController _horizontalScrollCtrl = ScrollController();

  int? _supplierId;
  int? _categoryId;
  int? _brandId;
  double _ivaRate = 21.0;
  bool _isSaving = false;
  int _savedSoFar = 0;
  int _totalToSave = 0;

  @override
  void initState() {
    super.initState();
    _supplierId =
        widget.initialSupplierId ?? widget.provider.safeFilterSupplierId;
    SettingsProvider? initialSettingsProv;
    try {
      initialSettingsProv = context.read<SettingsProvider?>();
    } catch (_) {}
    final initialProfile = _resolveEffectiveProfile(
      initialSettingsProv,
      widget.provider.categories,
    );
    for (int i = 0; i < 5; i++) {
      _rows.add(_createEmptyRow(initialProfile));
    }
    _loadInitialDefaults();
  }

  Rubro? _resolveCategoryRubro(Category? cat) {
    if (cat == null) return null;
    final rId = cat.rubroId ?? cat.rubro?.id;
    if (rId != null) {
      try {
        final found =
            widget.provider.safeRubros.where((r) => r.id == rId).firstOrNull;
        if (found != null) return found;
      } catch (_) {}
    }
    return cat.rubro;
  }

  BusinessVerticalProfile _resolveEffectiveProfile(
    SettingsProvider? settingsProv,
    List<Category> categories, {
    int? categoryIdOverride,
  }) {
    final baseProfile = settingsProv?.safeVerticalProfile ??
        BusinessVerticalProfile.fromType(BusinessVerticalProfile.retail);
    final effectiveCategoryId = categoryIdOverride ?? _categoryId;
    if (!(settingsProv?.features.multiRubro ?? false) ||
        effectiveCategoryId == null) {
      return baseProfile;
    }
    final cat = categories.where((c) => c.id == effectiveCategoryId).firstOrNull;
    final rubro = _resolveCategoryRubro(cat);
    return baseProfile.forCategoryRubro(rubro);
  }

  _QuickGridRowModel _createEmptyRow([BusinessVerticalProfile? profile]) {
    return _QuickGridRowModel(
      unitType: profile?.defaultUnitType ?? 'un',
      isSoldByWeight: profile?.defaultSoldByWeight ?? false,
    );
  }

  void _applyCategoryDefaultUnitToEmptyRows(
    int? nextCategoryId,
    List<Category> categories,
  ) {
    SettingsProvider? settingsProv;
    try {
      settingsProv = context.read<SettingsProvider?>();
    } catch (_) {}
    final nextProfile = _resolveEffectiveProfile(
      settingsProv,
      categories,
      categoryIdOverride: nextCategoryId,
    );
    for (final row in _rows) {
      if (row.isCompletelyEmpty && !row.userCustomizedUnit) {
        row.unitType = nextProfile.defaultUnitType;
        row.isSoldByWeight = nextProfile.defaultSoldByWeight;
      }
    }
  }

  Future<void> _loadInitialDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMargin = prefs.getDouble('last_profit_margin');
      if (mounted && savedMargin != null && savedMargin >= 0) {
        _marginCtrl.text = savedMargin.toCleanMargin();
      }
    } catch (_) {}

    if (!mounted) return;
    if (widget.provider.categories.isEmpty || widget.provider.brands.isEmpty) {
      await widget.provider.loadMetadata();
    }
    if (!mounted) return;
    try {
      final supProv = context.read<SupplierProvider?>();
      if (supProv != null && supProv.suppliers.isEmpty) {
        supProv.fetchSuppliers();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _marginCtrl.dispose();
    _horizontalScrollCtrl.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  double? _parseDefaultMargin() {
    final raw = _marginCtrl.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    final val = double.tryParse(raw);
    if (val == null || val < 0) return null;
    return val;
  }

  void _recalculateRowPriceFromCost(_QuickGridRowModel row) {
    if (row.manualPriceOverride) return;
    final cost = ArsThousandsInputFormatter.parse(row.costCtrl.text);
    final margin = _parseDefaultMargin();
    if (cost > 0 && margin != null) {
      final pvp = double.parse((cost * (1 + (margin / 100))).toStringAsFixed(2));
      row.priceCtrl.text = pvp.toArsInput();
    }
  }

  void _recalculateAllAutoPrices() {
    setState(() {
      for (final row in _rows) {
        _recalculateRowPriceFromCost(row);
      }
    });
  }

  void _addRows(int count) {
    SettingsProvider? settingsProv;
    try {
      settingsProv = context.read<SettingsProvider?>();
    } catch (_) {}
    final profile = _resolveEffectiveProfile(
      settingsProv,
      widget.provider.categories,
    );
    setState(() {
      for (int i = 0; i < count; i++) {
        _rows.add(_createEmptyRow(profile));
      }
    });
  }

  void _removeRow(int index) {
    if (_rows.length <= 1) return;
    final removed = _rows.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  List<String> _unitOptionsForMode(
    BusinessVerticalProfile profile, [
    String? currentUnit,
  ]) {
    final normalized = (currentUnit ?? '').trim();
    if (normalized.isEmpty || profile.allowedUnitKeys.contains(normalized)) {
      return profile.allowedUnitKeys;
    }
    return [...profile.allowedUnitKeys, normalized];
  }

  Future<void> _submitBatch() async {
    final activeRows = _rows.where((r) => r.hasAnyInput).toList();
    if (activeRows.isEmpty) {
      SnackBarService.warning(
        context,
        'Completá al menos una fila antes de guardar.',
      );
      return;
    }

    bool hasValidationErrors = false;
    setState(() {
      for (final row in _rows) {
        row.errorText = null;
      }
      for (final row in activeRows) {
        final costVal = ArsThousandsInputFormatter.parse(row.costCtrl.text);
        final priceVal = ArsThousandsInputFormatter.parse(row.priceCtrl.text);
        if (row.nameCtrl.text.trim().isEmpty) {
          row.errorText = 'Falta nombre';
          hasValidationErrors = true;
        } else if (row.priceCtrl.text.trim().isEmpty || priceVal <= 0) {
          row.errorText = 'Falta PVP';
          hasValidationErrors = true;
        } else if (costVal > 0 && priceVal < costVal) {
          row.errorText = 'El PVP no puede ser menor al costo';
          hasValidationErrors = true;
        }
      }
    });

    if (hasValidationErrors) {
      SnackBarService.error(
        context,
        'Revisá las filas marcadas en rojo (Nombre, PVP > 0 y PVP ≥ Costo).',
      );
      return;
    }

    SettingsProvider? submitSettingsProv;
    try {
      submitSettingsProv = context.read<SettingsProvider?>();
    } catch (_) {}
    final effectiveProfile = _resolveEffectiveProfile(
      submitSettingsProv,
      widget.provider.categories,
    );

    int createdCount = 0;
    final Set<_QuickGridRowModel> succeededRows = {};
    final List<Product> createdProducts = [];

    Future<void> executeBatchSave() async {
      setState(() {
        _isSaving = true;
        _savedSoFar = 0;
        _totalToSave = activeRows.length;
      });

      for (final row in activeRows) {
        final nameText = row.nameCtrl.text.trim();
        final skuText = row.supplierSkuCtrl.text.trim();
        final specText = row.technicalSpecCtrl.text.trim();
        final locText = row.storageLocationCtrl.text.trim();
        final barcodeText = row.barcodeCtrl.text.trim();
        final stockParsed =
            double.tryParse(row.stockCtrl.text.trim().replaceAll(',', '.')) ??
                0.0;
        final resolvedCalcConfig = row.calcConfig ??
            (effectiveProfile.canUseHardwareCalculator
                ? HardwareCalculatorEngine.tryInferExplicitConfig(
                    name: nameText,
                    technicalSpec: specText.isEmpty ? null : specText,
                  )
                : null);

        final payload = <String, dynamic>{
          'name': nameText,
          'barcode': barcodeText,
          'supplier_sku': skuText.isEmpty ? null : skuText,
          'technical_spec': specText.isEmpty ? null : specText,
          'storage_location': locText.isEmpty ? null : locText,
          'cost_price': ArsThousandsInputFormatter.parse(row.costCtrl.text),
          'selling_price': ArsThousandsInputFormatter.parse(row.priceCtrl.text),
          'iva_rate': _ivaRate,
          'stock': stockParsed < 0 ? 0.0 : stockParsed,
          'is_sold_by_weight': row.isSoldByWeight,
          'is_combo': false,
          'is_service': false,
          'unit_type': row.unitType,
          'active': true,
          'needs_catalog_review': false,
          'category_id': _categoryId,
          'brand_id': _brandId,
          'supplier_id': _supplierId,
          if (resolvedCalcConfig != null) 'calc_config': resolvedCalcConfig,
        };

        final ok = await widget.provider.createProduct(payload);
        if (ok) {
          createdCount++;
          succeededRows.add(row);
          final created = widget.provider.lastCreatedProduct;
          if (created != null && mounted) {
            createdProducts.add(created);
            try {
              context.read<PosProvider?>()?.syncUpdatedCatalogProduct(created);
            } catch (_) {}
            try {
              context.read<OfferProvider?>()?.syncUpdatedProduct(created);
            } catch (_) {}
          }
        } else {
          row.errorText = widget.provider.errorMessage
                  ?.replaceAll('Exception: ', '')
                  .trim() ??
              'Error al guardar';
        }
        if (mounted) {
          setState(() => _savedSoFar++);
        }
      }
    }

    bool authorized = widget.alreadyAuthorized;
    if (authorized) {
      final pin = widget.authorizedAdminPin?.trim();
      if (pin != null && pin.isNotEmpty) {
        ApiClient? client;
        try {
          client = context.read<ApiClient>();
        } catch (_) {}
        if (client != null) {
          await client.withAdminPin(pin, executeBatchSave);
        } else {
          await executeBatchSave();
        }
      } else {
        await executeBatchSave();
      }
    } else {
      authorized = await AdminPinDialog.protectAction(
        context,
        action: 'Carga Rápida de Productos (${activeRows.length} ítems)',
        permissionKey: AppPermissions.manageCatalog,
        onAuthorized: executeBatchSave,
      );
    }

    if (!authorized || !mounted) return;

    final margin = _parseDefaultMargin();
    if (margin != null && createdCount > 0) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('last_profit_margin', margin);
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (createdCount > 0) {
      try {
        context.read<InventoryAlertsProvider?>()?.fetchAlerts();
      } catch (_) {}
      if (createdProducts.isNotEmpty) {
        widget.onProductsCreated?.call(List<Product>.unmodifiable(createdProducts));
      }
    }

    if (succeededRows.length == activeRows.length) {
      Navigator.of(context).pop(createdCount);
      SnackBarService.success(
        context,
        '¡$createdCount productos creados exitosamente!',
      );
      return;
    }

    setState(() {
      for (final row in succeededRows) {
        _rows.remove(row);
        row.dispose();
      }
      if (_rows.isEmpty) {
        _rows.add(_createEmptyRow(effectiveProfile));
      }
    });

    SnackBarService.warning(
      context,
      'Se guardaron $createdCount productos. Corregí las filas con error y reintentá.',
    );
  }

  // Anchos calibrados para aprovechar 100% del modal sin scroll horizontal en pantallas desktop,
  // manteniendo scroll horizontal automático de respaldo en viewports angostos (< 1080px).
  static const double _minGridTableWidth = 1080.0;
  static const double _wIndex = 24.0;
  static const double _wSku = 94.0;
  static const double _wUnit = 76.0;
  static const double _wFrac = 40.0;
  static const double _wCost = 88.0;
  static const double _wPrice = 94.0;
  static const double _wStock = 60.0;
  static const double _wEan = 102.0;
  static const double _wDelete = 32.0;
  static const int _flexName = 5;
  static const int _flexSpec = 2;
  static const int _flexLocation = 2;

  Future<void> _createSupplierQuick({String? initialQuery}) async {
    if (_isSaving) return;
    final createdId = await CatalogQuickCreateDialogs.showCreateSupplier(
      context,
      initialQuery: initialQuery,
    );
    if (createdId != null && mounted) {
      setState(() => _supplierId = createdId);
    }
  }

  Future<void> _createCategoryQuick({String? initialName}) async {
    if (_isSaving) return;
    final createdId = await CatalogQuickCreateDialogs.showCreateCategory(
      context,
      initialName: initialName,
      subtitle: 'Creá una categoría rápida para este lote',
    );
    if (createdId != null && mounted) {
      List<Category> currentCategories;
      try {
        currentCategories = context.read<CatalogProvider>().categories;
      } catch (_) {
        currentCategories = widget.provider.categories;
      }
      setState(() {
        _categoryId = createdId;
        _applyCategoryDefaultUnitToEmptyRows(createdId, currentCategories);
      });
    }
  }

  Future<void> _createBrandQuick({String? initialName}) async {
    if (_isSaving) return;
    final createdId = await CatalogQuickCreateDialogs.showCreateBrand(
      context,
      initialName: initialName,
      subtitle: 'Creá una marca rápida para este lote',
    );
    if (createdId != null && mounted) {
      setState(() => _brandId = createdId);
    }
  }

  Widget _buildQuickAddInlineButton({
    required Key key,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 36,
        height: 40,
        child: IconButton.filledTonal(
          key: key,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
          icon: const Icon(Icons.add, size: 18),
          onPressed: _isSaving ? null : onPressed,
        ),
      ),
    );
  }

  Widget _buildHeaderControls({
    required List<Supplier> suppliers,
    required List<Category> categories,
    required List<Brand> brands,
    required bool canSeeSupplier,
    required bool isResponsableInscripto,
  }) {
    final sortedSuppliers = sortByAlphabeticalName(suppliers, (s) => s.name);
    final sortedCategories = sortByAlphabeticalName(categories, (c) => c.name);
    final sortedBrands = sortByAlphabeticalName(brands, (b) => b.name);

    final hasSup =
        _supplierId != null && sortedSuppliers.any((s) => s.id == _supplierId);
    final showFallbackInitialSupplier =
        !hasSup && _supplierId != null && widget.initialSupplierName != null;
    final supValue =
        (hasSup || showFallbackInitialSupplier) ? _supplierId : null;
    final catValue =
        sortedCategories.any((c) => c.id == _categoryId) ? _categoryId : null;
    final brandValue =
        sortedBrands.any((b) => b.id == _brandId) ? _brandId : null;

    Widget buildSupplierControl() => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: SearchableSelectField<int?>(
                key: const ValueKey('quick_grid_supplier_dropdown'),
                value: supValue,
                clearValue: null,
                isDense: true,
                enabled: !_isSaving,
                labelText: 'Proveedor del lote',
                dialogTitle: 'Seleccionar Proveedor',
                searchHintText: 'Buscar proveedor o CUIT...',
                prefixIcon: Icons.local_shipping_outlined,
                border: const OutlineInputBorder(),
                options: [
                  const SearchableSelectOption<int?>(
                    value: null,
                    label: '— Sin proveedor —',
                    isResetOption: true,
                  ),
                  if (showFallbackInitialSupplier)
                    SearchableSelectOption<int?>(
                      value: _supplierId,
                      label: widget.initialSupplierName!,
                    ),
                  ...sortedSuppliers.map((s) {
                    final hasCuit =
                        s.cuit != null && s.cuit!.trim().isNotEmpty;
                    return SearchableSelectOption<int?>(
                      value: s.id,
                      label: s.name,
                      subtitle: hasCuit ? 'CUIT: ${s.cuit!.trim()}' : null,
                      searchKeywords: hasCuit ? [s.cuit!.trim()] : const [],
                    );
                  }),
                ],
                onChanged: (val) => setState(() => _supplierId = val),
                onCreateNew: (query) =>
                    _createSupplierQuick(initialQuery: query),
                createLabelBuilder: (query) =>
                    'Crear proveedor "${query.trim()}"',
              ),
            ),
            const SizedBox(width: 6),
            _buildQuickAddInlineButton(
              key: const ValueKey('quick_grid_create_supplier_btn'),
              tooltip: 'Crear nuevo proveedor',
              onPressed: () => _createSupplierQuick(),
            ),
          ],
        );

    Widget buildCategoryControl() => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: SearchableSelectField<int?>(
                key: const ValueKey('quick_grid_category_dropdown'),
                value: catValue,
                clearValue: null,
                isDense: true,
                enabled: !_isSaving,
                labelText: 'Categoría por defecto',
                dialogTitle: 'Seleccionar Categoría',
                searchHintText: 'Buscar categoría...',
                prefixIcon: Icons.category_outlined,
                border: const OutlineInputBorder(),
                options: [
                  const SearchableSelectOption<int?>(
                    value: null,
                    label: '— Sin categoría —',
                    isResetOption: true,
                  ),
                  ...sortedCategories.map(
                    (c) => SearchableSelectOption<int?>(
                      value: c.id,
                      label: c.name,
                    ),
                  ),
                ],
                onChanged: (val) => setState(() {
                  _categoryId = val;
                  _applyCategoryDefaultUnitToEmptyRows(val, categories);
                }),
                onCreateNew: (query) =>
                    _createCategoryQuick(initialName: query),
                createLabelBuilder: (query) =>
                    'Crear categoría "${query.trim()}"',
              ),
            ),
            const SizedBox(width: 6),
            _buildQuickAddInlineButton(
              key: const ValueKey('quick_grid_create_category_btn'),
              tooltip: 'Crear nueva categoría',
              onPressed: () => _createCategoryQuick(),
            ),
          ],
        );

    Widget buildBrandControl() => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: SearchableSelectField<int?>(
                key: const ValueKey('quick_grid_brand_dropdown'),
                value: brandValue,
                clearValue: null,
                isDense: true,
                enabled: !_isSaving,
                labelText: 'Marca por defecto',
                dialogTitle: 'Seleccionar Marca',
                searchHintText: 'Buscar marca...',
                prefixIcon: Icons.branding_watermark_outlined,
                border: const OutlineInputBorder(),
                options: [
                  const SearchableSelectOption<int?>(
                    value: null,
                    label: '— Sin marca —',
                    isResetOption: true,
                  ),
                  ...sortedBrands.map(
                    (b) => SearchableSelectOption<int?>(
                      value: b.id,
                      label: b.name,
                    ),
                  ),
                ],
                onChanged: (val) => setState(() => _brandId = val),
                onCreateNew: (query) => _createBrandQuick(initialName: query),
                createLabelBuilder: (query) => 'Crear marca "${query.trim()}"',
              ),
            ),
            const SizedBox(width: 6),
            _buildQuickAddInlineButton(
              key: const ValueKey('quick_grid_create_brand_btn'),
              tooltip: 'Crear nueva marca',
              onPressed: () => _createBrandQuick(),
            ),
          ],
        );

    Widget buildMarginControl() => TextFormField(
          key: const ValueKey('quick_grid_default_margin_field'),
          controller: _marginCtrl,
          enabled: !_isSaving,
          decoration: const InputDecoration(
            labelText: 'Margen sug.',
            suffixText: '%',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => _recalculateAllAutoPrices(),
        );

    Widget buildIvaControl() => DropdownButtonFormField<double>(
          isExpanded: true,
          initialValue: _ivaRate,
          decoration: const InputDecoration(
            labelText: 'IVA lote',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: 21.0, child: Text('21%')),
            DropdownMenuItem(value: 10.5, child: Text('10.5%')),
            DropdownMenuItem(value: 27.0, child: Text('27%')),
            DropdownMenuItem(value: 0.0, child: Text('0%')),
          ],
          onChanged: _isSaving
              ? null
              : (val) => setState(() => _ivaRate = val ?? 21.0),
        );

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 980) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (canSeeSupplier) ...[
                  Expanded(flex: 3, child: buildSupplierControl()),
                  const SizedBox(width: 10),
                ],
                Expanded(flex: 2, child: buildCategoryControl()),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: buildBrandControl()),
                const SizedBox(width: 10),
                SizedBox(width: 118, child: buildMarginControl()),
                if (isResponsableInscripto) ...[
                  const SizedBox(width: 10),
                  SizedBox(width: 102, child: buildIvaControl()),
                ],
              ],
            );
          }

          return Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (canSeeSupplier)
                SizedBox(width: 260, child: buildSupplierControl()),
              SizedBox(width: 230, child: buildCategoryControl()),
              SizedBox(width: 220, child: buildBrandControl()),
              SizedBox(width: 124, child: buildMarginControl()),
              if (isResponsableInscripto)
                SizedBox(width: 104, child: buildIvaControl()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGridHeader(BusinessVerticalProfile profile) {
    const headerStyle = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w800,
      color: Color(0xFFF8FAFC),
    );
    Widget hText(String label, {TextAlign align = TextAlign.left}) => Text(
          label,
          style: headerStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(
          bottom: BorderSide(color: Color(0xFF334155)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(width: _wIndex, child: hText('#')),
          const SizedBox(width: 4),
          SizedBox(width: _wSku, child: hText('Cód. Prov.')),
          const SizedBox(width: 6),
          Expanded(flex: _flexName, child: hText('Nombre *')),
          const SizedBox(width: 6),
          Expanded(flex: _flexSpec, child: hText(profile.quickGridSpecHeader)),
          const SizedBox(width: 6),
          SizedBox(width: _wUnit, child: hText('Unidad')),
          const SizedBox(width: 4),
          if (profile.showQuickGridFracColumn) ...[
            SizedBox(
              width: _wFrac,
              child: Tooltip(
                message: profile.quickGridFracTooltip,
                child: Center(
                  child: hText(
                    profile.quickGridFracHeader,
                    align: TextAlign.center,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ] else
            const SizedBox(width: 2),
          SizedBox(width: _wCost, child: hText('Costo (\$)')),
          const SizedBox(width: 6),
          SizedBox(width: _wPrice, child: hText('PVP Venta *')),
          const SizedBox(width: 6),
          SizedBox(width: _wStock, child: hText('Stock')),
          const SizedBox(width: 6),
          Expanded(
            flex: _flexLocation,
            child: hText(profile.quickGridLocationHeader),
          ),
          const SizedBox(width: 6),
          SizedBox(width: _wEan, child: hText('EAN (Opc.)')),
          const SizedBox(width: 4),
          const SizedBox(width: _wDelete),
        ],
      ),
    );
  }

  Widget _buildGridRow(
    _QuickGridRowModel row,
    int index,
    BusinessVerticalProfile profile,
  ) {
    final unitOptions = _unitOptionsForMode(profile, row.unitType);
    final hasError = row.errorText != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: hasError
            ? Colors.red.shade50
            : (index.isOdd ? const Color(0xFFFAFAFC) : Colors.white),
        border: const Border(
          bottom: BorderSide(color: Color(0xFFF1F5F9)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: _wIndex,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: hasError ? Colors.red.shade700 : Colors.grey.shade600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: _wSku,
                child: TextField(
                  key: ValueKey('quick_grid_sku_$index'),
                  controller: row.supplierSkuCtrl,
                  enabled: !_isSaving,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: const InputDecoration(
                    hintText: 'Cód. / SKU',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 7, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: _flexName,
                child: TextField(
                  key: ValueKey('quick_grid_name_$index'),
                  controller: row.nameCtrl,
                  enabled: !_isSaving,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: const InputDecoration(
                    hintText: 'Nombre artículo *',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    if (row.errorText != null) {
                      setState(() => row.errorText = null);
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: _flexSpec,
                child: TextField(
                  key: ValueKey('quick_grid_spec_$index'),
                  controller: row.technicalSpecCtrl,
                  enabled: !_isSaving,
                  style: const TextStyle(fontSize: 12.5),
                  onChanged: (_) => row.calcConfig = null,
                  decoration: InputDecoration(
                    hintText: profile.quickGridSpecHint,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
                    border: const OutlineInputBorder(),
                    suffixIcon: profile.canUseHardwareCalculator
                        ? IconButton(
                            key: ValueKey('quick_grid_dim_helper_$index'),
                            tooltip: 'Armar medida Madera / Chapa (F7)',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 26,
                              maxWidth: 28,
                              minHeight: 26,
                            ),
                            icon: const Icon(
                              Icons.straighten_rounded,
                              size: 16,
                              color: Color(0xFF0F766E),
                            ),
                            onPressed: _isSaving
                                ? null
                                : () async {
                                    final selection =
                                        await HardwareDimensionHelperDialog
                                            .show(
                                      context,
                                      initialName: row.nameCtrl.text.trim(),
                                      initialSpec:
                                          row.technicalSpecCtrl.text.trim(),
                                      initialConfig: row.calcConfig,
                                    );
                                    if (selection == null || !mounted) return;
                                    setState(() {
                                      row.technicalSpecCtrl.text =
                                          selection.specText;
                                      row.calcConfig = selection.calcConfig;
                                    });
                                  },
                          )
                        : (profile.isApparel
                            ? IconButton(
                                key: ValueKey('quick_grid_apparel_helper_$index'),
                                tooltip: 'Asistente rápido de Talle y Color',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 26,
                                  maxWidth: 28,
                                  minHeight: 26,
                                ),
                                icon: const Icon(
                                  Icons.checkroom_rounded,
                                  size: 16,
                                  color: Color(0xFF4F46E5),
                                ),
                                onPressed: _isSaving
                                    ? null
                                    : () async {
                                        final selected =
                                            await ApparelVariantHelperDialog.show(
                                          context,
                                          initialValue:
                                              row.technicalSpecCtrl.text.trim(),
                                        );
                                        if (selected == null || !mounted) return;
                                        setState(() {
                                          row.technicalSpecCtrl.text = selected;
                                          row.calcConfig = null;
                                        });
                                      },
                              )
                            : null),
                    suffixIconConstraints: (profile.canUseHardwareCalculator ||
                            profile.isApparel)
                        ? const BoxConstraints(
                            minWidth: 26,
                            maxWidth: 28,
                            minHeight: 26,
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: _wUnit,
                child: KeyedSubtree(
                  key: ValueKey('quick_grid_unit_$index'),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('quick_grid_unit_dd_${index}_${row.unitType}'),
                    isExpanded: true,
                    initialValue: unitOptions.contains(row.unitType)
                        ? row.unitType
                        : unitOptions.first,
                    style: const TextStyle(fontSize: 12.5, color: Colors.black87),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      border: OutlineInputBorder(),
                    ),
                    items: unitOptions
                        .map(
                          (u) => DropdownMenuItem<String>(
                            value: u,
                            child: Text(
                              Product.shortLabelFor(u),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _isSaving
                        ? null
                        : (val) {
                            if (val == null) return;
                            setState(() {
                              row.userCustomizedUnit = true;
                              row.unitType = val;
                              row.isSoldByWeight =
                                  !Product.discreteUnitTypes.contains(val);
                            });
                          },
                  ),
                ),
              ),
              const SizedBox(width: 4),
              if (profile.showQuickGridFracColumn) ...[
                SizedBox(
                  width: _wFrac,
                  child: Tooltip(
                    message: profile.quickGridFracTooltip,
                    child: Center(
                      child: Checkbox(
                        value: row.isSoldByWeight,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: _isSaving
                            ? null
                            : (v) => setState(() {
                                  row.userCustomizedUnit = true;
                                  row.isSoldByWeight = v ?? false;
                                }),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ] else
                const SizedBox(width: 2),
              SizedBox(
                width: _wCost,
                child: TextField(
                  key: ValueKey('quick_grid_cost_$index'),
                  controller: row.costCtrl,
                  enabled: !_isSaving,
                  style: const TextStyle(fontSize: 12.5),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [ArsThousandsInputFormatter()],
                  decoration: const InputDecoration(
                    hintText: '0',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 7, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _recalculateRowPriceFromCost(row),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: _wPrice,
                child: TextField(
                  key: ValueKey('quick_grid_price_$index'),
                  controller: row.priceCtrl,
                  enabled: !_isSaving,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [ArsThousandsInputFormatter()],
                  decoration: const InputDecoration(
                    hintText: '0 *',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 7, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) {
                    row.manualPriceOverride = val.trim().isNotEmpty;
                    if (row.errorText != null) {
                      setState(() => row.errorText = null);
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: _wStock,
                child: TextField(
                  key: ValueKey('quick_grid_stock_$index'),
                  controller: row.stockCtrl,
                  enabled: !_isSaving,
                  style: const TextStyle(fontSize: 12.5),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    hintText: '0',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 7, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: _flexLocation,
                child: TextField(
                  key: ValueKey('quick_grid_location_$index'),
                  controller: row.storageLocationCtrl,
                  enabled: !_isSaving,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: InputDecoration(
                    hintText: profile.quickGridLocationHint,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: _wEan,
                child: TextField(
                  key: ValueKey('quick_grid_barcode_$index'),
                  controller: row.barcodeCtrl,
                  enabled: !_isSaving,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: const InputDecoration(
                    hintText: 'EAN opc.',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 7, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: _wDelete,
                child: IconButton(
                  key: ValueKey('quick_grid_delete_row_$index'),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: _wDelete, minHeight: 32),
                  icon: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: _rows.length > 1
                        ? Colors.red.shade400
                        : Colors.grey.shade300,
                  ),
                  tooltip: 'Quitar fila',
                  onPressed: (_isSaving || _rows.length <= 1)
                      ? null
                      : () => _removeRow(index),
                ),
              ),
            ],
          ),
          if (hasError)
            Padding(
              padding: const EdgeInsets.only(left: _wIndex + 4, top: 4),
              child: Text(
                row.errorText!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.red.shade700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalogProv = context.watch<CatalogProvider>();
    SettingsProvider? settingsProv;
    SupplierProvider? supplierProv;
    try {
      settingsProv = context.watch<SettingsProvider?>();
    } catch (_) {}
    try {
      supplierProv = context.watch<SupplierProvider?>();
    } catch (_) {}

    final canSeeSupplier =
        (settingsProv?.features.suppliers ?? true) && supplierProv != null;
    final isResponsableInscripto =
        settingsProv?.settings?.isResponsableInscripto ?? false;
    final effectiveProfile =
        _resolveEffectiveProfile(settingsProv, catalogProv.categories);

    return AppModalShell(
      title: 'Carga Rápida en Grilla por Proveedor',
      subtitle: 'Alta rápida de catálogo (no registra factura ni deuda en Cuenta Corriente) • Cálculo automático de PVP',
      icon: Icons.grid_on_rounded,
      accent: AppModalAccent.indigo,
      maxWidth: 1560,
      maxHeight: 860,
      expandBody: true,
      onClose: _isSaving ? null : () => Navigator.of(context).pop(),
      bodyPadding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeaderControls(
            suppliers: supplierProv?.suppliers ?? const [],
            categories: catalogProv.categories,
            brands: catalogProv.brands,
            canSeeSupplier: canSeeSupplier,
            isResponsableInscripto: isResponsableInscripto,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tableWidth =
                      math.max(_minGridTableWidth, constraints.maxWidth);
                  final needsHorizontalScroll =
                      tableWidth > constraints.maxWidth + 0.5;
                  return Scrollbar(
                    controller: _horizontalScrollCtrl,
                    thumbVisibility: needsHorizontalScroll,
                    child: SingleChildScrollView(
                      key: const ValueKey('quick_grid_horizontal_scroll'),
                      controller: _horizontalScrollCtrl,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: tableWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildGridHeader(effectiveProfile),
                            Expanded(
                              child: ListView.builder(
                                itemCount: _rows.length,
                                itemBuilder: (_, index) => _buildGridRow(
                                  _rows[index],
                                  index,
                                  effectiveProfile,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      footerLeading: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('quick_grid_add_1_row_btn'),
            onPressed: _isSaving ? null : () => _addRows(1),
            icon: const Icon(Icons.add, size: 17),
            label: const Text('+1 Fila'),
          ),
          OutlinedButton.icon(
            key: const ValueKey('quick_grid_add_5_rows_btn'),
            onPressed: _isSaving ? null : () => _addRows(5),
            icon: const Icon(Icons.playlist_add, size: 17),
            label: const Text('+5 Filas'),
          ),
          if (MediaQuery.of(context).size.width >= 1120 || _isSaving)
            Text(
              _isSaving
                  ? 'Guardando $_savedSoFar / $_totalToSave...'
                  : 'Tip: tipeá Costo para calcular el PVP automáticamente con el % Margen.',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
        ],
      ),
      footerActions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          key: const ValueKey('quick_grid_submit_btn'),
          onPressed: _isSaving ? null : _submitBatch,
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_rounded, size: 18),
          label: const Text('Guardar Lote en Catálogo'),
        ),
      ],
    );
  }
}
