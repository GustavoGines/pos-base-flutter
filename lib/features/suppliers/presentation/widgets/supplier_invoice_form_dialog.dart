import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:http/http.dart' as http;
import '../../../../core/network/api_client.dart';
import '../../../../core/presentation/widgets/compact_date_range_picker_dialog.dart';
import '../../../../core/utils/currency_formatter.dart';

import '../../providers/supplier_provider.dart';
import '../../../pos/presentation/providers/pos_provider.dart';
import '../../../catalog/domain/entities/product.dart';
import '../../../cash_movements/presentation/widgets/movement_form_dialog.dart';
import '../../../../core/constants/app_permissions.dart';
import '../../../auth/presentation/widgets/admin_pin_dialog.dart';

import '../../../catalog/presentation/providers/catalog_provider.dart';
import '../../../catalog/presentation/pages/catalog_screen.dart' show ProductFormDialog;
import 'dart:async';

class _InvoiceItemModel {
  final Product product;
  double quantity;
  double newCost;
  double? suggestedPrice;
  double manualPrice;
  bool updatePrice;
  String priceAnchor = 'cost'; // 'cost' | 'selling'
  late final TextEditingController qtyCtrl;
  late final TextEditingController costCtrl;
  late final TextEditingController marginCtrl;
  late final TextEditingController pvpCtrl;

