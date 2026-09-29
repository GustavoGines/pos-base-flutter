import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/utils/currency_formatter.dart';

class ExpenseAnalysisTab extends StatefulWidget {
  const ExpenseAnalysisTab({super.key});

  @override
  State<ExpenseAnalysisTab> createState() => _ExpenseAnalysisTabState();
}

class _ExpenseAnalysisTabState extends State<ExpenseAnalysisTab> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _analysisData = [];
  double _totalExpenses = 0.0;

  int _touchedIndex = -1;

  // Filtros avanzados
  bool _includeSuppliers = true;
  String? _selectedPaymentMethod;
  final TextEditingController _minAmountController = TextEditingController();
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _minAmountController.dispose();
    super.dispose();
  }

  String _buildQueryParams(String start, String end) {
    final buffer = StringBuffer('start_date=$start&end_date=$end&include_suppliers=$_includeSuppliers');
    if (_selectedPaymentMethod != null && _selectedPaymentMethod!.isNotEmpty) {
      buffer.write('&payment_method=$_selectedPaymentMethod');
    }
    final minAmount = _minAmountController.text.trim();
    if (minAmount.isNotEmpty) {
      buffer.write('&min_amount=${Uri.encodeComponent(minAmount)}');
    }
    return buffer.toString();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;
      final start = DateFormat('yyyy-MM-dd').format(_startDate);
      final end = DateFormat('yyyy-MM-dd').format(_endDate);
      final queryParams = _buildQueryParams(start, end);

      final client = context.read<ApiClient>();
      final response = await client.get(
        Uri.parse('$baseUrl/reports/expenses-analysis?$queryParams'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
          _analysisData = List<Map<String, dynamic>>.from(data['by_category'] ?? []);
          _totalExpenses = double.tryParse(data['total_expenses'].toString()) ?? 0.0;
          _isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _error = 'Error HTTP: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error de conexión: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _export(String type) async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;
    final start = DateFormat('yyyy-MM-dd').format(_startDate);
    final end = DateFormat('yyyy-MM-dd').format(_endDate);
    final queryParams = _buildQueryParams(start, end);
    
    final urlStr = '$baseUrl/reports/expenses-analysis/$type?$queryParams';

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Generando ${type.toUpperCase()}...')));
      }
      
      final client = context.read<ApiClient>();
      final response = await client.get(
        Uri.parse(urlStr),
        headers: {'Accept': type == 'pdf' ? 'application/pdf' : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'},
      );

      if (response.statusCode == 200) {
        final docsDir = await getApplicationDocumentsDirectory();
        final sep = Platform.pathSeparator;
        final exportDir = Directory('${docsDir.path}${sep}Sistema_POS${sep}Exportaciones');
        if (!await exportDir.exists()) {
          await exportDir.create(recursive: true);
        }

        final fileName = 'analisis_gastos_${DateTime.now().millisecondsSinceEpoch}.${type == 'pdf' ? 'pdf' : 'xlsx'}';
        final file = File('${exportDir.path}$sep$fileName');
        await file.writeAsBytes(response.bodyBytes);

        if (Platform.isWindows) {
          try {
            await Process.run('explorer.exe', ['/select,', file.path]);
          } catch (_) {}
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Archivo exportado correctamente: $fileName'),
              backgroundColor: Colors.green.shade700,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al exportar: HTTP ${response.statusCode}')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al descargar archivo: $e')));
      }
    }
  }

  Future<void> _exportExcel() => _export('export');
  Future<void> _exportPdf() => _export('pdf');

  void _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          child: child,
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _fetchData();
    }
  }

  // Colores para el gráfico
  final List<Color> _chartColors = [
    Colors.red.shade400,
    Colors.orange.shade400,
    Colors.amber.shade400,
    Colors.green.shade400,
    Colors.blue.shade400,
    Colors.purple.shade400,
    Colors.teal.shade400,
    Colors.indigo.shade400,
  ];

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(onPressed: _fetchData, child: const Text('Reintentar')),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Filtro de Fechas, Filtros Avanzados y Acciones
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.of(context).size.width < 500 ? 12 : 24,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      const Icon(Icons.date_range, color: Colors.blueGrey, size: 20),
                      Text(
                        'Desde ${DateFormat('dd/MM/yyyy').format(_startDate)} hasta ${DateFormat('dd/MM/yyyy').format(_endDate)}',
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.blueGrey),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.filter_alt_outlined, size: 16),
                        label: const Text('Cambiar Período'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.indigo.shade600,
                          side: BorderSide(color: Colors.indigo.shade200),
                        ),
                        onPressed: _selectDateRange,
                      ),
                      IconButton(
                        tooltip: 'Actualizar Datos',
                        icon: const Icon(Icons.refresh),
                        color: Colors.blueGrey,
                        onPressed: _fetchData,
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: _isLoading ? null : _exportExcel,
                        icon: const Icon(Icons.file_download, size: 15),
                        label: const Text('Exportar Excel'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _isLoading ? null : _exportPdf,
                        icon: const Icon(Icons.picture_as_pdf, size: 15),
                        label: const Text('Generar PDF'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade600,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              _buildFilterBar(),
            ],
          ),
        ),

        // KPI y Contenido Responsivo
        Expanded(
          child: Container(
            color: Colors.blueGrey.shade50,
            padding: EdgeInsets.all(MediaQuery.of(context).size.width < 500 ? 12.0 : 24.0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isStacked = constraints.maxWidth < 950;
                final isCompact = constraints.maxWidth < 500;

                Widget chartCard = Container(
                  height: isStacked ? 380 : double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  padding: EdgeInsets.all(isCompact ? 16 : 24),
                  child: _analysisData.isEmpty
                      ? _buildEmptyState()
                      : Column(
                          children: [
                            const Text('Distribución de Gastos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                            const SizedBox(height: 16),
                            Expanded(
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Texto central del gráfico
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text('TOTAL', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            '\$${_totalExpenses.toCurrency()}',
                                            style: TextStyle(
                                              fontSize: isCompact ? 18 : 22,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.blueGrey.shade900,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  // Gráfico de Anillo
                                  PieChart(
                                    PieChartData(
                                      pieTouchData: PieTouchData(
                                        touchCallback: (FlTouchEvent event, pieTouchResponse) {
                                          if (!event.isInterestedForInteractions || pieTouchResponse == null || pieTouchResponse.touchedSection == null) {
                                            if (_touchedIndex != -1) {
                                              setState(() => _touchedIndex = -1);
                                            }
                                            return;
                                          }
                                          final newIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                                          if (_touchedIndex != newIndex) {
                                            setState(() => _touchedIndex = newIndex);
                                          }
                                        },
                                      ),
                                      borderData: FlBorderData(show: false),
                                      sectionsSpace: 4,
                                      centerSpaceRadius: isCompact ? 70 : 130,
                                      sections: _analysisData.asMap().entries.map((entry) {
                                        final index = entry.key;
                                        final item = entry.value;
                                        final isTouched = index == _touchedIndex;
                                        final total = double.tryParse(item['amount'].toString()) ?? 0;
                                        final percentage = _totalExpenses > 0 ? (total / _totalExpenses) * 100 : 0;
                                        
                                        final radius = isCompact
                                            ? (isTouched ? 55.0 : 45.0)
                                            : (isTouched ? 90.0 : 75.0);
                                        final fontSize = isCompact
                                            ? (isTouched ? 12.0 : 10.0)
                                            : (isTouched ? 15.0 : 12.0);
                                        final categoryName = (item['category'] ?? 'Sin Categoría').toString();

                                        return PieChartSectionData(
                                          color: _chartColors[index % _chartColors.length],
                                          value: total,
                                          title: '${percentage.toStringAsFixed(1)}%',
                                          radius: radius,
                                          titleStyle: TextStyle(
                                            fontSize: fontSize,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                            shadows: const [Shadow(color: Colors.black26, blurRadius: 2)],
                                          ),
                                          badgeWidget: isTouched ? Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.95),
                                              borderRadius: BorderRadius.circular(4),
                                              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                                            ),
                                            child: Text(categoryName, style: TextStyle(color: _chartColors[index % _chartColors.length], fontWeight: FontWeight.bold, fontSize: 12)),
                                          ) : null,
                                          badgePositionPercentageOffset: isCompact ? 1.05 : 1.1,
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                );

                Widget rightPanel = Column(
                  children: [
                    // Tarjeta KPI
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(isCompact ? 16 : 24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [Colors.red.shade700, Colors.red.shade900]),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 6))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.account_balance_wallet, color: Colors.white70, size: 20),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'GASTO TOTAL DEL PERÍODO',
                                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '\$${_totalExpenses.toCurrency()}',
                              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Lista de Categorías
                    if (isStacked)
                      SizedBox(
                        height: 400,
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          elevation: 1,
                          shadowColor: Colors.black.withValues(alpha: 0.08),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('Desglose por Categoría', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                              ),
                              const Divider(height: 1),
                              Expanded(
                                child: _analysisData.isEmpty
                                    ? _buildEmptyState()
                                    : ListView.separated(
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        itemCount: _analysisData.length,
                                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
                                        itemBuilder: (context, index) {
                                          final item = _analysisData[index];
                                          final total = double.tryParse(item['amount'].toString()) ?? 0;
                                          final color = _chartColors[index % _chartColors.length];
                                          final transactions = int.tryParse(item['transactions'].toString()) ?? 0;
                                          final categoryName = (item['category'] ?? 'Sin Categoría').toString();
                                          
                                          final movements = item['movements'] as List<dynamic>? ?? [];

                                          return Theme(
                                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                            child: ExpansionTile(
                                              tilePadding: EdgeInsets.symmetric(
                                                horizontal: isCompact ? 12 : 16,
                                                vertical: 2,
                                              ),
                                              leading: Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                                                child: Icon(Icons.category, color: color, size: 18),
                                              ),
                                              title: Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      categoryName,
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Flexible(
                                                    child: FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      child: Text(
                                                        '\$${total.toCurrency()}',
                                                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.blueGrey.shade900),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              subtitle: Text('$transactions movimientos', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                              children: movements.map((mov) {
                                                final movDate = DateTime.tryParse(mov['date'].toString()) ?? DateTime.now();
                                                final movAmount = double.tryParse(mov['amount'].toString()) ?? 0;
                                                String desc = mov['description']?.toString() ?? '';
                                                if (desc.trim().isEmpty) desc = 'Gasto sin descripción';
                                                
                                                return Container(
                                                  color: Colors.grey.shade50,
                                                  padding: EdgeInsets.only(
                                                    left: isCompact ? 36 : 64,
                                                    right: isCompact ? 12 : 16,
                                                    top: 8,
                                                    bottom: 8,
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.subdirectory_arrow_right, size: 16, color: Colors.grey.shade400),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text(
                                                              desc,
                                                              style: TextStyle(color: Colors.blueGrey.shade800, fontSize: 13, fontWeight: FontWeight.w500),
                                                              maxLines: 2,
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                            const SizedBox(height: 2),
                                                            Text(DateFormat('dd MMM yyyy, HH:mm').format(movDate), style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Flexible(
                                                        child: FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          child: Text(
                                                            '\$${movAmount.toCurrency()}',
                                                            style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 13),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          elevation: 1,
                          shadowColor: Colors.black.withValues(alpha: 0.08),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('Desglose por Categoría', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                              ),
                              const Divider(height: 1),
                              Expanded(
                                child: _analysisData.isEmpty
                                    ? _buildEmptyState()
                                    : ListView.separated(
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        itemCount: _analysisData.length,
                                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
                                        itemBuilder: (context, index) {
                                          final item = _analysisData[index];
                                          final total = double.tryParse(item['amount'].toString()) ?? 0;
                                          final color = _chartColors[index % _chartColors.length];
                                          final transactions = int.tryParse(item['transactions'].toString()) ?? 0;
                                          final categoryName = (item['category'] ?? 'Sin Categoría').toString();
                                          
                                          final movements = item['movements'] as List<dynamic>? ?? [];

                                          return Theme(
                                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                            child: ExpansionTile(
                                              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                                              leading: Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                                                child: Icon(Icons.category, color: color, size: 18),
                                              ),
                                              title: Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      categoryName,
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Flexible(
                                                    child: FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      child: Text(
                                                        '\$${total.toCurrency()}',
                                                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.blueGrey.shade900),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              subtitle: Text('$transactions movimientos', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                              children: movements.map((mov) {
                                                final movDate = DateTime.tryParse(mov['date'].toString()) ?? DateTime.now();
                                                final movAmount = double.tryParse(mov['amount'].toString()) ?? 0;
                                                String desc = mov['description']?.toString() ?? '';
                                                if (desc.trim().isEmpty) desc = 'Gasto sin descripción';
                                                
                                                return Container(
                                                  color: Colors.grey.shade50,
                                                  padding: const EdgeInsets.only(left: 64, right: 16, top: 8, bottom: 8),
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.subdirectory_arrow_right, size: 16, color: Colors.grey.shade400),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text(
                                                              desc,
                                                              style: TextStyle(color: Colors.blueGrey.shade800, fontSize: 13, fontWeight: FontWeight.w500),
                                                              maxLines: 2,
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                            const SizedBox(height: 2),
                                                            Text(DateFormat('dd MMM yyyy, HH:mm').format(movDate), style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Flexible(
                                                        child: FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          child: Text(
                                                            '\$${movAmount.toCurrency()}',
                                                            style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 13),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );

                if (isStacked) {
                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        chartCard,
                        const SizedBox(height: 24),
                        rightPanel,
                      ],
                    ),
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: chartCard),
                    const SizedBox(width: 24),
                    Expanded(flex: 4, child: rightPanel),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Wrap(
      spacing: 16,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // 1. Switch/Toggle: "Incluir Pagos a Proveedores"
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 310),
          child: SizedBox(
            height: 40,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.local_shipping_outlined,
                  size: 18,
                  color: _includeSuppliers ? Colors.indigo.shade700 : Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Incluir Pagos a Proveedores',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _includeSuppliers ? Colors.indigo.shade900 : Colors.grey.shade700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Transform.scale(
                  scale: 0.85,
                  child: Switch(
                    key: const Key('switch_include_suppliers'),
                    value: _includeSuppliers,
                    activeThumbColor: Colors.indigo.shade600,
                    onChanged: (val) {
                      setState(() {
                        _includeSuppliers = val;
                      });
                      _fetchData();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // 2. Dropdown: "Método de Pago"
        Tooltip(
          message: 'Método de Pago',
          child: Container(
            height: 40,
            width: 190,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                key: const Key('dropdown_payment_method'),
                value: _selectedPaymentMethod,
                isExpanded: true,
                hint: const Align(alignment: Alignment.centerLeft, child: Text('Método de Pago', style: TextStyle(fontSize: 13))),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.blueGrey, size: 20),
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                selectedItemBuilder: (BuildContext context) {
                  return const [
                    Align(alignment: Alignment.centerLeft, child: Text('Método: Todos', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis, maxLines: 1)),
                    Align(alignment: Alignment.centerLeft, child: Text('Método: Efectivo', style: TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis, maxLines: 1)),
                    Align(alignment: Alignment.centerLeft, child: Text('Método: Transferencia', style: TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis, maxLines: 1)),
                    Align(alignment: Alignment.centerLeft, child: Text('Método: Cheque', style: TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis, maxLines: 1)),
                  ];
                },
                items: const [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Todos', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'cash',
                    child: Text('Efectivo'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'transfer',
                    child: Text('Transferencia'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'check',
                    child: Text('Cheque'),
                  ),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedPaymentMethod = val;
                  });
                  _fetchData();
                },
              ),
            ),
          ),
        ),

        // 3. Numeric text field: "Monto Mínimo"
        SizedBox(
          width: 150,
          height: 40,
          child: TextField(
            key: const Key('textfield_min_amount'),
            controller: _minAmountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
            ],
            style: const TextStyle(fontSize: 13),
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.only(left: 10, right: 10, bottom: 2),
              hintText: 'Monto Mínimo',
              hintStyle: const TextStyle(fontSize: 13, color: Colors.black54),
              prefixText: '\$ ',
              prefixStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey),
              suffixIcon: _minAmountController.text.isNotEmpty
                  ? IconButton(
                      key: const Key('button_clear_min_amount'),
                      icon: const Icon(Icons.clear, size: 14),
                      splashRadius: 14,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 0),
                      onPressed: () {
                        _minAmountController.clear();
                        _debounceTimer?.cancel();
                        setState(() {});
                        _fetchData();
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.indigo.shade400, width: 1.5),
              ),
            ),
            onChanged: (val) {
              setState(() {});
              _debounceTimer?.cancel();
              _debounceTimer = Timer(const Duration(milliseconds: 500), () {
                _fetchData();
              });
            },
            onSubmitted: (_) {
              _debounceTimer?.cancel();
              _fetchData();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.pie_chart_outline, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No hay gastos registrados', style: TextStyle(color: Colors.grey.shade600, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Intenta con otro rango de fechas.', style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
