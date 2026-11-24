import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/currency_formatter.dart';
import '../../../catalog/data/models/product_model.dart';
import '../../../catalog/domain/entities/product.dart';

/// Sugerencia individual devuelta por el Asistente de Compras del Proveedor.
class SupplierSuggestedItem {
  final Product product;
  final int timesBought;
  final double? lastUnitCost;
  final double? lastQuantity;
  final DateTime? lastPurchasedAt;

  const SupplierSuggestedItem({
    required this.product,
    this.timesBought = 0,
    this.lastUnitCost,
    this.lastQuantity,
    this.lastPurchasedAt,
  });

  factory SupplierSuggestedItem.fromProductJson(Map<String, dynamic> json) {
    final product = ProductModel.fromJson(json);
    final rawLastCost = json['last_unit_cost'];
    final rawLastQty = json['last_quantity'];
    final rawDate = json['last_purchased_at']?.toString();
    return SupplierSuggestedItem(
      product: product,
      timesBought: int.tryParse((json['times_bought'] ?? 0).toString()) ?? 0,
      lastUnitCost: rawLastCost != null
          ? double.tryParse(rawLastCost.toString())
          : null,
      lastQuantity:
          rawLastQty != null ? double.tryParse(rawLastQty.toString()) : null,
      lastPurchasedAt: rawDate != null && rawDate.isNotEmpty
          ? DateTime.tryParse(rawDate)?.toLocal()
          : null,
    );
  }
}

/// Resumen del último comprobante de compra/remito vigente del proveedor para clonar ítems.
class SupplierLastInvoiceSummary {
  final int id;
  final String invoiceNumber;
  final DateTime? issueDate;
  final List<SupplierSuggestedItem> items;

  const SupplierLastInvoiceSummary({
    required this.id,
    required this.invoiceNumber,
    this.issueDate,
    this.items = const [],
  });

  factory SupplierLastInvoiceSummary.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List? ?? const [];
    final parsedItems = <SupplierSuggestedItem>[];
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final itemMap = Map<String, dynamic>.from(raw);
      final prodMap = itemMap['product'];
      if (prodMap is! Map) continue;
      final product = ProductModel.fromJson(Map<String, dynamic>.from(prodMap));
      parsedItems.add(
        SupplierSuggestedItem(
          product: product,
          lastUnitCost:
              double.tryParse((itemMap['unit_cost'] ?? '').toString()),
          lastQuantity:
              double.tryParse((itemMap['quantity'] ?? '').toString()),
        ),
      );
    }

    final rawDate = json['issue_date']?.toString();
    return SupplierLastInvoiceSummary(
      id: int.tryParse((json['id'] ?? 0).toString()) ?? 0,
      invoiceNumber: json['invoice_number']?.toString() ?? '#${json['id']}',
      issueDate: rawDate != null && rawDate.isNotEmpty
          ? DateTime.tryParse(rawDate)?.toLocal()
          : null,
      items: parsedItems,
    );
  }
}

/// Datos completos del panel de sugerencias del proveedor.
class SupplierPurchaseAssistantData {
  final List<SupplierSuggestedItem> lowStock;
  final List<SupplierSuggestedItem> frequent;
  final List<SupplierSuggestedItem> catalog;
  final SupplierLastInvoiceSummary? lastInvoice;

  const SupplierPurchaseAssistantData({
    this.lowStock = const [],
    this.frequent = const [],
    this.catalog = const [],
    this.lastInvoice,
  });

  bool get isEmpty => lowStock.isEmpty && frequent.isEmpty && catalog.isEmpty;

  factory SupplierPurchaseAssistantData.fromJson(Map<String, dynamic> json) {
    List<SupplierSuggestedItem> parseList(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map(
            (e) => SupplierSuggestedItem.fromProductJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList();
    }

    final rawLastInv = json['last_invoice'];
    SupplierLastInvoiceSummary? lastInv;
    if (rawLastInv is Map) {
      final parsed = SupplierLastInvoiceSummary.fromJson(
        Map<String, dynamic>.from(rawLastInv),
      );
      if (parsed.items.isNotEmpty) {
        lastInv = parsed;
      }
    }

    return SupplierPurchaseAssistantData(
      lowStock: parseList(json['low_stock_products']),
      frequent: parseList(json['frequent_products']),
      catalog: parseList(json['catalog_products']),
      lastInvoice: lastInv,
    );
  }
}

/// Almacenamiento local del historial de búsquedas recientes anclado estrictamente por proveedor.
class SupplierSearchHistoryStore {
  static const int maxEntries = 8;

  static String _key(int supplierId) =>
      'supplier_invoice_recent_searches_$supplierId';

  static Future<List<String>> load(int supplierId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return List<String>.from(prefs.getStringList(_key(supplierId)) ?? const []);
    } catch (_) {
      return const [];
    }
  }