  _InvoiceItemModel({
    required this.product,
    this.quantity = 1,
    required this.newCost,
    required this.manualPrice,
    this.updatePrice = false,
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
  }

  void dispose() {
    qtyCtrl.dispose();
    costCtrl.dispose();
    marginCtrl.dispose();
    pvpCtrl.dispose();
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
  // ignore: prefer_final_fields
  bool _isUploading = false;

  bool get _isEditing => widget.initialInvoice != null;

  @override
  void initState() {
    super.initState();
    final inv = widget.initialInvoice;
    if (inv != null) {
      _payNow = false;
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
          stock: double.tryParse((prodMap['stock'] ?? 0).toString()) ?? 0.0,
          active: true,
          isSoldByWeight: isWeight,
          unitType: unitType,
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
          ),
        );
      }
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
    _searchController.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    super.dispose();
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
        final results = await context.read<PosProvider>().search(query);
        if (mounted) {
          setState(() {
            _searchResults = results;
            _isSearching = false;
          });
          // Auto-agregar si es un código de barras exacto (Modo Escáner Continuo)
          if (results.length == 1 &&
              results.first.barcode != null &&
              results.first.barcode!.trim() == query.trim()) {
            _addProduct(results.first);
          }
        }
      } catch (e) {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  void _addProduct(Product product) {
    final existingIndex = _items.indexWhere((i) => i.product.id == product.id);
    if (existingIndex >= 0) {
      setState(() {
        _items[existingIndex].quantity += 1;
        final item = _items[existingIndex];
        item.qtyCtrl.text = item.product.isSoldByWeight || item.product.unitType == 'kg'
            ? item.quantity.toStringAsFixed(3)
            : item.quantity.toInt().toString();
      });
    } else {
      setState(() {
        _items.insert(
          0,
          _InvoiceItemModel(
            product: product,
            newCost: product.costPrice,
            manualPrice: product.sellingPrice,
          ),
        );
      });
    }
    _searchController.clear();
    _searchResults = [];
    _searchFocus.requestFocus();
  }

  void _handleCostChange(_InvoiceItemModel item, String val) {
    final parsed = ArsThousandsInputFormatter.parse(val);

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
    });
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
        item.costCtrl.text = item.newCost.toArsInput();
      } else if (item.newCost > 0) {
        final calcPvp = item.newCost * (1 + (margin / 100));
        item.manualPrice = double.parse(calcPvp.toStringAsFixed(2));
        item.pvpCtrl.text = item.manualPrice.toArsInput();
        item.updatePrice = true;
      }
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
        item.costCtrl.text = item.newCost.toArsInput();
      } else if (item.newCost > 0) {
        // Regla Costo como Ancla: si el producto ya tiene costo, editar el PVP
        // solo recalcula la utilidad (%) y mantiene el costo firme como ancla.
        item.priceAnchor = 'cost';
        final effMargin = ((pvp - item.newCost) / item.newCost) * 100;
        item.marginCtrl.text = effMargin.toCleanMargin();
      } else {
        item.priceAnchor = 'selling';
      }
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

  double get _totalAmount {
    if (_items.isEmpty) return 0.0;
    final sub = _items.fold(0.0, (sum, item) => sum + item.subtotal);
    return sub + _freightAmount + _taxAmount - _discountAmount;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe agregar al menos un producto')),
      );
      return;
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
        final itemsData = _items
            .map((i) => {
                  'product_id': i.product.id,
                  'quantity': i.quantity,
                  'unit_cost': i.newCost,
                  'subtotal': i.quantity * i.newCost,
                  'update_price': i.updatePrice,
                  'new_selling_price': i.updatePrice ? i.manualPrice : null,
                })
            .toList();

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
            unawaited(catalogProv.loadProducts());
          }
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
              unawaited(catalogProv.loadProducts());
            }
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
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 820),
        padding: const EdgeInsets.all(0),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: _isEditing ? Colors.amber.shade900 : Colors.blue.shade800,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(
                    _isEditing ? Icons.edit_document : Icons.inventory_2,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isEditing
                          ? 'Editar Comprobante de Proveedor #${widget.initialInvoice!['id']}'
                          : 'Espejo de Ventas - Carga de Remito / Factura',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Proveedor: ${widget.supplierName}',
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 800;

                      final itemsTable = Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _items.isEmpty
                            ? Center(
                                child: Text(
                                  'Busque y seleccione productos para agregarlos al comprobante.',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              )
                            : ListView.separated(
                                itemCount: _items.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = _items[index];
                                  return _buildItemRow(item, index);
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
                                    controller: _searchController,
                                    focusNode: _searchFocus,
                                    decoration: InputDecoration(
                                      hintText: 'Buscar producto por nombre o código...',
                                      prefixIcon: const Icon(Icons.search),
                                      suffixIcon: IconButton(
                                        icon: const Icon(Icons.add_circle, color: Colors.blue),
                                        tooltip: 'Nuevo Producto Rápido',
                                        onPressed: () async {
                                          final catalogProv = context.read<CatalogProvider>();
                                          await showDialog(
                                            context: context,
                                            barrierDismissible: false,
                                            builder: (_) =>
                                                ProductFormDialog(provider: catalogProv),
                                          );
                                        },
                                      ),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.all(16),
                                    ),
                                    onChanged: _onSearchChanged,
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
                                                return ListTile(
                                                  title: Text(
                                                    p.name,
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                  subtitle: Text(
                                                    'Costo actual: \$${p.costPrice.toCurrency()} | Stock: ${p.stock}',
                                                  ),
                                                  trailing: const Icon(
                                                    Icons.add_shopping_cart,
                                                    color: Colors.blue,
                                                  ),
                                                  onTap: () => _addProduct(p),
                                                );
                                              },
                                            ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

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
                          Text(
                            'Datos Generales',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _type,
                            decoration: const InputDecoration(
                              labelText: 'Tipo de Comprobante',
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'invoice',
                                child: Text(
                                  'Factura de Compra',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'delivery_note',
                                child: Text(
                                  'Remito de Mercadería',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'credit_note',
                                child: Text(
                                  'Nota de Crédito',
                                  overflow: TextOverflow.ellipsis,
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
                          const SizedBox(height: 16),
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
                                    ),
                                    child: Text(
                                      _issueDate != null
                                          ? DateFormat('dd/MM/yyyy').format(_issueDate!)
                                          : 'Seleccionar',
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
                                    ),
                                    child: Text(
                                      _dueDate != null
                                          ? DateFormat('dd/MM/yyyy').format(_dueDate!)
                                          : 'Opcional',
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _invoiceNumberController,
                            decoration: const InputDecoration(
                              labelText: 'Nº Comprobante (Opc.)',
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _descriptionController,
                            decoration: const InputDecoration(
                              labelText: 'Concepto',
                              isDense: true,
                            ),
                            maxLines: 2,
                          ),
                          if (_isEditing) ...[
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _editReasonController,
                              decoration: InputDecoration(
                                labelText: 'Motivo de la corrección (Auditoría)',
                                hintText: 'Ej: Error en cantidad / precio de flete',
                                isDense: true,
                                prefixIcon: Icon(
                                  Icons.history_edu,
                                  color: Colors.amber.shade800,
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          // Attachment button
                          OutlinedButton.icon(
                            onPressed: _isUploading ? null : _pickAndUploadFile,
                            icon: _isUploading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.attach_file),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _attachmentUrl != null
                                    ? 'Comprobante Adjunto ✓'
                                    : 'Adjuntar Archivo',
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
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
                          const SizedBox(height: 16),
                        ],
                      );

                      final rightBottomContent = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!_isEditing && _type != 'credit_note')
                            Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              child: Material(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                clipBehavior: Clip.antiAlias,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.green.shade200),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: CheckboxListTile(
                                    title: const Text(
                                      'Abonar en el acto',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    subtitle: const Text(
                                      'Abre un movimiento de caja al guardar.',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    value: _payNow,
                                    onChanged: (val) => setState(() => _payNow = val ?? false),
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity: ListTileControlAffinity.leading,
                                  ),
                                ),
                              ),
                            ),

                          // Extra charges
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              SizedBox(
                                width: 90,
                                child: TextFormField(
                                  controller: _freightCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Flete (\$)',
                                    isDense: true,
                                  ),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [ArsThousandsInputFormatter()],
                                  onChanged: (v) {
                                    setState(() => _freightAmount = ArsThousandsInputFormatter.parse(v));
                                  },
                                ),
                              ),
                              SizedBox(
                                width: 90,
                                child: TextFormField(
                                  controller: _taxCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Impuestos (\$)',
                                    isDense: true,
                                  ),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [ArsThousandsInputFormatter()],
                                  onChanged: (v) {
                                    setState(() => _taxAmount = ArsThousandsInputFormatter.parse(v));
                                  },
                                ),
                              ),
                              SizedBox(
                                width: 90,
                                child: TextFormField(
                                  controller: _discountCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Descuento (\$)',
                                    isDense: true,
                                  ),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [ArsThousandsInputFormatter()],
                                  onChanged: (v) {
                                    setState(() => _discountAmount = ArsThousandsInputFormatter.parse(v));
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _isEditing ? Colors.amber.shade900 : Colors.blue.shade900,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'TOTAL',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '\$${_totalAmount.toCurrency()}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: FilledButton.icon(
                              style: _isEditing
                                  ? FilledButton.styleFrom(
                                      backgroundColor: Colors.amber.shade800,
                                    )
                                  : null,
                              onPressed: _isLoading ? null : _submit,
                              icon: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save),
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
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
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
                            Expanded(flex: 6, child: leftPanel),
                            const SizedBox(width: 24),
                            Expanded(flex: 3, child: rightPanel),
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
    );
  }

  Widget _buildItemRow(_InvoiceItemModel item, int index) {
    return Padding(
      key: ValueKey('invoice_item_${item.product.id}'),
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.product.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Costo Ant: \$${item.product.costPrice.toCurrency()} | PVP Actual: \$${item.product.sellingPrice.toCurrency()}',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '\$${item.subtotal.toCurrency()}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  item.dispose();
                  setState(() => _items.removeAt(index));
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: item.qtyCtrl,
                  decoration: InputDecoration(
                    labelText: 'Cant. (${item.product.unitType})',
                    isDense: true,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (val) {
                    final p = double.tryParse(val.replaceAll(',', '.'));
                    if (p != null) setState(() => item.quantity = p);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: item.costCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Costo Un. (Opc.)',
                    prefixText: '\$',
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [ArsThousandsInputFormatter()],
                  onChanged: (val) => _handleCostChange(item, val),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: item.marginCtrl,
                  decoration: const InputDecoration(
                    labelText: '% Util.',
                    suffixText: '%',
                    isDense: true,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (val) => _handleMarginChange(item, val),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: item.pvpCtrl,
                  decoration: InputDecoration(
                    labelText: 'Nuevo PVP',
                    prefixText: '\$',
                    isDense: true,
                    suffixIcon: Tooltip(
                      message: 'Actualizar Precio de Venta en Catálogo',
                      child: Checkbox(
                        value: item.updatePrice,
                        visualDensity: VisualDensity.compact,
                        onChanged: (val) => setState(() => item.updatePrice = val ?? false),
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
          if (item.updatePrice)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                '✓ Se actualizará el Precio de Venta a \$${item.manualPrice.toCurrency()}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.green.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
