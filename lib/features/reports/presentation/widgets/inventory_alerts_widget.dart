import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/compact_date_range_picker_dialog.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/expired_batches_sweep_dialog.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/product_batches_dialog.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/production_orders_dialog.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/stock_adjustment_dialog.dart';
import 'package:frontend_desktop/features/offers/presentation/providers/offer_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:frontend_desktop/core/utils/image_url_resolver.dart';
import 'package:frontend_desktop/core/constants/app_permissions.dart';
import 'package:frontend_desktop/features/auth/presentation/widgets/admin_pin_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

/// Widget autónomo de alertas semafóricas de stock.
/// Se monta en la GlobalAppBar y despliega un OverlayPortal no bloqueante
/// con la lista de productos en riesgo.
class InventoryAlertsWidget extends StatefulWidget {
  const InventoryAlertsWidget({super.key});

  @override
  State<InventoryAlertsWidget> createState() => _InventoryAlertsWidgetState();
}

class _InventoryAlertsWidgetState extends State<InventoryAlertsWidget> {
  final _overlayController = OverlayPortalController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InventoryAlertsProvider>().fetchAlerts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _clearSearch() {
    if (_searchController.text.isNotEmpty || _searchQuery.isNotEmpty) {
      _searchController.clear();
      setState(() {
        _searchQuery = '';
      });
    }
  }

  void _hideOverlay() {
    _clearSearch();
    _overlayController.hide();
  }

  void _toggleOverlay() {
    final willShow = !_overlayController.isShowing;
    if (!willShow) {
      _clearSearch();
    }
    _overlayController.toggle();
    if (willShow && mounted) {
      context.read<InventoryAlertsProvider>().fetchAlerts();
    }
  }

  static String _normalizeForSearch(String input) {
    return input
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u');
  }

  bool _matchesSearch(dynamic alert, List<String> queryTokens, CatalogProvider? catalogProvider) {
    if (queryTokens.isEmpty) return true;
    final name = (alert['product_name'] ?? alert['name'] ?? '').toString();
    final code = (alert['internal_code'] ?? '').toString();
    String barcode = (alert['barcode'] ?? '').toString();
    final category = (alert['category'] ?? '').toString();

    if (barcode.isEmpty && catalogProvider != null) {
      final pid = int.tryParse(alert['product_id']?.toString() ?? '');
      if (pid != null) {
        final match = catalogProvider.products.where((p) => p.id == pid).firstOrNull;
        if (match?.barcode != null) {
          barcode = match!.barcode!;
        }
      }
    }

    final haystack = _normalizeForSearch('$name $code $barcode $category');
    return queryTokens.every((token) => haystack.contains(token));
  }

