import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pos_provider.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import '../widgets/checkout_dialog.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({Key? key}) : super(key: key);

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
      // Siempre cargar la lista COMPLETA al entrar a POS, ignorando cualquier
      // búsqueda que el módulo de Catálogo haya dejado activa en el provider.
      Provider.of<CatalogProvider>(context, listen: false).loadProducts(page: 1, search: '');
      // Cargar el contador de órdenes pendientes al abrir el POS
      Provider.of<PosProvider>(context, listen: false).loadPendingSales();
      
      // Polling veloz (5 seg) para recepción casi-inmediata de órdenes en red local/multicaja
      _pendingOrdersTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (mounted) {
          Provider.of<PosProvider>(context, listen: false).loadPendingSales();
        }
      });
    });
  }

  @override
  void dispose() {
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
      final results = await Provider.of<PosProvider>(context, listen: false).search(query);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    });
  }

  void _onProductScannedOrSearched(String query) async {
    if (query.trim().isEmpty) return;
    String cleanQuery = query.trim();
    
    // --- LÓGICA EAN-13 BALANZA ETIQUETADORA (PRECIO EMBEBIDO) ---
    bool isEan13Scale = cleanQuery.length == 13 && cleanQuery.startsWith('2');
    double embeddedPrice = 0.0;
    
    if (isEan13Scale) {
      // Formato: 1 (Prefijo) + 5 (PLU) + 6 (Precio en pesos) + 1 (CheckDigit)
      final itemCodeStr = cleanQuery.substring(1, 6); // 5 dígitos de PLU
      final priceStr = cleanQuery.substring(6, 12);   // 6 dígitos de Precio Entero
      cleanQuery = int.parse(itemCodeStr).toString(); 
      embeddedPrice = double.parse(priceStr);
    }
    
    final posProvider = Provider.of<PosProvider>(context, listen: false);
    final results = await posProvider.search(cleanQuery);
    
    if (!mounted) return;

    if (results.isEmpty) {
      SnackBarService.error(context, 'Producto no encontrado: "$cleanQuery"');
    } else if (isEan13Scale) {
      final product = results.first;
      double calcWeight = 0.0;
      
      if (product.sellingPrice > 0) {
        calcWeight = embeddedPrice / product.sellingPrice;
      } else {
        calcWeight = 1.0; // Fallback de seguridad si el producto tiene precio base 0
      }
      
      // EAN-13 balanza: agregar directo con peso equivalente
      posProvider.submitWeighedProduct(product, calcWeight);
    } else if (results.length == 1) {
      // Un único resultado: agregar directo
      _handleProductSelection(results.first);
    } else {
      // Múltiples resultados: mostrar selector
      await _showProductPickerDialog(results, cleanQuery);
    }

    _searchController.clear();
    setState(() => _searchQuery = '');
    _searchFocusNode.requestFocus();
  }

  /// Diálogo para seleccionar entre múltiples resultados de búsqueda
  Future<void> _showProductPickerDialog(List<Product> results, String query) async {
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
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                  backgroundColor: p.isSoldByWeight ? Colors.orange.shade100 : Colors.blue.shade50,
                  child: Icon(
                    p.isSoldByWeight ? Icons.scale_rounded : Icons.inventory_2_outlined,
                    color: p.isSoldByWeight ? Colors.orange.shade700 : Colors.blue.shade700,
                    size: 20,
                  ),
                ),
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  p.isSoldByWeight ? 'Por Kg · \$${p.sellingPrice.toStringAsFixed(2)}/Kg' : '\$${p.sellingPrice.toStringAsFixed(2)}',
                ),
                trailing: const Icon(Icons.add_circle_outline, color: Colors.green),
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
    
    final success = posProvider.requestAddToCart(product);
    if (!success) {
      // Es producto por peso, pedir peso por Modal
      _showWeightModal(product, posProvider);
    }
  }

  void _showWeightModal(Product product, PosProvider provider) {
    final weightController = TextEditingController();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return ValueListenableBuilder<TextEditingValue>(
          valueListenable: weightController,
          builder: (context, value, child) {
            final isValid = value.text.trim().isNotEmpty && double.tryParse(value.text.replaceAll(',', '.')) != null && double.parse(value.text.replaceAll(',', '.')) > 0;
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text('Ingresar Peso (Kg) - ${product.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              content: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: TextField(
                  controller: weightController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Peso Exacto (Ej: 1.500)',
                    hintText: '0.000',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixText: 'KG',
                    helperText: 'Ejemplo: 0.5 = 500 gramos',
                  ),
                  onSubmitted: (val) {
                    if (isValid) _processWeight(val, product, provider, context);
                  },
                ),
              ),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              actions: [
                Consumer<SettingsProvider>(
                  builder: (ctx, settingsProvider, _) {
                    final comPort = settingsProvider.settings?.comPortScale;
                    if (comPort == null || comPort.isEmpty) {
                      return const SizedBox.shrink(); // Sin balanza local
                    }
                    return OutlinedButton.icon(
                      onPressed: () => _readWeightFromScale(comPort, weightController),
                      icon: const Icon(Icons.scale_rounded, color: Colors.blueGrey),
                      label: const Text('Leer Balanza'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blueGrey,
                        side: const BorderSide(color: Colors.blueGrey),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    );
                  },
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
                ),
                FilledButton(
                  onPressed: isValid ? () {
                    _processWeight(weightController.text, product, provider, context);
                  } : null,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Agregar'),
                )
              ],
            );
          }
        );
      }
    ).then((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _readWeightFromScale(String comPort, TextEditingController controller) async {
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
        if (mounted) SnackBarService.error(context, 'No se pudo abrir el puerto $comPort. ${err != null ? err.message : ""}');
        return;
      }

      // Configuración estándar de balanzas (ej. Kretz/Systel en Argentina)
      final config = port.config;
      config.baudRate = 9600;
      config.bits = 8;
      config.stopBits = 1;
      config.parity = 0; // SerialPortParity.none
      port.config = config;

      final reader = SerialPortReader(port, timeout: 500);
      String accumulatedData = '';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Esperando peso estable... (1.5 seg)'), duration: Duration(milliseconds: 1500)),
        );
      }

      // Escuchar el stream durante 1.5 segundos
      final subscription = reader.stream.listen((data) {
        accumulatedData += String.fromCharCodes(data);
      });

      await Future.delayed(const Duration(milliseconds: 1500));

      subscription.cancel();
      port.close();
      port.dispose();

      // Buscar si la balanza mandó un valor numérico continuo
      if (accumulatedData.isNotEmpty) {
        final RegExp weightRegex = RegExp(r'(\d+[\.,]\d+)');
        final matches = weightRegex.allMatches(accumulatedData);
        
        if (matches.isNotEmpty) {
          String weightStr = matches.last.group(0)!;
          weightStr = weightStr.replaceAll(',', '.');
          
          if (mounted) {
            controller.text = weightStr;
            SnackBarService.success(context, 'Lectura exitosa: $weightStr Kg');
          }
        } else {
          if (mounted) {
            SnackBarService.error(context, 'No se detectó un peso numérico. Datos: "$accumulatedData"');
          }
        }
      } else {
        if (mounted) {
          SnackBarService.error(context, 'No se recibieron datos. Revise la conexión de la balanza en $comPort.');
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarService.error(context, 'Error en el puerto $comPort: $e');
      }
    }
  }

  void _processWeight(String value, Product product, PosProvider provider, BuildContext dialogContext) {
    // Reemplaza comas por puntos en caso de que teclados latinos obligen coma
    String sanitizedValue = value.replaceAll(',', '.');
    final weight = double.tryParse(sanitizedValue);
    
    // Validación básica: El peso debe ser positivo y menor a una exageración (Ej: >1000Kg es raro en POS base)
    if (weight != null && weight > 0 && weight < 1000) {
      provider.submitWeighedProduct(product, weight);
      Navigator.pop(dialogContext);
    } else {
      SnackBarService.error(dialogContext, 'Por favor, ingrese un peso válido en Kg.');
    }
  }

  void _showEditCartItemModal(dynamic cartItem, PosProvider provider) {
    final qtyController = TextEditingController(
      text: cartItem.product.isSoldByWeight 
        ? cartItem.quantity.toStringAsFixed(3) 
        : cartItem.quantity.toInt().toString()
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return ValueListenableBuilder<TextEditingValue>(
          valueListenable: qtyController,
          builder: (context, value, child) {
            final isValid = value.text.trim().isNotEmpty && double.tryParse(value.text.replaceAll(',', '.')) != null && double.parse(value.text.replaceAll(',', '.')) > 0;
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text('Editar Cantidad - ${cartItem.product.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              content: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: TextField(
                  controller: qtyController,
                  autofocus: true,
                  keyboardType: cartItem.product.isSoldByWeight 
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.number,
                  decoration: InputDecoration(
                    labelText: cartItem.product.isSoldByWeight ? 'Peso Exacto (Ej: 1.500)' : 'Cantidad (Unidades)',
                    hintText: cartItem.product.isSoldByWeight ? '0.000' : '1',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixText: cartItem.product.isSoldByWeight ? 'KG' : 'UN',
                    helperText: cartItem.product.isSoldByWeight ? 'Ejemplo: 0.5 = 500 gramos' : null,
                  ),
                  onSubmitted: (val) {
                    if (isValid) _processCartItemEdit(val, cartItem, provider, context);
                  },
                ),
              ),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              actions: [
                if (cartItem.product.isSoldByWeight)
                  Consumer<SettingsProvider>(
                    builder: (ctx, settingsProvider, _) {
                      final comPort = settingsProvider.settings?.comPortScale;
                      if (comPort == null || comPort.isEmpty) {
                        return const SizedBox.shrink(); // Sin balanza local
                      }
                      return OutlinedButton.icon(
                        onPressed: () => _readWeightFromScale(comPort, qtyController),
                        icon: const Icon(Icons.scale_rounded, color: Colors.blueGrey),
                        label: const Text('Leer Balanza'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blueGrey,
                          side: const BorderSide(color: Colors.blueGrey),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      );
                    },
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
                ),
                FilledButton(
                  onPressed: isValid ? () {
                    _processCartItemEdit(qtyController.text, cartItem, provider, context);
                  } : null,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Actualizar'),
                )
              ],
            );
          }
        );
      }
    ).then((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _processCartItemEdit(String value, dynamic cartItem, PosProvider provider, BuildContext dialogContext) {
    String sanitizedValue = value.replaceAll(',', '.');
    final newQuantity = double.tryParse(sanitizedValue);

    if (newQuantity != null && newQuantity > 0) {
      // Si el producto NO es pesado, forzar entero por si acaso.
      final finalQuantity = cartItem.product.isSoldByWeight ? newQuantity : newQuantity.toInt().toDouble();
      
      provider.updateQuantity(cartItem, finalQuantity);
      Navigator.pop(dialogContext);
    } else {
      SnackBarService.error(dialogContext, 'Por favor, ingrese una cantidad válida mayor a 0.');
    }
  }

  // Helper de conversión segura String/num → double
  double _toDouble(dynamic value) =>
      value == null ? 0.0 : double.tryParse(value.toString()) ?? 0.0;

  void _handleCheckout() async {
    final posProvider = Provider.of<PosProvider>(context, listen: false);
    final cashRegisterProvider = Provider.of<CashRegisterProvider>(context, listen: false);
    
    final currentShift = cashRegisterProvider.currentShift;
    if (currentShift == null || !currentShift.isOpen) {
      SnackBarService.error(context, 'No hay turno de caja abierto.');
      return;
    }

    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CheckoutDialog(total: posProvider.cartTotal),
    );
    
    if (success == true) {
      if (mounted) {
        // 1. PRIORIDAD ABSOLUTA: Mostrar confirmación visual de inmediato
        SnackBarService.success(context, '¡Venta registrada con éxito!');
        
        // 2. ACTUALIZACIÓN LOCAL (IN-MEMORY):
        // Reordenamos el "Acceso Rápido" al instante sin depender de la red.
        final catalogProvider = Provider.of<CatalogProvider>(context, listen: false);
        final Map<int, int> soldItems = {};
        for (var item in posProvider.cart) {
          soldItems[item.product.id] = (soldItems[item.product.id] ?? 0) + 1;
        }
        catalogProvider.updateProductSalesCountLocally(soldItems);

        // 3. REFRESCO SILENCIOSO (FIRE-AND-FORGET):
        // Intentamos sincronizar con el server pero sin mostrar errores al cajero.
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            catalogProvider.loadProducts(page: 1, search: '').catchError((e) {
              debugPrint('Refresco silencioso falló (esperado en redes inestables): $e');
            });
          }
        });
      }
    }
    
    _searchFocusNode.requestFocus();
  }

  // ────────────────────────────────────────────────────────────────
  // PREVENTA: Dejar el carrito actual en espera (status = pending)
  // ────────────────────────────────────────────────────────────────
  void _handleHoldOrder() async {
    final posProvider = Provider.of<PosProvider>(context, listen: false);
    final cashRegisterProvider = Provider.of<CashRegisterProvider>(context, listen: false);
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
    } else if (!success && mounted) {
      SnackBarService.error(context, posProvider.errorMessage ?? 'No se pudo guardar la orden.');
    }
    _searchFocusNode.requestFocus();
  }

  // ────────────────────────────────────────────────────────────────
  // MODAL DE ÓRDENES PENDIENTES
  // ────────────────────────────────────────────────────────────────
  Future<void> _handleDeletePendingOrder(int saleId, PosProvider posProvider, {StateSetter? setStateDialog}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anular Orden en Espera', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: Text('¿Desea anular la orden #$saleId?\nEsta acción devolverá los productos al stock físico y no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
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
      final success = await posProvider.voidPendingOrder(saleId);
      if (mounted) {
        if (success) {
          SnackBarService.success(context, 'Orden #$saleId anulada. El stock fue restaurado.');
          if (setStateDialog != null) {
            setStateDialog(() {});
          } else {
            _searchFocusNode.requestFocus();
          }
        } else {
          SnackBarService.error(context, posProvider.errorMessage ?? 'Error al anular orden');
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
                BoxShadow(color: Colors.redAccent.withOpacity(0.4), blurRadius: 4, spreadRadius: 1),
              ],
            ),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
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
                shadowColor: Colors.black.withOpacity(0.3),
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
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        child: Row(
                          children: [
                            Icon(Icons.pending_actions_rounded, color: Colors.orange.shade700, size: 24),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text('Órdenes en Espera', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            ),
                            // PIN con setOverlayState para no romper el layout global
                            IconButton(
                              icon: Icon(
                                _isPendingPinned ? Icons.push_pin : Icons.push_pin_outlined,
                                size: 20,
                                color: _isPendingPinned ? Colors.blueAccent : Colors.grey,
                              ),
                              tooltip: null, // Parche: eliminamos el tooltip que causa el crash
                              onPressed: () {
                                setOverlayState(() {
                                  _isPendingPinned = !_isPendingPinned;
                                });
                                setState(() {}); 
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh, size: 20, color: Colors.blueGrey),
                              tooltip: null, // Parche: eliminamos el tooltip que causa el crash
                              onPressed: () async {
                                await posProvider.loadPendingSales();
                                if (context.mounted) setOverlayState(() {});
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              tooltip: null,
                              onPressed: () => _pendingOrdersPortalController.hide(),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Flexible(
                        child: pendingSales.isEmpty
                            ? _buildEmptyPendingState()
                            : _buildPendingOrdersList(pendingSales, posProvider),
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
          Text('¡No hay órdenes!', style: TextStyle(fontSize: 16, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildPendingOrdersList(List<dynamic> pendingSales, PosProvider posProvider) {
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade100)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.orange.shade100,
                      child: Text('#$saleId', style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold, fontSize: 10)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('\$${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Row(
                            children: [
                              Icon(Icons.access_time, size: 10, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Builder(
                                builder: (context) {
                                  final createdAt = sale['created_at'] as String?;
                                  if (createdAt == null) return const Text('--:--', style: TextStyle(fontSize: 11));
                                  
                                  // Forzamos formato ISO UTC (YYYY-MM-DDTHH:mm:ssZ) para que .toLocal() funcione
                                  final isoStr = createdAt.contains('T') ? createdAt : createdAt.replaceFirst(' ', 'T');
                                  final utcStr = isoStr.endsWith('Z') ? isoStr : '${isoStr}Z';
                                  
                                  final dt = DateTime.tryParse(utcStr)?.toLocal();
                                  if (dt == null) return Text(createdAt.substring(11, 16), style: const TextStyle(fontSize: 11));
                                  
                                  return Text(
                                    "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}",
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                              const Text('•', style: TextStyle(color: Colors.grey, fontSize: 10)),
                              const SizedBox(width: 8),
                              Text('$itemCount ítem(s)', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
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
                      child: const Text('Anular', style: TextStyle(color: Colors.red, fontSize: 12)),
                      onPressed: () => _handleDeletePendingOrder(saleId, posProvider),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade50,
                        foregroundColor: Colors.orange.shade900,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        _pendingOrdersPortalController.hide();
                        posProvider.recallOrderToCart(sale);
                        SnackBarService.success(context, '📥 Orden #$saleId cargada al carrito.');
                        _searchFocusNode.requestFocus();
                      },
                      child: const Text('RECUPERAR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
        extraAction: Consumer<PosProvider>(
          builder: (ctx, pos, _) {
            final count = pos.pendingCount;
            return TapRegion(
              groupId: 'pending_orders_overlay',
              child: CompositedTransformTarget(
                link: _pendingOrdersLayerLink,
                child: OverlayPortal(
                  controller: _pendingOrdersPortalController,
                  overlayChildBuilder: (context) => _buildPendingOrdersOverlay(pos),
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
                              angle: count > 0 ? (0.15 * (1.0 - value) * (DateTime.now().second % 5 == 0 ? 1 : 0)) : 0,
                              child: IconButton(
                                tooltip: 'Órdenes en Espera',
                                icon: Icon(
                                  Icons.pending_actions_rounded,
                                  color: count > 0 ? Colors.orange.shade700 : Colors.blueGrey,
                                  size: 28,
                                ),
                                onPressed: () => _pendingOrdersPortalController.toggle(),
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
                    child: Icon(Icons.point_of_sale_rounded, size: 52, color: Colors.orange.shade400),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Caja sin turno activo',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Para registrar ventas, necesitás abrir\nla caja en esta terminal.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade600, height: 1.5),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushReplacementNamed('/home');
                    },
                    icon: const Icon(Icons.lock_open_rounded),
                    label: const Text('Abrir Caja Ahora', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Row(
                  children: [
                    SizedBox(
                      width: constraints.maxWidth * 0.35,
                      child: _buildCartPanel(),
                    ),
                    const VerticalDivider(width: 1, thickness: 1),
                    Expanded(
                      child: _buildRightPanel(),
                    )
                  ],
                );
              }
            ),
          );
        },
      ),
    );
  }

  Widget _buildCartPanel() {
    return Consumer<PosProvider>(
      builder: (context, pos, child) {
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
                    Icon(Icons.sync_rounded, color: Colors.orange.shade800, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Editando Orden #${pos.activePendingSaleId}',
                        style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline, color: Colors.red.shade700, size: 18),
                      tooltip: 'Anular Orden',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _handleDeletePendingOrder(pos.activePendingSaleId!, pos),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.orange.shade900, size: 18),
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

            // Header del carrito
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.blue.shade50,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Ticket Actual', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Icon(Icons.shopping_cart),
                ],
              ),
            ),
            
            // Lista de ítems
            Expanded(
              child: pos.cart.isEmpty
                  ? const Center(child: Text('El carrito está vacío', style: TextStyle(color: Colors.grey)))
                  : ListView.separated(
                      itemCount: pos.cart.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = pos.cart[index];
                        final bool exceedsStock = item.quantity > item.product.stock;
                        final String qtyDisplay = item.product.isSoldByWeight 
                            ? item.quantity.toStringAsFixed(3) 
                            : item.quantity.toInt().toString();
                        final String stockDisplay = item.product.isSoldByWeight
                            ? item.product.stock.toStringAsFixed(3)
                            : item.product.stock.toInt().toString();

                        return ListTile(
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              if (exceedsStock)
                                Text(
                                  'Stock disponible: $stockDisplay',
                                  style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            '$qtyDisplay x \$${item.product.sellingPrice.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: exceedsStock ? Colors.red.shade600 : null,
                              fontWeight: exceedsStock ? FontWeight.bold : null,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('\$${item.subtotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16)),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => pos.removeFromCart(item),
                              )
                            ],
                          ),
                          onTap: () {
                            _showEditCartItemModal(item, pos);
                          },
                        );
                      },
                    ),
            ),

            // Footer (Total + Doble Botón)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Total ────────────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      const Text('TOTAL:', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '\$${pos.cartTotal.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green),
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── Botón: Dejar en Espera ────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: pos.cart.isEmpty || pos.isLoading || isRecall ? null : _handleHoldOrder,
                      icon: const Icon(Icons.pending_actions_rounded, size: 18),
                      label: const Text('Dejar en Espera', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blueGrey.shade700,
                        side: BorderSide(color: pos.cart.isEmpty ? Colors.grey.shade300 : Colors.blueGrey.shade400),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ── Botón Principal: Cobrar ───────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: pos.cart.isEmpty
                            ? Colors.grey.shade400
                            : pos.isLoading
                                ? Colors.green.shade300
                                : Colors.green.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: pos.isLoading ? 0 : 4,
                      ),
                      onPressed: pos.cart.isEmpty || pos.isLoading ? null : _handleCheckout,
                      child: pos.isLoading
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(width: 22, height: 22,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)),
                                SizedBox(width: 10),
                                Text('Procesando...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              ],
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.point_of_sale_rounded, size: 22),
                                SizedBox(width: 8),
                                Text('💵 COBRAR', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            )
          ],
        );
      }
    );
  }

  Widget _buildRightPanel() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Barra de búsqueda con búsqueda server-side vía API
          TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              hintText: 'Escribir nombre o escanear código...',
              prefixIcon: _isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
            const Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Acceso Rápido', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('Productos por peso · Sin código de barras · Más vendidos',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
          ] else ...[  
            Row(
              children: [
                const Icon(Icons.filter_list_rounded, color: Colors.blueAccent),
                const SizedBox(width: 6),
                Text('Resultados para "${_searchController.text}"',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
              ],
            ),
          ],
          const SizedBox(height: 12),

          // ── Grilla dinámica ────────────────────────────────────────────
          Expanded(
            child: Consumer<CatalogProvider>(
              builder: (context, catalog, child) {
                if (catalog.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Determinar qué mostrar: resultados de API o Acceso Rápido
                final List<Product> displayItems;
                if (_searchQuery.isEmpty) {
                  // Acceso Rápido Inteligente:
                  // Nivel 1: Por peso o sin código de barras (siempre arriba)
                  // Nivel 2: Más vendidos primero
                  final level1 = catalog.products.where((p) => 
                    p.isSoldByWeight || (p.barcode == null || p.barcode!.isEmpty)
                  ).toList();
                  
                  final others = catalog.products.where((p) => 
                    !p.isSoldByWeight && (p.barcode != null && p.barcode!.isNotEmpty)
                  ).toList();

                  // Ordenar ambos grupos por ventas descendente
                  level1.sort((a, b) => b.salesCount.compareTo(a.salesCount));
                  others.sort((a, b) => b.salesCount.compareTo(a.salesCount));

                  displayItems = [...level1, ...others];
                } else {
                  // Resultados del servidor — búsqueda real sobre toda la BD
                  displayItems = _searchResults;
                }

                if (displayItems.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.search_off, size: 56, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(
                          _searchQuery.isEmpty
                              ? 'No hay productos en el catálogo.'
                              : 'No se encontraron productos para "${_searchController.text}"',
                          style: const TextStyle(color: Colors.grey, fontSize: 15),
                          textAlign: TextAlign.center,
                        ),
                        if (_searchQuery.isNotEmpty) ...[  
                          const SizedBox(height: 8),
                          const Text('Presá Enter para buscar en el servidor',
                              style: TextStyle(color: Colors.blueGrey, fontSize: 13)),
                        ],
                      ],
                    ),
                  );
                }

                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    childAspectRatio: 0.85,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: displayItems.length,
                  itemBuilder: (context, index) {
                    final product = displayItems[index];
                    final isByWeight = product.isSoldByWeight;

                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _handleProductSelection(product),
                      child: Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            gradient: LinearGradient(
                              colors: isByWeight
                                  ? [Colors.orange.shade50, Colors.white]   // naranja para granel
                                  : [Colors.blue.shade50, Colors.white],    // azul para unitarios
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Ícono diferenciador
                                Icon(
                                  isByWeight ? Icons.scale_rounded : Icons.inventory_2_outlined,
                                  color: isByWeight ? Colors.orange.shade600 : Colors.blue.shade600,
                                  size: 24,
                                ),
                                const SizedBox(height: 4),
                                Expanded(
                                  child: Center(
                                    child: Text(
                                      product.name, 
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isByWeight ? Colors.orange.shade100 : Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    isByWeight
                                        ? '\$${product.sellingPrice.toStringAsFixed(2)}/Kg'
                                        : '\$${product.sellingPrice.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: isByWeight ? Colors.orange.shade800 : Colors.green.shade700,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                // Badge "Por Peso" para los productos de granel
                                if (isByWeight) ...[  
                                  const SizedBox(height: 3),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade200,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('⚖️ Por Kg',
                                      style: TextStyle(fontSize: 10, color: Colors.orange.shade900, fontWeight: FontWeight.w600)),
                                  ),
                                ],
                                // Badge de Popularidad (Nivel Senior UX)
                                if (product.salesCount > 0) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.flash_on_rounded, size: 10, color: Colors.blueAccent),
                                        const SizedBox(width: 2),
                                        Text(
                                          '${product.salesCount} vendidos',
                                          style: const TextStyle(
                                            fontSize: 9, 
                                            color: Colors.blueAccent, 
                                            fontWeight: FontWeight.bold
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
