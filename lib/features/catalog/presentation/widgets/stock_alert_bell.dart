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

  @override
  void initState() {
    super.initState();
    // Carga inicial de alertas
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<CatalogProvider>().fetchCriticalAlerts();
      }
    });

    // Polling Silencioso (Latido) cada 2 minutos
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

  void _showCriticalList(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _StockAlertBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CatalogProvider>(
      builder: (context, provider, _) {
        final alerts = provider.criticalAlerts;
        final count = alerts.length;

        // Si hay alertas, creamos una animación de "campaneo" sutil
        return TweenAnimationBuilder<double>(
          key: ValueKey(count > 0), // Reinicia si cambia el estado
          tween: Tween(begin: 0.0, end: count > 0 ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 1500),
          curve: Curves.elasticOut,
          builder: (context, value, child) {
            return Stack(
              alignment: Alignment.center,
              children: [
                // Transformación de rotación para la campana
                Transform.rotate(
                  angle: count > 0 ? (0.15 * (1.0 - value) * (DateTime.now().second % 5 == 0 ? 1 : 0)) : 0, 
                  // Usamos un pequeño truco con el tiempo para que no sea infinito y molesto
                  child: IconButton(
                    icon: Icon(
                      count > 0 ? Icons.notifications_active : Icons.notifications_none,
                      color: count > 0 ? Colors.orange.shade700 : Colors.blueGrey,
                    ),
                    tooltip: 'Alertas de Stock',
                    onPressed: () => _showCriticalList(context),
                  ),
                ),
                if (count > 0)
                  Positioned(
                    right: 2,
                    top: 2,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.8, end: 1.05),
                      duration: const Duration(seconds: 1),
                      curve: Curves.easeInOut,
                      builder: (context, scale, _) {
                        return Transform.scale(
                          scale: scale, // Efecto de pulso en el badge
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white, width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withValues(alpha: 0.4),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              '$count',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      },
                      onEnd: () {}, // Podemos dejarlo vacío o repetir
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _StockAlertBottomSheet extends StatelessWidget {
  const _StockAlertBottomSheet();

  @override
  Widget build(BuildContext context) {
    return Consumer<CatalogProvider>(
      builder: (context, provider, _) {
        final alerts = provider.criticalAlerts;

        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Stock Crítico',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${alerts.length} productos necesitan reposición',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () => provider.fetchCriticalAlerts(),
                      tooltip: 'Actualizar',
                    ),
                  ],
                ),
              ),
              const Divider(),
              // List
              Expanded(
                child: alerts.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: alerts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final product = alerts[index];
                          return Card(
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                            color: Colors.grey.shade50,
                            child: InkWell(
                              onTap: () {
                                Navigator.of(context).pop();
                                showDialog(
                                  context: context,
                                  builder: (context) => StockAdjustmentDialog(
                                    provider: provider,
                                    product: product,
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _StockAlertItem(product: product),
                                    const Divider(height: 20),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          icon: const Icon(Icons.remove_red_eye_outlined, size: 16),
                                          label: const Text('Ver en Catálogo', style: TextStyle(fontSize: 12)),
                                          onPressed: () {
                                            Navigator.of(context).pop();
                                            // Paso el producto como argumento para navegación inteligente
                                            Navigator.of(context).pushNamed('/catalog', arguments: product);
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.add_shopping_cart, size: 16),
                                          label: const Text('Reponer', style: TextStyle(fontSize: 12)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.teal.shade50,
                                            foregroundColor: Colors.teal.shade700,
                                            elevation: 0,
                                          ),
                                          onPressed: () {
                                            Navigator.of(context).pop();
                                            showDialog(
                                              context: context,
                                              builder: (context) => StockAdjustmentDialog(
                                                provider: provider,
                                                product: product,
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 64, color: Colors.green.shade200),
          const SizedBox(height: 16),
          const Text(
            '¡Todo en orden!',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey),
          ),
          const Text(
            'No hay productos por debajo del stock mínimo.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _StockAlertItem extends StatelessWidget {
  final dynamic product;
  const _StockAlertItem({required this.product});

  @override
  Widget build(BuildContext context) {
    final double stock = product.stock;
    final double minStock = product.minStock ?? 0;
    final bool isCritical = stock <= 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: isCritical ? Colors.red.shade100 : Colors.orange.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  product.internalCode,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12, letterSpacing: 1),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  Text(
                    product.isSoldByWeight ? stock.toStringAsFixed(3) : stock.toInt().toString(),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isCritical ? Colors.red.shade700 : Colors.orange.shade800,
                    ),
                  ),
                  Text(
                    product.isSoldByWeight ? ' Kg' : ' u',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
              Text(
                'Mínimo: ${minStock.toInt()}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