  Future<void> _handleAlertTap(dynamic alert) async {
    _hideOverlay();
    if (!mounted) return;
    final catalogProvider = context.read<CatalogProvider>();
    final alertsProvider = context.read<InventoryAlertsProvider>();
    try {
      final productId = int.parse(alert['product_id'].toString());
      var product = await catalogProvider.resolveProductById(productId);
      if (!mounted) return;
      if (product == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Producto no disponible en catálogo local. Recargue la App.')),
        );
        return;
      }
      final alertStock = double.tryParse(alert['current_stock']?.toString() ?? '');
      if (alertStock != null && product.stock != alertStock) {
        product = product.copyWith(stock: alertStock);
      }
      await showDialog(
        context: context,
        builder: (ctx) => StockAdjustmentDialog(
          provider: catalogProvider,
          product: product!,
        ),
      );
      if (mounted) {
        alertsProvider.fetchAlerts();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Producto no disponible en catálogo local. Recargue la App.')),
      );
    }
  }

  Future<void> _handleViewProductTap(dynamic alert) async {
    _hideOverlay();
    if (!mounted) return;
    final catalogProvider = context.read<CatalogProvider>();
    final alertsProvider = context.read<InventoryAlertsProvider>();
    try {
      final productId = int.parse(alert['product_id'].toString());
      final product = await catalogProvider.resolveProductById(productId);
      if (!mounted) return;
      if (product == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Producto no disponible en catálogo local.')),
        );
        return;
      }
      await Navigator.of(context).pushNamed('/catalog', arguments: product);
      if (mounted) {
        alertsProvider.fetchAlerts();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Producto no disponible en catálogo local.')),
      );
    }
  }

  List<dynamic> _safeExpirationAlerts(InventoryAlertsProvider provider) {
    try {
      return provider.expirationAlerts;
    } catch (_) {
      return const [];
    }
  }

  List<dynamic> _safeDeficitAlerts(InventoryAlertsProvider provider) {
    try {
      return provider.deficitAlerts;
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: 'inventory_alerts_overlay',
      child: OverlayPortal.overlayChildLayoutBuilder(
        controller: _overlayController,
        overlayChildBuilder: (context, info) =>
            _buildOverlayContent(context, info),
        child: Consumer2<InventoryAlertsProvider, SettingsProvider>(
            builder: (context, provider, settings, _) {
              final hasPredictive = settings.features.predictiveAlerts;
              final expAlerts = _safeExpirationAlerts(provider);
              final deficitAlerts = _safeDeficitAlerts(provider);
              final count = hasPredictive
                  ? provider.totalAlertsCount
                  : (provider.reactiveAlerts.length +
                      expAlerts.length +
                      deficitAlerts.length);
              final hasCritical = provider.reactiveAlerts.isNotEmpty ||
                  expAlerts.any((a) => a['alert_level'] == 'critical') ||
                  (hasPredictive &&
                      provider.predictiveCriticalAlerts.isNotEmpty);

              return TweenAnimationBuilder<double>(
                key: ValueKey(count > 0 ? count : 0),
                tween: Tween(begin: 0.0, end: count > 0 ? 1.0 : 0.0),
                duration: const Duration(milliseconds: 1000),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Badge(
                    isLabelVisible: count > 0,
                    label: Text(count > 9 ? '9+' : count.toString(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                    backgroundColor: hasCritical ? Colors.red.shade600 : Colors.orange.shade600,
                    offset: const Offset(-4, 4),
                    child: Transform.rotate(
                      angle: count > 0 ? (0.3 * (1.0 - value)) : 0,
                      child: IconButton(
                        tooltip: count == 0
                            ? 'Sin alertas'
                            : '$count alerta${count > 1 ? 's' : ''} activa${count > 1 ? 's' : ''}',
                        icon: Icon(
                          count > 0
                              ? Icons.notifications_active
                              : Icons.notifications_none,
                          color: hasCritical
                              ? Colors.red.shade600
                              : count > 0
                                  ? Colors.orange.shade700
                                  : Colors.blueGrey.shade400,
                        ),
                        onPressed: _toggleOverlay,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
    );
  }

  Widget _buildOverlayContent(
    BuildContext context,
    OverlayChildLayoutInfo info,
  ) {
    final Offset targetBottomRight = MatrixUtils.transformPoint(
      info.childPaintTransform,
      Offset(info.childSize.width, info.childSize.height),
    );
    final double top = targetBottomRight.dy + 8.0;
    final double rawRight = info.overlaySize.width - targetBottomRight.dx;
    final double right = rawRight < 8.0 ? 8.0 : rawRight;

    return Positioned(
      top: top,
      right: right,
      child: TapRegion(
        groupId: 'inventory_alerts_overlay',
        onTapOutside: (_) => _hideOverlay(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 540),
          child: Material(
            elevation: 16,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            shadowColor: Colors.black.withValues(alpha: 0.3),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(context),
                  _buildSearchBar(context),
                  const Divider(height: 1),
                  Flexible(child: _buildBody()),
                  const Divider(height: 1),
                  _buildFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.orange.shade50, shape: BoxShape.circle),
            child: Icon(Icons.notifications_active,
                color: Colors.orange.shade800, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Alertas de Reposición',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20, color: Colors.blueGrey),
            tooltip: null,
            onPressed: () =>
                context.read<InventoryAlertsProvider>().fetchAlerts(),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: null,
            onPressed: _hideOverlay,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Consumer2<InventoryAlertsProvider, SettingsProvider>(
      builder: (context, provider, settings, _) {
        final hasPredictive = settings.features.predictiveAlerts;
        final expAlerts = _safeExpirationAlerts(provider);
        final deficitAlerts = _safeDeficitAlerts(provider);
        final hasAnyAlerts = hasPredictive
            ? (provider.alerts.isNotEmpty || deficitAlerts.isNotEmpty)
            : (provider.reactiveAlerts.isNotEmpty ||
                expAlerts.isNotEmpty ||
                deficitAlerts.isNotEmpty);

        if (provider.isLoading || !hasAnyAlerts) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SizedBox(
            height: 36,
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              style: const TextStyle(fontSize: 12.5),
              decoration: InputDecoration(
                hintText: 'Buscar producto, código o categoría...',
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: Colors.blueGrey.shade400,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 34,
                  minHeight: 36,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: Colors.grey.shade600,
                        ),
                        padding: EdgeInsets.zero,
                        tooltip: 'Limpiar búsqueda',
                        onPressed: () {
                          _clearSearch();
                          _searchFocusNode.requestFocus();
                        },
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 36,
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: Colors.orange.shade600,
                    width: 1.3,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    return Consumer2<InventoryAlertsProvider, SettingsProvider>(
      builder: (context, provider, settings, _) {
        final hasPredictive = settings.features.predictiveAlerts;
        final expAlerts = _safeExpirationAlerts(provider);
        final deficitAlerts = _safeDeficitAlerts(provider);

        if (provider.isLoading) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if ((hasPredictive && provider.alerts.isEmpty && deficitAlerts.isEmpty) ||
            (!hasPredictive &&
                provider.reactiveAlerts.isEmpty &&
                expAlerts.isEmpty &&
                deficitAlerts.isEmpty)) {
          return Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline,
                    size: 48, color: Colors.green.shade400),
                const SizedBox(height: 12),
                Text('¡Todo en orden!',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700)),
                const SizedBox(height: 6),
                Text(
                    hasPredictive
                        ? 'No hay productos con menos de 3 días de stock estimado ni debajo del mínimo.'
                        : 'Ningún producto alcanzó su stock mínimo.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                if (!hasPredictive) ...[
                  const SizedBox(height: 24),
                  _buildProBanner(context),
                ],
              ],
            ),
          );
        }

        CatalogProvider? catalogProvider;
        try {
          catalogProvider = context.read<CatalogProvider>();
        } catch (_) {}

        final queryTokens = _normalizeForSearch(_searchQuery.trim())
            .split(RegExp(r'\s+'))
            .where((t) => t.isNotEmpty)
            .toList();

        final filteredExpAlerts = expAlerts
            .where((a) => _matchesSearch(a, queryTokens, catalogProvider))
            .toList();
        final filteredReactiveAlerts = provider.reactiveAlerts
            .where((a) => _matchesSearch(a, queryTokens, catalogProvider))
            .toList();
        final filteredPredictiveAlerts = hasPredictive
            ? provider.predictiveCriticalAlerts
                .where((a) => _matchesSearch(a, queryTokens, catalogProvider))
                .toList()
            : const <dynamic>[];
        final filteredDeficitAlerts = deficitAlerts
            .where((a) => _matchesSearch(a, queryTokens, catalogProvider))
            .toList();

        if (queryTokens.isNotEmpty &&
            filteredExpAlerts.isEmpty &&
            filteredReactiveAlerts.isEmpty &&
            filteredPredictiveAlerts.isEmpty &&
            filteredDeficitAlerts.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_off_rounded,
                  size: 42,
                  color: Colors.blueGrey.shade300,
                ),
                const SizedBox(height: 10),
                Text(
                  'Sin resultados para "${_searchQuery.trim()}"',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.blueGrey.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Probá buscando por otro nombre, código interno o categoría.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    _clearSearch();
                    _searchFocusNode.requestFocus();
                  },
                  icon: const Icon(Icons.clear_all_rounded, size: 16),
                  label: const Text(
                    'Ver todas las alertas',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          );
        }

        final entries = <Widget>[
          if (filteredDeficitAlerts.isNotEmpty) ...[
            _SectionHeader(
              label: queryTokens.isEmpty
                  ? '⚠️ VENTAS SIN LOTE RESPALDATORIO (${filteredDeficitAlerts.length})'
                  : '⚠️ VENTAS SIN LOTE (${filteredDeficitAlerts.length}/${deficitAlerts.length})',
              color: Colors.deepOrange.shade50,
              textColor: Colors.deepOrange.shade900,
            ),
            ...filteredDeficitAlerts
                .map((a) => _buildDeficitTile(context, provider, a)),
          ],
          if (filteredExpAlerts.isNotEmpty) ...[
            _SectionHeader(
              label: queryTokens.isEmpty
                  ? '⏰ ALERTAS DE VENCIMIENTO (${filteredExpAlerts.length})'
                  : '⏰ ALERTAS DE VENCIMIENTO (${filteredExpAlerts.length}/${expAlerts.length})',
              color: Colors.purple.shade50,
              textColor: Colors.purple.shade900,
              trailing: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: Colors.deepOrange.shade800,
                ),
                icon: const Icon(Icons.cleaning_services_outlined, size: 14),
                label: const Text(
                  'Barrido Vencidos',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
                onPressed: () async {
                  _hideOverlay();
                  if (!mounted) return;
                  final catalogProvider = context.read<CatalogProvider>();
                  final swept = await showDialog<bool>(
                    context: context,
                    builder: (_) =>
                        ExpiredBatchesSweepDialog(provider: catalogProvider),
                  );
                  if (swept == true && mounted) {
                    provider.fetchAlerts();
                  }
                },
              ),
            ),
            ...filteredExpAlerts
                .map((a) => _buildExpirationTile(context, provider, a)),
          ],
          if (filteredReactiveAlerts.isNotEmpty) ...[
            _SectionHeader(
              label: queryTokens.isEmpty
                  ? '🔴 QUIEBRE DE STOCK O DEBAJO DEL MÍNIMO (${filteredReactiveAlerts.length})'
                  : '🔴 QUIEBRE DE STOCK O DEBAJO DEL MÍNIMO (${filteredReactiveAlerts.length}/${provider.reactiveAlerts.length})',
              color: Colors.red.shade50,
              textColor: Colors.red.shade800,
            ),
            ...filteredReactiveAlerts
                .map((a) => _buildDynamicTile(context, a, 'critical')),
          ],
          if (hasPredictive && filteredPredictiveAlerts.isNotEmpty) ...[
            _SectionHeader(
              label: queryTokens.isEmpty
                  ? '🟠 ALERTA DE VELOCIDAD — <= 3 días (${filteredPredictiveAlerts.length})'
                  : '🟠 ALERTA DE VELOCIDAD — <= 3 días (${filteredPredictiveAlerts.length}/${provider.predictiveCriticalAlerts.length})',
              color: Colors.orange.shade50,
              textColor: Colors.orange.shade800,
            ),
            ...filteredPredictiveAlerts
                .map((a) => _buildDynamicTile(context, a, 'critical')),
          ],
          if (!hasPredictive && queryTokens.isEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildProBanner(context),
            ),
            const SizedBox(height: 12),
          ],
        ];

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 10),
          shrinkWrap: true,
          itemCount: entries.length,
          itemBuilder: (context, index) => entries[index],
        );
      },
    );
  }

  Widget _buildDynamicTile(BuildContext context, dynamic alert, String level) {
    final type = alert['alert_type']?.toString() ?? 'predictive';
    void onTap() => _handleAlertTap(alert);
    void onVer() => _handleViewProductTap(alert);

    if (type == 'out_of_stock' || type == 'low_stock') {
      return _ReactiveAlertTile(
          alert: alert, level: level, onReponer: onTap, onVer: onVer);
    }
    return _PredictiveAlertTile(
        alert: alert, level: level, onTap: onTap, onVer: onVer);
  }

  Widget _buildExpirationTile(
    BuildContext context,
    InventoryAlertsProvider provider,
    dynamic alert,
  ) {
    final productId = (alert['product_id'] as num?)?.toInt() ?? 0;
    final batchId = (alert['batch_id'] as num?)?.toInt();
    final batchCode = alert['batch_code']?.toString();
    final name = (alert['product_name'] ?? alert['name'])?.toString() ?? 'Producto';
    final daysRemaining = ((alert['days_until_expiry'] ?? alert['days_until_expiration']) as num?)?.toInt() ?? 0;
    final stageLabel = alert['expiry_stage_label']?.toString() ?? 'Próximo a vencer';
    final stock = double.tryParse((alert['current_stock'] ?? 0).toString()) ?? 0;
    final expDate = alert['expiration_date']?.toString() ?? '';
    final isExpired = daysRemaining <= 0;
    final isCritical = daysRemaining <= 3;

    final badgeColor = isExpired
        ? Colors.red.shade700
        : (isCritical ? Colors.deepOrange.shade700 : Colors.purple.shade700);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isExpired ? Colors.red.shade50.withValues(alpha: 0.4) : Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isExpired ? Icons.warning_amber_rounded : Icons.event_busy,
              color: badgeColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        stageLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (batchCode != null && batchCode.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.teal.shade200),
                        ),
                        child: Text(
                          'Lote $batchCode',
                          style: TextStyle(
                            color: Colors.teal.shade900,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    Text(
                      isExpired
                          ? 'Venció ($expDate)'
                          : 'Faltan $daysRemaining d ($expDate)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: badgeColor,
                      ),
                    ),
                    Text(
                      '• Stock: ${stock % 1 == 0 ? stock.toInt() : stock.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Posponer o gestionar alerta',
            icon: Icon(Icons.snooze, size: 18, color: Colors.blueGrey.shade600),
            onSelected: (action) async {
              if (action == 'snooze_1' || action == 'snooze_3' || action == 'snooze_stage') {
                _hideOverlay();
                final ok = await provider.snoozeExpirationAlert(
                  productId,
                  action: action == 'snooze_stage' ? 'snooze_next_stage' : 'snooze_days',
                  days: action == 'snooze_1' ? 1 : (action == 'snooze_3' ? 3 : null),
                  batchId: batchId,
                );
                if (!mounted) return;
                if (ok) {
                  final msg = action == 'snooze_stage'
                      ? 'Alerta silenciada hasta la siguiente etapa.'
                      : 'Alerta pospuesta por ${action == 'snooze_1' ? '1 día' : '3 días'}.';
                  SnackBarService.success(context, msg);
                } else {
                  SnackBarService.error(context, provider.error ?? 'No se pudo posponer la alerta.');
                }
              } else if (action == 'write_off') {
                await _openWriteOffFromAlert(
                  provider,
                  productId: productId,
                  batchId: batchId,
                  batchCode: batchCode,
                  productName: name,
                  availableQty: stock,
                );
              } else if (action == 'transform' && batchId != null) {
                _hideOverlay();
                if (!mounted) return;
                final catalogProvider = context.read<CatalogProvider>();
                await showDialog(
                  context: context,
                  builder: (_) => ProductionOrdersDialog(
                    provider: catalogProvider,
                    filterIngredientProductId: productId,
                    initialExplicitBatchId: batchId,
                  ),
                );
                if (mounted) provider.fetchAlerts();
              } else if (action == 'liquidate') {
                await _openLiquidateFromAlert(
                  productId: productId,
                  productName: name,
                  batchCode: batchCode,
                  expDate: expDate,
                  isExpired: isExpired,
                );
              } else if (action == 'update_exp') {
                await _openUpdateExpirationFromAlert(
                  provider,
                  productId: productId,
                  productName: name,
                  batchId: batchId,
                  batchCode: batchCode,
                  currentExpDate: expDate,
                );
              } else if (action == 'batches' && batchId != null) {
                _hideOverlay();
                if (!mounted) return;
                final catalogProvider = context.read<CatalogProvider>();
                final product = await catalogProvider.resolveProductById(productId);
                if (!mounted) return;
                if (product == null) {
                  SnackBarService.error(context, 'Producto no disponible en catálogo.');
                  return;
                }
                await showDialog(
                  context: context,
                  builder: (_) => ProductBatchesDialog(
                    provider: catalogProvider,
                    product: product,
                  ),
                );
                if (mounted) provider.fetchAlerts();
              } else if (action == 'clear') {
                await _openClearExpirationFromAlert(
                  provider,
                  productId: productId,
                  productName: name,
                  batchId: batchId,
                  batchCode: batchCode,
                );
              } else if (action == 'view') {
                await _handleViewProductTap(alert);
              }
            },
            itemBuilder: (context) {
              final nextStageLabel = daysRemaining > 7
                  ? 'Silenciar hasta próximo aviso (7 días)'
                  : (daysRemaining > 3
                      ? 'Silenciar hasta aviso crítico (3 días)'
                      : 'Silenciar hasta el día del vencimiento');
              return [
                PopupMenuItem(
                  value: 'write_off',
                  child: Text(
                    batchId != null
                        ? 'Registrar Merma / Dar de baja lote'
                        : 'Registrar Merma / Dar de baja stock',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepOrange,
                    ),
                  ),
                ),
                if (batchId != null)
                  const PopupMenuItem(
                    value: 'transform',
                    child: Text('Transformar / Re-elaborar en receta',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal)),
                  ),
                const PopupMenuItem(
                  value: 'liquidate',
                  child: Text('Crear Oferta de Liquidación (%)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purple)),
                ),
                const PopupMenuItem(
                  value: 'update_exp',
                  child: Text('Actualizar fecha de vencimiento',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.indigo)),
                ),
                if (!isExpired)
                  PopupMenuItem(
                    value: 'snooze_stage',
                    child: Text(
                      nextStageLabel,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                const PopupMenuItem(
                  value: 'snooze_1',
                  child: Text('Posponer por 1 día', style: TextStyle(fontSize: 12)),
                ),
                const PopupMenuItem(
                  value: 'snooze_3',
                  child: Text('Posponer por 3 días', style: TextStyle(fontSize: 12)),
                ),
                if (batchId != null)
                  const PopupMenuItem(
                    value: 'batches',
                    child: Text('Gestionar lotes del producto', style: TextStyle(fontSize: 12)),
                  ),
                const PopupMenuItem(
                  value: 'view',
                  child: Text('Editar producto en Catálogo', style: TextStyle(fontSize: 12)),
                ),
                const PopupMenuItem(
                  value: 'clear',
                  child: Text('Lote vendido / Quitar fecha vto.',
                      style: TextStyle(fontSize: 12, color: Colors.red)),
                ),
              ];
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDeficitTile(
    BuildContext context,
    InventoryAlertsProvider provider,
    dynamic alert,
  ) {
    final productId = (alert['product_id'] as num?)?.toInt() ?? 0;
    final name = (alert['product_name'] ?? alert['name'])?.toString() ?? 'Producto';
    final batchCode = alert['batch_code']?.toString() ?? 'DÉFICIT';
    final deficitQty = double.tryParse((alert['deficit_quantity'] ?? 0).toString()) ?? 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.deepOrange.shade50.withValues(alpha: 0.35),
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.deepOrange.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.sync_problem, color: Colors.deepOrange.shade900, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  'Faltante sin respaldo de lote ($batchCode): ${deficitQty.toQty()} u. • Cargar producción o compra para conciliar.',
                  style: TextStyle(fontSize: 11.5, color: Colors.deepOrange.shade900),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () async {
              _hideOverlay();
              if (!mounted) return;
              final catalogProvider = context.read<CatalogProvider>();
              final product = await catalogProvider.resolveProductById(productId);
              if (!mounted) return;
              if (product == null) {
                await _handleViewProductTap(alert);
                return;
              }
              await showDialog(
                context: context,
                builder: (_) => ProductBatchesDialog(
                  provider: catalogProvider,
                  product: product,
                  initialOpenCreate: true,
                ),
              );
              if (mounted) provider.fetchAlerts();
            },
            child: const Text('Conciliar', style: TextStyle(fontSize: 11.5)),
          ),
        ],
      ),
    );
  }

  Future<void> _openWriteOffFromAlert(
    InventoryAlertsProvider alertsProvider, {
    required int productId,
    int? batchId,
    String? batchCode,
    required String productName,
    required double availableQty,
  }) async {
    _hideOverlay();
    if (!mounted) return;
    final qtyCtrl = TextEditingController(text: availableQty > 0 ? availableQty.toQty() : '');
    final notesCtrl = TextEditingController(text: 'Merma desde alerta de vencimiento');
    String? inlineError;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Text('Merma: $productName'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  batchId != null
                      ? 'Lote: ${batchCode ?? '#$batchId'} • Stock lote: ${availableQty.toQty()}'
                      : 'Stock actual disponible: ${availableQty.toQty()}',
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Cantidad a dar de baja',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Motivo de merma',
                    isDense: true,
                  ),
                ),
                if (inlineError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    inlineError!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
              onPressed: () {
                final parsed = double.tryParse(qtyCtrl.text.replaceAll(',', '.').trim());
                if (parsed == null || parsed <= 0) {
                  setModalState(() => inlineError = 'Ingresá una cantidad mayor a cero.');
                  return;
                }
                if (availableQty > 0 && parsed > availableQty + 0.0005) {
                  setModalState(
                    () => inlineError = 'No podés dar de baja más que el stock disponible (${availableQty.toQty()}).',
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Confirmar Merma'),
            ),
          ],
        ),
      ),
    );

    final qty = double.tryParse(qtyCtrl.text.replaceAll(',', '.').trim());
    final notes = notesCtrl.text.trim();
    qtyCtrl.dispose();
    notesCtrl.dispose();
    if (confirmed != true || qty == null || qty <= 0 || !mounted) return;

    final catalogProvider = context.read<CatalogProvider>();
    await AdminPinDialog.protectAction(
      context,
      action: 'Registrar Merma en $productName',
      permissionKey: AppPermissions.adjustStock,
      onAuthorized: () async {
        if (batchId != null) {
          final res = await catalogProvider.writeOffBatch(
            batchId,
            quantity: qty,
            notes: notes.isNotEmpty ? notes : null,
          );
          if (!mounted) return;
          if (res != null) {
            final lost = (res['cost_lost'] as num?)?.toDouble();
            SnackBarService.success(
              context,
              'Merma registrada${lost != null && lost > 0 ? ' (Costo perdido: \$${lost.toCurrency()})' : ''}.',
            );
            alertsProvider.fetchAlerts();
          } else {
            SnackBarService.error(
              context,
              catalogProvider.errorMessage ?? 'No se pudo registrar la merma.',
            );
          }
        } else {
          final ok = await catalogProvider.adjustStock(
            productId: productId,
            type: 'out',
            quantity: qty,
            notes: notes.isNotEmpty ? notes : 'Merma desde alerta de vencimiento',
            reasonCode: 'waste',
          );
          if (!mounted) return;
          if (ok) {
            SnackBarService.success(context, 'Merma registrada y stock actualizado (-${qty.toQty()}).');
            alertsProvider.fetchAlerts();
          } else {
            SnackBarService.error(
              context,
              catalogProvider.errorMessage ?? 'No se pudo registrar la merma.',
            );
          }
        }
      },
    );
  }

  Future<void> _openLiquidateFromAlert({
    required int productId,
    required String productName,
    String? batchCode,
    required String expDate,
    bool isExpired = false,
  }) async {
    _hideOverlay();
    if (!mounted) return;
    final rawBaseName =
        'Liquidación $productName${batchCode != null && batchCode.isNotEmpty ? ' ($batchCode)' : ''}';
    final defaultName =
        rawBaseName.length > 140 ? '${rawBaseName.substring(0, 137).trimRight()}...' : rawBaseName;
    final nameCtrl = TextEditingController(text: defaultName);
    final pctCtrl = TextEditingController(text: '30');

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final parsedRaw = DateTime.tryParse(expDate.trim());
    final parsedExpDay =
        parsedRaw != null ? DateTime(parsedRaw.year, parsedRaw.month, parsedRaw.day) : null;
    final bool expWasInPast = parsedExpDay != null && parsedExpDay.isBefore(today);

    DateTime endDate = (parsedExpDay != null && !parsedExpDay.isBefore(today))
        ? parsedExpDay
        : today.add(const Duration(days: 3));
    String? inlineError;

    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.local_offer_outlined, color: Colors.purple),
              SizedBox(width: 8),
              Flexible(child: Text('Crear Oferta de Liquidación')),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (expWasInPast || isExpired) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade400),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 18, color: Colors.amber.shade900),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            parsedExpDay != null
                                ? 'La fecha registrada (${DateFormat('dd/MM/yyyy').format(parsedExpDay)}) ya pasó. Para que la oferta impacte hoy en caja, sugerimos vigencia hasta el ${DateFormat('dd/MM/yyyy').format(endDate)}. Si la mercadería no está apta, usá "Registrar Merma".'
                                : 'Producto marcado como vencido. Si vas a liquidarlo hoy, elegí una fecha límite desde hoy en adelante; si no es apto, registrá Merma.',
                            style: TextStyle(fontSize: 11.5, color: Colors.amber.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                TextField(
                  controller: nameCtrl,
                  maxLength: 150,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la oferta',
                    isDense: true,
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pctCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Porcentaje de descuento (%)',
                    suffixText: '%',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final preset in const [
                      ('Solo hoy', 0),
                      ('+2 días', 2),
                      ('+3 días', 3),
                      ('+7 días', 7),
                    ])
                      ChoiceChip(
                        label: Text(preset.$1, style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        selected: sameDay(endDate, today.add(Duration(days: preset.$2))),
                        onSelected: (_) {
                          setModalState(() {
                            endDate = today.add(Duration(days: preset.$2));
                            inlineError = null;
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event, size: 16),
                  label: Text('Válida hasta: ${DateFormat('dd/MM/yyyy').format(endDate)}'),
                  onPressed: () async {
                    final picked = await showCompactDatePicker(
                      context: ctx,
                      initialDate: endDate.isBefore(today) ? today : endDate,
                      firstDate: today,
                      helpText: 'Fecha fin de liquidación',
                    );
                    if (picked != null) {
                      setModalState(() {
                        endDate = DateTime(picked.year, picked.month, picked.day);
                        inlineError = null;
                      });
                    }
                  },
                ),
                if (inlineError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    inlineError!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final pct = double.tryParse(pctCtrl.text.replaceAll(',', '.').trim());
                if (pct == null || pct <= 0 || pct > 100) {
                  setModalState(() => inlineError = 'Ingresá un descuento válido entre 1% y 100%.');
                  return;
                }
                if (endDate.isBefore(today)) {
                  setModalState(
                    () => inlineError = 'La fecha límite no puede ser anterior a hoy para que aplique en caja.',
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Publicar Oferta'),
            ),
          ],
        ),
      ),
    );

    final offerName = nameCtrl.text.trim();
    final discount = double.tryParse(pctCtrl.text.replaceAll(',', '.').trim());
    nameCtrl.dispose();
    pctCtrl.dispose();
    if (confirmed != true || discount == null || discount <= 0 || discount > 100 || !mounted) {
      return;
    }

    final offerProv = context.read<OfferProvider>();
    final ok = await offerProv.createQuickOffer(
      name: offerName.isNotEmpty ? offerName : 'Liquidación $productName',
      description: batchCode != null && batchCode.isNotEmpty
          ? 'Liquidación por vencimiento lote $batchCode'
          : 'Liquidación por próximo vencimiento',
      type: 'percentage',
      discountPercentage: discount,
      periodType: 'custom',
      startDate: DateTime(today.year, today.month, today.day, 0, 0, 0),
      endDate: DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59),
      productIds: [productId],
    );
    if (mounted) {
      if (ok) {
        try {
          context.read<PosProvider>().syncActiveOffers(offerProv.activeOffers);
        } catch (_) {}
        SnackBarService.success(
          context,
          'Oferta de liquidación (${discount.toQty()}% OFF) activa hasta ${DateFormat('dd/MM/yyyy').format(endDate)} y aplicada en caja.',
        );
      } else {
        SnackBarService.error(context, offerProv.errorMessage ?? 'No se pudo crear la oferta.');
      }
    }
  }

  Future<void> _openUpdateExpirationFromAlert(
    InventoryAlertsProvider alertsProvider, {
    required int productId,
    required String productName,
    int? batchId,
    String? batchCode,
    required String currentExpDate,
  }) async {
    _hideOverlay();
    if (!mounted) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final parsed = DateTime.tryParse(currentExpDate.trim());
    final initial = (parsed != null && !parsed.isBefore(today))
        ? parsed
        : today.add(const Duration(days: 3));

    final picked = await showCompactDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      helpText: batchCode != null && batchCode.isNotEmpty
          ? 'Nuevo vencimiento — $productName (Lote $batchCode)'
          : 'Nuevo vencimiento — $productName',
    );
    if (picked == null || !mounted) return;

    await AdminPinDialog.protectAction(
      context,
      action: 'Actualizar vencimiento de $productName',
      permissionKey: AppPermissions.manageCatalog,
      onAuthorized: () async {
        final formatted = DateFormat('yyyy-MM-dd').format(picked);
        final ok = await alertsProvider.snoozeExpirationAlert(
          productId,
          action: 'update_expiration',
          expirationDate: formatted,
          batchId: batchId,
        );
        if (!mounted) return;
        if (ok) {
          SnackBarService.success(
            context,
            'Vencimiento actualizado al ${DateFormat('dd/MM/yyyy').format(picked)}.',
          );
        } else {
          SnackBarService.error(
            context,
            alertsProvider.error ?? 'No se pudo actualizar el vencimiento.',
          );
        }
      },
    );
  }

  Future<void> _openClearExpirationFromAlert(
    InventoryAlertsProvider alertsProvider, {
    required int productId,
    required String productName,
    int? batchId,
    String? batchCode,
  }) async {
    _hideOverlay();
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar fecha de vencimiento'),
        content: Text(
          batchId != null
              ? 'Se quitará la fecha de vencimiento del lote ${batchCode ?? '#$batchId'} de "$productName" SIN descontar stock.\n\nSi la mercadería se descartó, usá "Registrar Merma".'
              : 'Se quitará la fecha de vencimiento de "$productName" SIN descontar stock.\n\nSi la mercadería se descartó, usá "Registrar Merma".',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar fecha'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await AdminPinDialog.protectAction(
      context,
      action: 'Quitar fecha de vencimiento ($productName)',
      permissionKey: AppPermissions.manageCatalog,
      onAuthorized: () async {
        final ok = await alertsProvider.snoozeExpirationAlert(
          productId,
          action: 'clear_expiration',
          batchId: batchId,
        );
        if (!mounted) return;
        if (ok) {
          SnackBarService.success(context, 'Fecha de vencimiento quitada.');
        } else {
          SnackBarService.error(
            context,
            alertsProvider.error ?? 'No se pudo quitar la fecha de vencimiento.',
          );
        }
      },
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 14, color: Colors.grey.shade400),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Alertas combinadas: Stock mínimo superado vs. Estimación a 15 días.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProBanner(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final url = Uri.parse(
                'https://wa.me/543704787285?text=Hola,%20quiero%20contratar%20el%20Plan%20Premium%20para%20activar%20las%20Alertas%20Predictivas');
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.workspace_premium_rounded,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Desbloquear Alertas Predictivas',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Anticipáte a los quiebres de stock — Plan Premium',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded,
                    color: Colors.white70, size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final Widget? trailing;
  const _SectionHeader({
    required this.label,
    required this.color,
    required this.textColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: color,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _ReactiveAlertTile extends StatelessWidget {
  final dynamic alert;
  final String level;
  final VoidCallback onReponer;
  final VoidCallback onVer;

  const _ReactiveAlertTile({
    required this.alert,
    required this.level,
    required this.onReponer,
    required this.onVer,
  });

  @override
  Widget build(BuildContext context) {
    final stock =
        double.tryParse(alert['current_stock']?.toString() ?? '0') ?? 0.0;
    final isCritical = alert['alert_type'] == 'out_of_stock';
    final isWeight =
        alert['is_sold_by_weight'] == 1 || alert['is_sold_by_weight'] == true;

    final String? rawImg = alert['image_url']?.toString() ?? alert['image_path']?.toString();
    String? effectiveImg = resolveImageUrl(rawImg);
    if (effectiveImg == null || effectiveImg.isEmpty) {
      try {
        final pid = int.tryParse(alert['product_id']?.toString() ?? '');
        if (pid != null) {
          final cat = context.read<CatalogProvider>();
          final match = cat.products.where((p) => p.id == pid).firstOrNull;
          effectiveImg = match?.imageUrl;
        }
      } catch (_) {}
    }
    final uri = effectiveImg != null && effectiveImg.isNotEmpty ? Uri.tryParse(effectiveImg) : null;
    final hasImage = uri != null && uri.hasScheme && uri.hasAuthority && uri.host.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isCritical ? Colors.red.shade100 : Colors.orange.shade100),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 5,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: isWeight ? Colors.orange.shade50 : Colors.blue.shade50,
                    border: Border.all(color: Colors.grey.shade300, width: 1),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: hasImage
                        ? CachedNetworkImage(
                            imageUrl: effectiveImg!,
                            width: 38,
                            height: 38,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => const Center(
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                            errorWidget: (context, url, error) => Icon(
                              Icons.inventory_2_outlined,
                              size: 20,
                              color: isWeight ? Colors.orange.shade700 : Colors.blue.shade700,
                            ),
                          )
                        : Icon(
                            Icons.inventory_2_outlined,
                            size: 20,
                            color: isWeight ? Colors.orange.shade700 : Colors.blue.shade700,
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(alert['product_name'].toString(),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(alert['internal_code']?.toString() ?? '',
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 11)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isWeight
                      ? '${stock.toStringAsFixed(3)} Kg'
                      : '${stock.toInt()} u',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isCritical ? Colors.red : Colors.orange.shade800),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onVer,
                  child: const Text('Ver', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: onReponer,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade50,
                      foregroundColor: Colors.teal.shade700,
                      elevation: 0),
                  child: const Text('Reponer', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PredictiveAlertTile extends StatelessWidget {
  final dynamic alert;
  final String level;
  final VoidCallback onTap;
  final VoidCallback onVer;

  const _PredictiveAlertTile({
    required this.alert,
    required this.level,
    required this.onTap,
    required this.onVer,
  });

  @override
  Widget build(BuildContext context) {
    final isCritical = level == 'critical';
    final color = isCritical ? Colors.red.shade600 : Colors.orange.shade700;
    final bgColor = isCritical ? Colors.red.shade50 : Colors.orange.shade50;
    final days =
        double.tryParse(alert['days_of_coverage']?.toString() ?? '0') ?? 0.0;
    final stock =
        double.tryParse(alert['current_stock']?.toString() ?? '0') ?? 0.0;
    final avgDaily =
        double.tryParse(alert['avg_daily_units']?.toString() ?? '0') ?? 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isCritical ? Colors.red.shade100 : Colors.orange.shade100),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 5,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration:
                      BoxDecoration(color: bgColor, shape: BoxShape.circle),
                  child: Icon(
                    isCritical
                        ? Icons.warning_rounded
                        : Icons.access_time_rounded,
                    color: color,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert['product_name'].toString(),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${alert['category']} · Stock: ${stock % 1 == 0 ? stock.toInt() : stock} unid.',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600),
                      ),
                      Text(
                        'Velocidad: ${avgDaily.toStringAsFixed(1)} uds/día',
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${days.toStringAsFixed(1)}d',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: color,
                          height: 1),
                    ),
                    const SizedBox(height: 2),
                    Text('para llegar\nal mínimo',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 8,
                            height: 1.1,
                            color: Colors.grey.shade500)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onVer,
                  child: const Text('Ver', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade50,
                      foregroundColor: Colors.teal.shade700,
                      elevation: 0),
                  child: const Text('Reponer', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
