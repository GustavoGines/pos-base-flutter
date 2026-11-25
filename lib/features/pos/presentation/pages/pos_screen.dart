import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/config/app_config.dart';
import 'package:frontend_desktop/core/config/business_vertical_profile.dart';
import 'package:frontend_desktop/features/catalog/data/models/product_model.dart';
import 'package:frontend_desktop/core/utils/receipt_printer_service.dart';
import 'package:flutter/material.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/utils/batch_barcode_helper.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import '../providers/pos_provider.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/customers/providers/customer_provider.dart';
import '../widgets/checkout_dialog.dart';
import '../widgets/pos_quick_access_view.dart';
import '../widgets/pos_financial_summary.dart';
import '../widgets/pos_quick_action_buttons.dart';
import '../widgets/pos_quick_customer_dialog.dart';
import '../widgets/pos_quick_item_dialog.dart';
import '../widgets/pos_price_lookup_dialog.dart';
import '../widgets/pos_rename_cart_item_dialog.dart';
import '../widgets/pos_hardware_calculator_dialog.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_pdf_preview.dart';
import 'package:frontend_desktop/core/presentation/widgets/plan_upgrade_dialog.dart';
import 'package:frontend_desktop/core/presentation/widgets/pos_search_history_popover.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
import 'package:frontend_desktop/features/offers/presentation/providers/offer_provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/features/cash_movements/presentation/widgets/movement_form_dialog.dart' as frontend_desktop_cash_movements_dialog;
import 'package:frontend_desktop/core/utils/scale_serial_service.dart';
import 'package:frontend_desktop/features/quotes/presentation/providers/quote_provider.dart';
import 'package:frontend_desktop/features/quotes/presentation/widgets/quote_success_dialog.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import '../../../auth/presentation/widgets/admin_pin_dialog.dart';
import '../../../../core/constants/app_permissions.dart';
import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/core/utils/a4_split_pdf_service.dart';
import 'package:frontend_desktop/features/logistics/presentation/providers/logistics_provider.dart';
import 'package:frontend_desktop/core/services/remote_scanner_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  _PosScreenState createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();

  // Búsqueda: resultados del servidor, query visual y timer de debounce
  String _searchQuery = '';
  List<Product> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounceSearchTimer;

  Timer? _pendingOrdersTimer;

  // Controladores para el Popover de Órdenes en Espera
  final _pendingOrdersPortalController = OverlayPortalController();
  bool _isPendingPinned = false; // Modo Híbrido
  bool _onlyCurrentRegisterPending = false; // MC-03: Filtro de órdenes en espera por caja activa

  // Controladores para el Popover flotante de Historial de Búsquedas
  final _searchHistoryPortalController = OverlayPortalController();
  static const Object _searchHistoryTapGroupId = 'pos_search_history_popover';
  int _searchHistoryHighlightIndex = -1;

  // Filtro rápido en memoria para el Acceso Rápido
  String _quickAccessFilter = 'all'; // 'all', 'pinned', 'top_sellers', 'offers', 'weight', o 'cat_<id>'

  // Protección Anti-"Efecto Baile": congela el orden de IDs durante el turno activo
  // para que al cobrar una venta suba el badge (⚡/🔥) pero las tarjetas y Ctrl+1..9 no cambien de lugar.
  String? _frozenOrderSignature;
  final Map<int, int> _frozenRankById = {};

  // Candado anti-doble-modal para preventir abrir CheckoutDialog dos veces
  bool _isCheckingOut = false;

  StreamSubscription<int>? _printLabelSub;
  ModalRoute<dynamic>? _posRoute;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _posRoute = ModalRoute.of(context);
  }

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_handleSearchFocusChange);
    HardwareKeyboard.instance.addHandler(_handlePosHardwareKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPrintLabelListener();
      _requestSearchFocusSilently();
      // Siempre cargar la lista COMPLETA al entrar a POS, ignorando cualquier
      // búsqueda u ordenamiento que el módulo de Catálogo haya dejado activo.
      Provider.of<CatalogProvider>(context, listen: false)
          .loadProducts(page: 1, search: '', sortBy: '', perPage: 500);
      Provider.of<CatalogProvider>(context, listen: false).loadMetadata();
      // Sincronizar y aplicar lista de precios fijada por la terminal
      final localTerminal = Provider.of<LocalTerminalProvider>(context, listen: false);
      final posProvider = Provider.of<PosProvider>(context, listen: false);
      final settings = Provider.of<SettingsProvider>(context, listen: false).settings;
      final isMultiPriceEnabled = settings?.hasMultiPriceEnabled == true;
      
      String initialTier = 'base';
      String? initialLabel;

      if (localTerminal.lockedPriceTier != 'none') {
        final lockedTier = localTerminal.lockedPriceTier;

        if (isMultiPriceEnabled &&
            settings!.isPriceTierKeyAvailable(lockedTier)) {
          initialTier = lockedTier;
          initialLabel = localTerminal.lockedPriceTierLabel;
        } else {
          // Limpiar la lista fijada porque Multi-Listas está desactivada, fue eliminada o tiene 0%
          localTerminal.setLockedPriceTier('none');
        }
      }

      posProvider.updateSettings(settings);
      posProvider.setDefaultTier(initialTier, initialLabel);
      if (posProvider.cart.isEmpty) {
        posProvider.clearCart(); // Aplica la lista fijada inmediatamente
      }

      // Cargar el contador de órdenes pendientes al abrir el POS
      posProvider.loadPendingSales();

      // Sincronizar de inmediato las ofertas en memoria (si ya estaban cargadas)
      // y refrescar desde el servidor en segundo plano
      final offerProvider = Provider.of<OfferProvider>(context, listen: false);
      if (offerProvider.activeOffers.isNotEmpty) {
        posProvider.syncActiveOffers(offerProvider.activeOffers);
      }
      offerProvider.loadActiveOffers().then((_) {
        if (mounted) {
          posProvider.syncActiveOffers(offerProvider.activeOffers);
        }
      });

      // Polling veloz (5 seg) para recepción casi-inmediata de órdenes en red local/multicaja.
      // Justificado: servidor local con máx. 3 terminales (carga mínima).
      _pendingOrdersTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (mounted) {
          Provider.of<PosProvider>(context, listen: false).loadPendingSales();
        }
      });
    });
  }

  void _initPrintLabelListener() {
    final scanner = Provider.of<RemoteScannerService?>(context, listen: false);
    if (scanner == null) return;
    _printLabelSub?.cancel();
    _printLabelSub =
        scanner.onPrintLabelRequested.listen(_handlePrintLabelRequest);
  }

  Future<void> _handlePrintLabelRequest(int productId) async {
    if (!mounted) return;
    try {
      final catalog = Provider.of<CatalogProvider>(context, listen: false);
      Product? product;
      try {
        product = catalog.products.firstWhere((p) => p.id == productId);
      } catch (_) {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        final prefs = await SharedPreferences.getInstance();
        final String apiUrl = prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;
        final response = await http.get(
          Uri.parse('$apiUrl/catalog/products/$productId'),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer ${auth.sessionToken}',
          },
        );
        if (response.statusCode == 200) {
          product = ProductModel.fromJson(jsonDecode(response.body));
        }
      }

      if (product != null) {
        await ReceiptPrinterService.instance.printLabel(product);
        if (mounted) {
          SnackBarService.success(context, 'Etiqueta impresa remotamente');
        }
      }
    } catch (e) {
      debugPrint("Error parsing PrintLabelRequested event: $e");
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handlePosHardwareKey);
    _printLabelSub?.cancel();
    _pendingOrdersTimer?.cancel();
    _debounceSearchTimer?.cancel();
    _searchFocusNode.removeListener(_handleSearchFocusChange);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchFocusChange() {
    // El cierre del popover lo controlan TapRegion.onTapOutside, TextFieldTapRegion, Esc y Tab.
    // No ocultamos ni abrimos en foco programático para evitar destruir clics internos en X/Limpiar
    // y evitar aperturas involuntarias al cerrar modales.
  }

  void _requestSearchFocusSilently() {
    if (!mounted) return;
    _searchFocusNode.requestFocus();
  }

  List<Product> _resolveActiveRecentProducts(
    CatalogProvider catalog,
    LocalTerminalProvider? localTerminal,
  ) {
    final ids = localTerminal?.recentProductIdsForScope(
          LocalTerminalProvider.scopePosCounter,
        ) ??
        const <int>[];
    if (ids.isEmpty) return const [];
    final resolved = catalog.resolveRecentProducts(ids, activeOnly: true);
    final missingIds = catalog.unhydratedRecentProductIds(ids);
    if (missingIds.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(catalog.syncPinnedProducts(missingIds));
      });
    }
    return resolved;
  }

  bool _hasSearchHistoryEntries(
    CatalogProvider catalog,
    LocalTerminalProvider? localTerminal,
  ) {
    if (localTerminal == null) return false;
    final terms = localTerminal.recentTermsForScope(
      LocalTerminalProvider.scopePosCounter,
    );
    if (terms.isNotEmpty) return true;
    return _resolveActiveRecentProducts(catalog, localTerminal).isNotEmpty;
  }

  void _showSearchHistoryPopoverIfAvailable({int initialHighlightIndex = -1}) {
    if (!mounted || _isCheckingOut) return;
    if (_searchController.text.trim().isNotEmpty) return;
    final catalog = Provider.of<CatalogProvider>(context, listen: false);
    final localTerminal = tryGetLocalTerminalProvider(context, listen: false);
    if (!_hasSearchHistoryEntries(catalog, localTerminal)) return;
    if (_searchHistoryHighlightIndex != initialHighlightIndex) {
      setState(() => _searchHistoryHighlightIndex = initialHighlightIndex);
    }
    if (!_searchHistoryPortalController.isShowing) {
      _searchHistoryPortalController.show();
    }
  }

  void _hideSearchHistoryPopover() {
    if (_searchHistoryHighlightIndex != -1 && mounted) {
      setState(() => _searchHistoryHighlightIndex = -1);
    } else {
      _searchHistoryHighlightIndex = -1;
    }
    if (_searchHistoryPortalController.isShowing) {
      _searchHistoryPortalController.hide();
    }
  }

  void _recordRecentSearchIfValid(
    String? term, {
    int? selectedProductId,
    Product? selectedProduct,
  }) {
    if (selectedProduct != null) {
      try {
        Provider.of<CatalogProvider>(context, listen: false)
            .registerRecentlySeenProducts([selectedProduct]);
      } catch (_) {}
    }
    final validTerm = (term != null &&
            LocalTerminalProvider.isValidRecentSearchTerm(term))
        ? term
        : null;
    final validProdId = selectedProductId ?? selectedProduct?.id;
    if (validTerm == null && (validProdId == null || validProdId <= 0)) return;
    final localTerminal = tryGetLocalTerminalProvider(context, listen: false);
    if (localTerminal == null) return;
    unawaited(localTerminal.recordRecentSearchForScope(
      LocalTerminalProvider.scopePosCounter,
      term: validTerm,
      selectedProductId: validProdId,
    ));
  }

  Future<void> _applyRecentSearchTerm(String term) async {
    final clean = term.trim();
    if (clean.isEmpty || !mounted) return;
    _hideSearchHistoryPopover();
    _debounceSearchTimer?.cancel();
    _searchController.text = clean;
    _searchController.selection = TextSelection.collapsed(offset: clean.length);
    setState(() {
      _searchQuery = clean;
      _isSearching = true;
    });
    _requestSearchFocusSilently();

    final results = (await Provider.of<PosProvider>(context, listen: false)
            .search(clean))
        .where((p) => p.active)
        .toList();
    if (!mounted || _searchQuery != clean) return;
    Provider.of<CatalogProvider>(context, listen: false)
        .registerRecentlySeenProducts(results);
    setState(() {
      _searchResults = results;
      _isSearching = false;
    });
    _recordRecentSearchIfValid(clean);
  }

  /// Verifica si un código escaneado corresponde a un producto dado de baja (`active == false`),
  /// consultando primero memoria y, si el catálogo supera 500 ítems, con fallback al servidor.
  Future<Product?> _findInactiveProductByCode(
    String code, {
    String? scalePlu,
  }) async {
    final catalog = Provider.of<CatalogProvider>(context, listen: false);
    final inactiveInMemory = catalog.products.where((p) => !p.active);

    Product? match = RemoteScannerService.findExactProductMatch(
      inactiveInMemory,
      code,
      activeOnly: false,
    );
    if (match == null && scalePlu != null && scalePlu.isNotEmpty) {
      match = RemoteScannerService.findExactProductMatch(
        inactiveInMemory,
        scalePlu,
        activeOnly: false,
      );
    }
    if (match != null) return match;

    final lookupCode = (scalePlu != null && scalePlu.isNotEmpty) ? scalePlu : code;
    if (!RegExp(r'^[A-Za-z0-9\-_]{3,32}$').hasMatch(lookupCode)) {
      return null;
    }

    try {
      final remoteAll = await catalog.searchProductsRemote(
        lookupCode,
        perPage: 10,
        activeOnly: false,
      );
      if (!mounted) return null;
      final inactiveRemote = remoteAll.where((p) => !p.active);
      return RemoteScannerService.findExactProductMatch(
            inactiveRemote,
            code,
            activeOnly: false,
          ) ??
          (scalePlu != null && scalePlu.isNotEmpty
              ? RemoteScannerService.findExactProductMatch(
                  inactiveRemote,
                  scalePlu,
                  activeOnly: false,
                )
              : null);
    } catch (_) {
      return null;
    }
  }

  /// Búsqueda en vivo vía API con debounce de 400ms
  void _onPosSearchChanged(String value) {
    final query = value.trim();
    _debounceSearchTimer?.cancel();

    if (query.isNotEmpty) {
      _hideSearchHistoryPopover();
    }

    if (query.isEmpty) {
      setState(() {
        _searchQuery = '';
        _searchResults = [];
        _isSearching = false;
        _searchHistoryHighlightIndex = -1;
      });
      return;
    }

    setState(() => _searchQuery = query);

    _debounceSearchTimer = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted || _searchQuery != query || _searchQuery.isEmpty) return;
      setState(() => _isSearching = true);
      final results = (await Provider.of<PosProvider>(context, listen: false)
              .search(query))
          .where((p) => p.active)
          .toList();
      if (!mounted || _searchQuery != query) return;
      Provider.of<CatalogProvider>(context, listen: false)
          .registerRecentlySeenProducts(results);
      if (results.isNotEmpty) {
        _recordRecentSearchIfValid(query);
      }
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    });
  }

  void _clearActiveSearchFilter() {
    _searchController.clear();
    _onPosSearchChanged('');
    _requestSearchFocusSilently();
  }

  void _onProductScannedOrSearched(String query) async {
    _hideSearchHistoryPopover();
    if (query.trim().isEmpty) {
      final posProvider = Provider.of<PosProvider>(context, listen: false);
      if (posProvider.cart.isNotEmpty && !posProvider.isLoading && !_isCheckingOut) {
        _handleCheckout();
      }
      return;
    }
    final rawQuery = query.trim();
    String cleanQuery = rawQuery.toUpperCase();

    // FT-02: Limpiar inmediatamente el debounce y el controlador antes de cualquier await.
    // Evita la concatenación de códigos cuando el lector láser dispara en ráfaga
    // y cancela cualquier búsqueda por texto parcial en vuelo para ese mismo término.
    _debounceSearchTimer?.cancel();
    _searchController.clear();
    if (_searchQuery.isNotEmpty || _searchResults.isNotEmpty || _isSearching) {
      setState(() {
        _searchQuery = '';
        _searchResults = [];
        _isSearching = false;
      });
    }

    final posProvider = Provider.of<PosProvider>(context, listen: false);

    // 0a. Interceptar Etiquetas Térmicas de Lote (L#<batch_id> o L#<batch_id>#W#<gramos>)
    final parsedBatch = BatchBarcodeHelper.parse(cleanQuery);
    if (parsedBatch != null) {
      await _handleBatchBarcodeScan(cleanQuery, posProvider);
      return;
    }

    // 0. Interceptar Presupuestos (Código de barras PRES-)
    if (cleanQuery.startsWith('PRES-')) {
      setState(() => _isSearching = true);

      try {
        final repo =
            Provider.of<QuoteProvider>(context, listen: false).repository;
        final quote = await repo.getQuoteByNumber(cleanQuery);

        setState(() => _isSearching = false);

        if (quote != null) {
          // Mostrar diálogo de confirmación
          if (mounted) {
            final confirm = await AppConfirmDialog.show(
              context,
              title: 'Cargar Presupuesto: $cleanQuery',
              message:
                  '¿Desea limpiar la caja actual y cargar los ${quote.items.length} productos de este presupuesto?',
              confirmLabel: 'Cargar',
              cancelLabel: 'Cancelar',
              icon: Icons.request_quote_rounded,
            );

            if (confirm == true) {
              final settings = context.read<SettingsProvider>().settings;
              final customerProvider = context.read<CustomerProvider>();
              posProvider.loadQuoteToCart(quote, settings: settings, availableCustomers: customerProvider.customers);
              SnackBarService.success(
                  context, 'Presupuesto cargado listo para facturar.');
            }
          }
        } else {
          SnackBarService.error(
              context, 'Presupuesto no encontrado: "$cleanQuery"');
        }
      } catch (e) {
        setState(() => _isSearching = false);
        SnackBarService.error(context, 'Error al recuperar presupuesto: $e');
      }

      if (mounted) {
        _requestSearchFocusSilently();
      }
      return;
    }

    // 1. Intentamos buscar el código exactamente como se escaneó primero.
    // Esto es crucial por si el producto es unitario y su código EAN normal comienza con '2'.
    List<Product> results = (await posProvider.search(cleanQuery))
        .where((p) => p.active)
        .toList();
    if (mounted && results.isNotEmpty) {
      Provider.of<CatalogProvider>(context, listen: false)
          .registerRecentlySeenProducts(results);
    }

    bool appliedScaleLogic = false;
    double embeddedPrice = 0.0;
    String? scalePlu;

    // 2. Si no hubo coincidencias exactas, verificamos si es una etiqueta de balanza (13 dígitos, empieza en '2')
    if (results.isEmpty &&
        cleanQuery.length == 13 &&
        cleanQuery.startsWith('2')) {
      // Formato típico local: 1 (Prefijo) + 5 (PLU) + 6 (Precio Entero) + 1 (Dígito Verificador)
      final itemCodeStr = cleanQuery.substring(1, 6);
      final priceStr = cleanQuery.substring(6, 12);
      final pluQuery = int.parse(itemCodeStr).toString();
      scalePlu = pluQuery;
      embeddedPrice = double.parse(priceStr);

      // Hacemos una segunda búsqueda usando solamente el PLU extraído
      results = (await posProvider.search(pluQuery))
          .where((p) => p.active)
          .toList();

      if (results.isNotEmpty) {
        if (results.first.isSoldByWeight) {
          if (embeddedPrice == 0) {
            // Etiqueta de balanza inválida: el código tiene formato correcto pero precio $0.
            // Puede ser una etiqueta dañada o mal impresa. No agregamos al carrito silenciosamente.
            if (mounted) {
              SnackBarService.error(
                context,
                'Etiqueta de balanza inválida (precio \$0) para "${results.first.name}". '
                'Revise la etiqueta o ingrese el peso manualmente.',
              );
              _requestSearchFocusSilently();
            }
            return;
          }
          appliedScaleLogic = true;
        } else {
          if (embeddedPrice == 0) {
            // Es un ticket interno estándar (Ean13Generator sin balanza)
            appliedScaleLogic = false;
          } else {
            // El código tiene importe incrustado pero el producto no es pesado
            if (mounted) {
              SnackBarService.error(context,
                  'El producto "${results.first.name}" no se vende por peso. Revise la etiqueta.');
              _requestSearchFocusSilently();
            }
            return;
          }
        }
      }
    }

    if (!mounted) return;

    if (results.isEmpty) {
      // Antes de darlo por inexistente o abrir el diálogo de alta rápida, verificar si está dado de baja
      final inactiveProduct =
          await _findInactiveProductByCode(cleanQuery, scalePlu: scalePlu);
      if (!mounted) return;
      if (inactiveProduct != null) {
        SnackBarService.warning(
          context,
          'El producto "${inactiveProduct.name}" está dado de baja (inactivo) y no puede agregarse al carrito.',
        );
        _requestSearchFocusSilently();
        return;
      }

      final existingQuickItem = posProvider.cart.cast<CartItem?>().firstWhere(
        (it) =>
            it != null &&
            it.product.active &&
            it.product.barcode != null &&
            it.product.barcode!.trim().toUpperCase() == cleanQuery &&
            !it.product.isSoldByWeight,
        orElse: () => null,
      );
      if (existingQuickItem != null) {
        posProvider.updateQuantity(
          existingQuickItem,
          existingQuickItem.quantity + 1,
        );
        if (mounted) {
          _requestSearchFocusSilently();
        }
        return;
      }

      SnackBarService.error(context, 'Producto no encontrado: "$cleanQuery"');
      if (RegExp(r'^(?=.*\d)[A-Za-z0-9\-_]{5,32}$').hasMatch(cleanQuery)) {
        await _showUnrecognizedBarcodeDialog(cleanQuery);
      }
    } else if (appliedScaleLogic) {
      final product = results.first;
      if (!product.active) {
        SnackBarService.warning(
          context,
          'El producto "${product.name}" está dado de baja (inactivo) y no puede agregarse al carrito.',
        );
        _requestSearchFocusSilently();
        return;
      }
      double calcWeight = 0.0;

      if (product.sellingPrice > 0) {
        calcWeight = embeddedPrice / product.sellingPrice;
      } else {
        calcWeight = 1.0; // Fallback de seguridad
      }

      final offerProvider = Provider.of<OfferProvider>(context, listen: false);
      final promoPrice = offerProvider.getDiscountedPrice(product);
      final promoOffer = offerProvider.getActiveOfferForProduct(product.id, basePrice: product.sellingPrice);

      posProvider.submitWeighedProductWithPromo(
        product,
        calcWeight,
        promotionalPrice: promoPrice,
        promotionalLabel: promoOffer?.name,
        promotionalPeriodType: promoOffer?.periodType,
      );
    } else if (results.length == 1) {
      _recordRecentSearchIfValid(
        rawQuery,
        selectedProductId: results.first.id,
        selectedProduct: results.first,
      );
      _handleProductSelection(results.first);
    } else {
      _recordRecentSearchIfValid(rawQuery);
      await _showProductPickerDialog(results, rawQuery);
    }

    if (mounted) {
      _requestSearchFocusSilently();
    }
  }

  /// Diálogo para seleccionar entre múltiples resultados de búsqueda
  Future<void> _showProductPickerDialog(
      List<Product> results, String query) async {
    await showDialog(
      context: context,
      builder: (ctx) => AppModalShell(
        title: 'Resultados para "$query"',
        subtitle: '${results.length} coincidencias encontradas',
        icon: Icons.search_rounded,
        accent: AppModalAccent.blue,
        maxWidth: 500,
        useAlertDialogWrapper: true,
        onClose: () => Navigator.pop(ctx),
        bodyPadding: const EdgeInsets.symmetric(vertical: 8),
        body: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: results.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final p = results[i];
            bool canUseScale = true;
            try {
              canUseScale = Provider.of<SettingsProvider?>(context, listen: false)
                      ?.safeVerticalProfile
                      .canUseScaleWeight ??
                  true;
            } catch (_) {}
            final preferDiscrete = p.isDiscreteFractionalItem(
              businessUsesScaleWeight: canUseScale,
            );
            final isNonScale =
                p.isMetricOrLiquidUnit || preferDiscrete || !canUseScale;
            final unitLbl = Product.resolveQuantityUnitLabel(
              unitType: p.unitType,
              isSoldByWeight: p.isSoldByWeight,
              preferDiscreteUn: preferDiscrete,
            );
            final spec = p.technicalSpec?.trim();
            final loc = p.storageLocation?.trim();
            final metaParts = <String>[
              if (spec != null && spec.isNotEmpty) spec,
              if (loc != null && loc.isNotEmpty) loc,
              p.isSoldByWeight
                  ? 'Por $unitLbl · \$${p.sellingPrice.toCurrency()}/$unitLbl'
                  : '\$${p.sellingPrice.toCurrency()}',
            ];
            return Material(
              color: Colors.transparent,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: p.isSoldByWeight
                      ? (isNonScale ? Colors.teal.shade50 : Colors.orange.shade100)
                      : Colors.blue.shade50,
                  child: Icon(
                    p.isSoldByWeight
                        ? (isNonScale
                            ? Icons.straighten_rounded
                            : Icons.scale_rounded)
                        : Icons.inventory_2_outlined,
                    color: p.isSoldByWeight
                        ? (isNonScale
                            ? Colors.teal.shade700
                            : Colors.orange.shade700)
                        : Colors.blue.shade700,
                    size: 20,
                  ),
                ),
                title: Text(p.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  metaParts.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing:
                    const Icon(Icons.add_circle_outline, color: Colors.green),
                onTap: () {
                  Navigator.pop(ctx);
                  _recordRecentSearchIfValid(
                    query,
                    selectedProductId: p.id,
                    selectedProduct: p,
                  );
                  _handleProductSelection(p);
                },
              ),
            );
          },
        ),
        footerActions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleBatchBarcodeScan(
    String rawCode,
    PosProvider posProvider,
  ) async {
    setState(() => _isSearching = true);
    try {
      final res = await posProvider.scanBatch(rawCode);
      if (!mounted) return;
      setState(() => _isSearching = false);

      final isWrittenOff = res['is_written_off'] == true;
      final isExpired = res['is_expired'] == true;
      final canSell = res['can_sell'] == true;
      final isExhausted = res['is_exhausted'] == true;
      final blockReason = res['block_reason']?.toString();
      final batchMap = res['batch'] is Map
          ? Map<String, dynamic>.from(res['batch'] as Map)
          : <String, dynamic>{};
      final batchId = (batchMap['id'] as num?)?.toInt();
      final batchCode = batchMap['batch_code']?.toString();
      final batchExpirationDate = batchMap['expiration_date']?.toString();

      if (isWrittenOff) {
        SnackBarService.error(
          context,
          blockReason ??
              'Lote ${batchCode ?? ''} dado de baja. Retire la bandeja del exhibidor.',
        );
        _requestSearchFocusSilently();
        return;
      }

      if (isExpired && !canSell) {
        final authorize = await AppConfirmDialog.show(
          context,
          title: 'Lote Vencido',
          message:
              '${blockReason ?? 'El lote ${batchCode ?? ''} se encuentra vencido.'}\n\nPara continuar igualmente con la venta se requiere autorización de Supervisor.',
          confirmLabel: 'Autorizar Venta',
          cancelLabel: 'Retirar / Cancelar',
          icon: Icons.warning_amber_rounded,
          isDestructive: true,
        );
        if (authorize != true || !mounted) {
          _requestSearchFocusSilently();
          return;
        }
        final pinResult = await AdminPinDialog.verifyAndGetPin(
          context,
          action: 'Vender bandeja vencida (${batchCode ?? rawCode})',
        );
        if (pinResult == null || !mounted) {
          _requestSearchFocusSilently();
          return;
        }
        if (pinResult != 'ALREADY_AUTHORIZED') {
          posProvider.setAuthorizedExpiredBatchPin(pinResult);
        }
      } else if (isExpired && canSell) {
        SnackBarService.warning(
          context,
          'Aviso: lote ${batchCode ?? ''} vencido (venta autorizada).',
        );
      } else if (isExhausted) {
        SnackBarService.warning(
          context,
          'Aviso: el lote ${batchCode ?? ''} figura sin saldo disponible en sistema.',
        );
      }

      final productMap = Map<String, dynamic>.from(res['product'] as Map);
      final product = ProductModel.fromJson(productMap);
      final weightKg = (res['weight_kg'] as num?)?.toDouble();

      if (weightKg != null && weightKg > 0) {
        final offerProvider = Provider.of<OfferProvider>(context, listen: false);
        final promoPrice = offerProvider.getDiscountedPrice(product);
        final promoOffer = offerProvider.getActiveOfferForProduct(
          product.id,
          basePrice: product.sellingPrice,
        );
        posProvider.submitWeighedProductWithPromo(
          product,
          weightKg,
          promotionalPrice: promoPrice,
          promotionalLabel: promoOffer?.name,
          promotionalPeriodType: promoOffer?.periodType,
          batchId: batchId,
          batchCode: batchCode,
          batchExpirationDate: batchExpirationDate,
        );
        SnackBarService.success(
          context,
          '${product.name} (${weightKg.toStringAsFixed(3)} kg • Lote ${batchCode ?? '#$batchId'}) agregado.',
        );
        _requestSearchFocusSilently();
        return;
      }

      _handleProductSelection(
        product,
        batchId: batchId,
        batchCode: batchCode,
        batchExpirationDate: batchExpirationDate,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
        SnackBarService.error(
          context,
          e.toString().replaceFirst('Exception: ', ''),
        );
        _requestSearchFocusSilently();
      }
    }
  }

  void _handleProductSelection(
    Product product, {
    int? batchId,
    String? batchCode,
    String? batchExpirationDate,
  }) {
    if (!product.active) {
      SnackBarService.warning(
        context,
        'El producto "${product.name}" está dado de baja (inactivo) y no puede venderse.',
      );
      _requestSearchFocusSilently();
      return;
    }

    if (_searchQuery.trim().isNotEmpty) {
      _recordRecentSearchIfValid(
        _searchQuery,
        selectedProductId: product.id,
        selectedProduct: product,
      );
    } else {
      try {
        Provider.of<CatalogProvider>(context, listen: false)
            .registerRecentlySeenProducts([product]);
      } catch (_) {}
    }

    final posProvider = Provider.of<PosProvider>(context, listen: false);
    if (!product.isSoldByWeight) {
      final catalogProducts =
          Provider.of<CatalogProvider>(context, listen: false).activeProducts;
      final blockMsg = posProvider.validateUnitStockConstraint(
        product,
        1.0,
        catalogProducts: catalogProducts,
      );
      if (blockMsg != null) {
        SnackBarService.error(context, blockMsg);
        _requestSearchFocusSilently();
        return;
      }
    }
    final offerProvider = Provider.of<OfferProvider>(context, listen: false);
    final promoPrice = offerProvider.getDiscountedPrice(product);
    final promoOffer = offerProvider.getActiveOfferForProduct(product.id, basePrice: product.sellingPrice);

    final success = posProvider.requestAddToCartWithPromo(
      product,
      promotionalPrice: promoPrice,
      promotionalLabel: promoOffer?.name,
      promotionalPeriodType: promoOffer?.periodType,
      batchId: batchId,
      batchCode: batchCode,
      batchExpirationDate: batchExpirationDate,
    );
    if (success) {
      _requestSearchFocusSilently();
    } else {
      // Es producto por peso, pedir peso por Modal
      _showWeightModal(
        product,
        posProvider,
        promotionalPrice: promoPrice,
        promotionalLabel: promoOffer?.name,
        promotionalPeriodType: promoOffer?.periodType,
        batchId: batchId,
        batchCode: batchCode,
        batchExpirationDate: batchExpirationDate,
      );
    }
  }

  void _handleDecrementProduct(Product product) {
    final posProvider = Provider.of<PosProvider>(context, listen: false);

    CartItem? cartItem;
    try {
      cartItem = posProvider.cart.firstWhere(
        (item) => item.product.id == product.id,
      );
    } catch (_) {
      return;
    }

    if (product.isSoldByWeight || cartItem.quantity <= 1) {
      posProvider.removeFromCart(cartItem);
    } else {
      posProvider.updateQuantity(cartItem, cartItem.quantity - 1);
    }
    _requestSearchFocusSilently();
  }


  /// Color de acento semántico por categoría (misma paleta que las tarjetas del catálogo).
  static const List<Color> _categoryPalette = [
    Color(0xFF3F51B5),
    Color(0xFF009688),
    Color(0xFF2196F3),
    Color(0xFF673AB7),
    Color(0xFF00BCD4),
    Color(0xFF607D8B),
  ];

  Color _quickLookAccent(Product product) {
    if (product.isSoldByWeight) return Colors.orange.shade700;
    if (product.category?.name != null && product.category!.name.isNotEmpty) {
      final name = product.category!.name.toLowerCase();
      final hash = name.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
      return _categoryPalette[hash % _categoryPalette.length];
    }
    return Colors.blueGrey.shade600;
  }

  String _formatQuickLookStock(
    double qty,
    bool isByWeight, {
    String? unitShortLabel,
  }) =>
      qty.toUnitStockDisplay(
        isSoldByWeight: isByWeight,
        unitSuffix: unitShortLabel ?? 'u.',
        weightUnit: unitShortLabel,
      );

  Widget _buildQuickLookMetaChip({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickLookMetaBadges(Product product) {
    final location = product.storageLocation?.trim();
    final spec = product.technicalSpec?.trim();
    final sku = product.supplierSku?.trim();
    final hasAny = (location != null && location.isNotEmpty) ||
        (spec != null && spec.isNotEmpty) ||
        (sku != null && sku.isNotEmpty);
    if (!hasAny) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          if (location != null && location.isNotEmpty)
            _buildQuickLookMetaChip(
              icon: Icons.place_outlined,
              label: 'Ubic: $location',
              color: Colors.amber.shade900,
              bgColor: Colors.amber.shade50,
              borderColor: Colors.amber.shade300,
            ),
          if (spec != null && spec.isNotEmpty)
            _buildQuickLookMetaChip(
              icon: Icons.straighten_outlined,
              label: spec,
              color: Colors.blueGrey.shade800,
              bgColor: Colors.blueGrey.shade50,
              borderColor: Colors.blueGrey.shade200,
            ),
          if (sku != null && sku.isNotEmpty)
            _quickLookCodeChip('Prov', sku),
        ],
      ),
    );
  }

  void _showImageZoomDialog(BuildContext context, Product product) {
    if (product.imageUrl == null || product.imageUrl!.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AppModalShell(
        title: product.name,
        subtitle: 'Podés hacer zoom con la rueda del mouse o gestos táctiles',
        icon: Icons.image_outlined,
        accent: AppModalAccent.slate,
        maxWidth: 620,
        maxHeight: 620,
        onClose: () => Navigator.pop(ctx),
        bodyPadding: const EdgeInsets.all(16),
        body: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: InteractiveViewer(
            clipBehavior: Clip.none,
            minScale: 1.0,
            maxScale: 3.5,
            child: CachedNetworkImage(
              imageUrl: product.imageUrl!,
              fit: BoxFit.contain,
              placeholder: (context, url) => const Center(
                child: Padding(
                  padding: EdgeInsets.all(40.0),
                  child: CircularProgressIndicator(),
                ),
              ),
              errorWidget: (context, url, error) => const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 64,
                  color: Colors.grey,
                ),
              ),
            ),
          ),
        ),
        footerActions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showProductQuickLookDialog(Product product) {
    _hideSearchHistoryPopover();
    if (product.active) {
      _recordRecentSearchIfValid(
        _searchQuery.trim().isNotEmpty ? _searchQuery : null,
        selectedProduct: product,
      );
    }
    final localTerminal =
        Provider.of<LocalTerminalProvider>(context, listen: false);
    final posProvider = Provider.of<PosProvider>(context, listen: false);
    final offerProv = Provider.of<OfferProvider>(context, listen: false);
    final isPinned = localTerminal.pinnedProductIds.contains(product.id);
    final isByWeight = product.isSoldByWeight;
    final accent = _quickLookAccent(product);

    double cartQty = 0;
    for (final item in posProvider.cart) {
      if (item.product.id == product.id) {
        cartQty += item.quantity;
      }
    }

    final promoPrice = offerProv.getDiscountedPrice(product);
    final hasPromo = promoPrice != null &&
        promoPrice > 0 &&
        promoPrice < product.sellingPrice;
    final lowStock = product.isCombo
        ? product.stock <= (product.minStock ?? 0)
        : (product.minStock != null && product.stock <= product.minStock!);

    final uri = product.imageUrl != null && product.imageUrl!.isNotEmpty
        ? Uri.tryParse(product.imageUrl!)
        : null;
    final hasImage =
        uri != null && uri.hasScheme && uri.hasAuthority && uri.host.isNotEmpty;

    final bool canUseHardwareCalculator;
    final bool isHardwareVertical;
    {
      SettingsProvider? settingsProv;
      List<dynamic>? rawRubros;
      try {
        settingsProv = Provider.of<SettingsProvider>(context, listen: false);
        rawRubros = Provider.of<CatalogProvider?>(context, listen: false)?.safeRubros;
      } catch (_) {
        settingsProv = null;
      }
      canUseHardwareCalculator = settingsProv?.canUseHardwareCalculatorFor(
            product: product,
            rubros: rawRubros?.cast() ?? const [],
          ) ??
          false;
      isHardwareVertical =
          (settingsProv?.safeIsHardwareStore ?? false) ||
              canUseHardwareCalculator;
    }

    showDialog(
      context: context,
      builder: (ctx) => AppModalShell(
        title: 'Vista Rápida de Producto',
        subtitle: product.category?.name ?? 'Ficha rápida de mostrador',
        icon: isByWeight ? Icons.scale_rounded : Icons.inventory_2_outlined,
        accent:
            isHardwareVertical ? AppModalAccent.teal : AppModalAccent.blue,
        compact: true,
        maxWidth: 490,
        onClose: () => Navigator.pop(ctx),
        bodyPadding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                // ── Header: Hero Media Showcase Enterprise o Fallback Compacto ──
                if (hasImage) ...[
                  // ── Hero Media Showcase Enterprise (175px) ──
                  Container(
                    width: double.infinity,
                    height: 175,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () =>
                                  _showImageZoomDialog(context, product),
                              borderRadius: BorderRadius.circular(13),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: CachedNetworkImage(
                                  imageUrl: product.imageUrl!,
                                  fit: BoxFit.contain,
                                  placeholder: (context, url) => const Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  ),
                                  errorWidget: (context, url, error) => Icon(
                                    isByWeight
                                        ? Icons.scale_rounded
                                        : Icons.inventory_2_outlined,
                                    color: accent,
                                    size: 48,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Badges flotantes superiores
                          Positioned(
                            top: 8,
                            left: 8,
                            right: 8,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                if (product.category?.name != null)
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.white.withValues(alpha: 0.92),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                            color: accent.withValues(alpha: 0.35)),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.05),
                                            blurRadius: 4,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        product.category!.name.toUpperCase(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: accent,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  const SizedBox.shrink(),
                                const SizedBox(width: 8),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (hasPromo)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 3),
                                        margin:
                                            const EdgeInsets.only(right: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFD97706),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                                Icons
                                                    .local_fire_department_rounded,
                                                size: 11,
                                                color: Colors.white),
                                            SizedBox(width: 2),
                                            Text(
                                              'OFERTA',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    Material(
                                      color:
                                          Colors.white.withValues(alpha: 0.92),
                                      shape: const CircleBorder(),
                                      elevation: 1,
                                      shadowColor: Colors.black26,
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: () => _showImageZoomDialog(
                                            context, product),
                                        child: const Tooltip(
                                          message: 'Ampliar imagen (HD)',
                                          child: Padding(
                                            padding: EdgeInsets.all(6.0),
                                            child: Icon(
                                              Icons.fullscreen_rounded,
                                              size: 18,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Hint inferior derecho sutil
                          Positioned(
                            bottom: 6,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.zoom_in,
                                      size: 12, color: Colors.grey.shade600),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Clic para ampliar',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Nombre e identidad del producto debajo del Hero
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (product.internalCode.isNotEmpty)
                        _quickLookCodeChip('Int', product.internalCode),
                      if (product.barcode != null &&
                          product.barcode!.isNotEmpty)
                        _quickLookCodeChip('EAN', product.barcode!),
                    ],
                  ),
                  _buildQuickLookMetaBadges(product),
                ] else ...[
                  // ── Fallback Compacto para productos SIN imagen ──
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: accent.withValues(alpha: 0.25)),
                        ),
                        child: Center(
                          child: Icon(
                            isByWeight
                                ? Icons.scale_rounded
                                : Icons.inventory_2_outlined,
                            color: accent,
                            size: 30,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (product.category?.name != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                margin: const EdgeInsets.only(bottom: 4),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: accent.withValues(alpha: 0.35)),
                                ),
                                child: Text(
                                  product.category!.name,
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      color: accent,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            Text(
                              product.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  height: 1.2),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (product.internalCode.isNotEmpty)
                                  _quickLookCodeChip(
                                      'Int', product.internalCode),
                                if (product.barcode != null &&
                                    product.barcode!.isNotEmpty)
                                  _quickLookCodeChip('EAN', product.barcode!),
                              ],
                            ),
                            _buildQuickLookMetaBadges(product),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),

                // ── KPIs: Stock + Ventas/Ticket ──
                Row(
                  children: [
                    Expanded(
                      child: _quickLookKpiCard(
                        icon: Icons.inventory_2_outlined,
                        iconColor: lowStock
                            ? Colors.orange.shade700
                            : Colors.green.shade600,
                        label: 'Stock Actual',
                        value: _formatQuickLookStock(
                          product.stock,
                          isByWeight,
                          unitShortLabel: product.unitShortLabel,
                        ),
                        valueColor: lowStock ? Colors.orange.shade800 : null,
                        footer: product.minStock != null
                            ? 'Mín: ${_formatQuickLookStock(product.minStock!, isByWeight, unitShortLabel: product.unitShortLabel)}'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _quickLookKpiCard(
                        icon: Icons.local_fire_department_rounded,
                        iconColor: const Color(0xFFE65100),
                        label: 'Ventas',
                        value: product.salesCount > 0
                            ? '${product.salesCount} vend.'
                            : 'Sin ventas',
                        footer: cartQty > 0
                            ? 'En ticket: ${_formatQuickLookStock(cartQty, isByWeight, unitShortLabel: product.unitShortLabel)}'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Cuadro de precios ──
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      _buildInfoRow('Precio Base',
                          '\$${product.sellingPrice.toCurrency()}'),
                      if (hasPromo)
                        _buildInfoRow(
                          '🔥 Oferta Activa',
                          '\$${promoPrice.toCurrency()}',
                          valueColor: const Color(0xFFB45309),
                        ),
                      ...() {
                        final settings = () {
                          try {
                            return Provider.of<SettingsProvider>(
                              context,
                              listen: false,
                            ).settings;
                          } catch (_) {
                            return null;
                          }
                        }();
                        final previews =
                            ProductPricingCalculator.buildMultiPricePreviews(
                          product: product,
                          multiPriceEnabled:
                              settings?.hasMultiPriceEnabled == true,
                          wholesaleFactor: settings?.wholesalePriceFactor ??
                              posProvider.wholesaleFactor,
                          cardFactor: settings?.cardPriceFactor ??
                              posProvider.cardFactor,
                          customTiers: settings?.customPriceTiers ?? const [],
                          promotionalPrice: hasPromo ? promoPrice : null,
                          hasExplicitOffer: hasPromo,
                          cardSurchargeOnOffersMode:
                              posProvider.cardSurchargeOnOffersMode,
                          discountTierOnOffersMode:
                              posProvider.discountTierOnOffersMode,
                          ignoreFixedPrices:
                              settings?.ignoreProductFixedPrices ??
                                  posProvider.ignoreProductFixedPrices,
                        );
                        return previews.map(
                          (preview) => _buildInfoRow(
                            'Precio ${preview.label}${preview.isFixedOverride ? ' (Fijo)' : ''}',
                            '\$${preview.price.toCurrency()}',
                          ),
                        );
                      }(),
                      if (product.priceTiers != null &&
                          product.priceTiers!.isNotEmpty) ...[
                        const Divider(height: 16),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Tramos por cantidad:',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12.5)),
                        ),
                        const SizedBox(height: 4),
                        ...product.priceTiers!.map((tier) {
                          final minQ = double.tryParse(
                                  tier['min_quantity']?.toString() ?? '1') ??
                              1.0;
                          final uPrice = double.tryParse(
                                  tier['unit_price']?.toString() ?? '0') ??
                              0.0;
                          final qtyText = minQ == minQ.toInt()
                              ? minQ.toInt().toString()
                              : minQ.toStringAsFixed(2);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('$qtyText+ unidades',
                                    style: const TextStyle(
                                        fontSize: 12.5, color: Colors.black54)),
                                Text('\$${uPrice.toCurrency()}',
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
                if (product.isCombo &&
                    product.comboIngredients != null &&
                    product.comboIngredients!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.layers_outlined,
                                size: 15, color: Colors.amber.shade900),
                            const SizedBox(width: 6),
                            Text(
                              'Ingredientes del Combo',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ...product.comboIngredients!.map((ing) {
                          final ingId = (ing['id'] as num?)?.toInt();
                          final ingName = ing['name']?.toString() ?? 'Producto';
                          final reqQty =
                              (ing['quantity'] as num?)?.toDouble() ?? 1.0;
                          final catalogMatch = ingId != null
                              ? Provider.of<CatalogProvider>(context,
                                      listen: false)
                                  .products
                                  .where((p) => p.id == ingId)
                                  .firstOrNull
                              : null;
                          final ingStock = catalogMatch?.stock ??
                              ((ing['stock'] as num?)?.toDouble() ?? 0.0);
                          final ingByWeight = catalogMatch?.isSoldByWeight ??
                              (ing['is_sold_by_weight'] == true ||
                                  ing['is_sold_by_weight'] == 1);
                          final ingUnitShort = catalogMatch?.unitShortLabel ??
                              (ing['unit_type'] != null
                                  ? Product.shortLabelFor(
                                      ing['unit_type'].toString())
                                  : null);
                          final hasEnough = ingStock >= reqQty;
                          final reqFmt = reqQty.toQty();

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Icon(
                                  hasEnough
                                      ? Icons.check_circle_rounded
                                      : Icons.error_rounded,
                                  size: 14,
                                  color: hasEnough
                                      ? Colors.green.shade600
                                      : Colors.red.shade600,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '$ingName (x$reqFmt)',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: hasEnough
                                        ? Colors.green.shade50
                                        : Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: hasEnough
                                          ? Colors.green.shade200
                                          : Colors.red.shade200,
                                    ),
                                  ),
                                  child: Text(
                                    'Stock: ${_formatQuickLookStock(ingStock, ingByWeight, unitShortLabel: ingUnitShort)}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: hasEnough
                                          ? Colors.green.shade800
                                          : Colors.red.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            footerLeading: TextButton.icon(
              icon: Icon(
                isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                size: 17,
              ),
              label: Text(isPinned ? 'Desfijar' : 'Fijar'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () {
                localTerminal.togglePinnedProduct(product.id);
                Navigator.pop(ctx);
                // Si estamos en filtro 'pinned' y ya no hay productos fijados, cambiar a 'all'
                if (_quickAccessFilter == 'pinned' &&
                    localTerminal.pinnedProductIds.isEmpty) {
                  setState(() {
                    _quickAccessFilter = 'all';
                  });
                }
              },
            ),
            footerActions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
              if (canUseHardwareCalculator)
                OutlinedButton.icon(
                  icon: const Icon(Icons.straighten_rounded, size: 16),
                  label: const Text('Calcular (F7)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.tealDark,
                    side: const BorderSide(color: AppColors.tealDark),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (product.active) {
                      _recordRecentSearchIfValid(
                        _searchQuery.trim().isNotEmpty ? _searchQuery : null,
                        selectedProduct: product,
                      );
                    }
                    _openHardwareCalculatorDialog(initialProduct: product);
                  },
                ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_shopping_cart, size: 17),
                label: const Text('Agregar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _handleProductSelection(product);
                },
              ),
            ],
          ),
        ).then((_) {
      if (mounted) _requestSearchFocusSilently();
    });
  }

  Widget _quickLookCodeChip(String tag, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$tag: ',
            style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600),
          ),
          Text(value,
              style:
                  const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _quickLookKpiCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    Color? valueColor,
    String? footer,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: iconColor),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: valueColor ?? const Color(0xFF1E293B)),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(footer,
                  style:
                      TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: valueColor)),
        ],
      ),
    );
  }

  /// Guía visual de atajos de teclado del POS, con teclas estilo "keycap".
  /// Se abre con F1 o con el botón ⌨️ de la barra de Acceso Rápido.
  void _showKeyboardShortcutsHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AppModalShell(
        title: 'Guía Rápida de Teclado POS',
        subtitle: 'Atajos de mostrador, cobro en 1 segundo y gestión rápida',
        icon: Icons.keyboard_rounded,
        accent: AppModalAccent.slate,
        compact: true,
        maxWidth: 540,
        maxHeight: 600,
        onClose: () => Navigator.pop(ctx),
        bodyPadding: const EdgeInsets.all(16),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _shortcutSection(
              Icons.bolt_rounded,
              AppColors.amber,
              'Flujo "Doble Enter" (Cobro en 1 segundo)',
              [
                _shortcutRow(['Enter'],
                    'con buscador vacío → Abre ventana de Cobro'),
                _shortcutRow(['Enter'],
                    'en ventana de Cobro → Confirma pago exacto en Efectivo'),
                _shortcutRow(
                    ['F9', 'F12'], 'Cobrar directo en cualquier momento'),
              ],
            ),
            const SizedBox(height: 10),
            _shortcutSection(
              Icons.shopping_cart_outlined,
              AppColors.primaryDark,
              'Carrito y Acceso Rápido',
              [
                _shortcutRow(['F3'],
                    'Crear Producto o Combo Rápido (Temporal o en Catálogo)'),
                _shortcutRow(['Ctrl', 'E'],
                    'Renombrar último ítem para Factura / Ticket (Alias)'),
                _shortcutRow(['Ctrl', '1..9'],
                    'Agrega el producto 1 al 9 de la grilla'),
                _shortcutRow(['+', '-'],
                    'con buscador vacío → Suma o resta 1 u. al último ítem'),
                _shortcutRow(['Supr'],
                    'con buscador vacío → Elimina el último ítem del carrito'),
                _shortcutRow(['Clic Der.'],
                    'sobre producto → Vista Rápida (stock, precios, fijar)'),
              ],
            ),
            const SizedBox(height: 10),
            _shortcutSection(
              Icons.payments_outlined,
              AppColors.emerald,
              'Ventana de Cobro (Desglose de Pago)',
              [
                _shortcutRow(['Ctrl', '1..8'],
                    'Métodos de pago (Efectivo, Point, QR, Tarjetas, Transf., Cta. Cte., Cheque)'),
                _shortcutRow(['F2'], 'Pago exacto auto-ajustable en efectivo'),
                _shortcutRow(['F4'], 'Agregar otro medio de pago (Pago Mixto)'),
                _shortcutRow(['F6'], 'Asociar / Buscar Cliente'),
                _shortcutRow(['F7'], 'Marcar / Desmarcar Imprimir Comprobante'),
                _shortcutRow(['F8'], 'Marcar / Desmarcar Vista Previa'),
                _shortcutRow(
                    ['F9'], 'Alternar Ticket Común / Factura Fiscal ARCA'),
                _shortcutRow(
                    ['F10'], 'Alternar Logística (Retira / Envío / Acopio)'),
                _shortcutRow(['Enter'], 'Confirmar Venta'),
                _shortcutRow(
                    ['Esc'], 'Cerrar ventana de Cobro (conserva borrador)'),
              ],
            ),
            const SizedBox(height: 10),
            _shortcutSection(
              Icons.folder_special_outlined,
              AppColors.indigo,
              'Orden en Espera, Clientes y Filtros',
              [
                _shortcutRow(['F4'], 'Poner el carrito actual en Espera'),
                _shortcutRow(
                    ['F5'], 'Consultar precio y stock sin agregar al carrito'),
                _shortcutRow(['F6'], 'Asociar / Buscar Cliente al carrito'),
                if (context.read<SettingsProvider>().canUseHardwareCalculatorFor(
                      rubros: Provider.of<CatalogProvider?>(context, listen: false)
                              ?.safeRubros ??
                          const [],
                    ))
                  _shortcutRow(['F7'],
                      'Calculadora Rápida Ferretera (Machimbre / Chapas / Pintura)'),
                _shortcutRow(['Esc'],
                    'Cierra ventana de Cobro, limpia buscador o vuelve a "Todos"'),
                _shortcutRow(['F1'], 'Abre esta guía de ayuda'),
              ],
            ),
          ],
        ),
        footerActions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido (Esc)'),
          ),
        ],
      ),
    ).then((_) {
      if (mounted) _requestSearchFocusSilently();
    });
  }

  Widget _shortcutSection(
    IconData icon,
    Color accent,
    String title,
    List<Widget> rows,
  ) {
    return AppSectionCard(
      title: title,
      icon: icon,
      accent: accent,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }

  Widget _shortcutRow(List<String> keys, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 150,
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (var i = 0; i < keys.length; i++) ...[
                  _keycap(keys[i]),
                  if (i < keys.length - 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('+',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(description,
                style: const TextStyle(fontSize: 12.5, height: 1.3)),
          ),
        ],
      ),
    );
  }

  Widget _keycap(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade400, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF334155),
        ),
      ),
    );
  }
  void _showWeightModal(
    Product product,
    PosProvider provider, {
    double? promotionalPrice,
    String? promotionalLabel,
    String? promotionalPeriodType,
    int? batchId,
    String? batchCode,
    String? batchExpirationDate,
  }) {
    SettingsProvider? settingsProv;
    List<dynamic>? rawRubros;
    try {
      settingsProv = context.read<SettingsProvider?>();
      rawRubros = Provider.of<CatalogProvider?>(context, listen: false)?.safeRubros;
    } catch (_) {}
    final businessUsesScale =
        settingsProv?.safeVerticalProfile.canUseScaleWeight ?? true;
    final preferDiscreteUn = product.isDiscreteFractionalItem(
      businessUsesScaleWeight: businessUsesScale,
    );
    final isHardwareStore = settingsProv?.safeIsHardwareStore ?? false;
    final canUseF7 = settingsProv?.canUseHardwareCalculatorFor(
          product: product,
          rubros: rawRubros?.cast() ?? const [],
        ) ??
        false;
    final isHardwareFractionalMode = isHardwareStore ||
        product.isMetricOrLiquidUnit ||
        preferDiscreteUn ||
        !businessUsesScale;
    final unitShort = Product.resolveQuantityUnitLabel(
      unitType: product.unitType,
      isSoldByWeight: product.isSoldByWeight,
      preferDiscreteUn: preferDiscreteUn,
    );
    final double maxLimit = isHardwareFractionalMode ? 100000.0 : 1000.0;
    bool openedF7Calculator = false;

    showDialog(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          return _ManagedControllerScope(
            builder: (dialogContext, weightController, isDialogMounted) {
              return ValueListenableBuilder<TextEditingValue>(
                  valueListenable: weightController,
                  builder: (dialogContext, value, child) {
                    final parsedVal =
                        double.tryParse(value.text.trim().replaceAll(',', '.'));
                    final isValid = parsedVal != null &&
                        parsedVal >= 0.001 &&
                        parsedVal < maxLimit;
                    return AppModalShell(
                      title: isHardwareFractionalMode
                          ? 'Cantidad / Medida ($unitShort) - ${product.name}'
                          : 'Ingresar Peso (Kg) - ${product.name}',
                      icon: Icons.scale_rounded,
                      accent: AppModalAccent.amber,
                      compact: true,
                      maxWidth: 460,
                      useAlertDialogWrapper: true,
                      onClose: () => Navigator.pop(dialogContext),
                      bodyPadding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                      body: TextField(
                        controller: weightController,
                        autofocus: true,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: isHardwareFractionalMode
                              ? 'Cantidad / Medida en $unitShort (Ej: 2.5)'
                              : 'Peso Exacto (Ej: 1.500)',
                          hintText: isHardwareFractionalMode ? '0.00' : '0.000',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          suffixText: isHardwareFractionalMode ? unitShort : 'KG',
                          helperText: isHardwareFractionalMode
                              ? 'Acepta enteros o decimales (ej: 1.5 $unitShort)'
                              : 'Ejemplo: 0.5 = 500 gramos',
                        ),
                        onSubmitted: (val) {
                          if (isValid) {
                            _processWeight(
                              val,
                              product,
                              provider,
                              dialogContext,
                              promotionalPrice: promotionalPrice,
                              promotionalLabel: promotionalLabel,
                              promotionalPeriodType: promotionalPeriodType,
                              batchId: batchId,
                              batchCode: batchCode,
                              batchExpirationDate: batchExpirationDate,
                              maxLimit: maxLimit,
                              unitShortLabel: unitShort,
                              isHardwareFractionalMode: isHardwareFractionalMode,
                            );
                          }
                        },
                      ),
                      footerActions: [
                        if (!isHardwareFractionalMode)
                          Consumer<LocalTerminalProvider>(
                            builder: (ctx, localTerminal, _) {
                              final comPort = localTerminal.scaleComPort;
                              final isConfigured = comPort.trim().isNotEmpty;
                              return OutlinedButton.icon(
                                onPressed: () {
                                  if (!isConfigured) {
                                    showTerminalPeripheralsDialog(dialogContext);
                                    return;
                                  }
                                  _readWeightFromScale(
                                      comPort, weightController,
                                      isDialogMounted: isDialogMounted);
                                },
                                icon: Icon(Icons.scale_rounded,
                                    color: isConfigured ? Colors.blueGrey : Colors.grey),
                                label: Text(
                                  isConfigured ? 'Leer Balanza' : 'Configurar Balanza',
                                  style: TextStyle(
                                    color: isConfigured ? Colors.blueGrey : Colors.grey,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: isConfigured ? Colors.blueGrey : Colors.grey,
                                  side: BorderSide(
                                    color: isConfigured ? Colors.blueGrey : Colors.grey.shade400,
                                  ),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                              );
                            },
                          ),
                        if (canUseF7)
                          OutlinedButton.icon(
                            onPressed: () {
                              openedF7Calculator = true;
                              Navigator.pop(dialogContext);
                              _openHardwareCalculatorDialog(initialProduct: product);
                            },
                            icon: const Icon(Icons.calculate_outlined, size: 18),
                            label: const Text('Abrir Calculadora F7'),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Cancelar'),
                        ),
                        FilledButton(
                          onPressed: isValid
                              ? () {
                                  _processWeight(
                                    weightController.text,
                                    product,
                                    provider,
                                    dialogContext,
                                    promotionalPrice: promotionalPrice,
                                    promotionalLabel: promotionalLabel,
                                    promotionalPeriodType: promotionalPeriodType,
                                    batchId: batchId,
                                    batchCode: batchCode,
                                    batchExpirationDate: batchExpirationDate,
                                    maxLimit: maxLimit,
                                    unitShortLabel: unitShort,
                                    isHardwareFractionalMode:
                                        isHardwareFractionalMode,
                                  );
                                }
                              : null,
                          child: const Text('Agregar'),
                        )
                      ],
                    );
                  });
            },
          );
        }).then((_) {
      if (!openedF7Calculator) {
        _requestSearchFocusSilently();
      }
    });
  }

  void _readWeightFromScale(
      String comPort, TextEditingController controller,
      {bool Function()? isDialogMounted}) async {
    final trimmedPort = comPort.trim();
    if (trimmedPort.isEmpty) {
      if (mounted) {
        SnackBarService.warning(
          context,
          'La balanza no está configurada en esta terminal.',
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Leyendo balanza en $trimmedPort...'),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    try {
      final result = await ScaleSerialService.instance.readWeight(trimmedPort);

      if (!mounted || !(isDialogMounted?.call() ?? true)) return;

      if (result.success && result.weightKg != null) {
        final weightStr = result.weightKg!.toStringAsFixed(3);
        controller.text = weightStr;
        controller.selection = TextSelection.fromPosition(
          TextPosition(offset: weightStr.length),
        );
        SnackBarService.success(context, 'Lectura exitosa: $weightStr Kg');
      } else {
        SnackBarService.error(
          context,
          result.errorMessage ?? 'No se pudo obtener el peso de la balanza.',
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarService.error(context, 'Error al comunicar con la balanza: $e');
      }
    }
  }

  void _processWeight(
    String value,
    Product product,
    PosProvider provider,
    BuildContext dialogContext, {
    double? promotionalPrice,
    String? promotionalLabel,
    String? promotionalPeriodType,
    int? batchId,
    String? batchCode,
    String? batchExpirationDate,
    double maxLimit = 1000.0,
    String unitShortLabel = 'Kg',
    bool isHardwareFractionalMode = false,
  }) {
    // Reemplaza comas por puntos en caso de que teclados latinos obligen coma
    String sanitizedValue = value.trim().replaceAll(',', '.');
    final weight = double.tryParse(sanitizedValue);

    // Validación alineada con ProcessSaleRequest (min:0.001) y tope anti-código de barras
    if (weight != null && weight >= 0.001 && weight < maxLimit) {
      provider.submitWeighedProductWithPromo(
        product,
        weight,
        promotionalPrice: promotionalPrice,
        promotionalLabel: promotionalLabel,
        promotionalPeriodType: promotionalPeriodType,
        batchId: batchId,
        batchCode: batchCode,
        batchExpirationDate: batchExpirationDate,
      );
      Navigator.pop(dialogContext);
    } else {
      SnackBarService.error(
        dialogContext,
        isHardwareFractionalMode
            ? 'Por favor, ingrese una cantidad válida entre 0.001 y ${(maxLimit - 0.001).toStringAsFixed(3)} $unitShortLabel.'
            : 'Por favor, ingrese un peso válido entre 0.001 y 999.999 Kg.',
      );
    }
  }

  // Helper de conversión segura String/num → double
  double _toDouble(dynamic value) =>
      value == null ? 0.0 : double.tryParse(value.toString()) ?? 0.0;

  void _handleCheckout() async {
    _hideSearchHistoryPopover();
    if (_isCheckingOut) return;
    _isCheckingOut = true;

    try {
      final posProvider = Provider.of<PosProvider>(context, listen: false);
      final cashRegisterProvider =
          Provider.of<CashRegisterProvider>(context, listen: false);

      // ── VALIDACIÓN PROACTIVA: Verificar el turno en el servidor ANTES de abrir
      // la pantalla de cobro. Esto intercepta el caso donde el turno fue cerrado
      // desde otra terminal mientras este cliente estaba ocioso con el carrito lleno.
      // MC-06: Si la terminal no está bloqueada en Ajustes (assignedRegisterId == 0),
      // usar activeRegisterId de CashRegisterProvider para no secuestrar Caja 2 hacia Caja 1.
      final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
      final targetRegId = settingsProvider.assignedRegisterId > 0
          ? settingsProvider.assignedRegisterId
          : cashRegisterProvider.activeRegisterId;
      await cashRegisterProvider.checkCurrentShift(registerId: targetRegId);

      final currentShift = cashRegisterProvider.currentShift;
      if (!mounted) return;

      if (currentShift == null || !currentShift.isOpen) {
        // El turno ya no existe en el servidor → mostrar cartel de seguridad de inmediato
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AppModalShell(
            title: 'Turno Cerrado',
            subtitle: 'Operación bloqueada por cierre remoto',
            icon: Icons.lock_clock_rounded,
            accent: AppModalAccent.red,
            compact: true,
            maxWidth: 440,
            showCloseButton: false,
            useAlertDialogWrapper: true,
            bodyPadding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            body: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'El turno de caja fue cerrado desde otra terminal.',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(
                  'La sesión actual ya no es válida. Será redirigido al inicio para actualizar el estado de la caja.',
                  style: TextStyle(fontSize: 13, color: Colors.red.shade700),
                ),
              ],
            ),
            footerActions: [
              FilledButton.icon(
                style:
                    FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.refresh),
                label: const Text('Recargar sesión'),
              ),
            ],
          ),
        );
        if (mounted) {
          posProvider.clearCart();
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/home', (route) => false);
        }
        return;
      }

    // Turno confirmado activo en el servidor → abrir pantalla de cobro
    // Garantizar que los métodos de pago estén cargados ANTES de abrir el diálogo.
    // En el primer inicio después de compilar, el fetch puede haber fallado silenciosamente
    // (token de auth no listo), dejando la lista vacía y el diálogo colgado sin retry.
    if (posProvider.paymentMethods.isEmpty) {
      await posProvider.loadPaymentMethods();
      if (!mounted) return;
      if (posProvider.paymentMethods.isEmpty) {
        SnackBarService.error(
          context,
          'No se pudieron cargar los métodos de pago. Intente nuevamente.',
        );
        return;
      }
    }

    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CheckoutDialog(
        total: posProvider.cartSubtotal,
        initialCustomer: posProvider.selectedCustomer,
      ),
    );

    if (success == true) {
      if (mounted) {
        // 1. PRIORIDAD ABSOLUTA: Mostrar confirmación visual de inmediato
        SnackBarService.success(context, '¡Venta registrada con éxito!');

        // 2. ACTUALIZAR LOGÍSTICA EN BACKGROUND (SOLO SI EL MÓDULO Y EL PERMISO ESTÁN ACTIVOS)
        final authProv = context.read<AuthProvider>();
        final settingsProvider =
            Provider.of<SettingsProvider>(context, listen: false);
        if (settingsProvider.features.logistics &&
            authProv.hasPermission(AppPermissions.manageDeliveryNotes)) {
          Provider.of<LogisticsProvider>(context, listen: false).refreshAll(force: true);
        }

        final localTerminalProvider =
            Provider.of<LocalTerminalProvider>(context, listen: false);
        final localFormat = localTerminalProvider.printerFormat;

        // ── Post-venta Logística (Fricción Cero) ──────────────────────────
        // El remito ya fue creado en processCheckout(). Aquí decidimos cómo mostrarlo
        // solo como fallback si PosProvider no pudo abrir la vista previa directamente.
        if (posProvider.wasLastSaleDispatched &&
            posProvider.lastSalePrinted &&
            !posProvider.previewHandledInProvider) {
          final deliveryNote = posProvider.lastDeliveryNote;
          final isDeliveredNow =
              (deliveryNote?['status'] ?? posProvider.currentFulfillmentStatus) ==
                  'delivered';

          // SOLO mostramos el Remito (Split o Separado) si el remito se entrega AHORA.
          // Si quedó pendiente, el comprobante de venta simple ya se imprimió en processCheckout,
          // y el remito lo imprimirá Logística mañana.
          debugPrint(
              'DEBUG: Dispatch detected. isDeliveredNow=$isDeliveredNow, note=$deliveryNote');

          if (isDeliveredNow &&
              deliveryNote != null &&
              (deliveryNote.containsKey('sale') ||
                  posProvider.lastSaleCart.isNotEmpty)) {
            try {
              final sale = Map<String, dynamic>.from(
                (deliveryNote['sale'] as Map<String, dynamic>?) ?? {},
              );

              // Enriquecemos siempre desde el snapshot del carrito y pagos de posProvider
              // para garantizar que las ofertas, descuentos, precio de lista, IVA e importes de pago
              // salgan idénticos al comprobante individual en la hoja partida (Comprobante + Remito).
              sale['id'] ??= deliveryNote['sale_id'];
              sale['total'] ??= posProvider.lastSaleTotal;
              sale['shipping_cost'] ??= posProvider.lastSaleShippingCost;
              sale['surcharge_amount'] ??= posProvider.lastSurchargeAmount;
              if (posProvider.lastSalePayments.isNotEmpty) {
                sale['payments'] = posProvider.lastSalePayments;
              }
              sale['tendered_amount'] = posProvider.lastTenderedAmount;
              sale['change_amount'] = posProvider.lastChangeAmount;
              if (posProvider.lastSaleCart.isNotEmpty) {
                final double cartSavings = posProvider.lastSaleCart.fold(
                  0.0,
                  (sum, it) => sum + it.discountSavings,
                );
                final double cartTierSurcharge = posProvider.lastSaleCart.fold(
                  0.0,
                  (sum, it) => sum + it.surchargeAmount,
                );
                final double cartSubtotalList = posProvider.lastSaleCart.fold(
                  0.0,
                  (sum, it) => sum + it.regularSubtotal,
                );
                sale['subtotal_list'] = cartSubtotalList;
                sale['discount_amount'] = cartSavings;
                sale['tier_surcharge_amount'] = cartTierSurcharge;
                sale['items'] = posProvider.lastSaleCart
                    .map((item) => {
                          'product_id': item.product.id,
                          'quantity': item.quantity,
                          'product_name': item.effectiveDisplayName,
                          'custom_description': item.customDescription,
                          'custom_details': item.effectiveReceiptDetails(),
                          'is_temporary': item.isTemporary,
                          'unit_price': item.unitPrice,
                          'regular_price': item.product.sellingPrice,
                          'regular_subtotal': item.regularSubtotal,
                          'discount_amount': item.discountSavings,
                          'surcharge_amount': item.surchargeAmount,
                          'has_discount': item.hasDiscount,
                          'discount_label': item.hasActiveOffer
                              ? item.offerBadgeLabel
                              : (item.promotionalLabel ?? ''),
                          'subtotal': item.subtotal,
                          'product': {
                            'name': item.effectiveDisplayName,
                            'internal_code': item.product.internalCode,
                            'iva_rate': item.product.ivaRate,
                            'is_sold_by_weight': item.product.isSoldByWeight,
                            'unit_type': item.product.unitType,
                            'technical_spec': item.product.technicalSpec,
                            'calc_config': item.product.calcConfig,
                            'selling_price': item.product.sellingPrice,
                          }
                        })
                    .toList();
              }
              sale['customer'] ??= deliveryNote['customer'] ??
                  deliveryNote['sale']?['customer'];

              final authProvider =
                  Provider.of<AuthProvider>(context, listen: false);
              final vendorName =
                  authProvider.currentUser?['name']?.toString() ?? 'CAJERO';
              final businessName =
                  settingsProvider.settings?.companyName ?? 'MI NEGOCIO';

              if (localFormat == 'a4_split' ||
                  localFormat == 'a4_normal' ||
                  localFormat == 'a4') {
                // 1. A4 SMART (Split si <= 5 ítems, MultiPage si > 5 ítems)
                final pdfBytes =
                    await A4SplitPdfService.generateA4SplitReceiptAndDispatch(
                  sale: sale,
                  deliveryNote: deliveryNote,
                  businessName: businessName,
                  businessAddress: settingsProvider.settings?.address,
                  phone: settingsProvider.settings?.phone ?? '',
                  cuit: settingsProvider.settings?.taxId ?? '',
                  taxCondition: settingsProvider.settings?.taxCondition,
                  iibb: settingsProvider.settings?.iibb,
                  activityStartDate: settingsProvider.settings?.activityStartDate,
                  vendorName: vendorName,
                  paperSize: localTerminalProvider.pdfPaperSize,
                  businessSettings: settingsProvider.settings,
                );

                if (mounted) {
                  final paperSize = localTerminalProvider.pdfPaperSize;
                  final result = await showDialog<String>(
                    context: context,
                    barrierDismissible: false,
                    builder: (dialogCtx) {
                      bool isVoiding = false;
                      return StatefulBuilder(
                        builder: (context, setState) {
                          return AppPdfPreviewModal(
                            title: 'Vista Previa - Venta #${sale['id']}',
                            subtitle:
                                'Comprobante y despacho • Hoja ${pdfPaperSizeLabel(paperSize)}',
                            icon: Icons.picture_as_pdf_rounded,
                            accent: AppModalAccent.blue,
                            pdfFileName: 'Comprobante_${sale['id']}.pdf',
                            initialPageFormat:
                                pdfPageFormatFromPaperSize(paperSize),
                            build: (format) async => pdfBytes,
                            canClose: !isVoiding,
                            onClose: isVoiding
                                ? null
                                : () => Navigator.pop(dialogCtx),
                            headerTrailing: isVoiding
                                ? const Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 12),
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.dangerLight,
                                      ),
                                    ),
                                  )
                                : OutlinedButton.icon(
                                    onPressed: () async {
                                      final confirm =
                                          await AppConfirmDialog.show(
                                        context,
                                        title: '¿Anular Venta?',
                                        message:
                                            'Esta acción cancelará el cobro en el sistema y devolverá los productos al carrito.',
                                        confirmLabel: 'SÍ, ANULAR',
                                        cancelLabel: 'NO, VOLVER',
                                        icon: Icons.cancel_outlined,
                                        isDestructive: true,
                                      );

                                      if (confirm == true) {
                                        final currentShift = context
                                            .read<CashRegisterProvider>()
                                            .currentShift;
                                        if (currentShift == null) {
                                          if (dialogCtx.mounted) {
                                            SnackBarService.error(
                                              dialogCtx,
                                              'Debe haber un turno de caja abierto para anular órdenes.',
                                            );
                                          }
                                          return;
                                        }
                                        setState(() {
                                          isVoiding = true;
                                        });
                                        try {
                                          final success = await posProvider
                                              .voidPendingOrder(
                                            int.parse(sale['id'].toString()),
                                            shiftId: currentShift.id,
                                          );
                                          if (!success) {
                                            throw Exception(
                                              posProvider.errorMessage ??
                                                  'Error desconocido',
                                            );
                                          }
                                          // Restaurar carrito al estado previo a la venta
                                          posProvider.restoreLastSaleCart();

                                          if (dialogCtx.mounted) {
                                            SnackBarService.warning(
                                              dialogCtx,
                                              'Venta anulada. Los productos han vuelto al carrito.',
                                            );
                                            Navigator.pop(
                                              dialogCtx,
                                              'annulled',
                                            );
                                          }
                                        } catch (e) {
                                          if (dialogCtx.mounted) {
                                            SnackBarService.error(
                                              dialogCtx,
                                              'Error al anular: $e',
                                            );
                                            setState(() {
                                              isVoiding = false;
                                            });
                                          }
                                        }
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.delete_forever_rounded,
                                      size: 17,
                                    ),
                                    label:
                                        const Text('ANULAR COBRO Y VOLVER'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor:
                                          const Color(0xFFFCA5A5),
                                      backgroundColor: AppColors.danger
                                          .withValues(alpha: 0.22),
                                      side: BorderSide(
                                        color: AppColors.dangerLight
                                            .withValues(alpha: 0.55),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      textStyle: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                          );
                        },
                      );
                    },
                  );

                  if (result == 'annulled') return;
                }
              }
            } catch (e) {
              debugPrint('Error crítico generando PDF Split: $e');
              // FALLBACK: Si falló el split, intentamos al menos mostrar la venta simple de Laravel
              // para que el cajero no se quede sin nada.
              if (localFormat.startsWith('a4')) {
                await _showFallbackA4Pdf(posProvider);
              }
            }
          } else if (isDeliveredNow && deliveryNote == null) {
            // Caso borde: requiere despacho inmediato pero falló la creación del remito
            // Mostramos al menos la venta simple
            if (localFormat.startsWith('a4')) {
              await _showFallbackA4Pdf(posProvider);
            }
          } else {
            // Estado 'pending': el PDF de venta simple ya fue mostrado por pos_provider (Laravel PDF)
            // No se muestra nada extra aqui: el galpón imprimirá el remito desde el módulo de Logística
          }
        }

        // 2. ACTUALIZACIÓN LOCAL (IN-MEMORY):
        // Actualizamos el contador de ventas en memoria para que los badges (⚡/🔥) se refresquen
        // al instante, manteniendo congelada la posición de las tarjetas durante el turno.
        // Usamos lastSaleCart (snapshot guardado antes de clearCart) porque
        // posProvider.cart ya está vacío en este punto.
        if (!mounted) return;
        final catalogProvider =
            Provider.of<CatalogProvider>(context, listen: false);
        final popularityMetric =
            Provider.of<SettingsProvider?>(context, listen: false)
                    ?.settings
                    ?.posPopularityMetric ??
                'tickets';
        final Map<int, int> soldItems = {};
        for (var item in posProvider.lastSaleCart) {
          if (item.quantity <= 0) continue;
          if (popularityMetric == 'units') {
            final points = item.quantity.ceil();
            soldItems[item.product.id] =
                (soldItems[item.product.id] ?? 0) + points;
          } else {
            // Modo 'tickets' (default): 1 aparición en el ticket = +1 punto de frecuencia
            soldItems[item.product.id] = 1;
          }
        }
        final anySoldMissing =
            catalogProvider.updateProductSalesCountLocally(soldItems);
        if (anySoldMissing) {
          // Se vendió algo que no estaba cargado en la grilla (ej. vía buscador): traemos el
          // dato real del servidor en segundo plano (sin spinner) preservando el orden visual actual.
          catalogProvider.refreshQuickAccessSilently(preserveVisualOrder: true);
        }

        // 2.b DEDUCCIÓN INMEDIATA EN MEMORIA (0ms) en Catálogo y en _searchResults:
        // Evita que si el cajero vuelve a tocar el mismo producto/combo enseguida (o desde el buscador),
        // use el snapshot viejo antes de que termine el refresco HTTP en segundo plano.
        final Map<int, double> consumedInSale = {};
        final List<Product> soldProductsSnapshot = [];
        for (final item in posProvider.lastSaleCart) {
          if (item.quantity <= 0) continue;
          soldProductsSnapshot.add(item.product);
          if (item.product.isCombo &&
              item.product.comboIngredients != null &&
              item.product.comboIngredients!.isNotEmpty) {
            for (final ing in item.product.comboIngredients!) {
              final ingId = (ing['id'] as num?)?.toInt();
              final ingQty = (ing['quantity'] as num?)?.toDouble() ?? 1.0;
              if (ingId != null && ingQty > 0) {
                consumedInSale[ingId] =
                    (consumedInSale[ingId] ?? 0.0) + (item.quantity * ingQty);
              }
            }
          } else {
            consumedInSale[item.product.id] =
                (consumedInSale[item.product.id] ?? 0.0) + item.quantity;
          }
        }
        catalogProvider.applyImmediateLocalStockDeduction(consumedInSale);
        // OF-01: mismo descuento inmediato para los productos en oferta fuera del catálogo en memoria
        final offerProvForStock = Provider.of<OfferProvider>(context, listen: false);
        if (offerProvForStock.offerOnlyProducts.isNotEmpty) {
          offerProvForStock.replaceOfferOnlyProducts(
            catalogProvider.deductStockLocallyForProductList(
              offerProvForStock.offerOnlyProducts,
              consumedInSale,
            ),
          );
        }
        if (_searchResults.isNotEmpty) {
          setState(() {
            _searchResults = catalogProvider.deductStockLocallyForProductList(
              _searchResults,
              consumedInSale,
            );
          });
        }

        // 3. REFRESCO SELECTIVO (FIRE-AND-FORGET):
        // Solo actualizamos el stock de los productos vendidos — sin recargar el catálogo completo.
        // Esto elimina el parpadeo de la grilla y acelera la vuelta a pantalla de venta.
        final List<int> soldIds = soldItems.keys.toList();
        catalogProvider
            .refreshStockForSoldProducts(
          soldIds,
          soldProductsSnapshot: soldProductsSnapshot,
        )
            .then((updatedMap) {
          if (!mounted || updatedMap.isEmpty) return;
          if (offerProvForStock.offerOnlyProducts.isNotEmpty) {
            final updatedOffers = catalogProvider.applyStockUpdatesToProductList(
              offerProvForStock.offerOnlyProducts,
              updatedMap,
            );
            if (!identical(updatedOffers, offerProvForStock.offerOnlyProducts)) {
              offerProvForStock.replaceOfferOnlyProducts(updatedOffers);
            }
          }
          if (_searchResults.isNotEmpty) {
            setState(() {
              _searchResults = catalogProvider.applyStockUpdatesToProductList(
                _searchResults,
                updatedMap,
              );
            });
          }
        }).catchError((e) {
          debugPrint('Refresco de stock silencioso falló (esperado en redes inestables): $e');
        });

        // Refrescar alertas de inventario en paralelo (no bloquea el flujo de caja)
        try {
          Provider.of<InventoryAlertsProvider>(context, listen: false)
              .fetchAlerts();
        } catch (e) {
          debugPrint('Error refrescando alertas: $e');
        }

        // BUG 1 FIX: Alertar al cajero si el comprobante no pudo imprimirse.
        // La venta ya fue registrada exitosamente — esto es solo feedback de hardware.
        if (posProvider.printerWarning != null) {
          SnackBarService.warning(context, posProvider.printerWarning!);
        }
      }
    } else if (posProvider.isShiftClosed && mounted) {
      // ── SEGURIDAD: Turno cerrado remotamente ─────────────────────
      // El backend rechazó la venta porque el turno ya fue cerrado
      // desde otra terminal. Mostramos un diálogo crítico no descartable
      // y forzamos la vuelta al inicio para limpiar todo el estado.
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AppModalShell(
          title: 'Turno Cerrado',
          subtitle: 'Operación bloqueada por cierre remoto',
          icon: Icons.lock_clock_rounded,
          accent: AppModalAccent.red,
          compact: true,
          maxWidth: 440,
          showCloseButton: false,
          useAlertDialogWrapper: true,
          bodyPadding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                posProvider.errorMessage ??
                    'El turno de caja fue cerrado desde otra terminal.',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(
                'La sesión actual ya no es válida. Será redirigido al inicio para actualizar el estado de la caja.',
                style: TextStyle(fontSize: 13, color: Colors.red.shade700),
              ),
            ],
          ),
          footerActions: [
            FilledButton.icon(
              style:
                  FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.refresh),
              label: const Text('Recargar sesión'),
            ),
          ],
        ),
      );

      // Limpiar estado del provider y navegar al inicio eliminando toda la pila
      if (mounted) {
        posProvider.clearCart();
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/home', (route) => false);
      }
    } else if (posProvider.errorMessage?.contains('SESSION_EXPIRED') == true ||
        posProvider.errorMessage?.contains('otro dispositivo') == true) {
      // ── SEGURIDAD: Sesión única — manejado por el Global Interceptor en main.dart
      return;
    }

    _requestSearchFocusSilently();
    } finally {
      _isCheckingOut = false;
    }
  }

  // ────────────────────────────────────────────────────────────────
  // PREVENTA: Dejar el carrito actual en espera (status = pending)
  // ────────────────────────────────────────────────────────────────
  void _handleHoldOrder() async {
    final posProvider = Provider.of<PosProvider>(context, listen: false);
    final cashRegisterProvider =
        Provider.of<CashRegisterProvider>(context, listen: false);
    final currentUser = context.read<AuthProvider>().currentUser;

    final currentShift = cashRegisterProvider.currentShift;
    if (currentShift == null || !currentShift.isOpen) {
      SnackBarService.error(context, 'No hay turno de caja abierto.');
      return;
    }

    Future<bool> executeHoldCall() {
      return posProvider.holdOrder(
        shiftId: currentShift.id,
        userId: currentUser?['id'] as int?,
      );
    }

    ApiClient? apiClient;
    try {
      apiClient = context.read<ApiClient>();
    } catch (_) {}

    final bool success;
    if (posProvider.authorizedDiscountPin != null && apiClient != null) {
      success = await apiClient.withAdminPin(
        posProvider.authorizedDiscountPin!,
        executeHoldCall,
      );
    } else {
      success = await executeHoldCall();
    }

    if (success && mounted) {
      SnackBarService.success(context, '📋 Orden guardada en espera.');
    } else if (!success && posProvider.isShiftClosed && mounted) {
      // Mismo tratamiento de seguridad que en checkout: turno cerrado remotamente
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AppModalShell(
          title: 'Turno Cerrado',
          subtitle: 'Operación bloqueada por cierre remoto',
          icon: Icons.lock_clock_rounded,
          accent: AppModalAccent.red,
          compact: true,
          maxWidth: 440,
          showCloseButton: false,
          useAlertDialogWrapper: true,
          bodyPadding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                posProvider.errorMessage ??
                    'El turno de caja fue cerrado desde otra terminal.',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(
                'La sesión actual ya no es válida. Será redirigido al inicio para actualizar el estado de la caja.',
                style: TextStyle(fontSize: 13, color: Colors.red.shade700),
              ),
            ],
          ),
          footerActions: [
            FilledButton.icon(
              style:
                  FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.refresh),
              label: const Text('Recargar sesión'),
            ),
          ],
        ),
      );
      if (mounted) {
        posProvider.clearCart();
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/home', (route) => false);
      }
    } else if (!success &&
        (posProvider.errorMessage?.contains('SESSION_EXPIRED') == true ||
            posProvider.errorMessage?.contains('otro dispositivo') == true) &&
        mounted) {
      // ── SEGURIDAD: Sesión única — manejado por el Global Interceptor en main.dart
      return;
    } else if (!success && mounted) {
      SnackBarService.error(
          context, posProvider.errorMessage ?? 'No se pudo guardar la orden.');
    }
    _requestSearchFocusSilently();
  }

  // ────────────────────────────────────────────────────────────────
  // MODAL DE ÓRDENES PENDIENTES
  // ────────────────────────────────────────────────────────────────
  Future<void> _handleDeletePendingOrder(int saleId, PosProvider posProvider,
      {StateSetter? setStateDialog}) async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'Anular Orden en Espera',
      message:
          '¿Desea anular la orden #$saleId?\nEsta acción devolverá los productos al stock físico y no se puede deshacer.',
      confirmLabel: 'Anular',
      icon: Icons.delete_outline_rounded,
      isDestructive: true,
    );

    if (confirmed == true && mounted) {
      final currentShiftId = context.read<CashRegisterProvider>().currentShift?.id;
      if (currentShiftId == null) {
        SnackBarService.error(context, 'Debe haber un turno de caja abierto para anular órdenes.');
        return;
      }
      final success = await posProvider.voidPendingOrder(saleId, shiftId: currentShiftId);
      if (mounted) {
        if (success) {
          SnackBarService.success(
              context, 'Orden #$saleId anulada. El stock fue restaurado.');
          if (setStateDialog != null) {
            setStateDialog(() {});
          } else {
            _requestSearchFocusSilently();
          }
        } else {
          SnackBarService.error(
              context, posProvider.errorMessage ?? 'Error al anular orden');
        }
      }
    }
  }

  // ────────────────────────────────────────────────────────────────
  // ────────────────────────────────────────────────────────────────
  // POPOVER DE ÓRDENES EN ESPERA (FIJO)
  // ────────────────────────────────────────────────────────────────
  // ────────────────────────────────────────────────────────────────
  // ────────────────────────────────────────────────────────────────
  // POPOVER DE ÓRDENES EN ESPERA (HÍBRIDO Y ESTABLE)
  // ────────────────────────────────────────────────────────────────

  Widget _buildPendingBadge(int count) {
    return RepaintBoundary(
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.8, end: 1.05),
          duration: const Duration(seconds: 1),
          curve: Curves.easeInOut,
          builder: (context, scale, _) {
            return Transform.scale(
              scale: scale,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.redAccent.withValues(alpha: 0.4),
                        blurRadius: 4,
                        spreadRadius: 1),
                  ],
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text('$count',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPendingFilterPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF10B981).withValues(alpha: 0.20)
              : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? const Color(0xFF34D399).withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.14),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(
                Icons.check_circle_rounded,
                size: 13,
                color: Color(0xFF34D399),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : const Color(0xFFCBD5E1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingOrdersOverlay(
    PosProvider posProvider,
    OverlayChildLayoutInfo info,
  ) {
    final Offset targetBottomRight = MatrixUtils.transformPoint(
      info.childPaintTransform,
      Offset(info.childSize.width, info.childSize.height),
    );
    final double top = targetBottomRight.dy + 8.0;
    final double rawRight = info.overlaySize.width - targetBottomRight.dx;
    final double right = rawRight < 8.0 ? 8.0 : rawRight;

    return Positioned(
      top: top,
      right: right,
      child: StatefulBuilder(
        builder: (context, setOverlayState) {
          final pendingSales = posProvider.pendingSales;

          Widget content = ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
            child: Material(
                key: const ValueKey('pending_orders_overlay_material'),
                elevation: 16,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                shadowColor: Colors.black.withValues(alpha: 0.3),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header Dual-Tone Caja4U con controles internos
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF121C33), Color(0xFF16233F)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border(
                            bottom: BorderSide(
                              color: Color(0xFF1E2D4A),
                              width: 1.5,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF59E0B)
                                        .withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFFF59E0B)
                                          .withValues(alpha: 0.45),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.pending_actions_rounded,
                                    color: Color(0xFFFBBF24),
                                    size: 19,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Órdenes en Espera',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15.5,
                                      color: Colors.white,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                                // PIN con setOverlayState para no romper el layout global
                                IconButton(
                                  constraints: const BoxConstraints.tightFor(
                                    width: 32,
                                    height: 32,
                                  ),
                                  padding: EdgeInsets.zero,
                                  style: IconButton.styleFrom(
                                    backgroundColor: _isPendingPinned
                                        ? const Color(0xFF10B981)
                                            .withValues(alpha: 0.22)
                                        : Colors.white.withValues(alpha: 0.08),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(
                                        color: _isPendingPinned
                                            ? const Color(0xFF34D399)
                                                .withValues(alpha: 0.55)
                                            : Colors.white
                                                .withValues(alpha: 0.14),
                                      ),
                                    ),
                                  ),
                                  icon: Icon(
                                    _isPendingPinned
                                        ? Icons.push_pin
                                        : Icons.push_pin_outlined,
                                    size: 18,
                                    color: _isPendingPinned
                                        ? const Color(0xFF34D399)
                                        : const Color(0xFFCBD5E1),
                                  ),
                                  tooltip:
                                      null, // Parche: eliminamos el tooltip que causa el crash
                                  onPressed: () {
                                    setOverlayState(() {
                                      _isPendingPinned = !_isPendingPinned;
                                    });
                                    setState(() {});
                                  },
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  constraints: const BoxConstraints.tightFor(
                                    width: 32,
                                    height: 32,
                                  ),
                                  padding: EdgeInsets.zero,
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        Colors.white.withValues(alpha: 0.08),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(
                                        color: Colors.white
                                            .withValues(alpha: 0.14),
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.refresh,
                                    size: 18,
                                    color: Color(0xFFCBD5E1),
                                  ),
                                  tooltip:
                                      null, // Parche: eliminamos el tooltip que causa el crash
                                  onPressed: () async {
                                    await posProvider.loadPendingSales();
                                    if (context.mounted) setOverlayState(() {});
                                  },
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  constraints: const BoxConstraints.tightFor(
                                    width: 32,
                                    height: 32,
                                  ),
                                  padding: EdgeInsets.zero,
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        Colors.white.withValues(alpha: 0.08),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(
                                        color: Colors.white
                                            .withValues(alpha: 0.14),
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.close,
                                    size: 18,
                                    color: Color(0xFFCBD5E1),
                                  ),
                                  tooltip: null,
                                  onPressed: () =>
                                      _pendingOrdersPortalController.hide(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // MC-03: Selector rápido Todas las cajas vs Solo esta caja
                            Row(
                              children: [
                                _buildPendingFilterPill(
                                  label: 'Todas las cajas',
                                  selected: !_onlyCurrentRegisterPending,
                                  onTap: () {
                                    setOverlayState(() {
                                      _onlyCurrentRegisterPending = false;
                                    });
                                  },
                                ),
                                const SizedBox(width: 8),
                                _buildPendingFilterPill(
                                  label: 'Solo esta caja',
                                  selected: _onlyCurrentRegisterPending,
                                  onTap: () {
                                    setOverlayState(() {
                                      _onlyCurrentRegisterPending = true;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: Builder(
                          builder: (ctx) {
                            final currentShift = ctx.read<CashRegisterProvider>().currentShift;
                            final activeRegId = ctx.read<CashRegisterProvider>().activeRegisterId;
                            final filteredPending = !_onlyCurrentRegisterPending
                                ? pendingSales
                                : pendingSales.where((s) {
                                    final sShiftId = s['cash_shift_id'];
                                    final sRegId = s['cash_shift']?['cash_register_id'] ??
                                        s['cash_shift']?['cash_register']?['id'];
                                    if (activeRegId != null && sRegId != null) {
                                      return sRegId.toString() == activeRegId.toString();
                                    }
                                    if (currentShift != null && sShiftId != null) {
                                      return sShiftId.toString() == currentShift.id.toString();
                                    }
                                    return true;
                                  }).toList();
                            return filteredPending.isEmpty
                                ? _buildEmptyPendingState()
                                : _buildPendingOrdersList(
                                    filteredPending, posProvider);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          );

          if (!_isPendingPinned) {
            return TapRegion(
              groupId: 'pending_orders_overlay',
              onTapOutside: (_) => _pendingOrdersPortalController.hide(),
              child: content,
            );
          }
          return content;
        },
      ),
    );
  }

  Widget _buildEmptyPendingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 56, color: Colors.green),
          SizedBox(height: 12),
          Text('¡No hay órdenes!',
              style: TextStyle(fontSize: 16, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildPendingOrdersList(
      List<dynamic> pendingSales, PosProvider posProvider) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: pendingSales.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final sale = pendingSales[index];
        final saleId = (sale['id'] as num).toInt();
        final total = _toDouble(sale['total']);
        final itemCount = (sale['items'] as List?)?.length ?? 0;
        final originRegName = sale['cash_shift']?['cash_register']?['name']?.toString();
        final originUserName = sale['user']?['name']?.toString();

        return Card(
          elevation: 0,
          color: Colors.grey.shade50,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade100)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.orange.shade100,
                      child: Text('#$saleId',
                          style: TextStyle(
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.bold,
                              fontSize: 10)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('\$${total.toCurrency()}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 16)),
                              const Spacer(),
                              if (originRegName != null && originRegName.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.indigo.shade100),
                                  ),
                                  child: Text(
                                    originUserName != null && originUserName.isNotEmpty
                                        ? '$originRegName • $originUserName'
                                        : originRegName,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo.shade700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          Row(
                            children: [
                              Icon(Icons.access_time,
                                  size: 10, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Builder(
                                builder: (context) {
                                  final createdAt =
                                      sale['created_at'] as String?;
                                  if (createdAt == null) {
                                    return const Text('--:--',
                                        style: TextStyle(fontSize: 11));
                                  }

                                  // Forzamos formato ISO UTC (YYYY-MM-DDTHH:mm:ssZ) para que .toLocal() funcione
                                  final isoStr = createdAt.contains('T')
                                      ? createdAt
                                      : createdAt.replaceFirst(' ', 'T');
                                  final utcStr = isoStr.endsWith('Z')
                                      ? isoStr
                                      : '${isoStr}Z';

                                  final dt =
                                      DateTime.tryParse(utcStr)?.toLocal();
                                  if (dt == null) {
                                    return Text(createdAt.substring(11, 16),
                                        style: const TextStyle(fontSize: 11));
                                  }

                                  return Text(
                                    "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}",
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600),
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                              const Text('•',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 10)),
                              const SizedBox(width: 8),
                              Text('$itemCount ítem(s)',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      child: const Text('Anular',
                          style: TextStyle(color: Colors.red, fontSize: 12)),
                      onPressed: () =>
                          _handleDeletePendingOrder(saleId, posProvider),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade50,
                        foregroundColor: Colors.orange.shade900,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        _pendingOrdersPortalController.hide();
                        final customers = context.read<CustomerProvider>().customers;
                        posProvider.recallOrderToCart(sale, availableCustomers: customers);
                        SnackBarService.success(
                            context, '📥 Orden #$saleId cargada al carrito.');
                        _requestSearchFocusSilently();
                      },
                      child: const Text('RECUPERAR',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return RemoteScannerListener(
      debugLabel: 'PosScreen',
      onBarcodeScanned: (barcode) {
        if (!mounted || _isCheckingOut) return;
        _hideSearchHistoryPopover();
        _searchController.text = barcode;
        _onProductScannedOrSearched(barcode);
      },
      child: Scaffold(
        appBar: GlobalAppBar(
        currentRoute: '/pos',
        extraAction: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Builder(
              builder: (walletCtx) {
                final canAccessExpenses =
                    walletCtx.watch<SettingsProvider?>()?.features.expenses ??
                        false;
                return Tooltip(
                  message: canAccessExpenses
                      ? 'Gastos y Mov. de Caja'
                      : '🔒 Gastos y Mov. de Caja • Plan Premium',
                  child: InkWell(
                    key: const ValueKey('pos_appbar_wallet_btn'),
                    onTap: () {
                      if (!canAccessExpenses) {
                        PlanUpgradeDialog.show(
                          walletCtx,
                          featureName: 'Gestión de Gastos y Movimientos de Caja',
                          description:
                              'El registro de gastos operativos, retiros e ingresos manuales de caja con impacto en reportes y cierres Z está disponible en el Plan Premium.',
                          onNavigateToSettings: () =>
                              Navigator.of(walletCtx).pushNamed('/settings'),
                        );
                        return;
                      }
                      showDialog(
                        context: walletCtx,
                        barrierDismissible: true,
                        builder: (context) =>
                            const frontend_desktop_cash_movements_dialog
                                .MovementFormDialog(),
                      );
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: canAccessExpenses
                            ? Colors.white.withValues(alpha: 0.07)
                            : const Color(0xFFF59E0B).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: canAccessExpenses
                              ? Colors.white.withValues(alpha: 0.14)
                              : const Color(0xFFF59E0B).withValues(alpha: 0.45),
                        ),
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 19,
                            color: canAccessExpenses
                                ? const Color(0xFF38BDF8)
                                : const Color(0xFF94A3B8),
                          ),
                          if (!canAccessExpenses)
                            Positioned(
                              right: -4,
                              top: -4,
                              child: Container(
                                padding: const EdgeInsets.all(1.5),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFD97706),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.lock_rounded,
                                  size: 9,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 6),
            Consumer<PosProvider>(
              builder: (ctx, pos, _) {
                final count = pos.pendingCount;
                return TapRegion(
                  groupId: 'pending_orders_overlay',
                  child: OverlayPortal.overlayChildLayoutBuilder(
                    controller: _pendingOrdersPortalController,
                    overlayChildBuilder: (context, info) =>
                        _buildPendingOrdersOverlay(pos, info),
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        IconButton(
                          tooltip: count > 0
                              ? 'Órdenes en Espera ($count)'
                              : 'Órdenes en Espera',
                          constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                          padding: EdgeInsets.zero,
                          style: IconButton.styleFrom(
                            backgroundColor: count > 0
                                ? const Color(0xFFF59E0B).withValues(alpha: 0.18)
                                : Colors.white.withValues(alpha: 0.07),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: count > 0
                                    ? const Color(0xFFF59E0B).withValues(alpha: 0.45)
                                    : Colors.white.withValues(alpha: 0.14),
                              ),
                            ),
                          ),
                          icon: RepaintBoundary(
                            child: ExcludeSemantics(
                              child: TweenAnimationBuilder<double>(
                                key: ValueKey(count > 0),
                                tween: Tween(begin: 0.0, end: count > 0 ? 1.0 : 0.0),
                                duration: const Duration(milliseconds: 1500),
                                curve: Curves.elasticOut,
                                builder: (context, value, _) {
                                  return Transform.rotate(
                                    angle: count > 0
                                        ? (0.15 *
                                            (1.0 - value) *
                                            (DateTime.now().second % 5 == 0
                                                ? 1
                                                : 0))
                                        : 0,
                                    child: Icon(
                                      Icons.pending_actions_rounded,
                                      color: count > 0
                                          ? const Color(0xFFFBBF24)
                                          : const Color(0xFFCBD5E1),
                                      size: 19,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          onPressed: () =>
                              _pendingOrdersPortalController.toggle(),
                        ),
                        if (count > 0)
                          Positioned(
                            right: -4,
                            top: -4,
                            child: IgnorePointer(
                              child: _buildPendingBadge(count),
                            ),
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
      body: Consumer<CashRegisterProvider>(
        builder: (ctx, cashProv, _) {
          // ── EmptyState: Admin entró sin turno ────────────────────
          if (cashProv.currentShift == null || !cashProv.currentShift!.isOpen) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.point_of_sale_rounded,
                        size: 52, color: Colors.orange.shade400),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Caja sin turno activo',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Para registrar ventas, necesitás abrir\nla caja en esta terminal.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 15, color: Colors.grey.shade600, height: 1.5),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushReplacementNamed('/home');
                    },
                    icon: const Icon(Icons.lock_open_rounded),
                    label: const Text('Abrir Caja Ahora',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Podés seguir navegando el resto del sistema',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  ),
                ],
              ),
            );
          }
          // ── POS Normal ──────────────────────────────────
          return SafeArea(
            child: LayoutBuilder(builder: (context, constraints) {
              double ratio = context.read<LocalTerminalProvider>().posSplitRatio;
              return StatefulBuilder(
                builder: (context, setState) {
                  final totalWidth = constraints.maxWidth;
                  final availableWidth = (totalWidth - 16.0).clamp(0.0, double.infinity);
                  final minCartWidth = 340.0.clamp(0.0, availableWidth * 0.5);
                  final maxAllowedByCatalog = (totalWidth - 460.0).clamp(minCartWidth, totalWidth * 0.52 < minCartWidth ? minCartWidth : totalWidth * 0.52);
                  final maxCartWidth = maxAllowedByCatalog < minCartWidth ? minCartWidth : maxAllowedByCatalog;

                  final minCartRatio = totalWidth > 0 ? (minCartWidth / totalWidth) : 0.38;
                  final computedMaxRatio = totalWidth > 0 ? (maxCartWidth / totalWidth) : 0.38;

                  return Row(
                    children: [
                      SizedBox(
                        width: (totalWidth * ratio).clamp(minCartWidth, maxCartWidth),
                        child: _buildCartPanel(),
                      ),
                      Tooltip(
                        message: 'Arrastrar para ajustar ancho · Doble clic para restablecer',
                        waitDuration: const Duration(milliseconds: 600),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeColumn,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onPanUpdate: (details) {
                              if (totalWidth <= 0) return;
                              setState(() {
                                ratio += details.delta.dx / totalWidth;
                                if (ratio < minCartRatio) ratio = minCartRatio;
                                if (ratio > computedMaxRatio) ratio = computedMaxRatio;
                              });
                            },
                            onPanEnd: (details) {
                              context.read<LocalTerminalProvider>().setPosSplitRatio(ratio);
                            },
                            onDoubleTap: () {
                              final resetRatio = 0.38.clamp(minCartRatio, computedMaxRatio);
                              setState(() {
                                ratio = resetRatio;
                              });
                              context.read<LocalTerminalProvider>().setPosSplitRatio(resetRatio);
                              SnackBarService.info(context, 'Tamaño del mostrador restablecido al diseño ideal');
                            },
                            child: Container(
                              width: 16,
                              color: Colors.transparent,
                              child: Center(
                                child: Container(
                                  width: 4,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade400,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: _buildRightPanel(),
                      )
                    ],
                  );
                },
              );
            }),
          );
        },
      ),
      ),
    );
  }

  Widget _buildCartPanel() {
    return Consumer<PosProvider>(builder: (context, pos, child) {
      final isRecall = pos.activePendingSaleId != null;

      return Column(
        children: [
          // Banner de Recuperación de Orden
          if (isRecall)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.orange.shade50,
              child: Row(
                children: [
                  Icon(Icons.sync_rounded,
                      color: Colors.orange.shade800, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Editando Orden #${pos.activePendingSaleId}',
                      style: TextStyle(
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        color: Colors.red.shade700, size: 18),
                    tooltip: 'Anular Orden',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _handleDeletePendingOrder(
                        pos.activePendingSaleId!, pos),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.close,
                        color: Colors.orange.shade900, size: 18),
                    tooltip: 'Cancelar Edición',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      pos.clearRecall();
                      _requestSearchFocusSilently();
                    },
                  ),
                ],
              ),
            ),

          // Banner de Recuperación de Presupuesto
          if (pos.activeQuoteId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.indigo.shade50,
              child: Row(
                children: [
                  Icon(Icons.description_rounded,
                      color: Colors.indigo.shade800, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Presupuesto Recuperado',
                      style: TextStyle(
                          color: Colors.indigo.shade900,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close,
                        color: Colors.indigo.shade900, size: 18),
                    tooltip: 'Quitar Presupuesto',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      pos.clearCart();
                      _requestSearchFocusSilently();
                    },
                  ),
                ],
              ),
            ),

          // Header del carrito
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: Colors.blue.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shopping_cart_outlined, size: 20, color: Colors.blueAccent),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Ticket Actual',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.92, end: 1.0)
                          .animate(animation),
                      child: child,
                    ),
                  ),
                  child: pos.cart.isNotEmpty
                      ? Row(
                          key: const ValueKey('cart_header_actions_visible'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color:
                                    Colors.blueAccent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${pos.cart.length} ${pos.cart.length == 1 ? 'ítem' : 'ítems'}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueAccent,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete_sweep,
                                  color: Colors.red),
                              tooltip: 'Vaciar Carrito',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () async {
                                final confirm = await AppConfirmDialog.show(
                                  context,
                                  title: 'Vaciar Carrito',
                                  message:
                                      '¿Deseas quitar todos los productos y vaciar el carrito?',
                                  confirmLabel: 'Vaciar',
                                  icon: Icons.remove_shopping_cart_outlined,
                                  isDestructive: true,
                                );
                                if (confirm == true) {
                                  pos.clearCart();
                                  _requestSearchFocusSilently();
                                }
                              },
                            ),
                          ],
                        )
                      : const SizedBox.shrink(
                          key: ValueKey('cart_header_actions_empty'),
                        ),
                ),
              ],
            ),
          ),

          // Lista de ítems con marca de agua persistente y transiciones suaves
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                IgnorePointer(
                  child: Center(
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedScale(
                            scale: pos.cart.isEmpty ? 1.0 : 0.86,
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            child: AnimatedOpacity(
                              opacity: pos.cart.isEmpty ? 0.90 : 0.45,
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                              child: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: PosWatermarkLogo(size: 205),
                              ),
                            ),
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            child: pos.cart.isEmpty
                                ? const Padding(
                                    padding: EdgeInsets.only(top: 12),
                                    child: Text(
                                      'El carrito está vacío',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (pos.cart.isNotEmpty)
                  ListView.separated(
                    itemCount: pos.cart.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = pos.cart[index];
                      final bool isRI = context
                              .read<SettingsProvider?>()
                              ?.settings
                              ?.isResponsableInscripto ??
                          false;
                      final String qtyDisplay = (item.product.isSoldByWeight ||
                              (item.quantity - item.quantity.roundToDouble())
                                      .abs() >
                                  0.0005)
                          ? item.quantity.toQty()
                          : item.quantity.round().toString();

                      return LayoutBuilder(
                        builder: (context, itemConstraints) {
                          final double cartWidth = itemConstraints.maxWidth;
                          final bool isCompactCart = cartWidth < 395;
                          final bool isWideCart = cartWidth >= 475;

                          // Micro-badge de IVA: ahora vive junto al precio unitario en Fila 2
                          final Widget? ivaChip = isRI
                              ? _buildCartMicroChip(
                                  label: item.product.ivaRate == 0
                                      ? (isCompactCart ? 'Ex.' : 'Exento 0%')
                                      : (isCompactCart
                                          ? '${item.product.ivaRate.toCleanMargin()}%'
                                          : 'IVA ${item.product.ivaRate.toCleanMargin()}%'),
                                  bgColor: item.product.ivaRate == 0
                                      ? Colors.blueGrey.shade50
                                      : (item.product.ivaRate == 10.5
                                          ? Colors.indigo.shade50
                                          : Colors.blueGrey.shade50),
                                  borderColor: item.product.ivaRate == 0
                                      ? Colors.blueGrey.shade200
                                      : (item.product.ivaRate == 10.5
                                          ? Colors.indigo.shade200
                                          : Colors.blueGrey.shade200),
                                  textColor: item.product.ivaRate == 0
                                      ? Colors.blueGrey.shade700
                                      : (item.product.ivaRate == 10.5
                                          ? Colors.indigo.shade800
                                          : Colors.blueGrey.shade800),
                                  tooltip: item.product.ivaRate == 0
                                      ? 'Producto Exento (IVA 0%)'
                                      : 'Alícuota fiscal: IVA ${item.product.ivaRate.toCleanMargin()}%',
                                )
                              : null;

                          // Fila 3 unificada (Orden estricto: 1.Estrategia -> 2.Stock/Vto -> 3.Origen/Costo)
                          final leadingBadges = <Widget>[];
                          final cartSpecTrim = item.product.technicalSpec?.trim();
                          if (cartSpecTrim != null &&
                              cartSpecTrim.isNotEmpty &&
                              Product.resolveEffectiveReceiptDetails(
                                    displayName: item.effectiveDisplayName,
                                    technicalSpec: cartSpecTrim,
                                    customDetails: item.customDetails,
                                  ) !=
                                  null &&
                              !((item.customDetails ?? '')
                                  .toLowerCase()
                                  .contains(cartSpecTrim.toLowerCase()))) {
                            leadingBadges.add(_buildCartMicroChip(
                              label: cartSpecTrim,
                              bgColor: const Color(0xFFEEF2FF),
                              borderColor: const Color(0xFFC7D2FE),
                              textColor: const Color(0xFF3730A3),
                              tooltip: 'Especificación / Variante: $cartSpecTrim',
                            ));
                          }
                          if (item.hasManualSellingPriceOverride) {
                            leadingBadges.add(_buildCartMicroChip(
                              label: '✏️ Precio manual',
                              bgColor: Colors.teal.shade50,
                              borderColor: Colors.teal.shade300,
                              textColor: Colors.teal.shade900,
                              tooltip:
                                  'Precio ajustado manualmente (Lista: \$${item.product.sellingPrice.toCurrency()})',
                            ));
                          } else if (item.hasActiveOffer) {
                            if (item.hasSurchargeOnOffer) {
                              final rawTierName = item.activeTier == PriceTier.card
                                  ? 'Tarjeta'
                                  : ((item.customTierLabel ?? '').trim().isNotEmpty
                                      ? item.customTierLabel!.trim()
                                      : 'Lista +%');
                              final tierName = isCompactCart && rawTierName == 'Tarjeta'
                                  ? 'Tarj.'
                                  : rawTierName;
                              final f = item.calculatedPrice.appliedSurchargeFactor;
                              final pctStr = (f != null && f > 1.0001)
                                  ? ' (+${((f - 1.0) * 100.0).toCleanMargin()}%)'
                                  : '';
                              leadingBadges.add(_buildCartMicroChip(
                                label: isCompactCart
                                    ? '💳 $tierName s/Of.$pctStr'
                                    : '💳 $tierName s/ Oferta$pctStr',
                                bgColor: Colors.deepOrange.shade50,
                                borderColor: Colors.deepOrange.shade300,
                                textColor: Colors.deepOrange.shade900,
                                tooltip:
                                    '${item.offerBadgeLabel} (\$${item.calculatedPrice.preSurchargeUnitPrice.toCurrency()}) + recargo de lista ($rawTierName) = \$${item.unitPrice.toCurrency()}',
                              ));
                            } else if (item.isOfferSurchargeExempt) {
                              leadingBadges.add(_buildCartMicroChip(
                                label: isCompactCart
                                    ? '🏷️ ${item.offerBadgeLabel} (Sin rec.)'
                                    : '🏷️ ${item.offerBadgeLabel} (Sin recargo)',
                                bgColor: const Color(0xFFD97706).withValues(alpha: 0.12),
                                borderColor: const Color(0xFFD97706).withValues(alpha: 0.40),
                                textColor: const Color(0xFFB45309),
                                tooltip: 'Oferta vigente aplicada sin recargo de lista',
                              ));
                            } else {
                              leadingBadges.add(_buildCartMicroChip(
                                label: item.offerBeatDiscountTier && !isCompactCart
                                    ? '🏷️ ${item.offerBadgeLabel} (Mejor precio)'
                                    : '🏷️ ${item.offerBadgeLabel}',
                                bgColor: const Color(0xFFD97706).withValues(alpha: 0.12),
                                borderColor: const Color(0xFFD97706).withValues(alpha: 0.40),
                                textColor: const Color(0xFFB45309),
                                tooltip: item.offerBeatDiscountTier
                                    ? 'Oferta aplicada por tener menor precio que la lista activa (sin acumular descuentos). Lista base: \$${item.product.sellingPrice.toCurrency()}'
                                    : 'Oferta promocional aplicada (Lista: \$${item.product.sellingPrice.toCurrency()})',
                              ));
                            }
                          } else if (item.hasAgreedPrice) {
                            leadingBadges.add(_buildCartMicroChip(
                              label: isCompactCart ? '📋 Pactado' : '📋 Precio pactado',
                              bgColor: Colors.blueGrey.shade50,
                              borderColor: Colors.blueGrey.shade300,
                              textColor: Colors.blueGrey.shade800,
                              tooltip:
                                  'Precio congelado de orden o presupuesto (Lista: \$${item.product.sellingPrice.toCurrency()})',
                            ));
                          } else if (item.activeTier == PriceTier.wholesale) {
                            leadingBadges.add(_buildCartMicroChip(
                              label: '🏭 Mayorista',
                              bgColor: Colors.blue.shade50,
                              borderColor: Colors.blue.shade300,
                              textColor: Colors.blue.shade800,
                              tooltip: 'Lista Mayorista aplicada',
                            ));
                          } else if (item.activeTier == PriceTier.card) {
                            leadingBadges.add(_buildCartMicroChip(
                              label: '💳 Tarjeta',
                              bgColor: Colors.orange.shade50,
                              borderColor: Colors.orange.shade300,
                              textColor: Colors.orange.shade800,
                              tooltip: 'Recargo Lista Tarjeta aplicado',
                            ));
                          } else if (item.activeTier == PriceTier.custom) {
                            final pct = (item.customFactor - 1.0) * 100.0;
                            final pctStr = pct.abs() >= 0.05
                                ? ' (${pct > 0 ? '+' : ''}${pct.toCleanMargin()}%)'
                                : '';
                            final tierLabel =
                                (item.customTierLabel ?? '').trim().isNotEmpty
                                    ? item.customTierLabel!.trim()
                                    : 'Lista Esp.';
                            leadingBadges.add(_buildCartMicroChip(
                              label: '🏷️ $tierLabel$pctStr',
                              bgColor: Colors.purple.shade50,
                              borderColor: Colors.purple.shade300,
                              textColor: Colors.purple.shade800,
                              tooltip: 'Lista personalizada: $tierLabel$pctStr',
                            ));
                          } else if (item.hasVolumeScale) {
                            final tier = item.product.getApplicableTier(item.quantity);
                            final minQ = tier != null
                                ? ((tier['min_quantity'] as num?)?.toQty() ?? '')
                                : '';
                            leadingBadges.add(_buildCartMicroChip(
                              label: minQ.isNotEmpty ? '📦 Escala x$minQ' : '📦 Escala',
                              bgColor: Colors.green.shade50,
                              borderColor: Colors.green.shade300,
                              textColor: Colors.green.shade800,
                              tooltip: 'Descuento por cantidad/volumen aplicado',
                            ));
                          }

                          final Widget? quickOriginChip =
                              (item.isTemporary && !item.saveToCatalog)
                                  ? _buildCartMicroChip(
                                      label: item.product.isCombo
                                          ? '⚡ Combo Temp.'
                                          : '⚡ Temporal',
                                      bgColor: Colors.amber.shade50,
                                      borderColor: Colors.amber.shade300,
                                      textColor: Colors.amber.shade900,
                                      tooltip:
                                          'Ítem temporal solo para esta venta (no descuenta stock propio)',
                                    )
                                  : (item.saveToCatalog
                                      ? _buildCartMicroChip(
                                          label: '🆕 A catálogo',
                                          bgColor: Colors.blue.shade50,
                                          borderColor: Colors.blue.shade300,
                                          textColor: Colors.blue.shade900,
                                          tooltip:
                                              'Se creará automáticamente en el catálogo al cobrar',
                                        )
                                      : null);

                          final trailingBadges = <Widget>[
                            if (item.isRenamed)
                              _buildCartMicroChip(
                                label: '✏️ Alias',
                                bgColor: Colors.indigo.shade50,
                                borderColor: Colors.indigo.shade200,
                                textColor: Colors.indigo.shade800,
                                tooltip: 'Nombre original en catálogo: ${item.product.name}',
                              ),
                            if (item.hasManualCostOverride)
                              _buildCartMicroChip(
                                label: '✏️ Costo',
                                bgColor: Colors.teal.shade50,
                                borderColor: Colors.teal.shade200,
                                textColor: Colors.teal.shade800,
                                tooltip:
                                    'Costo ajustado para esta venta: \$${item.effectiveCostPrice.toCurrency()}',
                              ),
                            if (item.batchId != null)
                              _buildCartMicroChip(
                                label: '🏷️ ${item.batchCode ?? 'Lote #${item.batchId}'}',
                                bgColor: Colors.deepPurple.shade50,
                                borderColor: Colors.deepPurple.shade200,
                                textColor: Colors.deepPurple.shade800,
                                tooltip:
                                    'Lote específico escaneado${item.batchExpirationDate != null ? ' • Vence: ${item.batchExpirationDate}' : ''}',
                              ),
                          ];

                          // En anchos generosos del carrito, subir el badge comercial único a la Fila 2
                          // ahorra una fila completa cuando el producto no tiene otros chips.
                          final bool inlineStrategyInPriceRow =
                              isWideCart && leadingBadges.length == 1;

                          final nameColumn = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.effectiveDisplayName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                  height: 1.2,
                                ),
                              ),
                              if (item.customDetails != null &&
                                  item.customDetails!.trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    '📝 ${item.customDetails!.trim()}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.blueGrey.shade700,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                            ],
                          );

                          return _AnimatedCartItemTile(
                            key: ObjectKey(item),
                            quantity: item.quantity,
                            subtotal: item.subtotal,
                            onTap: () => _openRenameCartItemDialog(item),
                            onSecondaryTap: () => _openRenameCartItemDialog(item),
                            child: Padding(
                              padding: isCompactCart
                                  ? const EdgeInsets.symmetric(
                                      horizontal: 9, vertical: 7)
                                  : const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Fila 1: Nombre del producto (100% ancho disponible) + Editar + Eliminar
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: item.isRenamed
                                            ? Tooltip(
                                                message:
                                                    '${item.effectiveDisplayName}\n(Catálogo: ${item.product.name})',
                                                waitDuration: const Duration(
                                                    milliseconds: 500),
                                                child: nameColumn,
                                              )
                                            : nameColumn,
                                      ),
                                      const SizedBox(width: 4),
                                      Tooltip(
                                        message:
                                            'Editar Línea en Carrito (Clic / Clic Der. / Ctrl+E)',
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(6),
                                          onTap: () =>
                                              _openRenameCartItemDialog(item),
                                          child: Padding(
                                            padding: const EdgeInsets.all(2.0),
                                            child: Icon(
                                              Icons.edit_note_rounded,
                                              size: 19,
                                              color: item.isRenamed ||
                                                      item.hasManualPriceOverride ||
                                                      (item.customDetails != null &&
                                                          item.customDetails!
                                                              .trim()
                                                              .isNotEmpty)
                                                  ? Colors.indigo.shade700
                                                  : Colors.blueGrey.shade600,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      InkWell(
                                        borderRadius: BorderRadius.circular(6),
                                        onTap: () {
                                          pos.removeFromCart(item);
                                          _requestSearchFocusSilently();
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.all(2.0),
                                          child: Icon(
                                            Icons.delete_outline,
                                            size: 19,
                                            color: Colors.red.shade600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),

                                  // Fila 2: Precio unitario + Micro-IVA (+ badge en modo ancho) + Stepper + Subtotal
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: Wrap(
                                          spacing: 5,
                                          runSpacing: 3,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            if (item.unitPrice !=
                                                item.effectiveRegularUnitPrice)
                                              Text(
                                                '\$${item.effectiveRegularUnitPrice.toCurrency()}',
                                                style: const TextStyle(
                                                  decoration:
                                                      TextDecoration.lineThrough,
                                                  color: Colors.grey,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            Text(
                                              '$qtyDisplay x \$${item.unitPrice.toCurrency()}',
                                              style: TextStyle(
                                                fontSize: isCompactCart ? 11.5 : 12,
                                                fontWeight: (item.unitPrice !=
                                                            item.effectiveRegularUnitPrice ||
                                                        item.hasManualPriceOverride)
                                                    ? FontWeight.bold
                                                    : FontWeight.w500,
                                                color: item.unitPrice >
                                                        item.effectiveRegularUnitPrice
                                                    ? Colors.red.shade700
                                                    : (item.unitPrice <
                                                            item.effectiveRegularUnitPrice
                                                        ? Colors.green.shade700
                                                        : (item.hasManualPriceOverride
                                                            ? Colors.teal.shade800
                                                            : Colors.black87)),
                                              ),
                                            ),
                                            if (ivaChip != null) ivaChip,
                                            if (quickOriginChip != null)
                                              quickOriginChip,
                                            if (inlineStrategyInPriceRow)
                                              ...leadingBadges,
                                          ],
                                        ),
                                      ),
                                      SizedBox(width: isCompactCart ? 4 : 6),

                                      // Controles (- / +) y Subtotal adaptables
                                      Flexible(
                                        flex: 0,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (item.product.isSoldByWeight)
                                                IconButton(
                                                  icon: const Icon(
                                                      Icons.scale_outlined,
                                                      size: 20,
                                                      color: Colors.blue),
                                                  padding: EdgeInsets.zero,
                                                  constraints:
                                                      const BoxConstraints(),
                                                  tooltip: 'Editar peso',
                                                  onPressed: () {
                                                    _openRenameCartItemDialog(
                                                      item,
                                                      focusQuantityInitially: true,
                                                    );
                                                  },
                                                )
                                              else if ((item.quantity % 1).abs() >
                                                      1e-6 ||
                                                  (item.customDetails != null &&
                                                      item.customDetails!
                                                          .trim()
                                                          .isNotEmpty)) ...[
                                                InkWell(
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  onTap: () =>
                                                      _openRenameCartItemDialog(
                                                    item,
                                                    focusQuantityInitially:
                                                        true,
                                                  ),
                                                  child: Container(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                      horizontal: isCompactCart
                                                          ? 5
                                                          : 7,
                                                      vertical: 3,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          Colors.teal.shade50,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6),
                                                      border: Border.all(
                                                        color: Colors
                                                            .teal.shade200,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      qtyDisplay,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 12.5,
                                                        color: Colors
                                                            .teal.shade900,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                if (context
                                                        .read<SettingsProvider>()
                                                        .canUseHardwareCalculatorFor(
                                                          product: item.product,
                                                          rubros: Provider.of<CatalogProvider?>(
                                                                    context,
                                                                    listen: false,
                                                                  )?.safeRubros ??
                                                              const [],
                                                        ) &&
                                                    !item.isTemporary &&
                                                    item.product.id > 0) ...[
                                                  const SizedBox(width: 4),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.straighten_rounded,
                                                      size: 18,
                                                      color: Color(0xFF0F766E),
                                                    ),
                                                    padding: EdgeInsets.zero,
                                                    constraints:
                                                        const BoxConstraints(),
                                                    tooltip:
                                                        'Recalcular medidas (F7)',
                                                    onPressed: () =>
                                                        _openHardwareCalculatorDialog(
                                                      initialProduct:
                                                          item.product,
                                                      replacingCartItem: item,
                                                    ),
                                                  ),
                                                ],
                                              ] else ...[
                                                InkWell(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  onTap: () {
                                                    if (item.quantity > 1) {
                                                      pos.updateQuantity(
                                                          item, item.quantity - 1);
                                                    } else {
                                                      pos.removeFromCart(item);
                                                    }
                                                    _requestSearchFocusSilently();
                                                  },
                                                  child: Padding(
                                                    padding: EdgeInsets.all(
                                                        isCompactCart ? 1.5 : 2.0),
                                                    child: Icon(
                                                        Icons.remove_circle_outline,
                                                        size: isCompactCart ? 18 : 20,
                                                        color: Colors.grey),
                                                  ),
                                                ),
                                                InkWell(
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  onTap: () =>
                                                      _openRenameCartItemDialog(
                                                    item,
                                                    focusQuantityInitially: true,
                                                  ),
                                                  child: Padding(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                            horizontal:
                                                                isCompactCart ? 4 : 6,
                                                            vertical: 2),
                                                    child: Text(
                                                      qtyDisplay,
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                InkWell(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  onTap: () {
                                                    final catalogProducts = Provider
                                                            .of<CatalogProvider>(
                                                                context,
                                                                listen: false)
                                                        .products;
                                                    final blockMsg = pos
                                                        .validateUnitStockConstraint(
                                                      item.product,
                                                      item.quantity + 1,
                                                      excludingItem: item,
                                                      catalogProducts:
                                                          catalogProducts,
                                                    );
                                                    if (blockMsg != null) {
                                                      SnackBarService.error(
                                                          context, blockMsg);
                                                      _searchFocusNode
                                                          .requestFocus();
                                                      return;
                                                    }
                                                    pos.updateQuantity(
                                                        item, item.quantity + 1);
                                                    _requestSearchFocusSilently();
                                                  },
                                                  child: Padding(
                                                    padding: EdgeInsets.all(
                                                        isCompactCart ? 1.5 : 2.0),
                                                    child: Icon(
                                                        Icons.add_circle_outline,
                                                        size: isCompactCart ? 18 : 20,
                                                        color: Colors.blue),
                                                  ),
                                                ),
                                              ],
                                              SizedBox(
                                                  width: isCompactCart ? 6 : 10),
                                              Text(
                                                '\$${item.subtotal.toCurrency()}',
                                                style: TextStyle(
                                                  fontSize:
                                                      isCompactCart ? 13.5 : 14.5,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                  // Fila 3 unificada: Estrategia/Precio (si no se subió en ancho) -> Stock/Vto -> Origen/Costo
                                  _CartItemStockIndicator(
                                    item: item,
                                    leadingBadges: inlineStrategyInPriceRow
                                        ? const []
                                        : leadingBadges,
                                    trailingBadges: trailingBadges,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
              ],
            ),
          ),

          // Footer (Total + Doble Botón)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5))
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Lista de Precios [Premium Feature + Modo Avanzado] ────────────────
                if (context
                        .watch<SettingsProvider>()
                        .settings
                        ?.hasAnyAlternativePriceTier ==
                    true)
                  Builder(builder: (_) {
                    final settings = context.read<SettingsProvider>().settings!;
                    final customTiers = settings.activeCustomPriceTiers;

                    final dropdownItems = <DropdownMenuItem<String>>[
                      const DropdownMenuItem(
                          value: 'base', child: Text('🏪 Minorista (Base)')),
                      if (settings.isWholesaleTierAvailable)
                        const DropdownMenuItem(
                            value: 'wholesale', child: Text('🏭 Mayorista')),
                      if (settings.isCardTierAvailable)
                        const DropdownMenuItem(
                            value: 'card', child: Text('💳 Tarjeta')),
                      // Listas personalizadas dinámicas del backend (con modificador != 0)
                      ...customTiers.map((t) {
                        final name = t['name']?.toString().trim() ?? 'Custom';
                        final mod = (t['modifier'] as num?)?.toDouble() ?? 0.0;
                        final sign = mod >= 0 ? '+' : '';
                        return DropdownMenuItem(
                          value: 'custom_$name',
                          child: Text(
                              '🏷️ $name ($sign${mod.toStringAsFixed(0)}%)'),
                        );
                      }),
                    ];

                    // Valor seguro para evitar excepciones si una lista quedó en 0% o fue quitada
                    final rawCurrentValue = pos.activeTier == PriceTier.custom
                        ? (pos.customTierLabel != null
                            ? 'custom_${pos.customTierLabel}'
                            : 'base')
                        : pos.activeTier.name;
                    final availableValues =
                        dropdownItems.map((item) => item.value).toSet();
                    final currentValue =
                        availableValues.contains(rawCurrentValue)
                            ? rawCurrentValue
                            : 'base';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Lista de Precio:',
                              style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: SizedBox(
                                      height: 28,
                                      child: DropdownButton<String>(
                                        value: currentValue,
                                        isDense: true,
                                        underline: const SizedBox(),
                                        icon: const Icon(Icons.keyboard_arrow_down,
                                            size: 16),
                                        style: const TextStyle(
                                            fontSize: 12.5,
                                            color: Colors.black87,
                                            fontWeight: FontWeight.bold),
                                        items: dropdownItems,
                                        onChanged: (String? val) {
                                          if (val == null) return;
                                          if (val == 'base') {
                                            pos.setPriceTier(PriceTier.base);
                                          } else if (val == 'wholesale') {
                                            pos.setPriceTier(
                                              PriceTier.wholesale,
                                              wholesaleFactor:
                                                  settings.wholesalePriceFactor,
                                              cardFactor:
                                                  settings.cardPriceFactor,
                                            );
                                          } else if (val == 'card') {
                                            pos.setPriceTier(
                                              PriceTier.card,
                                              wholesaleFactor:
                                                  settings.wholesalePriceFactor,
                                              cardFactor:
                                                  settings.cardPriceFactor,
                                            );
                                          } else if (val.startsWith('custom_')) {
                                            final label =
                                                val.substring(7); // strip 'custom_'
                                            final tier = customTiers.firstWhere(
                                                (t) => t['name'] == label,
                                                orElse: () => {});
                                            final mod =
                                                (tier['modifier'] as num?)?.toDouble() ??
                                                    0.0;
                                            pos.setPriceTier(
                                              PriceTier.custom,
                                              customFactor: 1 + (mod / 100),
                                              customLabel: label,
                                            );
                                          }
                                          WidgetsBinding.instance.addPostFrameCallback((_) {
                                            if (mounted) _requestSearchFocusSilently();
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Consumer<LocalTerminalProvider>(
                                  builder: (context, terminal, _) {
                                    // Se considera "fijado" si el nivel de la terminal 
                                    // coincide con el que seleccionamos actualmente
                                    final isPinned = terminal.lockedPriceTier == currentValue;
                                    return IconButton(
                                      icon: Icon(
                                        isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                                        size: 18,
                                        color: isPinned ? Colors.orange.shade700 : Colors.grey.shade400,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      tooltip: isPinned ? 'Lista fijada para esta terminal' : 'Fijar lista para esta terminal',
                                      onPressed: () {
                                        if (isPinned) {
                                          terminal.setLockedPriceTier('none');
                                          pos.setDefaultTier('base', null);
                                          SnackBarService.success(context, 'Lista de precios desbloqueada. Volverá a Base al finalizar la venta.');
                                        } else {
                                          final customLabel = pos.activeTier == PriceTier.custom ? pos.customTierLabel : null;
                                          terminal.setLockedPriceTier(currentValue, label: customLabel);
                                          pos.setDefaultTier(currentValue, customLabel);
                                          SnackBarService.success(context, 'Lista fijada. El carrito usará esta lista automáticamente.');
                                        }
                                        _requestSearchFocusSilently();
                                      },
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  })
                else if (context.watch<SettingsProvider>().settings != null &&
                    !context
                        .watch<SettingsProvider>()
                        .settings!
                        .features
                        .multiplePrices)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: InkWell(
                      key: const ValueKey('pos_locked_price_tiers_indicator'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: () async {
                        await PlanUpgradeDialog.show(
                          context,
                          featureName: 'Múltiples Listas de Precios',
                          description:
                              'Operá con listas Mayorista, Tarjeta y listas personalizadas automáticas desde el mostrador con el Plan Premium.',
                        );
                        if (mounted) _requestSearchFocusSilently();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Lista de Precio:',
                              style: TextStyle(
                                color: Colors.blueGrey.shade700,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.lock_outline_rounded,
                                    size: 14,
                                    color: Colors.amber.shade800,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      'Minorista · Mayorista/Tarjeta [PRO]',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.amber.shade900,
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
                  ),

                // ── Resumen Financiero: Subtotal, Ahorro/Descuentos y Total ──────────────
                const PosFinancialSummary(),
                const SizedBox(height: 8),

                // ── Atajos Rápidos Modernos (Espera, Presupuestos, Clientes, Ofertas, Precios) ──
                PosQuickActionButtons(
                  onHoldOrder: _handleHoldOrder,
                  onOpenPendingList: () => _pendingOrdersPortalController.toggle(),
                  onOpenPriceLookup: _openPriceLookupDialog,
                  onAfterDialogClosed: () {
                    if (mounted) _requestSearchFocusSilently();
                  },
                ),
                const SizedBox(height: 6),

                // ── Botón Principal: Cobrar ───────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: pos.cart.isEmpty
                          ? Colors.grey.shade400
                          : pos.isLoading
                              ? Colors.green.shade300
                              : Colors.green.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: pos.isLoading ? 0 : 3,
                    ),
                    onPressed: pos.cart.isEmpty || pos.isLoading
                        ? null
                        : _handleCheckout,
                    child: pos.isLoading
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.2)),
                              SizedBox(width: 10),
                              Text('Procesando...',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                            ],
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.point_of_sale_rounded, size: 20),
                              SizedBox(width: 8),
                              Text('💵 COBRAR',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.1)),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          )
        ],
      );
    });
  }

  /// OF-01: Productos candidatos para el filtro "Ofertas": el catálogo activo en memoria (primeros 500)
  /// más los productos en oferta vigente que no entraron en ese bloque, traídos completos aparte.
  /// Si un producto está en ambos, prevalece el del catálogo (stock y contadores en caliente).
  List<Product> _offerCandidateProducts(CatalogProvider catalog, OfferProvider offerProv) {
    final activeBase = catalog.activeProducts;
    final extra = offerProv.offerOnlyProducts.where((p) => p.active).toList();
    if (extra.isEmpty) return List<Product>.from(activeBase);
    final loadedIds = catalog.products.map((p) => p.id).toSet();
    return [
      ...activeBase,
      ...extra.where((p) => !loadedIds.contains(p.id)),
    ];
  }

  /// OF-01: Pide al servidor los productos en oferta que faltan en el catálogo en memoria.
  /// Idempotente (el provider compara el conjunto faltante), por eso puede llamarse en cada build.
  void _scheduleOfferOnlyProductsSync(CatalogProvider catalog, OfferProvider offerProv) {
    if (catalog.isLoading || catalog.products.isEmpty || _searchQuery.isNotEmpty) return;
    final loadedIds = catalog.products.map((p) => p.id).toSet();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) offerProv.syncOfferOnlyProducts(loadedIds);
    });
  }

  List<Product> _categoryCandidateProducts(CatalogProvider catalog, int categoryId) {
    final activeBase = catalog.activeProducts;
    final extra = catalog.getCategoryExtraProducts(categoryId);
    if (extra.isEmpty) return List<Product>.from(activeBase);
    final loadedIds = catalog.products.map((p) => p.id).toSet();
    return [
      ...activeBase,
      ...extra.where((p) => !loadedIds.contains(p.id)),
    ];
  }

  void _scheduleCategoryProductsSync(CatalogProvider catalog, int categoryId) {
    if (catalog.isLoading || catalog.products.isEmpty || _searchQuery.isNotEmpty) return;
    if (catalog.isCategoryHydrated(categoryId)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) catalog.syncCategoryProducts(categoryId);
    });
  }

  int? _categoryIdByName(CatalogProvider catalog, String categoryName) {
    final target = categoryName.trim().toLowerCase();
    for (final c in catalog.categories) {
      if (c.name.trim().toLowerCase() == target) return c.id;
    }
    return null;
  }

  /// `true` mientras el filtro activo espera del servidor productos que no están en los
  /// primeros 500 (solo la primera vez por sesión: luego queda en caché y es instantáneo).
  bool _isQuickAccessFilterHydrating(CatalogProvider catalog, LocalTerminalProvider localTerminal) {
    if (_searchQuery.isNotEmpty || catalog.isLoading || catalog.products.isEmpty) return false;
    if (_quickAccessFilter == 'weight') return !catalog.isWeightHydrated;
    if (_quickAccessFilter == 'pinned') {
      return !catalog.isPinnedHydrated(localTerminal.pinnedProductIds);
    }
    if (_quickAccessFilter.startsWith('cat_')) {
      final catId = _categoryIdByName(catalog, _quickAccessFilter.substring(4));
      return catId != null && !catalog.isCategoryHydrated(catId);
    }
    return false;
  }

  /// Precarga en segundo plano las categorías visibles como chips, para que al tocarlas
  /// aparezcan completas sin espera. Secuencial y deduplicada en el provider.
  void _schedulePrefetchVisibleCategories(CatalogProvider catalog, Iterable<String> categoryNames) {
    if (catalog.isLoading || catalog.products.isEmpty || catalog.categories.isEmpty) return;
    final ids = <int>[];
    for (final name in categoryNames) {
      final id = _categoryIdByName(catalog, name);
      if (id != null && !catalog.isCategoryHydrated(id)) ids.add(id);
    }
    if (ids.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) catalog.prefetchCategories(ids);
    });
  }

  List<Product> _weightCandidateProducts(CatalogProvider catalog) {
    final activeBase = catalog.activeProducts;
    final extra = catalog.weightOnlyProducts;
    if (extra.isEmpty) return List<Product>.from(activeBase);
    final loadedIds = catalog.products.map((p) => p.id).toSet();
    return [
      ...activeBase,
      ...extra.where((p) => !loadedIds.contains(p.id)),
    ];
  }

  void _scheduleWeightProductsSync(CatalogProvider catalog) {
    if (catalog.isLoading || catalog.products.isEmpty || _searchQuery.isNotEmpty) return;
    if (catalog.isWeightHydrated) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) catalog.syncWeightProducts();
    });
  }

  List<Product> _pinnedCandidateProducts(CatalogProvider catalog) {
    final activeBase = catalog.activeProducts;
    final extra = catalog.pinnedExtraProducts;
    if (extra.isEmpty) return List<Product>.from(activeBase);
    final loadedIds = catalog.products.map((p) => p.id).toSet();
    return [
      ...activeBase,
      ...extra.where((p) => !loadedIds.contains(p.id)),
    ];
  }

  void _schedulePinnedProductsSync(CatalogProvider catalog, Set<int> pinnedIds) {
    if (catalog.isLoading || catalog.products.isEmpty || _searchQuery.isNotEmpty || pinnedIds.isEmpty) return;
    if (catalog.isPinnedHydrated(pinnedIds)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) catalog.syncPinnedProducts(pinnedIds);
    });
  }

  List<Product> _getFilteredProducts(CatalogProvider catalog, OfferProvider offerProv, LocalTerminalProvider localTerminal) {
    if (_searchQuery.isNotEmpty) {
      return _searchResults.where((p) => p.active).toList();
    }

    final settingsProv = Provider.of<SettingsProvider?>(context, listen: false);
    final demoteOutOfStock = settingsProv?.settings?.posDemoteOutOfStock ?? false;

    List<Product> filtered = List<Product>.from(catalog.activeProducts);

    if (_quickAccessFilter == 'pinned') {
      _schedulePinnedProductsSync(catalog, localTerminal.pinnedProductIds);
      filtered = _pinnedCandidateProducts(catalog)
          .where((p) => localTerminal.pinnedProductIds.contains(p.id))
          .toList();
    } else if (_quickAccessFilter == 'top_sellers') {
      filtered = filtered.where((p) => p.salesCount > 0).toList();
    } else if (_quickAccessFilter == 'offers') {
      // OF-01: incluir productos en oferta que quedaron fuera del bloque inicial de 500 del catálogo
      filtered = _offerCandidateProducts(catalog, offerProv)
          .where((p) => offerProv.getActiveOfferForProduct(p.id, basePrice: p.sellingPrice) != null)
          .toList();
    } else if (_quickAccessFilter == 'weight') {
      _scheduleWeightProductsSync(catalog);
      filtered = _weightCandidateProducts(catalog).where((p) => p.isSoldByWeight).toList();
    } else if (_quickAccessFilter.startsWith('cat_')) {
      final categoryName = _quickAccessFilter.substring(4).trim();
      final catId = _categoryIdByName(catalog, categoryName);
      if (catId != null) {
        _scheduleCategoryProductsSync(catalog, catId);
        filtered = _categoryCandidateProducts(catalog, catId)
            .where((p) => p.category?.name.trim().toLowerCase() == categoryName.toLowerCase())
            .toList();
      } else {
        filtered = filtered.where((p) => p.category?.name.trim().toLowerCase() == categoryName.toLowerCase()).toList();
      }
    }

    // Mientras el filtro trae del servidor los productos que faltan, no se muestra la lista
    // parcial (evita el "aparecen 2 y después de golpe todos"). Tampoco se congela el orden
    // con datos incompletos: se calcula una sola vez con el conjunto completo.
    if (_isQuickAccessFilterHydrating(catalog, localTerminal)) {
      return const <Product>[];
    }

    final pinnedSorted = localTerminal.pinnedProductIds.toList()..sort();
    final signature = '$_quickAccessFilter|${pinnedSorted.join(",")}|$demoteOutOfStock|${catalog.catalogOrderVersion}';

    if (_frozenOrderSignature == signature && _frozenRankById.isNotEmpty) {
      for (final p in filtered) {
        if (!_frozenRankById.containsKey(p.id)) {
          _frozenRankById[p.id] = _frozenRankById.length;
        }
      }
      filtered.sort((a, b) {
        final rankA = _frozenRankById[a.id] ?? 999999;
        final rankB = _frozenRankById[b.id] ?? 999999;
        return rankA.compareTo(rankB);
      });
      return filtered;
    }

    // Ordenamiento inteligente: 1° Fijados -> 2° Con Stock (opcional) -> 3° Más Vendidos -> 4° Pesables -> 5° Nombre
    filtered.sort((a, b) {
      if (_quickAccessFilter != 'top_sellers') {
        final aPinned = localTerminal.pinnedProductIds.contains(a.id);
        final bPinned = localTerminal.pinnedProductIds.contains(b.id);

        if (aPinned != bPinned) {
          return aPinned ? -1 : 1;
        }
      }

      if (demoteOutOfStock) {
        final aHasStock = a.stock > 0;
        final bHasStock = b.stock > 0;
        if (aHasStock != bHasStock) {
          return aHasStock ? -1 : 1;
        }
      }

      final salesCmp = b.salesCount.compareTo(a.salesCount);
      if (salesCmp != 0) return salesCmp;

      if (a.isSoldByWeight != b.isSoldByWeight) {
        return a.isSoldByWeight ? -1 : 1;
      }

      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    _frozenOrderSignature = signature;
    _frozenRankById
      ..clear()
      ..addEntries(
        List.generate(filtered.length, (i) => MapEntry(filtered[i].id, i)),
      );

    return filtered;
  }

  bool _handlePosHardwareKey(KeyEvent event) {
    if (!mounted || _posRoute?.isCurrent != true) return false;
    if (event is! KeyDownEvent) return false;

    // F1 → Guía rápida de teclado (es ayuda contextual, no una operación de caja:
    // debe funcionar incluso sin turno abierto)
    if (event.logicalKey == LogicalKeyboardKey.f1) {
      _showKeyboardShortcutsHelpDialog();
      return true;
    }

    final cashProv = Provider.of<CashRegisterProvider>(context, listen: false);
    if (cashProv.currentShift == null || !cashProv.currentShift!.isOpen) {
      return false;
    }

    final posProvider = Provider.of<PosProvider>(context, listen: false);
    final catalog = Provider.of<CatalogProvider>(context, listen: false);
    final offerProv = Provider.of<OfferProvider>(context, listen: false);
    final localTerminal = tryGetLocalTerminalProvider(context, listen: false);
    final displayItems = _getFilteredProducts(
      catalog,
      offerProv,
      localTerminal ?? LocalTerminalProvider(),
    );
    final isSearchEmpty = _searchController.text.trim().isEmpty;

    // F9 / F12 → Cobrar directo (funciona siempre que haya ítems en el carrito)
    if (event.logicalKey == LogicalKeyboardKey.f9 || event.logicalKey == LogicalKeyboardKey.f12) {
      _hideSearchHistoryPopover();
      if (posProvider.cart.isNotEmpty && !posProvider.isLoading && !_isCheckingOut) {
        _handleCheckout();
      }
      return true;
    }

    // F3 → Crear Producto o Combo Rápido (Temporal o en Catálogo)
    if (event.logicalKey == LogicalKeyboardKey.f3) {
      _hideSearchHistoryPopover();
      _openQuickItemDialog();
      return true;
    }

    // F4 → Poner en Espera directo
    if (event.logicalKey == LogicalKeyboardKey.f4) {
      _hideSearchHistoryPopover();
      if (posProvider.cart.isNotEmpty && !posProvider.isLoading) {
        _handleHoldOrder();
      }
      return true;
    }

    // F5 → Consultar Precio sin agregar al carrito
    if (event.logicalKey == LogicalKeyboardKey.f5) {
      _hideSearchHistoryPopover();
      _openPriceLookupDialog();
      return true;
    }

    // F6 → Abrir selector rápido de clientes
    if (event.logicalKey == LogicalKeyboardKey.f6) {
      _hideSearchHistoryPopover();
      final settingsProv = Provider.of<SettingsProvider>(context, listen: false);
      final hasCurrentAccounts = settingsProv.settings?.features.currentAccounts ?? false;
      if (!hasCurrentAccounts) {
        PlanUpgradeDialog.show(
          context,
          featureName: 'Gestión de Clientes y Cuentas Corrientes',
          description:
              'La gestión de clientes con cuenta corriente y saldo a favor está disponible en el Plan Ferretería/Corralón o como módulo adicional.',
        ).then((_) {
          if (mounted) _requestSearchFocusSilently();
        });
      } else {
        showDialog(
          context: context,
          builder: (ctx) => const PosQuickCustomerDialog(),
        ).then((_) {
          if (mounted) _requestSearchFocusSilently();
        });
      }
      return true;
    }

    // F7 → Calculadora Rápida de Mostrador para Ferretería (Machimbre / Chapas / Pintura)
    if (event.logicalKey == LogicalKeyboardKey.f7) {
      final settingsProv =
          Provider.of<SettingsProvider>(context, listen: false);
      final rubros = Provider.of<CatalogProvider?>(context, listen: false)?.safeRubros ??
          const [];
      if (settingsProv.canUseHardwareCalculatorFor(rubros: rubros)) {
        _hideSearchHistoryPopover();
        _openHardwareCalculatorDialog();
        return true;
      }
    }

    // Tab → Cerrar popover si está abierto para no quedar flotando tras cambiar foco
    if (event.logicalKey == LogicalKeyboardKey.tab &&
        _searchHistoryPortalController.isShowing) {
      _hideSearchHistoryPopover();
      return false;
    }

    // Escape → Cerrar overlay de órdenes pendientes o historial de búsqueda o limpiar buscador/resetear filtro
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_searchHistoryPortalController.isShowing) {
        _hideSearchHistoryPopover();
        _requestSearchFocusSilently();
        return true;
      }
      if (_pendingOrdersPortalController.isShowing) {
        _pendingOrdersPortalController.hide();
        _requestSearchFocusSilently();
        return true;
      }
      if (_searchController.text.isNotEmpty) {
        _searchController.clear();
        _onPosSearchChanged('');
        _requestSearchFocusSilently();
      } else if (_quickAccessFilter != 'all') {
        setState(() {
          _quickAccessFilter = 'all';
        });
        _requestSearchFocusSilently();
      }
      return true;
    }

    // Atajos que solo funcionan cuando el buscador está vacío
    if (isSearchEmpty) {
      // Navegación por teclado en Popover de historial de búsquedas (ArrowDown/ArrowUp/Enter)
      if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
          (_searchFocusNode.hasFocus || _searchHistoryPortalController.isShowing)) {
        final historyTerms = localTerminal?.recentTermsForScope(
              LocalTerminalProvider.scopePosCounter,
            ) ??
            const <String>[];
        final historyProducts =
            _resolveActiveRecentProducts(catalog, localTerminal);
        final totalHistory = historyTerms.length + historyProducts.length;
        if (totalHistory > 0) {
          if (!_searchHistoryPortalController.isShowing) {
            _showSearchHistoryPopoverIfAvailable(initialHighlightIndex: 0);
          } else {
            setState(() {
              _searchHistoryHighlightIndex =
                  (_searchHistoryHighlightIndex + 1).clamp(0, totalHistory - 1);
            });
          }
          return true;
        }
      }

      if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
          _searchHistoryPortalController.isShowing) {
        setState(() {
          _searchHistoryHighlightIndex = _searchHistoryHighlightIndex <= 0
              ? -1
              : _searchHistoryHighlightIndex - 1;
        });
        return true;
      }

      // Ctrl + 1..9 para seleccionar productos (anti-AltCodes de Windows)
      final isControlPressed = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) ||
                               HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight);

      if (isControlPressed) {
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.keyE) {
          if (posProvider.cart.isNotEmpty) {
            _openRenameCartItemDialog(posProvider.cart.last);
          }
          return true;
        }
        int? index;

        if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
          index = 0;
        } else if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
          index = 1;
        } else if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
          index = 2;
        } else if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
          index = 3;
        } else if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) {
          index = 4;
        } else if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) {
          index = 5;
        } else if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) {
          index = 6;
        } else if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) {
          index = 7;
        } else if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) {
          index = 8;
        }

        if (index != null && index < displayItems.length) {
          _handleProductSelection(displayItems[index]);
        }
        // Consumir cualquier Ctrl+1..9 (haya producto o no) para que no se propague al buscador
        return index != null;
      }

      // Enter / NumpadEnter → Si hay un ítem del historial resaltado con flechas, aplicarlo;
      // si no hay selección (-1), cerrar popover y cobrar directamente (Enter: Cobrar).
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        if (_searchHistoryPortalController.isShowing &&
            _searchHistoryHighlightIndex >= 0) {
          final historyTerms = localTerminal?.recentTermsForScope(
                LocalTerminalProvider.scopePosCounter,
              ) ??
              const <String>[];
          final historyProducts =
              _resolveActiveRecentProducts(catalog, localTerminal);
          if (_searchHistoryHighlightIndex < historyTerms.length) {
            _applyRecentSearchTerm(historyTerms[_searchHistoryHighlightIndex]);
            return true;
          }
          final pIdx = _searchHistoryHighlightIndex - historyTerms.length;
          if (pIdx >= 0 && pIdx < historyProducts.length) {
            final prod = historyProducts[pIdx];
            _hideSearchHistoryPopover();
            _recordRecentSearchIfValid(
              null,
              selectedProductId: prod.id,
              selectedProduct: prod,
            );
            _handleProductSelection(prod);
            return true;
          }
        }
        _hideSearchHistoryPopover();
        if (posProvider.cart.isNotEmpty && !posProvider.isLoading && !_isCheckingOut) {
          _handleCheckout();
        }
        return true;
      }

      // + → Incrementar último ítem
      if (event.logicalKey == LogicalKeyboardKey.numpadAdd ||
          event.logicalKey == LogicalKeyboardKey.add ||
          event.character == '+') {
        if (posProvider.cart.isNotEmpty) {
          final lastItem = posProvider.cart.last;
          final isCalculatedOrFractional =
              (lastItem.quantity % 1).abs() > 1e-6 ||
                  (lastItem.customDetails != null &&
                      lastItem.customDetails!.trim().isNotEmpty);
          if (!lastItem.product.isSoldByWeight && !isCalculatedOrFractional) {
            final catalogProducts =
                Provider.of<CatalogProvider>(context, listen: false).activeProducts;
            final blockMsg = posProvider.validateUnitStockConstraint(
              lastItem.product,
              lastItem.quantity + 1,
              excludingItem: lastItem,
              catalogProducts: catalogProducts,
            );
            if (blockMsg != null) {
              SnackBarService.error(context, blockMsg);
              return true;
            }
            posProvider.updateQuantity(lastItem, lastItem.quantity + 1);
          }
          return true;
        }
      }

      // - → Decrementar último ítem
      if (event.logicalKey == LogicalKeyboardKey.numpadSubtract ||
          event.logicalKey == LogicalKeyboardKey.minus ||
          event.character == '-') {
        if (posProvider.cart.isNotEmpty) {
          final lastItem = posProvider.cart.last;
          final isCalculatedOrFractional =
              (lastItem.quantity % 1).abs() > 1e-6 ||
                  (lastItem.customDetails != null &&
                      lastItem.customDetails!.trim().isNotEmpty);
          if (!lastItem.product.isSoldByWeight && !isCalculatedOrFractional) {
            if (lastItem.quantity > 1) {
              posProvider.updateQuantity(lastItem, lastItem.quantity - 1);
            } else {
              posProvider.removeFromCart(lastItem);
            }
          }
          return true;
        }
      }

      // Delete → Eliminar último ítem
      if (event.logicalKey == LogicalKeyboardKey.delete) {
        if (posProvider.cart.isNotEmpty) {
          posProvider.removeFromCart(posProvider.cart.last);
        }
        return true;
      }
    }

    return false;
  }

  Future<void> _openQuickItemDialog({String? initialQuery}) async {
    _hideSearchHistoryPopover();
    final posProvider = Provider.of<PosProvider>(context, listen: false);
    final result = await PosQuickItemDialog.show(
      context,
      activeTier: posProvider.activeTier,
      wholesaleFactor: posProvider.wholesaleFactor,
      cardFactor: posProvider.cardFactor,
      customFactor: posProvider.currentCustomFactor,
      customTierLabel: posProvider.customTierLabel,
      initialQuery: initialQuery,
    );
    if (!mounted) return;
    if (result != null) {
      for (final oldItem in result.replacedCartItems) {
        posProvider.removeFromCart(oldItem);
      }
      final newItem = result.item;
      posProvider.addQuickOrTemporaryItem(newItem);
      SnackBarService.success(
        context,
        newItem.saveToCatalog
            ? '🆕 "${newItem.effectiveDisplayName}" agregado (se guardará en el catálogo al cobrar).'
            : (result.replacedCartItems.isNotEmpty
                ? '📦 "${newItem.effectiveDisplayName}" armado con ${result.replacedCartItems.length} ítem(s) del carrito.'
                : '⚡ "${newItem.effectiveDisplayName}" agregado como ítem temporal.'),
      );
    }
    _requestSearchFocusSilently();
  }

  Future<void> _openPriceLookupDialog() async {
    _hideSearchHistoryPopover();
    String? followUpQuickCreateQuery;
    String? followUpAssociateBarcode;
    Product? followUpHardwareCalcProduct;
    final selectedProduct = await PosPriceLookupDialog.show(
      context,
      onQuickCreateRequested: (q) => followUpQuickCreateQuery = q,
      onAssociateBarcodeRequested: (code) => followUpAssociateBarcode = code,
      onHardwareCalculatorRequested: (p) => followUpHardwareCalcProduct = p,
    );
    if (!mounted) return;
    if (followUpQuickCreateQuery != null) {
      await _openQuickItemDialog(initialQuery: followUpQuickCreateQuery);
      return;
    }
    if (followUpAssociateBarcode != null) {
      await _showUnrecognizedBarcodeDialog(followUpAssociateBarcode!);
      return;
    }
    if (followUpHardwareCalcProduct != null) {
      await _openHardwareCalculatorDialog(
        initialProduct: followUpHardwareCalcProduct,
      );
      return;
    }
    if (selectedProduct != null) {
      _handleProductSelection(selectedProduct);
    }
    _requestSearchFocusSilently();
  }

  Future<void> _openHardwareCalculatorDialog({
    Product? initialProduct,
    CartItem? replacingCartItem,
  }) async {
    _hideSearchHistoryPopover();
    if (initialProduct != null &&
        initialProduct.active &&
        _searchQuery.trim().isNotEmpty) {
      _recordRecentSearchIfValid(
        _searchQuery,
        selectedProduct: initialProduct,
      );
    }
    final settingsProv = Provider.of<SettingsProvider>(context, listen: false);
    final rubros = Provider.of<CatalogProvider?>(context, listen: false)?.safeRubros ??
        const [];
    if (!settingsProv.canUseHardwareCalculatorFor(
      product: initialProduct,
      rubros: rubros,
    )) {
      return;
    }

    final out = await PosHardwareCalculatorDialog.show(
      context,
      initialProduct: initialProduct,
      replacingCartItem: replacingCartItem,
      target: HardwareCalculatorTarget.pos,
    );
    if (!mounted) return;
    if (out?.createdQuote != null) {
      final quote = out!.createdQuote!;
      final settings = settingsProv.settings;
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final vendorName = auth.currentUser?['name']?.toString() ?? 'Vendedor';
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => QuoteSuccessDialog(
          quote: quote,
          businessName: settings?.companyName ?? 'Mi Negocio',
          businessAddress: settings?.address,
          businessPhone: settings?.phone,
          customerPhone: quote.customerPhone,
          vendorName: vendorName,
        ),
      );
      if (!mounted) return;
    }
    if (out != null &&
        out.searchComplementKeyword != null &&
        out.searchComplementKeyword!.trim().isNotEmpty) {
      final kw = out.searchComplementKeyword!.trim();
      _searchController.text = kw;
      _searchController.selection = TextSelection.collapsed(offset: kw.length);
      _onPosSearchChanged(kw);
    }
    _requestSearchFocusSilently();
  }

  Future<void> _openRenameCartItemDialog(
    CartItem item, {
    bool focusQuantityInitially = false,
  }) async {
    final posProvider = Provider.of<PosProvider>(context, listen: false);
    final catalogProvider = Provider.of<CatalogProvider>(context, listen: false);
    var followUpOpenHardwareCalc = false;
    final res = await PosRenameCartItemDialog.show(
      context,
      item: item,
      focusQuantityInitially: focusQuantityInitially,
      onOpenHardwareCalculator: () {
        followUpOpenHardwareCalc = true;
      },
    );
    if (!mounted) return;
    if (followUpOpenHardwareCalc) {
      await _openHardwareCalculatorDialog(
        initialProduct: item.product,
        replacingCartItem: item,
      );
      return;
    }
    if (res == null) {
      _requestSearchFocusSilently();
      return;
    }

    final isCatalogItem =
        !item.isTemporary && !item.saveToCatalog && item.product.id > 0;
    final hasShelfStockChange = isCatalogItem &&
        res.shelfStockChanged &&
        res.newShelfStockBeforeSale != null;

    final baseProd = catalogProvider.products
            .where((p) => p.id == item.product.id)
            .firstOrNull ??
        item.product;
    final effectiveQty = res.newQuantity ?? item.quantity;
    final simulatedProd = hasShelfStockChange
        ? baseProd.copyWith(stock: res.newShelfStockBeforeSale!)
        : baseProd;
    final unitBlockMsg = posProvider.validateUnitStockConstraint(
      simulatedProd,
      effectiveQty,
      excludingItem: item,
      catalogProducts: hasShelfStockChange ? null : catalogProvider.products,
    );
    if (unitBlockMsg != null) {
      SnackBarService.error(context, unitBlockMsg);
      _requestSearchFocusSilently();
      return;
    }

    final needsDbUpdate = isCatalogItem &&
        (res.updateCatalogName ||
            (res.updateCatalogInDb &&
                (res.sellingPriceChanged || res.costPriceChanged)) ||
            res.updateIvaInDb ||
            res.barcodeChanged);

    // Si hay una rebaja temporal para esta venta (sin guardar el precio en BD), validar apply_discounts
    final hasTemporaryDiscountForThisSale = isCatalogItem &&
        !res.updateCatalogInDb &&
        res.newUnitPrice != null &&
        res.newUnitPrice! < (item.defaultCalculatedUnitPrice - 0.01);

    if (hasTemporaryDiscountForThisSale) {
      final pinResult = await AdminPinDialog.verifyAndGetPin(
        context,
        action: 'Autorizar rebaja de precio en "${item.product.name}"',
        permissionKey: AppPermissions.applyDiscounts,
      );
      if (!mounted) return;
      if (pinResult == null) {
        _requestSearchFocusSilently();
        return;
      }
      if (pinResult != 'ALREADY_AUTHORIZED') {
        posProvider.setAuthorizedDiscountPin(pinResult);
      }
    }

    // Impacto permanente en Base de Datos (Nombre/Precio/Costo/IVA y/o Código de Barras)
    Product? updatedProduct;
    if (needsDbUpdate) {
      final authorized = await AdminPinDialog.protectAction(
        context,
        action: res.barcodeChanged &&
                !res.updateCatalogInDb &&
                !res.updateCatalogName &&
                !res.updateIvaInDb
            ? 'Asociar Código de Barras en Catálogo (${item.product.name})'
            : 'Actualizar Producto en Catálogo (${item.product.name})',
        permissionKey: AppPermissions.manageCatalog,
        onAuthorized: () async {
          updatedProduct = await catalogProvider.updateProductPriceFromPos(
            item.product.id,
            name: res.updateCatalogName ? res.customDescription : null,
            sellingPrice: (res.updateCatalogInDb && res.sellingPriceChanged)
                ? res.newUnitPrice
                : null,
            costPrice: (res.updateCatalogInDb && res.costPriceChanged)
                ? res.newCostPrice
                : null,
            ivaRate: res.updateIvaInDb ? res.newIvaRate : null,
            barcode: res.barcodeChanged ? res.newBarcode : null,
          );
        },
      );

      if (!mounted) return;

      if (!authorized) {
        _requestSearchFocusSilently();
        return;
      }

      if (updatedProduct == null) {
        SnackBarService.error(
          context,
          catalogProvider.errorMessage ??
              'No se pudo actualizar el producto en la Base de Datos.',
        );
        _requestSearchFocusSilently();
        return;
      }
    }

    // Ajuste físico de stock en góndola (antes de cobrar esta venta)
    bool shelfStockAdjustedOk = false;
    if (hasShelfStockChange) {
      final baseStockForDelta = updatedProduct?.stock ?? baseProd.stock;
      final delta = res.newShelfStockBeforeSale! - baseStockForDelta;
      if (delta.abs() >= 0.0005) {
        bool ok = false;
        final authorized = await AdminPinDialog.protectAction(
          context,
          action: 'Ajustar stock físico en góndola (${item.product.name})',
          permissionKey: AppPermissions.adjustStock,
          onAuthorized: () async {
            ok = await catalogProvider.adjustStock(
              productId: item.product.id,
              type: delta > 0 ? 'increment' : 'decrement',
              quantity: delta.abs(),
              notes: 'Ajuste rápido en caja POS (antes de venta)',
            );
          },
        );
        if (!mounted) return;
        if (!authorized) {
          _requestSearchFocusSilently();
          return;
        }
        if (!ok) {
          SnackBarService.error(
            context,
            catalogProvider.errorMessage ??
                'No se pudo ajustar el stock en la Base de Datos.',
          );
          _requestSearchFocusSilently();
          return;
        }
        shelfStockAdjustedOk = true;
        final refreshedFromCat =
            catalogProvider.lastUpdatedProduct?.id == item.product.id
                ? catalogProvider.lastUpdatedProduct!
                : catalogProvider.products
                    .where((p) => p.id == item.product.id)
                    .firstOrNull;
        updatedProduct = refreshedFromCat ??
            (updatedProduct ?? baseProd)
                .copyWith(stock: res.newShelfStockBeforeSale!);
      }
    }

    // Actualizar también en resultados de búsqueda activos y Ofertas si existieran
    if (updatedProduct != null) {
      if (_searchResults.isNotEmpty) {
        final updatedSearch = catalogProvider.applyStockUpdatesToProductList(
          _searchResults,
          {updatedProduct!.id: updatedProduct!.stock},
        );
        final idx = updatedSearch.indexWhere((p) => p.id == updatedProduct!.id);
        final copy = List<Product>.from(updatedSearch);
        if (idx != -1) {
          copy[idx] = updatedProduct!;
        }
        setState(() {
          _searchResults = copy;
        });
      }
      if (shelfStockAdjustedOk) {
        try {
          final offerProv = Provider.of<OfferProvider>(context, listen: false);
          if (offerProv.offerOnlyProducts.isNotEmpty) {
            final updatedOffers = catalogProvider.applyStockUpdatesToProductList(
              offerProv.offerOnlyProducts,
              {updatedProduct!.id: updatedProduct!.stock},
            );
            if (!identical(updatedOffers, offerProv.offerOnlyProducts)) {
              offerProv.replaceOfferOnlyProducts(updatedOffers);
            }
          }
        } catch (_) {}
      }
    }

    posProvider.updateCartItemCustomDescription(
      item,
      customDescription: res.customDescription,
      customDetails: res.customDetails,
      newUnitPrice: (res.updateCatalogInDb && res.sellingPriceChanged)
          ? null
          : res.newUnitPrice,
      clearManualUnitPrice: res.clearManualUnitPrice,
      newCostPrice: (res.updateCatalogInDb && res.costPriceChanged)
          ? null
          : res.newCostPrice,
      clearManualCostPrice: res.clearManualCostPrice,
      newManualSubtotal: res.newManualSubtotal,
      clearManualSubtotal: res.clearManualSubtotal,
      newQuantity: res.newQuantity,
      newIvaRate: isCatalogItem ? null : res.newIvaRate,
      updatedCatalogProduct: updatedProduct,
    );

    if (shelfStockAdjustedOk) {
      // Sincronizar la campanita de alertas y el estado backend del indicador del carrito
      try {
        Provider.of<InventoryAlertsProvider>(context, listen: false)
            .fetchAlerts();
      } catch (_) {}
    }

    if (updatedProduct != null) {
      final msg = shelfStockAdjustedOk && !needsDbUpdate
          ? '📦 Stock en góndola actualizado en BD a ${updatedProduct!.stock.toUnitStockDisplay(isSoldByWeight: updatedProduct!.isSoldByWeight, unitSuffix: 'u')} para "${updatedProduct!.name}".'
          : (res.barcodeChanged &&
                  !res.updateCatalogInDb &&
                  !res.updateCatalogName &&
                  !res.updateIvaInDb &&
                  !shelfStockAdjustedOk
              ? '🔫 Código de barras (${res.newBarcode}) asociado en la Base de Datos a "${updatedProduct!.name}".'
              : '💾 Cambios guardados en la Base de Datos para "${updatedProduct!.name}".');
      SnackBarService.success(context, msg);
    }
    _requestSearchFocusSilently();
  }

  /// Punto 2B: Cuando se escanea un código de barras desconocido en el mostrador,
  /// permite asociarlo en 1 clic al último producto del carrito o buscar el producto por nombre.
  Future<void> _showUnrecognizedBarcodeDialog(String scannedBarcode) async {
    final posProvider = Provider.of<PosProvider>(context, listen: false);
    final catalogProvider =
        Provider.of<CatalogProvider>(context, listen: false);

    CartItem? lastCatalogCartItem;
    for (final it in posProvider.cart.reversed) {
      if (!it.isTemporary &&
          !it.saveToCatalog &&
          it.product.id > 0 &&
          !it.product.isCombo) {
        lastCatalogCartItem = it;
        break;
      }
    }

    Future<void> assignBarcodeToProduct(
      BuildContext dialogCtx,
      Product targetProduct, {
      required bool addToCartAfter,
    }) async {
      Product? updatedProduct;
      final authorized = await AdminPinDialog.protectAction(
        context,
        action:
            'Asociar código $scannedBarcode a "${targetProduct.name}" en Catálogo',
        permissionKey: AppPermissions.manageCatalog,
        onAuthorized: () async {
          updatedProduct = await catalogProvider.updateProductPriceFromPos(
            targetProduct.id,
            barcode: scannedBarcode,
          );
        },
      );

      if (!mounted) return;
      if (!authorized) return;

      if (updatedProduct == null) {
        SnackBarService.error(
          context,
          catalogProvider.errorMessage ??
              'No se pudo asociar el código de barras.',
        );
        return;
      }

      if (dialogCtx.mounted) {
        Navigator.of(dialogCtx).pop();
      }

      // Sincronizar en carrito si ya estaba presente
      for (final cartIt in posProvider.cart) {
        if (cartIt.product.id == updatedProduct!.id) {
          posProvider.updateCartItemCustomDescription(
            cartIt,
            customDescription: cartIt.customDescription,
            customDetails: cartIt.customDetails,
            newUnitPrice: cartIt.manualUnitPrice,
            newCostPrice: cartIt.manualCostPrice,
            newManualSubtotal: cartIt.manualSubtotal,
            updatedCatalogProduct: updatedProduct,
          );
          break;
        }
      }

      if (addToCartAfter) {
        _handleProductSelection(updatedProduct!);
      }

      SnackBarService.success(
        context,
        '🔫 Código $scannedBarcode asociado a "${updatedProduct!.name}" en la Base de Datos.',
      );
    }

    final action = await showDialog<String>(
      context: context,
      builder: (_) => _UnrecognizedBarcodeDialog(
        scannedBarcode: scannedBarcode,
        lastCatalogCartItem: lastCatalogCartItem,
        onSearchCatalog: (q) => posProvider.search(q),
        onAssignBarcode: assignBarcodeToProduct,
      ),
    );

    if (action == 'quick_create' && mounted) {
      await _openQuickItemDialog(initialQuery: scannedBarcode);
    }
  }

  Widget _buildSearchHistoryOverlay(
    BuildContext overlayContext,
    OverlayChildLayoutInfo info,
  ) {
    return PosSearchHistoryPopover.buildAnchoredOverlay(
      info: info,
      maxWidth: 580.0,
      maxOverlayHeight: 380.0,
      child: Consumer3<CatalogProvider, PosProvider, OfferProvider>(
        builder: (ctx, catalog, pos, offerProv, _) {
          final localTerminal = tryGetLocalTerminalProvider(ctx, listen: true);
          final terms = localTerminal?.recentTermsForScope(
                LocalTerminalProvider.scopePosCounter,
              ) ??
              const <String>[];
          final recentProducts =
              _resolveActiveRecentProducts(catalog, localTerminal);

          if (localTerminal == null ||
              (terms.isEmpty && recentProducts.isEmpty)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _hideSearchHistoryPopover();
            });
            return const SizedBox.shrink();
          }

          return PosSearchHistoryPopover(
            containerKey: const ValueKey('pos_search_history_overlay'),
            terms: terms,
            products: recentProducts,
            highlightedIndex: _searchHistoryHighlightIndex,
            tapGroupId: _searchHistoryTapGroupId,
            maxWidth: 580.0,
            onDismiss: _hideSearchHistoryPopover,
            onClearAll: () {
              unawaited(localTerminal.clearRecentSearchesForScope(
                LocalTerminalProvider.scopePosCounter,
              ));
              _hideSearchHistoryPopover();
              _requestSearchFocusSilently();
            },
            onSelectTerm: _applyRecentSearchTerm,
            onRemoveTerm: (term) {
              final willBeEmpty = terms.length <= 1 && recentProducts.isEmpty;
              unawaited(localTerminal.removeRecentTermForScope(
                LocalTerminalProvider.scopePosCounter,
                term,
              ));
              if (willBeEmpty) {
                _hideSearchHistoryPopover();
              } else if (_searchHistoryHighlightIndex != -1) {
                setState(() => _searchHistoryHighlightIndex = -1);
              }
            },
            onSelectProduct: (p) {
              _hideSearchHistoryPopover();
              _recordRecentSearchIfValid(
                null,
                selectedProductId: p.id,
                selectedProduct: p,
              );
              _handleProductSelection(p);
            },
            onRemoveProduct: (productId) {
              final willBeEmpty =
                  recentProducts.length <= 1 && terms.isEmpty;
              unawaited(localTerminal.removeRecentProductIdForScope(
                LocalTerminalProvider.scopePosCounter,
                productId,
              ));
              if (willBeEmpty) {
                _hideSearchHistoryPopover();
              } else if (_searchHistoryHighlightIndex != -1) {
                setState(() => _searchHistoryHighlightIndex = -1);
              }
            },
            priceResolver: (p) {
              final promoPrice = offerProv.getDiscountedPrice(p);
              final hasOffer = promoPrice != null &&
                  promoPrice > 0 &&
                  promoPrice < p.sellingPrice;
              final calc = ProductPricingCalculator.calculate(
                product: p,
                activeTier: pos.activeTier,
                wholesaleFactor: pos.wholesaleFactor,
                cardFactor: pos.cardFactor,
                customFactor: pos.currentCustomFactor,
                promotionalPrice: promoPrice,
                hasExplicitOffer: hasOffer,
                cardSurchargeOnOffersMode: pos.cardSurchargeOnOffersMode,
                discountTierOnOffersMode: pos.discountTierOnOffersMode,
                ignoreFixedPrices: pos.ignoreProductFixedPrices,
              );
              return (
                price: calc.finalUnitPrice,
                crossedOutPrice: calc.crossedOutPrice,
                hasActiveOffer: calc.hasActiveOffer,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildRightPanel() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 580;
        final rightPanelProfile =
            context.watch<SettingsProvider?>()?.safeVerticalProfile ??
                BusinessVerticalProfile.fromType(BusinessVerticalProfile.retail);
        final panelRubros =
            Provider.of<CatalogProvider?>(context, listen: true)?.safeRubros ??
                const [];
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Barra de búsqueda con búsqueda server-side vía API + Popover historial + Botón Ítem/Combo Rápido (F3)
              Row(
                children: [
                  Expanded(
                    child: TapRegion(
                      groupId: _searchHistoryTapGroupId,
                      child: OverlayPortal.overlayChildLayoutBuilder(
                        controller: _searchHistoryPortalController,
                        overlayChildBuilder: _buildSearchHistoryOverlay,
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onTap: () {
                            if (_searchController.text.trim().isEmpty) {
                              _showSearchHistoryPopoverIfAvailable();
                            }
                          },
                          inputFormatters: [
                            FilteringTextInputFormatter.deny(
                              RegExp(r'[\x00-\x1F\u263A\u263B\u2665\u2666\u2663\u2660\u2022\u25D8\u25CB]'),
                            ),
                            TextInputFormatter.withFunction((oldValue, newValue) {
                              if (oldValue.text.isEmpty &&
                                  (newValue.text == '+' || newValue.text == '-')) {
                                final hasCart =
                                    Provider.of<PosProvider>(context, listen: false)
                                        .cart
                                        .isNotEmpty;
                                if (hasCart) return oldValue;
                              }
                              return newValue;
                            }),
                          ],
                          decoration: InputDecoration(
                            hintText: isCompact
                                ? 'Buscar o escanear código... (Enter: Cobrar)'
                                : 'Escribir nombre o escanear código... (Enter: Cobrar · F3: Ítem Rápido · F1: Atajos)',
                            prefixIcon: _isSearching
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2)),
                                  )
                                : const Icon(Icons.search),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    tooltip: 'Limpiar filtro',
                                    onPressed: _clearActiveSearchFilter,
                                  )
                                : Consumer<CatalogProvider>(
                                    builder: (ctx, catalog, _) {
                                      final localTerminal =
                                          tryGetLocalTerminalProvider(ctx,
                                              listen: true);
                                      if (!_hasSearchHistoryEntries(
                                          catalog, localTerminal)) {
                                        return const SizedBox.shrink();
                                      }
                                      return Focus(
                                        canRequestFocus: false,
                                        descendantsAreFocusable: false,
                                        child: Tooltip(
                                          message: 'Búsquedas recientes',
                                          child: IconButton(
                                            key: const ValueKey(
                                                'pos_search_history_toggle_btn'),
                                            icon: Icon(
                                              Icons.history_rounded,
                                              size: 20,
                                              color:
                                                  _searchHistoryPortalController
                                                          .isShowing
                                                      ? const Color(0xFF0F766E)
                                                      : Colors.blueGrey.shade600,
                                            ),
                                            onPressed: () {
                                              if (_searchHistoryPortalController
                                                  .isShowing) {
                                                _hideSearchHistoryPopover();
                                              } else {
                                                _showSearchHistoryPopoverIfAvailable();
                                              }
                                              _requestSearchFocusSilently();
                                            },
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                            border:
                                OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            filled: true,
                            fillColor: Colors.grey.shade100,
                          ),
                          // Búsqueda en tiempo real con debounce → API completa
                          onChanged: _onPosSearchChanged,
                          // Enter: para códigos de barras (API call + agregar al carrito)
                          onSubmitted: _onProductScannedOrSearched,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (context
                      .watch<SettingsProvider>()
                      .canUseHardwareCalculatorFor(rubros: panelRubros)) ...[
                    Tooltip(
                      message:
                          'Calculadora Rápida Ferretera: Machimbre, Chapas y Pintura (F7)',
                      child: ElevatedButton.icon(
                        onPressed: () => _openHardwareCalculatorDialog(),
                        icon: const Icon(Icons.straighten_rounded, size: 18),
                        label: Text(
                          isCompact ? 'Calc (F7)' : 'Calculadora (F7)',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 12.5),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F766E),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: EdgeInsets.symmetric(
                            horizontal: isCompact ? 10 : 14,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Tooltip(
                    message: 'Crear Producto o Combo Rápido en mostrador (F3)',
                    child: ElevatedButton.icon(
                      onPressed: _openQuickItemDialog,
                      icon: const Icon(Icons.flash_on_rounded, size: 18),
                      label: Text(
                        isCompact ? 'Rápido (F3)' : 'Ítem / Combo Rápido (F3)',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade700,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompact ? 12 : 16,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ── Header dinámico ────────────────────────────────────────────
              if (_searchQuery.isEmpty) ...[
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Acceso Rápido',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(
                            'Fijados · Más vendidos · ${rightPanelProfile.posQuickAccessSubtitle} · Orden alfabético',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Tooltip(
                      message: 'Guía rápida de atajos de teclado',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _showKeyboardShortcutsHelpDialog,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: isCompact ? 8 : 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.shade50,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.blueGrey.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.keyboard_rounded,
                                  size: 15, color: Colors.blueGrey.shade700),
                              const SizedBox(width: 4),
                              Text(
                                isCompact ? 'F1' : 'Atajos (F1)',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.blueGrey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Consumer<CatalogProvider>(
                      builder: (context, catalog, child) {
                        if (catalog.isLoading) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16.0),
                            child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2)),
                          );
                        }
                        return IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.grey),
                          tooltip: 'Actualizar catálogo y ofertas',
                          onPressed: () {
                            final catProv = context.read<CatalogProvider>();
                            catProv.invalidateQuickAccessExtraCaches();
                            catProv.loadMetadata(force: true);
                            catProv.loadProducts(page: 1, search: '', sortBy: '', perPage: 500);
                            final offerProv = context.read<OfferProvider>();
                            final posProv = context.read<PosProvider>();
                            offerProv.invalidateOfferOnlyProducts(); // OF-01: refrescar stock de ofertas fuera del catálogo
                            offerProv.loadActiveOffers().then((_) {
                              if (mounted) {
                                posProv.syncActiveOffers(offerProv.activeOffers);
                              }
                            });
                          },
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildViewModeSelector(context),
                  ],
                ),
                const SizedBox(height: 8),
                _buildQuickAccessFilterBar(context, constraints.maxWidth),
              ] else ...[
                Row(
                  children: [
                    const Icon(Icons.filter_list_rounded, color: Colors.blueAccent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Resultados para "${_searchController.text}"',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueAccent),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton.icon(
                      key: const ValueKey('pos_clear_search_filter_btn'),
                      onPressed: _clearActiveSearchFilter,
                      icon: const Icon(Icons.filter_alt_off_rounded, size: 17),
                      label: const Text('Limpiar filtro'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: Colors.blueGrey.shade700,
                      ),
                    ),
                  ],
                ),
              ],
          const SizedBox(height: 12),

          // ── Grilla dinámica ────────────────────────────────────────────
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Consumer<CatalogProvider>(
                  builder: (context, catalog, _) {
                    if (catalog.isLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final offerProv = context.watch<OfferProvider>();
                    final localTerminal = context.watch<LocalTerminalProvider>();
                    final displayItems = _getFilteredProducts(catalog, offerProv, localTerminal);

                    if (displayItems.isEmpty && _isQuickAccessFilterHydrating(catalog, localTerminal)) {
                      // Carga única del catálogo completo del filtro (luego queda en caché).
                      return const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      );
                    }

                    if (displayItems.isEmpty) {
                      if (_searchQuery.isEmpty && _quickAccessFilter != 'all' && catalog.activeProducts.isNotEmpty) {
                        // Filtro activo devuelve 0 ítems pero el catálogo tiene productos
                        String emptyMessage = '';
                        String filterName = 'este filtro';
                        if (_quickAccessFilter == 'pinned') {
                          filterName = 'productos fijados';
                        } else if (_quickAccessFilter == 'top_sellers') {
                          filterName = 'más vendidos';
                        } else if (_quickAccessFilter == 'offers') {
                          filterName = 'ofertas activas';
                        } else if (_quickAccessFilter == 'weight') {
                          emptyMessage =
                              rightPanelProfile.posEmptyFractionalFilterLabel;
                        } else if (_quickAccessFilter.startsWith('cat_')) {
                          filterName = 'esta categoría';
                        }

                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.filter_list_off,
                                  size: 56, color: Colors.grey),
                              const SizedBox(height: 12),
                              Text(
                                emptyMessage.isNotEmpty
                                    ? emptyMessage
                                    : 'No hay productos para $filterName',
                                style: const TextStyle(color: Colors.grey, fontSize: 15),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                icon: const Icon(Icons.clear_all),
                                label: const Text('Ver todos los productos'),
                                onPressed: () {
                                  setState(() {
                                    _quickAccessFilter = 'all';
                                  });
                                },
                              ),
                            ],
                          ),
                        );
                      }

                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.search_off,
                                size: 56, color: Colors.grey),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'No hay productos en el catálogo.'
                                  : 'No se encontraron productos para "${_searchController.text}"',
                              style:
                                  const TextStyle(color: Colors.grey, fontSize: 15),
                              textAlign: TextAlign.center,
                            ),
                            if (_searchQuery.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              const Text(
                                'Presioná Enter para buscar por código o limpiá el filtro',
                                style: TextStyle(
                                    color: Colors.blueGrey, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                key: const ValueKey('pos_empty_clear_search_filter_btn'),
                                icon: const Icon(Icons.filter_alt_off_rounded),
                                label: const Text('Limpiar filtro'),
                                onPressed: _clearActiveSearchFilter,
                              ),
                            ],
                          ],
                        ),
                      );
                    }

                    final viewMode =
                        context.watch<LocalTerminalProvider>().catalogViewMode;
                    return _buildDynamicCatalogView(displayItems, viewMode);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
      },
    );
  }

  // Fallback Helper para imprimir el ticket normal si falla el A4 Split
  Future<void> _showFallbackA4Pdf(PosProvider posProvider) async {
    try {
      final pdfBytes = await posProvider.repository
          .downloadTicketPdf(posProvider.lastSaleId);
      if (!mounted) return;
      var paperSize = 'a4';
      try {
        paperSize = context.read<LocalTerminalProvider>().pdfPaperSize;
      } catch (_) {}
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) {
          bool isVoiding = false;
          return StatefulBuilder(
            builder: (context, setState) {
              return AppPdfPreviewModal(
                title: 'Vista Previa Backoffice - Venta #${posProvider.lastSaleId}',
                subtitle:
                    'Comprobante respaldado • Hoja ${pdfPaperSizeLabel(paperSize)}',
                icon: Icons.picture_as_pdf_rounded,
                accent: AppModalAccent.blue,
                pdfFileName: 'Comprobante_${posProvider.lastSaleId}.pdf',
                initialPageFormat: pdfPageFormatFromPaperSize(paperSize),
                build: (format) async => pdfBytes,
                canClose: !isVoiding,
                onClose: isVoiding ? null : () => Navigator.pop(dialogCtx),
                headerTrailing: isVoiding
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.dangerLight,
                          ),
                        ),
                      )
                    : OutlinedButton.icon(
                        onPressed: () async {
                          final confirm = await AppConfirmDialog.show(
                            dialogCtx,
                            title: '¿Anular Venta?',
                            message:
                                'Esta acción cancelará el cobro en el sistema y devolverá los productos al carrito.',
                            confirmLabel: 'SÍ, ANULAR',
                            cancelLabel: 'NO, VOLVER',
                            icon: Icons.cancel_outlined,
                            isDestructive: true,
                          );

                          if (confirm == true) {
                            final currentShift = context
                                .read<CashRegisterProvider>()
                                .currentShift;
                            if (currentShift == null) {
                              if (dialogCtx.mounted) {
                                SnackBarService.error(
                                  dialogCtx,
                                  'Debe haber un turno de caja abierto para anular órdenes.',
                                );
                              }
                              return;
                            }
                            if (posProvider.lastSaleId <= 0) {
                              if (dialogCtx.mounted) {
                                SnackBarService.error(
                                  dialogCtx,
                                  'No hay ID de venta válido para anular.',
                                );
                              }
                              return;
                            }
                            setState(() {
                              isVoiding = true;
                            });

                            final hasPermission =
                                await AdminPinDialog.protectAction(
                              dialogCtx,
                              action: 'Anulación de Ventas Emitidas',
                              permissionKey: AppPermissions.voidSales,
                              onAuthorized: () async {
                                try {
                                  final success =
                                      await posProvider.voidPendingOrder(
                                    posProvider.lastSaleId,
                                    shiftId: currentShift.id,
                                  );
                                  if (!success) {
                                    if (dialogCtx.mounted) {
                                      SnackBarService.error(
                                        dialogCtx,
                                        'No se pudo anular la venta: ${posProvider.errorMessage ?? "Error desconocido"}',
                                      );
                                    }
                                    setState(() {
                                      isVoiding = false;
                                    });
                                    return;
                                  }
                                  // Restaurar carrito al estado previo a la venta
                                  posProvider.restoreLastSaleCart();

                                  if (dialogCtx.mounted) {
                                    SnackBarService.warning(
                                      dialogCtx,
                                      'Venta anulada. Los productos han vuelto al carrito.',
                                    );
                                    Navigator.pop(dialogCtx, 'annulled');
                                  }
                                } catch (e) {
                                  if (dialogCtx.mounted) {
                                    SnackBarService.error(
                                      dialogCtx,
                                      'Error al anular: $e',
                                    );
                                    setState(() {
                                      isVoiding = false;
                                    });
                                  }
                                }
                              },
                            );

                            if (!hasPermission) {
                              setState(() {
                                isVoiding = false;
                              });
                            }
                          }
                        },
                        icon: const Icon(
                          Icons.delete_forever_rounded,
                          size: 17,
                        ),
                        label: const Text('ANULAR COBRO Y VOLVER'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFFCA5A5),
                          backgroundColor:
                              AppColors.danger.withValues(alpha: 0.22),
                          side: BorderSide(
                            color:
                                AppColors.dangerLight.withValues(alpha: 0.55),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
              );
            },
          );
        },
      );
    } catch (e) {
      debugPrint('Fallback PDF Error: $e');
    }
  }
// ─── VIEW MODES IMPLEMENTATION ───
  Widget _buildViewModeSelector(BuildContext context) {
    final viewMode = context.watch<LocalTerminalProvider>().catalogViewMode;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildViewModeButton(context, 'grid_large', Icons.grid_view_rounded, 'Tarjetas Grandes', viewMode),
          _buildViewModeButton(context, 'grid_medium', Icons.apps_rounded, 'Tarjetas Medianas', viewMode),
          _buildViewModeButton(context, 'compact', Icons.view_comfy_rounded, 'Botones Compactos', viewMode),
          _buildViewModeButton(context, 'list', Icons.view_list_rounded, 'Lista', viewMode),
        ],
      ),
    );
  }

  Widget _buildViewModeButton(BuildContext context, String mode, IconData icon, String tooltip, String currentMode) {
    final isSelected = mode == currentMode;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          context.read<LocalTerminalProvider>().setCatalogViewMode(mode);
          _requestSearchFocusSilently();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue.withAlpha(25) : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: isSelected ? Colors.blueAccent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isSelected ? Colors.blueAccent : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAccessFilterBar(BuildContext context, [double panelWidth = 800]) {
    final localTerminal = context.watch<LocalTerminalProvider>();
    final catalog = context.watch<CatalogProvider>();
    final offerProv = context.watch<OfferProvider>();
    BusinessVerticalProfile quickProfile =
        BusinessVerticalProfile.fromType(BusinessVerticalProfile.retail);
    try {
      quickProfile =
          context.watch<SettingsProvider?>()?.safeVerticalProfile ??
              quickProfile;
    } catch (_) {}
    final supportsWeightFilter =
        quickProfile.canUseFractionalCut || quickProfile.canUseScaleWeight;

    final activeCatalogProducts = catalog.activeProducts;
    final hasPinned = localTerminal.pinnedProductIds.any(
      (id) => !catalog.products.any((p) => p.id == id && !p.active),
    );
    final hasTopSellers = activeCatalogProducts.any((p) => p.salesCount > 0);
    // OF-01: considerar también los productos en oferta fuera del bloque inicial del catálogo
    _scheduleOfferOnlyProductsSync(catalog, offerProv);
    final hasOffers = _offerCandidateProducts(catalog, offerProv)
        .any((p) => offerProv.getActiveOfferForProduct(p.id, basePrice: p.sellingPrice) != null);

    final hasWeight = activeCatalogProducts.any((p) => p.isSoldByWeight) || catalog.weightOnlyProducts.isNotEmpty;

    final localCounts = <String, int>{};
    for (final p in activeCatalogProducts) {
      final catName = p.category?.name.trim();
      if (catName != null && catName.isNotEmpty) {
        localCounts[catName] = (localCounts[catName] ?? 0) + 1;
      }
    }

    final categories = <String, int>{};
    if (catalog.categories.isNotEmpty) {
      final catalogFullyInMemory = catalog.lastPage <= 1;
      for (final cat in catalog.categories) {
        final name = cat.name.trim();
        final serverCount = cat.productsCount ?? 0;
        final localCount = localCounts[name] ?? 0;
        final extraCount = catalog.getCategoryExtraProducts(cat.id).length;
        final totalCount = catalogFullyInMemory
            ? (localCount + extraCount)
            : (serverCount > (localCount + extraCount)
                ? serverCount
                : (localCount + extraCount));
        if (totalCount > 0) {
          categories[name] = totalCount;
        }
      }
    }
    for (final entry in localCounts.entries) {
      if (!categories.containsKey(entry.key) && entry.value > 0) {
        categories[entry.key] = entry.value;
      }
    }

    final selectedCatMissing = _quickAccessFilter.startsWith('cat_') &&
        !categories.keys.any(
          (k) => k.toLowerCase() == _quickAccessFilter.substring(4).trim().toLowerCase(),
        );

    // Si un filtro dinámico o categoría queda sin productos activos asociados, regresar automáticamente a 'all'
    if ((_quickAccessFilter == 'top_sellers' && !hasTopSellers) ||
        (_quickAccessFilter == 'pinned' && !hasPinned) ||
        (_quickAccessFilter == 'offers' && !hasOffers) ||
        (_quickAccessFilter == 'weight' &&
            (!supportsWeightFilter || !hasWeight)) ||
        selectedCatMissing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _quickAccessFilter = 'all';
          });
        }
      });
    }
    final allCategories = categories.entries.toList()
      ..sort((a, b) {
        final cmp = b.value.compareTo(a.value);
        return cmp != 0 ? cmp : a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });

    // Cálculo elástico del espacio horizontal real descontando chips fijos activos
    final innerWidth = (panelWidth - 32.0).clamp(300.0, 4000.0);
    final isCombinedWeightAndFrac =
        quickProfile.canUseScaleWeight && quickProfile.canUseFractionalCut;
    final weightChipLabel = isCombinedWeightAndFrac
        ? '⚖️ Peso / Fracc.'
        : (quickProfile.canUseFractionalCut
            ? '📏 Fraccionables'
            : '⚖️ Por Peso');
    final systemChipsWidth = 68.0 + // 'Todos'
        (hasPinned ? 102.0 : 0.0) +
        (hasTopSellers ? 130.0 : 0.0) +
        (hasOffers ? 100.0 : 0.0) +
        (supportsWeightFilter
            ? (isCombinedWeightAndFrac ? 126.0 : 105.0)
            : 0.0);

    final maxWithoutMore = ((innerWidth - systemChipsWidth) / 125.0).floor().clamp(1, 8);
    final int maxDirectCategories = allCategories.length <= maxWithoutMore
        ? allCategories.length
        : ((innerWidth - systemChipsWidth - 96.0) / 125.0).floor().clamp(1, 8);

    final activeCategory = _quickAccessFilter.startsWith('cat_')
        ? _quickAccessFilter.substring(4).trim()
        : null;

    MapEntry<String, int>? pinnedActiveEntry;
    final List<MapEntry<String, int>> visibleCategories = [];
    final List<MapEntry<String, int>> overflowCategories = [];

    if (activeCategory != null) {
      final activeIndex = allCategories.indexWhere((e) => e.key == activeCategory);
      if (activeIndex != -1) {
        // La categoría activa se ancla justo al lado de 'Todos' para jamás desaparecer al agrandar el carrito
        pinnedActiveEntry = allCategories[activeIndex];
        final others = allCategories.where((e) => e.key != activeCategory).toList();
        final remainingSlots = (maxDirectCategories - 1).clamp(0, others.length);
        visibleCategories.addAll(others.take(remainingSlots));
        overflowCategories.addAll(others.skip(remainingSlots));
      } else {
        visibleCategories.addAll(allCategories.take(maxDirectCategories));
        overflowCategories.addAll(allCategories.skip(maxDirectCategories));
      }
    } else {
      visibleCategories.addAll(allCategories.take(maxDirectCategories));
      overflowCategories.addAll(allCategories.skip(maxDirectCategories));
    }

    // Precarga silenciosa: pesables + categorías visibles, para que al tocarlas aparezcan
    // completas al instante (las del menú "Más" se cargan al elegirlas, con indicador breve).
    if (_searchQuery.isEmpty) {
      _scheduleWeightProductsSync(catalog);
      _schedulePrefetchVisibleCategories(
        catalog,
        visibleCategories.map((e) => e.key),
      );
    }

    return SizedBox(
      height: 36,
      child: Row(
        children: [
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                },
              ),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildFilterChip('Todos', 'all', _quickAccessFilter),
                  if (pinnedActiveEntry != null)
                    _buildCategoryChip(
                      pinnedActiveEntry.key,
                      pinnedActiveEntry.value,
                      isSelected: true,
                    ),
                  if (hasPinned)
                    _buildFilterChip('📌 Fijados', 'pinned', _quickAccessFilter),
                  if (hasTopSellers)
                    _buildFilterChip('🔥 Más Vendidos', 'top_sellers', _quickAccessFilter),
                  if (hasOffers)
                    _buildFilterChip('🏷️ Ofertas', 'offers', _quickAccessFilter),
                  if (supportsWeightFilter)
                    _buildFilterChip(
                      weightChipLabel,
                      'weight',
                      _quickAccessFilter,
                    ),
                  for (final catEntry in visibleCategories)
                    _buildCategoryChip(
                      catEntry.key,
                      catEntry.value,
                      isSelected: _quickAccessFilter == 'cat_${catEntry.key}',
                    ),
                ],
              ),
            ),
          ),
          if (overflowCategories.isNotEmpty) ...[
            const SizedBox(width: 4),
            _buildMoreCategoriesMenu(overflowCategories, activeCategory),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, String currentFilter) {
    final isSelected = value == currentFilter;
    final activeChipColor =
        value == 'offers' ? const Color(0xFFB45309) : Colors.blueAccent;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _quickAccessFilter = selected ? value : 'all';
          });
          _requestSearchFocusSilently();
        },
        selectedColor: activeChipColor.withAlpha(25),
        checkmarkColor: activeChipColor,
        labelStyle: TextStyle(
          color: isSelected ? activeChipColor : Colors.grey.shade700,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
        shape: StadiumBorder(
          side: BorderSide(
            color: isSelected ? activeChipColor : Colors.grey.shade300,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String catName, int count, {required bool isSelected}) {
    final color = PosQuickAccessCatalogView.resolveCategoryAccent(catName);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        avatar: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        showCheckmark: false,
        label: Text('$catName ($count)', style: const TextStyle(fontSize: 12)),
        selected: isSelected,
        deleteIcon: isSelected ? const Icon(Icons.close_rounded, size: 14) : null,
        onDeleted: isSelected
            ? () {
                setState(() {
                  _quickAccessFilter = 'all';
                });
                _requestSearchFocusSilently();
              }
            : null,
        onSelected: (selected) {
          setState(() {
            _quickAccessFilter = selected ? 'cat_$catName' : 'all';
          });
          _requestSearchFocusSilently();
        },
        selectedColor: color.withAlpha(35),
        checkmarkColor: color,
        labelStyle: TextStyle(
          color: isSelected ? color : Colors.grey.shade700,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        shape: StadiumBorder(
          side: BorderSide(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
      ),
    );
  }

  Widget _buildMoreCategoriesMenu(List<MapEntry<String, int>> overflowCategories, String? activeCategory) {
    final isAnyOverflowSelected = overflowCategories.any((e) => e.key == activeCategory);
    final useSearchDialog = overflowCategories.length > 12;

    final buttonContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isAnyOverflowSelected ? Colors.blue.withAlpha(25) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isAnyOverflowSelected ? Colors.blueAccent : Colors.grey.shade300,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            useSearchDialog ? Icons.search_rounded : Icons.category_outlined,
            size: 14,
            color: isAnyOverflowSelected ? Colors.blueAccent : Colors.grey.shade700,
          ),
          const SizedBox(width: 5),
          Text(
            'Más (${overflowCategories.length})',
            style: TextStyle(
              fontSize: 12,
              fontWeight: isAnyOverflowSelected ? FontWeight.bold : FontWeight.normal,
              color: isAnyOverflowSelected ? Colors.blueAccent : Colors.grey.shade700,
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            useSearchDialog ? Icons.open_in_new_rounded : Icons.arrow_drop_down,
            size: useSearchDialog ? 12 : 16,
            color: isAnyOverflowSelected ? Colors.blueAccent : Colors.grey.shade700,
          ),
        ],
      ),
    );

    if (useSearchDialog) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Tooltip(
          message: 'Buscar entre las ${overflowCategories.length} categorías',
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _showCategoriesSearchDialog(overflowCategories, activeCategory),
            child: buttonContent,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<String>(
        tooltip: 'Ver todas las categorías',
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.55,
          minWidth: 250,
          maxWidth: 320,
        ),
        onSelected: (cat) {
          setState(() {
            _quickAccessFilter = 'cat_$cat';
          });
          _requestSearchFocusSilently();
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: buttonContent,
        itemBuilder: (context) => overflowCategories.map((entry) {
          final catColor = PosQuickAccessCatalogView.resolveCategoryAccent(entry.key);
          final isCurrent = entry.key == activeCategory;
          return PopupMenuItem<String>(
            value: entry.key,
            height: 38,
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: catColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.key,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCurrent ? catColor : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${entry.value}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ),
                if (isCurrent) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.check, size: 16, color: catColor),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _showCategoriesSearchDialog(
    List<MapEntry<String, int>> categories,
    String? activeCategory,
  ) async {
    final searchCtrl = TextEditingController();

    final selectedCat = await showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final query = searchCtrl.text.trim().toLowerCase();
            final filtered = query.isEmpty
                ? categories
                : categories
                    .where((e) => e.key.toLowerCase().contains(query))
                    .toList();

            return AppModalShell(
              title: 'Todas las Categorías (${categories.length})',
              subtitle: 'Selecciona una categoría para filtrar el catálogo',
              icon: Icons.category_rounded,
              accent: AppModalAccent.blue,
              maxWidth: 580,
              maxHeight: 560,
              expandBody: true,
              onClose: () => Navigator.pop(dialogCtx),
              topBar: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: const BoxDecoration(
                  color: AppColors.surfaceMuted,
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: TextField(
                  controller: searchCtrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Buscar categoría por nombre...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            splashRadius: 16,
                            onPressed: () {
                              searchCtrl.clear();
                              setModalState(() {});
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.blueAccent,
                        width: 1.5,
                      ),
                    ),
                  ),
                  onChanged: (_) => setModalState(() {}),
                  onSubmitted: (_) {
                    if (filtered.isNotEmpty) {
                      Navigator.pop(dialogCtx, filtered.first.key);
                    }
                  },
                ),
              ),
              bodyPadding: const EdgeInsets.all(16),
              body: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No se encontró ninguna categoría con "$query"',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      itemCount: filtered.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisExtent: 44,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemBuilder: (context, index) {
                        final entry = filtered[index];
                        final isCurrent = entry.key == activeCategory;
                        final catColor =
                            PosQuickAccessCatalogView.resolveCategoryAccent(
                          entry.key,
                        );

                        return Material(
                          color: isCurrent
                              ? catColor.withAlpha(25)
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => Navigator.pop(dialogCtx, entry.key),
                            hoverColor: catColor.withAlpha(15),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isCurrent
                                      ? catColor
                                      : Colors.grey.shade200,
                                  width: isCurrent ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: catColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      entry.key,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: isCurrent
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        color: isCurrent
                                            ? catColor
                                            : Colors.black87,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.grey.shade200,
                                      ),
                                    ),
                                    child: Text(
                                      '${entry.value}',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                  if (isCurrent) ...[
                                    const SizedBox(width: 4),
                                    Icon(Icons.check, size: 14, color: catColor),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            );
          },
        );
      },
    );

    searchCtrl.dispose();

    if (selectedCat != null && mounted) {
      setState(() {
        _quickAccessFilter = 'cat_$selectedCat';
      });
      _requestSearchFocusSilently();
    }
  }

  Widget _buildDynamicCatalogView(List<Product> displayItems, String viewMode) {
    final localTerminal = Provider.of<LocalTerminalProvider>(context, listen: false);
    final canUseScale =
        Provider.of<SettingsProvider?>(context, listen: false)
                ?.safeVerticalProfile
                .canUseScaleWeight ??
            true;
    return PosQuickAccessCatalogView(
      products: displayItems,
      viewMode: viewMode,
      // El ranking Top solo aplica al Acceso Rápido; en búsquedas sería relativo a los resultados.
      showTopRanks: _searchQuery.isEmpty,
      showKeyboardShortcuts: true,
      canUseScaleWeight: canUseScale,
      onSelectProduct: _handleProductSelection,
      onDecrementProduct: _handleDecrementProduct,
      onQuickLook: _showProductQuickLookDialog,
      pinnedProductIds: localTerminal.pinnedProductIds,
      priceBuilder: (product, isByWeight, fontSize) => _buildPriceWidget(
        product,
        isByWeight,
        fontSize,
        viewMode: viewMode,
      ),
    );
  }

  Widget _buildPriceWidget(
    Product product,
    bool isByWeight,
    double fontSize, {
    String? viewMode,
  }) {
    return Consumer2<PosProvider, OfferProvider>(
      builder: (context, pos, offerProv, _) {
        final promoPrice = offerProv.getDiscountedPrice(product);
        final hasOffer = promoPrice != null &&
            promoPrice > 0 &&
            promoPrice < product.sellingPrice;
        final calc = ProductPricingCalculator.calculate(
          product: product,
          activeTier: pos.activeTier,
          wholesaleFactor: pos.wholesaleFactor,
          cardFactor: pos.cardFactor,
          customFactor: pos.currentCustomFactor,
          promotionalPrice: promoPrice,
          hasExplicitOffer: hasOffer,
          cardSurchargeOnOffersMode: pos.cardSurchargeOnOffersMode,
          discountTierOnOffersMode: pos.discountTierOnOffersMode,
          ignoreFixedPrices: pos.ignoreProductFixedPrices,
        );

        final displayPrice = calc.finalUnitPrice;
        final canUseScale =
            Provider.of<SettingsProvider?>(context, listen: false)
                    ?.safeVerticalProfile
                    .canUseScaleWeight ??
                true;
        final unitSuffix = Product.resolveQuantityUnitLabel(
          unitType: product.unitType,
          isSoldByWeight: product.isSoldByWeight,
          preferDiscreteUn: product.isDiscreteFractionalItem(
            businessUsesScaleWeight: canUseScale,
          ),
        );
        final formattedMain = isByWeight
            ? '\$${displayPrice.toCurrency()}/$unitSuffix'
            : '\$${displayPrice.toCurrency()}';
        final isRightAligned = viewMode == 'list' || viewMode == 'compact';
        final Color highlightColor = calc.hasActiveOffer
            ? const Color(0xFFB45309)
            : (isByWeight ? Colors.orange.shade800 : const Color(0xFF1B873A));

        if (calc.crossedOutPrice != null) {
          final formattedOrig = isByWeight
              ? '\$${calc.crossedOutPrice!.toCurrency()}/$unitSuffix'
              : '\$${calc.crossedOutPrice!.toCurrency()}';

          // En modo lista mantenemos el diseño horizontal limpio que ya tiene buen espacio;
          // en tarjetas (grandes/medianas) y botones compactos apilamos verticalmente
          // para que el precio destacado se vea grande y nunca se comprima.
          if (viewMode == 'list') {
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    formattedOrig,
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: fontSize - 2.5,
                      decoration: TextDecoration.lineThrough,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    formattedMain,
                    style: TextStyle(
                      color: highlightColor,
                      fontWeight: FontWeight.w900,
                      fontSize: fontSize,
                    ),
                  ),
                ],
              ),
            );
          }

          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: isRightAligned ? Alignment.centerRight : Alignment.centerLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  isRightAligned ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  formattedOrig,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: (fontSize * 0.68).clamp(9.5, 11.5),
                    decoration: TextDecoration.lineThrough,
                    decorationColor: Colors.grey.shade500,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  formattedMain,
                  style: TextStyle(
                    color: highlightColor,
                    fontWeight: FontWeight.w900,
                    fontSize: fontSize,
                    height: 1.05,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          );
        }

        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: isRightAligned ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            formattedMain,
            style: TextStyle(
              color: isByWeight ? Colors.orange.shade800 : const Color(0xFF1B873A),
              fontWeight: FontWeight.w800,
              fontSize: fontSize,
              height: 1.05,
              letterSpacing: -0.2,
            ),
            maxLines: 1,
          ),
        );
      },
    );
  }

  Widget _buildCartMicroChip({
    required String label,
    required Color bgColor,
    required Color borderColor,
    required Color textColor,
    String? tooltip,
  }) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 9.5,
          color: textColor,
          fontWeight: FontWeight.w700,
          height: 1.15,
        ),
      ),
    );
    if (tooltip != null && tooltip.isNotEmpty) {
      return Tooltip(message: tooltip, child: chip);
    }
    return chip;
  }

}

