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

  String _periodType = 'daily'; // 'daily', 'weekly', 'monthly'
  final List<Product> _selectedProducts = [];
  bool _isSaving = false;
  int _searchSeq = 0; // Token de debounce del buscador de productos
  OfferModel? _editingOffer;
  TextEditingController? _autoCompleteCtrl;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

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
      Provider.of<OfferProvider>(context, listen: false).loadActiveOffers();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _offerNameCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  /// Busca en el servidor (todo el catálogo) con debounce. Descarta resultados obsoletos si el
  /// usuario siguió escribiendo.
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

  void _startEditOffer(OfferModel offer) {
    setState(() {
      _editingOffer = offer;
      _offerNameCtrl.text = offer.name;
      _discountCtrl.text = offer.discountPercentage?.toString() ?? (offer.discountPercentage?.toString() ?? '10');
      _periodType = offer.periodType;
      _selectedProducts.clear();
      for (final pMap in offer.products) {
        final id = (pMap['id'] as num?)?.toInt() ?? 0;
        final name = pMap['name']?.toString() ?? 'Producto';
        final sellingPrice = double.tryParse(pMap['selling_price']?.toString() ?? '0') ?? 0.0;
        final internalCode = pMap['internal_code']?.toString() ?? '';
        final barcode = pMap['barcode']?.toString();
        _selectedProducts.add(Product(
          id: id,
          name: name,
          sellingPrice: sellingPrice,
          internalCode: internalCode,
          barcode: barcode,
          costPrice: 0,
          stock: 0,
          active: true,
          isSoldByWeight: false,
        ));
      }
    });
    _tabController.animateTo(1);
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        width: 650,
        height: 560,
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
                        'Crear ofertas diarias, semanales o mensuales para la terminal',
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

            // TabBar
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
                  'Podés armar una oferta rápida en la pestaña "Armar Nueva Oferta".',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: () => _tabController.animateTo(1),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Crear Oferta Ahora'),
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
                            icon: const Icon(Icons.edit_outlined, size: 20, color: Color(0xFF1976D2)),
                            tooltip: 'Editar oferta',
                            onPressed: () => _startEditOffer(offer),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                            tooltip: 'Eliminar oferta',
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Eliminar Oferta'),
                                  content: Text('¿Deseas dar de baja la oferta "${offer.name}"?'),
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
                              if (confirm == true) {
                                final authorized = await AdminPinDialog.verify(
                                  context,
                                  action: 'eliminar oferta "${offer.name}"',
                                  permissionKey: 'apply_discounts',
                                );
                                if (!authorized) return;

                                final success = await offerProv.deleteOffer(offer.id);
                                if (success && mounted) {
                                  Provider.of<PosProvider>(context, listen: false).syncActiveOffers(offerProv.activeOffers);
                                  SnackBarService.success(context, 'Oferta eliminada.');
                                } else if (mounted) {
                                  SnackBarService.error(context, offerProv.errorMessage ?? 'Error al eliminar la oferta.');
                                }
                              }
                            },
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
