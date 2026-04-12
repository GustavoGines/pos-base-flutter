import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_alerts_provider.dart';

/// Widget autónomo de alertas semafóricas de stock.
/// Se monta como botón en la GlobalAppBar y al pulsar despliega
/// un panel flotante con la lista de productos en riesgo.
class InventoryAlertsWidget extends StatefulWidget {
  const InventoryAlertsWidget({super.key});

  @override
  State<InventoryAlertsWidget> createState() => _InventoryAlertsWidgetState();
}

class _InventoryAlertsWidgetState extends State<InventoryAlertsWidget> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InventoryAlertsProvider>().fetchAlerts();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InventoryAlertsProvider>(
      builder: (context, provider, _) {
        final count = provider.totalAlertsCount;
        final hasCritical = provider.criticalAlerts.isNotEmpty;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: count == 0
                  ? 'Sin alertas de stock'
                  : '$count producto${count > 1 ? 's' : ''} con bajo stock',
              icon: Icon(
                Icons.inventory_2_outlined,
                color: hasCritical
                    ? Colors.red.shade600
                    : count > 0
                        ? Colors.orange.shade700
                        : Colors.blueGrey.shade400,
              ),
              onPressed: () => _showAlertsPanel(context, provider),
            ),
            if (count > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 17,
                  height: 17,
                  decoration: BoxDecoration(
                    color: hasCritical ? Colors.red.shade600 : Colors.orange.shade600,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      count > 9 ? '9+' : count.toString(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _showAlertsPanel(BuildContext context, InventoryAlertsProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => _AlertsPanelDialog(provider: provider),
    );
  }
}

// ─── Panel flotante de alertas ────────────────────────────────────────────────

class _AlertsPanelDialog extends StatelessWidget {
  final InventoryAlertsProvider provider;
  const _AlertsPanelDialog({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.only(right: 16, top: 60, bottom: 16),
      alignment: Alignment.topRight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade800,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Alertas de Reposición',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  // Botón refrescar
                  IconButton(
                    onPressed: () => provider.fetchAlerts(),
                    icon: const Icon(Icons.refresh, color: Colors.white70, size: 18),
                    tooltip: 'Actualizar',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Cuerpo
            if (provider.isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              )
            else if (provider.alerts.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.check_circle_outline, size: 48, color: Colors.green.shade400),
                    const SizedBox(height: 12),
                    Text('¡Todo en orden!',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700)),
                    const SizedBox(height: 6),
                    Text('No hay productos con menos de 7 días de stock estimado.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 450),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (provider.criticalAlerts.isNotEmpty) ...[
                      _SectionHeader(
                          label: '🔴 CRÍTICO — Menos de 3 días',
                          color: Colors.red.shade50,
                          textColor: Colors.red.shade800),
                      ...provider.criticalAlerts
                          .map((a) => _AlertTile(alert: a, level: 'critical')),
                    ],
                    if (provider.warningAlerts.isNotEmpty) ...[
                      _SectionHeader(
                          label: '🟡 ATENCIÓN — Entre 3 y 7 días',
                          color: Colors.orange.shade50,
                          textColor: Colors.orange.shade800),
                      ...provider.warningAlerts
                          .map((a) => _AlertTile(alert: a, level: 'warning')),
                    ],
                  ],
                ),
              ),

            // Footer
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 12, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Estimado en base a los últimos 15 días de ventas.',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    ),
                  ),
                ],
              ),
            ),
          ],
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

class _AlertTile extends StatelessWidget {
  final dynamic alert;
  final String level;
  const _AlertTile({required this.alert, required this.level});

  @override
  Widget build(BuildContext context) {
    final isCritical = level == 'critical';
    final color = isCritical ? Colors.red.shade600 : Colors.orange.shade700;
    final bgColor = isCritical ? Colors.red.shade50 : Colors.orange.shade50;
    final days = (alert['days_of_coverage'] as num).toDouble();
    final stock = (alert['current_stock'] as num).toDouble();
    final avgDaily = (alert['avg_daily_units'] as num).toDouble();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
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
              Text('restantes',
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
            ],
          ),
        ],
      ),
    );
  }
}
