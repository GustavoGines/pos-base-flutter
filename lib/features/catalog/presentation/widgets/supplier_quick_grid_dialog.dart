import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/constants/app_permissions.dart';
import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/core/utils/search_text_utils.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/features/auth/presentation/widgets/admin_pin_dialog.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/offers/presentation/providers/offer_provider.dart';
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

  String unitType = 'un';
  bool isSoldByWeight = false;
  bool manualPriceOverride = false;
  String? errorText;

  bool get hasAnyInput =>
      supplierSkuCtrl.text.trim().isNotEmpty ||
      nameCtrl.text.trim().isNotEmpty ||
      technicalSpecCtrl.text.trim().isNotEmpty ||
      costCtrl.text.trim().isNotEmpty ||
      priceCtrl.text.trim().isNotEmpty ||
      storageLocationCtrl.text.trim().isNotEmpty ||
      barcodeCtrl.text.trim().isNotEmpty;

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

  const SupplierQuickGridDialog({
    super.key,
    required this.provider,
    this.initialSupplierId,
    this.initialSupplierName,
    this.alreadyAuthorized = false,
    this.authorizedAdminPin,
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
    for (int i = 0; i < 5; i++) {
      _rows.add(_QuickGridRowModel());
    }
    _loadInitialDefaults();
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
    setState(() {
      for (int i = 0; i < count; i++) {
        _rows.add(_QuickGridRowModel());
      }
    });
  }

  void _removeRow(int index) {
    if (_rows.length <= 1) return;
    final removed = _rows.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  List<String> _unitOptionsForMode(bool isHardwareStore) {
    if (isHardwareStore) {
      return const [
        'un',
        'mt',
        'm2',
        'm3',
        'bolsa',
        'rollo',
        'caja',
        'par',
        'kg',
        'g',
        'lt',
      ];
    }
    return const ['un', 'kg', 'g', 'lt'];
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

    int createdCount = 0;
    final Set<_QuickGridRowModel> succeededRows = {};

    Future<void> executeBatchSave() async {
      setState(() {
        _isSaving = true;
        _savedSoFar = 0;
        _totalToSave = activeRows.length;
      });

      for (final row in activeRows) {
        final skuText = row.supplierSkuCtrl.text.trim();
        final specText = row.technicalSpecCtrl.text.trim();
        final locText = row.storageLocationCtrl.text.trim();
        final barcodeText = row.barcodeCtrl.text.trim();
        final stockParsed =
            double.tryParse(row.stockCtrl.text.trim().replaceAll(',', '.')) ??
                0.0;

        final payload = <String, dynamic>{
          'name': row.nameCtrl.text.trim(),
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
        };

        final ok = await widget.provider.createProduct(payload);
        if (ok) {
          createdCount++;
          succeededRows.add(row);
          final created = widget.provider.lastCreatedProduct;
          if (created != null && mounted) {
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
        _rows.add(_QuickGridRowModel());
      }
    });

    SnackBarService.warning(
      context,
      'Se guardaron $createdCount productos. Corregí las filas con error y reintentá.',
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
    final supValue = hasSup
        ? _supplierId
        : (_supplierId != null && widget.initialSupplierName != null
            ? _supplierId
            : null);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          if (canSeeSupplier)
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<int?>(
                key: const ValueKey('quick_grid_supplier_dropdown'),
                isExpanded: true,
                initialValue: supValue,
                decoration: const InputDecoration(
                  labelText: 'Proveedor del lote',
                  prefixIcon: Icon(Icons.local_shipping_outlined, size: 18),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('— Sin proveedor —'),
                  ),
                  if (!hasSup &&
                      _supplierId != null &&
                      widget.initialSupplierName != null)
                    DropdownMenuItem<int?>(
                      value: _supplierId,
                      child: Text(widget.initialSupplierName!),
                    ),
                  ...sortedSuppliers.map(
                    (s) => DropdownMenuItem<int?>(
                      value: s.id,
                      child: Text(s.name, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: _isSaving
                    ? null
                    : (val) => setState(() => _supplierId = val),
              ),
            ),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<int?>(
              key: const ValueKey('quick_grid_category_dropdown'),
              isExpanded: true,
              initialValue: sortedCategories.any((c) => c.id == _categoryId)
                  ? _categoryId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Categoría por defecto',
                prefixIcon: Icon(Icons.category_outlined, size: 18),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('— Sin categoría —'),
                ),
                ...sortedCategories.map(
                  (c) => DropdownMenuItem<int?>(
                    value: c.id,
                    child: Text(c.name, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged:
                  _isSaving ? null : (val) => setState(() => _categoryId = val),
            ),
          ),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<int?>(
              key: const ValueKey('quick_grid_brand_dropdown'),
              isExpanded: true,
              initialValue:
                  sortedBrands.any((b) => b.id == _brandId) ? _brandId : null,
              decoration: const InputDecoration(
                labelText: 'Marca por defecto',
                prefixIcon: Icon(Icons.branding_watermark_outlined, size: 18),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('— Sin marca —'),
                ),
                ...sortedBrands.map(
                  (b) => DropdownMenuItem<int?>(
                    value: b.id,
                    child: Text(b.name, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged:
                  _isSaving ? null : (val) => setState(() => _brandId = val),
            ),
          ),
          SizedBox(
            width: 145,
            child: TextFormField(
              key: const ValueKey('quick_grid_default_margin_field'),
              controller: _marginCtrl,
              enabled: !_isSaving,
              decoration: const InputDecoration(
                labelText: '% Margen sug.',
                suffixText: '%',
                prefixIcon: Icon(Icons.percent, size: 17),
                isDense: true,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => _recalculateAllAutoPrices(),
            ),
          ),
          if (isResponsableInscripto)
            SizedBox(
              width: 120,
              child: DropdownButtonFormField<double>(
                isExpanded: true,
                initialValue: _ivaRate,
                decoration: const InputDecoration(
                  labelText: 'IVA lote',
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
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGridHeader() {
    const headerStyle = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w800,
      color: Color(0xFFF8FAFC),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(
          bottom: BorderSide(color: Color(0xFF334155)),
        ),
      ),
      child: const Row(
        children: [
          SizedBox(width: 28, child: Text('#', style: headerStyle)),
          SizedBox(width: 105, child: Text('Cód. Prov.', style: headerStyle)),
          SizedBox(width: 8),
          SizedBox(width: 215, child: Text('Nombre *', style: headerStyle)),
          SizedBox(width: 8),
          SizedBox(width: 125, child: Text('Medida / Espec.', style: headerStyle)),
          SizedBox(width: 8),
          SizedBox(width: 92, child: Text('Unidad', style: headerStyle)),
          SizedBox(width: 48, child: Center(child: Text('Fracc.', style: headerStyle))),
          SizedBox(width: 8),
          SizedBox(width: 100, child: Text('Costo (\$)', style: headerStyle)),
          SizedBox(width: 8),
          SizedBox(width: 108, child: Text('PVP Venta *', style: headerStyle)),
          SizedBox(width: 8),
          SizedBox(width: 72, child: Text('Stock', style: headerStyle)),
          SizedBox(width: 8),
          SizedBox(width: 115, child: Text('Ubicación', style: headerStyle)),
          SizedBox(width: 8),
          SizedBox(width: 115, child: Text('EAN (Opc.)', style: headerStyle)),
          SizedBox(width: 34),
        ],
      ),
    );
  }

  Widget _buildGridRow(
    _QuickGridRowModel row,
    int index,
    List<String> unitOptions,
  ) {
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
                width: 28,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: hasError ? Colors.red.shade700 : Colors.grey.shade600,
                  ),
                ),
              ),
              SizedBox(
                width: 105,
                child: TextField(
                  key: ValueKey('quick_grid_sku_$index'),
                  controller: row.supplierSkuCtrl,
                  enabled: !_isSaving,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: const InputDecoration(
                    hintText: 'SKU Prov.',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 215,
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
              const SizedBox(width: 8),
              SizedBox(
                width: 125,
                child: TextField(
                  key: ValueKey('quick_grid_spec_$index'),
                  controller: row.technicalSpecCtrl,
                  enabled: !_isSaving,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: const InputDecoration(
                    hintText: '1/2" / 2.5mm',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 92,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('quick_grid_unit_$index'),
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
                          child: Text(Product.shortLabelFor(u)),
                        ),
                      )
                      .toList(),
                  onChanged: _isSaving
                      ? null
                      : (val) {
                          if (val == null) return;
                          setState(() {
                            row.unitType = val;
                            row.isSoldByWeight =
                                !Product.discreteUnitTypes.contains(val);
                          });
                        },
                ),
              ),
              SizedBox(
                width: 48,
                child: Checkbox(
                  value: row.isSoldByWeight,
                  visualDensity: VisualDensity.compact,
                  onChanged: _isSaving
                      ? null
                      : (v) => setState(() => row.isSoldByWeight = v ?? false),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
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
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _recalculateRowPriceFromCost(row),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 108,
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
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
              const SizedBox(width: 8),
              SizedBox(
                width: 72,
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
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 115,
                child: TextField(
                  key: ValueKey('quick_grid_location_$index'),
                  controller: row.storageLocationCtrl,
                  enabled: !_isSaving,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: const InputDecoration(
                    hintText: 'Estante / Gav.',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 115,
                child: TextField(
                  key: ValueKey('quick_grid_barcode_$index'),
                  controller: row.barcodeCtrl,
                  enabled: !_isSaving,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: const InputDecoration(
                    hintText: 'EAN opc.',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 34,
                child: IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: _rows.length > 1
                        ? Colors.red.shade400
                        : Colors.grey.shade300,
                  ),
                  tooltip: 'Quitar fila',
                  onPressed:
                      (_isSaving || _rows.length <= 1) ? null : () => _removeRow(index),
                ),
              ),
            ],
          ),
          if (hasError)
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 4),
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

    final isHardwareStore = settingsProv?.safeIsHardwareStore ?? false;
    final canSeeSupplier =
        (settingsProv?.features.suppliers ?? true) && supplierProv != null;
    final isResponsableInscripto =
        settingsProv?.settings?.isResponsableInscripto ?? false;
    final unitOptions = _unitOptionsForMode(isHardwareStore);

    return AppModalShell(
      title: 'Carga Rápida en Grilla por Proveedor',
      subtitle: 'Alta rápida de catálogo (no registra factura ni deuda en Cuenta Corriente) • Cálculo automático de PVP',
      icon: Icons.grid_on_rounded,
      accent: AppModalAccent.indigo,
      maxWidth: 1240,
      maxHeight: 820,
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
              child: Scrollbar(
                controller: _horizontalScrollCtrl,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _horizontalScrollCtrl,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: 1280,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildGridHeader(),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _rows.length,
                            itemBuilder: (_, index) => _buildGridRow(
                              _rows[index],
                              index,
                              unitOptions,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
