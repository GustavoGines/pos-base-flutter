import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/reports_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class RubroProfitReportView extends StatefulWidget {
  const RubroProfitReportView({super.key});

  @override
  State<RubroProfitReportView> createState() => _RubroProfitReportViewState();
}

enum _RubroSortColumn { rubro, quantity, revenue, profit, margin }

class _RubroProfitReportViewState extends State<RubroProfitReportView> {
  static const Color _emeraldGreen = Color(0xFF10B981);
  List<int> _selectedRubroIds = [];
  int _pieTouchedIndex = -1;
  final Set<String> _expandedRubros = {};
  final Map<int, String> _availableRubros = {};
  final Map<String, int> _visibleProductsCount = {};
  DateTime? _lastLoadedStartDate;
  DateTime? _lastLoadedEndDate;

  _RubroSortColumn _currentSortColumn = _RubroSortColumn.revenue;
  bool _sortAscending = false;

  final List<Color> _chartColors = const [
    Color(0xFF3B82F6), // Blue
    Color(0xFF10B981), // Emerald
    Color(0xFFF59E0B), // Amber
    Color(0xFF8B5CF6), // Purple
    Color(0xFFEC4899), // Pink
    Color(0xFF06B6D4), // Cyan
    Color(0xFFF97316), // Orange
    Color(0xFF64748B), // Slate
  ];