  static Future<List<String>> record(int supplierId, String rawTerm) async {
    final term = rawTerm.trim();
    if (term.length < 2) return load(supplierId);
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = List<String>.from(
        prefs.getStringList(_key(supplierId)) ?? const [],
      );
      final lower = term.toLowerCase();
      current.removeWhere((e) => e.trim().toLowerCase() == lower);
      current.insert(0, term);
      if (current.length > maxEntries) {
        current.removeRange(maxEntries, current.length);
      }
      await prefs.setStringList(_key(supplierId), current);
      return current;
    } catch (_) {
      return const [];
    }
  }

  static Future<List<String>> remove(int supplierId, String term) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = List<String>.from(
        prefs.getStringList(_key(supplierId)) ?? const [],
      );
      final lower = term.trim().toLowerCase();
      current.removeWhere((e) => e.trim().toLowerCase() == lower);
      await prefs.setStringList(_key(supplierId), current);
      return current;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> clear(int supplierId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(supplierId));
    } catch (_) {}
  }
}

/// Panel de sugerencias de reposición, historial de compras y onboarding para proveedor nuevo.
class SupplierPurchaseAssistantPanel extends StatefulWidget {
  final String supplierName;
  final SupplierPurchaseAssistantData data;
  final bool isLoading;
  final Set<int> addedProductIds;
  final ValueChanged<SupplierSuggestedItem> onAddItem;
  final VoidCallback onAddAllLowStock;
  final VoidCallback onCloneLastInvoice;
  final VoidCallback onOpenQuickGrid;
  final VoidCallback onOpenNewProduct;

  const SupplierPurchaseAssistantPanel({
    super.key,
    required this.supplierName,
    required this.data,
    required this.isLoading,
    required this.addedProductIds,
    required this.onAddItem,
    required this.onAddAllLowStock,
    required this.onCloneLastInvoice,
    required this.onOpenQuickGrid,
    required this.onOpenNewProduct,
  });

  @override
  State<SupplierPurchaseAssistantPanel> createState() =>
      _SupplierPurchaseAssistantPanelState();
}

