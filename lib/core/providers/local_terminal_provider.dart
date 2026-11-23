import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/utils/receipt_printer_service.dart';

class LocalTerminalProvider extends ChangeNotifier {
  static const String _printerFormatKey = 'local_printer_format';
  static const String _printerConnectionKey = 'local_printer_connection';
  static const String _printerNameOrIpKey = 'local_printer_name_or_ip';
  static const String _scaleComPortKey = 'local_scale_com_port';
  static const String _autoOpenCashDrawerKey = 'local_auto_open_drawer';
  static const String _mpPointDeviceIdKey = 'local_mp_point_device_id';
  static const String _pdfPaperSizeKey = 'local_pdf_paper_size';
  static const String _lockedPriceTierKey = 'local_locked_price_tier';
  static const String _lockedPriceTierLabelKey = 'local_locked_price_tier_label';
  static const String _catalogViewModeKey = 'local_catalog_view_mode';
  static const String _posSplitRatioKey = 'local_pos_split_ratio';
  static const String _customersSplitRatioKey = 'local_customers_split_ratio';
  static const String _salesHistorySplitRatioKey = 'local_sales_history_split_ratio';
  static const String _pinnedProductsKey = 'local_pinned_product_ids';
  static const String _recentSearchTermsKey = 'local_pos_recent_search_terms_v1';
  static const String _recentSearchProductIdsKey = 'local_pos_recent_search_product_ids_v1';

  // Scopes operativos del historial de búsquedas
  static const String scopePosCounter = 'pos_counter';
  static const String scopeQuotes = 'quotes';
  static const String scopeHardwareCalc = 'hardware_calc';
  static const String scopeCatalog = 'catalog';
  static const List<String> _knownSearchScopes = [
    scopePosCounter,
    scopeQuotes,
    scopeHardwareCalc,
    scopeCatalog,
  ];
  static const int maxRecentSearchTerms = 8;
  static const int maxRecentSearchProducts = 5;

  // Opciones válidas: 'thermal_80', 'thermal_58', 'a4'
  String _printerFormat = 'thermal_80';

  // Opciones válidas: 'usb', 'network', 'none'
  String _printerConnection = 'none';

  String _printerNameOrIp = '';
  String _scaleComPort = '';
  bool _autoOpenCashDrawer = true;
  String _mpPointDeviceId = '';
  String _pdfPaperSize = 'a4'; // Opciones válidas: 'a4', 'letter'

  String _lockedPriceTier = 'none';
  String? _lockedPriceTierLabel;

  String _terminalId = 'caja-1'; // Default for scanner
  String _catalogViewMode = 'grid_large';
  double _posSplitRatio = 0.35;
  double _customersSplitRatio = 0.30;
  double _salesHistorySplitRatio = 0.28;

  Set<int> _pinnedProductIds = {};
  final Map<String, List<String>> _scopedRecentSearchTerms = {};
  final Map<String, List<int>> _scopedRecentSearchProductIds = {};

  bool _isInitialized = false;

  String get printerFormat => _printerFormat;
  String get printerConnection => _printerConnection;
  String get printerNameOrIp => _printerNameOrIp;
  String get scaleComPort => _scaleComPort;
  bool get autoOpenCashDrawer => _autoOpenCashDrawer;
  String get mpPointDeviceId => _mpPointDeviceId;
  String get pdfPaperSize => _pdfPaperSize;
  String get lockedPriceTier => _lockedPriceTier;
  String? get lockedPriceTierLabel => _lockedPriceTierLabel;
  String get terminalId => _terminalId;
  String get catalogViewMode => _catalogViewMode;
  double get posSplitRatio => _posSplitRatio;
  double get customersSplitRatio => _customersSplitRatio;
  double get salesHistorySplitRatio => _salesHistorySplitRatio;
  Set<int> get pinnedProductIds => _pinnedProductIds;
  List<String> get recentSearchTerms => List<String>.unmodifiable(
      _scopedRecentSearchTerms[scopePosCounter] ?? const []);
  List<int> get recentSearchProductIds => List<int>.unmodifiable(
      _scopedRecentSearchProductIds[scopePosCounter] ?? const []);
  bool get isInitialized => _isInitialized;

  LocalTerminalProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _printerFormat = prefs.getString(_printerFormatKey) ?? 'thermal_80';
    if (_printerFormat == 'a4_split' ||
        _printerFormat == 'a4_standard' ||
        _printerFormat == 'a4_normal') {
      _printerFormat = 'a4';
      prefs.setString(_printerFormatKey, 'a4');
    }
    _printerConnection = prefs.getString(_printerConnectionKey) ?? 'none';
    _printerNameOrIp = prefs.getString(_printerNameOrIpKey) ?? '';
    _scaleComPort = prefs.getString(_scaleComPortKey) ?? '';
    _autoOpenCashDrawer = prefs.getBool(_autoOpenCashDrawerKey) ?? true;
    _mpPointDeviceId = prefs.getString(_mpPointDeviceIdKey) ?? '';
    _pdfPaperSize = prefs.getString(_pdfPaperSizeKey) ?? 'a4';
    _lockedPriceTier = prefs.getString(_lockedPriceTierKey) ?? 'none';
    _lockedPriceTierLabel = prefs.getString(_lockedPriceTierLabelKey);
    _catalogViewMode = prefs.getString(_catalogViewModeKey) ?? 'grid_large';
    _posSplitRatio = prefs.getDouble(_posSplitRatioKey) ?? 0.35;
    _customersSplitRatio = prefs.getDouble(_customersSplitRatioKey) ?? 0.30;
    _salesHistorySplitRatio = prefs.getDouble(_salesHistorySplitRatioKey) ?? 0.28;
    _terminalId = prefs.getString('local_terminal_id') ?? 'caja-1';

    final pinnedIdsList = prefs.getStringList(_pinnedProductsKey);
    if (pinnedIdsList != null) {
      _pinnedProductIds = pinnedIdsList
          .map((idStr) => int.tryParse(idStr))
          .whereType<int>()
          .toSet();
    }

    for (final scope in _knownSearchScopes) {
      _loadSearchHistoryScopeFromPrefs(prefs, scope);
    }

    _isInitialized = true;

    // CRÍTICO: sincronizar el singleton de impresión con la config guardada.
    // Sin esto, ReceiptPrinterService arranca siempre con defaultUsb() (COM3
    // hardcodeado) ignorando lo que el usuario configuró en Ajustes > Hardware.
    _syncPrinterService();

