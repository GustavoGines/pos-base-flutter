import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pos_provider.dart';
import 'package:frontend_desktop/features/offers/presentation/providers/offer_provider.dart';
import 'package:frontend_desktop/features/offers/data/models/offer_model.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
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

  String _periodType = 'daily'; // 'daily', 'weekly', 'monthly'
  String _historyFilter = 'all'; // 'all', 'expired', 'paused', 'active'
  final List<Product> _selectedProducts = [];
  bool _isSaving = false;
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
      offerProv.loadActiveOffers();
      offerProv.loadAllOffers(status: _historyFilter);
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

  void _startEditOffer(OfferModel offer) {
    setState(() {
      _editingOffer = offer;
      _offerNameCtrl.text = offer.name;
      _discountCtrl.text = offer.discountPercentage?.toString() ?? '10';
      _periodType = offer.periodType;
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
      _discountCtrl.text = offer.discountPercentage?.toString() ?? '10';
      _periodType = offer.periodType;
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
    SnackBarService.info(context, '📋 Plantilla cargada. Ajustá productos o porcentajes antes de activar.');
  }

  void _cancelEdit() {
    setState(() {
      _editingOffer = null;
      _offerNameCtrl.clear();
      _discountCtrl.text = '10';
      _periodType = 'daily';
      _selectedProducts.clear();
      final pos = Provider.of<PosProvider>(context, listen: false);
      for (final item in pos.cart) {
        if (!_selectedProducts.any((p) => p.id == item.product.id)) {
          _selectedProducts.add(item.product);
        }
      }
    });
  }

  Future<void> _handleSaveOffer() async {
    final name = _offerNameCtrl.text.trim();
    if (name.isEmpty) {
      SnackBarService.warning(context, 'Por favor indicá un nombre para la oferta.');
      return;
    }

    final discount = double.tryParse(_discountCtrl.text.replaceAll(',', '.')) ?? 0;
    if (discount <= 0 || discount > 100) {
      SnackBarService.warning(context, 'El porcentaje de descuento debe estar entre 1% y 100%.');
      return;
    }

    if (_selectedProducts.isEmpty) {
      SnackBarService.warning(context, 'Seleccioná al menos un producto para aplicar la oferta.');
      return;
    }

    final actionType = _editingOffer != null ? 'editar oferta' : 'crear oferta';
    final authorized = await AdminPinDialog.verify(
      context,
      action: '$actionType "$name"',
      permissionKey: 'apply_discounts',
    );
    if (!authorized) return;

    setState(() => _isSaving = true);
    final offerProv = Provider.of<OfferProvider>(context, listen: false);
    final pos = Provider.of<PosProvider>(context, listen: false);

    bool success = false;
    if (_editingOffer != null) {
      success = await offerProv.updateOffer(
        id: _editingOffer!.id,
        name: name,
        type: 'percentage',
        discountPercentage: discount,
        periodType: _periodType,
        productIds: _selectedProducts.map((p) => p.id).toList(),
      );
    } else {
      success = await offerProv.createQuickOffer(
        name: name,
        type: 'percentage',
        discountPercentage: discount,
        periodType: _periodType,
        productIds: _selectedProducts.map((p) => p.id).toList(),
      );
    }

    if (success && mounted) {
      pos.syncActiveOffers(offerProv.activeOffers);
      final wasEdit = _editingOffer != null;
      _cancelEdit();
      SnackBarService.success(
        context,
        wasEdit ? '🏷️ Oferta "$name" actualizada con éxito.' : '🏷️ Oferta "$name" ($discount% OFF) activada con éxito.',
      );
      _tabController.animateTo(0);
    } else if (mounted) {
      SnackBarService.error(context, offerProv.errorMessage ?? 'Error al guardar la oferta.');
    }

    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _handleToggleStatus(OfferModel offer) async {
    final isPausing = offer.isCurrentlyActive;
    final authorized = await AdminPinDialog.verify(
      context,
      action: '${isPausing ? "pausar" : "reanudar"} oferta "${offer.name}"',
      permissionKey: 'apply_discounts',
    );
    if (!authorized) return;

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
  }

  Future<void> _showRelaunchModal(OfferModel offer) async {
    String selectedPeriod = offer.periodType;
    bool duplicate = true;

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
                      'Vas a volver a activar la oferta "${offer.name}" (${offer.discountPercentage?.toStringAsFixed(1) ?? "0"}% OFF en ${offer.products.length} productos).',
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

    if (confirmed != true) return;

    final authorized = await AdminPinDialog.verify(
      context,
      action: 'relanzar oferta "${offer.name}"',
      permissionKey: 'apply_discounts',
    );
    if (!authorized) return;

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
    if (confirm != true) return;

    final authorized = await AdminPinDialog.verify(
      context,
      action: 'eliminar oferta "${offer.name}"',
      permissionKey: 'apply_discounts',
    );
    if (!authorized) return;

    final offerProv = Provider.of<OfferProvider>(context, listen: false);
    final pos = Provider.of<PosProvider>(context, listen: false);
    final success = await offerProv.deleteOffer(offer.id);

    if (success && mounted) {
      pos.syncActiveOffers(offerProv.activeOffers);
      SnackBarService.success(context, 'Oferta eliminada.');
    } else if (mounted) {
      SnackBarService.error(context, offerProv.errorMessage ?? 'Error al eliminar la oferta.');
    }
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
        if (offerProv.isLoading && offerProv.activeOffers.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final list = offerProv.activeOffers;

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
                  const SizedBox(height: 6),
                  Text(
                    'Productos incluidos (${offer.products.length}):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.purple.shade900),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: offer.products.map((p) {
                      final name = p['name']?.toString() ?? 'Producto';
                      return Chip(
                        label: Text(name, style: const TextStyle(fontSize: 11)),
                        backgroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
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
              child: offerProv.isLoading && list.isEmpty
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
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: offer.products.take(4).map((p) {
                    final name = p['name']?.toString() ?? 'Producto';
                    return Chip(
                      label: Text(name, style: const TextStyle(fontSize: 10)),
                      backgroundColor: Colors.grey.shade100,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList()
                    ..addAll(
                      offer.products.length > 4
                          ? [
                              Chip(
                                label: Text('+${offer.products.length - 4}',
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                backgroundColor: Colors.purple.shade50,
                                padding: EdgeInsets.zero,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                            ]
                          : [],
                    ),
                ),
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

                  // Pausar / Reanudar
                  IconButton(
                    icon: Icon(
                      isCurrentlyActive ? Icons.pause_circle_outline : Icons.play_circle_outline,
                      size: 20,
                      color: isCurrentlyActive ? Colors.orange : Colors.green.shade700,
                    ),
                    tooltip: isCurrentlyActive ? 'Pausar oferta' : 'Reanudar oferta',
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

  Widget _buildCreateOfferTab() {
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
          const SizedBox(height: 14),

          // Descuento
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _discountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Porcentaje de Descuento (%)',
                    suffixText: '%',
                    prefixIcon: const Icon(Icons.percent_rounded, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
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
          const SizedBox(height: 14),

          // Búsqueda de productos adicionales
          const Text('Productos en la Oferta:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
                  hintText: 'Buscar y agregar productos del catálogo...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              );
            },
          ),
          const SizedBox(height: 10),

          // Chips de productos seleccionados
          if (_selectedProducts.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text('No hay productos agregados. Tocá "Cargar Carrito" o buscá arriba.',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _selectedProducts.map((p) {
                return Chip(
                  label: Text('${p.name} (\$${p.sellingPrice.toCurrency()})', style: const TextStyle(fontSize: 11)),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setState(() {
                      _selectedProducts.removeWhere((item) => item.id == p.id);
                    });
                  },
                );
              }).toList(),
            ),

          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 46,
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
                    : (_editingOffer != null ? '💾 Guardar Cambios de la Oferta' : '🚀 Activar Oferta Inmediatamente'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
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
