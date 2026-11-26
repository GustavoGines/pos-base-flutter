import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/presentation/widgets/app_modal_shell.dart';
import '../../../../core/presentation/widgets/compact_date_range_picker_dialog.dart';
import '../../../../core/services/remote_scanner_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/image_url_resolver.dart';
import '../../../../core/utils/snack_bar_service.dart';

import '../../providers/supplier_provider.dart';
import '../../../pos/presentation/providers/pos_provider.dart';
import '../../../../core/config/business_vertical_profile.dart';
import '../../../catalog/domain/entities/product.dart';
import '../../../catalog/domain/entities/rubro.dart';
import '../../../catalog/presentation/widgets/supplier_quick_grid_dialog.dart';
import 'supplier_purchase_assistant_panel.dart';
import '../../../cash_movements/presentation/widgets/movement_form_dialog.dart';
import '../../../../core/constants/app_permissions.dart';
import '../../../auth/presentation/widgets/admin_pin_dialog.dart';
import '../../../settings/presentation/providers/settings_provider.dart';

import '../../../catalog/presentation/providers/catalog_provider.dart';
import '../../../catalog/presentation/pages/catalog_screen.dart' show ProductFormDialog;
import '../../../reports/presentation/providers/inventory_alerts_provider.dart';
import 'dart:async';

class _InvoiceItemModel {
  final Product product;
  double quantity;
  double newCost;
  double? suggestedPrice;
  double manualPrice;
  bool updatePrice;
  double vatRate; // 21.0 | 10.5 | 27.0 | 0.0
  String priceAnchor = 'cost'; // 'cost' | 'selling'
  bool enterByPackage = false;
  bool? linkSupplier;
  int? batchId;
  DateTime? expirationDate;
  bool showLotFields = false;
  late final TextEditingController qtyCtrl;
  late final TextEditingController costCtrl;
  late final TextEditingController marginCtrl;
  late final TextEditingController pvpCtrl;
  late final TextEditingController batchCodeCtrl;
  late final TextEditingController validityDaysCtrl;

  bool get hasPackageConversion =>
      product.conversionFactor != null && product.conversionFactor! > 1;

  double get conversionFactor =>
      hasPackageConversion ? product.conversionFactor! : 1.0;

  String get packageLabel =>
      (product.purchasePackageName != null &&
              product.purchasePackageName!.trim().isNotEmpty)
          ? product.purchasePackageName!.trim()
          : 'Bulto';

  void switchInputMode(bool byPackage) {
    if (!hasPackageConversion || enterByPackage == byPackage) return;
    enterByPackage = byPackage;
    if (byPackage) {
      // Si el usuario acaba de agregar la fila con 1 unidad suelta,
      // al pasar a bulto asumimos 1 bulto completo para evitar 0.01 bultos.
      if ((quantity - 1.0).abs() < 0.0001) {
        quantity = conversionFactor;
      }
      final pkgQty = quantity / conversionFactor;
      qtyCtrl.text = (pkgQty - pkgQty.roundToDouble()).abs() < 0.0005
          ? pkgQty.round().toString()
          : pkgQty.toStringAsFixed(2);
      final pkgCost = newCost * conversionFactor;
      costCtrl.text = pkgCost > 0 ? pkgCost.toArsInput() : '';
    } else {
      qtyCtrl.text = product.isSoldByWeight || product.unitType == 'kg'
          ? quantity.toStringAsFixed(3)
          : ((quantity - quantity.roundToDouble()).abs() < 0.0005
              ? quantity.round().toString()
              : quantity.toStringAsFixed(2));
      costCtrl.text = newCost > 0 ? newCost.toArsInput() : '';
    }
  }

  _InvoiceItemModel({
    required this.product,
    this.quantity = 1,
    required this.newCost,
    required this.manualPrice,
    this.updatePrice = true,
    this.vatRate = 21.0,
    this.linkSupplier,
    this.batchId,
    String? batchCode,
    this.expirationDate,
    bool autoDefaultExpiry = false,
  }) {
    priceAnchor = newCost > 0 ? 'cost' : 'selling';
    final qtyStr = product.isSoldByWeight || product.unitType == 'kg'
        ? quantity.toStringAsFixed(3)
        : (quantity % 1 == 0 ? quantity.toInt().toString() : quantity.toStringAsFixed(2));
    qtyCtrl = TextEditingController(text: qtyStr);
    costCtrl = TextEditingController(
      text: newCost > 0 ? newCost.toArsInput() : '',
    );
    pvpCtrl = TextEditingController(
      text: manualPrice > 0 ? manualPrice.toArsInput() : '',
    );
    final initialMargin = (newCost > 0 && manualPrice > 0)
        ? (((manualPrice - newCost) / newCost) * 100)
        : 0.0;
    marginCtrl = TextEditingController(
      text: initialMargin > 0 ? initialMargin.toCleanMargin() : '',
    );
    batchCodeCtrl = TextEditingController(text: batchCode ?? '');
    if (autoDefaultExpiry &&
        expirationDate == null &&
        product.vencimientoDias != null &&
        product.vencimientoDias! > 0) {
      expirationDate =
          DateTime.now().add(Duration(days: product.vencimientoDias!));
    }
    if (expirationDate != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final expDay = DateTime(
        expirationDate!.year,
        expirationDate!.month,
        expirationDate!.day,
      );
      final diff = expDay.difference(today).inDays;
      validityDaysCtrl = TextEditingController(
        text: (diff >= 1 && diff <= 3650) ? diff.toString() : '',
      );
    } else {
      validityDaysCtrl = TextEditingController();
    }
    showLotFields = product.trackBatches ||
        (batchCode != null && batchCode.isNotEmpty) ||
        expirationDate != null;
  }

  void dispose() {
    qtyCtrl.dispose();
    costCtrl.dispose();
    marginCtrl.dispose();
    pvpCtrl.dispose();
    batchCodeCtrl.dispose();
    validityDaysCtrl.dispose();
  }

  double get subtotal => quantity * newCost;
}

class SupplierInvoiceFormDialog extends StatefulWidget {
  final int supplierId;
  final String supplierName;
  final Map<String, dynamic>? initialInvoice;
  final String? authorizedAdminPin;

  const SupplierInvoiceFormDialog({
    super.key,
    required this.supplierId,
    required this.supplierName,
    this.initialInvoice,
    this.authorizedAdminPin,
  });

  @override
  State<SupplierInvoiceFormDialog> createState() => _SupplierInvoiceFormDialogState();
}

class _SupplierInvoiceFormDialogState extends State<SupplierInvoiceFormDialog> {
  final _formKey = GlobalKey<FormState>();
  String _type = 'invoice';
  final _invoiceNumberController = TextEditingController();
  final _descriptionController = TextEditingController(text: 'Mercadería');
  final _editReasonController = TextEditingController();
  final _freightCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();

  // ── Fiscal Controllers & State (ARCA / AFIP - Responsable Inscripto) ──
  String _voucherLetter = 'A';
  bool _affectsVatBook = true;
  bool _isFiscalExpanded = true;
  bool _autoSyncFiscal21 = true;
  bool _costsIncludeVat = true; // true: costos cargados con IVA inc. | false: costos netos + IVA (Mayorista)
  String? _selectedIibbMode; // '1_net', '1.5_net', '2_net', '2_gross', '2.5_net', '3_net', '3_gross', '4_net'
  bool _didInitSupplierMeta = false;
  String? _supplierTaxCategory;
  String? _supplierCuit;
  String? _lastAutoInvoiceNumber;
  final _pointOfSaleCtrl = TextEditingController();
  final _voucherNumberCtrl = TextEditingController();
  final _net21Ctrl = TextEditingController();
  final _iva21Ctrl = TextEditingController();
  final _net105Ctrl = TextEditingController();
  final _iva105Ctrl = TextEditingController();
  final _net27Ctrl = TextEditingController();
  final _iva27Ctrl = TextEditingController();
  final _ivaPerceptionCtrl = TextEditingController();
  final _iibbPerceptionCtrl = TextEditingController();
  final _nonTaxedCtrl = TextEditingController();
  final _exemptCtrl = TextEditingController();
  final _internalTaxesCtrl = TextEditingController();

  final _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;
  List<Product> _searchResults = [];
  bool _isSearching = false;

  final List<_InvoiceItemModel> _items = [];

  bool _isLoading = false;
  bool _payNow = true;

  DateTime? _issueDate = DateTime.now();
  DateTime? _dueDate;

  double _taxAmount = 0.0;
  double _freightAmount = 0.0;
  double _discountAmount = 0.0;

  String? _attachmentUrl;
  String? _localAttachmentPath;
  // ignore: prefer_final_fields
  bool _isUploading = false;

  List<String> _recentSearches = [];
  SupplierPurchaseAssistantData _assistantData =
      const SupplierPurchaseAssistantData();
  bool _isLoadingAssistant = false;
  bool _showAssistantPanel = false;
  bool _didLoadAssistant = false;

