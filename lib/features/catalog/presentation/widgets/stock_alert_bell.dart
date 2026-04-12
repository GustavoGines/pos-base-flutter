import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'stock_adjustment_dialog.dart';

class StockAlertBell extends StatefulWidget {
  const StockAlertBell({super.key});

  @override
  State<StockAlertBell> createState() => _StockAlertBellState();
}

class _StockAlertBellState extends State<StockAlertBell> {
  Timer? _refreshTimer;
  final _overlayController = OverlayPortalController();
  final _link = LayerLink();

  @override
  void initState() {
    super.initState();
    // Carga inicial de alertas
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<CatalogProvider>().fetchCriticalAlerts();
      }
    });

    // Polling Silencioso cada 2 minutos
    _refreshTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      if (mounted) {
        context.read<CatalogProvider>().fetchCriticalAlerts();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _toggleOverlay() {
    _overlayController.toggle();
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: 'stock_alert_overlay',
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _overlayController,
          overlayChildBuilder: (context) => _buildOverlayContent(),
          child: Consumer<CatalogProvider>(
            builder: (context, provider, _) {
              final alerts = provider.criticalAlerts;
              final count = alerts.length;

              return TweenAnimationBuilder<double>(
                key: ValueKey(count > 0),
                tween: Tween(begin: 0.0, end: count > 0 ? 1.0 : 0.0),
                duration: const Duration(milliseconds: 1500),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.rotate(
                        angle: count > 0 ? (0.15 * (1.0 - value) * (DateTime.now().second % 5 == 0 ? 1 : 0)) : 0, 
                        child: IconButton(
                          icon: Icon(
                            count > 0 ? Icons.notifications_active : Icons.notifications_none,
                            color: count > 0 ? Colors.orange.shade700 : Colors.blueGrey,
                          ),
                          tooltip: 'Alertas de Stock',
                          onPressed: _toggleOverlay,
                        ),
                      ),
                      if (count > 0)
                        Positioned(
                          right: 2,
                          top: 2,
                          child: IgnorePointer(
                            child: _buildBadge(count),
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(int count) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.8, end: 1.05),
      duration: const Duration(seconds: 1),
      curve: Curves.easeInOut,
      builder: (context, scale, _) {
        return Transform.scale(
          scale: scale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(color: Colors.red.withOpacity(0.4), blurRadius: 4, spreadRadius: 1),
              ],
            ),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          ),
        );
      },
    );
  }

  Widget _buildOverlayContent() {
    return TapRegion(
      groupId: 'stock_alert_overlay',
      onTapOutside: (_) => _overlayController.hide(),
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomRight,
        followerAnchor: Alignment.topRight,
        offset: const Offset(0, 8),
        child: Align(
          alignment: Alignment.topRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
            child: Material(
              elevation: 16,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              shadowColor: Colors.black.withOpacity(0.3),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeader(),
                    const Divider(height: 1),
                    Flexible(child: _buildAlertList()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
            child: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Notificaciones de Stock', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20, color: Colors.blueGrey),
            tooltip: null,
            onPressed: () => context.read<CatalogProvider>().fetchCriticalAlerts(),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: null,
            onPressed: () => _overlayController.hide(),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertList() {
    return Consumer<CatalogProvider>(
      builder: (context, provider, _) {
        final alerts = provider.criticalAlerts;
        if (alerts.isEmpty) {
          return const Center(child: Text('¡Todo en orden!', style: TextStyle(color: Colors.grey)));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: alerts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final product = alerts[index];
            return _StockAlertItem(
              product: product,
              onAction: () => _overlayController.hide(),
            );
          },
        );
      },
    );
  }
}

class _StockAlertItem extends StatelessWidget {
  final dynamic product;
  final VoidCallback onAction;
  const _StockAlertItem({required this.product, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final double stock = product.stock;
    final bool isCritical = stock <= 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isCritical ? Colors.red.shade100 : Colors.orange.shade100),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(product.internalCode, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                  ],
                ),
              ),
              Text(
                product.isSoldByWeight ? '${stock.toQty()} Kg' : '${stock.toInt()} u',
                style: TextStyle(fontWeight: FontWeight.bold, color: isCritical ? Colors.red : Colors.orange.shade800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  onAction();
                  Navigator.of(context).pushNamed('/catalog', arguments: product);
                },
                child: const Text('Ver', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  onAction();
                  showDialog(
                    context: context,
                    builder: (context) => StockAdjustmentDialog(
                      provider: context.read<CatalogProvider>(),
                      product: product,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade50, foregroundColor: Colors.teal.shade700, elevation: 0),
                child: const Text('Reponer', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
