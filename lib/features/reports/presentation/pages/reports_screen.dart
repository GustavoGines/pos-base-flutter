import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import '../providers/reports_provider.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReportsProvider>().fetchProfitByCategory();
    });
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final provider = context.read<ReportsProvider>();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: provider.startDate, end: provider.endDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: ColorScheme.light(
            primary: Colors.indigo.shade800,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      provider.setDateRange(picked.start, picked.end);
      provider.fetchProfitByCategory();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlobalAppBar(currentRoute: '/reports'),
      backgroundColor: Colors.grey.shade100,
      body: Consumer<ReportsProvider>(
        builder: (context, provider, _) {
          return Column(
            children: [
              // ── Barra de filtros ─────────────────────────────────────────────
              _FiltersBar(
                provider: provider,
                onDateTap: () => _selectDateRange(context),
                onRefresh: () => provider.fetchProfitByCategory(),
              ),
              // ── Contenido ────────────────────────────────────────────────────
              Expanded(
                child: provider.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : provider.error != null
                        ? _ErrorState(message: provider.error!)
                        : provider.reportData.isEmpty
                            ? const _EmptyState()
                            : _DashboardContent(provider: provider),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Barra de filtros ─────────────────────────────────────────────────────────

class _FiltersBar extends StatelessWidget {
  final ReportsProvider provider;
  final VoidCallback onDateTap;
  final VoidCallback onRefresh;

  const _FiltersBar({
    required this.provider,
    required this.onDateTap,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Icon(Icons.bar_chart, color: Colors.blueGrey.shade700, size: 20),
          const SizedBox(width: 10),
          Text(
            'REPORTES GERENCIALES',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey.shade800,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          const Text(
            'Período: ',
            style: TextStyle(color: Colors.blueGrey, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          OutlinedButton.icon(
            onPressed: onDateTap,
            icon: const Icon(Icons.calendar_today, size: 15),
            label: Text(
              '${df.format(provider.startDate)}  →  ${df.format(provider.endDate)}',
              style: const TextStyle(fontSize: 13),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.indigo.shade800,
              side: BorderSide(color: Colors.indigo.shade200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: provider.isExporting ? null : () => provider.exportToExcel(),
            icon: provider.isExporting
                ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.file_download, size: 15),
            label: const Text('Exportar Excel'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: provider.isExportingPdf ? null : () => provider.exportToPdf(),
            icon: provider.isExportingPdf
                ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.picture_as_pdf, size: 15),
            label: const Text('Generar PDF'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            color: Colors.blueGrey.shade600,
          ),
        ],
      ),
    );
  }
}

// ─── Contenido principal del Dashboard ───────────────────────────────────────

class _DashboardContent extends StatelessWidget {
  final ReportsProvider provider;
  const _DashboardContent({required this.provider});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero Cards
          _HeroCardsRow(provider: provider),
          const SizedBox(height: 24),
          // Gráfico + Tabla
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: _ChartCard(provider: provider)),
              const SizedBox(width: 16),
              Expanded(flex: 5, child: _DetailTableCard(provider: provider)),
            ],
          ),
          const SizedBox(height: 24),
          // Gráfico Evolutivo
          _TimeSeriesChartCard(provider: provider),
        ],
      ),
    );
  }
}

// ─── Hero Cards ───────────────────────────────────────────────────────────────

class _HeroCardsRow extends StatelessWidget {
  final ReportsProvider provider;
  const _HeroCardsRow({required this.provider});

  @override
  Widget build(BuildContext context) {
    final coverage = provider.totalItems > 0
        ? (provider.totalItemsWithCost / provider.totalItems * 100).toStringAsFixed(0)
        : '0';

    return Row(
      children: [
        Expanded(
          child: _HeroCard(
            title: 'Facturación Total',
            value: '\$${provider.totalRevenue.toCurrency()}',
            icon: Icons.point_of_sale,
            color: Colors.blue.shade600,
            bgColor: Colors.blue.shade50,
            trend: provider.revenueTrendPercentage,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _HeroCard(
            title: 'Ganancia Neta',
            value: '\$${provider.totalProfit.toCurrency()}',
            icon: Icons.trending_up,
            color: Colors.green.shade600,
            bgColor: Colors.green.shade50,
            trend: provider.profitTrendPercentage,
            subtitle: provider.hasMissingCostData
                ? 'Basado en $coverage% de ítems con costo registrado'
                : null,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _HeroCard(
            title: 'Margen Promedio',
            value: '${provider.marginPercentage.toStringAsFixed(1)}%',
            icon: Icons.pie_chart,
            color: Colors.purple.shade600,
            bgColor: Colors.purple.shade50,
            subtitle: provider.hasMissingCostData
                ? 'Calculado sobre ventas con costo cargado'
                : null,
          ),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final String? subtitle;
  final double? trend;

  const _HeroCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.bgColor,
    this.subtitle,
    this.trend,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      const Spacer(),
                      if (trend != null) _TrendBadge(trend: trend!),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 12, color: Colors.orange.shade600),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            subtitle!,
                            style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Gráfico de barras ────────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  final ReportsProvider provider;
  const _ChartCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final double maxOverallProfit = provider.reportData.fold(0.0, (m, item) {
      final p = double.tryParse(item['total_profit'].toString()) ?? 0.0;
      return p > m ? p : m;
    });
    
    final bool useRevenue = maxOverallProfit <= 0;

    final topData = List.of(provider.reportData)
      ..sort((a, b) {
        final valA = double.tryParse(a[useRevenue ? 'total_revenue' : 'total_profit'].toString()) ?? 0.0;
        final valB = double.tryParse(b[useRevenue ? 'total_revenue' : 'total_profit'].toString()) ?? 0.0;
        return valB.compareTo(valA);
      });
      
    final displayData = topData.take(5).toList();
    final topValue = displayData.isEmpty
        ? 100.0
        : (double.tryParse(displayData.first[useRevenue ? 'total_revenue' : 'total_profit'].toString()) ?? 100.0);
    final maxY = topValue > 0 ? topValue * 1.2 : 100.0;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              useRevenue ? 'Top 5 Categorías por Facturación' : 'Top 5 Categorías por Ganancia Neta',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 280,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => Colors.blueGrey.shade800,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                        '\$${rod.toY.toCurrency()}',
                        const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= displayData.length) return const SizedBox.shrink();
                          final name = displayData[value.toInt()]['category_name'].toString();
                          final label = name.length > 12 ? '${name.substring(0, 10)}..' : name;
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(label, style: TextStyle(fontSize: 10, color: Colors.blueGrey.shade600)),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 65,
                        getTitlesWidget: (value, meta) => Text(
                          '\$${value.toCurrency()}',
                          style: TextStyle(fontSize: 10, color: Colors.blueGrey.shade400),
                        ),
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    horizontalInterval: maxY / 4 > 0 ? maxY / 4 : 25.0,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: Colors.grey.shade100,
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: displayData.asMap().entries.map((e) {
                    final val = double.tryParse(e.value[useRevenue ? 'total_revenue' : 'total_profit'].toString()) ?? 0.0;
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: val,
                          gradient: LinearGradient(
                            colors: useRevenue 
                                ? [Colors.blue.shade400, Colors.blue.shade600] 
                                : [Colors.green.shade400, Colors.green.shade600],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          ),
                          width: 28,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tabla de detalles ────────────────────────────────────────────────────────

class _DetailTableCard extends StatelessWidget {
  final ReportsProvider provider;
  const _DetailTableCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detalle por Categoría',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800),
            ),
            const SizedBox(height: 16),
            // Cabecera
            _TableHeader(),
            const Divider(height: 1),
            // Filas
            ...provider.reportData.map((item) {
              final revenue = double.tryParse(item['total_revenue'].toString()) ?? 0;
              final revenueWithCost = double.tryParse(item['revenue_with_cost'].toString()) ?? 0;
              final profit = double.tryParse(item['total_profit'].toString()) ?? 0;
              final qty = double.tryParse(item['items_sold'].toString()) ?? 0;
              final margin = revenueWithCost > 0 ? (profit / revenueWithCost) * 100 : 0.0;
              return _TableRow(
                category: item['category_name'].toString(),
                qty: qty.toQty(),
                revenue: '\$${revenue.toCurrency()}',
                profit: '\$${profit.toCurrency()}',
                margin: '${margin.toStringAsFixed(1)}%',
                profitColor: profit > 0 ? Colors.green.shade700 : Colors.red.shade600,
                products: item['products'] as List<dynamic>? ?? [],
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: const [
          Expanded(flex: 3, child: Text('Categoría', style: style)),
          SizedBox(width: 45, child: Text('Cant.', style: style, textAlign: TextAlign.right)),
          SizedBox(width: 90, child: Text('Facturación', style: style, textAlign: TextAlign.right)),
          SizedBox(width: 90, child: Text('Ganancia', style: style, textAlign: TextAlign.right)),
          SizedBox(width: 70, child: Text('Margen', style: style, textAlign: TextAlign.right)),
          SizedBox(width: 24), // Espacio para el icono de expandir
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  final String category;
  final String qty;
  final String revenue;
  final String profit;
  final String margin;
  final Color profitColor;
  final List<dynamic> products;

  const _TableRow({
    required this.category,
    required this.qty,
    required this.revenue,
    required this.profit,
    required this.margin,
    required this.profitColor,
    required this.products,
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
        child: Row(
          children: [
            Expanded(flex: 3, child: Text(category, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
            SizedBox(width: 45, child: Text(qty, style: const TextStyle(fontSize: 13), textAlign: TextAlign.right)),
            SizedBox(width: 90, child: Text(revenue, style: const TextStyle(fontSize: 13), textAlign: TextAlign.right)),
            SizedBox(width: 90, child: Text(profit, style: TextStyle(fontSize: 13, color: profitColor, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
            SizedBox(width: 70, child: Text(margin, style: const TextStyle(fontSize: 13), textAlign: TextAlign.right)),
            const SizedBox(width: 24),
          ],
        ),
      );
    }

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 0),
        iconColor: Colors.indigo.shade400,
        collapsedIconColor: Colors.grey.shade400,
        title: Row(
          children: [
            Expanded(flex: 3, child: Text(category, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
            SizedBox(width: 45, child: Text(qty, style: const TextStyle(fontSize: 13), textAlign: TextAlign.right)),
            SizedBox(width: 90, child: Text(revenue, style: const TextStyle(fontSize: 13), textAlign: TextAlign.right)),
            SizedBox(width: 90, child: Text(profit, style: TextStyle(fontSize: 13, color: profitColor, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
            SizedBox(width: 70, child: Text(margin, style: const TextStyle(fontSize: 13), textAlign: TextAlign.right)),
          ],
        ),
        children: products.map((prod) {
          final pName = prod['product_name'].toString();
          final pQty = double.tryParse(prod['items_sold'].toString()) ?? 0;
          final pRev = double.tryParse(prod['total_revenue'].toString()) ?? 0;
          final pRevWithCost = double.tryParse(prod['revenue_with_cost'].toString()) ?? 0;
          final pProf = double.tryParse(prod['total_profit'].toString()) ?? 0;
          final pColor = pProf > 0 ? Colors.green.shade700 : Colors.red.shade600;
          
          final pMargin = pRevWithCost > 0 ? (pProf / pRevWithCost) * 100 : 0.0;
          final marginStr = '${pMargin.toStringAsFixed(1)}%';

          return Container(
            color: Colors.grey.shade50,
            padding: const EdgeInsets.fromLTRB(16, 8, 24, 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3, 
                  child: Row(
                    children: [
                      Icon(Icons.subdirectory_arrow_right, size: 14, color: Colors.grey.shade400),
                      const SizedBox(width: 6),
                      Expanded(child: Text(pName, style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700))),
                    ],
                  ),
                ),
                SizedBox(width: 45, child: Text(pQty.toQty(), style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700), textAlign: TextAlign.right)),
                SizedBox(width: 90, child: Text('\$${pRev.toCurrency()}', style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700), textAlign: TextAlign.right)),
                SizedBox(width: 90, child: Text('\$${pProf.toCurrency()}', style: TextStyle(fontSize: 12, color: pColor, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                SizedBox(width: 70, child: Text(marginStr, style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700), textAlign: TextAlign.right)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Estados vacío y error ────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart_outlined, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No hay ventas registradas en este período.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
          const SizedBox(height: 8),
          Text('Ajustá el rango de fechas para ver los resultados.',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 56, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text('Error al cargar el reporte', style: TextStyle(color: Colors.red.shade700, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SelectableText(message, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        ],
      ),
    );
  }
}

// ─── Tendencias y Gráfico Evolutivo ──────────────────────────────────────────

class _TrendBadge extends StatelessWidget {
  final double trend;
  const _TrendBadge({required this.trend});

  @override
  Widget build(BuildContext context) {
    if (trend == 0) return const SizedBox.shrink();
    // En reportes, NaN se evalúa si fallan las divisiones sobre periodos nulos
    if (trend.isNaN || trend.isInfinite) return const SizedBox.shrink();

    final isPositive = trend > 0;
    final color = isPositive ? Colors.green.shade700 : Colors.red.shade700;
    final bgColor = isPositive ? Colors.green.shade50 : Colors.red.shade50;
    final icon = isPositive ? Icons.arrow_upward : Icons.arrow_downward;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 2),
          Text(
            '${trend.abs().toStringAsFixed(1)}%',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}

class _TimeSeriesChartCard extends StatelessWidget {
  final ReportsProvider provider;
  const _TimeSeriesChartCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final ev = provider.dailyEvolution;
    if (ev.isEmpty) return const SizedBox.shrink();

    final spots = <FlSpot>[];
    double maxRev = 0;
    for (int i = 0; i < ev.length; i++) {
      final rev = double.tryParse(ev[i]['daily_revenue'].toString()) ?? 0;
      if (rev > maxRev) maxRev = rev;
      spots.add(FlSpot(i.toDouble(), rev));
    }
    
    final maxY = maxRev > 0 ? maxRev * 1.2 : 100.0;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Evolución Diaria de Ventas',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 260,
              width: double.infinity,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxY / 4 == 0 ? 1 : maxY / 4,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Colors.grey.shade100,
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final int idx = value.toInt();
                          if (idx < 0 || idx >= ev.length) return const SizedBox.shrink();
                          if (ev.length > 20 && idx % 3 != 0 && idx != ev.length - 1) {
                            return const SizedBox.shrink();
                          }
                          final dateStr = ev[idx]['date'].toString();
                          try {
                            final date = DateTime.parse(dateStr);
                            final formatted = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(formatted, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                            );
                          } catch (_) {
                            return const SizedBox.shrink();
                          }
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: maxY / 4 == 0 ? 1 : maxY / 4,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) return const SizedBox.shrink();
                          if (value >= 1000) {
                            return Text('\$${(value / 1000).toStringAsFixed(0)}k', style: TextStyle(color: Colors.grey.shade500, fontSize: 11));
                          }
                          return Text('\$${value.toStringAsFixed(0)}', style: TextStyle(color: Colors.grey.shade500, fontSize: 11));
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: (ev.length - 1).toDouble() > 0 ? (ev.length - 1).toDouble() : 1.0,
                  minY: 0,
                  maxY: maxY,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: Colors.indigo.shade600,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: ev.length <= 31,
                        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                          radius: 3,
                          color: Colors.indigo.shade600,
                          strokeWidth: 1.5,
                          strokeColor: Colors.white,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.indigo.shade100.withOpacity(0.4),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((LineBarSpot touchedSpot) {
                          final idx = touchedSpot.x.toInt();
                          if (idx < 0 || idx >= ev.length) return null;
                          final rawDate = ev[idx]['date'];
                          try {
                             final parsed = DateTime.parse(rawDate);
                             final formatted = '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}';
                             return LineTooltipItem(
                               '$formatted\n\$${touchedSpot.y.toCurrency()}',
                               const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                             );
                          } catch (_) {
                             return LineTooltipItem('\$${touchedSpot.y.toCurrency()}', const TextStyle(color: Colors.white));
                          }
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
