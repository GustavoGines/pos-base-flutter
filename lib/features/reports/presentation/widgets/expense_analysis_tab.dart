import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _fetchData();
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

      final client = context.read<ApiClient>();
      final response = await client.get(
        Uri.parse('$baseUrl/reports/expenses-analysis?start_date=$start&end_date=$end'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _analysisData = List<Map<String, dynamic>>.from(data['by_category'] ?? []);
          _totalExpenses = double.tryParse(data['total_expenses'].toString()) ?? 0.0;
          _isLoading = false;
        });
      } else {
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
    
    final urlStr = '$baseUrl/reports/expenses-analysis/$type?start_date=$start&end_date=$end';

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
        final exportDir = Directory('${docsDir.path}\\Sistema_POS\\Exportaciones');
        if (!await exportDir.exists()) {
          await exportDir.create(recursive: true);
        }

        final fileName = 'analisis_gastos_${DateTime.now().millisecondsSinceEpoch}.${type == 'pdf' ? 'pdf' : 'xlsx'}';
        final file = File('${exportDir.path}\\$fileName');
        await file.writeAsBytes(response.bodyBytes);

        if (Platform.isWindows) {
          try {
            await Process.run('explorer.exe', ['/select,', file.path]);
          } catch (_) {}
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
        // Filtro de Fechas y Acciones
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.date_range, color: Colors.blueGrey, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Desde ${DateFormat('dd/MM/yyyy').format(_startDate)} hasta ${DateFormat('dd/MM/yyyy').format(_endDate)}',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.blueGrey),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.filter_alt_outlined, size: 16),
                    label: const Text('Cambiar Período'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.indigo.shade600,
                      side: BorderSide(color: Colors.indigo.shade200),
                    ),
                    onPressed: _selectDateRange,
                  ),
                ],
              ),
              Row(
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
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _exportPdf,
                    icon: const Icon(Icons.picture_as_pdf, size: 15),
                    label: const Text('Generar PDF'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    color: Colors.blue.shade600,
                    tooltip: 'Recargar Datos',
                    onPressed: _isLoading ? null : _fetchData,
                  ),
                ],
              ),
            ],
          ),
        ),

        // KPI y Contenido
        Expanded(
          child: Container(
            color: Colors.blueGrey.shade50,
            padding: const EdgeInsets.all(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Panel Izquierdo: Gráfico
                Expanded(
                  flex: 5,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    padding: const EdgeInsets.all(32),
                    child: _analysisData.isEmpty
                        ? _buildEmptyState()
                        : Column(
                            children: [
                              const Text('Distribución de Gastos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                              const SizedBox(height: 32),
                              Expanded(
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Texto central del gráfico
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text('TOTAL', style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
                                        Text(
                                          '\$${_totalExpenses.toCurrency()}',
                                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.blueGrey.shade900),
                                        ),
                                      ],
                                    ),
                                    // Gráfico de Anillo
                                    PieChart(
                                      PieChartData(
                                        pieTouchData: PieTouchData(
                                          touchCallback: (FlTouchEvent event, pieTouchResponse) {
                                            setState(() {
                                              if (!event.isInterestedForInteractions || pieTouchResponse == null || pieTouchResponse.touchedSection == null) {
                                                _touchedIndex = -1;
                                                return;
                                              }
                                              _touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                                            });
                                          },
                                        ),
                                        borderData: FlBorderData(show: false),
                                        sectionsSpace: 4,
                                        centerSpaceRadius: 120, // Aumentado para diseño premium
                                        sections: _analysisData.asMap().entries.map((entry) {
                                          final index = entry.key;
                                          final item = entry.value;
                                          final isTouched = index == _touchedIndex;
                                          final total = double.tryParse(item['amount'].toString()) ?? 0;
                                          final percentage = _totalExpenses > 0 ? (total / _totalExpenses) * 100 : 0;
                                          
                                          final radius = isTouched ? 70.0 : 55.0;
                                          final fontSize = isTouched ? 16.0 : 12.0;

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
                                                color: Colors.white.withValues(alpha: 0.9),
                                                borderRadius: BorderRadius.circular(4),
                                                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                                              ),
                                              child: Text(item['category'].toString(), style: TextStyle(color: _chartColors[index % _chartColors.length], fontWeight: FontWeight.bold, fontSize: 12)),
                                            ) : null,
                                            badgePositionPercentageOffset: 1.1,
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(width: 24),
                // Panel Derecho: KPIs y Lista
                Expanded(
                  flex: 4,
                  child: Column(
                    children: [
                      // Tarjeta KPI
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
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
                                Text('GASTO TOTAL DEL PERÍODO', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '\$${_totalExpenses.toCurrency()}',
                              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Lista de Categorías
                      Expanded(
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          elevation: 2,
                          shadowColor: Colors.black.withValues(alpha: 0.2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.all(20),
                                child: Text('Desglose por Categoría', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
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
                                          
                                          final movements = item['movements'] as List<dynamic>? ?? [];

                                          return Theme(
                                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                            child: ExpansionTile(
                                              tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                                              leading: Container(
                                                padding: const EdgeInsets.all(10),
                                                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                                                child: Icon(Icons.category, color: color, size: 20),
                                              ),
                                              title: Row(
                                                children: [
                                                  Expanded(child: Text(item['category'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                                                  Text(
                                                    '\$${total.toCurrency()}',
                                                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.blueGrey.shade900),
                                                  ),
                                                ],
                                              ),
                                              subtitle: Text('$transactions movimientos', style: TextStyle(color: Colors.grey.shade600)),
                                              children: movements.map((mov) {
                                                final movDate = DateTime.tryParse(mov['date'].toString()) ?? DateTime.now();
                                                final movAmount = double.tryParse(mov['amount'].toString()) ?? 0;
                                                String desc = mov['description']?.toString() ?? '';
                                                if (desc.trim().isEmpty) desc = 'Gasto sin descripción';
                                                
                                                return Container(
                                                  color: Colors.grey.shade50,
                                                  padding: const EdgeInsets.only(left: 72, right: 20, top: 8, bottom: 8),
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.subdirectory_arrow_right, size: 16, color: Colors.grey.shade400),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text(desc, style: TextStyle(color: Colors.blueGrey.shade800, fontSize: 13, fontWeight: FontWeight.w500)),
                                                            const SizedBox(height: 2),
                                                            Text(DateFormat('dd MMM yyyy, HH:mm').format(movDate), style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                                                          ],
                                                        ),
                                                      ),
                                                      Text('\$${movAmount.toCurrency()}', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 13)),
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
                  ),
                ),
              ],
            ),
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