// ── Componentes Encapsulados ──────────────────────────────────────────────

class _CartItemStockIndicator extends StatelessWidget {
  final CartItem item;
  final List<Widget> leadingBadges;
  final List<Widget> trailingBadges;

  const _CartItemStockIndicator({
    required this.item,
    this.leadingBadges = const [],
    this.trailingBadges = const [],
  });

  @override
  Widget build(BuildContext context) {
    // 💡 IMPORTANTE: Todo context.select() debe estar siempre en la raíz del build, NUNCA condicionado.
    final status = context.select<InventoryAlertsProvider, String?>(
        (p) => p.getAlertStatusForProduct(item.product.id));
    final criticalExpAlert =
        context.select<InventoryAlertsProvider, Map<String, dynamic>?>((p) {
      for (final raw in p.expirationAlerts) {
        if ((raw['product_id'] as num?)?.toInt() == item.product.id &&
            raw['alert_level'] == 'critical') {
          return raw is Map<String, dynamic>
              ? raw
              : Map<String, dynamic>.from(raw as Map);
        }
      }
      return null;
    });
    final hasPredictive = context
        .select<SettingsProvider, bool>((s) => s.features.predictiveAlerts);
    final cart = context.select<PosProvider, List<CartItem>>((p) => p.cart);
    final catalogProducts =
        context.select<CatalogProvider, List<Product>>((c) => c.products);

    Widget wrapWithSurroundingBadges(Widget? alertChip) {
      final allChips = <Widget>[
        ...leadingBadges,
        if (alertChip != null) alertChip,
        ...trailingBadges,
      ];
      if (allChips.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 5,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: allChips,
        ),
      );
    }

