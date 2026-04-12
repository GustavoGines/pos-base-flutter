import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/datasources/reports_remote_datasource.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class ReportsProvider extends ChangeNotifier {
  final ReportsRemoteDataSource dataSource;

  ReportsProvider({required this.dataSource});

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  bool _isExporting = false;
  bool get isExporting => _isExporting;

  DateTime _startDate = DateTime.now().copyWith(day: 1);
  DateTime _endDate = DateTime.now();

  DateTime get startDate => _startDate;
  DateTime get endDate => _endDate;

  List<dynamic> _reportData = [];
  List<dynamic> get reportData => _reportData;

  List<dynamic> _dailyEvolution = [];
  List<dynamic> get dailyEvolution => _dailyEvolution;

  double _previousPeriodRevenue = 0;
  double _previousPeriodProfit = 0;

  double get revenueTrendPercentage {
    if (_previousPeriodRevenue == 0) return totalRevenue > 0 ? 100.0 : 0.0;
    return ((totalRevenue - _previousPeriodRevenue) / _previousPeriodRevenue) * 100;
  }

  double get profitTrendPercentage {
    if (_previousPeriodProfit == 0) return totalProfit > 0 ? 100.0 : 0.0;
    return ((totalProfit - _previousPeriodProfit) / _previousPeriodProfit) * 100;
  }

  double get totalRevenue => _reportData.fold(0, (sum, item) => sum + (double.tryParse(item['total_revenue'].toString()) ?? 0));
  double get totalProfit => _reportData.fold(0, (sum, item) => sum + (double.tryParse(item['total_profit'].toString()) ?? 0));
  
  /// Facturación de items que SÍ tienen costo registrado (base real del margen)
  double get totalRevenueWithCost => _reportData.fold(0, (sum, item) => sum + (double.tryParse(item['revenue_with_cost'].toString()) ?? 0));

  int get totalItemsWithCost => _reportData.fold(0, (sum, item) => sum + (int.tryParse(item['items_with_cost'].toString()) ?? 0));
  int get totalItems => _reportData.fold(0, (sum, item) => sum + (int.tryParse(item['total_items'].toString()) ?? 0));

  bool get hasMissingCostData => totalItems > totalItemsWithCost;

  double get marginPercentage {
    if (totalRevenueWithCost == 0) return 0;
    return (totalProfit / totalRevenueWithCost) * 100;
  }

  void setDateRange(DateTime start, DateTime end) {
    _startDate = start;
    _endDate = end;
    notifyListeners();
  }

  Future<void> fetchProfitByCategory() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final df = DateFormat('yyyy-MM-dd');
      final result = await dataSource.getProfitByCategory(df.format(_startDate), df.format(_endDate));
      _reportData = result['data'] ?? [];
      _dailyEvolution = result['daily_evolution'] ?? [];
      
      final prev = result['previous_period'] ?? {};
      _previousPeriodRevenue = double.tryParse(prev['revenue']?.toString() ?? '0') ?? 0;
      _previousPeriodProfit = double.tryParse(prev['profit']?.toString() ?? '0') ?? 0;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> exportToExcel() async {
    _isExporting = true;
    _error = null;
    notifyListeners();

    try {
      final df = DateFormat('yyyy-MM-dd');
      final bytes = await dataSource.downloadExcel(df.format(_startDate), df.format(_endDate));
      
      final docsDir = await getApplicationDocumentsDirectory();
      final reportesDir = Directory('${docsDir.path}${Platform.pathSeparator}Sistema_POS${Platform.pathSeparator}Reportes');
      
      if (!await reportesDir.exists()) {
        await reportesDir.create(recursive: true);
      }
      
      final cleanStart = DateFormat('dd-MM-yyyy').format(_startDate);
      final cleanEnd = DateFormat('dd-MM-yyyy').format(_endDate);
      final filename = 'Ganancias_${cleanStart}_al_${cleanEnd}.xlsx';
      final file = File('${reportesDir.path}${Platform.pathSeparator}$filename');
      
      await file.writeAsBytes(bytes);

      if (Platform.isWindows) {
        try {
          await Process.run('explorer.exe', ['/select,', file.path]);
        } catch (e) {
          debugPrint('Error abriendo explorer: $e');
        }
      } else {
        final folderUri = Uri.parse('file:///${reportesDir.path.replaceAll('\\', '/')}');
        if (await canLaunchUrl(folderUri)) {
          await launchUrl(folderUri);
        }
      }
    } catch (e) {
      _error = 'Error al exportar: $e';
    } finally {
      _isExporting = false;
      notifyListeners();
    }
  }
}