  @override
  void initState() {
    super.initState();
    final provider = context.read<ReportsProvider>();
    _lastLoadedStartDate = provider.startDate;
    _lastLoadedEndDate = provider.endDate;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        context.read<CatalogProvider>().loadRubros();
      } catch (_) {}
      final hasMultiRubro = context.read<SettingsProvider>().features.multiRubro;
      if (hasMultiRubro) {
        context.read<ReportsProvider>().fetchProfitByRubro(rubroFilter: _selectedRubroIds.isEmpty ? null : _selectedRubroIds);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hasMultiRubro = context.watch<SettingsProvider>().features.multiRubro;
    if (!hasMultiRubro) return;

    final provider = context.watch<ReportsProvider>();
    if (_lastLoadedStartDate != provider.startDate || _lastLoadedEndDate != provider.endDate) {
      _lastLoadedStartDate = provider.startDate;
      _lastLoadedEndDate = provider.endDate;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<ReportsProvider>().fetchProfitByRubro(rubroFilter: _selectedRubroIds.isEmpty ? null : _selectedRubroIds);
        }
      });
    }
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
      _lastLoadedStartDate = picked.start;
      _lastLoadedEndDate = picked.end;
      provider.setDateRange(picked.start, picked.end);
      provider.fetchProfitByCategory();
      provider.fetchProfitByRubro(rubroFilter: _selectedRubroIds.isEmpty ? null : _selectedRubroIds);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMultiRubro = context.watch<SettingsProvider>().features.multiRubro;

    // GATING: Si el usuario está en el plan Básico, bloqueamos la vista completamente
    if (!hasMultiRubro) {
      return _buildPremiumLockedCard(context);
    }

    return Consumer<ReportsProvider>(
      builder: (context, provider, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 600;
            return SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 12 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Barra de filtros y acciones
                  _buildFilterBar(context, provider, isMobile),
                  const SizedBox(height: 20),

              if (provider.isLoadingRubro)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (provider.rubroError != null && provider.rubroReportData.isEmpty)
                _buildErrorCard(provider.rubroError!, () {
                  provider.fetchProfitByRubro(rubroFilter: _selectedRubroIds.isEmpty ? null : _selectedRubroIds);
                })
              else if (provider.rubroReportData.isEmpty)
                _buildEmptyCard()
              else ...[
                if (provider.rubroError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _buildErrorCard(provider.rubroError!, () {
                      provider.fetchProfitByRubro(rubroFilter: _selectedRubroIds.isEmpty ? null : _selectedRubroIds);
                    }),
                  ),
                // KPI Cards
                _buildKpiRow(provider),
                const SizedBox(height: 24),

                // Gráficos analíticos con fl_chart
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 950;
                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: _buildBarChartCard(provider)),
                          const SizedBox(width: 16),
                          Expanded(flex: 4, child: _buildPieChartCard(provider)),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        _buildBarChartCard(provider),
                        const SizedBox(height: 16),
                        _buildPieChartCard(provider),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Tabla Detallada por Rubro y Productos
                _buildDetailTableCard(provider),
              ],
            ],
          ),
        );
          },
        );
      },
    );
  }

  // ─── Tarjeta de Bloqueo Premium ───────────────────────────────────────────

  Widget _buildPremiumLockedCard(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.amber.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 15,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_person_rounded, size: 48, color: Colors.amber.shade800),
            ),
            const SizedBox(height: 20),
            Text(
              'Rentabilidad por Rubro',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade900),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'MÓDULO PREMIUM (MULTI-RUBRO)',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'El análisis financiero avanzado y los gráficos comparativos de ganancias por rubro '
              'requieren una licencia con la característica Multi-Rubro activada.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade600, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                SnackBarService.warning(context, 'Para activar Multi-Rubro, solicite un upgrade a su proveedor de licencia.');
              },
              icon: const Icon(Icons.workspace_premium, size: 18),
              label: const Text('Consultar Upgrade de Licencia'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.indigo.shade700,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Barra de Filtros ──────────────────────────────────────────────────────

    Future<void> _openMultiSelect(BuildContext context, ReportsProvider provider, List<Map<String, dynamic>> rubrosList) async {
    final tempSelected = List<int>.from(_selectedRubroIds);
    final result = await showDialog<List<int>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: const Text('Filtrar por Rubros'),
              content: SizedBox(
                width: 300,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CheckboxListTile(
                        title: const Text('Todos los Rubros', style: TextStyle(fontWeight: FontWeight.bold)),
                        value: tempSelected.isEmpty,
                        onChanged: (val) {
                          if (val == true) {
                            setState(() {
                              tempSelected.clear();
                            });
                          }
                        },
                      ),
                      const Divider(),
                      ...rubrosList.map((r) {
                        final id = r['id'] as int;
                        return CheckboxListTile(
                          title: Text(r['name'] as String),
                          value: tempSelected.contains(id),
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                tempSelected.add(id);
                              } else {
                                tempSelected.remove(id);
                              }
                            });
                          },
                        );
                      }),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, tempSelected),
                  child: const Text('Aplicar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        _selectedRubroIds = result;
      });
      provider.setRubroFilter(_selectedRubroIds.isEmpty ? null : _selectedRubroIds);
      provider.fetchProfitByRubro(rubroFilter: _selectedRubroIds.isEmpty ? null : _selectedRubroIds);
    }
  }

  Widget _buildFilterBar(BuildContext context, ReportsProvider provider, bool isMobile) {
    final df = DateFormat('dd/MM/yyyy');
    final dateRangeStr = '${df.format(provider.startDate)} - ${df.format(provider.endDate)}';

    // Acumular rubros desde CatalogProvider si está disponible
    try {
      final catalog = context.read<CatalogProvider>();
      for (final r in catalog.rubros) {
        _availableRubros[r.id] = r.name;
      }
    } catch (_) {}

    // Acumular rubros descubiertos en las respuestas de reportes
    for (final item in provider.rubroReportData) {
      final name = item['rubro_name']?.toString() ?? item['category_name']?.toString() ?? '';
      final id = item['rubro_id'] != null ? int.tryParse(item['rubro_id'].toString()) : null;
      if (id != null && name.isNotEmpty && name != 'Sin Rubro') {
        _availableRubros[id] = name;
      }
    }

    final rubrosList = _availableRubros.entries
        .map((e) => {'id': e.key, 'name': e.value})
        .toList()
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16, vertical: 12),
        child: Wrap(
          spacing: 12,
          runSpacing: 10,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Selector de Fecha
                OutlinedButton.icon(
                  onPressed: () => _selectDateRange(context),
                  icon: const Icon(Icons.date_range, size: 16),
                  label: Text(dateRangeStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.indigo.shade800,
                    side: BorderSide(color: Colors.indigo.shade200),
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),

                // Selector Multi-Rubro
                Container(
                  constraints: BoxConstraints(maxWidth: isMobile ? 240 : 260),
                  child: OutlinedButton.icon(
                    onPressed: () => _openMultiSelect(context, provider, rubrosList),
                    icon: const Icon(Icons.filter_list, size: 16),
                    label: Text(
                      _selectedRubroIds.isEmpty 
                        ? 'Todos los Rubros' 
                        : '${_selectedRubroIds.length} Rubros seleccionados',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.indigo.shade800,
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                
                IconButton(
                  onPressed: () => provider.fetchProfitByRubro(rubroFilter: _selectedRubroIds.isEmpty ? null : _selectedRubroIds),
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Actualizar reporte',
                  color: Colors.blueGrey.shade600,
                ),
              ],
            ),

            // Botones de Exportación
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: provider.isExporting ? null : () => provider.exportRubroToExcel(rubroFilter: _selectedRubroIds.isEmpty ? null : _selectedRubroIds),
                  icon: provider.isExporting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.file_download, size: 15),
                  label: const Text('Exportar Excel', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                FilledButton.icon(
                  onPressed: provider.isExportingPdf ? null : () => provider.exportRubroToPdf(rubroFilter: _selectedRubroIds.isEmpty ? null : _selectedRubroIds),
                  icon: provider.isExportingPdf
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.picture_as_pdf, size: 15),
                  label: const Text('Generar PDF', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── KPI Summary Cards ────────────────────────────────────────────────────

  Widget _buildKpiRow(ReportsProvider provider) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 750;
        final cards = [
          _buildKpiCard(
            title: 'Facturación Total',
            value: '\$${provider.rubroTotalRevenue.toCurrency()}',
            icon: Icons.point_of_sale,
            color: Colors.blue.shade600,
            bgColor: Colors.blue.shade50,
          ),
          _buildKpiCard(
            title: 'Ganancia Neta',
            value: '\$${provider.rubroTotalProfit.toCurrency()}',
            icon: Icons.trending_up,
            color: Colors.green.shade600,
            bgColor: Colors.green.shade50,
          ),
          _buildKpiCard(
            title: 'Margen Promedio',
            value: '${provider.rubroMarginPercentage.toStringAsFixed(1)}%',
            icon: Icons.pie_chart,
            color: Colors.purple.shade600,
            bgColor: Colors.purple.shade50,
          ),
          _buildKpiCard(
            title: 'Ítems Vendidos',
            value: provider.rubroTotalQuantitySold > 0 ? provider.rubroTotalQuantitySold.toQty() : '${provider.rubroTotalItemsSold}',
            icon: Icons.shopping_bag,
            color: Colors.orange.shade600,
            bgColor: Colors.orange.shade50,
          ),
        ];

        if (isNarrow) {
          return GridView.count(
            crossAxisCount: constraints.maxWidth < 450 ? 1 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.2,
            children: cards,
          );
        }

        return Row(
          children: cards
              .map((c) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: c,
                    ),
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.5),
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

  // ─── Gráfico de Barras Comparativo (fl_chart) ─────────────────────────────

  Widget _buildBarChartCard(ReportsProvider provider) {
    final data = provider.rubroReportData;
    final topData = data.take(8).toList();

    double maxVal = 0.0;
    double minVal = 0.0;
    for (final item in topData) {
      final rev = double.tryParse(item['total_revenue']?.toString() ?? '0') ?? 0.0;
      final prof = double.tryParse(item['total_profit']?.toString() ?? '0') ?? 0.0;
      if (rev > maxVal) maxVal = rev;
      if (prof > maxVal) maxVal = prof;
      if (prof < minVal) minVal = prof;
      if (rev < minVal) minVal = rev;
    }
    final maxY = maxVal > 0 ? maxVal * 1.25 : 100.0;
    final minY = minVal < 0 ? minVal * 1.25 : 0.0;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Comparativa de Facturación vs Ganancia por Rubro',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800),
                ),
                Wrap(
                  spacing: 12,
                  children: [
                    _buildLegendItem(color: Colors.indigo.shade600, label: 'Facturación'),
                    _buildLegendItem(color: _emeraldGreen, label: 'Ganancia Neta'),
                    if (minVal < 0)
                      _buildLegendItem(color: Colors.red.shade600, label: 'Pérdida Neta'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 260,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY,
                  minY: minY,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => Colors.blueGrey.shade900,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final idx = group.x.toInt();
                        if (idx < 0 || idx >= topData.length) return null;
                        final item = topData[idx];
                        final rubroName = item['rubro_name']?.toString() ?? item['category_name']?.toString() ?? '';
                        final isRevenue = rodIndex == 0;
                        final type = isRevenue ? 'Facturación' : (rod.toY < 0 ? 'Pérdida Neta' : 'Ganancia Neta');
                        return BarTooltipItem(
                          '$rubroName\n$type: \$${rod.toY.toCurrency()}',
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 56,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) return const SizedBox.shrink();
                          return Text(
                            '\$${_formatCompactCurrency(value)}',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value % 1 != 0) return const SizedBox.shrink();
                          final idx = value.toInt();
                          if (idx >= 0 && idx < topData.length) {
                            final name = topData[idx]['rubro_name']?.toString() ?? topData[idx]['category_name']?.toString() ?? '';
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                name.length > 10 ? '${name.substring(0, 8)}..' : name,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blueGrey.shade700),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.shade100, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(topData.length, (i) {
                    final item = topData[i];
                    final rev = double.tryParse(item['total_revenue']?.toString() ?? '0') ?? 0.0;
                    final prof = double.tryParse(item['total_profit']?.toString() ?? '0') ?? 0.0;
                    final isProfNegative = prof < 0;
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: rev,
                          color: Colors.indigo.shade600,
                          width: 14,
                          borderRadius: rev < 0
                              ? const BorderRadius.vertical(bottom: Radius.circular(4))
                              : const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                        BarChartRodData(
                          toY: prof,
                          color: isProfNegative ? Colors.red.shade600 : _emeraldGreen,
                          width: 14,
                          borderRadius: isProfNegative
                              ? const BorderRadius.vertical(bottom: Radius.circular(4))
                              : const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Gráfico de Torta / Distribución (fl_chart) ───────────────────────────

  Widget _buildPieChartCard(ReportsProvider provider) {
    final data = provider.rubroReportData;
    final totalRev = provider.rubroTotalRevenue;

    final positiveItems = data.where((item) {
      final rev = double.tryParse(item['total_revenue']?.toString() ?? '0') ?? 0.0;
      return rev > 0;
    }).toList();

    List<Map<String, dynamic>> chartItems = positiveItems
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (positiveItems.length > 8) {
      final top7 = positiveItems.take(7).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final others = positiveItems.skip(7);
      final othersRev = others.fold(
          0.0,
          (sum, it) =>
              sum + (double.tryParse(it['total_revenue']?.toString() ?? '0') ?? 0.0));
      chartItems = [
        ...top7,
        {
          'rubro_name': 'Otros (${positiveItems.length - 7})',
          'total_revenue': othersRev,
        }
      ];
    }

    final pieTotalRev = chartItems.fold<double>(
        0.0,
        (sum, it) =>
            sum + (double.tryParse(it['total_revenue']?.toString() ?? '0') ?? 0.0));

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Distribución de Facturación por Rubro',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800),
            ),
            const SizedBox(height: 16),
            totalRev <= 0 || chartItems.isEmpty
                ? Container(
                    height: 260,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.pie_chart_outline, size: 40, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text(
                          'Sin facturación para graficar distribución',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                : SizedBox(
                    height: 260,
                    child: PieChart(
                      PieChartData(
                        pieTouchData: PieTouchData(
                          touchCallback: (FlTouchEvent event, pieTouchResponse) {
                            setState(() {
                              if (!event.isInterestedForInteractions ||
                                  pieTouchResponse == null ||
                                  pieTouchResponse.touchedSection == null) {
                                _pieTouchedIndex = -1;
                                return;
                              }
                              _pieTouchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                            });
                          },
                        ),
                        borderData: FlBorderData(show: false),
                        sectionsSpace: 2,
                        centerSpaceRadius: 50,
                        sections: List.generate(chartItems.length, (i) {
                          final isTouched = i == _pieTouchedIndex;
                          final item = chartItems[i];
                          final rev = double.tryParse(item['total_revenue']?.toString() ?? '0') ?? 0.0;
                          final pct = pieTotalRev > 0 ? (rev / pieTotalRev) * 100 : 0.0;
                          final color = _chartColors[i % _chartColors.length];
                          final radius = isTouched ? 65.0 : 55.0;

                          return PieChartSectionData(
                            color: color,
                            value: rev,
                            title: pct >= 5 ? '${pct.toStringAsFixed(0)}%' : '',
                            radius: radius,
                            titleStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
            if (chartItems.isNotEmpty) ...[
              const SizedBox(height: 16),
              // Leyenda de Rubros
              Wrap(
                spacing: 10,
                runSpacing: 6,
                children: List.generate(chartItems.length, (i) {
                  final item = chartItems[i];
                  final name = item['rubro_name']?.toString() ?? item['category_name']?.toString() ?? '';
                  final color = _chartColors[i % _chartColors.length];
                  return _buildLegendItem(color: color, label: name);
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Lógica de Ordenamiento ────────────────────────────────────────────────

  void _onSortColumnTapped(_RubroSortColumn column) {
    setState(() {
      if (_currentSortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _currentSortColumn = column;
        _sortAscending = column == _RubroSortColumn.rubro;
      }
    });
  }

  List<Map<String, dynamic>> _getSortedData(List<dynamic> rawData) {
    final list = List<Map<String, dynamic>>.from(
      rawData.map((e) => Map<String, dynamic>.from(e as Map)),
    );
    list.sort((a, b) {
      int result;
      switch (_currentSortColumn) {
        case _RubroSortColumn.rubro:
          final nameA = (a['rubro_name'] ?? a['category_name'] ?? '').toString().toLowerCase();
          final nameB = (b['rubro_name'] ?? b['category_name'] ?? '').toString().toLowerCase();
          result = nameA.compareTo(nameB);
          break;
        case _RubroSortColumn.quantity:
          final qA = double.tryParse(a['items_sold']?.toString() ?? '0') ?? 0.0;
          final qB = double.tryParse(b['items_sold']?.toString() ?? '0') ?? 0.0;
          result = qA.compareTo(qB);
          break;
        case _RubroSortColumn.revenue:
          final rA = double.tryParse(a['total_revenue']?.toString() ?? '0') ?? 0.0;
          final rB = double.tryParse(b['total_revenue']?.toString() ?? '0') ?? 0.0;
          result = rA.compareTo(rB);
          break;
        case _RubroSortColumn.profit:
          final pA = double.tryParse(a['total_profit']?.toString() ?? '0') ?? 0.0;
          final pB = double.tryParse(b['total_profit']?.toString() ?? '0') ?? 0.0;
          result = pA.compareTo(pB);
          break;
        case _RubroSortColumn.margin:
          final pA = double.tryParse(a['total_profit']?.toString() ?? '0') ?? 0.0;
          final rwcA = double.tryParse(a['revenue_with_cost']?.toString() ?? '0') ?? 0.0;
          final mA = rwcA > 0 ? (pA / rwcA) * 100 : 0.0;

          final pB = double.tryParse(b['total_profit']?.toString() ?? '0') ?? 0.0;
          final rwcB = double.tryParse(b['revenue_with_cost']?.toString() ?? '0') ?? 0.0;
          final mB = rwcB > 0 ? (pB / rwcB) * 100 : 0.0;

          result = mA.compareTo(mB);
          break;
      }
      return _sortAscending ? result : -result;
    });
    return list;
  }

  // ─── Tabla Detallada ──────────────────────────────────────────────────────

  Widget _buildDetailTableCard(ReportsProvider provider) {
    final data = _getSortedData(provider.rubroReportData);

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  'Desglose por Rubro y Productos',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade900),
                ),
                Text(
                  '${data.length} rubros registrados',
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, tableConstraints) {
                final tableWidth = tableConstraints.maxWidth > 550 ? tableConstraints.maxWidth : 550.0;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTableHeader(),
                        const Divider(height: 1),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: data.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                          itemBuilder: (context, index) {
                            final item = data[index];
                            final rubroName = item['rubro_name']?.toString() ?? item['category_name']?.toString() ?? 'Sin Rubro';
                            final rev = double.tryParse(item['total_revenue']?.toString() ?? '0') ?? 0.0;
                            final prof = double.tryParse(item['total_profit']?.toString() ?? '0') ?? 0.0;
                            final qty = double.tryParse(item['items_sold']?.toString() ?? '0') ?? 0.0;
                            final rwc = double.tryParse(item['revenue_with_cost']?.toString() ?? '0') ?? 0.0;
                            final margin = rwc > 0 ? (prof / rwc) * 100 : 0.0;
                            final products = (item['products'] as List? ?? [])
                                .map((e) => Map<String, dynamic>.from(e as Map))
                                .toList();
                            final isExpanded = _expandedRubros.contains(rubroName);
                            final maxVisible = _visibleProductsCount[rubroName] ?? 25;
                            final displayProducts = products.take(maxVisible).toList();

                            return Column(
                              children: [
                                InkWell(
                                  key: ValueKey('rubro_row_$rubroName'),
                                  onTap: () {
                                    setState(() {
                                      if (isExpanded) {
                                        _expandedRubros.remove(rubroName);
                                      } else {
                                        _expandedRubros.add(rubroName);
                                      }
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                                          size: 20,
                                          color: Colors.blueGrey.shade400,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            rubroName,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            '${qty.toQty()} uds.',
                                            textAlign: TextAlign.right,
                                            style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            '\$${rev.toCurrency()}',
                                            textAlign: TextAlign.right,
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            '\$${prof.toCurrency()}',
                                            textAlign: TextAlign.right,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: prof >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            margin: const EdgeInsets.only(left: 8),
                                            decoration: BoxDecoration(
                                              color: margin >= 20
                                                  ? Colors.green.shade50
                                                  : (margin >= 0 ? Colors.orange.shade50 : Colors.red.shade50),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '${margin.toStringAsFixed(1)}%',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                                color: margin >= 20
                                                    ? Colors.green.shade800
                                                    : (margin >= 0 ? Colors.orange.shade800 : Colors.red.shade800),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (isExpanded && products.isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(left: 28, bottom: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.grey.shade200),
                                    ),
                                    child: Column(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                                          child: Row(
                                            children: const [
                                              Expanded(flex: 3, child: Text('Producto', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey))),
                                              Expanded(flex: 2, child: Text('Cant.', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey), textAlign: TextAlign.right)),
                                              Expanded(flex: 3, child: Text('Facturación', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey), textAlign: TextAlign.right)),
                                              Expanded(flex: 3, child: Text('Ganancia', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey), textAlign: TextAlign.right)),
                                              Expanded(flex: 2, child: Text('Margen', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey), textAlign: TextAlign.center)),
                                            ],
                                          ),
                                        ),
                                        const Divider(height: 1),
                                        ...displayProducts.map((prod) {
                                          final pName = prod['product_name']?.toString() ?? '';
                                          final pRev = double.tryParse(prod['total_revenue']?.toString() ?? '0') ?? 0.0;
                                          final pProf = double.tryParse(prod['total_profit']?.toString() ?? '0') ?? 0.0;
                                          final pQty = double.tryParse(prod['items_sold']?.toString() ?? '0') ?? 0.0;
                                          final pRwc = double.tryParse(prod['revenue_with_cost']?.toString() ?? '0') ?? 0.0;
                                          final pMargin = pRwc > 0 ? (pProf / pRwc) * 100 : 0.0;
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 4),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  flex: 3,
                                                  child: Text('• $pName', style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade800)),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Text('${pQty.toQty()} uds.', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600)),
                                                ),
                                                Expanded(
                                                  flex: 3,
                                                  child: Text('\$${pRev.toCurrency()}', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade800)),
                                                ),
                                                Expanded(
                                                  flex: 3,
                                                  child: Text('\$${pProf.toCurrency()}', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: pProf >= 0 ? Colors.green.shade700 : Colors.red.shade700)),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Text(
                                                    pRwc > 0 ? '${pMargin.toStringAsFixed(1)}%' : '-',
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                      color: pMargin >= 20 ? Colors.green.shade800 : (pMargin >= 0 ? Colors.orange.shade800 : Colors.red.shade800),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                        if (products.length > 25)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 8),
                                            child: Wrap(
                                              alignment: WrapAlignment.center,
                                              spacing: 12,
                                              runSpacing: 4,
                                              children: [
                                                if (maxVisible < products.length)
                                                  TextButton.icon(
                                                    onPressed: () {
                                                      setState(() {
                                                        _visibleProductsCount[rubroName] = maxVisible + 25;
                                                      });
                                                    },
                                                    icon: const Icon(Icons.expand_more, size: 16),
                                                    label: Text('Ver 25 más ($maxVisible de ${products.length})'),
                                                  ),
                                                if (maxVisible < products.length)
                                                  TextButton(
                                                    onPressed: () {
                                                      setState(() {
                                                        _visibleProductsCount[rubroName] = products.length;
                                                      });
                                                    },
                                                    child: Text('Ver todos (${products.length})'),
                                                  ),
                                                if (maxVisible > 25)
                                                  TextButton.icon(
                                                    onPressed: () {
                                                      setState(() {
                                                        _visibleProductsCount[rubroName] = 25;
                                                      });
                                                    },
                                                    icon: const Icon(Icons.expand_less, size: 16),
                                                    label: const Text('Mostrar menos (primeros 25)'),
                                                  ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─── Helpers Visuales ─────────────────────────────────────────────────────

  Widget _buildTableHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          const SizedBox(width: 28),
          _buildSortableHeaderItem(label: 'Rubro', column: _RubroSortColumn.rubro, flex: 3, textAlign: TextAlign.left),
          _buildSortableHeaderItem(label: 'Cant.', column: _RubroSortColumn.quantity, flex: 2, textAlign: TextAlign.right),
          _buildSortableHeaderItem(label: 'Facturación', column: _RubroSortColumn.revenue, flex: 3, textAlign: TextAlign.right),
          _buildSortableHeaderItem(label: 'Ganancia', column: _RubroSortColumn.profit, flex: 3, textAlign: TextAlign.right),
          _buildSortableHeaderItem(label: 'Margen', column: _RubroSortColumn.margin, flex: 2, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildSortableHeaderItem({
    required String label,
    required _RubroSortColumn column,
    required int flex,
    TextAlign textAlign = TextAlign.right,
  }) {
    final isActive = _currentSortColumn == column;
    return Expanded(
      flex: flex,
      child: Tooltip(
        message: 'Ordenar por $label (${isActive && _sortAscending ? 'Ascendente' : 'Descendente'})',
        child: InkWell(
          key: ValueKey('header_sort_${column.name}'),
          onTap: () => _onSortColumnTapped(column),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              mainAxisAlignment: textAlign == TextAlign.left
                  ? MainAxisAlignment.start
                  : (textAlign == TextAlign.center ? MainAxisAlignment.center : MainAxisAlignment.end),
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isActive ? Colors.indigo.shade800 : Colors.blueGrey,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(width: 2),
                  Icon(
                    _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 13,
                    color: Colors.indigo.shade800,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.blueGrey.shade700)),
      ],
    );
  }

  Widget _buildEmptyCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                'No se encontraron ventas para los rubros en el período seleccionado.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard(String error, VoidCallback onRetry) {
    return Card(
      elevation: 0,
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Error al cargar el reporte por rubro: $error',
                style: TextStyle(color: Colors.red.shade800, fontSize: 13),
              ),
            ),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCompactCurrency(double value) {
    final abs = value.abs();
    final sign = value < 0 ? '-' : '';
    if (abs >= 1000000) return '$sign${(abs / 1000000).toStringAsFixed(1)}M';
    if (abs >= 1000) return '$sign${(abs / 1000).toStringAsFixed(0)}k';
    return '$sign${abs.toStringAsFixed(0)}';
  }
}