    notifyListeners();
  }

  /// Propaga la configuración actual al singleton ReceiptPrinterService.
  /// Se llama al cargar los ajustes (arranque) y al cambiar cualquier
  /// parámetro de impresora para mantener ambos en sincronía.
  void _syncPrinterService() {
    ReceiptPrinterService.instance.reconfigure(this);
  }

  Future<void> setPosSplitRatio(double ratio) async {
    _posSplitRatio = ratio;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_posSplitRatioKey, ratio);
    notifyListeners();
  }

  Future<void> setCustomersSplitRatio(double ratio) async {
    _customersSplitRatio = ratio;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_customersSplitRatioKey, ratio);
    notifyListeners();
  }

  Future<void> setSalesHistorySplitRatio(double ratio) async {
    _salesHistorySplitRatio = ratio;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_salesHistorySplitRatioKey, ratio);
    notifyListeners();
  }

  Future<void> setCatalogViewMode(String mode) async {
    _catalogViewMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_catalogViewModeKey, mode);
    notifyListeners();
  }

  Future<void> setPrinterFormat(String format) async {
    // IMPORTANTE: actualizar la memoria ANTES del await para que
    // _syncPrinterService() lea el valor nuevo y no el viejo.
    _printerFormat = format;
    _syncPrinterService();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_printerFormatKey, format);
  }

  Future<void> setPrinterConnection(String connection) async {
    _printerConnection = connection;
    _syncPrinterService();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_printerConnectionKey, connection);
  }

  Future<void> setPrinterNameOrIp(String nameOrIp) async {
    _printerNameOrIp = nameOrIp;
    _syncPrinterService();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_printerNameOrIpKey, nameOrIp);
  }

  Future<void> setScaleComPort(String port) async {
    _scaleComPort = port;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scaleComPortKey, port);
  }

  Future<void> setAutoOpenCashDrawer(bool value) async {
    _autoOpenCashDrawer = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoOpenCashDrawerKey, value);
  }

  Future<void> setMpPointDeviceId(String deviceId) async {
    _mpPointDeviceId = deviceId.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mpPointDeviceIdKey, _mpPointDeviceId);
  }

  Future<void> setPdfPaperSize(String size) async {
    _pdfPaperSize = size;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pdfPaperSizeKey, size);
  }

  Future<void> setLockedPriceTier(String tier, {String? label}) async {
    _lockedPriceTier = tier;
    _lockedPriceTierLabel = label;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lockedPriceTierKey, tier);
    if (label != null) {
      await prefs.setString(_lockedPriceTierLabelKey, label);
    } else {
      await prefs.remove(_lockedPriceTierLabelKey);
    }
  }

  Future<void> setTerminalId(String id) async {
    _terminalId = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('local_terminal_id', id);
  }

  Future<void> togglePinnedProduct(int productId) async {
    if (_pinnedProductIds.contains(productId)) {
      _pinnedProductIds.remove(productId);
    } else {
      _pinnedProductIds.add(productId);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _pinnedProductsKey,
      _pinnedProductIds.map((id) => id.toString()).toList(),
    );

    notifyListeners();
  }

  static String _termsKeyForScope(String scope) {
    switch (scope) {
      case scopePosCounter:
        return _recentSearchTermsKey;
      case scopeQuotes:
        return 'local_quotes_recent_search_terms_v1';
      case scopeHardwareCalc:
        return 'local_hwcalc_recent_search_terms_v1';
      case scopeCatalog:
        return 'local_catalog_recent_search_terms_v1';
      default:
        final safe = scope.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
        return 'local_${safe}_recent_search_terms_v1';
    }
  }

  static String _productIdsKeyForScope(String scope) {
    switch (scope) {
      case scopePosCounter:
        return _recentSearchProductIdsKey;
      case scopeQuotes:
        return 'local_quotes_recent_search_product_ids_v1';
      case scopeHardwareCalc:
        return 'local_hwcalc_recent_search_product_ids_v1';
      case scopeCatalog:
        return 'local_catalog_recent_search_product_ids_v1';
      default:
        final safe = scope.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
        return 'local_${safe}_recent_search_product_ids_v1';
    }
  }

  void _loadSearchHistoryScopeFromPrefs(SharedPreferences prefs, String scope) {
    final savedTerms = prefs.getStringList(_termsKeyForScope(scope));
    if (savedTerms != null) {
      final seenLower = <String>{};
      final cleanedTerms = <String>[];
      for (final raw in savedTerms) {
        final cleaned = normalizeRecentSearchTerm(raw);
        if (!isValidRecentSearchTerm(cleaned)) continue;
        final lower = cleaned.toLowerCase();
        if (seenLower.add(lower)) {
          cleanedTerms.add(cleaned);
          if (cleanedTerms.length >= maxRecentSearchTerms) break;
        }
      }
      _scopedRecentSearchTerms[scope] = cleanedTerms;
    }

    final savedProdIds = prefs.getStringList(_productIdsKeyForScope(scope));
    if (savedProdIds != null) {
      final seenIds = <int>{};
      final cleanedIds = <int>[];
      for (final idStr in savedProdIds) {
        final id = int.tryParse(idStr);
        if (id != null && id > 0 && seenIds.add(id)) {
          cleanedIds.add(id);
          if (cleanedIds.length >= maxRecentSearchProducts) break;
        }
      }
      _scopedRecentSearchProductIds[scope] = cleanedIds;
    }
  }

  /// Normaliza espacios repetidos antes de validar o deduplicar un término.
  static String normalizeRecentSearchTerm(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Filtro anti-basura para historial de búsquedas del mostrador POS:
  /// - Ignora términos vacíos, de menos de 2 caracteres o mayores a 45 caracteres.
  /// - Exige al menos una letra o dígito (ignora signos repetidos como "..." o "---").
  /// - Ignora códigos internos de lote (`L#...`), presupuestos (`PRES-...`),
  ///   remitos/órdenes (`REM00012`, `ORD00045`) y códigos internos de balanza/etiqueta (`20...`).
  /// - Ignora cualquier cadena puramente numérica de 5 o más dígitos (EAN-13, EAN-8, UPC, PLU).
  /// - Conserva SKUs reales alfanuméricos cortos como `'HW101'`, `'T2'`, `'101'` o `'WD-40'`.
  static bool isValidRecentSearchTerm(String raw) {
    final cleaned = normalizeRecentSearchTerm(raw);
    if (cleaned.length < 2 || cleaned.length > 45) return false;
    if (!RegExp(r'[A-Za-z0-9ÁÉÍÓÚÜÑáéíóúüñ]').hasMatch(cleaned)) return false;
    final upper = cleaned.toUpperCase();
    if (upper.startsWith('L#') || upper.startsWith('PRES-')) return false;
    if (RegExp(r'^(?:REM|ORD)\d{4,}$').hasMatch(upper)) return false;
    if (RegExp(r'^20\d{5,}').hasMatch(upper)) return false;
    if (RegExp(r'^\d{5,}$').hasMatch(cleaned)) return false;
    return true;
  }

  List<String> _getRecentTermsForScopeInternal(String scope) =>
      List<String>.unmodifiable(_scopedRecentSearchTerms[scope] ?? const []);

  List<int> _getRecentProductIdsForScopeInternal(String scope) =>
      List<int>.unmodifiable(
          _scopedRecentSearchProductIds[scope] ?? const []);

  Future<void> _recordRecentSearchForScopeInternal(
    String scope, {
    String? term,
    int? selectedProductId,
  }) async {
    bool termsChanged = false;
    bool idsChanged = false;

    final currentTerms =
        List<String>.from(_scopedRecentSearchTerms[scope] ?? const []);
    final currentIds =
        List<int>.from(_scopedRecentSearchProductIds[scope] ?? const []);

    if (term != null && isValidRecentSearchTerm(term)) {
      final cleanTerm = normalizeRecentSearchTerm(term);
      final lower = cleanTerm.toLowerCase();
      if (currentTerms.isNotEmpty) {
        final latestLower = currentTerms.first.toLowerCase();
        if (cleanTerm.length > currentTerms.first.length &&
            lower.startsWith(latestLower)) {
          currentTerms.removeAt(0);
        }
      }
      currentTerms.removeWhere((t) => t.toLowerCase() == lower);
      currentTerms.insert(0, cleanTerm);
      if (currentTerms.length > maxRecentSearchTerms) {
        currentTerms.removeRange(maxRecentSearchTerms, currentTerms.length);
      }
      _scopedRecentSearchTerms[scope] = currentTerms;
      termsChanged = true;
    }

    if (selectedProductId != null && selectedProductId > 0) {
      currentIds.remove(selectedProductId);
      currentIds.insert(0, selectedProductId);
      if (currentIds.length > maxRecentSearchProducts) {
        currentIds.removeRange(maxRecentSearchProducts, currentIds.length);
      }
      _scopedRecentSearchProductIds[scope] = currentIds;
      idsChanged = true;
    }

    if (!termsChanged && !idsChanged) return;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    if (termsChanged) {
      await prefs.setStringList(_termsKeyForScope(scope), currentTerms);
    }
    if (idsChanged) {
      await prefs.setStringList(
        _productIdsKeyForScope(scope),
        currentIds.map((id) => id.toString()).toList(),
      );
    }
  }

  Future<void> _removeRecentTermForScopeInternal(
    String scope,
    String term,
  ) async {
    final list = _scopedRecentSearchTerms[scope];
    if (list == null || list.isEmpty) return;
    final lower = normalizeRecentSearchTerm(term).toLowerCase();
    final before = list.length;
    list.removeWhere((t) => t.toLowerCase() == lower);
    if (list.length == before) return;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_termsKeyForScope(scope), list);
  }

  Future<void> _removeRecentProductIdForScopeInternal(
    String scope,
    int productId,
  ) async {
    final list = _scopedRecentSearchProductIds[scope];
    if (list == null || !list.remove(productId)) return;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _productIdsKeyForScope(scope),
      list.map((id) => id.toString()).toList(),
    );
  }

  Future<void> _clearRecentSearchesForScopeInternal(String scope) async {
    final terms = _scopedRecentSearchTerms[scope];
    final ids = _scopedRecentSearchProductIds[scope];
    final hasAny =
        (terms != null && terms.isNotEmpty) || (ids != null && ids.isNotEmpty);
    if (!hasAny) return;
    _scopedRecentSearchTerms[scope] = [];
    _scopedRecentSearchProductIds[scope] = [];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_termsKeyForScope(scope));
    await prefs.remove(_productIdsKeyForScope(scope));
  }

  Future<void> recordRecentSearch({
    String? term,
    int? selectedProductId,
  }) =>
      _recordRecentSearchForScopeInternal(
        scopePosCounter,
        term: term,
        selectedProductId: selectedProductId,
      );

  Future<void> removeRecentSearchTerm(String term) =>
      _removeRecentTermForScopeInternal(scopePosCounter, term);

  Future<void> removeRecentSearchProductId(int productId) =>
      _removeRecentProductIdForScopeInternal(scopePosCounter, productId);

  Future<void> clearRecentSearches() =>
      _clearRecentSearchesForScopeInternal(scopePosCounter);
}

