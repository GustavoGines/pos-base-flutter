import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/config/app_config.dart';
import 'package:frontend_desktop/features/catalog/data/models/product_model.dart';
import 'package:frontend_desktop/core/utils/receipt_printer_service.dart';
import 'package:flutter/material.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
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
import 'package:frontend_desktop/core/presentation/widgets/plan_upgrade_dialog.dart';
import 'package:frontend_desktop/features/offers/presentation/providers/offer_provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/features/cash_movements/presentation/widgets/movement_form_dialog.dart' as frontend_desktop_cash_movements_dialog;
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:frontend_desktop/features/quotes/presentation/providers/quote_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import '../../../auth/presentation/widgets/admin_pin_dialog.dart';
import '../../../../core/constants/app_permissions.dart';
import 'package:frontend_desktop/core/utils/a4_split_pdf_service.dart';
import 'package:printing/printing.dart';
import 'package:frontend_desktop/features/logistics/presentation/providers/logistics_provider.dart';
import 'package:dart_pusher_channels/dart_pusher_channels.dart';
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
  final _pendingOrdersLayerLink = LayerLink();
  bool _isPendingPinned = false; // Modo Híbrido

  // Filtro rápido en memoria para el Acceso Rápido
  String _quickAccessFilter = 'all'; // 'all', 'pinned', 'top_sellers', 'offers', 'weight', o 'cat_<id>'

  // Protección Anti-"Efecto Baile": congela el orden de IDs durante el turno activo
  // para que al cobrar una venta suba el badge (⚡/🔥) pero las tarjetas y Ctrl+1..9 no cambien de lugar.
  String? _frozenOrderSignature;
  final Map<int, int> _frozenRankById = {};

  // Candado anti-doble-modal para preventir abrir CheckoutDialog dos veces
  bool _isCheckingOut = false;

  PusherChannelsClient? _pusher;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handlePosHardwareKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initReverb();
      _searchFocusNode.requestFocus();
      // Siempre cargar la lista COMPLETA al entrar a POS, ignorando cualquier
      // búsqueda u ordenamiento que el módulo de Catálogo haya dejado activo.
      Provider.of<CatalogProvider>(context, listen: false)
          .loadProducts(page: 1, search: '', sortBy: '', perPage: 500);
      // Sincronizar y aplicar lista de precios fijada por la terminal
      final localTerminal = Provider.of<LocalTerminalProvider>(context, listen: false);
      final posProvider = Provider.of<PosProvider>(context, listen: false);
      final settings = Provider.of<SettingsProvider>(context, listen: false).settings;
      
      String initialTier = 'base';
      String? initialLabel;

      if (localTerminal.lockedPriceTier != 'none') {
        final lockedTier = localTerminal.lockedPriceTier;
        
        // Validar si es una lista custom y si aún existe/está habilitada en la configuración global
        if (lockedTier.startsWith('custom_')) {
          final tierName = lockedTier.replaceFirst('custom_', '');
          final isEnabledGlobal = settings != null && (settings.features.multiplePrices || settings.enableAdvancedPriceTiers);
          final exists = isEnabledGlobal && settings.customPriceTiers.any((t) => t['name'] == tierName);
          
          if (exists) {
            initialTier = lockedTier;
            initialLabel = localTerminal.lockedPriceTierLabel;
          } else {
            // Limpiar la lista fijada porque ya no es válida o fue eliminada
            localTerminal.setLockedPriceTier('none');
          }
        } else {
          initialTier = lockedTier;
          initialLabel = localTerminal.lockedPriceTierLabel;
        }
      }

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

  Future<void> _initReverb() async {
    final localTerminal = Provider.of<LocalTerminalProvider>(context, listen: false);
    final terminalId = localTerminal.terminalId;

    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUrl = prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;
      final uri = Uri.parse(currentUrl);
      
      final isSecure = currentUrl.startsWith('https');
      String pusherHost = uri.host;
      if (pusherHost.startsWith('api.')) {
        pusherHost = pusherHost.replaceFirst('api.', 'ws.');
      } else if (pusherHost.startsWith('api-')) {
        pusherHost = pusherHost.replaceFirst('api-', 'ws-');
      }
          
      // Cloudflare rutea WSS por el puerto estándar 443. En red local directa usamos el 8080 de Reverb.
      final int pusherPort = isSecure ? 443 : 8080;
      
      final options = PusherChannelsOptions.fromHost(
        scheme: isSecure ? 'wss' : 'ws',
        host: pusherHost,
        port: pusherPort,
        key: 'kz786cdfeldnzispymxq',
      );

      _pusher = PusherChannelsClient.websocket(
        options: options,
        connectionErrorHandler: (error, trace, refresh) {},
      );

      // Escáner Inalámbrico
      final scanChannel = _pusher!.publicChannel('pos.scans.$terminalId');
      // Impresora Inalámbrica (Mobile Label Printing)
      final printerChannel = _pusher!.publicChannel('pos.printers.$terminalId');

      _pusher!.onConnectionEstablished.listen((_) {
        scanChannel.subscribe();
        printerChannel.subscribe();
      });

      scanChannel.bind('App\\Events\\MobileScanned').listen((event) {
        try {
          if (event.data == null) return;
          final data = jsonDecode(event.data.toString());
          final barcode = data['barcode'];
          if (mounted && barcode != null && ModalRoute.of(context)?.isCurrent == true) {
            _searchController.text = barcode;
            _onProductScannedOrSearched(barcode);
          }
        } catch (e) {
          debugPrint("Error parsing MobileScanned event: $e");
        }
      });

      printerChannel.bind('App\\Events\\PrintLabelRequested').listen((event) async {
        try {
          if (event.data == null) return;
          final data = jsonDecode(event.data.toString());
          final productId = data['productId'];
          if (mounted && productId != null) {
             // Encontrar producto por id e imprimir
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
                 }
               );
               if (response.statusCode == 200) {
                  product = ProductModel.fromJson(jsonDecode(response.body));
               }
             }
             
             if (product != null) {
               await ReceiptPrinterService.instance.printLabel(product);
               if (mounted) SnackBarService.success(context, 'Etiqueta impresa remotamente');
             }
          }
        } catch (e) {
          debugPrint("Error parsing PrintLabelRequested event: $e");
        }
      });

      await _pusher!.connect();
    } catch (e) {
      debugPrint("Error connecting Reverb: $e");
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handlePosHardwareKey);
    _pusher?.disconnect();
    _pendingOrdersTimer?.cancel();
    _debounceSearchTimer?.cancel();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Búsqueda en vivo vía API con debounce de 400ms
  void _onPosSearchChanged(String value) {
    final query = value.trim();
    _debounceSearchTimer?.cancel();

    if (query.isEmpty) {
      setState(() {
        _searchQuery = '';
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _searchQuery = query);

    _debounceSearchTimer = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted || _searchQuery.isEmpty) return;
      setState(() => _isSearching = true);
      final results =
          await Provider.of<PosProvider>(context, listen: false).search(query);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    });
  }

  void _onProductScannedOrSearched(String query) async {
    if (query.trim().isEmpty) {
      final posProvider = Provider.of<PosProvider>(context, listen: false);
      if (posProvider.cart.isNotEmpty && !posProvider.isLoading && !_isCheckingOut) {
        _handleCheckout();
      }
      return;
    }
    String cleanQuery = query.trim().toUpperCase();

    final posProvider = Provider.of<PosProvider>(context, listen: false);

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
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('Cargar Presupuesto: $cleanQuery'),
                content: Text(
                    '¿Desea limpiar la caja actual y cargar los ${quote.items.length} productos de este presupuesto?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Cargar'),
                  ),
                ],
              ),
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

      _searchController.clear();
      setState(() => _searchQuery = '');
      _searchFocusNode.requestFocus();
      return;
    }

    // 1. Intentamos buscar el código exactamente como se escaneó primero.
    // Esto es crucial por si el producto es unitario y su código EAN normal comienza con '2'.
    List<Product> results = await posProvider.search(cleanQuery);

    bool appliedScaleLogic = false;
    double embeddedPrice = 0.0;

    // 2. Si no hubo coincidencias exactas, verificamos si es una etiqueta de balanza (13 dígitos, empieza en '2')
    if (results.isEmpty &&
        cleanQuery.length == 13 &&
        cleanQuery.startsWith('2')) {
      // Formato típico local: 1 (Prefijo) + 5 (PLU) + 6 (Precio Entero) + 1 (Dígito Verificador)
      final itemCodeStr = cleanQuery.substring(1, 6);
      final priceStr = cleanQuery.substring(6, 12);
      final pluQuery = int.parse(itemCodeStr).toString();
      embeddedPrice = double.parse(priceStr);

      // Hacemos una segunda búsqueda usando solamente el PLU extraído
      results = await posProvider.search(pluQuery);

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
            }
            _searchController.clear();
            setState(() => _searchQuery = '');
            _searchFocusNode.requestFocus();
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
            }
            _searchController.clear();
            setState(() => _searchQuery = '');
            _searchFocusNode.requestFocus();
            return;
          }
        }
      }
    }

    if (!mounted) return;

    if (results.isEmpty) {
      SnackBarService.error(context, 'Producto no encontrado: "$cleanQuery"');
    } else if (appliedScaleLogic) {
      final product = results.first;
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
      _handleProductSelection(results.first);
    } else {
      await _showProductPickerDialog(results, cleanQuery);
    }

    _searchController.clear();
    setState(() => _searchQuery = '');
    _searchFocusNode.requestFocus();
  }

  /// Diálogo para seleccionar entre múltiples resultados de búsqueda
  Future<void> _showProductPickerDialog(
      List<Product> results, String query) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.search, color: Colors.blueAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Resultados para "$query"',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
        content: SizedBox(
          width: 480,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: results.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final p = results[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: p.isSoldByWeight
                      ? Colors.orange.shade100
                      : Colors.blue.shade50,
                  child: Icon(
                    p.isSoldByWeight
                        ? Icons.scale_rounded
                        : Icons.inventory_2_outlined,
                    color: p.isSoldByWeight
                        ? Colors.orange.shade700
                        : Colors.blue.shade700,
                    size: 20,
                  ),
                ),
                title: Text(p.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  p.isSoldByWeight
                      ? 'Por Kg · \$${p.sellingPrice.toCurrency()}/Kg'
                      : '\$${p.sellingPrice.toCurrency()}',
                ),
                trailing:
                    const Icon(Icons.add_circle_outline, color: Colors.green),
                onTap: () {
                  Navigator.pop(ctx);
                  _handleProductSelection(p);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  void _handleProductSelection(Product product) {
    final posProvider = Provider.of<PosProvider>(context, listen: false);
    final offerProvider = Provider.of<OfferProvider>(context, listen: false);
    final promoPrice = offerProvider.getDiscountedPrice(product);
    final promoOffer = offerProvider.getActiveOfferForProduct(product.id, basePrice: product.sellingPrice);

    final success = posProvider.requestAddToCartWithPromo(
      product,
      promotionalPrice: promoPrice,
      promotionalLabel: promoOffer?.name,
      promotionalPeriodType: promoOffer?.periodType,
    );
    if (success) {
      _searchFocusNode.requestFocus();
    } else {
      // Es producto por peso, pedir peso por Modal
      _showWeightModal(
        product,
        posProvider,
        promotionalPrice: promoPrice,
        promotionalLabel: promoOffer?.name,
        promotionalPeriodType: promoOffer?.periodType,
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
    _searchFocusNode.requestFocus();
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

  String _formatQuickLookStock(double qty, bool isByWeight) =>
      isByWeight ? '${qty.toStringAsFixed(3)} Kg' : '${qty.toInt()} u.';

  void _showProductQuickLookDialog(Product product) {
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
    final lowStock = !product.isCombo &&
        product.minStock != null &&
        product.stock <= product.minStock!;

    final uri = product.imageUrl != null && product.imageUrl!.isNotEmpty
        ? Uri.tryParse(product.imageUrl!)
        : null;
    final hasImage =
        uri != null && uri.hasScheme && uri.hasAuthority && uri.host.isNotEmpty;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header: foto + identidad ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: hasImage
                            ? CachedNetworkImage(
                                imageUrl: product.imageUrl!,
                                fit: BoxFit.contain,
                                errorWidget: (context, url, error) => Icon(
                                  isByWeight
                                      ? Icons.scale_rounded
                                      : Icons.inventory_2_outlined,
                                  color: accent,
                                  size: 30,
                                ),
                              )
                            : Icon(
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
                                _quickLookCodeChip('Int', product.internalCode),
                              if (product.barcode != null &&
                                  product.barcode!.isNotEmpty)
                                _quickLookCodeChip('EAN', product.barcode!),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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
                        value: _formatQuickLookStock(product.stock, isByWeight),
                        valueColor: lowStock ? Colors.orange.shade800 : null,
                        footer: product.minStock != null
                            ? 'Mín: ${_formatQuickLookStock(product.minStock!, isByWeight)}'
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
                            ? 'En ticket: ${_formatQuickLookStock(cartQty, isByWeight)}'
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
                          valueColor: const Color(0xFF7B1FA2),
                        ),
                      if (product.priceWholesale != null &&
                          product.priceWholesale! > 0)
                        _buildInfoRow('Precio Mayorista',
                            '\$${product.priceWholesale!.toCurrency()}'),
                      if (product.priceCard != null && product.priceCard! > 0)
                        _buildInfoRow('Precio Tarjeta',
                            '\$${product.priceCard!.toCurrency()}'),
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
                const SizedBox(height: 14),

                // ── Footer de acciones (ancho controlado, sin estirar el diálogo) ──
                Row(
                  children: [
                    TextButton.icon(
                      icon: Icon(
                          isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                          size: 18),
                      label: Text(isPinned ? 'Desfijar' : '📌 Fijar'),
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
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cerrar'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add_shopping_cart, size: 18),
                      label: const Text('Agregar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E88E5),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _handleProductSelection(product);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((_) {
      if (mounted) _searchFocusNode.requestFocus();
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
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
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
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.keyboard_rounded,
                        color: Colors.blueGrey.shade700, size: 22),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Guía Rápida de Teclado POS',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      tooltip: 'Cerrar (Esc)',
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _shortcutSection(
                  '⚡ Flujo "Doble Enter" (Cobro en 1 segundo)',
                  [
                    _shortcutRow(['Enter'],
                        'con buscador vacío → Abre ventana de Cobro'),
                    _shortcutRow([
                      'Enter'
                    ], 'en ventana de Cobro → Confirma pago exacto en Efectivo'),
                    _shortcutRow(
                        ['F9', 'F12'], 'Cobrar directo en cualquier momento'),
                  ],
                ),
                _shortcutSection(
                  '🛒 Carrito y Acceso Rápido',
                  [
                    _shortcutRow(['Ctrl', '1..9'],
                        'Agrega el producto 1 al 9 de la grilla'),
                    _shortcutRow([
                      '+',
                      '-'
                    ], 'con buscador vacío → Suma o resta 1 u. al último ítem'),
                    _shortcutRow([
                      'Supr'
                    ], 'con buscador vacío → Elimina el último ítem del carrito'),
                    _shortcutRow(['Clic Der.'],
                        'sobre producto → Vista Rápida (stock, precios, 📌)'),
                  ],
                ),
                _shortcutSection(
                  '💳 Ventana de Cobro (Desglose de Pago)',
                  [
                    _shortcutRow(['Ctrl', '1..7'], 'Métodos de pago (Efectivo, Point, QR, Tarjetas, Cta. Cte., Cheque)'),
                    _shortcutRow(['F2'], 'Pago exacto auto-ajustable en efectivo'),
                    _shortcutRow(['F4'], 'Agregar otro medio de pago (Pago Mixto)'),
                    _shortcutRow(['F6'], 'Asociar / Buscar Cliente'),
                    _shortcutRow(['F7'], 'Marcar / Desmarcar Imprimir Comprobante'),
                    _shortcutRow(['F8'], 'Marcar / Desmarcar Vista Previa'),
                    _shortcutRow(['F9'], 'Alternar Ticket Común / Factura Fiscal ARCA'),
                    _shortcutRow(['F10'], 'Alternar Logística (Retira / Envío / Acopio)'),
                    _shortcutRow(['Enter'], 'Confirmar Venta'),
                    _shortcutRow(['Esc'], 'Cerrar ventana de Cobro (conserva borrador)'),
                  ],
                ),
                _shortcutSection(
                  '🗂️ Orden en Espera, Clientes y Filtros',
                  [
                    _shortcutRow(['F4'], 'Poner el carrito actual en Espera'),
                    _shortcutRow(['F6'], 'Asociar / Buscar Cliente al carrito'),
                    _shortcutRow([
                      'Esc'
                    ], 'Cierra ventana de Cobro, limpia buscador o vuelve a "Todos"'),
                    _shortcutRow(['F1'], 'Abre esta guía de ayuda'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  Widget _shortcutSection(String title, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ...rows,
        ],
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
  void _showWeightModal(Product product, PosProvider provider,
      {double? promotionalPrice, String? promotionalLabel, String? promotionalPeriodType}) {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return _ManagedControllerScope(
            builder: (context, weightController, isDialogMounted) {
              return ValueListenableBuilder<TextEditingValue>(
                  valueListenable: weightController,
                  builder: (context, value, child) {
                    final isValid = value.text.trim().isNotEmpty &&
                        double.tryParse(value.text.replaceAll(',', '.')) != null &&
                        double.parse(value.text.replaceAll(',', '.')) > 0;
                    return AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      title: Text('Ingresar Peso (Kg) - ${product.name}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18)),
                      content: Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: TextField(
                          controller: weightController,
                          autofocus: true,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Peso Exacto (Ej: 1.500)',
                            hintText: '0.000',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            suffixText: 'KG',
                            helperText: 'Ejemplo: 0.5 = 500 gramos',
                          ),
                          onSubmitted: (val) {
                            if (isValid) {
                              _processWeight(val, product, provider, context,
                                  promotionalPrice: promotionalPrice,
                                  promotionalLabel: promotionalLabel,
                                  promotionalPeriodType: promotionalPeriodType);
                            }
                          },
                        ),
                      ),
                      actionsPadding:
                          const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      actions: [
                        Consumer<LocalTerminalProvider>(
                          builder: (ctx, localTerminal, _) {
                            final comPort = localTerminal.scaleComPort;
                            if (comPort.isEmpty) {
                              return const SizedBox.shrink(); // Sin balanza local
                            }
                            return OutlinedButton.icon(
                              onPressed: () => _readWeightFromScale(
                                  comPort, weightController,
                                  isDialogMounted: isDialogMounted),
                              icon: const Icon(Icons.scale_rounded,
                                  color: Colors.blueGrey),
                              label: const Text('Leer Balanza'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blueGrey,
                                side: const BorderSide(color: Colors.blueGrey),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                            );
                          },
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancelar',
                              style: TextStyle(color: Colors.grey)),
                        ),
                        FilledButton(
                          onPressed: isValid
                              ? () {
                                  _processWeight(weightController.text, product,
                                      provider, context,
                                      promotionalPrice: promotionalPrice,
                                      promotionalLabel: promotionalLabel,
                                      promotionalPeriodType: promotionalPeriodType);
                                }
                              : null,
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Agregar'),
                        )
                      ],
                    );
                  });
            },
          );
        }).then((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _readWeightFromScale(
      String comPort, TextEditingController controller,
      {bool Function()? isDialogMounted}) async {
    if (comPort.isEmpty) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Conectando a balanza en $comPort...')),
      );
    }

    try {
      final port = SerialPort(comPort);
      if (!port.openReadWrite()) {
        final err = SerialPort.lastError;
        if (mounted) {
          SnackBarService.error(context,
              'No se pudo abrir el puerto $comPort. ${err != null ? err.message : ""}');
        }
        port.dispose();
        return;
      }

      String accumulatedData = '';
      StreamSubscription? subscription;

      try {
        // Configuración estándar de balanzas (ej. Kretz/Systel en Argentina)
        final config = port.config;
        config.baudRate = 9600;
        config.bits = 8;
        config.stopBits = 1;
        config.parity = 0; // SerialPortParity.none
        port.config = config;

        final reader = SerialPortReader(port, timeout: 500);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Esperando peso estable... (1.5 seg)'),
                duration: Duration(milliseconds: 1500)),
          );
        }

        // Escuchar el stream durante 1.5 segundos
        subscription = reader.stream.listen((data) {
          accumulatedData += String.fromCharCodes(data);
        });

        await Future.delayed(const Duration(milliseconds: 1500));
      } finally {
        await subscription?.cancel();
        port.close();
        port.dispose();
      }

      // Buscar si la balanza mandó un valor numérico continuo
      if (accumulatedData.isNotEmpty) {
        final RegExp weightRegex = RegExp(r'(\d+[\.,]\d+)');
        final matches = weightRegex.allMatches(accumulatedData);

        if (matches.isNotEmpty) {
          String weightStr = matches.last.group(0)!;
          weightStr = weightStr.replaceAll(',', '.');

          if (mounted && (isDialogMounted?.call() ?? true)) {
            controller.text = weightStr;
            SnackBarService.success(context, 'Lectura exitosa: $weightStr Kg');
          }
        } else {
          if (mounted) {
            SnackBarService.error(context,
                'No se detectó un peso numérico. Datos: "$accumulatedData"');
          }
        }
      } else {
        if (mounted) {
          SnackBarService.error(context,
              'No se recibieron datos. Revise la conexión de la balanza en $comPort.');
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarService.error(context, 'Error en el puerto $comPort: $e');
      }
    }
  }

  void _processWeight(String value, Product product, PosProvider provider,
      BuildContext dialogContext,
      {double? promotionalPrice, String? promotionalLabel, String? promotionalPeriodType}) {
    // Reemplaza comas por puntos en caso de que teclados latinos obligen coma
    String sanitizedValue = value.replaceAll(',', '.');
    final weight = double.tryParse(sanitizedValue);

    // Validación básica: El peso debe ser positivo y menor a una exageración (Ej: >1000Kg es raro en POS base)
    if (weight != null && weight > 0 && weight < 1000) {
      provider.submitWeighedProductWithPromo(product, weight,
          promotionalPrice: promotionalPrice,
          promotionalLabel: promotionalLabel,
          promotionalPeriodType: promotionalPeriodType);
      Navigator.pop(dialogContext);
    } else {
      SnackBarService.error(
          dialogContext, 'Por favor, ingrese un peso válido en Kg.');
    }
  }

  void _showEditCartItemModal(dynamic cartItem, PosProvider provider) {
    final initialText = cartItem.product.isSoldByWeight
        ? cartItem.quantity.toQty()
        : cartItem.quantity.toInt().toString();

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return _ManagedControllerScope(
            initialText: initialText,
            builder: (context, qtyController, isDialogMounted) {
              return ValueListenableBuilder<TextEditingValue>(
                  valueListenable: qtyController,
                  builder: (context, value, child) {
                    final isValid = value.text.trim().isNotEmpty &&
                        double.tryParse(value.text.replaceAll(',', '.')) != null &&
                        double.parse(value.text.replaceAll(',', '.')) > 0;
                    return AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      title: Text('Editar Cantidad - ${cartItem.product.name}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18)),
                      content: Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: TextField(
                          controller: qtyController,
                          autofocus: true,
                          keyboardType: cartItem.product.isSoldByWeight
                              ? const TextInputType.numberWithOptions(decimal: true)
                              : TextInputType.number,
                          decoration: InputDecoration(
                            labelText: cartItem.product.isSoldByWeight
                                ? 'Peso Exacto (Ej: 1.500)'
                                : 'Cantidad (Unidades)',
                            hintText:
                                cartItem.product.isSoldByWeight ? '0.000' : '1',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            suffixText:
                                cartItem.product.isSoldByWeight ? 'KG' : 'UN',
                            helperText: cartItem.product.isSoldByWeight
                                ? 'Ejemplo: 0.5 = 500 gramos'
                                : null,
                          ),
                          onSubmitted: (val) {
                            if (isValid) {
                              _processCartItemEdit(
                                  val, cartItem, provider, context);
                            }
                          },
                        ),
                      ),
                      actionsPadding:
                          const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      actions: [
                        if (cartItem.product.isSoldByWeight)
                          Consumer<LocalTerminalProvider>(
                            builder: (ctx, localTerminal, _) {
                              final comPort = localTerminal.scaleComPort;
                              if (comPort.isEmpty) {
                                return const SizedBox.shrink(); // Sin balanza local
                              }
                              return OutlinedButton.icon(
                                onPressed: () => _readWeightFromScale(
                                    comPort, qtyController,
                                    isDialogMounted: isDialogMounted),
                                icon: const Icon(Icons.scale_rounded,
                                    color: Colors.blueGrey),
                                label: const Text('Leer Balanza'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.blueGrey,
                                  side: const BorderSide(color: Colors.blueGrey),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                              );
                            },
                          ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancelar',
                              style: TextStyle(color: Colors.grey)),
                        ),
                        FilledButton(
                          onPressed: isValid
                              ? () {
                                  _processCartItemEdit(qtyController.text, cartItem,
                                      provider, context);
                                }
                              : null,
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Actualizar'),
                        )
                      ],
                    );
                  });
            },
          );
        }).then((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _processCartItemEdit(String value, dynamic cartItem,
      PosProvider provider, BuildContext dialogContext) {
    String sanitizedValue = value.replaceAll(',', '.');
    final newQuantity = double.tryParse(sanitizedValue);

    if (newQuantity != null && newQuantity > 0) {
      // Si el producto NO es pesado, forzar entero por si acaso.
      final finalQuantity = cartItem.product.isSoldByWeight
          ? newQuantity
          : newQuantity.toInt().toDouble();

      provider.updateQuantity(cartItem, finalQuantity);
      Navigator.pop(dialogContext);
    } else {
      SnackBarService.error(
          dialogContext, 'Por favor, ingrese una cantidad válida mayor a 0.');
    }
  }

  // Helper de conversión segura String/num → double
  double _toDouble(dynamic value) =>
      value == null ? 0.0 : double.tryParse(value.toString()) ?? 0.0;

  void _handleCheckout() async {
    if (_isCheckingOut) return;
    _isCheckingOut = true;

    try {
      final posProvider = Provider.of<PosProvider>(context, listen: false);
      final cashRegisterProvider =
          Provider.of<CashRegisterProvider>(context, listen: false);

      // ── VALIDACIÓN PROACTIVA: Verificar el turno en el servidor ANTES de abrir
      // la pantalla de cobro. Esto intercepta el caso donde el turno fue cerrado
      // desde otra terminal mientras este cliente estaba ocioso con el carrito lleno.
      final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
      await cashRegisterProvider.checkCurrentShift(registerId: settingsProvider.assignedRegisterId > 0 ? settingsProvider.assignedRegisterId : null);

      final currentShift = cashRegisterProvider.currentShift;
      if (!mounted) return;

      if (currentShift == null || !currentShift.isOpen) {
        // El turno ya no existe en el servidor → mostrar cartel de seguridad de inmediato
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: Colors.red.shade50,
            title: Row(
              children: [
                Icon(Icons.lock_clock, color: Colors.red.shade700, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Turno Cerrado',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'El turno de caja fue cerrado desde otra terminal.',
                  style: TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 12),
                Text(
                  'La sesión actual ya no es válida. Será redirigido al inicio para actualizar el estado de la caja.',
                  style: TextStyle(fontSize: 13, color: Colors.red.shade700),
                ),
              ],
            ),
            actions: [
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

        // 2. ACTUALIZAR LOGÍSTICA EN BACKGROUND (SOLO SI TIENE PERMISO)
        final authProv = context.read<AuthProvider>();
        if (authProv.hasPermission(AppPermissions.manageDeliveryNotes)) {
          Provider.of<LogisticsProvider>(context, listen: false).refreshAll(force: true);
        }

        final settingsProvider =
            Provider.of<SettingsProvider>(context, listen: false);
        final localTerminalProvider =
            Provider.of<LocalTerminalProvider>(context, listen: false);
        final localFormat = localTerminalProvider.printerFormat;

        // ── Post-venta Logística (Fricción Cero) ──────────────────────────
        // El remito ya fue creado en processCheckout(). Aquí decidimos cómo mostrarlo.
        if (posProvider.wasLastSaleDispatched && posProvider.lastSalePrinted) {
          final deliveryNote = posProvider.lastDeliveryNote;
          final isDeliveredNow = deliveryNote?['status'] == 'delivered';

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
              final sale =
                  (deliveryNote['sale'] as Map<String, dynamic>?) ?? {};

              // Si el remito no trajo la venta hidratada, usamos el snapshot de seguridad del provider
              if (sale.isEmpty || sale['items'] == null) {
                sale['id'] = deliveryNote['sale_id'];
                sale['total'] = posProvider.lastSaleTotal;
                sale['shipping_cost'] = posProvider.lastSaleShippingCost;
                sale['surcharge_amount'] = posProvider.lastSurchargeAmount;
                sale['payments'] = posProvider.lastSalePayments;
                sale['tendered_amount'] = posProvider.lastTenderedAmount;
                sale['change_amount'] = posProvider.lastChangeAmount;
                sale['items'] = posProvider.lastSaleCart
                    .map((item) => {
                          'product_id': item.product.id,
                          'quantity': item.quantity,
                          'product_name': item.product.name,
                          'unit_price': item.unitPrice,
                          'subtotal': item.subtotal,
                          'product': {
                            'is_sold_by_weight': item.product.isSoldByWeight,
                          }
                        })
                    .toList();
                sale['customer'] = deliveryNote['customer'] ??
                    deliveryNote['sale']?['customer'];
              }

              final authProvider =
                  Provider.of<AuthProvider>(context, listen: false);
              final vendorName =
                  authProvider.currentUser?['name']?.toString() ?? 'CAJERO';
              final businessName =
                  settingsProvider.settings?.companyName ?? 'MI NEGOCIO';

              if (localFormat == 'a4_split' ||
                  localFormat == 'a4_normal' ||
                  localFormat == 'a4') {
                // 1. A4 SMART (Split si <= 6 ítems, MultiPage si > 6 ítems)
                final pdfBytes =
                    await A4SplitPdfService.generateA4SplitReceiptAndDispatch(
                  sale: sale,
                  deliveryNote: deliveryNote,
                  businessName: businessName,
                  businessAddress: settingsProvider.settings?.address,
                  vendorName: vendorName,
                  paperSize: localTerminalProvider.pdfPaperSize,
                );

                if (mounted) {
                  final result = await showDialog<String>(
                    context: context,
                    barrierDismissible: false,
                    builder: (dialogCtx) {
                      bool isVoiding = false;
                      return StatefulBuilder(
                        builder: (context, setState) {
                          return Dialog(
                            child: SizedBox(
                              width: 900,
                              height: 800,
                              child: Scaffold(
                                appBar: AppBar(
                                  title: Text(
                                      'Vista Previa - Venta #${sale['id']}'),
                                  automaticallyImplyLeading: false,
                                  actions: [
                                    if (isVoiding)
                                      Center(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16.0),
                                          child: SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.red),
                                          ),
                                        ),
                                      )
                                    else
                                      TextButton.icon(
                                        onPressed: () async {
                                          final confirm =
                                              await showDialog<bool>(
                                            context: context,
                                            builder: (c) => AlertDialog(
                                              title:
                                                  const Text('¿Anular Venta?'),
                                              content: const Text(
                                                  'Esta acción cancelará el cobro en el sistema y devolverá los productos al carrito.'),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(c, false),
                                                    child: const Text(
                                                        'NO, VOLVER')),
                                                ElevatedButton(
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                            backgroundColor:
                                                                Colors.red,
                                                            foregroundColor:
                                                                Colors.white),
                                                    onPressed: () =>
                                                        Navigator.pop(c, true),
                                                    child: const Text(
                                                        'SÍ, ANULAR')),
                                              ],
                                            ),
                                          );

                                          if (confirm == true) {
                                            final currentShift = context.read<CashRegisterProvider>().currentShift;
                                            if (currentShift == null) {
                                              if (dialogCtx.mounted) {
                                                SnackBarService.error(
                                                    dialogCtx, 'Debe haber un turno de caja abierto para anular órdenes.');
                                              }
                                              return;
                                            }
                                            setState(() {
                                              isVoiding = true;
                                            });
                                            try {
                                              final success = await posProvider
                                                  .voidPendingOrder(
                                                      int.parse(
                                                          sale['id'].toString()),
                                                      shiftId: currentShift.id);
                                              if (!success) {
                                                throw Exception(
                                                    posProvider.errorMessage ??
                                                        'Error desconocido');
                                              }
                                              // Restaurar carrito al estado previo a la venta
                                              posProvider.restoreLastSaleCart();

                                              if (dialogCtx.mounted) {
                                                SnackBarService.warning(
                                                    dialogCtx,
                                                    'Venta anulada. Los productos han vuelto al carrito.');
                                                Navigator.pop(
                                                    dialogCtx, 'annulled');
                                              }
                                            } catch (e) {
                                              if (dialogCtx.mounted) {
                                                SnackBarService.error(dialogCtx,
                                                    'Error al anular: $e');
                                                setState(() {
                                                  isVoiding = false;
                                                });
                                              }
                                            }
                                          }
                                        },
                                        icon: const Icon(Icons.delete_forever,
                                            color: Colors.red),
                                        label: const Text(
                                            'ANULAR COBRO Y VOLVER',
                                            style: TextStyle(
                                                color: Colors.red,
                                                fontWeight: FontWeight.bold)),
                                      ),
                                    const SizedBox(width: 16),
                                    IconButton(
                                      icon: const Icon(Icons.close),
                                      onPressed: isVoiding
                                          ? null
                                          : () => Navigator.pop(dialogCtx),
                                    ),
                                  ],
                                ),
                                body: PdfPreview(
                                  build: (format) async => pdfBytes,
                                  canChangePageFormat: false,
                                  canChangeOrientation: false,
                                  pdfFileName: 'Comprobante_${sale['id']}.pdf',
                                  canDebug: false,
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

        // 3. REFRESCO SELECTIVO (FIRE-AND-FORGET):
        // Solo actualizamos el stock de los productos vendidos — sin recargar el catálogo completo.
        // Esto elimina el parpadeo de la grilla y acelera la vuelta a pantalla de venta.
        final List<int> soldIds = soldItems.keys.toList();
        catalogProvider.refreshStockForSoldProducts(soldIds).catchError((e) {
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
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.red.shade50,
          title: Row(
            children: [
              Icon(Icons.lock_clock, color: Colors.red.shade700, size: 28),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Turno Cerrado',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                posProvider.errorMessage ??
                    'El turno de caja fue cerrado desde otra terminal.',
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 12),
              Text(
                'La sesión actual ya no es válida. Será redirigido al inicio para actualizar el estado de la caja.',
                style: TextStyle(fontSize: 13, color: Colors.red.shade700),
              ),
            ],
          ),
          actions: [
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

    _searchFocusNode.requestFocus();
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

    final success = await posProvider.holdOrder(
      shiftId: currentShift.id,
      userId: currentUser?['id'] as int?,
    );

    if (success && mounted) {
      SnackBarService.success(context, '📋 Orden guardada en espera.');
    } else if (!success && posProvider.isShiftClosed && mounted) {
      // Mismo tratamiento de seguridad que en checkout: turno cerrado remotamente
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.red.shade50,
          title: Row(
            children: [
              Icon(Icons.lock_clock, color: Colors.red.shade700, size: 28),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Turno Cerrado',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                posProvider.errorMessage ??
                    'El turno de caja fue cerrado desde otra terminal.',
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 12),
              Text(
                'La sesión actual ya no es válida. Será redirigido al inicio para actualizar el estado de la caja.',
                style: TextStyle(fontSize: 13, color: Colors.red.shade700),
              ),
            ],
          ),
          actions: [
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
    _searchFocusNode.requestFocus();
  }

  // ────────────────────────────────────────────────────────────────
  // MODAL DE ÓRDENES PENDIENTES
  // ────────────────────────────────────────────────────────────────
  Future<void> _handleDeletePendingOrder(int saleId, PosProvider posProvider,
      {StateSetter? setStateDialog}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anular Orden en Espera',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: Text(
            '¿Desea anular la orden #$saleId?\nEsta acción devolverá los productos al stock físico y no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete, size: 18),
            label: const Text('Anular'),
          ),
        ],
      ),
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
            _searchFocusNode.requestFocus();
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
    return TweenAnimationBuilder<double>(
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
    );
  }

  Widget _buildPendingOrdersOverlay(PosProvider posProvider) {
    return StatefulBuilder(
      builder: (context, setOverlayState) {
        final pendingSales = posProvider.pendingSales;

        Widget content = CompositedTransformFollower(
          link: _pendingOrdersLayerLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 8),
          child: Align(
            alignment: Alignment.topRight,
            child: ConstrainedBox(
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
                      // Header con controles internos
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        child: Row(
                          children: [
                            Icon(Icons.pending_actions_rounded,
                                color: Colors.orange.shade700, size: 24),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text('Órdenes en Espera',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18)),
                            ),
                            // PIN con setOverlayState para no romper el layout global
                            IconButton(
                              icon: Icon(
                                _isPendingPinned
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                                size: 20,
                                color: _isPendingPinned
                                    ? Colors.blueAccent
                                    : Colors.grey,
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
                            IconButton(
                              icon: const Icon(Icons.refresh,
                                  size: 20, color: Colors.blueGrey),
                              tooltip:
                                  null, // Parche: eliminamos el tooltip que causa el crash
                              onPressed: () async {
                                await posProvider.loadPendingSales();
                                if (context.mounted) setOverlayState(() {});
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              tooltip: null,
                              onPressed: () =>
                                  _pendingOrdersPortalController.hide(),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Flexible(
                        child: pendingSales.isEmpty
                            ? _buildEmptyPendingState()
                            : _buildPendingOrdersList(
                                pendingSales, posProvider),
                      ),
                    ],
                  ),
                ),
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
                          Text('\$${total.toCurrency()}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
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
                        _searchFocusNode.requestFocus();
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
    return Scaffold(
      appBar: GlobalAppBar(
        currentRoute: '/pos',
        extraAction: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: 'Gastos y Mov. de Caja',
              child: InkWell(
                onTap: () {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => const frontend_desktop_cash_movements_dialog.MovementFormDialog(),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E88E5).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF1E88E5).withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.account_balance_wallet_outlined, size: 22, color: Color(0xFF1E88E5)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Consumer<PosProvider>(
              builder: (ctx, pos, _) {
                final count = pos.pendingCount;
                return TapRegion(
                  groupId: 'pending_orders_overlay',
                  child: CompositedTransformTarget(
                    link: _pendingOrdersLayerLink,
                    child: OverlayPortal(
                      controller: _pendingOrdersPortalController,
                      overlayChildBuilder: (context) =>
                          _buildPendingOrdersOverlay(pos),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: TweenAnimationBuilder<double>(
                          key: ValueKey(count > 0),
                          tween: Tween(begin: 0.0, end: count > 0 ? 1.0 : 0.0),
                          duration: const Duration(milliseconds: 1500),
                          curve: Curves.elasticOut,
                          builder: (context, value, child) {
                            return Stack(
                              alignment: Alignment.center,
                              children: [
                                Transform.rotate(
                                  angle: count > 0
                                      ? (0.15 *
                                          (1.0 - value) *
                                          (DateTime.now().second % 5 == 0
                                              ? 1
                                              : 0))
                                      : 0,
                                  child: IconButton(
                                    tooltip: 'Órdenes en Espera',
                                    icon: Icon(
                                      Icons.pending_actions_rounded,
                                      color: count > 0
                                          ? Colors.orange.shade700
                                          : Colors.blueGrey,
                                      size: 28,
                                    ),
                                    onPressed: () =>
                                        _pendingOrdersPortalController.toggle(),
                                  ),
                                ),
                                if (count > 0)
                                  Positioned(
                                    right: 2,
                                    top: 2,
                                    child: IgnorePointer(
                                      child: _buildPendingBadge(count),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
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
                      _searchFocusNode.requestFocus();
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
                      _searchFocusNode.requestFocus();
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
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shopping_cart_outlined, size: 20, color: Colors.blueAccent),
                    SizedBox(width: 8),
                    Text('Ticket Actual',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  ],
                ),
                Row(
                  children: [
                    if (pos.cart.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.delete_sweep, color: Colors.red),
                        tooltip: 'Vaciar Carrito',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('Vaciar Carrito'),
                              content: const Text('¿Deseas quitar todos los productos y vaciar el carrito?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                                FilledButton(
                                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                  onPressed: () => Navigator.pop(c, true),
                                  child: const Text('Vaciar'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            pos.clearCart();
                            _searchFocusNode.requestFocus();
                          }
                        },
                      ),
                    const SizedBox(width: 8),
                    const Icon(Icons.shopping_cart),
                  ],
                ),
              ],
            ),
          ),

          // Lista de ítems
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: PosWatermarkLogo(size: 260),
                ),
                if (pos.cart.isEmpty)
                  const Center(
                    child: Text('El carrito está vacío',
                        style: TextStyle(color: Colors.grey)),
                  )
                else
                  ListView.separated(
                    itemCount: pos.cart.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = pos.cart[index];
                      final String qtyDisplay = item.product.isSoldByWeight
                          ? item.quantity.toQty()
                          : item.quantity.toInt().toString();

                      return ListTile(
                        title: Text(item.product.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (item.unitPrice != item.product.sellingPrice)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6.0),
                                    child: Text(
                                      '\$${item.product.sellingPrice.toCurrency()}',
                                      style: const TextStyle(
                                        decoration: TextDecoration.lineThrough,
                                        color: Colors.grey,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                Text(
                                  '$qtyDisplay x \$${item.unitPrice.toCurrency()}',
                                  style: TextStyle(
                                    fontWeight: item.unitPrice !=
                                            item.product.sellingPrice
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: item.unitPrice >
                                            item.product.sellingPrice
                                        ? Colors.red.shade700
                                        : (item.unitPrice <
                                                item.product.sellingPrice
                                            ? Colors.green.shade700
                                            : Colors.black87),
                                  ),
                                ),
                              ],
                            ),
                            if (item.hasActiveOffer)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: const Color(0xFF7B1FA2).withValues(alpha: 0.10),
                                    border: Border.all(
                                        color: const Color(0xFF7B1FA2).withValues(alpha: 0.35)),
                                    borderRadius: BorderRadius.circular(4)),
                                child: Text('🏷️ ${item.offerBadgeLabel}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF7B1FA2),
                                        fontWeight: FontWeight.bold)),
                              )
                            else if (item.activeTier == PriceTier.wholesale)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    border:
                                        Border.all(color: Colors.blue.shade300),
                                    borderRadius: BorderRadius.circular(4)),
                                child: Text('🏷️ Lista Mayorista Aplicada',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.blue.shade800,
                                        fontWeight: FontWeight.bold)),
                              )
                            else if (item.activeTier == PriceTier.card)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    border: Border.all(
                                        color: Colors.orange.shade300),
                                    borderRadius: BorderRadius.circular(4)),
                                child: Text('💳 Recargo Tarjeta',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.orange.shade800,
                                        fontWeight: FontWeight.bold)),
                              )
                            else if (item.activeTier == PriceTier.custom)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: Colors.purple.shade50,
                                    border: Border.all(
                                        color: Colors.purple.shade300),
                                    borderRadius: BorderRadius.circular(4)),
                                child: Text(
                                    '🏷️ Lista: ${item.customTierLabel ?? 'Personalizada'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.purple.shade800,
                                        fontWeight: FontWeight.bold)),
                              )
                            else if (item.product
                                        .getApplicableTier(item.quantity) !=
                                    null &&
                                item.unitPrice < item.product.sellingPrice)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    border: Border.all(
                                        color: Colors.green.shade300),
                                    borderRadius: BorderRadius.circular(4)),
                                child: Text(
                                  '📦 Desc. Volumétrico (x${(item.product.getApplicableTier(item.quantity)!['min_quantity'] as num).toQty()})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.green.shade800,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            _CartItemStockIndicator(item: item),
                          ],
                        ),
                        trailing: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (item.product.isSoldByWeight)
                                IconButton(
                                  icon: const Icon(Icons.scale_outlined,
                                      color: Colors.blue),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  tooltip: 'Editar peso',
                                  onPressed: () {
                                    _showEditCartItemModal(item, pos);
                                  },
                                )
                              else ...[
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline,
                                      color: Colors.grey),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  tooltip: 'Disminuir',
                                  onPressed: () {
                                    if (item.quantity > 1) {
                                      pos.updateQuantity(item, item.quantity - 1);
                                    } else {
                                      pos.removeFromCart(item);
                                    }
                                    _searchFocusNode.requestFocus();
                                  },
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline,
                                      color: Colors.blue),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  tooltip: 'Aumentar',
                                  onPressed: () {
                                    pos.updateQuantity(item, item.quantity + 1);
                                    _searchFocusNode.requestFocus();
                                  },
                                ),
                              ],
                              const SizedBox(width: 16),
                              Text('\$${item.subtotal.toCurrency()}',
                                  style: const TextStyle(fontSize: 16)),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () {
                                  pos.removeFromCart(item);
                                  _searchFocusNode.requestFocus();
                                },
                              )
                            ],
                          ),
                        ),
                        onTap: () {
                          _showEditCartItemModal(item, pos);
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
                        .read<SettingsProvider>()
                        .settings
                        ?.features
                        .multiplePrices ==
                    true &&
                    context
                        .read<SettingsProvider>()
                        .settings
                        ?.enableAdvancedPriceTiers ==
                    true)
                  Builder(builder: (_) {
                    final settings = context.read<SettingsProvider>().settings;
                    final customTiers = settings?.customPriceTiers ?? [];

                    // Valor a mostrar en el dropdown: si es custom, usamos el label
                    // Si es custom pero sin label (inconsistencia), caemos a base
                    final currentValue = pos.activeTier == PriceTier.custom
                        ? (pos.customTierLabel != null
                            ? 'custom_${pos.customTierLabel}'
                            : 'base')
                        : pos.activeTier.name;

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
                                        items: [
                                          const DropdownMenuItem(
                                              value: 'base',
                                              child: Text('🏪 Minorista (Base)')),
                                          const DropdownMenuItem(
                                              value: 'wholesale',
                                              child: Text('🏭 Mayorista')),
                                          const DropdownMenuItem(
                                              value: 'card', child: Text('💳 Tarjeta')),
                                          // Listas personalizadas dinámicas del backend
                                          ...customTiers.map((t) {
                                            final name =
                                                t['name']?.toString() ?? 'Custom';
                                            final mod =
                                                (t['modifier'] as num?)?.toDouble() ??
                                                    0.0;
                                            final sign = mod >= 0 ? '+' : '';
                                            return DropdownMenuItem(
                                              value: 'custom_$name',
                                              child: Text(
                                                  '🏷️ $name ($sign${mod.toStringAsFixed(0)}%)'),
                                            );
                                          }),
                                        ],
                                        onChanged: (String? val) {
                                          if (val == null) return;
                                          if (val == 'base') {
                                            pos.setPriceTier(PriceTier.base);
                                          } else if (val == 'wholesale') {
                                            pos.setPriceTier(
                                              PriceTier.wholesale,
                                              wholesaleFactor: settings != null
                                                  ? 1 +
                                                      (settings
                                                              .globalWholesalePercentage /
                                                          100)
                                                  : null,
                                              cardFactor: settings != null
                                                  ? 1 +
                                                      (settings.globalCardPercentage /
                                                          100)
                                                  : null,
                                            );
                                          } else if (val == 'card') {
                                            pos.setPriceTier(
                                              PriceTier.card,
                                              wholesaleFactor: settings != null
                                                  ? 1 +
                                                      (settings
                                                              .globalWholesalePercentage /
                                                          100)
                                                  : null,
                                              cardFactor: settings != null
                                                  ? 1 +
                                                      (settings.globalCardPercentage /
                                                          100)
                                                  : null,
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
                                            if (mounted) _searchFocusNode.requestFocus();
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
                                        _searchFocusNode.requestFocus();
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
                  }),

                // ── Resumen Financiero: Subtotal, Ahorro/Descuentos y Total ──────────────
                const PosFinancialSummary(),
                const SizedBox(height: 8),

                // ── Atajos Rápidos Modernos (Espera, Presupuestos, Clientes, Ofertas) ──
                PosQuickActionButtons(
                  onHoldOrder: _handleHoldOrder,
                  onOpenPendingList: () => _pendingOrdersPortalController.toggle(),
                  onAfterDialogClosed: () {
                    if (mounted) _searchFocusNode.requestFocus();
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

  List<Product> _getFilteredProducts(CatalogProvider catalog, OfferProvider offerProv, LocalTerminalProvider localTerminal) {
    if (_searchQuery.isNotEmpty) {
      return _searchResults;
    }

    final settingsProv = Provider.of<SettingsProvider?>(context, listen: false);
    final demoteOutOfStock = settingsProv?.settings?.posDemoteOutOfStock ?? false;

    List<Product> filtered = List<Product>.from(catalog.products);

    if (_quickAccessFilter == 'pinned') {
      filtered = filtered.where((p) => localTerminal.pinnedProductIds.contains(p.id)).toList();
    } else if (_quickAccessFilter == 'top_sellers') {
      filtered = filtered.where((p) => p.salesCount > 0).toList();
    } else if (_quickAccessFilter == 'offers') {
      filtered = filtered.where((p) => offerProv.getActiveOfferForProduct(p.id, basePrice: p.sellingPrice) != null).toList();
    } else if (_quickAccessFilter == 'weight') {
      filtered = filtered.where((p) => p.isSoldByWeight).toList();
    } else if (_quickAccessFilter.startsWith('cat_')) {
      final categoryName = _quickAccessFilter.substring(4).trim();
      filtered = filtered.where((p) => p.category?.name.trim() == categoryName).toList();
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
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
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
    final localTerminal = Provider.of<LocalTerminalProvider>(context, listen: false);
    final displayItems = _getFilteredProducts(catalog, offerProv, localTerminal);
    final isSearchEmpty = _searchController.text.trim().isEmpty;

    // F9 / F12 → Cobrar directo (funciona siempre que haya ítems en el carrito)
    if (event.logicalKey == LogicalKeyboardKey.f9 || event.logicalKey == LogicalKeyboardKey.f12) {
      if (posProvider.cart.isNotEmpty && !posProvider.isLoading && !_isCheckingOut) {
        _handleCheckout();
      }
      return true;
    }

    // F4 → Poner en Espera directo
    if (event.logicalKey == LogicalKeyboardKey.f4) {
      if (posProvider.cart.isNotEmpty && !posProvider.isLoading) {
        _handleHoldOrder();
      }
      return true;
    }

    // F6 → Abrir selector rápido de clientes
    if (event.logicalKey == LogicalKeyboardKey.f6) {
      final settingsProv = Provider.of<SettingsProvider>(context, listen: false);
      final hasCurrentAccounts = settingsProv.settings?.features.currentAccounts ?? false;
      if (!hasCurrentAccounts) {
        PlanUpgradeDialog.show(
          context,
          featureName: 'Gestión de Clientes y Cuentas Corrientes',
          description:
              'La gestión de clientes con cuenta corriente y saldo a favor está disponible en el Plan Ferretería/Corralón o como módulo adicional.',
        ).then((_) {
          if (mounted) _searchFocusNode.requestFocus();
        });
      } else {
        showDialog(
          context: context,
          builder: (ctx) => const PosQuickCustomerDialog(),
        ).then((_) {
          if (mounted) _searchFocusNode.requestFocus();
        });
      }
      return true;
    }

    // Escape → Cerrar overlay de órdenes pendientes o limpiar buscador/resetear filtro
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_pendingOrdersPortalController.isShowing) {
        _pendingOrdersPortalController.hide();
        _searchFocusNode.requestFocus();
        return true;
      }
      if (_searchController.text.isNotEmpty) {
        _searchController.clear();
        _onPosSearchChanged('');
        _searchFocusNode.requestFocus();
      } else if (_quickAccessFilter != 'all') {
        setState(() {
          _quickAccessFilter = 'all';
        });
        _searchFocusNode.requestFocus();
      }
      return true;
    }

    // Atajos que solo funcionan cuando el buscador está vacío
    if (isSearchEmpty) {
      // Ctrl + 1..9 para seleccionar productos (anti-AltCodes de Windows)
      final isControlPressed = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) ||
                               HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight);

      if (isControlPressed) {
        final key = event.logicalKey;
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

      // Enter / NumpadEnter → Cobrar siempre que el buscador esté vacío
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
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
          if (!lastItem.product.isSoldByWeight) {
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
          if (!lastItem.product.isSoldByWeight) {
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

  Widget _buildRightPanel() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 580;
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Barra de búsqueda con búsqueda server-side vía API
              TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
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
                      : 'Escribir nombre o escanear código... (Enter: Cobrar · F1: Atajos)',
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
                          onPressed: () {
                            _searchController.clear();
                            _onPosSearchChanged('');
                            _searchFocusNode.requestFocus();
                          },
                        )
                      : null,
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

              const SizedBox(height: 16),

              // ── Header dinámico ────────────────────────────────────────────
              if (_searchQuery.isEmpty) ...[
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Acceso Rápido',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(
                            'Fijados · Más vendidos · Productos por peso · Orden alfabético',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
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
                            context.read<CatalogProvider>().loadProducts(page: 1, search: '', sortBy: '', perPage: 500);
                            final offerProv = context.read<OfferProvider>();
                            final posProv = context.read<PosProvider>();
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
                  ],
                ),
              ],
          const SizedBox(height: 12),

          // ── Grilla dinámica ────────────────────────────────────────────
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: PosWatermarkLogo(size: 360),
                ),
                Consumer<CatalogProvider>(
                  builder: (context, catalog, _) {
                    if (catalog.isLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final offerProv = context.watch<OfferProvider>();
                    final localTerminal = context.watch<LocalTerminalProvider>();
                    final displayItems = _getFilteredProducts(catalog, offerProv, localTerminal);

                    if (displayItems.isEmpty) {
                      if (_searchQuery.isEmpty && _quickAccessFilter != 'all' && catalog.products.isNotEmpty) {
                        // Filtro activo devuelve 0 ítems pero el catálogo tiene productos
                        String filterName = 'este filtro';
                        if (_quickAccessFilter == 'pinned') {
                          filterName = 'productos fijados';
                        } else if (_quickAccessFilter == 'top_sellers') {
                          filterName = 'más vendidos';
                        } else if (_quickAccessFilter == 'offers') {
                          filterName = 'ofertas activas';
                        } else if (_quickAccessFilter == 'weight') {
                          filterName = 'productos por peso';
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
                                'No hay productos para $filterName',
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
                              const Text('Presá Enter para buscar en el servidor',
                                  style: TextStyle(
                                      color: Colors.blueGrey, fontSize: 13)),
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
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) {
          bool isVoiding = false;
          return StatefulBuilder(
            builder: (context, setState) {
              return Dialog(
                child: SizedBox(
                  width: 900,
                  height: 800,
                  child: Scaffold(
                    appBar: AppBar(
                      title: Text(
                          'Vista Previa Backoffice - Venta #${posProvider.lastSaleId}'),
                      automaticallyImplyLeading: false,
                      actions: [
                        if (isVoiding)
                          Center(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16.0),
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.red),
                              ),
                            ),
                          )
                        else
                          TextButton.icon(
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: dialogCtx,
                                builder: (c) => AlertDialog(
                                  title: const Text('¿Anular Venta?'),
                                  content: const Text(
                                      'Esta acción cancelará el cobro en el sistema y devolverá los productos al carrito.'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(c, false),
                                        child: const Text('NO, VOLVER')),
                                    ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                            foregroundColor: Colors.white),
                                        onPressed: () => Navigator.pop(c, true),
                                        child: const Text('SÍ, ANULAR')),
                                  ],
                                ),
                              );

                              if (confirm == true) {
                                final currentShift = context.read<CashRegisterProvider>().currentShift;
                                if (currentShift == null) {
                                  if (dialogCtx.mounted) {
                                    SnackBarService.error(
                                        dialogCtx, 'Debe haber un turno de caja abierto para anular órdenes.');
                                  }
                                  return;
                                }
                                if (posProvider.lastSaleId <= 0) {
                                  if (dialogCtx.mounted) {
                                    SnackBarService.error(
                                        dialogCtx, 'No hay ID de venta válido para anular.');
                                  }
                                  return;
                                }
                                setState(() {
                                  isVoiding = true;
                                });

                                final hasPermission = await AdminPinDialog.protectAction(
                                  dialogCtx,
                                  action: 'Anulación de Ventas Emitidas',
                                  permissionKey: AppPermissions.voidSales,
                                  onAuthorized: () async {
                                    try {
                                      final success = await posProvider.voidPendingOrder(
                                        posProvider.lastSaleId,
                                        shiftId: currentShift.id,
                                      );
                                      if (!success) {
                                        if (dialogCtx.mounted) {
                                          SnackBarService.error(dialogCtx, 'No se pudo anular la venta: ${posProvider.errorMessage ?? "Error desconocido"}');
                                        }
                                        setState(() {
                                          isVoiding = false;
                                        });
                                        return;
                                      }
                                      // Restaurar carrito al estado previo a la venta
                                      posProvider.restoreLastSaleCart();

                                      if (dialogCtx.mounted) {
                                        SnackBarService.warning(dialogCtx,
                                            'Venta anulada. Los productos han vuelto al carrito.');
                                        Navigator.pop(dialogCtx, 'annulled');
                                      }
                                    } catch (e) {
                                      if (dialogCtx.mounted) {
                                        SnackBarService.error(
                                            dialogCtx, 'Error al anular: $e');
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
                            icon: const Icon(Icons.delete_forever,
                                color: Colors.red),
                            label: const Text('ANULAR COBRO Y VOLVER',
                                style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold)),
                          ),
                        const SizedBox(width: 16),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed:
                              isVoiding ? null : () => Navigator.pop(dialogCtx),
                        ),
                      ],
                    ),
                    body: PdfPreview(
                      build: (format) async => pdfBytes,
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      pdfFileName: 'Comprobante_${posProvider.lastSaleId}.pdf',
                      canDebug: false,
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
          _searchFocusNode.requestFocus();
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

    final hasPinned = localTerminal.pinnedProductIds.isNotEmpty;
    final hasTopSellers = catalog.products.any((p) => p.salesCount > 0);
    final hasOffers = catalog.products.any((p) => offerProv.getActiveOfferForProduct(p.id, basePrice: p.sellingPrice) != null);

    // Si un filtro dinámico queda sin productos asociados, regresar automáticamente a 'all'
    if ((_quickAccessFilter == 'top_sellers' && !hasTopSellers) ||
        (_quickAccessFilter == 'pinned' && !hasPinned) ||
        (_quickAccessFilter == 'offers' && !hasOffers)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _quickAccessFilter = 'all';
          });
        }
      });
    }

    final categories = <String, int>{};
    for (final p in catalog.products) {
      final catName = p.category?.name.trim();
      if (catName != null && catName.isNotEmpty) {
        categories[catName] = (categories[catName] ?? 0) + 1;
      }
    }
    final allCategories = categories.entries.toList()
      ..sort((a, b) {
        final cmp = b.value.compareTo(a.value);
        return cmp != 0 ? cmp : a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });

    // Cálculo elástico del espacio horizontal real descontando chips fijos activos
    final innerWidth = (panelWidth - 32.0).clamp(300.0, 4000.0);
    final systemChipsWidth = 68.0 + // 'Todos'
        (hasPinned ? 102.0 : 0.0) +
        (hasTopSellers ? 130.0 : 0.0) +
        (hasOffers ? 100.0 : 0.0) +
        105.0; // '⚖️ Por Peso'

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
                  _buildFilterChip('⚖️ Por Peso', 'weight', _quickAccessFilter),
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
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _quickAccessFilter = selected ? value : 'all';
          });
          _searchFocusNode.requestFocus();
        },
        selectedColor: Colors.blue.withAlpha(25),
        checkmarkColor: Colors.blueAccent,
        labelStyle: TextStyle(
          color: isSelected ? Colors.blueAccent : Colors.grey.shade700,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
        shape: StadiumBorder(
          side: BorderSide(
            color: isSelected ? Colors.blueAccent : Colors.grey.shade300,
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
                _searchFocusNode.requestFocus();
              }
            : null,
        onSelected: (selected) {
          setState(() {
            _quickAccessFilter = selected ? 'cat_$catName' : 'all';
          });
          _searchFocusNode.requestFocus();
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
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<String>(
        tooltip: 'Ver todas las categorías',
        onSelected: (cat) {
          setState(() {
            _quickAccessFilter = 'cat_$cat';
          });
          _searchFocusNode.requestFocus();
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
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
                Icons.category_outlined,
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
                Icons.arrow_drop_down,
                size: 16,
                color: isAnyOverflowSelected ? Colors.blueAccent : Colors.grey.shade700,
              ),
            ],
          ),
        ),
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

  Widget _buildDynamicCatalogView(List<Product> displayItems, String viewMode) {
    final localTerminal = Provider.of<LocalTerminalProvider>(context, listen: false);
    return PosQuickAccessCatalogView(
      products: displayItems,
      viewMode: viewMode,
      // El ranking Top solo aplica al Acceso Rápido; en búsquedas sería relativo a los resultados.
      showTopRanks: _searchQuery.isEmpty,
      showKeyboardShortcuts: true,
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
        double displayPrice = product.sellingPrice;
        if (pos.activeTier == PriceTier.wholesale) {
          displayPrice = (product.priceWholesale != null && product.priceWholesale! > 0)
            ? product.priceWholesale!
            : product.sellingPrice * pos.wholesaleFactor;
        } else if (pos.activeTier == PriceTier.card) {
          displayPrice = (product.priceCard != null && product.priceCard! > 0)
            ? product.priceCard!
            : product.sellingPrice * pos.cardFactor;
        } else if (pos.activeTier == PriceTier.custom) {
          displayPrice = product.sellingPrice * pos.currentCustomFactor;
        }

        final promoPrice = offerProv.getDiscountedPrice(product);
        final hasPromo = promoPrice != null && promoPrice > 0 && promoPrice < displayPrice;
        final originalPrice = displayPrice;
        if (hasPromo) {
          displayPrice = promoPrice;
        }

        final formattedMain = isByWeight
            ? '\$${displayPrice.toCurrency()}/Kg'
            : '\$${displayPrice.toCurrency()}';
        final isRightAligned = viewMode == 'list' || viewMode == 'compact';

        if (hasPromo) {
          final formattedOrig = isByWeight
              ? '\$${originalPrice.toCurrency()}/Kg'
              : '\$${originalPrice.toCurrency()}';

          // En modo lista mantenemos el diseño horizontal limpio que ya tiene buen espacio;
          // en tarjetas (grandes/medianas) y botones compactos apilamos verticalmente
          // para que el precio de oferta se vea grande y nunca se comprima.
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
                      color: const Color(0xFF7B1FA2),
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
                    color: const Color(0xFF7B1FA2),
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

}

// ── Componentes Encapsulados ──────────────────────────────────────────────

class _CartItemStockIndicator extends StatelessWidget {
  final CartItem item;

  const _CartItemStockIndicator({required this.item});

  @override
  Widget build(BuildContext context) {
    if (item.product.isCombo) return const SizedBox.shrink();

    // 💡 IMPORTANTE: Todo context.select() debe estar siempre en la raíz del build, NUNCA condicionado.
    final status = context.select<InventoryAlertsProvider, String?>(
        (p) => p.getAlertStatusForProduct(item.product.id));
    final hasPredictive = context
        .select<SettingsProvider, bool>((s) => s.features.predictiveAlerts);

    // 1. Verificación en tiempo real (Proyección Local)
    // Calcula cómo quedará el stock si aprueba esta venta
    final projectedStock = item.product.stock - item.quantity;
    final minStock = item.product.minStock ?? 0;
    final bool isCriticalLocally = projectedStock <= minStock;

    // 2. Estado persistente del servidor (Backend)
    final bool isCriticalBackend = status == 'out_of_stock';
    final bool isPredictiveBackend = status == 'predictive';

    final bool isCritical = isCriticalLocally || isCriticalBackend;

    // Si no es crítico y no hay estado predictivo del server, ocultamos
    if (!isCritical && !isPredictiveBackend) return const SizedBox.shrink();

    // 🔒 CANDADO 2: La alerta predictiva naranja solo se muestra con el addon activo.
    if (!isCritical && isPredictiveBackend && !hasPredictive) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isCritical ? Colors.red.shade50 : Colors.orange.shade50,
        border: Border.all(
            color: isCritical ? Colors.red.shade200 : Colors.orange.shade200),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCritical ? Icons.error_outline : Icons.warning_amber_rounded,
            color: isCritical ? Colors.red.shade600 : Colors.orange.shade700,
            size: 10,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              isCritical
                  ? '🔴 Crítico (Quedan: ${projectedStock.toInt()} u)'
                  : '🟠 Quiebre en <3d',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isCritical ? Colors.red.shade700 : Colors.orange.shade800,
              ),
            ),
          ),
        ],
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
    );
  }
}

/// Scope con ciclo de vida propio para gestionar y liberar TextEditingController
/// automáticamente al desmontarse la ruta del diálogo y proteger callbacks asíncronos.
class _ManagedControllerScope extends StatefulWidget {
  final String initialText;
  final Widget Function(
    BuildContext context,
    TextEditingController controller,
    bool Function() isDialogMounted,
  ) builder;

  const _ManagedControllerScope({
    this.initialText = '',
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
    _controller = TextEditingController(text: widget.initialText);
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

