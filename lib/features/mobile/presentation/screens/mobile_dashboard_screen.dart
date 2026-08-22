import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/features/sales_history/presentation/providers/sales_history_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/reports_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:dart_pusher_channels/dart_pusher_channels.dart';
import 'package:frontend_desktop/core/config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class MobileDashboardScreen extends StatefulWidget {
  const MobileDashboardScreen({super.key});

  @override
  State<MobileDashboardScreen> createState() => _MobileDashboardScreenState();
}

class _MobileDashboardScreenState extends State<MobileDashboardScreen> {
  PusherChannelsClient? _pusher;
  String _selectedPeriod = 'today';

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _loadData());
    _initPusher();
  }

  Future<void> _initPusher() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUrl = prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;
      
      final options = PusherChannelsOptions.fromHost(
        scheme: currentUrl.startsWith('https') ? 'wss' : 'ws',
        host: Uri.parse(currentUrl).host,
        port: 8080,
        key: 'kz786cdfeldnzispymxq', // Debe coincidir con REVERB_APP_KEY
      );

      _pusher = PusherChannelsClient.websocket(
        options: options,
        connectionErrorHandler: (error, trace, refresh) {},
      );

      _pusher!.onConnectionEstablished.listen((_) {
        final channel = _pusher!.publicChannel('dashboard');
        channel.subscribe();
        channel.bind('App\\Events\\DashboardUpdated').listen((event) {
          if (mounted) _loadData();
        });
      });

      await _pusher!.connect();
    } catch (e) {
      debugPrint('Error init pusher in dashboard: $e');
    }
  }

  @override
  void dispose() {
    _pusher?.disconnect();
    super.dispose();
  }

  Future<void> _loadData() async {
    final salesProvider = context.read<SalesHistoryProvider>();
    final reportsProvider = context.read<ReportsProvider>();
    final cashRegisterProvider = context.read<CashRegisterProvider>();
    final alertsProvider = context.read<InventoryAlertsProvider>();

    await salesProvider.loadSales(period: _selectedPeriod);
    
    // Recargar métricas secundarias secuencialmente para evitar cuellos de botella en el servidor local
    await cashRegisterProvider.checkCurrentShiftSilently();
    await alertsProvider.fetchAlerts();

    DateTime start = DateTime.now();
    DateTime end = DateTime.now();

    if (_selectedPeriod == 'today') {
      start = DateTime.now();
      end = DateTime.now();
    } else if (_selectedPeriod == 'yesterday') {
      start = DateTime.now().subtract(const Duration(days: 1));
      end = DateTime.now().subtract(const Duration(days: 1));
    } else if (_selectedPeriod == 'week') {
      start = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
      end = start.add(const Duration(days: 6));
    } else if (_selectedPeriod == 'month') {
      start = DateTime(DateTime.now().year, DateTime.now().month, 1);
      end = DateTime(DateTime.now().year, DateTime.now().month + 1, 0);
    }

    reportsProvider.setDateRange(start, end);
    await reportsProvider.fetchProfitByCategory();
  }

  String _getPeriodLabel() {
    switch (_selectedPeriod) {
      case 'today': return 'Hoy';
      case 'yesterday': return 'Ayer';
      case 'week': return 'Esta Semana';
      case 'month': return 'Este Mes';
      default: return 'Hoy';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Panel de Ventas'),
        backgroundColor: const Color(0xFF1E2D45),
        foregroundColor: Colors.white,
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedPeriod,
              dropdownColor: const Color(0xFF1E2D45),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
              onChanged: (String? newValue) {
                if (newValue != null && newValue != _selectedPeriod) {
                  setState(() => _selectedPeriod = newValue);
                  _loadData();
                }
              },
              items: const [
                DropdownMenuItem(value: 'today', child: Text('Hoy')),
                DropdownMenuItem(value: 'yesterday', child: Text('Ayer')),
                DropdownMenuItem(value: 'week', child: Text('Esta Semana')),
                DropdownMenuItem(value: 'month', child: Text('Este Mes')),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: Consumer5<SalesHistoryProvider, ReportsProvider, SettingsProvider, CashRegisterProvider, InventoryAlertsProvider>(
        builder: (context, salesProvider, reportsProvider, settingsProvider, cashProvider, alertsProvider, child) {
          final canAccessAdvancedReports = settingsProvider.features.advancedReports;

          if (salesProvider.isLoading || reportsProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (salesProvider.errorMessage != null && salesProvider.errorMessage!.isNotEmpty) {
            return Center(child: Text('Error: ${salesProvider.errorMessage}'));
          }

          final sales = salesProvider.sales;
          
          double totalCash = 0;
          double totalCards = 0;
          double totalTransfer = 0;
          Map<String, double> productCount = {};

          for (var sale in sales) {
            if (sale.status == 'voided') continue;
            
            for (var pm in sale.payments) {
              if (pm.isCash || pm.methodCode == 'cash') {
                totalCash += pm.totalAmount;
              } else if (pm.methodCode.startsWith('card_')) {
                totalCards += pm.totalAmount;
              } else {
                totalTransfer += pm.totalAmount;
              }
            }

            for (var item in sale.items) {
              productCount[item.productName] = (productCount[item.productName] ?? 0) + item.quantity;
            }
          }

          var sortedProducts = productCount.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          var topProducts = sortedProducts.take(5).toList();

          return RefreshIndicator(
            onRefresh: _loadData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildShiftBanner(cashProvider),
                  
                  _buildSummaryCard(reportsProvider, sales.where((s) => s.status != 'voided').length, canAccessAdvancedReports),
                  const SizedBox(height: 16),
                  
                  if (_selectedPeriod != 'today' && _selectedPeriod != 'yesterday' && reportsProvider.dailyEvolution.isNotEmpty && canAccessAdvancedReports)
                    _buildChartCard(reportsProvider),
                    
                  if (_selectedPeriod != 'today' && _selectedPeriod != 'yesterday' && reportsProvider.dailyEvolution.isNotEmpty && canAccessAdvancedReports)
                    const SizedBox(height: 16),
                  
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Desglose de Ingresos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const Divider(),
                          _buildPaymentRow(Icons.payments, 'Efectivo', totalCash, Colors.green),
                          _buildPaymentRow(Icons.account_balance, 'Transferencia / QR', totalTransfer, Colors.blue),
                          _buildPaymentRow(Icons.credit_card, 'Tarjetas', totalCards, Colors.orange),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Productos Más Vendidos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const Divider(),
                          if (topProducts.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text('No hay ventas registradas aún.', style: TextStyle(color: Colors.grey)),
                            ),
                          ...topProducts.map((p) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF1E2D45).withValues(alpha: 0.1),
                              child: const Icon(Icons.star, color: Color(0xFF1E2D45)),
                            ),
                            title: Text(p.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                            trailing: Text('${p.value % 1 == 0 ? p.value.toInt() : p.value.toStringAsFixed(2)} unid.', style: const TextStyle(fontSize: 16)),
                          )),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  _buildAlertsSection(alertsProvider),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildShiftBanner(CashRegisterProvider cashProvider) {
    if (cashProvider.currentShift == null || !cashProvider.currentShift!.isOpen) {
      return const SizedBox.shrink();
    }

    final shift = cashProvider.currentShift!;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.point_of_sale, color: Colors.blue, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Turno Actual: ${shift.userName ?? "Desconocido"}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                Text('Efectivo esperado: \$${(shift.expectedBalance ?? 0).toStringAsFixed(0)} (Fondo Inicial: \$${shift.openingBalance.toStringAsFixed(0)})', style: TextStyle(fontSize: 12, color: Colors.blue.shade800)),
              ],
            ),
          ),
          const Icon(Icons.check_circle, color: Colors.green),
        ],
      ),
    );
  }

  Widget _buildAlertsSection(InventoryAlertsProvider alertsProvider) {
    if (alertsProvider.reactiveAlerts.isEmpty) {
      return const SizedBox.shrink();
    }

    final topAlerts = alertsProvider.reactiveAlerts.take(5).toList();

    return Card(
      elevation: 2,
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red.shade800),
                const SizedBox(width: 8),
                Text('⚠️ Stock Crítico', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
              ],
            ),
            const Divider(),
            ...topAlerts.map((alert) {
              final stock = double.tryParse(alert['current_stock']?.toString() ?? '0') ?? 0.0;
              final isWeight = alert['is_sold_by_weight'] == 1 || alert['is_sold_by_weight'] == true;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(alert['product_name'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text('Min: ${alert['min_stock'] ?? 0}', style: TextStyle(fontSize: 12, color: Colors.red.shade600)),
                trailing: Text(
                  isWeight ? '${stock.toStringAsFixed(3)} Kg' : '${stock.toInt()} u',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade800, fontSize: 16),
                ),
              );
            }),
            if (alertsProvider.reactiveAlerts.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Center(child: Text('+ ${alertsProvider.reactiveAlerts.length - 5} productos más', style: TextStyle(color: Colors.red.shade600, fontSize: 12))),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(ReportsProvider provider, int ticketsCount, bool canAccessAdvancedReports) {
    return Card(
      elevation: 4,
      color: Colors.green.shade700,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Text('INGRESOS (${_getPeriodLabel().toUpperCase()})', style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('\$${provider.totalRevenue.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('$ticketsCount tickets emitidos', style: const TextStyle(color: Colors.white, fontSize: 16)),
            if (canAccessAdvancedReports) ...[
              const Divider(color: Colors.white24, height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text('GANANCIA NETA', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      Text('\$${provider.totalProfit.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    children: [
                      const Text('MARGEN', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      Text('${provider.marginPercentage.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    children: [
                      const Text('TENDENCIA', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      Row(
                        children: [
                          Icon(provider.revenueTrendPercentage >= 0 ? Icons.arrow_upward : Icons.arrow_downward, color: Colors.white, size: 16),
                          Text('${provider.revenueTrendPercentage.abs().toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      )
                    ],
                  ),
                ],
              )
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildChartCard(ReportsProvider provider) {
    if (provider.dailyEvolution.isEmpty) return const SizedBox.shrink();

    List<FlSpot> spots = [];
    double maxY = 0;
    
    for (int i = 0; i < provider.dailyEvolution.length; i++) {
      final item = provider.dailyEvolution[i];
      final val = double.tryParse(item['daily_revenue'].toString()) ?? 0;
      if (val > maxY) maxY = val;
      spots.add(FlSpot(i.toDouble(), val));
    }

    maxY = maxY + (maxY * 0.2);
    if (maxY == 0) maxY = 100;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Evolución de Ventas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 45,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) return const Text('');
                          return Text('\$${(value / 1000).toStringAsFixed(0)}k', style: const TextStyle(fontSize: 10, color: Colors.grey));
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: provider.dailyEvolution.length > 7 ? (provider.dailyEvolution.length / 6).ceilToDouble() : 1,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx >= 0 && idx < provider.dailyEvolution.length) {
                            final dateStr = provider.dailyEvolution[idx]['date'].toString();
                            final date = DateTime.tryParse(dateStr);
                            if (date != null) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(DateFormat('dd/MM').format(date), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                              );
                            }
                          }
                          return const Text('');
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: (provider.dailyEvolution.length - 1).toDouble(),
                  minY: 0,
                  maxY: maxY,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: const Color(0xFF1E2D45),
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: const Color(0xFF1E2D45).withValues(alpha: 0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentRow(IconData icon, String label, double amount, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
          Text('\$${amount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