/// Extensión segura para múltiples scopes (`pos_counter`, `quotes`, `hardware_calc`, `catalog`).
/// Usa bloques `try/catch` con fallback en memoria para no romper tests que emplean mocks
/// mediante `implements LocalTerminalProvider`.
extension LocalTerminalSearchHistoryX on LocalTerminalProvider {
  static final Expando<Map<String, List<String>>> _fallbackTermsByInstance =
      Expando<Map<String, List<String>>>('_fallbackRecentTermsByScope');
  static final Expando<Map<String, List<int>>> _fallbackIdsByInstance =
      Expando<Map<String, List<int>>>('_fallbackRecentIdsByScope');

  Map<String, List<String>> _ensureFallbackTermsMap() {
    var map = _fallbackTermsByInstance[this];
    if (map == null) {
      map = {};
      _fallbackTermsByInstance[this] = map;
    }
    return map;
  }

  Map<String, List<int>> _ensureFallbackIdsMap() {
    var map = _fallbackIdsByInstance[this];
    if (map == null) {
      map = {};
      _fallbackIdsByInstance[this] = map;
    }
    return map;
  }

  List<String> recentTermsForScope(String scope) {
    try {
      return _getRecentTermsForScopeInternal(scope);
    } catch (_) {
      if (scope == LocalTerminalProvider.scopePosCounter) {
        try {
          return recentSearchTerms;
        } catch (_) {}
      }
      final list = _ensureFallbackTermsMap()[scope];
      return List<String>.unmodifiable(list ?? const []);
    }
  }