class _SupplierPurchaseAssistantPanelState
    extends State<SupplierPurchaseAssistantPanel> {
  String _activeTab = 'low_stock';
  bool _userPickedTab = false;

  @override
  void initState() {
    super.initState();
    _pickBestDefaultTab();
  }

  @override
  void didUpdateWidget(covariant SupplierPurchaseAssistantPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_userPickedTab ||
        oldWidget.data != widget.data && _currentList().isEmpty) {
      _pickBestDefaultTab();
    }
  }

  void _pickBestDefaultTab() {
    if (widget.data.lowStock.isNotEmpty) {
      _activeTab = 'low_stock';
    } else if (widget.data.frequent.isNotEmpty) {
      _activeTab = 'frequent';
    } else if (widget.data.catalog.isNotEmpty) {
      _activeTab = 'catalog';
    } else {
      _activeTab = 'low_stock';
    }
  }

  List<SupplierSuggestedItem> _currentList() {
    switch (_activeTab) {
      case 'frequent':
        return widget.data.frequent;
      case 'catalog':
        return widget.data.catalog;
      case 'low_stock':
      default:
        return widget.data.lowStock;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading && widget.data.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(height: 10),
              Text(
                'Cargando sugerencias del proveedor...',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      );
    }

    if (widget.data.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.storefront_outlined,
                  size: 30,
                  color: Color(0xFF2563EB),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Sin historial ni productos vinculados todavía a ${widget.supplierName}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Podés buscar artículos existentes arriba o crear rápidamente el catálogo inicial leyendo tu factura de papel.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('assistant_open_quick_grid_btn'),
                    onPressed: widget.onOpenQuickGrid,
                    icon: const Icon(Icons.bolt_rounded, size: 17),
                    label: const Text('Carga Masiva en Grilla Rápida'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('assistant_new_product_btn'),
                    onPressed: widget.onOpenNewProduct,
                    icon: const Icon(Icons.add_circle_outline, size: 17),
                    label: const Text('+ Nuevo Producto'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final currentItems = _currentList();
    final lastInvoice = widget.data.lastInvoice;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ChoiceChip(
                    key: const ValueKey('assistant_tab_low_stock'),
                    label: Text(
                      '🔴 Faltantes (${widget.data.lowStock.length})',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    selected: _activeTab == 'low_stock',
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onSelected: (_) => setState(() {
                      _userPickedTab = true;
                      _activeTab = 'low_stock';
                    }),
                  ),
                  ChoiceChip(
                    key: const ValueKey('assistant_tab_frequent'),
                    label: Text(
                      '🔄 Comprados antes (${widget.data.frequent.length})',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    selected: _activeTab == 'frequent',
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onSelected: (_) => setState(() {
                      _userPickedTab = true;
                      _activeTab = 'frequent';
                    }),
                  ),
                  ChoiceChip(
                    key: const ValueKey('assistant_tab_catalog'),
                    label: Text(
                      '📦 Del Proveedor (${widget.data.catalog.length})',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    selected: _activeTab == 'catalog',
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onSelected: (_) => setState(() {
                      _userPickedTab = true;
                      _activeTab = 'catalog';
                    }),
                  ),
                ],
              ),
              if ((_activeTab == 'low_stock' &&
                      widget.data.lowStock.isNotEmpty) ||
                  lastInvoice != null) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (_activeTab == 'low_stock' &&
                        widget.data.lowStock.isNotEmpty)
                      ActionChip(
                        key: const ValueKey('assistant_add_all_low_stock_btn'),
                        avatar: const Icon(
                          Icons.playlist_add_rounded,
                          size: 15,
                          color: Color(0xFFB91C1C),
                        ),
                        label: const Text(
                          'Agregar todos los faltantes',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF991B1B),
                          ),
                        ),
                        backgroundColor: const Color(0xFFFEF2F2),
                        side: const BorderSide(color: Color(0xFFFECACA)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onPressed: widget.onAddAllLowStock,
                      ),
                    if (lastInvoice != null)
                      ActionChip(
                        key: const ValueKey('assistant_clone_last_invoice_btn'),
                        avatar: const Icon(
                          Icons.content_copy_rounded,
                          size: 14,
                          color: Color(0xFF1D4ED8),
                        ),
                        label: Text(
                          '📋 Traer última compra (${lastInvoice.invoiceNumber})',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E40AF),
                          ),
                        ),
                        backgroundColor: const Color(0xFFEFF6FF),
                        side: const BorderSide(color: Color(0xFFBFDBFE)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onPressed: widget.onCloneLastInvoice,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: currentItems.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _activeTab == 'low_stock'
                          ? 'Sin faltantes por debajo del mínimo en este proveedor.'
                          : (_activeTab == 'frequent'
                              ? 'Aún no hay facturas previas registradas para este proveedor.'
                              : 'No hay artículos vinculados directamente a este proveedor.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: currentItems.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = currentItems[index];
                    final p = item.product;
                    final alreadyAdded = widget.addedProductIds.contains(p.id);
                    final hasConv =
                        p.conversionFactor != null && p.conversionFactor! > 1;
                    final pkgName = (p.purchasePackageName != null &&
                            p.purchasePackageName!.trim().isNotEmpty)
                        ? p.purchasePackageName!.trim()
                        : 'Bulto';
                    final convBadge = hasConv
                        ? '$pkgName x${p.conversionFactor!.toQty()} ${p.unitShortLabel}'
                        : null;
                    final stockStr = p.stock.toUnitStockDisplay(
                      isSoldByWeight: p.isSoldByWeight,
                      unitSuffix: p.unitShortLabel,
                      weightUnit: p.unitShortLabel,
                    );
                    final minStr = p.minStock?.toQty();
                    final effectiveCost =
                        p.costPrice > 0 ? p.costPrice : (item.lastUnitCost ?? 0);

                    final subtitleParts = <String>[
                      if (p.supplierSku != null &&
                          p.supplierSku!.trim().isNotEmpty)
                        'Cód. ${p.supplierSku!.trim()}',
                      if (p.technicalSpec != null &&
                          p.technicalSpec!.trim().isNotEmpty)
                        p.technicalSpec!.trim(),
                      'Stock: $stockStr${minStr != null ? ' (Mín: $minStr)' : ''}',
                      if (effectiveCost > 0)
                        'Costo: \$${effectiveCost.toCurrency()}',
                      if (_activeTab == 'frequent' && item.timesBought > 0)
                        '${item.timesBought}x comprado',
                      if (convBadge != null) convBadge,
                    ];

                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ),
                      title: Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            p.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.8,
                            ),
                          ),
                          if (p.stock <= 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Sin stock',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFB91C1C),
                                ),
                              ),
                            )
                          else if (p.minStock != null &&
                              p.minStock! > 0 &&
                              p.stock <= p.minStock!)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Stock bajo',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFB45309),
                                ),
                              ),
                            ),
                          if (alreadyAdded)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '✓ En lista',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF15803D),
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        subtitleParts.join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.2),
                      ),
                      trailing: IconButton(
                        tooltip: 'Agregar al comprobante',
                        icon: Icon(
                          alreadyAdded
                              ? Icons.add_circle_outline
                              : Icons.add_circle_rounded,
                          color: alreadyAdded
                              ? const Color(0xFF0F766E)
                              : const Color(0xFF2563EB),
                        ),
                        onPressed: () => widget.onAddItem(item),
                      ),
                      onTap: () => widget.onAddItem(item),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
