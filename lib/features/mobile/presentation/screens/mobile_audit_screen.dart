import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
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
import 'package:frontend_desktop/core/utils/image_url_resolver.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/categories_manager_dialog.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/brands_manager_dialog.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_permissions.dart';
import '../../../auth/presentation/widgets/admin_pin_dialog.dart';

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
  final TextEditingController _addStockQuickCtrl = TextEditingController(); // Sumar stock (+) en vista rápida

  bool _isProcessing = false;
  Product? _scannedProduct;
  String? _lastScannedCode;
  DateTime? _lastScanTime;

  @override
  void initState() {
    super.initState();
    try {
      _audioPlayer.setSource(AssetSource('beep_loud.wav')).catchError((_) {});
    } catch (_) {}
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

    // Limpiar cualquier snackbar anterior antes de procesar el nuevo código
    if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();

    setState(() {
      _isProcessing = true;
      _scannedProduct = null;
    });

    try {
      try {
        if (_audioPlayer.state == PlayerState.playing) {
          _audioPlayer.stop().catchError((_) {});
        }
        _audioPlayer.play(AssetSource('beep_loud.wav')).catchError((_) {});
      } catch (_) {}

      // Pausar cámara mientras procesamos
      try {
        _scannerController.stop().catchError((_) {});
      } catch (_) {}

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
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  _showProductFormDialog(initialBarcode: query.trim());
                },
              ),
              duration: const Duration(seconds: 4),
            ),
          );
          try {
            _scannerController.start().catchError((_) {}); // Retomar escaneo
          } catch (_) {}
        }
      } else {
        // Encontrar coincidencia exacta por código
        Product? match;
        try {
          match = results.firstWhere(
            (p) => p.barcode == query.trim() || p.internalCode == query.trim(),
          );
        } catch (_) {
          match = results.first; // Si no hay match exacto, usar el primero (útil para búsqueda por ID o nombre manual)
        }

        if (mounted && true) {
          FocusScope.of(context).unfocus(); // Ocultar teclado
          setState(() {
            _scannedProduct = match;
            _priceCtrl.text = match!.sellingPrice % 1 == 0
                ? match.sellingPrice.toInt().toString()
                : match.sellingPrice.toString();
            _stockCtrl.text = (match.stock % 1 == 0 ? match.stock.toInt().toString() : match.stock.toString());
            _addStockQuickCtrl.clear(); // Limpiar campo de ingreso rápido
          });
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarService.error(context, 'Error al buscar: $e');
        try {
          _scannerController.start().catchError((_) {});
        } catch (_) {}
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

    // Evitar escaneos duplicados rápidos
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

    final newPrice = double.tryParse(_priceCtrl.text.trim().replaceAll(',', '.'));
    final addStock = _addStockQuickCtrl.text.trim().isNotEmpty
        ? double.tryParse(_addStockQuickCtrl.text.trim().replaceAll(',', '.'))
        : null;

    if (newPrice == null) {
      SnackBarService.error(context, 'Precio inválido');
      return;
    }

    final isPriceChanged = (newPrice - _scannedProduct!.sellingPrice).abs() > 0.001;
    final isStockChanged = addStock != null && addStock > 0;

    Future<void> executeSave() async {
      setState(() => _isProcessing = true);

      try {
        final catalogProvider = context.read<CatalogProvider>();
        final payload = <String, dynamic>{
          'selling_price': newPrice,
          'cost_price': _scannedProduct!.costPrice,
          'stock': _scannedProduct!.stock,
        };

        // Si el empleado llenó "Sumar Stock (+)", usamos incremento atómico.
        // Si lo dejó vacío, solo actualizamos el precio (sin tocar el stock).
        if (addStock != null && addStock > 0) {
          payload['add_stock'] = addStock;
        }

        final success = await catalogProvider.updateProduct(
          _scannedProduct!.id,
          payload,
        );

        if (success && mounted) {
          final msg = (addStock != null && addStock > 0)
              ? '✅ Precio actualizado y +${addStock.toStringAsFixed(0)} u. sumadas al stock'
              : '✅ Precio actualizado';
          SnackBarService.success(context, msg);

          final effectiveStock = (addStock != null && addStock > 0)
              ? (_scannedProduct!.stock + addStock)
              : _scannedProduct!.stock;

          Product? updated = catalogProvider.lastUpdatedProduct;
          if (updated == null || updated.id != _scannedProduct!.id) {
            updated = _scannedProduct!.copyWith(
              sellingPrice: newPrice,
              stock: effectiveStock,
            );
          }

          setState(() {
            _scannedProduct = updated;
            _priceCtrl.text = updated!.sellingPrice % 1 == 0
                ? updated.sellingPrice.toInt().toString()
                : updated.sellingPrice.toString();
            _stockCtrl.text = (updated.stock % 1 == 0
                ? updated.stock.toInt().toString()
                : updated.stock.toString());
            _addStockQuickCtrl.clear();
          });
        } else if (mounted) {
          SnackBarService.error(context, catalogProvider.errorMessage ?? 'Error desconocido al guardar');
        }
      } catch (e) {
        if (mounted) SnackBarService.error(context, 'Error al guardar: $e');
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }

    if (isPriceChanged) {
      final authorized = await AdminPinDialog.protectAction(
        context,
        action: 'Modificar Precio de Catálogo',
        permissionKey: AppPermissions.manageCatalog,
        onAuthorized: () async {
          if (isStockChanged) {
            await AdminPinDialog.protectAction(
              context,
              action: 'Ajustar Stock de Inventario',
              permissionKey: AppPermissions.adjustStock,
              onAuthorized: executeSave,
            );
          } else {
            await executeSave();
          }
        },
      );
      if (!authorized) return;
    } else if (isStockChanged) {
      await AdminPinDialog.protectAction(
        context,
        action: 'Ajustar Stock de Inventario',
        permissionKey: AppPermissions.adjustStock,
        onAuthorized: executeSave,
      );
    } else {
      await executeSave();
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
        if (mounted) SnackBarService.success(context, '✅ Orden enviada a la Tiquetera Térmica');
      } else {
        if (mounted) SnackBarService.error(context, '❌ Error en la Tiquetera Térmica: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) SnackBarService.error(context, '❌ Error de red con la Tiquetera: $e');
    }
  }

  Future<void> _showProductFormDialog({String? initialBarcode, Product? productToEdit}) async {
    try {
      _scannerController.stop().catchError((_) {});
    } catch (_) {}

    final nameCtrl = TextEditingController(text: productToEdit?.name);
    final barcodeCtrl = TextEditingController(text: productToEdit?.barcode ?? initialBarcode);
    final costCtrl = TextEditingController(
      text: productToEdit != null
          ? (productToEdit.costPrice % 1 == 0 ? productToEdit.costPrice.toInt().toString() : productToEdit.costPrice.toString())
          : '',
    );
    final marginCtrl = TextEditingController();
    final priceCtrl = TextEditingController(
      text: productToEdit != null
          ? (productToEdit.sellingPrice % 1 == 0 ? productToEdit.sellingPrice.toInt().toString() : productToEdit.sellingPrice.toString())
          : '',
    );
    final stockCtrl = TextEditingController(text: productToEdit != null ? (productToEdit.stock % 1 == 0 ? productToEdit.stock.toInt().toString() : productToEdit.stock.toString()) : '');
    final minStockCtrl = TextEditingController(text: productToEdit?.minStock?.toString() ?? '');
    final vencimientoCtrl = TextEditingController(text: productToEdit?.vencimientoDias?.toString() ?? '');
    final addStockCtrl = TextEditingController();
    final internalCodeCtrl = TextEditingController(text: productToEdit?.internalCode ?? '');

    bool isSaving = false;
    String? selectedImagePath;
    Uint8List? selectedImageBytes;
    String? selectedImageName;
    bool isUploadingImage = false;
    int? selectedCategoryId = productToEdit?.category?.id;
    int? selectedBrandId = productToEdit?.brand?.id;
    int? selectedSupplierId = productToEdit?.supplier?.id;
    bool isSoldByWeight = productToEdit?.isSoldByWeight ?? false;
    bool isActive = productToEdit?.active ?? true;
    String unitType = productToEdit?.unitType ?? 'un';

    if (productToEdit != null && productToEdit.costPrice > 0) {
      final marginVal = ((productToEdit.sellingPrice - productToEdit.costPrice) / productToEdit.costPrice) * 100;
      marginCtrl.text = marginVal % 1 == 0 ? marginVal.toInt().toString() : marginVal.toStringAsFixed(2);
    }

    // Helper para escaner secundario
    Future<String?> scanBarcodeSecundario() async {
      return await showDialog<String>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Escanear Código'),
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

    final canSeeSupplier = context.read<SettingsProvider>().features.suppliers;
    if (canSeeSupplier) {
      context.read<SupplierProvider>().fetchSuppliers();
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final catalogProv = context.read<CatalogProvider>();

            Future<void> pickProductImage() async {
              try {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.image,
                  withData: true,
                );
                if (result != null && result.files.isNotEmpty) {
                  final file = result.files.single;
                  final ext = file.extension?.toLowerCase() ??
                      (file.name.contains('.') ? file.name.split('.').last.toLowerCase() : '');
                  if (ext.isNotEmpty && !['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
                    if (context.mounted) {
                      SnackBarService.error(context, 'Formato no soportado ($ext). Usa JPG, PNG o WEBP.');
                    }
                    return;
                  }
                  int fileSize = file.size > 0 ? file.size : (file.bytes?.length ?? 0);
                  if (fileSize == 0 && file.path != null && file.path!.isNotEmpty) {
                    try {
                      final ioFile = File(file.path!);
                      if (ioFile.existsSync()) {
                        fileSize = ioFile.lengthSync();
                      }
                    } catch (_) {}
                  }
                  if (fileSize > 2 * 1024 * 1024) {
                    if (context.mounted) {
                      SnackBarService.error(context, 'La imagen supera los 2MB permitidos (máx 2048 KB).');
                    }
                    return;
                  }
                  Uint8List? bytes = file.bytes;
                  if (bytes == null && file.path != null && file.path!.isNotEmpty) {
                    try {
                      final ioFile = File(file.path!);
                      if (ioFile.existsSync()) {
                        bytes = ioFile.readAsBytesSync();
                      }
                    } catch (_) {}
                  }
                  setStateDialog(() {
                    selectedImagePath = file.path;
                    selectedImageBytes = bytes;
                    selectedImageName = file.name;
                  });
                }
              } catch (e) {
                debugPrint('Error seleccionando imagen: $e');
                if (context.mounted) {
                  SnackBarService.error(context, 'Error al seleccionar imagen: $e');
                }
              }
            }

            void calcPriceFromMargin() {
              final cost = double.tryParse(costCtrl.text.replaceAll(',', '.')) ?? 0.0;
              final margin = double.tryParse(marginCtrl.text.replaceAll(',', '.')) ?? 0.0;
              if (cost > 0) {
                final price = cost + (cost * (margin / 100));
                priceCtrl.text = price % 1 == 0 ? price.toInt().toString() : price.toStringAsFixed(2);
              }
            }

            void calcMarginFromPrice() {
              final cost = double.tryParse(costCtrl.text.replaceAll(',', '.')) ?? 0.0;
              final price = double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0.0;
              if (cost > 0 && price > 0) {
                final margin = ((price - cost) / cost) * 100;
                marginCtrl.text = margin % 1 == 0 ? margin.toInt().toString() : margin.toStringAsFixed(2);
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
                      tooltip: 'Imprimir en Tiquetera Térmica',
                      onPressed: () => _printLabelRemotely(productToEdit.id),
                    ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Selector de Imagen de Producto
                    Builder(
                      builder: (context) {
                        final resolvedExistingImageUrl = resolveImageUrl(productToEdit?.imageUrl);
                        final hasValidExistingImage = resolvedExistingImageUrl != null && resolvedExistingImageUrl.isNotEmpty;
                        final hasSelected = selectedImageBytes != null || (selectedImagePath != null && selectedImagePath!.isNotEmpty);
                        final hasAny = hasSelected || hasValidExistingImage;

                        Widget imageContent;
                        if (isUploadingImage) {
                          imageContent = const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        } else if (selectedImageBytes != null) {
                          imageContent = Image.memory(
                            selectedImageBytes!,
                            width: 75,
                            height: 75,
                            fit: BoxFit.cover,
                          );
                        } else if (selectedImagePath != null && selectedImagePath!.isNotEmpty) {
                          imageContent = Image.file(
                            File(selectedImagePath!),
                            width: 75,
                            height: 75,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 32, color: Colors.grey),
                          );
                        } else if (hasValidExistingImage) {
                          imageContent = Image.network(
                            resolvedExistingImageUrl,
                            width: 75,
                            height: 75,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 32, color: Colors.grey),
                          );
                        } else {
                          imageContent = Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_a_photo_outlined, size: 26, color: Colors.grey.shade600),
                              const SizedBox(height: 2),
                              Text(
                                'Subir Foto',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                              ),
                            ],
                          );
                        }

                        final imageCard = InkWell(
                          key: const Key('mobile_product_image_picker'),
                          onTap: (isSaving || isUploadingImage) ? null : () => pickProductImage(),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 75,
                            height: 75,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: hasSelected ? const Color(0xFF673AB7) : Colors.grey.shade300,
                                width: hasSelected ? 2 : 1,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Center(child: imageContent),
                          ),
                        );

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              imageCard,
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Foto del Producto',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade800),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Cámara o galería',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        OutlinedButton.icon(
                                          key: const Key('mobile_pick_image_button'),
                                          onPressed: (isSaving || isUploadingImage) ? null : () => pickProductImage(),
                                          icon: const Icon(Icons.photo_library_outlined, size: 14),
                                          label: Text(hasAny ? 'Cambiar Foto' : 'Seleccionar Foto', style: const TextStyle(fontSize: 11)),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            minimumSize: const Size(0, 30),
                                          ),
                                        ),
                                        if (hasSelected)
                                          IconButton(
                                            tooltip: 'Descartar foto',
                                            icon: const Icon(Icons.close, color: Colors.red, size: 18),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: (isSaving || isUploadingImage)
                                                ? null
                                                : () {
                                                    setStateDialog(() {
                                                      selectedImagePath = null;
                                                      selectedImageBytes = null;
                                                      selectedImageName = null;
                                                    });
                                                  },
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Nombre del producto', isDense: true),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: barcodeCtrl,
                      decoration: InputDecoration(
                        labelText: 'Código de barras', 
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
                    TextField(
                      controller: internalCodeCtrl,
                      decoration: const InputDecoration(labelText: 'Código Interno', isDense: true, border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int?>(isExpanded: true,
                            // ignore: deprecated_member_use
                            value: selectedCategoryId,
                            decoration: const InputDecoration(labelText: 'Categoría', isDense: true, border: OutlineInputBorder()),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('Sin Categoría')),
                              ...catalogProv.categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                            ],
                            onChanged: (val) => setStateDialog(() => selectedCategoryId = val),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.settings),
                          tooltip: 'Gestionar Categorías',
                          onPressed: () async {
                            final newCategoryId = await showDialog<int?>(
                              context: context,
                              builder: (_) => const CategoriesManagerDialog(),
                            );
                            if (context.mounted) {
                               await catalogProv.loadMetadata();
                               setStateDialog(() {
                                 if (newCategoryId != null) {
                                   selectedCategoryId = newCategoryId;
                                 }
                               });
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
                            // ignore: deprecated_member_use
                            value: selectedBrandId,
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
                            final newBrandId = await showDialog<int?>(
                              context: context,
                              builder: (_) => const BrandsManagerDialog(),
                            );
                            if (context.mounted) {
                               await catalogProv.loadMetadata();
                               setStateDialog(() {
                                 if (newBrandId != null) {
                                   selectedBrandId = newBrandId;
                                 }
                               });
                            }
                          },
                        ),
                      ],
                    ),
                    
                    if (context.read<SettingsProvider>().features.suppliers) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int?>(
                              isExpanded: true,
                              // ignore: deprecated_member_use
                              value: context.read<SupplierProvider>().suppliers.any((s) => s.id == selectedSupplierId) ? selectedSupplierId : null,
                              decoration: const InputDecoration(labelText: 'Proveedor (Opcional)', isDense: true, border: OutlineInputBorder()),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Sin Proveedor')),
                                ...context.read<SupplierProvider>().suppliers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis))),
                              ],
                              onChanged: (val) => setStateDialog(() => selectedSupplierId = val),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Recargar Proveedores',
                            onPressed: () {
                              context.read<SupplierProvider>().fetchSuppliers();
                            },
                          ),
                        ],
                      ),
                    ],
                    
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
                            onChanged: (_) => calcPriceFromMargin(), // Ajusta precio según el margen
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: priceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Venta (\$)', isDense: true),
                            onChanged: (_) => calcMarginFromPrice(), // Ajusta margen según el precio
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
                    Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: minStockCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Stock Mínimo', isDense: true, border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: DropdownButtonFormField<String>(
                            // ignore: deprecated_member_use
                            value: unitType,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Unidad', isDense: true, border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(value: 'un', child: Text('Unidades')),
                              DropdownMenuItem(value: 'kg', child: Text('Kilogramos')),
                              DropdownMenuItem(value: 'lt', child: Text('Litros')),
                              DropdownMenuItem(value: 'm', child: Text('Metros')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setStateDialog(() => unitType = val);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: vencimientoCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Días para Vencimiento', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.event_busy, color: Colors.orange, size: 20)),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Se vende por peso (Balanza)'),
                      value: isSoldByWeight,
                      onChanged: (val) => setStateDialog(() => isSoldByWeight = val),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      title: const Text('Activo (Visible en Catálogo)'),
                      value: isActive,
                      onChanged: (val) => setStateDialog(() => isActive = val),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: (isSaving || isUploadingImage) ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: (isSaving || isUploadingImage)
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          final cost = double.tryParse(costCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;
                          final price = double.tryParse(priceCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;
                          final stock = double.tryParse(stockCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;
                          final addStock = addStockCtrl.text.trim().isNotEmpty
                              ? double.tryParse(addStockCtrl.text.trim().replaceAll(',', '.'))
                              : null;
                          final vencimientoDias = int.tryParse(vencimientoCtrl.text.trim());
                          final minStock = minStockCtrl.text.trim().isNotEmpty
                              ? double.tryParse(minStockCtrl.text.trim().replaceAll(',', '.'))
                              : null;

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
                              'internal_code': internalCodeCtrl.text.trim().isEmpty ? null : internalCodeCtrl.text.trim(),
                              'cost_price': cost,
                              'selling_price': price,
                              'stock': stock,
                              'category_id': selectedCategoryId,
                              'brand_id': selectedBrandId,
                              'supplier_id': selectedSupplierId,
                              'is_sold_by_weight': isSoldByWeight,
                              'unit_type': isSoldByWeight ? 'kg' : unitType,
                              'active': isActive,
                            };

                            if (addStock != null && addStock > 0) {
                              payload['add_stock'] = addStock;
                            }
                            if (minStock != null) {
                              payload['min_stock'] = minStock;
                            }
                            if (vencimientoDias != null) {
                              payload['vencimiento_dias'] = vencimientoDias;
                            }

                            int? targetProductId = productToEdit?.id;
                            if (productToEdit == null) {
                              payload['active'] = true;
                              success = await catalogProv.createProduct(payload);
                              targetProductId = catalogProv.lastCreatedProduct?.id;
                            } else {
                              success = await catalogProv.updateProduct(productToEdit.id, payload);
                            }

                            bool imageUploadSuccess = true;
                            String? imageUploadError;
                            String? uploadedImageUrl;
                            if (success && (selectedImagePath != null || selectedImageBytes != null)) {
                              if (targetProductId != null) {
                                setStateDialog(() => isUploadingImage = true);
                                uploadedImageUrl = await catalogProv.uploadProductImage(
                                  targetProductId,
                                  selectedImagePath ?? '',
                                  bytes: selectedImageBytes,
                                  filename: selectedImageName,
                                );
                                if (uploadedImageUrl == null) {
                                  imageUploadSuccess = false;
                                  imageUploadError = catalogProv.errorMessage?.replaceAll('Exception: ', '');
                                }
                              } else {
                                imageUploadSuccess = false;
                                imageUploadError = 'No se pudo obtener el identificador del producto.';
                              }
                            }
                            
                            if (success && ctx.mounted) {
                              Navigator.pop(ctx);
                              if (imageUploadSuccess) {
                                SnackBarService.success(context, productToEdit == null ? 'Producto creado exitosamente' : 'Producto modificado exitosamente');
                              } else {
                                SnackBarService.warning(
                                  context,
                                  'Producto guardado, pero no se pudo subir la foto: ${imageUploadError ?? "Error al procesar la imagen."}',
                                );
                              }
                              
                              String queryToSearch = barcodeCtrl.text.trim();
                              if (queryToSearch.isEmpty) {
                                queryToSearch = internalCodeCtrl.text.trim();
                              }
                              if (queryToSearch.isEmpty) {
                                queryToSearch = nameCtrl.text.trim();
                              }

                              // Determinar el producto actualizado
                              Product? updated = targetProductId != null
                                  ? catalogProv.products.where((p) => p.id == targetProductId).firstOrNull
                                  : null;

                              if (updated == null && catalogProv.lastUpdatedProduct?.id == targetProductId) {
                                updated = catalogProv.lastUpdatedProduct;
                              } else if (updated == null && catalogProv.lastCreatedProduct?.id == targetProductId) {
                                updated = catalogProv.lastCreatedProduct;
                              }

                              if (updated == null && productToEdit != null && productToEdit.id == targetProductId) {
                                final effectiveStock = (addStock != null && addStock > 0) ? (stock + addStock) : stock;
                                final newCategory = selectedCategoryId != null
                                    ? catalogProv.categories.where((c) => c.id == selectedCategoryId).firstOrNull
                                    : null;
                                final newBrand = selectedBrandId != null
                                    ? catalogProv.brands.where((b) => b.id == selectedBrandId).firstOrNull
                                    : null;
                                final newSupplier = selectedSupplierId != null
                                    ? context.read<SupplierProvider>().suppliers.where((s) => s.id == selectedSupplierId).firstOrNull
                                    : null;
                                updated = productToEdit.copyWith(
                                  name: name,
                                  barcode: barcodeCtrl.text.trim().isEmpty ? null : barcodeCtrl.text.trim(),
                                  internalCode: internalCodeCtrl.text.trim().isEmpty ? null : internalCodeCtrl.text.trim(),
                                  sellingPrice: price,
                                  costPrice: cost,
                                  stock: effectiveStock,
                                  imageUrl: uploadedImageUrl ?? productToEdit.imageUrl,
                                  category: newCategory,
                                  clearCategory: selectedCategoryId == null,
                                  brand: newBrand,
                                  clearBrand: selectedBrandId == null,
                                  supplier: newSupplier,
                                  clearSupplier: selectedSupplierId == null,
                                  isSoldByWeight: isSoldByWeight,
                                  unitType: isSoldByWeight ? 'kg' : unitType,
                                  active: isActive,
                                );
                              }

                              if (updated != null) {
                                if (uploadedImageUrl != null && updated.imageUrl != uploadedImageUrl) {
                                  updated = updated.copyWith(imageUrl: uploadedImageUrl);
                                }
                                setState(() {
                                  _scannedProduct = updated;
                                  _priceCtrl.text = updated!.sellingPrice % 1 == 0
                                      ? updated.sellingPrice.toInt().toString()
                                      : updated.sellingPrice.toString();
                                  _stockCtrl.text = (updated.stock % 1 == 0 ? updated.stock.toInt().toString() : updated.stock.toString());
                                  _addStockQuickCtrl.clear();
                                });
                                if (queryToSearch.isNotEmpty) {
                                  _manualSearchCtrl.text = queryToSearch;
                                }
                              } else {
                                if (queryToSearch.isNotEmpty) {
                                  _manualSearchCtrl.text = queryToSearch;
                                  _searchProduct(queryToSearch);
                                }
                              }
                            } else if (ctx.mounted) {
                              SnackBarService.error(context, catalogProv.errorMessage ?? 'Error desconocido');
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              SnackBarService.error(context, 'Error: $e');
                            }
                          } finally {
                            if (ctx.mounted) {
                              setStateDialog(() {
                                isSaving = false;
                                isUploadingImage = false;
                              });
                            }
                          }
                        },
                  child: (isSaving || isUploadingImage)
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
      try {
        _scannerController.start().catchError((_) {});
      } catch (_) {}
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
            onPressed: () {
              try {
                _scannerController.toggleTorch().catchError((_) {});
              } catch (_) {}
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _scannedProduct = null;
                _manualSearchCtrl.clear();
              });
              try {
                _scannerController.start().catchError((_) {});
              } catch (_) {}
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. ÁREA DE CÁMARA O PRODUCTO (Alternan)
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
                          Builder(
                            builder: (context) {
                              final resolvedScannedImg = resolveImageUrl(_scannedProduct!.imageUrl);
                              if (resolvedScannedImg != null && resolvedScannedImg.isNotEmpty) {
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    resolvedScannedImg,
                                    width: 64,
                                    height: 64,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.check_circle, color: Colors.green, size: 64),
                                  ),
                                );
                              }
                              return const Icon(Icons.check_circle, color: Colors.green, size: 64);
                            },
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blueAccent),
                            tooltip: 'Editar detalles',
                            onPressed: () => _showProductFormDialog(productToEdit: _scannedProduct),
                          ),
                          IconButton(
                            icon: const Icon(Icons.print, color: Colors.blueAccent),
                            tooltip: 'Imprimir en Tiquetera Térmica',
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
                        'Código: ${_scannedProduct!.barcode ?? _scannedProduct!.internalCode}',
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
                      hintText: 'Ingresar código manual...',
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

          // 3. ÁREA DE EDICIÓN
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
                      // ✅ FIX: Campo "Sumar Stock" con incremento atómico (sin race condition)
                      TextFormField(
                        controller: _addStockQuickCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Sumar Stock (+) — Opcional',
                          hintText: 'Ej: 12 (suma al stock actual)',
                          helperText: '⚡ Ingreso atómico: protegido contra ventas simultáneas',
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
                                  content: Text('¿Seguro que deseas eliminar "${_scannedProduct!.name}"? Esta acción no se puede deshacer.'),
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
                child: Text('Apuntá al Código de barras\no ingresalo manualmente.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
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