  List<int> recentProductIdsForScope(String scope) {
    try {
      return _getRecentProductIdsForScopeInternal(scope);
    } catch (_) {
      if (scope == LocalTerminalProvider.scopePosCounter) {
        try {
          return recentSearchProductIds;
        } catch (_) {}
      }
      final list = _ensureFallbackIdsMap()[scope];
      return List<int>.unmodifiable(list ?? const []);
    }
  }

  Future<void> recordRecentSearchForScope(
    String scope, {
    String? term,
    int? selectedProductId,
  }) async {
    try {
      await _recordRecentSearchForScopeInternal(
        scope,
        term: term,
        selectedProductId: selectedProductId,
      );
      return;
    } catch (_) {
      if (scope == LocalTerminalProvider.scopePosCounter) {
        try {
          await recordRecentSearch(
            term: term,
            selectedProductId: selectedProductId,
          );
          return;
        } catch (_) {}
      }
    }

    var changed = false;
    if (term != null && LocalTerminalProvider.isValidRecentSearchTerm(term)) {
      final cleanTerm = LocalTerminalProvider.normalizeRecentSearchTerm(term);
      final lower = cleanTerm.toLowerCase();
      final map = _ensureFallbackTermsMap();
      final list = List<String>.from(map[scope] ?? const []);
      if (list.isNotEmpty) {
        final latestLower = list.first.toLowerCase();
        if (cleanTerm.length > list.first.length &&
            lower.startsWith(latestLower)) {
          list.removeAt(0);
        }
      }
      list.removeWhere((t) => t.toLowerCase() == lower);
      list.insert(0, cleanTerm);
      if (list.length > LocalTerminalProvider.maxRecentSearchTerms) {
        list.removeRange(
            LocalTerminalProvider.maxRecentSearchTerms, list.length);
      }
      map[scope] = list;
      changed = true;
    }
    if (selectedProductId != null && selectedProductId > 0) {
      final map = _ensureFallbackIdsMap();
      final list = List<int>.from(map[scope] ?? const []);
      list.remove(selectedProductId);
      list.insert(0, selectedProductId);
      if (list.length > LocalTerminalProvider.maxRecentSearchProducts) {
        list.removeRange(
            LocalTerminalProvider.maxRecentSearchProducts, list.length);
      }
      map[scope] = list;
      changed = true;
    }
    if (changed) {
      try {
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        notifyListeners();
      } catch (_) {}
    }
  }

