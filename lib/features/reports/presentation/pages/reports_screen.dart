import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/checks/presentation/providers/check_provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';

import '../providers/reports_provider.dart';
import '../widgets/internal_consumption_report_view.dart';
import '../widgets/rubro_profit_report_view.dart';
import '../widgets/expense_analysis_tab.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with TickerProviderStateMixin {
  int _currentTabCount = 1;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    final features = context.read<SettingsProvider>().features;
    _currentTabCount = _calculateTabCount(features);

    _tabController = TabController(length: _currentTabCount, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReportsProvider>().fetchProfitByCategory();
      // Cargar cheques para el KPI de liquidez (solo si la feature está activa)
      final checksEnabled = context.read<SettingsProvider>().settings?.features.checks == true;
      if (checksEnabled) {
        context.read<CheckProvider>().loadChecks();
      }
    });
  }


  int _calculateTabCount(dynamic features) {
    // 1 base: Reportes Generales (unifica Categoría, Marcas y Ranking POS)
    int count = 1;
    if (features.multiRubro) count += 1;
    if (features.advancedReports) {
      count += 1; // Balance Mensual
      if (features.expenses) count += 1; // Análisis de Gastos
      if (features.currentAccounts) count += 1; // Consumo Interno
    }
    return count;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final features = context.watch<SettingsProvider>().features;
    final newCount = _calculateTabCount(features);
    if (newCount != _currentTabCount) {
      _currentTabCount = newCount;
      final old = _tabController;
      _tabController = TabController(length: _currentTabCount, vsync: this);
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final provider = context.read<ReportsProvider>();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: provider.startDate, end: provider.endDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'SELECCIONÁ EL RANGO DE FECHAS',
      cancelText: 'CANCELAR',
      confirmText: 'APLICAR',
      saveText: 'APLICAR',
      // 🎨 Rediseño Premium: tema indigo alineado con el Dashboard
      builder: (context, child) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          child: Theme(
            data: ThemeData.light().copyWith(
              colorScheme: ColorScheme.light(
                primary: Colors.indigo.shade700,
                onPrimary: Colors.white,
                secondary: Colors.indigo.shade400,
                onSecondary: Colors.white,
                surface: Colors.white,
                onSurface: Colors.blueGrey.shade900,
                surfaceContainerHighest: Colors.indigo.shade50,
              ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.indigo.shade700,
                  textStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ),
              datePickerTheme: DatePickerThemeData(
                backgroundColor: Colors.white,
                headerBackgroundColor: Colors.indigo.shade700,
                headerForegroundColor: Colors.white,
                dayOverlayColor: WidgetStateProperty.all(Colors.indigo.withValues(alpha: 0.1)),
                rangePickerBackgroundColor: Colors.white,
                rangeSelectionBackgroundColor: Colors.indigo.shade50,
                rangePickerHeaderBackgroundColor: Colors.indigo.shade700,
                rangePickerHeaderForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              dialogTheme: DialogThemeData(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 8,
              ),
            ),
            child: child!,
          ),
        ),
      ),
    );
    if (picked != null) {
      provider.setDateRange(picked.start, picked.end);
      provider.fetchProfitByCategory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final features = context.watch<SettingsProvider>().features;
    final hasAdvancedReports = features.advancedReports;
    final hasCurrentAccounts = features.currentAccounts;
      final hasMultiRubro = features.multiRubro;

    return Scaffold(
      appBar: const GlobalAppBar(currentRoute: '/reports'),
      backgroundColor: Colors.grey.shade100,
      body: Consumer<ReportsProvider>(
        builder: (context, provider, _) {
          return Column(
            children: [
              // ── Tab Bar ─────────────────────────────────────────────────────
              Container(
                color: Colors.white,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TabBar(
                      controller: _tabController,
                      labelColor: Colors.indigo.shade800,
                      unselectedLabelColor: Colors.blueGrey,
                      indicatorColor: Colors.indigo.shade700,
                      indicatorWeight: 3,
                      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      tabs: [
                        const Tab(icon: Icon(Icons.analytics_outlined, size: 18), text: 'Reportes Generales'),
                        if (hasMultiRubro)
                          const Tab(icon: Icon(Icons.account_tree_outlined, size: 18), text: 'Por Rubro'),
                        // 🔒 CANDADO 3: Balance Mensual y Consumo Interno solo para plan con advanced_reports
                        if (hasAdvancedReports) ...[
                          const Tab(icon: Icon(Icons.calendar_month, size: 18), text: 'Balance Mensual'),
                          if (features.expenses)
                            const Tab(icon: Icon(Icons.pie_chart, size: 18), text: 'Análisis de Gastos'),
                          if (hasCurrentAccounts)
                            const Tab(icon: Icon(Icons.inventory_2, size: 18), text: 'Consumo Interno'),
                        ]
                      ],
                    ),
                    // Filtros y selector de sub-vista en la pestaña Reportes Generales (índice 0)
                    AnimatedBuilder(
                      animation: _tabController,
                      builder: (_, __) {
                        if (_tabController.index == 0) {
                          return _FiltersBar(
                            provider: provider,
                            isBrand: provider.generalViewMode == 'brand',
                            onDateTap: () => _selectDateRange(context),
                            onRefresh: () => provider.fetchProfitByCategory(),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                ),
              ),
              // ── Contenido de pestañas ────────────────────────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab Reportes Generales (índice 0 - siempre visible)
                    provider.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : provider.error != null
                            ? _ErrorState(message: provider.error!)
                            : _DashboardContent(
                                provider: provider,
                                isBrand: provider.generalViewMode == 'brand',
                              ),
                    // Tab Por Rubro (índice 1 - solo con multi_rubro)
                    if (hasMultiRubro) const RubroProfitReportView(),
                    // Tab Balance Mensual (solo con advanced_reports)
                    if (hasAdvancedReports)
                      _MonthlyBalanceTab(provider: provider),
                    if (hasAdvancedReports && features.expenses)
                      const ExpenseAnalysisTab(),
                    // Tab Consumo Interno (solo con advanced_reports Y currentAccounts)
                    if (hasAdvancedReports && hasCurrentAccounts)
                      const InternalConsumptionReportView(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Barra de filtros y selector de sub-vista ─────────────────────────────────

class _FiltersBar extends StatelessWidget {
  final ReportsProvider provider;
  final bool isBrand;
  final VoidCallback onDateTap;
  final VoidCallback onRefresh;

  const _FiltersBar({
    required this.provider,
    this.isBrand = false,
    required this.onDateTap,
    required this.onRefresh,
  });

  Widget _buildModeSegment({
    required String mode,
    required IconData icon,
    required String label,
    required Color activeColor,
  }) {
    final selected = provider.generalViewMode == mode;
    return InkWell(
      onTap: () => provider.setGeneralViewMode(mode),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? Colors.white : Colors.blueGrey.shade700,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                color: selected ? Colors.white : Colors.blueGrey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 10,
          children: [
            // Selector segmentado de sub-vista
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Wrap(
                spacing: 4,
                children: [
                  _buildModeSegment(
                    mode: 'category',
                    icon: Icons.bar_chart_rounded,
                    label: 'Por Categoría',
                    activeColor: Colors.indigo.shade700,
                  ),
                  _buildModeSegment(
                    mode: 'brand',
                    icon: Icons.branding_watermark_outlined,
                    label: 'Por Marcas',
                    activeColor: Colors.indigo.shade700,
                  ),
                  _buildModeSegment(
                    mode: 'ranking',
                    icon: Icons.local_fire_department_rounded,
                    label: 'Ranking y Acceso Rápido POS',
                    activeColor: const Color(0xFFE65100),
                  ),
                ],
              ),
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Período: ',
                  style: TextStyle(color: Colors.blueGrey, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    final today = DateTime.now();
                    provider.setDateRange(today, today);
                    onRefresh();
                  },
                  icon: const Icon(Icons.today, size: 15),
                  label: const Text('Hoy', style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.indigo.shade600,
                    side: BorderSide(color: Colors.indigo.shade200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(width: 8),
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
                if (provider.generalViewMode != 'ranking') ...[
                  FilledButton.icon(
                    onPressed: provider.isExporting ? null : () => provider.exportToExcel(isBrand: isBrand),
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
                    onPressed: provider.isExportingPdf ? null : () => provider.exportToPdf(isBrand: isBrand),
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
                ],
                IconButton(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Actualizar',
                  color: Colors.blueGrey.shade600,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Contenido principal del Dashboard ───────────────────────────────────────

class _DashboardContent extends StatelessWidget {
  final ReportsProvider provider;
  final bool isBrand;
  const _DashboardContent({required this.provider, this.isBrand = false});

  @override
  Widget build(BuildContext context) {
    final isRankingView = provider.generalViewMode == 'ranking';
    final activeList = isBrand ? provider.brandReportData : provider.reportData;

    if (!isRankingView && activeList.isEmpty) {
      return const _EmptyState();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero Cards
          _HeroCardsRow(provider: provider),
          const SizedBox(height: 24),
          if (isRankingView) ...[
            _PosQuickAccessRankingSection(provider: provider),
          ] else ...[
            // Gráfico + Tabla
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: _ChartCard(provider: provider, isBrand: isBrand)),
                const SizedBox(width: 16),
                Expanded(flex: 5, child: _DetailTableCard(provider: provider, isBrand: isBrand)),
              ],
            ),
            const SizedBox(height: 24),
            // Gráfico Evolutivo
            _TimeSeriesChartCard(provider: provider),
          ],
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
    final settings = context.watch<SettingsProvider>().settings;
    final checksEnabled = settings?.features.checks == true;

    // Cheques proximos a cobrar (en cartera, payment_date <= hoy + 7)
    double checksThisWeekAmount = 0.0;
    int checksThisWeekCount = 0;
    if (checksEnabled) {
      final checkProvider = context.watch<CheckProvider>();
      final now = DateTime.now();
      final nextWeek = now.add(const Duration(days: 7));
      final upcoming = checkProvider.checks.where((c) =>
          c.status == 'in_wallet' &&
          !c.paymentDate.isAfter(nextWeek));
      checksThisWeekAmount = upcoming.fold(0.0, (sum, c) => sum + c.amount);
      checksThisWeekCount = upcoming.length;
    }

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
        if (checksEnabled) ...[
          const SizedBox(width: 16),
          Expanded(
            child: _HeroCard(
              title: 'Cheques a Cobrar (7 días)',
              value: '\$${checksThisWeekAmount.toCurrency()}',
              icon: Icons.account_balance_wallet,
              color: Colors.indigo.shade600,
              bgColor: Colors.indigo.shade50,
              subtitle: '$checksThisWeekCount cheque${checksThisWeekCount != 1 ? 's' : ''} próximo${checksThisWeekCount != 1 ? 's' : ''}',
            ),
          ),
        ],
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
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (trend != null) ...[
                        const SizedBox(width: 4),
                        _TrendBadge(trend: trend!),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                  ),
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
  final bool isBrand;
  const _ChartCard({required this.provider, this.isBrand = false});

  @override
  Widget build(BuildContext context) {
    final dataList = isBrand ? provider.brandReportData : provider.reportData;
    final double maxOverallProfit = dataList.fold(0.0, (m, item) {
      final p = double.tryParse(item['total_profit'].toString()) ?? 0.0;
      return p > m ? p : m;
    });
    
    final bool useRevenue = maxOverallProfit <= 0;

    final topData = List.of(dataList)
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
              useRevenue 
                  ? (isBrand ? 'Top 5 Marcas por Facturación' : 'Top 5 Categorías por Facturación') 
                  : (isBrand ? 'Top 5 Marcas por Ganancia Neta' : 'Top 5 Categorías por Ganancia Neta'),
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
  final bool isBrand;
  const _DetailTableCard({required this.provider, this.isBrand = false});

  @override
  Widget build(BuildContext context) {
    final dataList = isBrand ? provider.brandReportData : provider.reportData;

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
              isBrand ? 'Detalle por Marca' : 'Detalle por Categoría',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800),
            ),
            const SizedBox(height: 16),
            // Cabecera
            _TableHeader(isBrand: isBrand),
            const Divider(height: 1),
            // Filas
            ...dataList.map((item) {
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
  final bool isBrand;
  const _TableHeader({this.isBrand = false});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(isBrand ? 'Marca' : 'Categoría', style: style)),
          const SizedBox(width: 60, child: Text('Cant.', style: style, textAlign: TextAlign.right)),
          const SizedBox(width: 120, child: Text('Facturación', style: style, textAlign: TextAlign.right)),
          const SizedBox(width: 120, child: Text('Ganancia', style: style, textAlign: TextAlign.right)),
          const SizedBox(width: 75, child: Text('Margen', style: style, textAlign: TextAlign.right)),
          const SizedBox(width: 24), // Espacio para el icono de expandir
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
            SizedBox(width: 60, child: Text(qty, style: const TextStyle(fontSize: 13), textAlign: TextAlign.right)),
            SizedBox(width: 120, child: Text(revenue, style: const TextStyle(fontSize: 13), textAlign: TextAlign.right)),
            SizedBox(width: 120, child: Text(profit, style: TextStyle(fontSize: 13, color: profitColor, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
            SizedBox(width: 75, child: Text(margin, style: const TextStyle(fontSize: 13), textAlign: TextAlign.right)),
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
            SizedBox(width: 60, child: Text(qty, style: const TextStyle(fontSize: 13), textAlign: TextAlign.right)),
            SizedBox(width: 120, child: Text(revenue, style: const TextStyle(fontSize: 13), textAlign: TextAlign.right)),
            SizedBox(width: 120, child: Text(profit, style: TextStyle(fontSize: 13, color: profitColor, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
            SizedBox(width: 75, child: Text(margin, style: const TextStyle(fontSize: 13), textAlign: TextAlign.right)),
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
                SizedBox(width: 60, child: Text(pQty.toQty(), style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700), textAlign: TextAlign.right)),
                SizedBox(width: 120, child: Text('\$${pRev.toCurrency()}', style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700), textAlign: TextAlign.right)),
                SizedBox(width: 120, child: Text('\$${pProf.toCurrency()}', style: TextStyle(fontSize: 12, color: pColor, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                SizedBox(width: 75, child: Text(marginStr, style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700), textAlign: TextAlign.right)),
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
                          // R-W2: Densidad adaptativa — muestra ~8 etiquetas
                          // independientemente del tamaño del rango (día, mes, año).
                          final step = (ev.length / 8).round().clamp(1, ev.length);
                          final isFirst = idx == 0;
                          final isLast  = idx == ev.length - 1;
                          if (!isFirst && !isLast && idx % step != 0) {
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
                        // R-1: Reemplaza deprecated withOpacity por withValues.
                        color: Colors.indigo.shade100.withValues(alpha: 0.4),
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

// ─── Pestaña Balance Mensual ──────────────────────────────────────────────────

class _MonthlyBalanceTab extends StatefulWidget {
  final ReportsProvider provider;
  const _MonthlyBalanceTab({required this.provider});

  @override
  State<_MonthlyBalanceTab> createState() => _MonthlyBalanceTabState();
}

class _MonthlyBalanceTabState extends State<_MonthlyBalanceTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.provider.balanceMonths.isEmpty) {
        widget.provider.fetchMonthlyBalance();
      }
    });
  }

  Future<void> _pickMonth(BuildContext ctx, bool isStart) async {
    final provider = widget.provider;
    final initial = isStart ? provider.balanceStartMonth : provider.balanceEndMonth;
    DateTime picked = initial;

    await showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: Text(isStart ? 'Mes de inicio' : 'Mes de fin'),
        content: SizedBox(
          width: 320,
          child: CalendarDatePicker(
            initialDate: initial,
            firstDate: DateTime(2023),
            lastDate: DateTime.now(),
            initialCalendarMode: DatePickerMode.year,
            onDateChanged: (d) => picked = d,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );

    if (!ctx.mounted) return;

    // BUG R-3 FIX: Validar que el rango no quede invertido antes de aplicarlo.
    final pickedDate = DateTime(picked.year, picked.month);
    if (isStart) {
      if (pickedDate.isAfter(provider.balanceEndMonth)) {
        SnackBarService.warning(
            ctx, 'La fecha de inicio no puede ser posterior a la fecha de fin.');
        return;
      }
      provider.setBalanceRange(pickedDate, provider.balanceEndMonth);
    } else {
      if (pickedDate.isBefore(provider.balanceStartMonth)) {
        SnackBarService.warning(
            ctx, 'La fecha de fin no puede ser anterior a la fecha de inicio.');
        return;
      }
      provider.setBalanceRange(provider.balanceStartMonth, pickedDate);
    }
    provider.fetchMonthlyBalance();
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final mf = DateFormat('MMM yyyy');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Selectores de mes ─────────────────────────────────────────────
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month, color: Colors.indigo, size: 20),
                  const SizedBox(width: 10),
                  const Text('Período:',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () => _pickMonth(context, true),
                    icon: const Icon(Icons.arrow_drop_down, size: 16),
                    label: Text('Desde: ${mf.format(provider.balanceStartMonth)}'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.indigo.shade800,
                      side: BorderSide(color: Colors.indigo.shade200),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _pickMonth(context, false),
                    icon: const Icon(Icons.arrow_drop_down, size: 16),
                    label: Text('Hasta: ${mf.format(provider.balanceEndMonth)}'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.indigo.shade800,
                      side: BorderSide(color: Colors.indigo.shade200),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: provider.isExportingBalanceExcel ? null : () => provider.exportMonthlyBalanceToExcel(),
                    icon: provider.isExportingBalanceExcel
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
                    onPressed: provider.isExportingBalancePdf ? null : () => provider.exportMonthlyBalanceToPdf(),
                    icon: provider.isExportingBalancePdf
                        ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.picture_as_pdf, size: 15),
                    label: const Text('Generar PDF'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                  const Spacer(),
                  if (provider.isLoadingBalance)
                    const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    IconButton(
                      onPressed: () => provider.fetchMonthlyBalance(),
                      icon: const Icon(Icons.refresh, size: 18),
                      tooltip: 'Actualizar',
                      color: Colors.blueGrey.shade600,
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          if (provider.isLoadingBalance)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(48),
                    child: CircularProgressIndicator()))
          else if (provider.balanceMonths.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  children: [
                    Icon(Icons.bar_chart_outlined, size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text('Sin datos en el período seleccionado.',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
                  ],
                ),
              ),
            )
          else ...[
            // ── BarChart panorámico ─────────────────────────────────────────
            Card(
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
                    Row(
                      children: [
                        Text('Facturación vs Ganancia por Mes',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey.shade800)),
                        const Spacer(),
                        _BarLegend(color: Colors.indigo.shade400, label: 'Facturación'),
                        const SizedBox(width: 12),
                        _BarLegend(color: Colors.green.shade500, label: 'Ganancia'),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 280,
                      child: BarChart(
                        BarChartData(
                          maxY: provider.balanceMaxRevenue * 1.15,
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: provider.balanceMaxRevenue / 4 == 0
                                ? 1
                                : provider.balanceMaxRevenue / 4,
                            getDrawingHorizontalLine: (v) =>
                                FlLine(color: Colors.grey.shade100, strokeWidth: 1),
                          ),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 32,
                                getTitlesWidget: (value, meta) {
                                  final idx = value.toInt();
                                  if (idx < 0 || idx >= provider.balanceMonths.length) {
                                    return const SizedBox.shrink();
                                  }
                                  final label = provider.balanceMonths[idx]['label'].toString();
                                  // Abreviamos: "Ene 2026" → "Ene"
                                  final short = label.split(' ').first;
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(short,
                                        style: TextStyle(
                                            color: Colors.grey.shade500, fontSize: 11)),
                                  );
                                },
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 52,
                                interval: provider.balanceMaxRevenue / 4 == 0
                                    ? 1
                                    : provider.balanceMaxRevenue / 4,
                                getTitlesWidget: (value, meta) {
                                  if (value == 0) return const SizedBox.shrink();
                                  if (value >= 1000) {
                                    return Text(
                                        '\$${(value / 1000).toStringAsFixed(0)}k',
                                        style: TextStyle(
                                            color: Colors.grey.shade500, fontSize: 10));
                                  }
                                  return Text('\$${value.toStringAsFixed(0)}',
                                      style: TextStyle(
                                          color: Colors.grey.shade500, fontSize: 10));
                                },
                              ),
                            ),
                          ),
                          barGroups: provider.balanceMonths
                              .asMap()
                              .entries
                              .map((entry) {
                                final idx = entry.key;
                                final m = entry.value;
                                final rev = double.tryParse(m['total_revenue'].toString()) ?? 0;
                                final profit = double.tryParse(m['total_profit'].toString()) ?? 0;
                                return BarChartGroupData(
                                  x: idx,
                                  barRods: [
                                    BarChartRodData(
                                      toY: rev,
                                      color: Colors.indigo.shade400,
                                      width: 16,
                                      borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(4)),
                                    ),
                                    BarChartRodData(
                                      toY: profit,
                                      color: Colors.green.shade500,
                                      width: 16,
                                      borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(4)),
                                    ),
                                  ],
                                  barsSpace: 4,
                                );
                              })
                              .toList(),
                          barTouchData: BarTouchData(
                            touchTooltipData: BarTouchTooltipData(
                              // R-2: Color de fondo del tooltip en Balance Mensual
                              // (igual al del gráfico de categorías — consistencia visual).
                              getTooltipColor: (_) => Colors.blueGrey.shade800,
                              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                if (groupIndex >= provider.balanceMonths.length) return null;
                                final m = provider.balanceMonths[groupIndex];
                                final label = m['label'].toString();
                                final isRevenue = rodIndex == 0;
                                return BarTooltipItem(
                                  '${isRevenue ? "Facturación" : "Ganancia"}\n$label\n\$${rod.toY.toCurrency()}',
                                  TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: isRevenue ? FontWeight.bold : FontWeight.normal,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── KPI Cards del Balance ─────────────────────────────────────────
            Row(
              children: [
                Expanded(
                    child: _HeroCard(
                  title: 'Facturación Total',
                  value: '\$${provider.balanceTotalRevenue.toCurrency()}',
                  icon: Icons.attach_money,
                  color: Colors.indigo.shade600,
                  bgColor: Colors.indigo.shade50,
                )),
                const SizedBox(width: 16),
                Expanded(
                    child: _HeroCard(
                  title: 'Egresos Totales',
                  value: '\$${provider.balanceTotalCost.toCurrency()}',
                  icon: Icons.shopping_cart_checkout,
                  color: Colors.red.shade600,
                  bgColor: Colors.red.shade50,
                )),
                const SizedBox(width: 16),
                Expanded(
                    child: _HeroCard(
                  title: 'Ganancia Bruta Real',
                  value: '\$${(provider.balanceTotalRevenue - provider.balanceTotalCost).toCurrency()}',
                  icon: Icons.price_check,
                  color: Colors.teal.shade600,
                  bgColor: Colors.teal.shade50,
                )),
                const SizedBox(width: 16),
                Expanded(
                    child: _HeroCard(
                  title: 'Flujo de Caja Neto',
                  value: '\$${provider.balanceTotalProfit.toCurrency()}',
                  icon: Icons.trending_up,
                  color: Colors.green.shade600,
                  bgColor: Colors.green.shade50,
                )),
                const SizedBox(width: 16),
                Expanded(
                    child: _HeroCard(
                  title: 'Margen Promedio',
                  value: '${provider.balanceAvgMargin.toStringAsFixed(1)}%',
                  icon: Icons.pie_chart,
                  color: Colors.purple.shade600,
                  bgColor: Colors.purple.shade50,
                )),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BarLegend extends StatelessWidget {
  final Color color;
  final String label;
  const _BarLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600)),
      ],
    );
  }
}

// ─── Sección de Ranking de Rotación y Configurador Acceso Rápido POS ─────────

class _PosQuickAccessRankingSection extends StatefulWidget {
  final ReportsProvider provider;
  const _PosQuickAccessRankingSection({required this.provider});

  @override
  State<_PosQuickAccessRankingSection> createState() =>
      _PosQuickAccessRankingSectionState();
}

class _PosQuickAccessRankingSectionState
    extends State<_PosQuickAccessRankingSection> {
  late int _selectedDays;
  late String _selectedMetric;
  late bool _demoteOutOfStock;
  bool _initializedFromSettings = false;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedFromSettings) {
      final settings = context.read<SettingsProvider>().settings;
      _selectedDays = settings?.posPopularityDays ?? 30;
      if (!const [0, 7, 15, 30, 90].contains(_selectedDays)) {
        _selectedDays = 30;
      }
      _selectedMetric = settings?.posPopularityMetric == 'units'
          ? 'units'
          : 'tickets';
      _demoteOutOfStock = settings?.posDemoteOutOfStock ?? false;
      _searchCtrl.text = widget.provider.rankingSearchQuery;
      _initializedFromSettings = true;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleRecalibrate({required String action}) async {
    final settingsProv = context.read<SettingsProvider>();
    final catalogProv = context.read<CatalogProvider>();

    if (action == 'reset') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.cleaning_services_rounded, color: Color(0xFFE65100)),
              SizedBox(width: 10),
              Expanded(child: Text('¿Poner contadores del POS en cero?')),
            ],
          ),
          content: const Text(
            'Todos los contadores de "Más Vendidos" del Acceso Rápido volverán a 0 a partir de este momento.\n\n'
            'Es ideal al iniciar una nueva temporada comercial o al finalizar pruebas iniciales. '
            'Los reportes contables e históricos de ventas NO se ven afectados.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE65100),
              ),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Sí, poner en cero'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    try {
      final res = await widget.provider.recalibratePosPopularity(
        action: action,
        days: _selectedDays,
        metric: _selectedMetric,
        demoteOutOfStock: _demoteOutOfStock,
      );
      await settingsProv.loadSettings(isSilent: true);
      await catalogProv.refreshQuickAccessSilently(preserveVisualOrder: false);

      if (!mounted) return;
      final msg = res['message']?.toString() ??
          'Configuración de Acceso Rápido aplicada.';
      SnackBarService.success(context, msg);
    } catch (e) {
      if (!mounted) return;
      SnackBarService.error(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  Widget _buildSortPill(String label, String value, IconData icon) {
    final isSelected = widget.provider.rankingSortBy == value;
    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 15,
        color: isSelected ? Colors.white : Colors.blueGrey.shade700,
      ),
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => widget.provider.setRankingSortBy(value),
      selectedColor: Colors.indigo.shade700,
      backgroundColor: Colors.grey.shade100,
      showCheckmark: false,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
        color: isSelected ? Colors.white : Colors.blueGrey.shade800,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final ranking = provider.flatProductsRanking;
    final isBusy = provider.isRecalibratingPos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 1. Tarjeta de Configuración del Motor de Acceso Rápido POS ──
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.orange.shade200, width: 1.2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 12,
                  spacing: 12,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3CD),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFFB300)),
                          ),
                          child: const Icon(
                            Icons.local_fire_department_rounded,
                            color: Color(0xFFE65100),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Motor de Popularidad — Acceso Rápido (Terminal POS)',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey.shade900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Define cómo se ordenan las tarjetas y el Top 3 (🔥) en el mostrador de ventas.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blueGrey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: isBusy
                              ? null
                              : () => _handleRecalibrate(action: 'reset'),
                          icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                          label: const Text('Poner en Cero'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.deepOrange.shade700,
                            side: BorderSide(color: Colors.deepOrange.shade200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: isBusy
                              ? null
                              : () => _handleRecalibrate(action: 'recalibrate'),
                          icon: isBusy
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.sync_rounded, size: 17),
                          label: const Text('Guardar y Recalibrar POS Ahora'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE65100),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 24,
                  runSpacing: 16,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Selector de Ventana Móvil
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ventana Temporal del Ranking POS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.blueGrey.shade800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonHideUnderline(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: DropdownButton<int>(
                              value: _selectedDays,
                              isDense: true,
                              items: const [
                                DropdownMenuItem(
                                  value: 7,
                                  child: Text('Últimos 7 días (Semanal)',
                                      style: TextStyle(fontSize: 13)),
                                ),
                                DropdownMenuItem(
                                  value: 15,
                                  child: Text('Últimos 15 días (Quincenal)',
                                      style: TextStyle(fontSize: 13)),
                                ),
                                DropdownMenuItem(
                                  value: 30,
                                  child: Text('Últimos 30 días (Recomendado)',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                ),
                                DropdownMenuItem(
                                  value: 90,
                                  child: Text('Últimos 90 días (Trimestral)',
                                      style: TextStyle(fontSize: 13)),
                                ),
                                DropdownMenuItem(
                                  value: 0,
                                  child: Text('Histórico completo (Sin caducidad)',
                                      style: TextStyle(fontSize: 13)),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _selectedDays = v);
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Selector de Criterio (Tickets vs Unidades)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Criterio de Popularidad en Mostrador',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.blueGrey.shade800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonHideUnderline(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: DropdownButton<String>(
                              value: _selectedMetric,
                              isDense: true,
                              items: const [
                                DropdownMenuItem(
                                  value: 'tickets',
                                  child: Text(
                                    'Frecuencia por Tickets (1 ticket = 1 pto · Recomendado)',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'units',
                                  child: Text(
                                    'Volumen de Unidades / Kg vendidos',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _selectedMetric = v);
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Switch productos sin stock
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: _demoteOutOfStock,
                            activeThumbColor: const Color(0xFFE65100),
                            onChanged: (val) =>
                                setState(() => _demoteOutOfStock = val),
                          ),
                          const SizedBox(width: 6),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Relegar agotados (stock ≤ 0) al final',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blueGrey.shade800,
                                ),
                              ),
                              Text(
                                'Opcional (desactivar si vende con stock en negativo)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blueGrey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 14, color: Colors.blueGrey.shade500),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'El ranking se recalcula automáticamente en cada Cierre de Caja. Durante el turno, el orden de los botones permanece congelado para proteger la memoria muscular del cajero y los atajos Ctrl+1..9.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.blueGrey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // ── 2. Tabla Global de Rotación de Productos del Período ──
        Card(
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
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ranking de Rotación de Productos en el Período',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey.shade900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${ranking.length} producto${ranking.length == 1 ? '' : 's'} con ventas registradas entre ${DateFormat('dd/MM/yyyy').format(provider.startDate)} y ${DateFormat('dd/MM/yyyy').format(provider.endDate)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey.shade500,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      width: 280,
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: provider.setRankingSearchQuery,
                        decoration: InputDecoration(
                          hintText: 'Buscar producto, categoría o marca...',
                          hintStyle: const TextStyle(fontSize: 12.5),
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    provider.setRankingSearchQuery('');
                                  },
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Ordenar por:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.blueGrey.shade600,
                      ),
                    ),
                    _buildSortPill(
                        'Tickets (Frecuencia)', 'tickets', Icons.confirmation_number_outlined),
                    _buildSortPill(
                        'Unidades / Kg', 'units', Icons.inventory_2_outlined),
                    _buildSortPill(
                        'Facturación', 'revenue', Icons.payments_outlined),
                    _buildSortPill(
                        'Ganancia Neta', 'profit', Icons.trending_up_rounded),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                if (ranking.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        'No se encontraron productos vendidos con los filtros actuales.',
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 14),
                      ),
                    ),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 8),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 54,
                          child: Text('#',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey)),
                        ),
                        const Expanded(
                          flex: 4,
                          child: Text('Producto / Categoría · Marca',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey)),
                        ),
                        const SizedBox(
                          width: 95,
                          child: Text('Tickets',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey)),
                        ),
                        const SizedBox(
                          width: 95,
                          child: Text('Cant. Vend.',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey)),
                        ),
                        const SizedBox(
                          width: 110,
                          child: Text('Badge POS Hoy',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey)),
                        ),
                        const SizedBox(
                          width: 120,
                          child: Text('Facturación',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey)),
                        ),
                        const SizedBox(
                          width: 120,
                          child: Text('Ganancia',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey)),
                        ),
                        const SizedBox(
                          width: 75,
                          child: Text('Margen',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey)),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ...ranking.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final rank = idx + 1;
                    final item = entry.value;
                    final isTop3 = rank <= 3;
                    final pName = item['product_name'] as String;
                    final catName = item['category_name'] as String;
                    final brandName = item['brand_name'] as String;
                    final tickets = item['tickets_count'] as int;
                    final qty = item['items_sold'] as double;
                    final posCount = item['pos_sales_count'] as int;
                    final isByWeight = item['is_sold_by_weight'] as bool;
                    final rev = item['total_revenue'] as double;
                    final prof = item['total_profit'] as double;
                    final margin = item['margin_pct'] as double;

                    return Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 8),
                      decoration: BoxDecoration(
                        color: isTop3
                            ? const Color(0xFFFFFBEB).withValues(alpha: 0.55)
                            : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade100),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 54,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isTop3
                                      ? const Color(0xFFFFF3CD)
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isTop3
                                        ? const Color(0xFFFFB300)
                                        : Colors.grey.shade300,
                                  ),
                                ),
                                child: Text(
                                  isTop3 ? '🔥 #$rank' : '#$rank',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: isTop3
                                        ? const Color(0xFFB45309)
                                        : Colors.blueGrey.shade700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        pName,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isByWeight) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade100,
                                          borderRadius:
                                              BorderRadius.circular(5),
                                        ),
                                        child: Text(
                                          '⚖️ Kg',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.orange.shade900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$catName · $brandName',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blueGrey.shade500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 95,
                            child: Text(
                              '$tickets ticket${tickets == 1 ? '' : 's'}',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.indigo.shade700,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 95,
                            child: Text(
                              isByWeight ? '${qty.toQty()} kg' : qty.toQty(),
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                          SizedBox(
                            width: 110,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: posCount > 0
                                      ? Colors.blue.shade50
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: posCount > 0
                                        ? Colors.blue.shade200
                                        : Colors.grey.shade300,
                                  ),
                                ),
                                child: Text(
                                  posCount > 0
                                      ? '⚡ $posCount vend.'
                                      : '0 vend.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: posCount > 0
                                        ? Colors.blue.shade800
                                        : Colors.grey.shade500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child: Text(
                              '\$${rev.toCurrency()}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child: Text(
                              '\$${prof.toCurrency()}',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: prof >= 0
                                    ? Colors.green.shade700
                                    : Colors.red.shade600,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 75,
                            child: Text(
                              '${margin.toStringAsFixed(1)}%',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}