    if (item.isTemporary ||
        item.saveToCatalog ||
        item.product.id <= 0 ||
        item.product.isService) {
      return wrapWithSurroundingBadges(null);
    }

    // Mapa rápido de productos del catálogo para consultar siempre el stock más fresco
    final productById = <int, Product>{
      for (final p in catalogProducts) p.id: p,
    };

    final currentProduct = productById[item.product.id] ?? item.product;
    if (currentProduct.isService) {
      return wrapWithSurroundingBadges(null);
    }

    // Acumular el consumo real de cada producto/ingrediente en todo el carrito actual
    // (contemplando tanto productos sueltos como ingredientes dentro de Combos).
    final consumedByProductId = <int, double>{};
    for (final cartItem in cart) {
      final prod = productById[cartItem.product.id] ?? cartItem.product;
      if (prod.isCombo &&
          prod.comboIngredients != null &&
          prod.comboIngredients!.isNotEmpty) {
        for (final ing in prod.comboIngredients!) {
          final ingId = (ing['id'] as num?)?.toInt();
          final ingQty = (ing['quantity'] as num?)?.toDouble() ?? 1.0;
          if (ingId != null && ingQty > 0) {
            consumedByProductId[ingId] =
                (consumedByProductId[ingId] ?? 0.0) + (cartItem.quantity * ingQty);
          }
        }
      } else {
        consumedByProductId[prod.id] =
            (consumedByProductId[prod.id] ?? 0.0) + cartItem.quantity;
      }
    }

