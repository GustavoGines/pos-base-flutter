import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ExpenseAnalysisTab extends StatefulWidget {
  const ExpenseAnalysisTab({super.key});

  @override
  State<ExpenseAnalysisTab> createState() => _ExpenseAnalysisTabState();
}

class _ExpenseAnalysisTabState extends State<ExpenseAnalysisTab> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _analysisData = [];
  double _totalExpenses = 0;

  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

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
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _analysisData = List<Map<String, dynamic>>.from(data['by_category'] ?? []);
            _totalExpenses = double.tryParse(data['total_expenses']?.toString() ?? '0') ?? 0.0;
            _isLoading = false;
          });
        }
      } else {
        throw Exception('Error al cargar datos');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _fetchData();
    }
  }

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
        // Filtro de Fechas
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.white,
          child: Row(
            children: [
              const Icon(Icons.date_range, color: Colors.blueGrey),
              const SizedBox(width: 8),
              Text(
                'Desde ${DateFormat('dd/MM/yyyy').format(_startDate)} hasta ${DateFormat('dd/MM/yyyy').format(_endDate)}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _selectDateRange,
                icon: const Icon(Icons.filter_alt),
                label: const Text('Cambiar Fecha'),
                style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade50, foregroundColor: Colors.indigo.shade700),
              ),
            ],
          ),
        ),

        Expanded(
          child: _analysisData.isEmpty
              ? const Center(child: Text('No hay gastos registrados en este período.'))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 800;
                    
                    final chartWidget = Container(
                      padding: const EdgeInsets.all(24),
                      margin: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 60,
                          sections: _analysisData.asMap().entries.map((entry) {
                            final index = entry.key;
                            final item = entry.value;
                            final total = double.tryParse(item['amount'].toString()) ?? 0;
                            final colors = [Colors.red.shade400, Colors.orange.shade400, Colors.amber.shade400, Colors.green.shade400, Colors.blue.shade400, Colors.purple.shade400];
                            return PieChartSectionData(
                              color: colors[index % colors.length],
                              value: total,
                              title: '${((total / (_totalExpenses > 0 ? _totalExpenses : 1)) * 100).toStringAsFixed(1)}%',
                              radius: 50,
                              titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                            );
                          }).toList(),
                        ),
                      ),
                    );

                    final listWidget = Container(
                      margin: EdgeInsets.only(top: 16, right: 16, bottom: 16, left: isWide ? 0 : 16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text('Total de Gastos: \$${_totalExpenses.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red)),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: ListView.separated(
                              itemCount: _analysisData.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = _analysisData[index];
                                final total = double.tryParse(item['amount'].toString()) ?? 0;
                                final name = item['category'];
                                final count = item['transactions'];
                                final colors = [Colors.red.shade400, Colors.orange.shade400, Colors.amber.shade400, Colors.green.shade400, Colors.blue.shade400, Colors.purple.shade400];
                                final color = colors[index % colors.length];

                                return ListTile(
                                  leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.2), child: Icon(Icons.category, color: color)),
                                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text('$count movimientos registrados'),
                                  trailing: Text('\$${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );

                    if (isWide) {
                      return Row(
                        children: [
                          Expanded(flex: 1, child: chartWidget),
                          Expanded(flex: 1, child: listWidget),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          Expanded(flex: 1, child: chartWidget),
                          Expanded(flex: 1, child: listWidget),
                        ],
                      );
                    }
                  },
                ),
        ),
      ],
    );
  }
}