  Future<void> removeRecentTermForScope(String scope, String term) async {
    try {
      await _removeRecentTermForScopeInternal(scope, term);
      return;
    } catch (_) {
      if (scope == LocalTerminalProvider.scopePosCounter) {
        try {
          await removeRecentSearchTerm(term);
          return;
        } catch (_) {}
      }
    }
    final map = _ensureFallbackTermsMap();
    final list = map[scope];
    if (list == null) return;
    final lower = LocalTerminalProvider.normalizeRecentSearchTerm(term).toLowerCase();
    final before = list.length;
    list.removeWhere((t) => t.toLowerCase() == lower);
    if (list.length != before) {
      try {
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        notifyListeners();
      } catch (_) {}
    }
  }

  Future<void> removeRecentProductIdForScope(
    String scope,
    int productId,
  ) async {
    try {
      await _removeRecentProductIdForScopeInternal(scope, productId);
      return;
    } catch (_) {
      if (scope == LocalTerminalProvider.scopePosCounter) {
        try {
          await removeRecentSearchProductId(productId);
          return;
        } catch (_) {}
      }
    }
    final map = _ensureFallbackIdsMap();
    final list = map[scope];
    if (list != null && list.remove(productId)) {
      try {
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        notifyListeners();
      } catch (_) {}
    }
  }

  Future<void> clearRecentSearchesForScope(String scope) async {
    try {
      await _clearRecentSearchesForScopeInternal(scope);
      return;
    } catch (_) {
      if (scope == LocalTerminalProvider.scopePosCounter) {
        try {
          await clearRecentSearches();
          return;
        } catch (_) {}
      }
    }
    final terms = _ensureFallbackTermsMap().remove(scope);
    final ids = _ensureFallbackIdsMap().remove(scope);
    if ((terms != null && terms.isNotEmpty) || (ids != null && ids.isNotEmpty)) {
      try {
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        notifyListeners();
      } catch (_) {}
    }
  }
}