  bool get _isEditing => widget.initialInvoice != null;

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
    final inv = widget.initialInvoice;
    if (inv != null) {
      _payNow = false;
      _autoSyncFiscal21 = false;
      _type = inv['type']?.toString() ?? 'invoice';
      _invoiceNumberController.text = inv['invoice_number']?.toString() ?? '';
      _descriptionController.text = inv['description']?.toString() ?? 'Mercadería';
      final rawIssue = inv['issue_date']?.toString() ?? inv['date']?.toString();
      if (rawIssue != null) {
        _issueDate = DateTime.tryParse(rawIssue)?.toLocal() ?? DateTime.now();
      }
      final rawDue = inv['due_date']?.toString();
      if (rawDue != null && rawDue.isNotEmpty) {
        _dueDate = DateTime.tryParse(rawDue);
      }
      _taxAmount = double.tryParse((inv['tax_amount'] ?? 0).toString()) ?? 0.0;
      _freightAmount = double.tryParse((inv['freight_amount'] ?? 0).toString()) ?? 0.0;
      _discountAmount = double.tryParse((inv['discount_amount'] ?? 0).toString()) ?? 0.0;

      _freightCtrl.text = _freightAmount > 0 ? _freightAmount.toArsInput() : '';
      _taxCtrl.text = _taxAmount > 0 ? _taxAmount.toArsInput() : '';
      _discountCtrl.text = _discountAmount > 0 ? _discountAmount.toArsInput() : '';
      _attachmentUrl = inv['receipt_file_url']?.toString();

      // ── Carga de Campos Fiscales ──
      final letter = inv['voucher_letter']?.toString().toUpperCase();
      if (letter != null && ['A', 'B', 'C', 'M', 'X'].contains(letter)) {
        _voucherLetter = letter;
      }
      if (inv['affects_vat_book'] != null) {
        _affectsVatBook = inv['affects_vat_book'] == 1 ||
            inv['affects_vat_book'] == true ||
            inv['affects_vat_book'].toString() == 'true';
      }
      if (inv['point_of_sale'] != null) {
        _pointOfSaleCtrl.text = inv['point_of_sale'].toString();
      }
      if (inv['voucher_number'] != null) {
        _voucherNumberCtrl.text = inv['voucher_number'].toString();
      }
      final n21 = double.tryParse((inv['net_21'] ?? '').toString()) ?? 0.0;
      if (n21 > 0) _net21Ctrl.text = n21.toArsInput();
      final i21 = double.tryParse((inv['iva_21'] ?? '').toString()) ?? 0.0;
      if (i21 > 0) _iva21Ctrl.text = i21.toArsInput();

      final n105 = double.tryParse((inv['net_105'] ?? '').toString()) ?? 0.0;
      if (n105 > 0) _net105Ctrl.text = n105.toArsInput();
      final i105 = double.tryParse((inv['iva_105'] ?? '').toString()) ?? 0.0;
      if (i105 > 0) _iva105Ctrl.text = i105.toArsInput();

      final n27 = double.tryParse((inv['net_27'] ?? '').toString()) ?? 0.0;
      if (n27 > 0) _net27Ctrl.text = n27.toArsInput();
      final i27 = double.tryParse((inv['iva_27'] ?? '').toString()) ?? 0.0;
      if (i27 > 0) _iva27Ctrl.text = i27.toArsInput();

      final ivaP = double.tryParse((inv['iva_perception'] ?? '').toString()) ?? 0.0;
      if (ivaP > 0) _ivaPerceptionCtrl.text = ivaP.toArsInput();
      final iibbP = double.tryParse((inv['iibb_perception'] ?? '').toString()) ?? 0.0;
      if (iibbP > 0) _iibbPerceptionCtrl.text = iibbP.toArsInput();

      final nonT = double.tryParse((inv['non_taxed_amount'] ?? '').toString()) ?? 0.0;
      if (nonT > 0) _nonTaxedCtrl.text = nonT.toArsInput();
      final ex = double.tryParse((inv['exempt_amount'] ?? '').toString()) ?? 0.0;
      if (ex > 0) _exemptCtrl.text = ex.toArsInput();
      final intT = double.tryParse((inv['internal_taxes'] ?? '').toString()) ?? 0.0;
      if (intT > 0) _internalTaxesCtrl.text = intT.toArsInput();

      final hasAnyFiscalAmount = (n21 + i21 + n105 + i105 + n27 + i27 + ivaP + iibbP + nonT + ex + intT) > 0;
      if ((letter == null || letter.isEmpty || letter == 'S/D') && !hasAnyFiscalAmount) {
        _voucherLetter = 'S/D';
      }

      double defaultExistingVatRate = 21.0;
      if (n105 > 0 && n21 == 0 && n27 == 0) {
        defaultExistingVatRate = 10.5;
      } else if (n27 > 0 && n21 == 0 && n105 == 0) {
        defaultExistingVatRate = 27.0;
      } else if (ex > 0 && n21 == 0 && n105 == 0 && n27 == 0) {
        defaultExistingVatRate = 0.0;
      }

      final rawItems = inv['items'] as List<dynamic>? ?? [];
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final prodMap = map['product'] is Map
            ? Map<String, dynamic>.from(map['product'] as Map)
            : <String, dynamic>{};

        final productId = int.tryParse((map['product_id'] ?? prodMap['id'] ?? 0).toString()) ?? 0;
        if (productId <= 0) continue;

        final qty = double.tryParse((map['quantity'] ?? 1).toString()) ?? 1.0;
        final unitCost = double.tryParse((map['unit_cost'] ?? 0).toString()) ?? 0.0;
        final prevCost = double.tryParse(
                (map['previous_cost'] ??
                        map['current_cost_price'] ??
                        prodMap['cost_price'] ??
                        unitCost)
                    .toString()) ??
            unitCost;
        final newSelling = map['new_selling_price'] != null
            ? double.tryParse(map['new_selling_price'].toString())
            : null;
        final currentSelling = double.tryParse(
                (map['current_selling_price'] ??
                        prodMap['selling_price'] ??
                        newSelling ??
                        0)
                    .toString()) ??
            0.0;
        final unitType =
            map['unit_type']?.toString() ?? prodMap['unit_type']?.toString() ?? 'un';
        final isWeight = map['is_sold_by_weight'] == true ||
            map['is_sold_by_weight'] == 1 ||
            prodMap['is_sold_by_weight'] == true ||
            prodMap['is_sold_by_weight'] == 1 ||
            unitType == 'kg';

        final product = Product(
          id: productId,
          name: map['product_name']?.toString() ??
              prodMap['name']?.toString() ??
              'Producto #$productId',
          barcode: map['barcode']?.toString() ?? prodMap['barcode']?.toString(),
          internalCode: map['internal_code']?.toString() ??
              prodMap['internal_code']?.toString() ??
              '',
          costPrice: prevCost,
          sellingPrice: currentSelling,
          stock: double.tryParse((map['stock'] ?? prodMap['stock'] ?? 0).toString()) ?? 0.0,
          active: true,
          isSoldByWeight: isWeight,
          unitType: unitType,
          supplierSku: map['supplier_sku']?.toString() ??
              prodMap['supplier_sku']?.toString(),
          technicalSpec: map['technical_spec']?.toString() ??
              prodMap['technical_spec']?.toString(),
          purchasePackageName: map['purchase_package_name']?.toString() ??
              prodMap['purchase_package_name']?.toString(),
          conversionFactor: double.tryParse(
            (map['conversion_factor'] ?? prodMap['conversion_factor'] ?? '')
                .toString(),
          ),
          trackBatches: map['track_batches'] == true ||
              map['track_batches'] == 1 ||
              prodMap['track_batches'] == true ||
              prodMap['track_batches'] == 1,
          vencimientoDias: int.tryParse(
              (map['vencimiento_dias'] ?? prodMap['vencimiento_dias'] ?? '').toString()),
        );

        _items.add(
          _InvoiceItemModel(
            product: product,
            quantity: qty,
            newCost: unitCost,
            manualPrice: newSelling ?? currentSelling,
            // En modo edición, no forzamos la reescritura del precio de venta en catálogo
            // salvo que el usuario modifique el PVP o marque la casilla explícitamente.
            updatePrice: false,
            vatRate: defaultExistingVatRate,
            batchId: (map['batch_id'] as num?)?.toInt(),
            batchCode: map['batch_code']?.toString(),
            expirationDate: map['expiration_date'] != null &&
                    map['expiration_date'].toString() != 'null' &&
                    map['expiration_date'].toString().trim().isNotEmpty
                ? DateTime.tryParse(map['expiration_date'].toString().split('T').first)
                : null,
          ),
        );
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInitSupplierMeta) {
      _didInitSupplierMeta = true;
      try {
        final suppliers = context.read<SupplierProvider>().suppliers;
        for (final s in suppliers) {
          if (s.id == widget.supplierId) {
            _supplierTaxCategory = s.taxCategory;
            _supplierCuit = s.cuit;
            if (!_isEditing && s.taxCategory != null && s.taxCategory!.isNotEmpty) {
              if (s.taxCategory == 'Monotributista' || s.taxCategory == 'Exento') {
                _voucherLetter = 'C';
              } else if (s.taxCategory == 'Responsable Inscripto') {
                _voucherLetter = 'A';
              }
            }
            break;
          }
        }
      } catch (_) {}
    }
    if (!_didLoadAssistant) {
      _didLoadAssistant = true;
      unawaited(_loadPurchaseAssistant());
    }
  }

  Future<void> _loadRecentSearches() async {
    final loaded = await SupplierSearchHistoryStore.load(widget.supplierId);
    if (mounted) {
      setState(() => _recentSearches = loaded);
    }
  }

  Future<void> _recordRecentSearch(String rawTerm) async {
    final clean = rawTerm.trim();
    if (clean.length < 2) return;
    final updated = await SupplierSearchHistoryStore.record(
      widget.supplierId,
      clean,
    );
    if (mounted) {
      setState(() => _recentSearches = updated);
    }
  }

  Future<void> _removeRecentSearch(String term) async {
    final updated = await SupplierSearchHistoryStore.remove(
      widget.supplierId,
      term,
    );
    if (mounted) {
      setState(() => _recentSearches = updated);
    }
  }

  Future<void> _clearRecentSearches() async {
    await SupplierSearchHistoryStore.clear(widget.supplierId);
    if (mounted) {
      setState(() => _recentSearches = const []);
    }
  }

  SupplierPurchaseAssistantData _buildLocalAssistantFallback() {
    final supplierProducts = <Product>[];
    try {
      final catalogProv = context.read<CatalogProvider?>();
      if (catalogProv != null) {
        for (final p in catalogProv.products) {
          if (p.active && !p.isService && p.supplier?.id == widget.supplierId) {
            supplierProducts.add(p);
          }
        }
      }
    } catch (_) {}

    final lowStock = supplierProducts
        .where((p) =>
            p.stock <= 0 ||
            (p.minStock != null && p.minStock! > 0 && p.stock <= p.minStock!))
        .map((p) => SupplierSuggestedItem(product: p))
        .toList();
    final catalog = supplierProducts
        .map((p) => SupplierSuggestedItem(product: p))
        .toList();
    return SupplierPurchaseAssistantData(
      lowStock: lowStock,
      catalog: catalog,
    );
  }

  Future<void> _loadPurchaseAssistant() async {
    if (_isEditing) return;
    if (mounted) {
      setState(() => _isLoadingAssistant = true);
    }

    SupplierPurchaseAssistantData? loaded;
    try {
      final apiClient = context.read<ApiClient>();
      final supplierProv = context.read<SupplierProvider>();
      final response = await apiClient.get(
        Uri.parse(
          '${supplierProv.baseUrl}/suppliers/${widget.supplierId}/purchase-assistant',
        ),
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is Map<String, dynamic>) {
          loaded = SupplierPurchaseAssistantData.fromJson(decoded);
        }
      }
    } catch (_) {}

    loaded ??= _buildLocalAssistantFallback();

    if (!mounted) return;
    setState(() {
      _assistantData = loaded!;
      _isLoadingAssistant = false;
    });
  }

  void _addAllLowStockItems() {
    final existingIds = _items.map((i) => i.product.id).toSet();
    final toAdd = _assistantData.lowStock
        .where((s) => !existingIds.contains(s.product.id))
        .toList();
    if (toAdd.isEmpty) {
      SnackBarService.info(
        context,
        'Todos los artículos con stock bajo ya están en la lista.',
      );
      return;
    }
    for (final s in toAdd) {
      _addProduct(s.product, suggestedUnitCost: s.lastUnitCost);
    }
    setState(() => _showAssistantPanel = false);
    SnackBarService.success(
      context,
      'Se agregaron ${toAdd.length} artículos con stock bajo.',
    );
  }

  Future<void> _cloneLastInvoice() async {
    final last = _assistantData.lastInvoice;
    if (last == null || last.items.isEmpty) return;

    String action = 'append';
    if (_items.isNotEmpty) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Traer comprobante ${last.invoiceNumber}'),
          content: const Text(
            'Ya tenés ítems cargados en este comprobante. ¿Querés sumar los de la última compra o reemplazar la lista actual?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'append'),
              child: const Text('Sumar a los actuales'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'replace'),
              child: const Text('Reemplazar lista'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      action = choice;
    }

    if (action == 'replace') {
      for (final old in _items) {
        old.dispose();
      }
      setState(() => _items.clear());
    }

    for (final it in last.items.reversed) {
      final hasPkg =
          it.product.conversionFactor != null && it.product.conversionFactor! > 1;
      final usePkg = hasPkg &&
          it.lastQuantity != null &&
          it.lastQuantity! >= it.product.conversionFactor!;
      _addProduct(
        it.product,
        suggestedUnitCost: it.lastUnitCost,
        initialUnitQuantity: it.lastQuantity,
        autoEnterPackage: usePkg,
      );
    }
    if (mounted) {
      setState(() => _showAssistantPanel = false);
      SnackBarService.success(
        context,
        'Se cargaron ${last.items.length} ítems de ${last.invoiceNumber}.',
      );
    }
  }

  Future<void> _openQuickGridForSupplier() async {
    CatalogProvider? catalogProv;
    try {
      catalogProv = context.read<CatalogProvider?>();
    } catch (_) {}
    if (catalogProv == null) return;

    await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SupplierQuickGridDialog(
        provider: catalogProv!,
        initialSupplierId: widget.supplierId,
        initialSupplierName: widget.supplierName,
        authorizedAdminPin: widget.authorizedAdminPin,
        onProductsCreated: (createdList) {
          for (final p in createdList) {
            _addProduct(p);
          }
          unawaited(_loadPurchaseAssistant());
        },
      ),
    );
  }

  Future<void> _openNewProductForSupplier({String initialQuery = ''}) async {
    CatalogProvider? catalogProv;
    try {
      catalogProv = context.read<CatalogProvider?>();
    } catch (_) {}
    if (catalogProv == null) return;

    final rawQuery = initialQuery.trim();
    final looksLikeBarcode = RegExp(r'^\d{6,}$').hasMatch(rawQuery);
    final looksLikeSupplierSku = !looksLikeBarcode &&
        rawQuery.isNotEmpty &&
        RegExp(r'^(?=.*\d)[A-Za-z0-9\-_./]{2,24}$').hasMatch(rawQuery);

    final createdProduct = await showDialog<Product>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProductFormDialog(
        provider: catalogProv!,
        initialSupplierId: widget.supplierId,
        initialSupplierName: widget.supplierName,
        initialName: (looksLikeBarcode || looksLikeSupplierSku)
            ? null
            : (rawQuery.isNotEmpty ? rawQuery : null),
        initialBarcode: looksLikeBarcode ? rawQuery : null,
        initialSupplierSku: looksLikeSupplierSku ? rawQuery : null,
        lockInitialStockToZero: true,
      ),
    );
    if (createdProduct != null && mounted) {
      _addProduct(createdProduct);
      unawaited(_loadPurchaseAssistant());
    }
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    _invoiceNumberController.dispose();
    _descriptionController.dispose();
    _editReasonController.dispose();
    _freightCtrl.dispose();
    _taxCtrl.dispose();
    _discountCtrl.dispose();
    _pointOfSaleCtrl.dispose();
    _voucherNumberCtrl.dispose();
    _net21Ctrl.dispose();
    _iva21Ctrl.dispose();
    _net105Ctrl.dispose();
    _iva105Ctrl.dispose();
    _net27Ctrl.dispose();
    _iva27Ctrl.dispose();
    _ivaPerceptionCtrl.dispose();
    _iibbPerceptionCtrl.dispose();
    _nonTaxedCtrl.dispose();
    _exemptCtrl.dispose();
    _internalTaxesCtrl.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<List<Product>> _searchCatalogForInvoice(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];
    final qLower = clean.toLowerCase();

    final posResults = await context.read<PosProvider>().search(clean);
    final byId = <int, Product>{for (final p in posResults) p.id: p};

    try {
      final catalogProv = context.read<CatalogProvider?>();
      if (catalogProv != null) {
        final remoteAll = await catalogProv.searchProductsRemote(
          clean,
          perPage: 25,
          activeOnly: false,
        );
        for (final p in remoteAll) {
          byId.putIfAbsent(p.id, () => p);
        }
      }
    } catch (_) {}

    bool isExactCode(Product p) {
      return (p.barcode?.trim().toLowerCase() == qLower) ||
          (p.internalCode.trim().toLowerCase() == qLower) ||
          (p.supplierSku?.trim().toLowerCase() == qLower);
    }

    final merged = byId.values.toList();
    merged.sort((a, b) {
      final aExact = isExactCode(a) ? 0 : 1;
      final bExact = isExactCode(b) ? 0 : 1;
      if (aExact != bExact) return aExact.compareTo(bExact);

      final aSup = a.supplier?.id == widget.supplierId ? 0 : 1;
      final bSup = b.supplier?.id == widget.supplierId ? 0 : 1;
      if (aSup != bSup) return aSup.compareTo(bSup);

      final aAct = a.active ? 0 : 1;
      final bAct = b.active ? 0 : 1;
      if (aAct != bAct) return aAct.compareTo(bAct);

      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return merged;
  }

  Future<void> _onSearchSubmittedOrScanned(String rawQuery) async {
    final q = rawQuery.trim();
    if (q.isEmpty || !mounted) return;
    _debounce?.cancel();
    _searchController.text = q;
    _searchController.selection = TextSelection.collapsed(offset: q.length);
    unawaited(_recordRecentSearch(q));
    setState(() => _isSearching = true);
    try {
      final results = await _searchCatalogForInvoice(q);
      if (!mounted) return;
      final exact = RemoteScannerService.findExactProductMatch(
        results,
        q,
        activeOnly: false,
      );
      final Product? match =
          exact ?? (results.length == 1 ? results.first : null);
      if (match != null) {
        setState(() => _isSearching = false);
        _addProduct(match);
        return;
      }
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
      if (results.isEmpty) {
        SnackBarService.info(
          context,
          'No se encontraron productos para "$q".',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _isSearching = true);
      try {
        final results = await _searchCatalogForInvoice(query);
        if (mounted) {
          setState(() {
            _searchResults = results;
            _isSearching = false;
          });
          // Auto-agregar si es un código de barras exacto (Modo Escáner Continuo)
          if (results.length == 1 &&
              results.first.barcode != null &&
              results.first.barcode!.trim() == query.trim()) {
            _addProduct(results.first, recordSearch: true);
          }
        }
      } catch (e) {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  bool get _canUseBatches {
    try {
      final s = context.read<SettingsProvider?>();
      if (s != null) {
        return s.features.batchExpiration || s.features.production;
      }
    } catch (_) {}
    return true;
  }

  bool _canUseBatchesForProduct(Product product) {
    try {
      final s = context.read<SettingsProvider?>();
      if (s == null) return true;
      final baseProfile = s.safeVerticalProfile;
      Rubro? itemRubro = product.category?.rubro;
      final rId = product.category?.rubroId ?? product.category?.rubro?.id;
      if (rId != null) {
        try {
          final catProv = context.read<CatalogProvider?>();
          if (catProv != null) {
            itemRubro = catProv.safeRubros
                    .where((r) => r.id == rId)
                    .firstOrNull ??
                itemRubro;
          }
        } catch (_) {}
      }
      final itemProfile = baseProfile.resolveItemProfile(
        itemRubro,
        hasMultiRubro: s.features.multiRubro,
      );
      final storeHasNativeBatch =
          BusinessVerticalProfile.isNativeBatchVertical(
        baseProfile.primaryType,
        baseProfile.secondaryTypes,
      );
      return itemProfile.canUseBatchExpiration(
        featureBatchExpiration: s.features.batchExpiration,
        featureProduction: s.features.production,
        storeHasNativeBatchVertical: storeHasNativeBatch,
      );
    } catch (_) {}
    return _canUseBatches;
  }

  void _addProduct(
    Product product, {
    double? suggestedUnitCost,
    double? initialUnitQuantity,
    bool autoEnterPackage = true,
    bool recordSearch = false,
  }) {
    if (recordSearch && _searchController.text.trim().length >= 2) {
      unawaited(_recordRecentSearch(_searchController.text));
    }
    final canUseBatches = _canUseBatchesForProduct(product);
    final existingIndex = _items.indexWhere((i) => i.product.id == product.id);
    if (existingIndex >= 0) {
      setState(() {
        final item = _items[existingIndex];
        if (item.enterByPackage && item.hasPackageConversion) {
          item.quantity += item.conversionFactor;
          final pkgQty = item.quantity / item.conversionFactor;
          item.qtyCtrl.text = (pkgQty - pkgQty.roundToDouble()).abs() < 0.0005
              ? pkgQty.round().toString()
              : pkgQty.toStringAsFixed(2);
        } else {
          item.quantity += 1;
          item.qtyCtrl.text =
              item.product.isSoldByWeight || item.product.unitType == 'kg'
                  ? item.quantity.toStringAsFixed(3)
                  : item.quantity.toInt().toString();
        }
        _autoRecalculateFiscalIfNeeded();
      });
    } else {
      final effectiveCost =
          product.costPrice > 0 ? product.costPrice : (suggestedUnitCost ?? 0.0);
      final qtyToUse =
          (initialUnitQuantity != null && initialUnitQuantity > 0)
              ? initialUnitQuantity
              : 1.0;
      final defaultLinkSupplier = (!_isEditing &&
              _type != 'credit_note' &&
              product.supplier == null)
          ? true
          : null;
      final newItem = _InvoiceItemModel(
        product: product,
        quantity: qtyToUse,
        newCost: effectiveCost,
        manualPrice: product.sellingPrice,
        autoDefaultExpiry: canUseBatches,
        linkSupplier: defaultLinkSupplier,
      );
      if (autoEnterPackage && newItem.hasPackageConversion) {
        newItem.switchInputMode(true);
      }
      setState(() {
        _items.insert(0, newItem);
        _autoRecalculateFiscalIfNeeded();
      });
    }
    _searchController.clear();
    _searchResults = [];
    _searchFocus.requestFocus();
  }

  void _addAnotherLotRow(int index, _InvoiceItemModel sourceItem) {
    setState(() {
      sourceItem.showLotFields = true;
      final newItem = _InvoiceItemModel(
        product: sourceItem.product,
        quantity: 1,
        newCost: sourceItem.newCost,
        manualPrice: sourceItem.manualPrice,
        updatePrice: sourceItem.updatePrice,
        vatRate: sourceItem.vatRate,
        batchId: null,
        expirationDate: null,
        autoDefaultExpiry: false,
      )..showLotFields = true;
      _items.insert(index + 1, newItem);
      _autoRecalculateFiscalIfNeeded();
    });
  }

  void _handleCostChange(_InvoiceItemModel item, String val) {
    final parsedInput = ArsThousandsInputFormatter.parse(val);
    final parsed = (item.enterByPackage && item.hasPackageConversion)
        ? double.parse((parsedInput / item.conversionFactor).toStringAsFixed(4))
        : parsedInput;

    setState(() {
      item.newCost = parsed;
      item.priceAnchor = parsed > 0 ? 'cost' : 'selling';
      final margin = double.tryParse(item.marginCtrl.text.replaceAll(',', '.').trim());
      if (parsed > 0 && margin != null && margin > 0) {
        final calcPvp = double.parse((parsed * (1 + (margin / 100))).toStringAsFixed(2));
        item.manualPrice = calcPvp;
        item.pvpCtrl.text = calcPvp.toArsInput();
        item.updatePrice = true;
      } else if (item.newCost > item.product.costPrice &&
          item.product.costPrice > 0 &&
          item.product.sellingPrice > item.product.costPrice) {
        final histMargin =
            (item.product.sellingPrice - item.product.costPrice) / item.product.costPrice;
        item.suggestedPrice = double.parse((item.newCost * (1 + histMargin)).toStringAsFixed(2));
        item.manualPrice = item.suggestedPrice!;
        item.pvpCtrl.text = item.manualPrice.toArsInput();
        item.marginCtrl.text = (histMargin * 100).toCleanMargin();
        item.updatePrice = true;
      } else if (parsed > 0 && item.manualPrice > 0) {
        final effMargin = ((item.manualPrice - parsed) / parsed) * 100;
        item.marginCtrl.text = effMargin.toCleanMargin();
      }
      _autoRecalculateFiscalIfNeeded();
    });
  }

  void _syncCostFieldFromUnitCost(_InvoiceItemModel item) {
    final displayCost = (item.enterByPackage && item.hasPackageConversion)
        ? double.parse((item.newCost * item.conversionFactor).toStringAsFixed(2))
        : item.newCost;
    item.costCtrl.text = displayCost.toArsInput();
  }

  void _handleMarginChange(_InvoiceItemModel item, String val) {
    final clean = val.replaceAll(',', '.').trim();
    final margin = double.tryParse(clean);
    if (margin == null) return;

    setState(() {
      final costEmpty = item.costCtrl.text.trim().isEmpty || item.newCost <= 0;
      if ((item.priceAnchor == 'selling' || costEmpty) &&
          item.manualPrice > 0 &&
          margin > -100) {
        final calcCost = item.manualPrice / (1 + (margin / 100));
        item.newCost = double.parse(calcCost.toStringAsFixed(2));
        _syncCostFieldFromUnitCost(item);
      } else if (item.newCost > 0) {
        final calcPvp = item.newCost * (1 + (margin / 100));
        item.manualPrice = double.parse(calcPvp.toStringAsFixed(2));
        item.pvpCtrl.text = item.manualPrice.toArsInput();
        item.updatePrice = true;
      }
      _autoRecalculateFiscalIfNeeded();
    });
  }

  void _handlePvpChange(_InvoiceItemModel item, String val) {
    final pvp = ArsThousandsInputFormatter.tryParse(val);
    if (pvp == null || pvp <= 0) return;

    setState(() {
      item.manualPrice = pvp;
      item.updatePrice = true;
      final margin = double.tryParse(item.marginCtrl.text.replaceAll(',', '.').trim());
      final costEmpty = item.costCtrl.text.trim().isEmpty || item.newCost <= 0;
      if (costEmpty && margin != null && margin > 0) {
        item.priceAnchor = 'selling';
        final calcCost = pvp / (1 + (margin / 100));
        item.newCost = double.parse(calcCost.toStringAsFixed(2));
        _syncCostFieldFromUnitCost(item);
      } else if (item.newCost > 0) {
        // Regla Costo como Ancla: si el producto ya tiene costo, editar el PVP
        // solo recalcula la utilidad (%) y mantiene el costo firme como ancla.
        item.priceAnchor = 'cost';
        final effMargin = ((pvp - item.newCost) / item.newCost) * 100;
        item.marginCtrl.text = effMargin.toCleanMargin();
      } else {
        item.priceAnchor = 'selling';
      }
      _autoRecalculateFiscalIfNeeded();
    });
  }

  Future<void> _pickAndUploadFile() async {
    final result = await fp.FilePicker.platform.pickFiles(
      type: fp.FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (!mounted) return;
    if (result != null && result.files.single.path != null) {
      final filePath = result.files.single.path!;
      await AdminPinDialog.protectAction(
        context,
        action: 'Adjuntar Comprobante de Compra',
        permissionKey: _isEditing
            ? AppPermissions.manageSupplierInvoices
            : AppPermissions.createSupplierInvoice,
        onAuthorized: () async {
          if (!mounted) return;
          setState(() => _isUploading = true);
          try {
            final supplierProv = context.read<SupplierProvider>();
            final apiClient = context.read<ApiClient>();

            final request = http.MultipartRequest(
              'POST',
              Uri.parse('${supplierProv.baseUrl}/supplier-invoices/upload'),
            );
            request.files.add(await http.MultipartFile.fromPath('file', filePath));

            final streamedResponse = await apiClient.send(request);
            final response = await http.Response.fromStream(streamedResponse);

            if (response.statusCode == 200) {
              final data = json.decode(response.body);
              if (!mounted) return;
              setState(() {
                _attachmentUrl = (data['path'] ?? data['file_url'])?.toString();
                _localAttachmentPath = filePath;
                _isUploading = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Comprobante subido.')),
              );
            } else {
              throw Exception('Error al subir comprobante');
            }
          } catch (e) {
            if (!mounted) return;
            setState(() => _isUploading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Fallo la subida.')),
            );
          }
        },
      );
    }
  }

  Future<void> _showAttachmentPreview() async {
    final localPath = _localAttachmentPath;
    final remotePath = _attachmentUrl?.trim();
    String baseUrl = '';
    try {
      baseUrl = context.read<SupplierProvider>().baseUrl;
    } catch (_) {}
    final resolvedUrl = resolveImageUrl(remotePath, baseUrl: baseUrl);
    final targetStr = (localPath != null && localPath.isNotEmpty)
        ? localPath
        : (resolvedUrl ?? remotePath ?? '');
    if (targetStr.isEmpty) return;

    final isPdf = targetStr.toLowerCase().contains('.pdf');
    if (isPdf) {
      final uri = (localPath != null &&
              localPath.isNotEmpty &&
              File(localPath).existsSync())
          ? Uri.file(localPath)
          : Uri.tryParse(resolvedUrl ?? targetStr);
      if (uri != null) {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok && mounted) {
          SnackBarService.warning(
            context,
            'No se pudo abrir el PDF en el visor del sistema.',
          );
        }
      }
      return;
    }

    if (!mounted) return;
    final hasLocalFile =
        localPath != null && localPath.isNotEmpty && File(localPath).existsSync();
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: Colors.black54,
              child: Row(
                children: [
                  const Icon(
                    Icons.receipt_long,
                    color: Colors.white70,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Comprobante Adjunto',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 920, maxHeight: 680),
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5.0,
                  child: hasLocalFile
                      ? Image.file(
                          File(localPath),
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              'No se pudo cargar la imagen local.',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        )
                      : Image.network(
                          resolvedUrl ?? targetStr,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              'No se pudo descargar la imagen del comprobante.',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double get _fiscalSum {
    final n21 = ArsThousandsInputFormatter.parse(_net21Ctrl.text);
    final i21 = ArsThousandsInputFormatter.parse(_iva21Ctrl.text);
    final n105 = ArsThousandsInputFormatter.parse(_net105Ctrl.text);
    final i105 = ArsThousandsInputFormatter.parse(_iva105Ctrl.text);
    final n27 = ArsThousandsInputFormatter.parse(_net27Ctrl.text);
    final i27 = ArsThousandsInputFormatter.parse(_iva27Ctrl.text);
    final ivaP = ArsThousandsInputFormatter.parse(_ivaPerceptionCtrl.text);
    final iibbP = ArsThousandsInputFormatter.parse(_iibbPerceptionCtrl.text);
    final nonT = ArsThousandsInputFormatter.parse(_nonTaxedCtrl.text);
    final ex = ArsThousandsInputFormatter.parse(_exemptCtrl.text);
    final impInt = ArsThousandsInputFormatter.parse(_internalTaxesCtrl.text);
    return n21 + i21 + n105 + i105 + n27 + i27 + ivaP + iibbP + nonT + ex + impInt;
  }

  void _syncInvoiceNumberFromPvAndNro() {
    final pv = _pointOfSaleCtrl.text.trim();
    final nro = _voucherNumberCtrl.text.trim();
    final currentText = _invoiceNumberController.text.trim();
    if (pv.isNotEmpty && nro.isNotEmpty && (currentText.isEmpty || currentText == _lastAutoInvoiceNumber)) {
      final pvInt = int.tryParse(pv);
      final nroInt = int.tryParse(nro);
      if (pvInt != null && nroInt != null) {
        final formatted =
            '${pvInt.toString().padLeft(4, '0')}-${nroInt.toString().padLeft(8, '0')}';
        _invoiceNumberController.text = formatted;
        _lastAutoInvoiceNumber = formatted;
      }
    }
    setState(() {});
  }

  void _onPerceptionOrInternalTaxChanged() {
    if (_items.isNotEmpty && (_voucherLetter == 'A' || _voucherLetter == 'M')) {
      final ivaP = ArsThousandsInputFormatter.parse(_ivaPerceptionCtrl.text);
      final iibbP = ArsThousandsInputFormatter.parse(_iibbPerceptionCtrl.text);
      final impInt = ArsThousandsInputFormatter.parse(_internalTaxesCtrl.text);
      final perceptionsSum = ivaP + iibbP + impInt;
      if (_costsIncludeVat) {
        _taxAmount = double.parse(perceptionsSum.toStringAsFixed(2));
        _taxCtrl.text = _taxAmount > 0 ? _taxAmount.toArsInput() : '';
      } else {
        final i21 = ArsThousandsInputFormatter.parse(_iva21Ctrl.text);
        final i105 = ArsThousandsInputFormatter.parse(_iva105Ctrl.text);
        final i27 = ArsThousandsInputFormatter.parse(_iva27Ctrl.text);
        _taxAmount = double.parse((i21 + i105 + i27 + perceptionsSum).toStringAsFixed(2));
        _taxCtrl.text = _taxAmount > 0 ? _taxAmount.toArsInput() : '';
      }
    }
    setState(() {});
  }

  void _applyIibbRate(String mode, {bool triggerSetState = true}) {
    if (mode == 'clear') {
      _selectedIibbMode = null;
      _iibbPerceptionCtrl.clear();
      if (triggerSetState) {
        _onPerceptionOrInternalTaxChanged();
      }
      return;
    }

    _selectedIibbMode = mode;

    final n21 = ArsThousandsInputFormatter.parse(_net21Ctrl.text);
    final i21 = ArsThousandsInputFormatter.parse(_iva21Ctrl.text);
    final n105 = ArsThousandsInputFormatter.parse(_net105Ctrl.text);
    final i105 = ArsThousandsInputFormatter.parse(_iva105Ctrl.text);
    final n27 = ArsThousandsInputFormatter.parse(_net27Ctrl.text);
    final i27 = ArsThousandsInputFormatter.parse(_iva27Ctrl.text);
    final nonT = ArsThousandsInputFormatter.parse(_nonTaxedCtrl.text);
    final ex = ArsThousandsInputFormatter.parse(_exemptCtrl.text);

    final netSum = n21 + n105 + n27;
    final grossSum = netSum + i21 + i105 + i27;
    final itemsSub = _items.fold(0.0, (s, i) => s + i.subtotal);

    double base = 0.0;
    double rate = 0.0;

    switch (mode) {
      case '1_net':
        rate = 0.01;
        base = netSum > 0 ? netSum : (nonT + ex > 0 ? nonT + ex : itemsSub);
        break;
      case '1.5_net':
        rate = 0.015;
        base = netSum > 0 ? netSum : (nonT + ex > 0 ? nonT + ex : itemsSub);
        break;
      case '2_net':
        rate = 0.02;
        base = netSum > 0 ? netSum : (nonT + ex > 0 ? nonT + ex : itemsSub);
        break;
      case '2_gross':
        rate = 0.02;
        base = grossSum > 0 ? grossSum : itemsSub;
        break;
      case '2.5_net':
        rate = 0.025;
        base = netSum > 0 ? netSum : (nonT + ex > 0 ? nonT + ex : itemsSub);
        break;
      case '3_net':
        rate = 0.03;
        base = netSum > 0 ? netSum : (nonT + ex > 0 ? nonT + ex : itemsSub);
        break;
      case '3_gross':
        rate = 0.03;
        base = grossSum > 0 ? grossSum : itemsSub;
        break;
      case '4_net':
        rate = 0.04;
        base = netSum > 0 ? netSum : (nonT + ex > 0 ? nonT + ex : itemsSub);
        break;
    }

    if (base > 0 && rate > 0) {
      final calc = (base * rate * 100).round() / 100.0;
      _iibbPerceptionCtrl.text = calc.toArsInput();
      if (triggerSetState) {
        _onPerceptionOrInternalTaxChanged();
      }
    } else if (triggerSetState) {
      setState(() {});
    }
  }

  String get _iibbBadgeLabel {
    final iibbVal = ArsThousandsInputFormatter.parse(_iibbPerceptionCtrl.text);
    switch (_selectedIibbMode) {
      case '1_net':
        return '1% ▾';
      case '1.5_net':
        return '1.5% ▾';
      case '2_net':
        return '2% ▾';
      case '2_gross':
        return '2% c/IVA ▾';
      case '2.5_net':
        return '2.5% ▾';
      case '3_net':
        return '3% ▾';
      case '3_gross':
        return '3% c/IVA ▾';
      case '4_net':
        return '4% ▾';
    }
    if (iibbVal > 0) {
      final netSum = ArsThousandsInputFormatter.parse(_net21Ctrl.text) +
          ArsThousandsInputFormatter.parse(_net105Ctrl.text) +
          ArsThousandsInputFormatter.parse(_net27Ctrl.text);
      if (netSum > 0) {
        final effPct = (iibbVal / netSum) * 100;
        final rounded = (effPct * 100).round() / 100.0;
        final str = rounded % 1 == 0
            ? rounded.toInt().toString()
            : rounded.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '').replaceAll('.', ',');
        return '$str% ▾';
      }
    }
    return '% ▾';
  }

  void _toggleCostsIncludeVat(bool includeVat) {
    if (_costsIncludeVat == includeVat) return;
    setState(() {
      _costsIncludeVat = includeVat;
      _autoSyncFiscal21 = true;
      if (_costsIncludeVat) {
        final otherPerceptions = ArsThousandsInputFormatter.parse(_ivaPerceptionCtrl.text) +
            ArsThousandsInputFormatter.parse(_iibbPerceptionCtrl.text) +
            ArsThousandsInputFormatter.parse(_internalTaxesCtrl.text);
        _taxAmount = double.parse(otherPerceptions.toStringAsFixed(2));
        _taxCtrl.text = _taxAmount > 0 ? _taxAmount.toArsInput() : '';
      }
      _autoRecalculateFiscalIfNeeded();
    });
  }

  void _onNet21Changed(String v) {
    if (_voucherLetter == 'B' || _voucherLetter == 'C') return;
    _autoSyncFiscal21 = false;
    final net = ArsThousandsInputFormatter.parse(v);
    if (net > 0) {
      final iva = (net * 0.21 * 100).round() / 100.0;
      _iva21Ctrl.text = iva.toArsInput();
    } else {
      _iva21Ctrl.clear();
    }
    if (!_costsIncludeVat) {
      _onPerceptionOrInternalTaxChanged();
    } else {
      setState(() {});
    }
  }

  void _onNet105Changed(String v) {
    if (_voucherLetter == 'B' || _voucherLetter == 'C') return;
    _autoSyncFiscal21 = false;
    final net = ArsThousandsInputFormatter.parse(v);
    if (net > 0) {
      final iva = (net * 0.105 * 100).round() / 100.0;
      _iva105Ctrl.text = iva.toArsInput();
    } else {
      _iva105Ctrl.clear();
    }
    if (!_costsIncludeVat) {
      _onPerceptionOrInternalTaxChanged();
    } else {
      setState(() {});
    }
  }

  void _onNet27Changed(String v) {
    if (_voucherLetter == 'B' || _voucherLetter == 'C') return;
    _autoSyncFiscal21 = false;
    final net = ArsThousandsInputFormatter.parse(v);
    if (net > 0) {
      final iva = (net * 0.27 * 100).round() / 100.0;
      _iva27Ctrl.text = iva.toArsInput();
    } else {
      _iva27Ctrl.clear();
    }
    if (!_costsIncludeVat) {
      _onPerceptionOrInternalTaxChanged();
    } else {
      setState(() {});
    }
  }

  void _autoRecalculateFiscalIfNeeded() {
    if (_items.isEmpty) {
      if (_autoSyncFiscal21) {
        _net21Ctrl.clear();
        _iva21Ctrl.clear();
        _net105Ctrl.clear();
        _iva105Ctrl.clear();
        _net27Ctrl.clear();
        _iva27Ctrl.clear();
        _nonTaxedCtrl.clear();
      }
      return;
    }

    if (_voucherLetter == 'B' || _voucherLetter == 'C') {
      final total = _totalAmount;
      if (total > 0) {
        _nonTaxedCtrl.text = total.toArsInput();
      }
      _net21Ctrl.clear();
      _iva21Ctrl.clear();
      _net105Ctrl.clear();
      _iva105Ctrl.clear();
      _net27Ctrl.clear();
      _iva27Ctrl.clear();
    } else if ((_voucherLetter == 'A' || _voucherLetter == 'M') && _autoSyncFiscal21) {
      final otherPerceptions = ArsThousandsInputFormatter.parse(_ivaPerceptionCtrl.text) +
          ArsThousandsInputFormatter.parse(_iibbPerceptionCtrl.text) +
          ArsThousandsInputFormatter.parse(_internalTaxesCtrl.text);

      double raw21 = 0.0;
      double raw105 = 0.0;
      double raw27 = 0.0;
      double rawEx = 0.0;
      for (final item in _items) {
        if (item.vatRate == 10.5) {
          raw105 += item.subtotal;
        } else if (item.vatRate == 27.0) {
          raw27 += item.subtotal;
        } else if (item.vatRate == 0.0) {
          rawEx += item.subtotal;
        } else {
          raw21 += item.subtotal;
        }
      }

      if (!_costsIncludeVat) {
        // Modo Mayorista (Costos Netos + IVA): cada subtotal de artículo es Neto Gravado
        final netDelta = _freightAmount - _discountAmount;
        if (netDelta.abs() > 0.001) {
          if (raw21 > 0) {
            raw21 = (raw21 + netDelta).clamp(0.0, double.infinity);
          } else if (raw105 > 0) {
            raw105 = (raw105 + netDelta).clamp(0.0, double.infinity);
          } else if (raw27 > 0) {
            raw27 = (raw27 + netDelta).clamp(0.0, double.infinity);
          } else if (rawEx > 0) {
            rawEx = (rawEx + netDelta).clamp(0.0, double.infinity);
          }
        }

        double i21 = 0.0;
        double i105 = 0.0;
        double i27 = 0.0;

        if (raw21 > 0) {
          final n21 = double.parse(raw21.toStringAsFixed(2));
          i21 = (n21 * 0.21 * 100).round() / 100.0;
          _net21Ctrl.text = n21.toArsInput();
          _iva21Ctrl.text = i21.toArsInput();
        } else {
          _net21Ctrl.clear();
          _iva21Ctrl.clear();
        }

        if (raw105 > 0) {
          final n105 = double.parse(raw105.toStringAsFixed(2));
          i105 = (n105 * 0.105 * 100).round() / 100.0;
          _net105Ctrl.text = n105.toArsInput();
          _iva105Ctrl.text = i105.toArsInput();
        } else {
          _net105Ctrl.clear();
          _iva105Ctrl.clear();
        }

        if (raw27 > 0) {
          final n27 = double.parse(raw27.toStringAsFixed(2));
          i27 = (n27 * 0.27 * 100).round() / 100.0;
          _net27Ctrl.text = n27.toArsInput();
          _iva27Ctrl.text = i27.toArsInput();
        } else {
          _net27Ctrl.clear();
          _iva27Ctrl.clear();
        }

        if (rawEx > 0) {
          _exemptCtrl.text = double.parse(rawEx.toStringAsFixed(2)).toArsInput();
        } else {
          _exemptCtrl.clear();
        }
        _nonTaxedCtrl.clear();

        if (_selectedIibbMode != null) {
          _applyIibbRate(_selectedIibbMode!, triggerSetState: false);
        }
        final updatedPerceptions = ArsThousandsInputFormatter.parse(_ivaPerceptionCtrl.text) +
            ArsThousandsInputFormatter.parse(_iibbPerceptionCtrl.text) +
            ArsThousandsInputFormatter.parse(_internalTaxesCtrl.text);
        final totalTaxes = double.parse((i21 + i105 + i27 + updatedPerceptions).toStringAsFixed(2));
        _taxAmount = totalTaxes;
        _taxCtrl.text = totalTaxes > 0 ? totalTaxes.toArsInput() : '';
        return;
      }

      // Modo Estándar (Costos con IVA Incluido)
      final total = _totalAmount;
      if (total <= 0) return;
      final distributable = (total - otherPerceptions) > 0 ? (total - otherPerceptions) : total;

      final itemsSum = raw21 + raw105 + raw27 + rawEx;
      final delta = distributable - itemsSum;
      if (delta.abs() > 0.001) {
        if (raw21 > 0) {
          raw21 = (raw21 + delta).clamp(0.0, double.infinity);
        } else if (raw105 > 0) {
          raw105 = (raw105 + delta).clamp(0.0, double.infinity);
        } else if (raw27 > 0) {
          raw27 = (raw27 + delta).clamp(0.0, double.infinity);
        } else if (rawEx > 0) {
          rawEx = (rawEx + delta).clamp(0.0, double.infinity);
        } else {
          raw21 = distributable;
        }
      }

      if (raw21 > 0) {
        final n21 = (raw21 / 1.21 * 100).round() / 100.0;
        final i21 = double.parse((raw21 - n21).toStringAsFixed(2));
        _net21Ctrl.text = n21.toArsInput();
        _iva21Ctrl.text = i21.toArsInput();
      } else {
        _net21Ctrl.clear();
        _iva21Ctrl.clear();
      }

      if (raw105 > 0) {
        final n105 = (raw105 / 1.105 * 100).round() / 100.0;
        final i105 = double.parse((raw105 - n105).toStringAsFixed(2));
        _net105Ctrl.text = n105.toArsInput();
        _iva105Ctrl.text = i105.toArsInput();
      } else {
        _net105Ctrl.clear();
        _iva105Ctrl.clear();
      }

      if (raw27 > 0) {
        final n27 = (raw27 / 1.27 * 100).round() / 100.0;
        final i27 = double.parse((raw27 - n27).toStringAsFixed(2));
        _net27Ctrl.text = n27.toArsInput();
        _iva27Ctrl.text = i27.toArsInput();
      } else {
        _net27Ctrl.clear();
        _iva27Ctrl.clear();
      }

      if (rawEx > 0) {
        _exemptCtrl.text = double.parse(rawEx.toStringAsFixed(2)).toArsInput();
      } else {
        _exemptCtrl.clear();
      }
      _nonTaxedCtrl.clear();

      if (_selectedIibbMode != null) {
        _applyIibbRate(_selectedIibbMode!, triggerSetState: false);
        final updatedPerceptions = ArsThousandsInputFormatter.parse(_ivaPerceptionCtrl.text) +
            ArsThousandsInputFormatter.parse(_iibbPerceptionCtrl.text) +
            ArsThousandsInputFormatter.parse(_internalTaxesCtrl.text);
        _taxAmount = double.parse(updatedPerceptions.toStringAsFixed(2));
        _taxCtrl.text = _taxAmount > 0 ? _taxAmount.toArsInput() : '';
      }
    }
  }

  void _distributeTotalByRate(double rate) {
    _autoSyncFiscal21 = true;
    for (final item in _items) {
      item.vatRate = rate;
    }
    _autoRecalculateFiscalIfNeeded();
    setState(() {});
  }

  void _distributeTotalInNet21() {
    _distributeTotalByRate(21.0);
  }

  void _onVoucherLetterChanged(String newLetter) {
    setState(() {
      _voucherLetter = newLetter;
      if (_voucherLetter == 'B' || _voucherLetter == 'C' || _voucherLetter == 'S/D') {
        _net21Ctrl.clear();
        _iva21Ctrl.clear();
        _net105Ctrl.clear();
        _iva105Ctrl.clear();
        _net27Ctrl.clear();
        _iva27Ctrl.clear();
        if (_voucherLetter == 'S/D') {
          _nonTaxedCtrl.clear();
        } else if (_totalAmount > 0) {
          _nonTaxedCtrl.text = _totalAmount.toArsInput();
        }
      } else if (_voucherLetter == 'A' || _voucherLetter == 'M') {
        _autoSyncFiscal21 = true;
        _autoRecalculateFiscalIfNeeded();
      }
    });
  }

  double get _totalAmount {
    if (_items.isEmpty) return 0.0;
    final sub = _items.fold(0.0, (sum, item) => sum + item.subtotal);
    return sub + _freightAmount + _taxAmount - _discountAmount;
  }

  void _syncTotalFromFiscalBreakdown() {
    if (_items.isEmpty) return;
    final fSum = _fiscalSum;
    if (fSum <= 0) return;
    final sub = _items.fold(0.0, (sum, item) => sum + item.subtotal);
    final neededTax = double.parse((fSum - sub - _freightAmount + _discountAmount).toStringAsFixed(2));
    if (neededTax >= 0) {
      setState(() {
        _taxAmount = neededTax;
        _taxCtrl.text = neededTax > 0 ? neededTax.toArsInput() : '';
      });
    } else {
      _distributeTotalInNet21();
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe agregar al menos un producto')),
      );
      return;
    }

    final isRI = context.read<SettingsProvider>().isResponsableInscripto;
    if (isRI &&
        _type != 'delivery_note' &&
        (_voucherLetter == 'A' || _voucherLetter == 'M') &&
        _affectsVatBook &&
        _totalAmount > 0) {
      final fSum = _fiscalSum;
      if (fSum == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: Text('Debe ingresar el desglose fiscal para Factura $_voucherLetter'),
          ),
        );
        return;
      }
      if ((fSum - _totalAmount).abs() > 0.05) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: Text(
              'El total del comprobante (\$${_totalAmount.toCurrency()}) no coincide con la suma de importes fiscales (\$${fSum.toCurrency()}). Diferencia: \$${(fSum - _totalAmount).abs().toCurrency()}',
            ),
          ),
        );
        return;
      }
    }

    final permissionKey = _isEditing
        ? AppPermissions.manageSupplierInvoices
        : AppPermissions.createSupplierInvoice;
    final actionText = _isEditing
        ? 'Editar Comprobante de Proveedor #${widget.initialInvoice!['id']}'
        : 'Cargar Comprobante de Compra';

    Future<void> executeSubmit() async {
      setState(() => _isLoading = true);

      try {
        final itemsData = _items.map((i) {
          final itemCanUseBatches = _canUseBatchesForProduct(i.product);
          return {
            'product_id': i.product.id,
            'quantity': i.quantity,
            'unit_cost': i.newCost,
            'subtotal': double.parse((i.quantity * i.newCost).toStringAsFixed(2)),
            'update_price': i.updatePrice,
            'new_selling_price': i.updatePrice ? i.manualPrice : null,
            if (i.linkSupplier != null) 'link_supplier': i.linkSupplier,
            if (itemCanUseBatches && i.batchId != null) 'batch_id': i.batchId,
            if (itemCanUseBatches && i.batchCodeCtrl.text.trim().isNotEmpty)
              'batch_code': i.batchCodeCtrl.text.trim(),
            if (itemCanUseBatches && i.expirationDate != null)
              'expiration_date':
                  DateFormat('yyyy-MM-dd').format(i.expirationDate!),
          };
        }).toList();

        final data = <String, dynamic>{
          'type': _type,
          'status': 'pending',
          'amount': _totalAmount,
          'tax_amount': _taxAmount,
          'freight_amount': _freightAmount,
          'discount_amount': _discountAmount,
          'issue_date': _issueDate?.toIso8601String(),
          'due_date': _dueDate?.toIso8601String().split('T')[0],
          'receipt_file_url': _attachmentUrl,
          'invoice_number': _invoiceNumberController.text.trim(),
          'description': _descriptionController.text.trim(),
          'items': itemsData,
        };

        if (_type == 'delivery_note') {
          data['affects_vat_book'] = false;
          data['voucher_letter'] = null;
        } else if (isRI) {
          if (_voucherLetter == 'S/D') {
            data['voucher_letter'] = null;
            data['affects_vat_book'] = _affectsVatBook;
          } else {
            data['voucher_letter'] = _voucherLetter;
            data['point_of_sale'] = int.tryParse(_pointOfSaleCtrl.text.trim());
            data['voucher_number'] = int.tryParse(_voucherNumberCtrl.text.trim());
            data['net_21'] = ArsThousandsInputFormatter.parse(_net21Ctrl.text);
            data['iva_21'] = ArsThousandsInputFormatter.parse(_iva21Ctrl.text);
            data['net_105'] = ArsThousandsInputFormatter.parse(_net105Ctrl.text);
            data['iva_105'] = ArsThousandsInputFormatter.parse(_iva105Ctrl.text);
            data['net_27'] = ArsThousandsInputFormatter.parse(_net27Ctrl.text);
            data['iva_27'] = ArsThousandsInputFormatter.parse(_iva27Ctrl.text);
            data['iva_perception'] = ArsThousandsInputFormatter.parse(_ivaPerceptionCtrl.text);
            data['iibb_perception'] = ArsThousandsInputFormatter.parse(_iibbPerceptionCtrl.text);
            data['non_taxed_amount'] = ArsThousandsInputFormatter.parse(_nonTaxedCtrl.text);
            data['exempt_amount'] = ArsThousandsInputFormatter.parse(_exemptCtrl.text);
            data['internal_taxes'] = ArsThousandsInputFormatter.parse(_internalTaxesCtrl.text);
            data['affects_vat_book'] = _affectsVatBook;
          }
        }

        if (_isEditing) {
          data['edit_reason'] = _editReasonController.text.trim().isNotEmpty
              ? _editReasonController.text.trim()
              : 'Edición manual de comprobante';
        }

        final provider = context.read<SupplierProvider>();
        CatalogProvider? catalogProv;
        try {
          catalogProv = context.read<CatalogProvider>();
        } catch (_) {}

        if (_isEditing) {
          final invoiceId = int.parse(widget.initialInvoice!['id'].toString());
          await provider.updateInvoice(
            invoiceId,
            data,
            adminPin: widget.authorizedAdminPin,
          );
          if (catalogProv != null) {
            unawaited(catalogProv.loadProductsWithoutSupplierFilter());
          }
          try {
            unawaited(context.read<InventoryAlertsProvider>().fetchAlerts());
          } catch (_) {}
          if (mounted) {
            Navigator.of(context).pop(true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Comprobante actualizado. Stock, costos y saldo recalculados con registro en auditoría.',
                ),
              ),
            );
          }
        } else {
          final success = await provider.createInvoice(widget.supplierId, data);

          if (success && mounted) {
            if (catalogProv != null) {
              unawaited(catalogProv.loadProductsWithoutSupplierFilter());
            }
            try {
              unawaited(context.read<InventoryAlertsProvider>().fetchAlerts());
            } catch (_) {}
            Navigator.of(context).pop(true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Factura registrada correctamente. Stock y Costos actualizados.'),
              ),
            );

            if (_payNow && _type == 'invoice') {
              final supplier =
                  provider.suppliers.firstWhere((s) => s.id == widget.supplierId);
              final newBalance = supplier.balance;
              final amountToPay = newBalance > 0
                  ? (_totalAmount < newBalance ? _totalAmount : newBalance)
                  : 0.0;
              final discount = _totalAmount - amountToPay;

              String? helperText;
              if (discount > 0 && amountToPay > 0) {
                helperText =
                    '💡 Se han descontado \$${discount.toCurrency()} que tenías a favor.';
              } else {
                helperText =
                    '💡 Este importe corresponde únicamente a la mercadería que acabas de cargar hoy. (Para saldar la deuda total, usa el botón rojo "Pagar Total" de arriba).';
              }

              if (amountToPay > 0) {
                showDialog(
                  context: context,
                  barrierDismissible: true,
                  builder: (_) => MovementFormDialog(
                    initialSupplierId: widget.supplierId,
                    initialType: 'supplier_payment',
                    initialAmount: amountToPay,
                    initialCategory: 'Pago a Proveedor',
                    helperText: helperText,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Factura cubierta con Saldo a Favor.',
                      style: TextStyle(color: Colors.white),
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            }
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }

    if (_isEditing &&
        widget.authorizedAdminPin != null &&
        widget.authorizedAdminPin!.isNotEmpty) {
      await executeSubmit();
      return;
    }

    await AdminPinDialog.protectAction(
      context,
      action: actionText,
      permissionKey: permissionKey,
      onAuthorized: executeSubmit,
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isRIHeader = false;
    try {
      isRIHeader = context.watch<SettingsProvider>().isResponsableInscripto;
    } catch (_) {}

    return RemoteScannerListener(
      debugLabel: 'SupplierInvoiceFormDialog',
      onBarcodeScanned: _onSearchSubmittedOrScanned,
      child: Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.95,
        height: MediaQuery.of(context).size.height * 0.94,
        constraints: const BoxConstraints(maxWidth: 1240, maxHeight: 880),
        padding: const EdgeInsets.all(0),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.f2): () {
              _searchFocus.requestFocus();
              _searchController.selection = TextSelection(
                baseOffset: 0,
                extentOffset: _searchController.text.length,
              );
            },
          },
          child: Column(
            children: [
            AppModalHeader(
              title: _isEditing
                  ? 'Editar Comprobante de Proveedor #${widget.initialInvoice!['id']}'
                  : 'Espejo de Ventas - Carga de Remito / Factura',
              subtitle:
                  'Proveedor: ${widget.supplierName}${(_supplierCuit != null && _supplierCuit!.isNotEmpty) ? ' ($_supplierCuit)' : ''}',
              icon: _isEditing ? Icons.edit_document : Icons.inventory_2_outlined,
              accent: _isEditing ? AppModalAccent.amber : AppModalAccent.blue,
              compact: MediaQuery.of(context).size.height < 640,
              trailing: isRIHeader &&
                      _supplierTaxCategory != null &&
                      _supplierTaxCategory!.isNotEmpty
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        _supplierTaxCategory!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : null,
              onClose: () => Navigator.pop(context),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Form(
                  key: _formKey,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 800;
                      final isRI = context.watch<SettingsProvider>().isResponsableInscripto;

                      final assistantPanel = SupplierPurchaseAssistantPanel(
                        supplierName: widget.supplierName,
                        data: _assistantData,
                        isLoading: _isLoadingAssistant,
                        addedProductIds:
                            _items.map((i) => i.product.id).toSet(),
                        onAddItem: (suggested) {
                          final hasPkg =
                              suggested.product.conversionFactor != null &&
                                  suggested.product.conversionFactor! > 1;
                          final usePkg = hasPkg &&
                              (suggested.lastQuantity == null ||
                                  suggested.lastQuantity! >=
                                      suggested.product.conversionFactor!);
                          _addProduct(
                            suggested.product,
                            suggestedUnitCost: suggested.lastUnitCost,
                            autoEnterPackage: usePkg,
                          );
                        },
                        onAddAllLowStock: _addAllLowStockItems,
                        onCloneLastInvoice: () =>
                            unawaited(_cloneLastInvoice()),
                        onOpenQuickGrid: () =>
                            unawaited(_openQuickGridForSupplier()),
                        onOpenNewProduct: () =>
                            unawaited(_openNewProductForSupplier()),
                      );

                      final itemsTable = Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _items.isEmpty
                            ? (_isEditing
                                ? Center(
                                    child: Text(
                                      'Busque y seleccione productos para agregarlos al comprobante.',
                                      style: TextStyle(
                                          color: Colors.grey.shade600),
                                    ),
                                  )
                                : assistantPanel)
                            : ListView.separated(
                                itemCount: _items.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = _items[index];
                                  return _buildItemRow(
                                    item,
                                    index,
                                    showVatSelector: isRI &&
                                        _type != 'delivery_note' &&
                                        (_voucherLetter == 'A' || _voucherLetter == 'M'),
                                  );
                                },
                              ),
                      );

                      final leftPanel = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Buscador
                          Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            clipBehavior: Clip.antiAlias,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Column(
                                children: [
                                  TextField(
                                    key: const ValueKey('supplier_invoice_search_field'),
                                    controller: _searchController,
                                    focusNode: _searchFocus,
                                    onSubmitted: _onSearchSubmittedOrScanned,
                                    decoration: InputDecoration(
                                      hintText: 'Buscar por nombre, EAN, PLU, Cód. Prov. o medida...',
                                      prefixIcon: const Icon(Icons.search),
                                      suffixIcon: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_items.isNotEmpty && !_isEditing)
                                            IconButton(
                                              key: const ValueKey(
                                                'toggle_supplier_assistant_btn',
                                              ),
                                              icon: Icon(
                                                _showAssistantPanel
                                                    ? Icons.lightbulb_rounded
                                                    : Icons.lightbulb_outline,
                                                color: _showAssistantPanel
                                                    ? Colors.amber.shade700
                                                    : Colors.blueGrey.shade600,
                                                size: 20,
                                              ),
                                              tooltip: _showAssistantPanel
                                                  ? 'Ocultar sugerencias del proveedor'
                                                  : 'Sugerencias del proveedor',
                                              onPressed: () => setState(
                                                () => _showAssistantPanel =
                                                    !_showAssistantPanel,
                                              ),
                                            ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.add_circle,
                                              color: Colors.blue,
                                            ),
                                            tooltip: 'Nuevo Producto Rápido',
                                            onPressed: () =>
                                                _openNewProductForSupplier(
                                              initialQuery:
                                                  _searchController.text,
                                            ),
                                          ),
                                        ],
                                      ),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    ),
                                    onChanged: _onSearchChanged,
                                  ),
                                  if (!_isSearching &&
                                      _searchResults.isEmpty &&
                                      _recentSearches.isNotEmpty)
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.fromLTRB(
                                        10,
                                        4,
                                        10,
                                        6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        border: Border(
                                          top: BorderSide(
                                            color: Colors.grey.shade200,
                                          ),
                                        ),
                                      ),
                                      child: Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            'Recientes:',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                          for (final term in _recentSearches)
                                            InputChip(
                                              key: ValueKey(
                                                'recent_search_chip_${widget.supplierId}_$term',
                                              ),
                                              label: Text(
                                                '🕒 $term',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                ),
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              onPressed: () =>
                                                  _onSearchSubmittedOrScanned(
                                                term,
                                              ),
                                              onDeleted: () =>
                                                  _removeRecentSearch(term),
                                            ),
                                          TextButton(
                                            style: TextButton.styleFrom(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            onPressed: _clearRecentSearches,
                                            child: const Text(
                                              'Limpiar',
                                              style: TextStyle(fontSize: 10.5),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (_isSearching || _searchResults.isNotEmpty)
                                    Container(
                                      constraints: const BoxConstraints(maxHeight: 200),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          top: BorderSide(color: Colors.grey.shade200),
                                        ),
                                      ),
                                      child: _isSearching
                                          ? const Center(
                                              child: Padding(
                                                padding: EdgeInsets.all(16.0),
                                                child: CircularProgressIndicator(),
                                              ),
                                            )
                                          : ListView.builder(
                                              shrinkWrap: true,
                                              itemCount: _searchResults.length,
                                              itemBuilder: (context, index) {
                                                final p = _searchResults[index];
                                                final hasConv = p.conversionFactor != null &&
                                                    p.conversionFactor! > 1;
                                                final convLabel = hasConv
                                                    ? '${(p.purchasePackageName != null && p.purchasePackageName!.trim().isNotEmpty) ? p.purchasePackageName!.trim() : 'Bulto'} x${(p.conversionFactor! % 1 == 0) ? p.conversionFactor!.toInt() : p.conversionFactor!.toStringAsFixed(2)} ${p.unitShortLabel}'
                                                    : null;
                                                final subtitleParts = <String>[
                                                  if (p.supplierSku != null &&
                                                      p.supplierSku!.trim().isNotEmpty)
                                                    'Cód. Prov: ${p.supplierSku!.trim()}',
                                                  if (p.technicalSpec != null &&
                                                      p.technicalSpec!.trim().isNotEmpty)
                                                    p.technicalSpec!.trim(),
                                                  'Costo: \$${p.costPrice.toCurrency()}',
                                                  'Stock: ${p.stock.toUnitStockDisplay(isSoldByWeight: p.isSoldByWeight, unitSuffix: p.unitShortLabel, weightUnit: p.unitShortLabel)}',
                                                  if (convLabel != null) convLabel,
                                                ];
                                                final isFromThisSupplier =
                                                    p.supplier?.id == widget.supplierId;
                                                final isInactive = !p.active;
                                                return ListTile(
                                                  title: Wrap(
                                                    spacing: 6,
                                                    runSpacing: 4,
                                                    crossAxisAlignment:
                                                        WrapCrossAlignment.center,
                                                    children: [
                                                      Text(
                                                        p.name,
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          color: isInactive
                                                              ? const Color(0xFF64748B)
                                                              : null,
                                                        ),
                                                      ),
                                                      if (isFromThisSupplier)
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 1.5,
                                                          ),
                                                          decoration: BoxDecoration(
                                                            color: const Color(0xFFCCFBF1),
                                                            borderRadius:
                                                                BorderRadius.circular(5),
                                                            border: Border.all(
                                                              color: const Color(0xFF5EEAD4),
                                                            ),
                                                          ),
                                                          child: const Text(
                                                            'De este proveedor',
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.w700,
                                                              color: Color(0xFF0F766E),
                                                            ),
                                                          ),
                                                        ),
                                                      if (isInactive)
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 1.5,
                                                          ),
                                                          decoration: BoxDecoration(
                                                            color: const Color(0xFFFEF3C7),
                                                            borderRadius:
                                                                BorderRadius.circular(5),
                                                            border: Border.all(
                                                              color: const Color(0xFFFCD34D),
                                                            ),
                                                          ),
                                                          child: const Text(
                                                            'Inactivo',
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.w700,
                                                              color: Color(0xFFB45309),
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                  subtitle: Text(
                                                    subtitleParts.join(' · '),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  trailing: const Icon(
                                                    Icons.add_shopping_cart,
                                                    color: Colors.blue,
                                                  ),
                                                  onTap: () => _addProduct(
                                                    p,
                                                    recordSearch: true,
                                                  ),
                                                );
                                              },
                                            ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (_items.isNotEmpty &&
                              !_isEditing &&
                              _showAssistantPanel) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 215,
                              child: Material(
                                color: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(color: Colors.amber.shade200),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: assistantPanel,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),

                          // Tabla de Items
                          if (isWide)
                            Expanded(child: itemsTable)
                          else
                            SizedBox(height: 350, child: itemsTable),
                        ],
                      );

                      final rightFormContent = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Datos Generales',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.bold, fontSize: 13.5),
                                ),
                              ),
                              SizedBox(
                                height: 28,
                                child: OutlinedButton.icon(
                                  onPressed: _isUploading ? null : _pickAndUploadFile,
                                  icon: _isUploading
                                      ? const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.attach_file, size: 14),
                                  label: Text(
                                    _attachmentUrl != null
                                        ? 'Comprobante Adjunto ✓'
                                        : 'Adjuntar Archivo',
                                    style: const TextStyle(fontSize: 11.5),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    foregroundColor: _attachmentUrl != null
                                        ? Colors.green.shade700
                                        : Colors.blue.shade700,
                                    side: BorderSide(
                                      color: _attachmentUrl != null
                                          ? Colors.green.shade300
                                          : Colors.blue.shade300,
                                    ),
                                  ),
                                ),
                              ),
                              if ((_attachmentUrl != null &&
                                      _attachmentUrl!.trim().isNotEmpty) ||
                                  _localAttachmentPath != null) ...[
                                const SizedBox(width: 4),
                                SizedBox(
                                  height: 28,
                                  child: IconButton(
                                    key: const ValueKey(
                                      'preview_supplier_attachment_btn',
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                    tooltip: 'Ver comprobante adjunto',
                                    icon: const Icon(
                                      Icons.visibility_outlined,
                                      size: 16,
                                      color: Color(0xFF1D4ED8),
                                    ),
                                    onPressed: _showAttachmentPreview,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Fila 1: Tipo de Comprobante + Concepto
                          Row(
                            children: [
                              Expanded(
                                flex: 5,
                                child: DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue: _type,
                                  decoration: const InputDecoration(
                                    labelText: 'Tipo de Comprobante',
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'invoice',
                                      child: Text(
                                        'Factura de Compra',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 13),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'delivery_note',
                                      child: Text(
                                        'Remito de Mercadería',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 13),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'credit_note',
                                      child: Text(
                                        'Nota de Crédito',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    setState(() {
                                      _type = val!;
                                      if (_type == 'credit_note') {
                                        _payNow = false;
                                      } else if (!_isEditing) {
                                        _payNow = true;
                                      }
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 4,
                                child: TextFormField(
                                  controller: _descriptionController,
                                  style: const TextStyle(fontSize: 13),
                                  decoration: const InputDecoration(
                                    labelText: 'Concepto',
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  ),
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Fila 2: Fecha Emisión + Vencimiento
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () async {
                                    final date = await showCompactDatePicker(
                                      context: context,
                                      initialDate: _issueDate ?? DateTime.now(),
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime(2100),
                                      helpText: 'Fecha de Emisión del Comprobante',
                                    );
                                    if (!mounted) return;
                                    if (date != null) {
                                      final now = DateTime.now();
                                      setState(
                                        () => _issueDate = DateTime(
                                          date.year,
                                          date.month,
                                          date.day,
                                          now.hour,
                                          now.minute,
                                          now.second,
                                        ),
                                      );
                                    }
                                  },
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      labelText: 'Fecha Emisión',
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    ),
                                    child: Text(
                                      _issueDate != null
                                          ? DateFormat('dd/MM/yyyy').format(_issueDate!)
                                          : 'Seleccionar',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: InkWell(
                                  onTap: () async {
                                    final date = await showCompactDatePicker(
                                      context: context,
                                      initialDate: _dueDate ?? DateTime.now(),
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime(2100),
                                      helpText: 'Fecha de Vencimiento de Pago',
                                    );
                                    if (!mounted) return;
                                    if (date != null) setState(() => _dueDate = date);
                                  },
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      labelText: 'Vencimiento',
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    ),
                                    child: Text(
                                      _dueDate != null
                                          ? DateFormat('dd/MM/yyyy').format(_dueDate!)
                                          : 'Opcional',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Fila 3: En modo edición mostramos Motivo de corrección; Nº Comprobante manual solo si no hay bloque fiscal
                          if (_isEditing && (!isRI || _type == 'delivery_note'))
                            Row(
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: TextFormField(
                                    controller: _invoiceNumberController,
                                    style: const TextStyle(fontSize: 13),
                                    decoration: const InputDecoration(
                                      labelText: 'Nº Comprobante (Opc.)',
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 5,
                                  child: TextFormField(
                                    controller: _editReasonController,
                                    style: const TextStyle(fontSize: 13),
                                    decoration: InputDecoration(
                                      labelText: 'Motivo de la corrección (Auditoría)',
                                      hintText: 'Ej: Error en cantidad / IVA',
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      prefixIcon: Icon(
                                        Icons.history_edu,
                                        color: Colors.amber.shade800,
                                        size: 15,
                                      ),
                                      prefixIconConstraints: const BoxConstraints(minWidth: 28),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else if (_isEditing)
                            TextFormField(
                              controller: _editReasonController,
                              style: const TextStyle(fontSize: 12.5),
                              decoration: InputDecoration(
                                labelText: 'Motivo de la corrección (Auditoría)',
                                hintText: 'Ej: Ajuste de costos / desglose IVA',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                prefixIcon: Icon(
                                  Icons.history_edu,
                                  color: Colors.amber.shade800,
                                  size: 15,
                                ),
                                prefixIconConstraints: const BoxConstraints(minWidth: 28),
                              ),
                            )
                          else if (!isRI || _type == 'delivery_note')
                            TextFormField(
                              controller: _invoiceNumberController,
                              style: const TextStyle(fontSize: 13),
                              decoration: const InputDecoration(
                                labelText: 'Nº Comprobante (Opc.)',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              ),
                            ),
                          if (isRI && _type != 'delivery_note') ...[
                            const SizedBox(height: 6),
                            _buildFiscalSection(),
                          ],
                          const SizedBox(height: 4),
                        ],
                      );

                      final rightBottomContent = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(height: 12),
                          if (!_isEditing && _type != 'credit_note')
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Material(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () => setState(() => _payNow = !_payNow),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.green.shade200),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 28,
                                          height: 28,
                                          child: Checkbox(
                                            value: _payNow,
                                            visualDensity: VisualDensity.compact,
                                            onChanged: (val) => setState(() => _payNow = val ?? false),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Expanded(
                                          child: Row(
                                            children: [
                                              Text(
                                                'Abonar en el acto',
                                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                                              ),
                                              SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  'Abre un movimiento de caja al guardar.',
                                                  style: TextStyle(fontSize: 11, color: Colors.black54),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          // Extra charges (3-col via LayoutBuilder + Wrap to satisfy <=2 Expanded per Row rule)
                          LayoutBuilder(
                            builder: (context, box) {
                              final fieldWidth = ((box.maxWidth - 16) / 3).clamp(85.0, 220.0);
                              return Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  SizedBox(
                                    width: fieldWidth,
                                    child: TextFormField(
                                      controller: _freightCtrl,
                                      style: const TextStyle(fontSize: 13),
                                      decoration: const InputDecoration(
                                        labelText: 'Flete (\$)',
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      ),
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [ArsThousandsInputFormatter()],
                                      onChanged: (v) {
                                        setState(() {
                                          _freightAmount = ArsThousandsInputFormatter.parse(v);
                                          _autoRecalculateFiscalIfNeeded();
                                        });
                                      },
                                    ),
                                  ),
                                  SizedBox(
                                    width: fieldWidth,
                                    child: TextFormField(
                                      controller: _taxCtrl,
                                      style: const TextStyle(fontSize: 13),
                                      decoration: const InputDecoration(
                                        labelText: 'Impuestos (\$)',
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      ),
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [ArsThousandsInputFormatter()],
                                      onChanged: (v) {
                                        setState(() {
                                          _taxAmount = ArsThousandsInputFormatter.parse(v);
                                          _autoRecalculateFiscalIfNeeded();
                                        });
                                      },
                                    ),
                                  ),
                                  SizedBox(
                                    width: fieldWidth,
                                    child: TextFormField(
                                      controller: _discountCtrl,
                                      style: const TextStyle(fontSize: 13),
                                      decoration: const InputDecoration(
                                        labelText: 'Descuento (\$)',
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      ),
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [ArsThousandsInputFormatter()],
                                      onChanged: (v) {
                                        setState(() {
                                          _discountAmount = ArsThousandsInputFormatter.parse(v);
                                          _autoRecalculateFiscalIfNeeded();
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: _isEditing
                                    ? const [Color(0xFF78350F), Color(0xFF92400E)]
                                    : const [AppColors.navyStart, AppColors.navyEnd],
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'TOTAL',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                Flexible(
                                  child: Text(
                                    '\$${_totalAmount.toCurrency()}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            height: 42,
                            child: FilledButton.icon(
                              style: _isEditing
                                  ? FilledButton.styleFrom(
                                      backgroundColor: AppColors.amber,
                                    )
                                  : null,
                              onPressed: _isLoading ? null : _submit,
                              icon: _isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save, size: 18),
                              label: Text(
                                _isEditing ? 'GUARDAR CAMBIOS' : 'CONFIRMAR CARGA',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );

                      final rightPanel = Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: isWide
                            ? Column(
                                children: [
                                  Expanded(child: SingleChildScrollView(child: rightFormContent)),
                                  rightBottomContent,
                                ],
                              )
                            : Column(
                                children: [
                                  rightFormContent,
                                  rightBottomContent,
                                ],
                              ),
                      );

                      if (isWide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 11, child: leftPanel),
                            const SizedBox(width: 16),
                            Expanded(flex: 8, child: rightPanel),
                          ],
                        );
                      } else {
                        return SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              leftPanel,
                              const SizedBox(height: 16),
                              rightPanel,
                            ],
                          ),
                        );
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        ),
      ),
      ),
    );
  }

  Widget _buildConversionSelectorAndPreview(_InvoiceItemModel item, int index) {
    if (!item.hasPackageConversion) return const SizedBox.shrink();

    final factorStr = (item.conversionFactor % 1 == 0)
        ? item.conversionFactor.toInt().toString()
        : item.conversionFactor.toStringAsFixed(2);
    final unitShort = item.product.unitShortLabel;
    final stockIncoming = item.quantity.toUnitStockDisplay(
      isSoldByWeight: item.product.isSoldByWeight,
      unitSuffix: unitShort,
      weightUnit: unitShort,
    );

    return Container(
      margin: const EdgeInsets.only(top: 5, bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: item.enterByPackage
            ? const Color(0xFFF0F9FF)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: item.enterByPackage
              ? const Color(0xFF7DD3FC)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Modo de ingreso:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.blueGrey.shade700,
                ),
              ),
              ChoiceChip(
                key: ValueKey('invoice_item_unit_mode_${item.product.id}_$index'),
                label: Text(
                  'Por Unidad ($unitShort)',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
                selected: !item.enterByPackage,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onSelected: (selected) {
                  if (selected && item.enterByPackage) {
                    setState(() {
                      item.switchInputMode(false);
                      _autoRecalculateFiscalIfNeeded();
                    });
                  }
                },
              ),
              ChoiceChip(
                key: ValueKey('invoice_item_pkg_mode_${item.product.id}_$index'),
                label: Text(
                  'Por ${item.packageLabel} (x$factorStr $unitShort)',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
                selected: item.enterByPackage,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onSelected: (selected) {
                  if (selected && !item.enterByPackage) {
                    setState(() {
                      item.switchInputMode(true);
                      _autoRecalculateFiscalIfNeeded();
                    });
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Entran +$stockIncoming al stock · Costo unit.: \$${item.newCost.toCurrency()} / $unitShort',
            style: TextStyle(
              fontSize: 11.2,
              fontWeight: FontWeight.w700,
              color: item.enterByPackage
                  ? const Color(0xFF0369A1)
                  : Colors.blueGrey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(_InvoiceItemModel item, int index, {bool showVatSelector = false}) {
    final rateLabel = item.vatRate == 0.0
        ? 'Exento 0%'
        : (item.vatRate == 10.5 ? 'IVA 10.5%' : 'IVA ${item.vatRate.toInt()}%');
    final rateColor = item.vatRate == 10.5
        ? Colors.teal
        : (item.vatRate == 27.0
            ? Colors.deepOrange
            : (item.vatRate == 0.0 ? Colors.blueGrey : Colors.indigo));

    int lotIndex = 0;
    int totalLotsForProduct = 0;
    for (int idx = 0; idx < _items.length; idx++) {
      if (_items[idx].product.id == item.product.id) {
        totalLotsForProduct++;
        if (idx <= index) {
          lotIndex++;
        }
      }
    }

    final prevCost = item.product.costPrice;
    final double? costPctDiff = prevCost > 0.0001
        ? ((item.newCost - prevCost) / prevCost) * 100.0
        : null;
    final bool isSpikeWarning =
        !item.enterByPackage && costPctDiff != null && costPctDiff >= 150.0;
    final currentSupplierId = item.product.supplier?.id;
    final bool showLinkSupplierChip = !_isEditing &&
        _type != 'credit_note' &&
        (currentSupplierId == null || currentSupplierId != widget.supplierId);

    return Container(
      key: ObjectKey(item),
      color: index.isOdd ? Colors.grey.shade50.withValues(alpha: 0.7) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message:
                      '${item.product.name}\nCosto Ant: \$${item.product.costPrice.toCurrency()} | PVP Actual: \$${item.product.sellingPrice.toCurrency()}',
                  child: Row(
                    children: [
                      if (totalLotsForProduct > 1) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.deepOrange.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Lote $lotIndex/$totalLotsForProduct',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.deepOrange.shade900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: item.product.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              if (item.product.supplierSku != null &&
                                  item.product.supplierSku!.trim().isNotEmpty)
                                TextSpan(
                                  text: ' [${item.product.supplierSku!.trim()}]',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.indigo.shade700,
                                  ),
                                ),
                              if (item.product.technicalSpec != null &&
                                  item.product.technicalSpec!.trim().isNotEmpty)
                                TextSpan(
                                  text: ' · ${item.product.technicalSpec!.trim()}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blueGrey.shade700,
                                  ),
                                ),
                              TextSpan(
                                text:
                                    '  •  Ant: \$${item.product.costPrice.toCurrency()} | PVP: \$${item.product.sellingPrice.toCurrency()}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.normal,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (showVatSelector) ...[
                const SizedBox(width: 6),
                PopupMenuButton<double>(
                  tooltip: 'Cambiar alícuota de IVA de este artículo',
                  initialValue: item.vatRate,
                  onSelected: (rate) {
                    setState(() {
                      item.vatRate = rate;
                      _autoSyncFiscal21 = true;
                      _autoRecalculateFiscalIfNeeded();
                    });
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 21.0,
                      child: Text('IVA 21% (Estándar)', style: TextStyle(fontSize: 13)),
                    ),
                    PopupMenuItem(
                      value: 10.5,
                      child: Text('IVA 10.5% (Reducido)', style: TextStyle(fontSize: 13)),
                    ),
                    PopupMenuItem(
                      value: 27.0,
                      child: Text('IVA 27% (Servicios)', style: TextStyle(fontSize: 13)),
                    ),
                    PopupMenuItem(
                      value: 0.0,
                      child: Text('Exento / No Gravado (0%)', style: TextStyle(fontSize: 13)),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: rateColor.shade50,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: rateColor.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          rateLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: rateColor.shade800,
                          ),
                        ),
                        Icon(Icons.arrow_drop_down, size: 14, color: rateColor.shade700),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Text(
                '\$${item.subtotal.toCurrency()}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
              const SizedBox(width: 2),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red, size: 17),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                tooltip: 'Quitar ítem',
                onPressed: () {
                  item.dispose();
                  setState(() {
                    _items.removeAt(index);
                    _autoRecalculateFiscalIfNeeded();
                  });
                },
              ),
            ],
          ),
          if (costPctDiff != null || showLinkSupplierChip) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (costPctDiff != null)
                  Container(
                    key: ValueKey('cost_variation_badge_${item.product.id}_$index'),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: costPctDiff.abs() < 0.5
                          ? Colors.grey.shade100
                          : (costPctDiff <= -0.5
                              ? Colors.green.shade50
                              : (costPctDiff >= 30.0
                                  ? Colors.red.shade50
                                  : Colors.orange.shade50)),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: costPctDiff.abs() < 0.5
                            ? Colors.grey.shade300
                            : (costPctDiff <= -0.5
                                ? Colors.green.shade300
                                : (costPctDiff >= 30.0
                                    ? Colors.red.shade300
                                    : Colors.orange.shade300)),
                      ),
                    ),
                    child: Text(
                      costPctDiff.abs() < 0.5
                          ? '= Sin cambio'
                          : (costPctDiff <= -0.5
                              ? '▼ ${costPctDiff.abs() < 10 ? costPctDiff.toStringAsFixed(1) : costPctDiff.toStringAsFixed(0)}%'
                              : '▲ +${costPctDiff < 10 ? costPctDiff.toStringAsFixed(1) : costPctDiff.toStringAsFixed(0)}%'),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: costPctDiff.abs() < 0.5
                            ? Colors.grey.shade700
                            : (costPctDiff <= -0.5
                                ? Colors.green.shade800
                                : (costPctDiff >= 30.0
                                    ? Colors.red.shade800
                                    : Colors.orange.shade800)),
                      ),
                    ),
                  ),
                if (showLinkSupplierChip)
                  FilterChip(
                    key: ValueKey('link_supplier_chip_${item.product.id}_$index'),
                    selected: item.linkSupplier == true,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    padding: EdgeInsets.zero,
                    selectedColor: Colors.indigo.shade50,
                    checkmarkColor: Colors.indigo.shade700,
                    label: Text(
                      currentSupplierId == null
                          ? (item.linkSupplier == true
                              ? 'Vincular al proveedor'
                              : 'Sin vincular proveedor')
                          : (item.linkSupplier == true
                              ? 'Reasignar a este proveedor'
                              : 'Mantener (${item.product.supplier!.name})'),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: item.linkSupplier == true
                            ? Colors.indigo.shade800
                            : Colors.blueGrey.shade700,
                      ),
                    ),
                    onSelected: (v) => setState(() => item.linkSupplier = v),
                  ),
              ],
            ),
          ],
          _buildConversionSelectorAndPreview(item, index),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  key: ValueKey('invoice_item_qty_${item.product.id}_$index'),
                  controller: item.qtyCtrl,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: item.enterByPackage
                        ? 'Cant. (${item.packageLabel})'
                        : 'Cant. (${item.product.unitShortLabel})',
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (val) {
                    final p = double.tryParse(val.replaceAll(',', '.'));
                    if (p != null) {
                      setState(() {
                        item.quantity = item.enterByPackage
                            ? double.parse((p * item.conversionFactor).toStringAsFixed(3))
                            : p;
                        _autoRecalculateFiscalIfNeeded();
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: TextFormField(
                  key: ValueKey('invoice_item_cost_${item.product.id}_$index'),
                  controller: item.costCtrl,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: item.enterByPackage
                        ? 'Costo x ${item.packageLabel}'
                        : 'Costo Un.',
                    prefixText: '\$',
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [ArsThousandsInputFormatter()],
                  onChanged: (val) => _handleCostChange(item, val),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: item.marginCtrl,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: '% Util.',
                    suffixText: '%',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (val) => _handleMarginChange(item, val),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: item.pvpCtrl,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: item.updatePrice ? FontWeight.w600 : FontWeight.normal,
                    color: item.updatePrice ? Colors.green.shade900 : null,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Nuevo PVP',
                    prefixText: '\$',
                    isDense: true,
                    filled: item.updatePrice,
                    fillColor: item.updatePrice
                        ? Colors.green.shade50.withValues(alpha: 0.7)
                        : null,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                    suffixIconConstraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    suffixIcon: Tooltip(
                      message: item.updatePrice
                          ? 'Se actualizará el Precio de Venta a \$${item.manualPrice.toCurrency()}'
                          : 'Marcar para actualizar el Precio de Venta en Catálogo',
                      child: Checkbox(
                        value: item.updatePrice,
                        activeColor: Colors.green.shade700,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (val) =>
                            setState(() => item.updatePrice = val ?? false),
                      ),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [ArsThousandsInputFormatter()],
                  onChanged: (val) => _handlePvpChange(item, val),
                ),
              ),
            ],
          ),
          if (isSpikeWarning)
            Container(
              key: ValueKey('cost_spike_warning_${item.product.id}_$index'),
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber.shade400),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Colors.amber.shade900,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.hasPackageConversion
                          ? 'El costo unitario subió +${costPctDiff.round()}% respecto a \$${prevCost.toCurrency()}. ¿Cargaste el costo por ${item.packageLabel}?'
                          : 'El costo unitario subió +${costPctDiff.round()}% respecto a \$${prevCost.toCurrency()}. Verificá que no corresponda al bulto.',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                  if (item.hasPackageConversion) ...[
                    const SizedBox(width: 6),
                    TextButton(
                      key: ValueKey('switch_spike_to_pkg_${item.product.id}_$index'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: Colors.amber.shade100,
                        foregroundColor: Colors.amber.shade900,
                      ),
                      onPressed: () {
                        final typedPkgQty = item.quantity > 0 ? item.quantity : 1.0;
                        final typedPkgCost = item.newCost;
                        setState(() {
                          item.enterByPackage = true;
                          item.quantity = double.parse(
                            (typedPkgQty * item.conversionFactor).toStringAsFixed(3),
                          );
                          item.qtyCtrl.text =
                              (typedPkgQty - typedPkgQty.roundToDouble()).abs() < 0.0005
                                  ? typedPkgQty.round().toString()
                                  : typedPkgQty.toStringAsFixed(2);
                          item.costCtrl.text = typedPkgCost.toArsInput();
                        });
                        _handleCostChange(item, item.costCtrl.text);
                      },
                      child: Text(
                        'Pasar a Por ${item.packageLabel}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (_canUseBatchesForProduct(item.product) &&
              !item.product.isCombo &&
              !item.product.isService) ...[
            if (!item.showLotFields)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.layers_outlined, size: 14),
                      label: const Text(
                        '+ Lote / Vto.',
                        style: TextStyle(fontSize: 11),
                      ),
                      onPressed: () => setState(() => item.showLotFields = true),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: Colors.deepOrange.shade700,
                      ),
                      icon: const Icon(Icons.add_circle_outline, size: 14),
                      label: const Text(
                        '+ Otro lote',
                        style: TextStyle(fontSize: 11),
                      ),
                      onPressed: () => _addAnotherLotRow(index, item),
                    ),
                  ],
                ),
              )
            else
              Container(
                margin: const EdgeInsets.only(top: 5),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: item.product.trackBatches
                        ? Colors.orange.shade300
                        : Colors.grey.shade300,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, lotConstraints) {
                        final batchCodeField = TextFormField(
                          controller: item.batchCodeCtrl,
                          style: const TextStyle(fontSize: 12),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Lote (opc. auto)',
                            hintText: 'FAC-001',
                            isDense: true,
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            prefixIcon: Icon(Icons.qr_code_outlined, size: 14),
                            prefixIconConstraints:
                                BoxConstraints(minWidth: 24, minHeight: 24),
                          ),
                        );

                        final validityField = TextFormField(
                          controller: item.validityDaysCtrl,
                          style: const TextStyle(fontSize: 12),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(
                            labelText: 'Validez',
                            suffixText: 'd',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 6,
                            ),
                          ),
                          onChanged: (val) {
                            final trimmed = val.trim();
                            if (trimmed.isEmpty) {
                              setState(() => item.expirationDate = null);
                              return;
                            }
                            final n = int.tryParse(trimmed);
                            if (n != null && n >= 1 && n <= 3650) {
                              final now = DateTime.now();
                              setState(() {
                                item.expirationDate =
                                    DateTime(now.year, now.month, now.day + n);
                              });
                            }
                          },
                        );

                        final dateBtn = OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 7,
                            ),
                            minimumSize: const Size(0, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () async {
                            final now = DateTime.now();
                            final picked = await showCompactDatePicker(
                              context: context,
                              initialDate: item.expirationDate ??
                                  DateTime(now.year, now.month, now.day + 7),
                              helpText:
                                  'Vencimiento del lote (${item.product.name})',
                            );
                            if (picked != null) {
                              final currentNow = DateTime.now();
                              final today = DateTime(
                                currentNow.year,
                                currentNow.month,
                                currentNow.day,
                              );
                              final expDay = DateTime(
                                picked.year,
                                picked.month,
                                picked.day,
                              );
                              final diff = expDay.difference(today).inDays;
                              setState(() {
                                item.expirationDate = picked;
                                item.validityDaysCtrl.text =
                                    (diff >= 1 && diff <= 3650)
                                        ? diff.toString()
                                        : '';
                              });
                            }
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.event_available_outlined,
                                size: 14,
                                color: item.expirationDate != null
                                    ? Colors.deepOrange
                                    : null,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  item.expirationDate != null
                                      ? 'Vence: ${DateFormat('dd/MM/yyyy').format(item.expirationDate!)}'
                                      : 'Vencimiento',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                              ),
                            ],
                          ),
                        );

                        final Widget? clearBtn = (item.expirationDate != null ||
                                item.validityDaysCtrl.text.isNotEmpty)
                            ? IconButton(
                                tooltip: 'Limpiar vencimiento',
                                icon: const Icon(Icons.clear, size: 15),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 24,
                                  minHeight: 24,
                                ),
                                onPressed: () => setState(() {
                                  item.expirationDate = null;
                                  item.validityDaysCtrl.clear();
                                }),
                              )
                            : null;

                        final addAnotherLotBtn = Tooltip(
                          message:
                              'Agregar otro lote de este producto (distinto vencimiento)',
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: Colors.deepOrange.shade700,
                            ),
                            icon: const Icon(Icons.add_circle_outline, size: 14),
                            label: const Text(
                              '+ Otro lote',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onPressed: () => _addAnotherLotRow(index, item),
                          ),
                        );

                        if (lotConstraints.maxWidth >= 430) {
                          return Row(
                            children: [
                              Expanded(flex: 3, child: batchCodeField),
                              const SizedBox(width: 5),
                              SizedBox(width: 72, child: validityField),
                              const SizedBox(width: 5),
                              Expanded(flex: 4, child: dateBtn),
                              if (clearBtn != null) clearBtn,
                              const SizedBox(width: 2),
                              addAnotherLotBtn,
                            ],
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(child: batchCodeField),
                                const SizedBox(width: 6),
                                SizedBox(width: 76, child: validityField),
                                const SizedBox(width: 4),
                                addAnotherLotBtn,
                              ],
                            ),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                Expanded(child: dateBtn),
                                if (clearBtn != null) clearBtn,
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                    if (!item.product.trackBatches &&
                        (item.batchCodeCtrl.text.trim().isNotEmpty ||
                            item.expirationDate != null))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Al guardar, se activará el control por lotes conservando el stock actual.',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.teal.shade900,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  TextStyle _fiscalFieldStyle(
    TextEditingController ctrl, {
    MaterialColor accent = Colors.indigo,
    bool isNumeric = true,
  }) {
    final hasVal = isNumeric
        ? ArsThousandsInputFormatter.parse(ctrl.text) > 0
        : ctrl.text.trim().isNotEmpty;
    return TextStyle(
      fontSize: hasVal ? 13.5 : 12.5,
      fontWeight: hasVal ? FontWeight.w800 : FontWeight.w500,
      color: hasVal ? accent.shade900 : Colors.blueGrey.shade700,
    );
  }

  InputDecoration _fiscalBoxDecoration({
    required String label,
    required TextEditingController ctrl,
    MaterialColor accent = Colors.indigo,
    bool isNumeric = true,
    String? hintText,
    Widget? suffixIcon,
  }) {
    final hasVal = isNumeric
        ? ArsThousandsInputFormatter.parse(ctrl.text) > 0
        : ctrl.text.trim().isNotEmpty;
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      isDense: true,
      filled: true,
      fillColor: hasVal
          ? accent.shade50.withValues(alpha: 0.75)
          : const Color(0xFFF8FAFC),
      labelStyle: TextStyle(
        fontSize: 11.5,
        fontWeight: hasVal ? FontWeight.w700 : FontWeight.w500,
        color: hasVal ? accent.shade800 : Colors.blueGrey.shade600,
      ),
      floatingLabelStyle: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: hasVal ? accent.shade800 : Colors.indigo.shade700,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      suffixIcon: suffixIcon,
      suffixIconConstraints: suffixIcon != null
          ? const BoxConstraints(minWidth: 28, minHeight: 24)
          : null,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(
          color: hasVal ? accent.shade400 : Colors.grey.shade300,
          width: hasVal ? 1.3 : 1.0,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: accent.shade700, width: 1.5),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
      ),
    );
  }

  Widget _buildFiscalSection() {
    final isBC = _voucherLetter == 'B' || _voucherLetter == 'C';
    final isSD = _voucherLetter == 'S/D';
    final fSum = _fiscalSum;
    final hasFiscalInput = fSum > 0;
    final isMatching = hasFiscalInput && (fSum - _totalAmount).abs() <= 0.05;
    final invNoText = _invoiceNumberController.text.trim();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasFiscalInput
              ? (isMatching ? Colors.green.shade300 : Colors.amber.shade300)
              : Colors.indigo.shade200,
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Encabezado desplegable
          InkWell(
            onTap: () => setState(() => _isFiscalExpanded = !_isFiscalExpanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.account_balance_rounded,
                    size: 16,
                    color: Colors.indigo.shade800,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Datos Fiscales (ARCA)',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade900,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (invNoText.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.indigo.shade200),
                      ),
                      child: Text(
                        invNoText,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.indigo.shade900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (hasFiscalInput) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isMatching ? Colors.green.shade50 : Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isMatching ? Colors.green.shade300 : Colors.amber.shade300,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isMatching ? Icons.check_circle : Icons.warning_amber_rounded,
                            size: 13,
                            color: isMatching ? Colors.green.shade700 : Colors.amber.shade800,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isMatching ? 'IVA OK' : 'Revisar',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isMatching ? Colors.green.shade800 : Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Icon(
                    _isFiscalExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: Colors.blueGrey,
                  ),
                ],
              ),
            ),
          ),

          if (_isFiscalExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Fila 1: Letra + Afecta Libro IVA
                  Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('voucher_letter_$_voucherLetter'),
                          isExpanded: true,
                          initialValue: _voucherLetter,
                          decoration: InputDecoration(
                            labelText: 'Letra',
                            isDense: true,
                            filled: true,
                            fillColor: Colors.indigo.shade50.withValues(alpha: 0.4),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(7),
                              borderSide: BorderSide(color: Colors.indigo.shade200),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(7),
                            ),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: 'A',
                              child: Text('A (Discrimina IVA)', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                            ),
                            const DropdownMenuItem(
                              value: 'B',
                              child: Text('B (No Computa)', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5)),
                            ),
                            const DropdownMenuItem(
                              value: 'C',
                              child: Text('C (Monotributo)', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5)),
                            ),
                            const DropdownMenuItem(
                              value: 'M',
                              child: Text('M (Retención 100%)', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5)),
                            ),
                            const DropdownMenuItem(
                              value: 'X',
                              child: Text('X (Comprobante Interno)', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5)),
                            ),
                            if (_isEditing || _voucherLetter == 'S/D')
                              const DropdownMenuItem(
                                value: 'S/D',
                                child: Text('S/D (Sin Desglose / Hist.)', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5)),
                              ),
                          ],
                          onChanged: (val) {
                            if (val != null) _onVoucherLetterChanged(val);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 4,
                        child: InkWell(
                          onTap: () => setState(() => _affectsVatBook = !_affectsVatBook),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Libro IVA',
                              isDense: true,
                              filled: true,
                              fillColor: _affectsVatBook
                                  ? Colors.indigo.shade50.withValues(alpha: 0.4)
                                  : Colors.grey.shade100,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(7),
                                borderSide: BorderSide(
                                  color: _affectsVatBook ? Colors.indigo.shade200 : Colors.grey.shade300,
                                ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    _affectsVatBook ? 'Computa' : 'Excluido',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: _affectsVatBook ? Colors.indigo.shade800 : Colors.grey.shade600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Transform.scale(
                                  scale: 0.72,
                                  child: Switch(
                                    value: _affectsVatBook,
                                    onChanged: (v) => setState(() => _affectsVatBook = v),
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Fila 2: Punto de Venta + Nº Comprobante
                  Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: TextFormField(
                          controller: _pointOfSaleCtrl,
                          style: _fiscalFieldStyle(_pointOfSaleCtrl, accent: Colors.blueGrey, isNumeric: false),
                          decoration: _fiscalBoxDecoration(
                            label: 'Pto. Venta',
                            ctrl: _pointOfSaleCtrl,
                            accent: Colors.blueGrey,
                            isNumeric: false,
                            hintText: '0001',
                          ),
                          keyboardType: TextInputType.number,
                          maxLength: 5,
                          buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                          onChanged: (_) => _syncInvoiceNumberFromPvAndNro(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 5,
                        child: TextFormField(
                          controller: _voucherNumberCtrl,
                          style: _fiscalFieldStyle(_voucherNumberCtrl, accent: Colors.blueGrey, isNumeric: false),
                          decoration: _fiscalBoxDecoration(
                            label: 'Nº Comprobante',
                            ctrl: _voucherNumberCtrl,
                            accent: Colors.blueGrey,
                            isNumeric: false,
                            hintText: '00012345',
                          ),
                          keyboardType: TextInputType.number,
                          maxLength: 8,
                          buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                          onChanged: (_) => _syncInvoiceNumberFromPvAndNro(),
                        ),
                      ),
                    ],
                  ),

                  // Banner informativo para S/D (Histórico sin desglose)
                  if (isSD) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blueGrey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Sin desglose de IVA (se imputa en No Gravado).',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blueGrey.shade800,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            height: 26,
                            child: OutlinedButton.icon(
                              onPressed: () => _onVoucherLetterChanged('A'),
                              icon: const Icon(Icons.auto_fix_high, size: 13),
                              label: const Text(
                                'Convertir a Factura A y Calcular IVA 21%',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.indigo.shade700,
                                side: BorderSide(color: Colors.indigo.shade300),
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Banner informativo para Letra B/C
                  if (isBC) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, size: 15, color: Colors.amber.shade800),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Comprobantes B/C no computan Crédito Fiscal. El total se asigna como No Gravado.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.amber.shade900,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Filas 3-5: Alícuotas de IVA (solo si no es B/C ni S/D)
                  if (!isBC && !isSD) ...[
                    const SizedBox(height: 6),
                    // Sub-header visual + Selector de Modo de Costos (c/IVA vs Netos + IVA Mayorista)
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(
                          'IVA CRÉDITO',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: Colors.indigo.shade800,
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () => _toggleCostsIncludeVat(true),
                                borderRadius: const BorderRadius.horizontal(left: Radius.circular(5)),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _costsIncludeVat ? Colors.indigo.shade700 : Colors.transparent,
                                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(5)),
                                  ),
                                  child: Text(
                                    'Costos c/IVA',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: _costsIncludeVat ? Colors.white : Colors.blueGrey.shade700,
                                    ),
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => _toggleCostsIncludeVat(false),
                                borderRadius: const BorderRadius.horizontal(right: Radius.circular(5)),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: !_costsIncludeVat ? Colors.indigo.shade700 : Colors.transparent,
                                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(5)),
                                  ),
                                  child: Text(
                                    'Costos Netos (+IVA)',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: !_costsIncludeVat ? Colors.white : Colors.blueGrey.shade700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _net21Ctrl,
                            style: _fiscalFieldStyle(_net21Ctrl, accent: Colors.indigo),
                            decoration: _fiscalBoxDecoration(
                              label: 'Neto 21% (\$)',
                              ctrl: _net21Ctrl,
                              accent: Colors.indigo,
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [ArsThousandsInputFormatter()],
                            onChanged: _onNet21Changed,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _iva21Ctrl,
                            style: _fiscalFieldStyle(_iva21Ctrl, accent: Colors.indigo),
                            decoration: _fiscalBoxDecoration(
                              label: 'IVA 21% (\$)',
                              ctrl: _iva21Ctrl,
                              accent: Colors.indigo,
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [ArsThousandsInputFormatter()],
                            onChanged: (_) => setState(() => _autoSyncFiscal21 = false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _net105Ctrl,
                            style: _fiscalFieldStyle(_net105Ctrl, accent: Colors.teal),
                            decoration: _fiscalBoxDecoration(
                              label: 'Neto 10.5% (\$)',
                              ctrl: _net105Ctrl,
                              accent: Colors.teal,
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [ArsThousandsInputFormatter()],
                            onChanged: _onNet105Changed,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _iva105Ctrl,
                            style: _fiscalFieldStyle(_iva105Ctrl, accent: Colors.teal),
                            decoration: _fiscalBoxDecoration(
                              label: 'IVA 10.5% (\$)',
                              ctrl: _iva105Ctrl,
                              accent: Colors.teal,
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [ArsThousandsInputFormatter()],
                            onChanged: (_) => setState(() => _autoSyncFiscal21 = false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _net27Ctrl,
                            style: _fiscalFieldStyle(_net27Ctrl, accent: Colors.deepOrange),
                            decoration: _fiscalBoxDecoration(
                              label: 'Neto 27% (\$)',
                              ctrl: _net27Ctrl,
                              accent: Colors.deepOrange,
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [ArsThousandsInputFormatter()],
                            onChanged: _onNet27Changed,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _iva27Ctrl,
                            style: _fiscalFieldStyle(_iva27Ctrl, accent: Colors.deepOrange),
                            decoration: _fiscalBoxDecoration(
                              label: 'IVA 27% (\$)',
                              ctrl: _iva27Ctrl,
                              accent: Colors.deepOrange,
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [ArsThousandsInputFormatter()],
                            onChanged: (_) => setState(() => _autoSyncFiscal21 = false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: SizedBox(
                            height: 26,
                            child: OutlinedButton.icon(
                              onPressed: _distributeTotalInNet21,
                              icon: const Icon(Icons.flash_on, size: 13),
                              label: const Text(
                                'Distribuir Total en Neto 21%',
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.indigo.shade700,
                                side: BorderSide(color: Colors.indigo.shade200),
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          height: 26,
                          child: OutlinedButton(
                            onPressed: () => _distributeTotalByRate(10.5),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.teal.shade800,
                              side: BorderSide(color: Colors.teal.shade300),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            child: const Text(
                              'Todo 10.5%',
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          height: 26,
                          child: OutlinedButton(
                            onPressed: () => _distributeTotalByRate(27.0),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.deepOrange.shade800,
                              side: BorderSide(color: Colors.deepOrange.shade300),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            child: const Text(
                              'Todo 27%',
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Sub-header de Percepciones Provinciales (Rentas IIBB) y Otros
                  const SizedBox(height: 6),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 2,
                    children: [
                      Text(
                        'PERCEPCIONES (RENTAS IIBB / IVA) Y OTROS',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: Colors.indigo.shade800,
                        ),
                      ),
                      Text(
                        '+ Suma al Total',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.indigo.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Fila 6: Percepciones (IVA Nacional + IIBB Rentas Provincial con calculadora %)
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _ivaPerceptionCtrl,
                          style: _fiscalFieldStyle(_ivaPerceptionCtrl, accent: Colors.indigo),
                          decoration: _fiscalBoxDecoration(
                            label: 'Percep. IVA (\$)',
                            ctrl: _ivaPerceptionCtrl,
                            accent: Colors.indigo,
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [ArsThousandsInputFormatter()],
                          onChanged: (_) => _onPerceptionOrInternalTaxChanged(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final iibbBadge = _iibbBadgeLabel;
                            final hasIibbRate = iibbBadge != '% ▾';
                            return TextFormField(
                              controller: _iibbPerceptionCtrl,
                              style: _fiscalFieldStyle(_iibbPerceptionCtrl, accent: Colors.indigo),
                              decoration: _fiscalBoxDecoration(
                                label: 'Percep. IIBB (\$)',
                                ctrl: _iibbPerceptionCtrl,
                                accent: Colors.indigo,
                                suffixIcon: PopupMenuButton<String>(
                                  tooltip: 'Calcular % Percepción IIBB (Rentas / ATP Formosa)',
                                  initialValue: _selectedIibbMode,
                                  onSelected: _applyIibbRate,
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: '1_net',
                                      child: Text('1% sobre Neto Gravado', style: TextStyle(fontSize: 12.5)),
                                    ),
                                    PopupMenuItem(
                                      value: '1.5_net',
                                      child: Text('1.5% sobre Neto Gravado', style: TextStyle(fontSize: 12.5)),
                                    ),
                                    PopupMenuItem(
                                      value: '2_net',
                                      child: Text('2% sobre Neto Gravado', style: TextStyle(fontSize: 12.5)),
                                    ),
                                    PopupMenuItem(
                                      value: '2_gross',
                                      child: Text(
                                        '2% s/ Subtotal+IVA (2,42% s/Neto - Ej. Resistencia)',
                                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: '2.5_net',
                                      child: Text('2.5% sobre Neto Gravado', style: TextStyle(fontSize: 12.5)),
                                    ),
                                    PopupMenuItem(
                                      value: '3_net',
                                      child: Text(
                                        '3% sobre Neto (General Rentas Formosa)',
                                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: '3_gross',
                                      child: Text('3% s/ Subtotal+IVA (3,63% s/Neto)', style: TextStyle(fontSize: 12.5)),
                                    ),
                                    PopupMenuItem(
                                      value: '4_net',
                                      child: Text('4% sobre Neto (No Insc. / Riesgo)', style: TextStyle(fontSize: 12.5)),
                                    ),
                                    PopupMenuDivider(),
                                    PopupMenuItem(
                                      value: 'clear',
                                      child: Text('Limpiar Percepción IIBB (\$0)', style: TextStyle(fontSize: 12.5, color: Colors.red)),
                                    ),
                                  ],
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: hasIibbRate ? AppColors.indigo : Colors.indigo.shade50,
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(
                                        color: hasIibbRate ? Colors.indigo.shade800 : Colors.indigo.shade200,
                                      ),
                                    ),
                                    child: Text(
                                      iibbBadge,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        color: hasIibbRate ? Colors.white : Colors.indigo.shade800,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [ArsThousandsInputFormatter()],
                              onChanged: (_) {
                                _selectedIibbMode = null;
                                _onPerceptionOrInternalTaxChanged();
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),

                  // Fila 7 Compacta (3 columnas vía LayoutBuilder + Wrap): No Gravado, Exento e Imp. Internos
                  const SizedBox(height: 5),
                  LayoutBuilder(
                    builder: (context, box) {
                      final w = ((box.maxWidth - 16) / 3).clamp(80.0, 220.0);
                      return Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          SizedBox(
                            width: w,
                            child: TextFormField(
                              controller: _nonTaxedCtrl,
                              style: _fiscalFieldStyle(_nonTaxedCtrl, accent: Colors.amber),
                              decoration: _fiscalBoxDecoration(
                                label: 'No Gravado (\$)',
                                ctrl: _nonTaxedCtrl,
                                accent: Colors.amber,
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [ArsThousandsInputFormatter()],
                              onChanged: (_) => setState(() => _autoSyncFiscal21 = false),
                            ),
                          ),
                          SizedBox(
                            width: w,
                            child: TextFormField(
                              controller: _exemptCtrl,
                              style: _fiscalFieldStyle(_exemptCtrl, accent: Colors.amber),
                              decoration: _fiscalBoxDecoration(
                                label: 'Exento (\$)',
                                ctrl: _exemptCtrl,
                                accent: Colors.amber,
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [ArsThousandsInputFormatter()],
                              onChanged: (_) => setState(() => _autoSyncFiscal21 = false),
                            ),
                          ),
                          SizedBox(
                            width: w,
                            child: TextFormField(
                              controller: _internalTaxesCtrl,
                              style: _fiscalFieldStyle(_internalTaxesCtrl, accent: Colors.brown),
                              decoration: _fiscalBoxDecoration(
                                label: 'Imp. Internos (\$)',
                                ctrl: _internalTaxesCtrl,
                                accent: Colors.brown,
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [ArsThousandsInputFormatter()],
                              onChanged: (_) => _onPerceptionOrInternalTaxChanged(),
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  // Indicador de suma fiscal
                  if (hasFiscalInput) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isMatching ? Colors.green.shade50 : Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isMatching ? Colors.green.shade300 : Colors.amber.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isMatching ? Icons.check_circle_outline : Icons.error_outline,
                            size: 14,
                            color: isMatching ? Colors.green.shade700 : Colors.amber.shade800,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              isMatching
                                  ? 'Suma fiscal coincide (\$${fSum.toCurrency()})'
                                  : 'Suma fiscal: \$${fSum.toCurrency()} (Total: \$${_totalAmount.toCurrency()})',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isMatching ? Colors.green.shade800 : Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isMatching && _items.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      SizedBox(
                        height: 26,
                        child: OutlinedButton.icon(
                          onPressed: _syncTotalFromFiscalBreakdown,
                          icon: const Icon(Icons.sync_alt, size: 14),
                          label: const Text(
                            'Sincronizar Impuestos / Total con Desglose',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.amber.shade900,
                            side: BorderSide(color: Colors.amber.shade400),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