    // 1. Verificación en tiempo real (Proyección Local simple y cruzada con Combos)
    double projectedStock;

    if (currentProduct.isCombo &&
        currentProduct.comboIngredients != null &&
        currentProduct.comboIngredients!.isNotEmpty) {
      double? minProjectedCombos;
      for (final ing in currentProduct.comboIngredients!) {
        final ingId = (ing['id'] as num?)?.toInt();
        final reqPerCombo = (ing['quantity'] as num?)?.toDouble() ?? 1.0;
        if (reqPerCombo <= 0) continue;

        final rawIngStock = (ingId != null && productById.containsKey(ingId))
            ? productById[ingId]!.stock
            : ((ing['stock'] as num?)?.toDouble() ?? 0.0);
        // Base 0 para Combos: si el ingrediente físico ya está en 0 o negativo,
        // la cantidad de combos armables disponibles antes del carrito es 0.
        final baseIngStock = rawIngStock < 0 ? 0.0 : rawIngStock;
        final totalIngConsumed = ingId != null
            ? (consumedByProductId[ingId] ?? (item.quantity * reqPerCombo))
            : (item.quantity * reqPerCombo);

        final remainingIngStock = baseIngStock - totalIngConsumed;
        final double combosRemainingForIng;
        if (remainingIngStock < -0.010) {
          combosRemainingForIng =
              (remainingIngStock / reqPerCombo).floorToDouble();
        } else if (remainingIngStock <= 0) {
          combosRemainingForIng = 0.0;
        } else {
          combosRemainingForIng =
              calcUnitsFitStock(remainingIngStock, reqPerCombo).toDouble();
        }

        if (minProjectedCombos == null ||
            combosRemainingForIng < minProjectedCombos) {
          minProjectedCombos = combosRemainingForIng;
        }
      }
      projectedStock =
          minProjectedCombos ?? (currentProduct.stock - item.quantity);
    } else {
      final totalConsumed =
          consumedByProductId[currentProduct.id] ?? item.quantity;
      final rawProjected = currentProduct.stock - totalConsumed;
      projectedStock =
          (rawProjected < 0 && rawProjected >= -0.010) ? 0.0 : rawProjected;
    }

