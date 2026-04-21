import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/delivery_note_repository.dart';

/// Clase auxiliar para encapsular el estado de paginación por cada pestaña
class LogisticsTabState {
  List<Map<String, dynamic>> notes = [];
  int currentPage = 1;
  bool hasMoreData = true;
  bool isLoading = false;
  bool isInitialized = false;

  void reset() {
    notes.clear();
    currentPage = 1;
    hasMoreData = true;
    isLoading = false;
    isInitialized = false;
  }
}

class LogisticsProvider extends ChangeNotifier {
  final DeliveryNoteRepository repository;

  LogisticsProvider({required this.repository});

  // Estado separado por cada pestaña (pending, partial, delivered)
  final Map<String, LogisticsTabState> _tabs = {
    'pending': LogisticsTabState(),
    'partial': LogisticsTabState(),
    'delivered': LogisticsTabState(),
  };

  String _searchQuery = '';
  Timer? _debounceTimer;
  Timer? _pollingTimer;
  bool _isDispatching = false;
  String? _errorMessage;

  String get searchQuery => _searchQuery;
  bool get isDispatching => _isDispatching;
  String? get errorMessage => _errorMessage;

  LogisticsTabState getTabState(String status) => _tabs[status]!;

  /// Inicia el polling silencioso cada 15 segundos
  void startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      // Solo actualiza los tabs que ya están inicializados para no gastar recursos
      if (_tabs['pending']!.isInitialized) silentFetch('pending');
      if (_tabs['partial']!.isInitialized) silentFetch('partial');
      if (_tabs['delivered']!.isInitialized) silentFetch('delivered');
    });
  }

  /// Detiene el polling
  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Fetch silencioso: actualiza la data de fondo sin mostrar loaders ni alterar la paginación existente
  Future<void> silentFetch(String status) async {
    final state = _tabs[status]!;
    if (!state.isInitialized) return;

    try {
      final result = await repository.fetchDeliveryNotes(
        status: status,
        search: _searchQuery,
        page: 1, // Siempre actualiza la primera página para ver nuevos ingresos
      );
      
      final rawData = result['data'] is List ? result['data'] : (result['data']?['data'] ?? []);
      final data = List<Map<String, dynamic>>.from(rawData);
      
      // Actualizamos la lista silenciosamente.
      // Si el operario scrolleó, preservamos los elementos cargados después de la página 1.
      // Si está en la página 1, reemplazamos todo.
      if (state.currentPage == 1) {
        state.notes = data;
      } else {
        // Para no romper la vista si bajó el scroll, reemplazamos exactamente
        // el bloque que corresponde a la página 1 (los primeros N elementos)
        // y conservamos el resto de la lista filtrando duplicados.
        final perPage = (result['data'] is Map && result['data']['per_page'] != null)
            ? (result['data']['per_page'] as int)
            : 15; // default laravel

        final newIds = data.map((e) => e['id']).toSet();

        // Mantenemos los elementos antiguos desde la página 2 en adelante,
        // excluyendo aquellos que hayan subido a la página 1 (ya están en 'data').
        final oldRemaining = state.notes.length > perPage
            ? state.notes.skip(perPage).where((e) => !newIds.contains(e['id'])).toList()
            : <Map<String, dynamic>>[];

        state.notes = [...data, ...oldRemaining];
      }

      notifyListeners();
    } catch (e) {
      // Ignoramos errores en silent fetch
      debugPrint('Error en silent fetch para $status: $e');
    }
  }

  /// Carga inicial de datos, o recarga forzada (refresca desde la página 1).
  Future<void> fetchFirstPage(String status) async {
    final state = _tabs[status]!;
    state.reset();
    state.isLoading = true;
    notifyListeners();

    try {
      final result = await repository.fetchDeliveryNotes(
        status: status,
        search: _searchQuery,
        page: 1,
      );
      
      // Soportamos estructuras tanto directas como anidadas en 'data' por seguridad.
      final rawData = result['data'] is List ? result['data'] : (result['data']?['data'] ?? []);
      final data = List<Map<String, dynamic>>.from(rawData);
      
      final meta = result['meta'] ?? result;
      final currentPage = meta['current_page'] ?? 1;
      final lastPage = meta['last_page'] ?? 1;
      
      state.notes = data;
      state.currentPage = 1;
      state.hasMoreData = currentPage < lastPage;
      state.isInitialized = true;
      _errorMessage = null;
    } catch (e) {
      debugPrint('Error parseando / fetching: $e');
      _errorMessage = e.toString();
    } finally {
      state.isLoading = false;
      notifyListeners();
    }
  }

  /// Paginación: Carga la siguiente página (Lazy Loading para Infinite Scroll).
  Future<void> fetchNextPage(String status) async {
    final state = _tabs[status]!;
    if (state.isLoading || !state.hasMoreData) return;

    state.isLoading = true;
    notifyListeners();

    try {
      final nextPage = state.currentPage + 1;
      final result = await repository.fetchDeliveryNotes(
        status: status,
        search: _searchQuery,
        page: nextPage,
      );
      
      final rawData = result['data'] is List ? result['data'] : (result['data']?['data'] ?? []);
      final data = List<Map<String, dynamic>>.from(rawData);
      
      final meta = result['meta'] ?? result;
      final currentPage = meta['current_page'] ?? nextPage;
      final lastPage = meta['last_page'] ?? nextPage;
      
      state.notes.addAll(data);
      state.currentPage = nextPage;
      state.hasMoreData = currentPage < lastPage;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      state.isLoading = false;
      notifyListeners();
    }
  }

  /// Buscador con Debouncer (500ms) para evitar llamadas innecesarias a la API.
  void onSearchChanged(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;

    if (_debounceTimer?.isActive ?? false) {
      _debounceTimer!.cancel();
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      // Cuando el usuario deja de escribir, refrescamos TODAS las pestañas que ya fueron visitadas.
      for (final status in _tabs.keys) {
        if (_tabs[status]!.isInitialized) {
          fetchFirstPage(status);
        }
      }
    });
  }

  /// Confirma el despacho (parcial o total) y recarga las listas afectadas.
  Future<bool> confirmDispatch(int deliveryNoteId, Map<int, double> deliveredNow) async {
    _isDispatching = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await repository.dispatchItems(deliveryNoteId, deliveredNow);
      
      // Si el despacho fue exitoso, refrescamos las pestañas inicializadas.
      // Así los remitos pasan automáticamente de 'pending' a 'partial' o 'delivered'.
      for (final status in _tabs.keys) {
        if (_tabs[status]!.isInitialized) {
          await fetchFirstPage(status);
        }
      }
      
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isDispatching = false;
      notifyListeners();
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
