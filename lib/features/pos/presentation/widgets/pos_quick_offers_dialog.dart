import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pos_provider.dart';
import 'package:frontend_desktop/features/offers/presentation/providers/offer_provider.dart';
import 'package:frontend_desktop/features/offers/data/models/offer_model.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/features/auth/presentation/widgets/admin_pin_dialog.dart';

class PosQuickOffersDialog extends StatefulWidget {
  const PosQuickOffersDialog({super.key});

  @override
  State<PosQuickOffersDialog> createState() => _PosQuickOffersDialogState();
}

class _PosQuickOffersDialogState extends State<PosQuickOffersDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _offerNameCtrl = TextEditingController();
  final TextEditingController _discountCtrl = TextEditingController(text: '10');
  final TextEditingController _historySearchCtrl = TextEditingController();

  String _offerType = 'percentage'; // 'percentage', 'fixed_price'
  String _periodType = 'daily'; // 'daily', 'weekly', 'monthly'
  final Set<String> _selectedDaysOfWeek = {};
  static const List<MapEntry<String, String>> _weekDayOptions = [
    MapEntry('monday', 'Lun'),
    MapEntry('tuesday', 'Mar'),
    MapEntry('wednesday', 'Mié'),
    MapEntry('thursday', 'Jue'),
    MapEntry('friday', 'Vie'),
    MapEntry('saturday', 'Sáb'),
    MapEntry('sunday', 'Dom'),
  ];

  String _historyFilter = 'all'; // 'all', 'expired', 'paused', 'active'
  final List<Product> _selectedProducts = [];
  bool _isSaving = false;
  bool _isLoadingGroup = false;
  int _searchSeq = 0; // Token de debounce del buscador de productos en formulario
  int _historySearchSeq = 0; // Token de debounce del buscador en historial
  OfferModel? _editingOffer;
  TextEditingController? _autoCompleteCtrl;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    final pos = Provider.of<PosProvider>(context, listen: false);
    // Pre-cargar con los productos actualmente en el carrito
    if (pos.cart.isNotEmpty) {
      for (final item in pos.cart) {
        if (!_selectedProducts.any((p) => p.id == item.product.id)) {
          _selectedProducts.add(item.product);
        }
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final offerProv = Provider.of<OfferProvider>(context, listen: false);
      final posProv = Provider.of<PosProvider>(context, listen: false);
      offerProv.loadActiveOffers().then((_) {
        if (mounted) {
          posProv.syncActiveOffers(offerProv.activeOffers);
        }
      });
      offerProv.loadAllOffers(status: _historyFilter);
      final catalogProv = Provider.of<CatalogProvider>(context, listen: false);
      if (catalogProv.categories.isEmpty || catalogProv.brands.isEmpty) {
        catalogProv.loadMetadata();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _offerNameCtrl.dispose();
    _discountCtrl.dispose();
    _historySearchCtrl.dispose();
    super.dispose();
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '-';
    final d = dt.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  /// Busca en el servidor (todo el catálogo) con debounce.
  Future<Iterable<Product>> _searchCatalogProducts(String text) async {
    final query = text.trim();
    if (query.isEmpty) return const Iterable<Product>.empty();
    final seq = ++_searchSeq;
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted || seq != _searchSeq) return const Iterable<Product>.empty();
    final catalog = Provider.of<CatalogProvider>(context, listen: false);
    final results = await catalog.searchProductsRemote(query);
    if (!mounted || seq != _searchSeq) return const Iterable<Product>.empty();
    return results;
  }

  void _onHistorySearchChanged(String text) {
    final seq = ++_historySearchSeq;
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted || seq != _historySearchSeq) return;
      Provider.of<OfferProvider>(context, listen: false).loadAllOffers(
        status: _historyFilter,
        search: text,
      );
    });
  }

  void _setHistoryFilter(String filter) {
    setState(() => _historyFilter = filter);
    Provider.of<OfferProvider>(context, listen: false).loadAllOffers(
      status: filter,
      search: _historySearchCtrl.text,
    );
  }

  String _formatDiscountInputValue(double? value, {required String fallback}) {
    if (value == null || value <= 0) return fallback;
    return value == value.roundToDouble() ? value.toInt().toString() : value.toString();
  }

  void _startEditOffer(OfferModel offer) {
    setState(() {
      _editingOffer = offer;
      _offerNameCtrl.text = offer.name;
      _offerType = offer.type == 'fixed_price' ? 'fixed_price' : 'percentage';
      _discountCtrl.text = _offerType == 'fixed_price'
          ? _formatDiscountInputValue(offer.discountAmount, fallback: '1000')
          : _formatDiscountInputValue(offer.discountPercentage, fallback: '10');
      _periodType = offer.periodType;
      _selectedDaysOfWeek
        ..clear()
        ..addAll(offer.daysOfWeek ?? const []);
      _selectedProducts.clear();
      for (final pMap in offer.products) {
        final id = (pMap['id'] as num?)?.toInt() ?? 0;
        final name = pMap['name']?.toString() ?? 'Producto';
        final sellingPrice = double.tryParse(pMap['selling_price']?.toString() ?? '0') ?? 0.0;
        final internalCode = pMap['internal_code']?.toString() ?? '';
        final barcode = pMap['barcode']?.toString();
        final costPrice = double.tryParse(pMap['cost_price']?.toString() ?? '0') ?? 0.0;
        _selectedProducts.add(Product(
          id: id,
          name: name,
          sellingPrice: sellingPrice,
          internalCode: internalCode,
          barcode: barcode,
          costPrice: costPrice,
          stock: 0,
          active: true,
          isSoldByWeight: false,
        ));
      }
    });
    _tabController.animateTo(2);
  }

  void _useOfferAsTemplate(OfferModel offer) {
    setState(() {
      _editingOffer = null; // No editamos el id existente, creamos una nueva
      _offerNameCtrl.text = '${offer.name} (Copia)';
      _offerType = offer.type == 'fixed_price' ? 'fixed_price' : 'percentage';
      _discountCtrl.text = _offerType == 'fixed_price'
          ? _formatDiscountInputValue(offer.discountAmount, fallback: '1000')
          : _formatDiscountInputValue(offer.discountPercentage, fallback: '10');
      _periodType = offer.periodType;
      _selectedDaysOfWeek
        ..clear()
        ..addAll(offer.daysOfWeek ?? const []);
      _selectedProducts.clear();
      for (final pMap in offer.products) {
        final id = (pMap['id'] as num?)?.toInt() ?? 0;
        final name = pMap['name']?.toString() ?? 'Producto';
        final sellingPrice = double.tryParse(pMap['selling_price']?.toString() ?? '0') ?? 0.0;
        final internalCode = pMap['internal_code']?.toString() ?? '';
        final barcode = pMap['barcode']?.toString();
        final costPrice = double.tryParse(pMap['cost_price']?.toString() ?? '0') ?? 0.0;
        _selectedProducts.add(Product(
          id: id,
          name: name,
          sellingPrice: sellingPrice,
          internalCode: internalCode,
          barcode: barcode,
          costPrice: costPrice,
          stock: 0,
          active: true,
          isSoldByWeight: false,
        ));
      }
    });
    _tabController.animateTo(2);
    SnackBarService.info(context, '📋 Plantilla cargada. Ajustá productos o descuentos antes de activar.');
  }

  void _cancelEdit() {
    setState(() {
      _editingOffer = null;
      _offerNameCtrl.clear();
      _offerType = 'percentage';
      _discountCtrl.text = '10';
      _periodType = 'daily';
      _selectedDaysOfWeek.clear();
      _selectedProducts.clear();
      final pos = Provider.of<PosProvider>(context, listen: false);
      for (final item in pos.cart) {
        if (!_selectedProducts.any((p) => p.id == item.product.id)) {
          _selectedProducts.add(item.product);
        }
      }
    });
  }

  Future<void> _showGroupPickerAndAddProducts({required String groupType}) async {
    final catalogProv = Provider.of<CatalogProvider>(context, listen: false);
    final supplierProv = Provider.of<SupplierProvider>(context, listen: false);

    String title;
    IconData headerIcon;
    List<({int id, String name, String? subtitle})> items = [];

    try {
      if (groupType == 'category') {
        title = 'Agregar productos por Categoría';
        headerIcon = Icons.category_outlined;
        if (catalogProv.categories.isEmpty) {
          await catalogProv.loadMetadata();
        }
        items = catalogProv.categories
            .map((c) => (id: c.id, name: c.name, subtitle: c.rubro?.name ?? c.description))
            .toList();
      } else if (groupType == 'brand') {
        title = 'Agregar productos por Marca';
        headerIcon = Icons.sell_outlined;
        if (catalogProv.brands.isEmpty) {
          await catalogProv.loadMetadata();
        }
        items = catalogProv.brands
            .map((b) => (id: b.id, name: b.name, subtitle: b.description))
            .toList();
      } else {
        title = 'Agregar productos por Proveedor';
        headerIcon = Icons.local_shipping_outlined;
        if (supplierProv.suppliers.isEmpty) {
          await supplierProv.fetchSuppliers();
        }
        items = supplierProv.suppliers
            .map((s) => (id: s.id, name: s.name, subtitle: s.cuit != null && s.cuit!.isNotEmpty ? 'CUIT: ${s.cuit}' : null))
            .toList();
      }
    } catch (e) {
      if (mounted) {
        SnackBarService.error(context, 'No se pudo cargar el listado: $e');
      }
      return;
    }

    if (!mounted) return;

    if (items.isEmpty) {
      SnackBarService.warning(context, 'No hay registros cargados para seleccionar.');
      return;
    }

    final selectedGroup = await showDialog<({int id, String name})>(
      context: context,
      builder: (dialogCtx) {
        String search = '';
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final q = search.trim().toLowerCase();
            final filtered = q.isEmpty
                ? items
                : items.where((it) {
                    return it.name.toLowerCase().contains(q) ||
                        (it.subtitle != null && it.subtitle!.toLowerCase().contains(q));
                  }).toList();

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(headerIcon, color: const Color(0xFF7B1FA2), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                  ),
                ],
              ),
              content: SizedBox(
                width: 440,
                height: 380,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      onChanged: (v) => setDialogState(() => search = v),
                      decoration: InputDecoration(
                        hintText: 'Filtrar por nombre...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                'Sin coincidencias para "$search"',
                                style: const TextStyle(color: Colors.grey, fontSize: 13),
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                              itemBuilder: (_, idx) {
                                final item = filtered[idx];
                                return ListTile(
                                  dense: true,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  leading: Icon(headerIcon, size: 18, color: Colors.purple.shade700),
                                  title: Text(
                                    item.name,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                  subtitle: (item.subtitle != null && item.subtitle!.isNotEmpty)
                                      ? Text(item.subtitle!, style: const TextStyle(fontSize: 11))
                                      : null,
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '+ Cargar',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.purple.shade800,
                                      ),
                                    ),
                                  ),
                                  onTap: () => Navigator.of(dialogCtx).pop((id: item.id, name: item.name)),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (selectedGroup == null || !mounted) return;

    setState(() => _isLoadingGroup = true);
    final products = await catalogProv.fetchProductsByGroup(
      categoryId: groupType == 'category' ? selectedGroup.id : null,
      brandId: groupType == 'brand' ? selectedGroup.id : null,
      supplierId: groupType == 'supplier' ? selectedGroup.id : null,
    );
    if (!mounted) return;
    setState(() => _isLoadingGroup = false);

    if (products.isEmpty) {
      SnackBarService.warning(
        context,
        'No se encontraron productos activos asociados a "${selectedGroup.name}".',
      );
      return;
    }

    int addedCount = 0;
    setState(() {
      for (final p in products) {
        if (!_selectedProducts.any((sp) => sp.id == p.id)) {
          _selectedProducts.add(p);
          addedCount++;
        }
      }
      if (_offerNameCtrl.text.trim().isEmpty) {
        final rawVal = double.tryParse(_discountCtrl.text.trim().replaceAll(',', '.')) ?? 0;
        if (_offerType == 'fixed_price') {
          final amtStr = rawVal > 0 ? '\$${rawVal.toCurrency()}' : '\$1.000';
          _offerNameCtrl.text = 'Promo ${selectedGroup.name} $amtStr OFF';
        } else {
          final pct = _discountCtrl.text.trim().isNotEmpty ? _discountCtrl.text.trim() : '10';
          _offerNameCtrl.text = 'Promo ${selectedGroup.name} $pct% OFF';
        }
      }
    });

    if (addedCount > 0) {
      SnackBarService.success(
        context,
        '✅ Se agregaron $addedCount producto(s) de "${selectedGroup.name}" a la oferta.',
      );
    } else {
      SnackBarService.info(
        context,
        'ℹ️ Todos los productos de "${selectedGroup.name}" (${products.length}) ya estaban en la lista.',
      );
    }
  }

  Future<void> _handleSaveOffer() async {
    final name = _offerNameCtrl.text.trim();
    if (name.isEmpty) {
      SnackBarService.warning(context, 'Por favor indicá un nombre para la oferta.');
      return;
    }

    final discount = double.tryParse(_discountCtrl.text.replaceAll(',', '.')) ?? 0;
    if (_offerType == 'percentage') {
      if (discount <= 0 || discount > 100) {
        SnackBarService.warning(context, 'El porcentaje de descuento debe estar entre 1% y 100%.');
        return;
      }
    } else {
      if (discount <= 0) {
        SnackBarService.warning(context, 'El monto fijo de descuento debe ser mayor a \$0.');
        return;
      }
    }

    if (_selectedProducts.isEmpty) {
      SnackBarService.warning(context, 'Seleccioná al menos un producto para aplicar la oferta.');
      return;
    }

    if (_offerType == 'fixed_price') {
      final invalidZero = _selectedProducts.where((p) => p.sellingPrice <= discount).toList();
      if (invalidZero.isNotEmpty) {
        SnackBarService.warning(
          context,
          'Hay ${invalidZero.length} producto(s) con precio de venta menor o igual al descuento de \$${discount.toCurrency()}. Quitalos con el botón rojo o reducí el monto.',
        );
        return;
      }
    }

    final effectiveDays = (_periodType == 'daily' || _selectedDaysOfWeek.isEmpty)
        ? null
        : _selectedDaysOfWeek.toList();

    final actionType = _editingOffer != null ? 'editar oferta' : 'crear oferta';
    await AdminPinDialog.protectAction(
      context,
      action: '$actionType "$name"',
      permissionKey: 'apply_discounts',
      onAuthorized: () async {
        if (!mounted) return;
        setState(() => _isSaving = true);
        final offerProv = Provider.of<OfferProvider>(context, listen: false);
        final pos = Provider.of<PosProvider>(context, listen: false);

        bool success = false;
        if (_editingOffer != null) {
          success = await offerProv.updateOffer(
            id: _editingOffer!.id,
            name: name,
            description: _editingOffer!.description,
            type: _offerType,
            discountPercentage: _offerType == 'percentage' ? discount : null,
            discountAmount: _offerType == 'fixed_price' ? discount : null,
            periodType: _periodType,
            daysOfWeek: effectiveDays,
            productIds: _selectedProducts.map((p) => p.id).toList(),
          );
        } else {
          success = await offerProv.createQuickOffer(
            name: name,
            type: _offerType,
            discountPercentage: _offerType == 'percentage' ? discount : null,
            discountAmount: _offerType == 'fixed_price' ? discount : null,
            periodType: _periodType,
            daysOfWeek: effectiveDays,
            productIds: _selectedProducts.map((p) => p.id).toList(),
          );
        }

        if (success && mounted) {
          pos.syncActiveOffers(offerProv.activeOffers);
          final wasEdit = _editingOffer != null;
          final isActiveToday = offerProv.activeOffers.any((o) => o.name == name);
          final discountBadge = _offerType == 'fixed_price'
              ? '\$${discount.toCurrency()} OFF'
              : '${_formatDiscountInputValue(discount, fallback: '10')}% OFF';
          _cancelEdit();
          SnackBarService.success(
            context,
            wasEdit
                ? '🏷️ Oferta "$name" actualizada con éxito.'
                : (isActiveToday
                    ? '🏷️ Oferta "$name" ($discountBadge) activada con éxito.'
                    : '🗓️ Oferta "$name" ($discountBadge) programada con éxito.'),
          );
          _tabController.animateTo(isActiveToday ? 0 : 1);
        } else if (mounted) {
          SnackBarService.error(context, offerProv.errorMessage ?? 'Error al guardar la oferta.');
        }

        if (mounted) {
          setState(() => _isSaving = false);
        }
      },
    );
  }

  List<Map<String, dynamic>> _findInvalidZeroProductsForOffer(OfferModel offer) {
    if (offer.type != 'fixed_price' || (offer.discountAmount ?? 0) <= 0) {
      return const [];
    }
    final discAmt = offer.discountAmount!;
    return offer.products.where((p) {
      final special = double.tryParse(p['pivot']?['special_price']?.toString() ?? '');
      if (special != null && special > 0) return false;
      final selling = double.tryParse(p['selling_price']?.toString() ?? '0') ?? 0.0;
      return selling <= discAmt;
    }).toList();
  }

  Future<void> _handleToggleStatus(OfferModel offer) async {
    final isPausing = offer.isActive;
    if (!isPausing) {
      final invalidZero = _findInvalidZeroProductsForOffer(offer);
      if (invalidZero.isNotEmpty) {
        SnackBarService.warning(
          context,
          'No se puede reanudar: ${invalidZero.length} producto(s) tienen precio de venta menor o igual al descuento (\$${offer.discountAmount!.toCurrency()}). Usá "Editar" para ajustarla.',
        );
        return;
      }
    }
    await AdminPinDialog.protectAction(
      context,
      action: '${isPausing ? "pausar" : "reanudar"} oferta "${offer.name}"',
      permissionKey: 'apply_discounts',
      onAuthorized: () async {
        if (!mounted) return;
        final offerProv = Provider.of<OfferProvider>(context, listen: false);
        final pos = Provider.of<PosProvider>(context, listen: false);
        final ok = await offerProv.toggleOfferStatus(offer.id);

        if (ok && mounted) {
          pos.syncActiveOffers(offerProv.activeOffers);
          SnackBarService.success(
            context,
            isPausing ? '⏸️ Oferta "${offer.name}" pausada.' : '▶️ Oferta "${offer.name}" reanudada.',
          );
        } else if (mounted) {
          SnackBarService.error(context, offerProv.errorMessage ?? 'Error al cambiar estado.');
        }
      },
    );
  }

  Future<void> _showRelaunchModal(OfferModel offer) async {
    String selectedPeriod = offer.periodType;
    bool duplicate = true;
    final invalidZeroProducts = _findInvalidZeroProductsForOffer(offer);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.rocket_launch_rounded, color: Colors.green.shade700, size: 22),
                  ),
                  const SizedBox(width: 10),
                  const Text('Relanzar Oferta', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vas a volver a activar la oferta "${offer.name}" (${offer.type == 'percentage' ? "${offer.discountPercentage?.toStringAsFixed(1) ?? "0"}% OFF" : "\$${offer.discountAmount?.toCurrency() ?? "0"} OFF"} en ${offer.products.length} productos).',
                      style: const TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                    const SizedBox(height: 14),

                    // Selector de vigencia
                    const Text('Elegí la nueva vigencia:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('☀️ Diaria (Hoy)', style: TextStyle(fontSize: 12)),
                          selected: selectedPeriod == 'daily',
                          selectedColor: Colors.purple.shade100,
                          onSelected: (val) {
                            if (val) setDialogState(() => selectedPeriod = 'daily');
                          },
                        ),
                        ChoiceChip(
                          label: const Text('📅 Semanal (7 días)', style: TextStyle(fontSize: 12)),
                          selected: selectedPeriod == 'weekly',
                          selectedColor: Colors.purple.shade100,
                          onSelected: (val) {
                            if (val) setDialogState(() => selectedPeriod = 'weekly');
                          },
                        ),
                        ChoiceChip(
                          label: const Text('📆 Mensual (30 días)', style: TextStyle(fontSize: 12)),
                          selected: selectedPeriod == 'monthly',
                          selectedColor: Colors.purple.shade100,
                          onSelected: (val) {
                            if (val) setDialogState(() => selectedPeriod = 'monthly');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Checkbox de clonar/reactivar
                    InkWell(
                      onTap: () {
                        setDialogState(() => duplicate = !duplicate);
                      },
                      child: Row(
                        children: [
                          Checkbox(
                            value: duplicate,
                            onChanged: (v) {
                              setDialogState(() => duplicate = v ?? true);
                            },
                          ),
                          const Expanded(
                            child: Text(
                              'Crear como nuevo registro histórico (recomendado para conservar auditoría)',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (invalidZeroProducts.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline_rounded, color: Colors.red.shade800, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Descuento incompatible: ${invalidZeroProducts.length} producto(s) tienen hoy un precio menor o igual a \$${offer.discountAmount?.toCurrency() ?? "0"}. Usá "Plantilla" para ajustarla antes de activar.',
                                style: TextStyle(fontSize: 11, color: Colors.red.shade900, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (offer.hasMarginWarning) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Atención: ${offer.marginWarnings.length} producto(s) tienen un precio con descuento menor al costo actual.',
                                style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                if (invalidZeroProducts.isNotEmpty)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade800),
                    onPressed: () {
                      Navigator.pop(ctx, false);
                      _useOfferAsTemplate(offer);
                    },
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    label: const Text('Ajustar como Plantilla'),
                  )
                else
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7B1FA2)),
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.bolt_rounded, size: 18),
                    label: const Text('Relanzar Ahora'),
                  ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;

    await AdminPinDialog.protectAction(
      context,
      action: 'relanzar oferta "${offer.name}"',
      permissionKey: 'apply_discounts',
      onAuthorized: () async {
        if (!mounted) return;
        final offerProv = Provider.of<OfferProvider>(context, listen: false);
        final pos = Provider.of<PosProvider>(context, listen: false);

        final res = await offerProv.relaunchOffer(
          id: offer.id,
          periodType: selectedPeriod,
          duplicate: duplicate,
        );

        if (res != null && mounted) {
          pos.syncActiveOffers(offerProv.activeOffers);
          SnackBarService.success(context, '🚀 Oferta "${offer.name}" relanzada con éxito.');
          _tabController.animateTo(0);
        } else if (mounted) {
          SnackBarService.error(context, offerProv.errorMessage ?? 'Error al relanzar la oferta.');
        }
      },
    );
  }

  Future<void> _handleDeleteOffer(OfferModel offer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eliminar Oferta'),
        content: Text('¿Deseas dar de baja definitivamente la oferta "${offer.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await AdminPinDialog.protectAction(
      context,
      action: 'eliminar oferta "${offer.name}"',
      permissionKey: 'apply_discounts',
      onAuthorized: () async {
        if (!mounted) return;
        final offerProv = Provider.of<OfferProvider>(context, listen: false);
        final pos = Provider.of<PosProvider>(context, listen: false);
        final success = await offerProv.deleteOffer(offer.id);

        if (success && mounted) {
          pos.syncActiveOffers(offerProv.activeOffers);
          SnackBarService.success(context, 'Oferta eliminada.');
        } else if (mounted) {
          SnackBarService.error(context, offerProv.errorMessage ?? 'Error al eliminar la oferta.');
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        width: 780,
        height: 600,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Cabecera
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B1FA2).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.local_offer_rounded, color: Color(0xFF7B1FA2), size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ofertas y Promociones',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Gestión integral, historial, plantillas y relanzamiento ágil de ofertas',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
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
            const SizedBox(height: 14),

            // TabBar con 3 pestañas
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4),
                  ],
                ),
                labelColor: const Color(0xFF7B1FA2),
                unselectedLabelColor: Colors.grey.shade600,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                tabs: [
                  const Tab(text: '🏷️ Ofertas Activas Hoy'),
                  const Tab(text: '📜 Historial y Catálogo'),
                  Tab(text: _editingOffer != null ? '✏️ Editar Oferta' : '✨ Armar Nueva Oferta'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // TabBarView
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildActiveOffersTab(),
                  _buildHistoryOffersTab(),
                  _buildCreateOfferTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveOffersTab() {
    return Consumer<OfferProvider>(
      builder: (context, offerProv, _) {
        final list = offerProv.activeOffers.where((o) => o.isCurrentlyActive).toList();

        if (offerProv.isLoadingActive && list.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (list.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.local_offer_outlined, size: 50, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                const Text(
                  'No hay ofertas activas para hoy',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Podés armar una nueva oferta o relanzar una anterior desde la pestaña "Historial".',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => _tabController.animateTo(1),
                      icon: const Icon(Icons.history_rounded, size: 18),
                      label: const Text('Ver Historial'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7B1FA2)),
                      onPressed: () => _tabController.animateTo(2),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Crear Oferta'),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (ctx, index) {
            final offer = list[index];
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.shade50.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.purple.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            offer.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              offer.periodLabel,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purple.shade900),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.green.shade600,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              offer.type == 'percentage'
                                  ? '-${offer.discountPercentage?.toStringAsFixed(1) ?? "0"}%'
                                  : '-\$${offer.discountAmount?.toCurrency() ?? "0"}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.pause_circle_outline, size: 20, color: Colors.orange),
                            tooltip: 'Pausar oferta',
                            onPressed: () => _handleToggleStatus(offer),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20, color: Color(0xFF1976D2)),
                            tooltip: 'Editar oferta',
                            onPressed: () => _startEditOffer(offer),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                            tooltip: 'Eliminar oferta',
                            onPressed: () => _handleDeleteOffer(offer),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Vigencia: ${_formatDate(offer.startDate)} al ${_formatDate(offer.endDate)}',
                    style: TextStyle(fontSize: 11, color: Colors.purple.shade800),
                  ),
                  if (offer.hasMarginWarning) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 15, color: Colors.amber.shade900),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Alerta de margen: ${offer.marginWarnings.length} producto(s) quedan por debajo de su costo actual.',
                              style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        'Productos incluidos (${offer.products.length}):',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.purple.shade900),
                      ),
                      if (offer.products.length > 3) ...[
                        const SizedBox(width: 8),
                        InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () => _showOfferProductsModal(offer),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Text(
                              '🔍 Ver listado completo',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.purple.shade700,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  _buildCompactProductChips(offer, showPrices: true, maxVisible: 3),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHistoryOffersTab() {
    return Consumer<OfferProvider>(
      builder: (context, offerProv, _) {
        final list = offerProv.allOffers;

        return Column(
          children: [
            // Barra de filtros y buscador
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _historySearchCtrl,
                    onChanged: _onHistorySearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Buscar oferta o producto...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _historySearchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _historySearchCtrl.clear();
                                _onHistorySearchChanged('');
                              },
                            )
                          : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Wrap(
                  spacing: 6,
                  children: [
                    _buildHistoryFilterChip('all', 'Todas'),
                    _buildHistoryFilterChip('expired', '🔴 Vencidas'),
                    _buildHistoryFilterChip('paused', '⏸️ Pausadas'),
                    _buildHistoryFilterChip('active', '🟢 Activas'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Lista de ofertas del historial
            Expanded(
              child: offerProv.isLoadingHistory && list.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history_toggle_off_rounded, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 10),
                              const Text('No se encontraron ofertas en el historial',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                              const SizedBox(height: 4),
                              const Text('Probá cambiando el filtro o la búsqueda.',
                                  style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (ctx, index) {
                            final offer = list[index];
                            return _buildHistoryOfferCard(offer);
                          },
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHistoryFilterChip(String value, String label) {
    final isSelected = _historyFilter == value;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      selectedColor: Colors.purple.shade100,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: (selected) {
        if (selected) {
          _setHistoryFilter(value);
        }
      },
    );
  }

  Widget _buildHistoryOfferCard(OfferModel offer) {
    final isCurrentlyActive = offer.isCurrentlyActive;
    final isPaused = offer.isPaused;
    final isExpired = offer.isExpired;

    Color badgeBg = Colors.grey.shade200;
    Color badgeText = Colors.grey.shade800;

    if (isCurrentlyActive) {
      badgeBg = Colors.green.shade50;
      badgeText = Colors.green.shade800;
    } else if (isPaused) {
      badgeBg = Colors.orange.shade50;
      badgeText = Colors.orange.shade900;
    } else if (isExpired) {
      badgeBg = Colors.red.shade50;
      badgeText = Colors.red.shade800;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fila Superior
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    offer.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      offer.statusLabel,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeText),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      offer.periodLabel,
                      style: TextStyle(fontSize: 11, color: Colors.purple.shade900),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.shade600,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  offer.type == 'percentage'
                      ? '-${offer.discountPercentage?.toStringAsFixed(1) ?? "0"}%'
                      : '-\$${offer.discountAmount?.toCurrency() ?? "0"}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Fechas de vigencia
          Text(
            'Vigencia: ${_formatDate(offer.startDate)} al ${_formatDate(offer.endDate)}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),

          if (offer.hasMarginWarning) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 14, color: Colors.amber.shade900),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Alerta de margen: ${offer.marginWarnings.length} producto(s) quedan por debajo de su costo actual.',
                      style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 8),

          // Productos y Acciones
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _buildCompactProductChips(offer, showPrices: false, maxVisible: 3),
              ),
              const SizedBox(width: 8),

              // Botones de acción del historial
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Botón Relanzar
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _showRelaunchModal(offer),
                    icon: const Icon(Icons.rocket_launch_rounded, size: 16),
                    label: const Text('Relanzar', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 6),

                  // Botón Plantilla
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _useOfferAsTemplate(offer),
                    icon: const Icon(Icons.copy_rounded, size: 15),
                    label: const Text('Plantilla', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 4),

                  // Pausar / Reanudar (basado en offer.isActive real, no en si hoy toca su día de semana)
                  if (!isExpired)
                    IconButton(
                      icon: Icon(
                        !isPaused ? Icons.pause_circle_outline : Icons.play_circle_outline,
                        size: 20,
                        color: !isPaused ? Colors.orange : Colors.green.shade700,
                      ),
                      tooltip: !isPaused ? 'Pausar oferta' : 'Reanudar oferta',
                      onPressed: () => _handleToggleStatus(offer),
                    ),

                  // Eliminar
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                    tooltip: 'Eliminar oferta',
                    onPressed: () => _handleDeleteOffer(offer),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _computePreviewDiscountedPrice(double sellingPrice, double rawInputValue) {
    if (rawInputValue <= 0) return sellingPrice;
    if (_offerType == 'fixed_price') {
      final res = (sellingPrice - rawInputValue).clamp(0.0, double.infinity);
      return (res * 100).roundToDouble() / 100.0;
    }
    if (rawInputValue > 100) return sellingPrice;
    return (sellingPrice * (1.0 - (rawInputValue / 100.0)) * 100).roundToDouble() / 100.0;
  }

  Widget _buildDiscountTypeOption({
    required String typeValue,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _offerType == typeValue;
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: () {
        if (_offerType == typeValue) return;
        setState(() {
          _offerType = typeValue;
          final currentNum = double.tryParse(_discountCtrl.text.replaceAll(',', '.')) ?? 0;
          if (typeValue == 'fixed_price' && (currentNum <= 0 || currentNum <= 100)) {
            _discountCtrl.text = '1000';
          } else if (typeValue == 'percentage' && (currentNum <= 0 || currentNum > 100)) {
            _discountCtrl.text = '10';
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF7B1FA2) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.white : Colors.grey.shade700,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? Colors.white : Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateOfferTab() {
    final currentVal = double.tryParse(_discountCtrl.text.replaceAll(',', '.')) ?? 0.0;
    final isValidInput = _offerType == 'fixed_price'
        ? currentVal > 0
        : (currentVal > 0 && currentVal <= 100);

    // Candado 1: En Monto Fijo ($), productos cuyo precio de venta <= descuento (quedarían en $0)
    final invalidZeroProducts = (_offerType == 'fixed_price' && isValidInput)
        ? _selectedProducts.where((p) => p.sellingPrice <= currentVal).toList()
        : <Product>[];
    final invalidZeroIdsSet = invalidZeroProducts.map((e) => e.id).toSet();

    // Candado 2: Escudo de margen (quedan > $0 pero por debajo del costo)
    final riskyProducts = _selectedProducts.where((p) {
      if (!isValidInput || p.costPrice <= 0 || p.sellingPrice <= 0) {
        return false;
      }
      if (invalidZeroIdsSet.contains(p.id)) {
        return false; // Ya está reportado en el bloqueo rojo de $0
      }
      final discounted = _computePreviewDiscountedPrice(p.sellingPrice, currentVal);
      return discounted < p.costPrice;
    }).toList();
    final riskyIdsSet = riskyProducts.map((e) => e.id).toSet();
    final hasSuppliersFeature = Provider.of<SettingsProvider>(context, listen: false).features.suppliers;
    final discountSummaryText = _offerType == 'fixed_price'
        ? '\$${currentVal.toCurrency()} OFF'
        : '${currentVal.toStringAsFixed(1)}% OFF';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_editingOffer != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit_note_rounded, color: Colors.blue.shade800, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Modificando oferta: ${_editingOffer!.name}',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue.shade900),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _cancelEdit,
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Cancelar edición'),
                  ),
                ],
              ),
            ),
          TextField(
            controller: _offerNameCtrl,
            decoration: InputDecoration(
              labelText: 'Nombre de la Oferta (ej: Promo Coca Cola 15% OFF)',
              prefixIcon: const Icon(Icons.local_offer_outlined, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),

          // Selector de Período / Vigencia
          const Text('Vigencia de la Oferta:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          Row(
            children: [
              _buildPeriodChip('daily', '☀️ Diaria (Hoy)'),
              const SizedBox(width: 8),
              _buildPeriodChip('weekly', '📅 Semanal (7 días)'),
              const SizedBox(width: 8),
              _buildPeriodChip('monthly', '📆 Mensual (30 días)'),
            ],
          ),

          // Selector de Días de la Semana (para ofertas Semanales o Mensuales)
          if (_periodType != 'daily') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.purple.shade50.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.event_repeat_rounded, size: 15, color: Colors.purple.shade700),
                      const SizedBox(width: 6),
                      Text(
                        'Días aplicables:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.purple.shade900),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _selectedDaysOfWeek.isEmpty
                              ? 'Todos los días (sin restricción)'
                              : 'Solo ${_selectedDaysOfWeek.length} día(s) seleccionado(s)',
                          style: TextStyle(fontSize: 11, color: Colors.purple.shade700),
                        ),
                      ),
                      if (_selectedDaysOfWeek.isNotEmpty)
                        InkWell(
                          onTap: () => setState(() => _selectedDaysOfWeek.clear()),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Text(
                              'Marcar todos',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.purple.shade800,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _weekDayOptions.map((entry) {
                      final isSelected = _selectedDaysOfWeek.contains(entry.key);
                      return FilterChip(
                        label: Text(
                          entry.value,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.purple.shade900 : Colors.grey.shade800,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: Colors.purple.shade100,
                        checkmarkColor: Colors.purple.shade800,
                        backgroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _selectedDaysOfWeek.add(entry.key);
                            } else {
                              _selectedDaysOfWeek.remove(entry.key);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Selector de Tipo (% Porcentaje vs $ Monto Fijo) + Valor + Cargar Carrito
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDiscountTypeOption(
                      typeValue: 'percentage',
                      label: 'Porcentaje',
                      icon: Icons.percent_rounded,
                    ),
                    const SizedBox(width: 2),
                    _buildDiscountTypeOption(
                      typeValue: 'fixed_price',
                      label: 'Monto Fijo',
                      icon: Icons.attach_money_rounded,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _discountCtrl,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: _offerType == 'fixed_price'
                        ? 'Monto a descontar'
                        : 'Porcentaje de descuento',
                    prefixText: _offerType == 'fixed_price' ? '\$ ' : null,
                    suffixText: _offerType == 'percentage' ? '%' : 'OFF',
                    prefixIcon: const Icon(Icons.discount_outlined, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple.shade50,
                  foregroundColor: const Color(0xFF7B1FA2),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.shopping_cart_checkout_rounded, size: 18),
                label: const Text('Cargar Carrito'),
                onPressed: () {
                  final pos = Provider.of<PosProvider>(context, listen: false);
                  setState(() {
                    for (final item in pos.cart) {
                      if (!_selectedProducts.any((p) => p.id == item.product.id)) {
                        _selectedProducts.add(item.product);
                      }
                    }
                  });
                  SnackBarService.info(context, '${pos.cart.length} productos del carrito cargados.');
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Cabecera de Productos + Botones de Carga Masiva por Categoría / Marca / Proveedor
          Row(
            children: [
              Text(
                'Productos en la Oferta (${_selectedProducts.length}):',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              if (_isLoadingGroup) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
              const Spacer(),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _buildBulkGroupButton(
                    icon: Icons.category_outlined,
                    label: '+ Categoría',
                    onTap: _isLoadingGroup ? null : () => _showGroupPickerAndAddProducts(groupType: 'category'),
                  ),
                  _buildBulkGroupButton(
                    icon: Icons.sell_outlined,
                    label: '+ Marca',
                    onTap: _isLoadingGroup ? null : () => _showGroupPickerAndAddProducts(groupType: 'brand'),
                  ),
                  if (hasSuppliersFeature)
                    _buildBulkGroupButton(
                      icon: Icons.local_shipping_outlined,
                      label: '+ Proveedor',
                      onTap: _isLoadingGroup ? null : () => _showGroupPickerAndAddProducts(groupType: 'supplier'),
                    ),
                  if (_selectedProducts.isNotEmpty)
                     InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => setState(() => _selectedProducts.clear()),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.delete_sweep_outlined, size: 14, color: Colors.red.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'Vaciar',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade700),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Autocomplete<Product>(
            displayStringForOption: (Product p) => '${p.name} (\$${p.sellingPrice.toCurrency()})',
            optionsBuilder: (TextEditingValue textValue) => _searchCatalogProducts(textValue.text),
            onSelected: (Product p) {
              setState(() {
                if (!_selectedProducts.any((sp) => sp.id == p.id)) {
                  _selectedProducts.add(p);
                }
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _autoCompleteCtrl?.clear();
              });
            },
            fieldViewBuilder: (ctx, ctrl, focusNode, onFieldSubmitted) {
              _autoCompleteCtrl = ctrl;
              return TextField(
                controller: ctrl,
                focusNode: focusNode,
                onSubmitted: (value) {
                  ctrl.clear();
                },
                decoration: InputDecoration(
                  hintText: 'Buscar y agregar productos individuales del catálogo...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              );
            },
          ),
          const SizedBox(height: 8),

          // Chips de productos seleccionados (con scroll acotado para cargas masivas)
          if (_selectedProducts.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  'No hay productos agregados. Usá "+ Categoría", "+ Marca", "Cargar Carrito" o buscá arriba.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 135),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _selectedProducts.map((p) {
                    final discounted = isValidInput
                        ? _computePreviewDiscountedPrice(p.sellingPrice, currentVal)
                        : p.sellingPrice;
                    final priceLabel = isValidInput
                        ? '\$${p.sellingPrice.toCurrency()} → \$${discounted.toCurrency()}'
                        : '\$${p.sellingPrice.toCurrency()}';
                    final isInvalidZero = invalidZeroIdsSet.contains(p.id);
                    final isRisky = riskyIdsSet.contains(p.id);
                    final displayName = p.name.length > 32 ? '${p.name.substring(0, 32)}…' : p.name;
                    return Tooltip(
                      message: '${p.name} ($priceLabel)',
                      child: Chip(
                        backgroundColor: isInvalidZero
                            ? Colors.red.shade50
                            : (isRisky ? Colors.amber.shade50 : Colors.white),
                        side: BorderSide(
                          color: isInvalidZero
                              ? Colors.red.shade400
                              : (isRisky ? Colors.amber.shade400 : Colors.grey.shade300),
                        ),
                        avatar: isInvalidZero
                            ? Icon(Icons.block_rounded, size: 14, color: Colors.red.shade800)
                            : (isRisky
                                ? Icon(Icons.warning_amber_rounded, size: 14, color: Colors.amber.shade900)
                                : null),
                        label: Text(
                          '$displayName ($priceLabel)',
                          style: TextStyle(
                            fontSize: 11,
                            color: isInvalidZero
                                ? Colors.red.shade900
                                : (isRisky ? Colors.amber.shade900 : Colors.black87),
                            fontWeight: (isInvalidZero || isRisky) ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        deleteIcon: const Icon(Icons.close, size: 15),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onDeleted: () {
                          setState(() {
                            _selectedProducts.removeWhere((item) => item.id == p.id);
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

          if (invalidZeroProducts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: Colors.red.shade800, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Descuento incompatible: Con \$${currentVal.toCurrency()} OFF, ${invalidZeroProducts.length} producto(s) quedan en \$0 (${invalidZeroProducts.map((e) => e.name).take(2).join(", ")}${invalidZeroProducts.length > 2 ? "..." : ""}).',
                      style: TextStyle(fontSize: 11, color: Colors.red.shade900, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade900,
                      backgroundColor: Colors.white,
                      side: BorderSide(color: Colors.red.shade700),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.remove_circle_outline, size: 15),
                    label: Text(
                      'Quitar estos ${invalidZeroProducts.length}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      final count = invalidZeroIdsSet.length;
                      setState(() {
                        _selectedProducts.removeWhere((p) => invalidZeroIdsSet.contains(p.id));
                      });
                      SnackBarService.info(
                        context,
                        '🧹 Se quitaron $count producto(s) cuyo precio era menor o igual al descuento.',
                      );
                    },
                  ),
                ],
              ),
            ),
          ],

          if (riskyProducts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Alerta de margen: Con $discountSummaryText, ${riskyProducts.length} producto(s) quedan bajo su costo (${riskyProducts.map((e) => e.name).take(2).join(", ")}${riskyProducts.length > 2 ? "..." : ""}).',
                      style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.amber.shade900,
                      backgroundColor: Colors.white,
                      side: BorderSide(color: Colors.amber.shade700),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.remove_circle_outline, size: 15),
                    label: Text(
                      'Quitar estos ${riskyProducts.length}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      final count = riskyIdsSet.length;
                      setState(() {
                        _selectedProducts.removeWhere((p) => riskyIdsSet.contains(p.id));
                      });
                      SnackBarService.info(
                        context,
                        '🛡️ Se quitaron $count producto(s) que quedaban por debajo del costo.',
                      );
                    },
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7B1FA2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _isSaving ? null : _handleSaveOffer,
              icon: _isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Icon(_editingOffer != null ? Icons.save_rounded : Icons.bolt_rounded, size: 22),
              label: Text(
                _isSaving
                    ? 'Guardando...'
                    : (_editingOffer != null ? 'Guardar Cambios de la Oferta' : 'Activar Oferta Inmediatamente'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulkGroupButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.purple.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.purple.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF7B1FA2)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF7B1FA2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactProductChips(
    OfferModel offer, {
    required bool showPrices,
    int maxVisible = 3,
  }) {
    final total = offer.products.length;
    final visibleProducts = offer.products.take(maxVisible).toList();
    final remaining = total - visibleProducts.length;

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...visibleProducts.map((p) {
          final rawName = p['name']?.toString() ?? 'Producto';
          final shortName = rawName.length > 34 ? '${rawName.substring(0, 34)}…' : rawName;
          final basePrice = double.tryParse(p['selling_price']?.toString() ?? '0') ?? 0.0;
          final pId = (p['id'] as num?)?.toInt();
          final discounted = basePrice > 0
              ? offer.calculateDiscountedPrice(basePrice, productId: pId)
              : 0.0;
          final labelText = (showPrices && basePrice > 0)
              ? '$shortName (\$${basePrice.toCurrency()} → \$${discounted.toCurrency()})'
              : shortName;

          return Tooltip(
            message: (basePrice > 0)
                ? '$rawName (\$${basePrice.toCurrency()} → \$${discounted.toCurrency()})'
                : rawName,
            child: Chip(
              label: Text(
                labelText,
                style: TextStyle(fontSize: showPrices ? 11 : 10),
              ),
              backgroundColor: showPrices ? Colors.white : Colors.grey.shade100,
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          );
        }),
        if (remaining > 0)
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _showOfferProductsModal(offer),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.purple.shade100,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.purple.shade300),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_rounded, size: 13, color: Colors.purple.shade900),
                  const SizedBox(width: 4),
                  Text(
                    '+$remaining más (Ver los $total)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple.shade900,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _showOfferProductsModal(OfferModel offer) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        String search = '';
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final q = search.trim().toLowerCase();
            final filtered = q.isEmpty
                ? offer.products
                : offer.products.where((p) {
                    final pName = (p['name'] ?? '').toString().toLowerCase();
                    final pCode = (p['internal_code'] ?? '').toString().toLowerCase();
                    final pBar = (p['barcode'] ?? '').toString().toLowerCase();
                    return pName.contains(q) || pCode.contains(q) || pBar.contains(q);
                  }).toList();

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.local_offer_rounded, color: Color(0xFF7B1FA2), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          offer.name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${offer.products.length} producto(s) incluidos • ${offer.periodLabel}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade600,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      offer.type == 'percentage'
                          ? '-${offer.discountPercentage?.toStringAsFixed(1) ?? "0"}%'
                          : '-\$${offer.discountAmount?.toCurrency() ?? "0"}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                  ),
                ],
              ),
              content: SizedBox(
                width: 560,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      onChanged: (v) => setDialogState(() => search = v),
                      decoration: InputDecoration(
                        hintText: 'Buscar producto por nombre o código dentro de la oferta...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                'No se encontraron productos para "$search"',
                                style: const TextStyle(color: Colors.grey, fontSize: 13),
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                              itemBuilder: (_, idx) {
                                final p = filtered[idx];
                                final name = p['name']?.toString() ?? 'Producto';
                                final code = (p['internal_code'] ?? p['barcode'] ?? '').toString();
                                final basePrice = double.tryParse(p['selling_price']?.toString() ?? '0') ?? 0.0;
                                final costPrice = double.tryParse(p['cost_price']?.toString() ?? '0') ?? 0.0;
                                final pId = (p['id'] as num?)?.toInt();
                                final discounted = basePrice > 0
                                    ? offer.calculateDiscountedPrice(basePrice, productId: pId)
                                    : 0.0;
                                final isBelowCost = costPrice > 0 && discounted > 0 && discounted < costPrice;

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                            ),
                                            if (code.isNotEmpty || isBelowCost)
                                              Row(
                                                children: [
                                                  if (code.isNotEmpty)
                                                    Text(
                                                      'Cód: $code',
                                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                                    ),
                                                  if (isBelowCost) ...[
                                                    if (code.isNotEmpty) const SizedBox(width: 8),
                                                    Text(
                                                      '⚠️ Bajo costo (\$${costPrice.toCurrency()})',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.amber.shade900,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (basePrice > 0) ...[
                                        const SizedBox(width: 10),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '\$${basePrice.toCurrency()}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade500,
                                                decoration: TextDecoration.lineThrough,
                                              ),
                                            ),
                                            Text(
                                              '\$${discounted.toCurrency()}',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPeriodChip(String value, String label) {
    final isSelected = _periodType == value;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      selectedColor: Colors.purple.shade100,
      onSelected: (selected) {
        if (selected) {
          setState(() => _periodType = value);
        }
      },
    );
  }
}