    final minStock = currentProduct.minStock ?? 0;
    final bool isCriticalLocally = projectedStock <= minStock;

    // 2. Estado persistente del servidor (Backend)
    // Si el stock local actualizado en memoria ya es positivo y supera el mínimo,
    // no dejamos que un estado 'out_of_stock' cacheado antes de recargar alertas
    // mantenga trabado el badge en rojo (salvo vencimiento crítico o combo sin receta).
    final hasComboRecipe = currentProduct.isCombo &&
        currentProduct.comboIngredients != null &&
        currentProduct.comboIngredients!.isNotEmpty;
    final bool staleReactiveOverriddenByFreshStock =
        (!currentProduct.isCombo || hasComboRecipe) &&
            currentProduct.stock > 0 &&
            projectedStock > minStock;
    final bool hasCriticalExpiration = criticalExpAlert != null;
    final bool isCriticalBackend = hasCriticalExpiration ||
        (status == 'out_of_stock' && !staleReactiveOverriddenByFreshStock);
    final bool isPredictiveBackend = status == 'predictive';

    final bool isCritical = isCriticalLocally || isCriticalBackend;

    // Si no es crítico y no hay estado predictivo del server, solo renderizar surrounding badges
    if (!isCritical && !isPredictiveBackend) {
      return wrapWithSurroundingBadges(null);
    }

