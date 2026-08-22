import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/config/app_config.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/categories_manager_dialog.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/brands_manager_dialog.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class MobileAuditScreen extends StatefulWidget {
  const MobileAuditScreen({super.key});

  @override
  State<MobileAuditScreen> createState() => _MobileAuditScreenState();
}

class _MobileAuditScreenState extends State<MobileAuditScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final TextEditingController _manualSearchCtrl = TextEditingController();
  
  final TextEditingController _priceCtrl = TextEditingController();
  final TextEditingController _stockCtrl = TextEditingController(); // Lectura del stock actual (display)
  final TextEditingController _addStockQuickCtrl = TextEditingController(); // Sumar stock (+) en vista rÃ¡pida

  bool _isProcessing = false;
  Product? _scannedProduct;
  String? _lastScannedCode;
  DateTime? _lastScanTime;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<CatalogProvider>().loadMetadata());
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _audioPlayer.dispose();
    _manualSearchCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _addStockQuickCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchProduct(String query) async {
    if (query.trim().isEmpty) return;
    
    setState(() {
      _isProcessing = true;
      _scannedProduct = null;
    });

    try {
      try {
        await _audioPlayer.play(AssetSource('beep.mp3'));
      } catch (_) {}

      // Pausar cÃ¡mara mientras procesamos
      _scannerController.stop();

      final posProvider = context.read<PosProvider>();
      final results = await posProvider.search(query.trim());

      if (results.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Producto no encontrado'),
              action: SnackBarAction(
                label: 'CREAR',
                onPressed: () {
                  ScaffoldMessenger.of(context).clearSnackBars();
                  _showProductFormDialog(initialBarcode: query.trim());
                },
              ),
              duration: const Duration(seconds: 4),
            ),
          );
          _scannerController.start(); // Retomar escaneo
        }
      } else {
        // Encontrar coincidencia exacta por cÃ³digo
        Product? match;
        try {
          match = results.firstWhere(
            (p) => p.barcode == query.trim() || p.internalCode == query.trim(),
          );
        } catch (_) {
          match = results.first; // Si no hay match exacto, usar el primero (Ãºtil para bÃºsqueda por ID o nombre manual)
        }

        if (mounted && true) {
          FocusScope.of(context).unfocus(); // Ocultar teclado
          setState(() {
            _scannedProduct = match;
            _priceCtrl.text = match!.sellingPrice.toInt().toString();
            _stockCtrl.text = (match.stock % 1 == 0 ? match.stock.toInt().toString() : match.stock.toString());
            _addStockQuickCtrl.clear(); // Limpiar campo de ingreso rÃ¡pido
          });
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarService.error(context, 'Error al buscar: $e');
        _scannerController.start();
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _onDetect(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String code = barcodes.first.rawValue ?? '';
    if (code.isEmpty) return;

    // Evitar escaneos duplicados rÃ¡pidos
    if (_lastScannedCode == code && _lastScanTime != null) {
      if (DateTime.now().difference(_lastScanTime!).inSeconds < 2) {
        return;
      }
    }

    _lastScannedCode = code;
    _lastScanTime = DateTime.now();
    _manualSearchCtrl.text = code;

    _searchProduct(code);
  }

  Future<void> _saveChanges() async {
    if (_scannedProduct == null) return;

    final newPrice = double.tryParse(_priceCtrl.text);
    final addStock = double.tryParse(_addStockQuickCtrl.text.trim());

    if (newPrice == null) {
      SnackBarService.error(context, 'Precio invÃ¡lido');
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final catalogProvider = context.read<CatalogProvider>();
      final payload = <String, dynamic>{
        'selling_price': newPrice,
        'cost_price': _scannedProduct!.costPrice,
        'stock': _scannedProduct!.stock,
      };

      // âœ… FIX: Si el empleado llenÃ³ "Sumar Stock (+)", usamos incremento atÃ³mico.
      // Si lo dejÃ³ vacÃ­o, solo actualizamos el precio (sin tocar el stock).
      if (addStock != null && addStock > 0) {
        payload['add_stock'] = addStock;
      }

      final success = await catalogProvider.updateProduct(
        _scannedProduct!.id,
        payload,
      );

      if (success && mounted) {
        final msg = (addStock != null && addStock > 0)
            ? 'âœ… Precio actualizado y +${addStock.toStringAsFixed(0)} u. sumadas al stock'
            : 'âœ… Precio actualizado';
        SnackBarService.success(context, msg);

        setState(() {
          _scannedProduct = null;
          _manualSearchCtrl.clear();
          _addStockQuickCtrl.clear();
        });
        _scannerController.start();
      } else if (mounted) {
        SnackBarService.error(context, catalogProvider.errorMessage ?? 'Error desconocido al guardar');
      }
    } catch (e) {
      if (mounted) SnackBarService.error(context, 'Error al guardar: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _printLabelRemotely(int productId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String apiUrl = prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;
      
      final apiClient = context.read<ApiClient>();
      
      final response = await apiClient.post(
        Uri.parse('$apiUrl/mobile/print-label'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'product_id': productId,
          'target_pc': 'caja-1', // Imprime siempre en la PC principal
        }),
      );
      
      if (response.statusCode == 200) {
        if (mounted) SnackBarService.success(context, 'âœ… Orden enviada a la impresora');
      } else {
        if (mounted) SnackBarService.error(context, 'âŒ Error al imprimir: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) SnackBarService.error(context, 'âŒ Error de red: $e');
    }
  }

  Future<void> _showProductFormDialog({String? initialBarcode, Product? productToEdit}) async {
    _scannerController.stop();

    final nameCtrl = TextEditingController(text: productToEdit?.name);
    final barcodeCtrl = TextEditingController(text: productToEdit?.barcode ?? initialBarcode);
    final costCtrl = TextEditingController(text: productToEdit != null ? productToEdit.costPrice.toInt().toString() : '');
    final marginCtrl = TextEditingController();
    final priceCtrl = TextEditingController(text: productToEdit != null ? productToEdit.sellingPrice.toInt().toString() : '');
    final stockCtrl = TextEditingController(text: productToEdit != null ? (productToEdit.stock % 1 == 0 ? productToEdit.stock.toInt().toString() : productToEdit.stock.toString()) : '');
    final vencimientoCtrl = TextEditingController(text: productToEdit?.vencimientoDias?.toString() ?? '');
    final addStockCtrl = TextEditingController();

    bool isSaving = false;
      int? selectedCategoryId = productToEdit?.category?.id;
    int? selectedBrandId = productToEdit?.brand?.id;
    bool isSoldByWeight = productToEdit?.isSoldByWeight ?? false;

    if (productToEdit != null && productToEdit.costPrice > 0) {
      marginCtrl.text = (((productToEdit.sellingPrice - productToEdit.costPrice) / productToEdit.costPrice) * 100).toInt().toString();
    }

    // Helper para escaner secundario
    Future<String?> scanBarcodeSecundario() async {
      return await showDialog<String>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Escanear CÃ³digo'),
            content: SizedBox(
              width: 300,
              height: 300,
              child: MobileScanner(
                onDetect: (capture) {
                  if (capture.barcodes.isNotEmpty) {
                    final code = capture.barcodes.first.rawValue;
                    if (code != null && code.isNotEmpty) {
                      Navigator.pop(ctx, code);
                    }
                  }
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ],
          );
        },
      );
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final catalogProv = context.read<CatalogProvider>();

            void calcPriceFromMargin() {
              final cost = double.tryParse(costCtrl.text) ?? 0.0;
              final margin = double.tryParse(marginCtrl.text) ?? 0.0;
              if (cost > 0) {
                final price = cost + (cost * (margin / 100));
                priceCtrl.text = price.toInt().toString();
              }
            }

            void calcMarginFromPrice() {
              final cost = double.tryParse(costCtrl.text) ?? 0.0;
              final price = double.tryParse(priceCtrl.text) ?? 0.0;
              if (cost > 0 && price > 0) {
                final margin = ((price - cost) / cost) * 100;
                marginCtrl.text = margin.toInt().toString();
              } else if (cost == 0) {
                marginCtrl.text = '';
              }
            }

            return AlertDialog(
              title: Row(
                children: [
                  Expanded(child: Text(productToEdit == null ? 'Nuevo Producto' : 'Editar Producto', style: const TextStyle(fontSize: 18))),
                  if (productToEdit != null)
                    IconButton(
                      icon: const Icon(Icons.print, color: Colors.blueAccent),
                      tooltip: 'Imprimir Etiqueta Remotamente',
                      onPressed: () => _printLabelRemotely(productToEdit.id),
                    ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Nombre del producto', isDense: true),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: barcodeCtrl,
                      decoration: InputDecoration(
                        labelText: 'CÃ³digo de barras', 
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.qr_code_scanner, color: Colors.blueAccent),
                          onPressed: () async {
                            final code = await scanBarcodeSecundario();
                            if (code != null) {
                              setStateDialog(() => barcodeCtrl.text = code);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int?>(isExpanded: true,
                            initialValue: selectedCategoryId,
                            decoration: const InputDecoration(labelText: 'CategorÃ­a', isDense: true, border: OutlineInputBorder()),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('Sin CategorÃ­a')),
                              ...catalogProv.categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                            ],
                            onChanged: (val) => setStateDialog(() => selectedCategoryId = val),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.settings),
                          tooltip: 'Gestionar CategorÃ­as',
                          onPressed: () async {
                            await showDialog(
                              context: context,
                              builder: (_) => const CategoriesManagerDialog(),
                            );
                            if (context.mounted) {
                               await catalogProv.loadMetadata();
                               setStateDialog(() {});
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int?>(isExpanded: true,
                            initialValue: selectedBrandId,
                            decoration: const InputDecoration(labelText: 'Marca', isDense: true, border: OutlineInputBorder()),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('Sin Marca')),
                              ...catalogProv.brands.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))),
                            ],
                            onChanged: (val) => setStateDialog(() => selectedBrandId = val),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.settings),
                          tooltip: 'Gestionar Marcas',
                          onPressed: () async {
                            await showDialog(
                              context: context,
                              builder: (_) => const BrandsManagerDialog(),
                            );
                            if (context.mounted) {
                               await catalogProv.loadMetadata();
                               setStateDialog(() {});
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Fila de Costo, Margen, Venta
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: costCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Costo (\$)', isDense: true),
                            onChanged: (_) => calcMarginFromPrice(), // Mantiene el precio fijo, ajusta margen
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: marginCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                            decoration: const InputDecoration(labelText: '% Gan.', isDense: true),
                            onChanged: (_) => calcPriceFromMargin(), // Ajusta precio segÃºn el margen
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: priceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Venta (\$)', isDense: true),
                            onChanged: (_) => calcMarginFromPrice(), // Ajusta margen segÃºn el precio
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: stockCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Stock Absoluto', isDense: true, border: OutlineInputBorder()),
                          ),
                        ),
                        if (productToEdit != null) const SizedBox(width: 8),
                        if (productToEdit != null) Expanded(
                          flex: 1,
                          child: TextField(
                            controller: addStockCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Sumar Stock (+)', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.add_box, color: Colors.green, size: 20)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: vencimientoCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'DÃ­as para Vencimiento', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.event_busy, color: Colors.orange, size: 20)),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Se vende por peso (Balanza)'),
                      value: isSoldByWeight,
                      onChanged: (val) => setStateDialog(() => isSoldByWeight = val),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          final cost = double.tryParse(costCtrl.text) ?? 0.0;
                          final price = double.tryParse(priceCtrl.text) ?? 0.0;
                          final stock = double.tryParse(stockCtrl.text) ?? 0.0;
                          final addStock = double.tryParse(addStockCtrl.text);
                          final vencimientoDias = int.tryParse(vencimientoCtrl.text);

                          if (name.isEmpty) {
                            SnackBarService.error(context, 'El nombre es obligatorio');
                            return;
                          }

                          setStateDialog(() => isSaving = true);
                          
                          try {
                            bool success;
                            final payload = {
                              'name': name,
                              'barcode': barcodeCtrl.text.trim().isEmpty ? null : barcodeCtrl.text.trim(),
                              'cost_price': cost,
                              'selling_price': price,
                              'stock': stock,
                              'category_id': selectedCategoryId,
                              'brand_id': selectedBrandId,
                              'is_sold_by_weight': isSoldByWeight,
                              'unit_type': isSoldByWeight ? 'kg' : 'un',
                            };

                            if (addStock != null && addStock > 0) {
                              payload['add_stock'] = addStock;
                            }
                            if (vencimientoDias != null) {
                              payload['vencimiento_dias'] = vencimientoDias;
                            }

                            if (productToEdit == null) {
                              payload['active'] = true;
                              success = await catalogProv.createProduct(payload);
                            } else {
                              success = await catalogProv.updateProduct(productToEdit.id, payload);
                            }
                            
                            if (success && ctx.mounted) {
                              Navigator.pop(ctx);
                              SnackBarService.success(context, productToEdit == null ? 'Producto creado exitosamente' : 'Producto modificado exitosamente');
                              
                              String queryToSearch = barcodeCtrl.text.trim();
                              if (queryToSearch.isEmpty) {
                                queryToSearch = nameCtrl.text.trim();
                              }
                              if (queryToSearch.isNotEmpty) {
                                _manualSearchCtrl.text = queryToSearch;
                                _searchProduct(queryToSearch);
                              }
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              SnackBarService.error(context, 'Error: $e');
                              setStateDialog(() => isSaving = false);
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (_scannedProduct == null) {
      _scannerController.start();
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('Control de Precios y Stock'),
        ),
        backgroundColor: const Color(0xFF1E2D45),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _scannerController.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _scannedProduct = null;
                _manualSearchCtrl.clear();
              });
              _scannerController.start();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. ÃREA DE CÃMARA O PRODUCTO (Alternan)
          if (_scannedProduct == null)
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  MobileScanner(
                    controller: _scannerController,
                    onDetect: _onDetect,
                  ),
                  Center(
                    child: Container(
                      width: 250,
                      height: 150,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.greenAccent, width: 3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  if (_isProcessing)
                    const Center(child: CircularProgressIndicator()),
                ],
              ),
            )
          else
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green, size: 64),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blueAccent),
                            tooltip: 'Editar detalles',
                            onPressed: () => _showProductFormDialog(productToEdit: _scannedProduct),
                          ),
                          IconButton(
                            icon: const Icon(Icons.print, color: Colors.blueAccent),
                            tooltip: 'Imprimir Etiqueta Remotamente',
                            onPressed: () => _printLabelRemotely(_scannedProduct!.id),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _scannedProduct!.name,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'CÃ³digo: ${_scannedProduct!.barcode ?? _scannedProduct!.internalCode}',
                        style: const TextStyle(fontSize: 16, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 2. BUSCADOR MANUAL
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualSearchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Ingresar cÃ³digo manual...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    onSubmitted: _searchProduct,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFF1E2D45)),
                  color: Colors.white,
                  icon: const Icon(Icons.search),
                  onPressed: () => _searchProduct(_manualSearchCtrl.text),
                ),
              ],
            ),
          ),

          // 3. ÃREA DE EDICIÃ“N
          if (_scannedProduct != null)
            Expanded(
              flex: 4,
              child: Container(
                color: Colors.grey.shade100,
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _priceCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Precio de Venta (\$)',
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Stock actual: solo lectura (display)
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.grey.shade400),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Stock actual', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                  const SizedBox(height: 4),
                                  Text(
                                    _stockCtrl.text,
                                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black54),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // âœ… FIX: Campo "Sumar Stock" con incremento atÃ³mico (sin race condition)
                      TextFormField(
                        controller: _addStockQuickCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Sumar Stock (+) â€” Opcional',
                          hintText: 'Ej: 12 (suma al stock actual)',
                          helperText: 'âš¡ Ingreso atÃ³mico: protegido contra ventas simultÃ¡neas',
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.green.shade50,
                          prefixIcon: const Icon(Icons.add_box, color: Colors.green),
                          labelStyle: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.green.shade700, width: 2),
                          ),
                        ),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _isProcessing ? null : _saveChanges,
                          icon: _isProcessing
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.save, size: 28),
                          label: const Text('GUARDAR CAMBIOS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          TextButton.icon(
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Eliminar Producto'),
                                  content: Text('Â¿Seguro que deseas eliminar "${_scannedProduct!.name}"? Esta acciÃ³n no se puede deshacer.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true), 
                                      child: const Text('Eliminar', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true && mounted) {
                                setState(() => _isProcessing = true);
                                try {
                                  final catalogProv = context.read<CatalogProvider>();
                                  await catalogProv.deleteProduct(_scannedProduct!.id);
                                  if (mounted) {
                                    SnackBarService.success(context, 'Producto eliminado');
                                    setState(() {
                                      _scannedProduct = null;
                                      _manualSearchCtrl.clear();
                                    });
                                    _scannerController.start();
                                  }
                                } catch (e) {
                                  if (mounted) SnackBarService.error(context, 'Error al eliminar: $e');
                                } finally {
                                  if (mounted) setState(() => _isProcessing = false);
                                }
                              }
                            },
                            icon: const Icon(Icons.delete, color: Colors.red),
                            label: const Text('Eliminar', style: TextStyle(color: Colors.red)),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _scannedProduct = null;
                                _manualSearchCtrl.clear();
                              });
                              _scannerController.start();
                            },
                            icon: const Icon(Icons.close, color: Colors.grey),
                            label: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            )
          else
            const Expanded(
              flex: 4,
              child: Center(
                child: Text('ApuntÃ¡ al CÃ³digo de barras\no ingresalo manualmente.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
              ),
            )
        ],
      ),
      floatingActionButton: _scannedProduct == null
          ? FloatingActionButton.extended(
              onPressed: () => _showProductFormDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo'),
              backgroundColor: const Color(0xFF1E2D45),
              foregroundColor: Colors.white,
            )
          : null,
    );
  }
}












