import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/stock_adjustment_dialog.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
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
  final _link = LayerLink();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InventoryAlertsProvider>().fetchAlerts();
    });
  }

  void _toggleOverlay() {
    _overlayController.toggle();
  }

  void _handleAlertTap(BuildContext context, dynamic alert) {
    _overlayController.hide();
    final catalogProvider = context.read<CatalogProvider>();
    try {
      final productId = int.parse(alert['product_id'].toString());
      final product = catalogProvider.products.firstWhere((p) => p.id == productId);
      showDialog(
        context: context,
        builder: (ctx) => StockAdjustmentDialog(
          provider: catalogProvider,
          product: product,
        ),
      ).then((_) {
        // Al cerrar el ajuste, recargamos el reporte de alertas por si zafó
        if (context.mounted) {
          context.read<InventoryAlertsProvider>().fetchAlerts();
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Producto no disponible en catálogo local. Recargue la App.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: 'inventory_alerts_overlay',
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _overlayController,
          overlayChildBuilder: (context) => _buildOverlayContent(context),
          child: Consumer2<InventoryAlertsProvider, SettingsProvider>(
            builder: (context, provider, settings, _) {
              final hasPredictive = settings.features.predictiveAlerts;
              final count = hasPredictive ? provider.totalAlertsCount : provider.reactiveAlerts.length;
              final hasCritical = provider.reactiveAlerts.isNotEmpty || (hasPredictive && provider.predictiveCriticalAlerts.isNotEmpty);

              return TweenAnimationBuilder<double>(
                key: ValueKey(count > 0 ? count : 0),
                tween: Tween(begin: 0.0, end: count > 0 ? 1.0 : 0.0),
                duration: const Duration(milliseconds: 1000),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Transform.rotate(
                       angle: count > 0 ? (0.3 * (1.0 - value)) : 0,
                       child: IconButton(
                        tooltip: count == 0
                            ? 'Sin alertas de stock'
                            : '$count producto${count > 1 ? 's' : ''} con bajo stock',
                        icon: Icon(
                          count > 0 ? Icons.notifications_active : Icons.notifications_none,
                          color: hasCritical
                              ? Colors.red.shade600
                              : count > 0
                                  ? Colors.orange.shade700
                                  : Colors.blueGrey.shade400,
                        ),
                        onPressed: _toggleOverlay,
                       ),
                      ),
                      if (count > 0)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: IgnorePointer(
                            child: Transform.scale(
                              scale: 0.8 + (0.2 * value),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: hasCritical ? Colors.red.shade600 : Colors.orange.shade600,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white, width: 1.5),
                                  boxShadow: [
                                    BoxShadow(color: hasCritical ? Colors.red.withOpacity(0.4) : Colors.orange.withOpacity(0.4), blurRadius: 4, spreadRadius: 1),
                                  ],
                                ),
                                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                child: Text(
                                  count > 9 ? '9+' : count.toString(),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
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

  Widget _buildOverlayContent(BuildContext context) {
    return TapRegion(
      groupId: 'inventory_alerts_overlay',
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
                    _buildHeader(context),
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
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
            child: Icon(Icons.notifications_active, color: Colors.orange.shade800, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Alertas de Reposición', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20, color: Colors.blueGrey),
            tooltip: null,
            onPressed: () => context.read<InventoryAlertsProvider>().fetchAlerts(),
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

  Widget _buildBody() {
    return Consumer2<InventoryAlertsProvider, SettingsProvider>(
      builder: (context, provider, settings, _) {
        final hasPredictive = settings.features.predictiveAlerts;
        
        if (provider.isLoading) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        } 
        
        if ((hasPredictive && provider.alerts.isEmpty) || (!hasPredictive && provider.reactiveAlerts.isEmpty)) {
          return Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 48, color: Colors.green.shade400),
                const SizedBox(height: 12),
                Text('¡Todo en orden!',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700)),
                const SizedBox(height: 6),
                Text(hasPredictive ? 'No hay productos con menos de 3 días de stock estimado ni debajo del mínimo.' : 'Ningún producto alcanzó su stock mínimo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                if (!hasPredictive) ...[
                  const SizedBox(height: 24),
                  _buildProBanner(context),
                ],
              ],
            ),
          );
        }

        return ListView(
          shrinkWrap: true,
          children: [
            if (provider.reactiveAlerts.isNotEmpty) ...[
              _SectionHeader(
                  label: '🔴 QUIEBRE DE STOCK O DEBAJO DEL MÍNIMO',
                  color: Colors.red.shade50,
                  textColor: Colors.red.shade800),
              ...provider.reactiveAlerts
                  .map((a) => _buildDynamicTile(context, a, 'critical')),
            ],
            if (hasPredictive && provider.predictiveCriticalAlerts.isNotEmpty) ...[
              _SectionHeader(
                  label: '🟠 ALERTA DE VELOCIDAD — <= 3 días',
                  color: Colors.orange.shade50,
                  textColor: Colors.orange.shade800),
              ...provider.predictiveCriticalAlerts
                  .map((a) => _buildDynamicTile(context, a, 'critical')),
            ],
            if (!hasPredictive) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildProBanner(context),
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }

  Widget _buildDynamicTile(BuildContext context, dynamic alert, String level) {
    final type = alert['alert_type']?.toString() ?? 'predictive';
    final onTap = () => _handleAlertTap(context, alert);
    
    if (type == 'out_of_stock' || type == 'low_stock') {
      return _ReactiveAlertTile(alert: alert, level: level, onReponer: onTap);
    }
    return _PredictiveAlertTile(alert: alert, level: level, onTap: onTap);
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
            color: const Color(0xFF7C3AED).withOpacity(0.3),
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
            final url = Uri.parse('https://wa.me/543704787285?text=Hola,%20quiero%20contratar%20el%20Plan%20Premium%20para%20activar%20las%20Alertas%20Predictivas');
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
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Desbloquear Alertas Predictivas',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Anticipáte a los quiebres de stock — Plan Premium',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14),
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
  const _SectionHeader(
      {required this.label, required this.color, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: color,
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
    );
  }
}

class _ReactiveAlertTile extends StatelessWidget {
  final dynamic alert;
  final String level;
  final VoidCallback onReponer;

  const _ReactiveAlertTile(
      {required this.alert, required this.level, required this.onReponer});

  @override
  Widget build(BuildContext context) {
    final stock = double.tryParse(alert['current_stock']?.toString() ?? '0') ?? 0.0;
    final isCritical = alert['alert_type'] == 'out_of_stock';
    final isWeight = alert['is_sold_by_weight'] == 1 || alert['is_sold_by_weight'] == true;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isCritical ? Colors.red.shade100 : Colors.orange.shade100),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 5, offset: const Offset(0, 2)),
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
                      Text(alert['product_name'].toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(alert['internal_code']?.toString() ?? '',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                    ],
                  ),
                ),
                Text(
                  isWeight ? '${stock.toStringAsFixed(3)} Kg' : '${stock.toInt()} u',
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
                  onPressed: () {
                    try {
                      final productId = int.parse(alert['product_id'].toString());
                      final product = context.read<CatalogProvider>().products.firstWhere((p) => p.id == productId);
                      Navigator.of(context).pushNamed('/catalog', arguments: product);
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Producto no disponible en catálogo local.')),
                      );
                    }
                  },
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

  const _PredictiveAlertTile({
    required this.alert, 
    required this.level,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCritical = level == 'critical';
    final color = isCritical ? Colors.red.shade600 : Colors.orange.shade700;
    final bgColor = isCritical ? Colors.red.shade50 : Colors.orange.shade50;
    final days = double.tryParse(alert['days_of_coverage']?.toString() ?? '0') ?? 0.0;
    final stock = double.tryParse(alert['current_stock']?.toString() ?? '0') ?? 0.0;
    final avgDaily = double.tryParse(alert['avg_daily_units']?.toString() ?? '0') ?? 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isCritical ? Colors.red.shade100 : Colors.orange.shade100),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 5, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
                  child: Icon(
                    isCritical ? Icons.warning_rounded : Icons.access_time_rounded,
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
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${alert['category']} · Stock: ${stock % 1 == 0 ? stock.toInt() : stock} unid.',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                      Text(
                        'Velocidad: ${avgDaily.toStringAsFixed(1)} uds/día',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
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
                        style: TextStyle(fontSize: 8, height: 1.1, color: Colors.grey.shade500)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    try {
                      final productId = int.parse(alert['product_id'].toString());
                      final product = context.read<CatalogProvider>().products.firstWhere((p) => p.id == productId);
                      Navigator.of(context).pushNamed('/catalog', arguments: product);
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Producto no disponible en catálogo local.')),
                      );
                    }
                  },
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