    // 🔒 CANDADO 2: La alerta predictiva naranja solo se muestra con el addon activo.
    if (!isCritical && isPredictiveBackend && !hasPredictive) {
      return wrapWithSurroundingBadges(null);
    }

    late final Widget alertBadge;
    if (hasCriticalExpiration) {
      final stage = criticalExpAlert['stage_code']?.toString() ?? '';
      final daysRaw =
          criticalExpAlert['days_until_expiry'] ?? criticalExpAlert['days_remaining'];
      final int? days = (daysRaw is num)
          ? daysRaw.toInt()
          : int.tryParse(daysRaw?.toString() ?? '');
      final bool isExpired = stage == 'expired' || (days != null && days <= 0);
      final String labelText = isExpired
          ? '⏰ Vencido'
          : (days != null ? '⏰ Vence ${days}d' : '⏰ Por vencer');
      final String expDate =
          criticalExpAlert['expiration_date']?.toString() ?? '';
      final String unitSuffixForAlert =
          currentProduct.unitType.trim().toLowerCase() == 'un' ||
                  currentProduct.unitType.trim().isEmpty
              ? 'u'
              : currentProduct.unitShortLabel;
      final String weightUnitForAlert =
          currentProduct.effectiveQuantityUnitLabel == 'Kg'
              ? 'kg'
              : currentProduct.effectiveQuantityUnitLabel;
      final String stockNote = (isCriticalLocally ||
              (status == 'out_of_stock' && !staleReactiveOverriddenByFreshStock))
          ? ' · Stock proyectado: ${projectedStock.toUnitStockDisplay(isSoldByWeight: currentProduct.isSoldByWeight, unitSuffix: unitSuffixForAlert, weightUnit: weightUnitForAlert)}'
          : '';
      final String tooltip = (isExpired
              ? 'Lote vencido${expDate.isNotEmpty ? ' ($expDate)' : ''}'
              : 'Próximo a vencer${expDate.isNotEmpty ? ' ($expDate)' : ''}') +
          stockNote;

      alertBadge = Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.deepOrange.shade50,
            border: Border.all(color: Colors.deepOrange.shade300),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            labelText,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: Colors.deepOrange.shade900,
              height: 1.15,
            ),
          ),
        ),
      );
    } else {
      final String unitSuffixForAlert =
          currentProduct.unitType.trim().toLowerCase() == 'un' ||
                  currentProduct.unitType.trim().isEmpty
              ? 'u'
              : currentProduct.unitShortLabel;
      final String weightUnitForAlert =
          currentProduct.effectiveQuantityUnitLabel == 'Kg'
              ? 'kg'
              : currentProduct.effectiveQuantityUnitLabel;
      final stockDisp = projectedStock.toUnitStockDisplay(
        isSoldByWeight: currentProduct.isSoldByWeight,
        unitSuffix: unitSuffixForAlert,
        weightUnit: weightUnitForAlert,
      );
      final String labelText =
          isCritical ? '🔴 Crítico: $stockDisp' : '🟠 <3d';
      final String tooltip = isCritical
          ? 'Stock proyectado crítico ($stockDisp)'
          : 'Quiebre de stock estimado en menos de 3 días';

      alertBadge = Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isCritical ? Colors.red.shade50 : Colors.orange.shade50,
            border: Border.all(
              color: isCritical ? Colors.red.shade200 : Colors.orange.shade200,
            ),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            labelText,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: isCritical ? Colors.red.shade700 : Colors.orange.shade800,
              height: 1.15,
            ),
          ),
        ),
      );
    }

    return wrapWithSurroundingBadges(alertBadge);
  }
}

/// Tile animado para cada línea del carrito POS:
/// - Al agregarse un producto nuevo: entra con deslizamiento + aparición suave (`Slide` + `Fade`) y un destello sutil.
/// - Al incrementarse cantidad o cambiar subtotal: ejecuta un pulso de color y micro-escala de confirmación.
/// - Soporta tanto Clic Izquierdo como Clic Derecho para abrir el editor unificado de la línea.
class _AnimatedCartItemTile extends StatefulWidget {
  final double quantity;
  final double subtotal;
  final VoidCallback onTap;
  final VoidCallback onSecondaryTap;
  final Widget child;

  const _AnimatedCartItemTile({
    super.key,
    required this.quantity,
    required this.subtotal,
    required this.onTap,
    required this.onSecondaryTap,
    required this.child,
  });

  @override
  State<_AnimatedCartItemTile> createState() => _AnimatedCartItemTileState();
}

class _AnimatedCartItemTileState extends State<_AnimatedCartItemTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  Color _flashColor = const Color(0xFFEFF6FF);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(-0.04, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _controller.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _flashColor = Colors.transparent;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant _AnimatedCartItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.quantity - widget.quantity).abs() > 0.0005 ||
        (oldWidget.subtotal - widget.subtotal).abs() > 0.005) {
      setState(() {
        _flashColor = const Color(0xFFE0F2FE);
      });
      Future.delayed(const Duration(milliseconds: 220), () {
        if (mounted) {
          setState(() {
            _flashColor = Colors.transparent;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          color: _flashColor,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTap: widget.onSecondaryTap,
            child: InkWell(
              onTap: widget.onTap,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Marca de agua semi-transparente (10% opacidad) con el logo del negocio o ícono de tienda
class PosWatermarkLogo extends StatelessWidget {
  final double size;
  const PosWatermarkLogo({super.key, this.size = 180});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final logoUrl = settings?.effectiveLogoUrl;

    return IgnorePointer(
      child: Opacity(
        opacity: 0.10,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: (logoUrl != null && logoUrl.isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: logoUrl,
                    width: size,
                    height: size,
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => Icon(
                      Icons.storefront_rounded,
                      size: size,
                      color: Colors.grey.shade400,
                    ),
                  )
                : Icon(
                    Icons.storefront_rounded,
                    size: size,
                    color: Colors.grey.shade400,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Scope con ciclo de vida propio para gestionar y liberar TextEditingController
/// automáticamente al desmontarse la ruta del diálogo y proteger callbacks asíncronos.
class _ManagedControllerScope extends StatefulWidget {
  final Widget Function(
    BuildContext context,
    TextEditingController controller,
    bool Function() isDialogMounted,
  ) builder;

  const _ManagedControllerScope({
    required this.builder,
  });

  @override
  State<_ManagedControllerScope> createState() =>
      _ManagedControllerScopeState();
}

class _ManagedControllerScopeState extends State<_ManagedControllerScope> {
  late final TextEditingController _controller;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      _controller,
      () => mounted && !_isDisposed,
    );
  }
}

/// Diálogo de código de barras no reconocido con ciclo de vida propio para
/// el `TextEditingController`, la dependencia de `ModalRoute` y el atajo `F3`.
class _UnrecognizedBarcodeDialog extends StatefulWidget {
  final String scannedBarcode;
  final CartItem? lastCatalogCartItem;
  final Future<List<Product>> Function(String query) onSearchCatalog;
  final Future<void> Function(
    BuildContext dialogCtx,
    Product targetProduct, {
    required bool addToCartAfter,
  }) onAssignBarcode;

  const _UnrecognizedBarcodeDialog({
    required this.scannedBarcode,
    required this.lastCatalogCartItem,
    required this.onSearchCatalog,
    required this.onAssignBarcode,
  });

  @override
  State<_UnrecognizedBarcodeDialog> createState() =>
      _UnrecognizedBarcodeDialogState();
}

class _UnrecognizedBarcodeDialogState
    extends State<_UnrecognizedBarcodeDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Product> _candidateProducts = [];
  bool _isSearchingCatalog = false;
  bool _isClosing = false;
  ModalRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    if (!mounted || _isClosing || event is! KeyDownEvent) return false;
    if (_route?.isCurrent != true) return false;
    if (event.logicalKey == LogicalKeyboardKey.f3) {
      _triggerQuickCreate();
      return true;
    }
    return false;
  }

  void _triggerQuickCreate() {
    if (!mounted || _isClosing) return;
    _isClosing = true;
    Navigator.of(context).pop('quick_create');
  }

  void _close() {
    if (!mounted || _isClosing) return;
    _isClosing = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final lastItem = widget.lastCatalogCartItem;
    return RemoteScannerListener(
      debugLabel: 'UnrecognizedBarcodeDialog',
      onBarcodeScanned: (barcode) async {
        final clean = barcode.trim();
        if (clean.isEmpty || !mounted) return;
        if (clean.toUpperCase() ==
            widget.scannedBarcode.trim().toUpperCase()) {
          SnackBarService.info(
            context,
            'Ese es el mismo código nuevo (${widget.scannedBarcode}). Elegí el producto abajo o escaneá un código existente.',
          );
          return;
        }
        _searchCtrl.text = clean;
        _searchCtrl.selection = TextSelection.collapsed(offset: clean.length);
        setState(() => _isSearchingCatalog = true);
        final found = await widget.onSearchCatalog(clean);
        if (!mounted || _searchCtrl.text.trim() != clean) return;
        setState(() {
          _candidateProducts =
              found.where((p) => !p.isCombo).take(8).toList();
          _isSearchingCatalog = false;
        });
      },
      child: AppModalShell(
        title: 'Código de Barras No Registrado',
        subtitle: 'EAN escaneado: ${widget.scannedBarcode}',
        icon: Icons.qr_code_scanner_rounded,
        accent: AppModalAccent.amber,
        compact: true,
        maxWidth: 500,
        onClose: _close,
        bodyPadding: const EdgeInsets.all(18),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (lastItem != null) ...[
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => widget.onAssignBarcode(
                  context,
                  lastItem.product,
                  addToCartAfter: false,
                ),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primaryBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.bolt_rounded,
                        color: AppColors.primaryDark,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Asociar en 1 clic al último ítem del carrito:',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF1E40AF),
                              ),
                            ),
                            Text(
                              lastItem.product.name,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1E3A8A),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 15,
                        color: AppColors.primaryDark,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _searchCtrl,
              autofocus: lastItem == null,
              decoration: InputDecoration(
                labelText:
                    'Buscar producto en catálogo para asociarle este código...',
                hintText: 'Escribí el nombre del producto...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                isDense: true,
              ),
              onChanged: (val) async {
                final q = val.trim();
                if (q.length < 2) {
                  setState(() {
                    _candidateProducts = [];
                    _isSearchingCatalog = false;
                  });
                  return;
                }
                setState(() => _isSearchingCatalog = true);
                final found = await widget.onSearchCatalog(q);
                if (!mounted || _searchCtrl.text.trim() != q) return;
                setState(() {
                  _candidateProducts =
                      found.where((p) => !p.isCombo).take(8).toList();
                  _isSearchingCatalog = false;
                });
              },
            ),
            if (_isSearchingCatalog)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            if (_candidateProducts.isNotEmpty) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _candidateProducts.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, idx) {
                    final p = _candidateProducts[idx];
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      title: Text(
                        p.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      subtitle: Text(
                        '\$${p.sellingPrice.toCurrency()} · ${p.barcode != null && p.barcode!.isNotEmpty ? "EAN actual: ${p.barcode}" : "Sin EAN"}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      trailing: FilledButton.tonalIcon(
                        onPressed: () => widget.onAssignBarcode(
                          context,
                          p,
                          addToCartAfter: true,
                        ),
                        icon: const Icon(Icons.link_rounded, size: 16),
                        label: const Text(
                          'Asociar y Agregar',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
        footerLeading: OutlinedButton.icon(
          onPressed: _triggerQuickCreate,
          icon: const Icon(Icons.flash_on_rounded, size: 17),
          label: const Text('Crear Ítem Rápido (F3)'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFB45309),
            side: const BorderSide(color: AppColors.amber),
          ),
        ),
        footerActions: [
          TextButton(
            onPressed: _close,
            child: const Text('Cerrar (Esc)'),
          ),
        ],
      ),
    );
  }
}

