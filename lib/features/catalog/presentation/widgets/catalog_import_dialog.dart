import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/config/app_config.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
import 'package:frontend_desktop/core/utils/search_text_utils.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';
import '../providers/catalog_provider.dart';

class CatalogImportDialog extends StatefulWidget {
  final int? initialSupplierId;
  final String? initialSupplierName;

  const CatalogImportDialog({
    super.key,
    this.initialSupplierId,
    this.initialSupplierName,
  });

  @override
  State<CatalogImportDialog> createState() => _CatalogImportDialogState();
}

class _CatalogImportDialogState extends State<CatalogImportDialog> {
  bool _isLoading = false;
  bool _isDragging = false;

  String? _selectedFilename;
  Uint8List? _selectedFileBytes;
  int? _selectedSupplierId;
  final TextEditingController _marginCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedSupplierId = widget.initialSupplierId;
    if (_selectedSupplierId == null) {
      try {
        _selectedSupplierId = context.read<CatalogProvider?>()?.safeFilterSupplierId;
      } catch (_) {}
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final supProv = context.read<SupplierProvider?>();
        if (supProv != null && supProv.suppliers.isEmpty) {
          supProv.fetchSuppliers();
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _marginCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv', 'txt'],
      withData: true,
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      if (file.bytes != null) {
        setState(() {
          _selectedFilename = file.name;
          _selectedFileBytes = file.bytes;
        });
      }
    }
  }

  Future<void> _handleDrop(DropDoneDetails details) async {
    if (details.files.isNotEmpty) {
      final file = details.files.first;
      // Validar extensión
      final name = file.name.toLowerCase();
      if (!name.endsWith('.xlsx') && !name.endsWith('.xls') && !name.endsWith('.csv') && !name.endsWith('.txt')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Formato no válido. Solo se admiten archivos Excel (.xlsx, .xls) o .csv'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      final bytes = await file.readAsBytes();
      setState(() {
        _selectedFilename = file.name;
        _selectedFileBytes = bytes;
      });
    }
  }

  Future<void> _downloadTemplate() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;
      final token = prefs.getString('pos_session_token');

      final downloadUri = Uri.parse('$baseUrl/catalog/products/import-template');
      final response = await http.get(
        downloadUri,
        headers: {
          'X-Session-Token': token ?? '',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet, application/octet-stream, */*',
        },
      );

      if (response.statusCode == 200) {
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar Plantilla de Importación',
          fileName: 'plantilla_importacion_productos.xlsx',
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
        );

        if (outputFile != null) {
          final file = File(outputFile);
          await file.writeAsBytes(response.bodyBytes);
          if (mounted) {
            SnackBarService.success(context, 'Plantilla guardada exitosamente.');
          }
        }
      } else {
        // Fallback a navegador si la descarga directa requiere redirección externa
        final fallbackUri = Uri.parse('$baseUrl/catalog/products/import-template?token=$token');
        if (await canLaunchUrl(fallbackUri)) {
          await launchUrl(fallbackUri);
        } else if (mounted) {
          SnackBarService.error(context, 'Error al descargar plantilla (${response.statusCode}).');
        }
      }
    } catch (e) {
      debugPrint('Error downloading template: $e');
      if (mounted) {
        SnackBarService.error(context, 'Error al descargar la plantilla: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _importData() async {
    if (_selectedFileBytes == null || _selectedFilename == null) return;

    final rawMargin = _marginCtrl.text.trim().replaceAll(',', '.');
    final parsedMargin = rawMargin.isEmpty ? null : double.tryParse(rawMargin);
    if (rawMargin.isNotEmpty && (parsedMargin == null || parsedMargin < 0)) {
      SnackBarService.error(
        context,
        'Ingresá un porcentaje de margen válido (mayor o igual a 0).',
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final provider = context.read<CatalogProvider>();
      final result = await provider.importProducts(
        fileBytes: _selectedFileBytes!,
        filename: _selectedFilename!,
        defaultSupplierId: _selectedSupplierId,
        defaultMarginPercent: parsedMargin,
      );
      
      if (mounted) {
        Navigator.of(context).pop(true);
        final noImported =
            result['created_count'] == 0 && result['updated_count'] == 0;
        showDialog(
          context: context,
          builder: (ctx) => AppModalShell(
            title: noImported ? 'No se importó nada' : 'Importación Exitosa',
            subtitle: 'Resultado de la importación de catálogo',
            icon: noImported
                ? Icons.warning_amber_rounded
                : Icons.check_circle_rounded,
            accent:
                noImported ? AppModalAccent.amber : AppModalAccent.emerald,
            compact: true,
            maxWidth: 460,
            bodyPadding: const EdgeInsets.all(18),
            body: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (noImported) ...[
                  const Text(
                    'El sistema no pudo encontrar productos válidos para importar.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '⚠️ Asegúrate de que la primera fila de tu Excel tenga exactamente los nombres de las columnas que espera el sistema (ej: "nombre", "codigo_interno", "precio"). Si usaste el archivo crudo del proveedor, debes renombrar las columnas.',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ] else ...[
                  Text('• Productos creados: ${result['created_count']}'),
                  Text('• Productos actualizados: ${result['updated_count']}'),
                  Text('• Errores (ignorados): ${result['failed_count']}'),
                  if (result['failed_count'] > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'Revisa tu Excel. Hubo filas vacías o sin nombre.',
                        style: TextStyle(
                          color: Colors.red.shade800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ],
            ),
            footerActions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red.shade800,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    SettingsProvider? settingsProv;
    SupplierProvider? supplierProv;
    try {
      settingsProv = context.watch<SettingsProvider?>();
    } catch (_) {}
    try {
      supplierProv = context.watch<SupplierProvider?>();
    } catch (_) {}

    final canSeeSupplier =
        (settingsProv?.features.suppliers ?? true) && supplierProv != null;
    final suppliers = supplierProv != null
        ? sortByAlphabeticalName<Supplier>(
            supplierProv.suppliers,
            (s) => s.name,
          )
        : <Supplier>[];
    final hasMatchingSupplier =
        _selectedSupplierId != null && suppliers.any((s) => s.id == _selectedSupplierId);
    final effectiveSupplierValue =
        hasMatchingSupplier ? _selectedSupplierId : (_selectedSupplierId != null && widget.initialSupplierName != null ? _selectedSupplierId : null);

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: _handleDrop,
      child: AppModalShell(
        title: 'Importar Catálogo (Excel / CSV)',
        subtitle: 'Alta y actualización masiva desde planilla',
        icon: Icons.upload_file_rounded,
        accent: AppModalAccent.emerald,
        maxWidth: 520,
        showCloseButton: !_isLoading,
        bodyPadding: const EdgeInsets.all(18),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Arrastra tu archivo aquí o haz clic para seleccionarlo. El sistema actualizará costos/precios y creará productos nuevos automáticamente.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text(
                'Columnas opcionales compatibles: cod_proveedor, medida, ubicacion, unidad (mt/m2/m3/bolsa/rollo/caja/par/kg/lt), presentacion_compra y factor_conversion.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Descargar Plantilla (Opcional)'),
              onPressed: _isLoading ? null : _downloadTemplate,
            ),
            const SizedBox(height: 14),
            if (canSeeSupplier) ...[
              DropdownButtonFormField<int?>(
                key: const ValueKey('import_default_supplier_dropdown'),
                isExpanded: true,
                initialValue: effectiveSupplierValue,
                decoration: const InputDecoration(
                  labelText: 'Proveedor por defecto (Opcional)',
                  helperText:
                      'Se asigna a las filas sin columna "proveedor" y prioriza el match por cod_proveedor',
                  prefixIcon: Icon(Icons.local_shipping_outlined),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('— Según Excel / Sin proveedor fijo —'),
                  ),
                  if (!hasMatchingSupplier &&
                      _selectedSupplierId != null &&
                      widget.initialSupplierName != null)
                    DropdownMenuItem<int?>(
                      value: _selectedSupplierId,
                      child: Text(widget.initialSupplierName!),
                    ),
                  ...suppliers.map(
                    (s) => DropdownMenuItem<int?>(
                      value: s.id,
                      child: Text(s.name, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: _isLoading
                    ? null
                    : (val) => setState(() => _selectedSupplierId = val),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              key: const ValueKey('import_default_margin_field'),
              controller: _marginCtrl,
              enabled: !_isLoading,
              decoration: const InputDecoration(
                labelText: '% Margen por defecto (Opcional)',
                helperText:
                    'Si una fila trae Costo sin Precio Venta, calcula PVP = Costo × (1 + %)',
                prefixIcon: Icon(Icons.percent),
                suffixText: '%',
                isDense: true,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _isLoading ? null : _pickFile,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _isDragging ? Colors.green : AppColors.primaryBorder,
                    style: BorderStyle.solid,
                    width: _isDragging ? 2.0 : 1.0,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  color: _isDragging
                      ? Colors.green.shade50
                      : AppColors.primarySoft,
                ),
                child: Column(
                  children: [
                    Icon(
                      _selectedFilename != null
                          ? Icons.file_present
                          : Icons.upload_file,
                      size: 42,
                      color: _isDragging ? Colors.green : AppColors.primaryDark,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _selectedFilename != null
                          ? 'Archivo listo: $_selectedFilename'
                          : 'Suelta el Excel aquí o haz clic',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _isDragging
                            ? Colors.green.shade800
                            : const Color(0xFF1E3A8A),
                        fontWeight: _selectedFilename != null
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_isLoading) ...[
              const SizedBox(height: 18),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 8),
              const Center(
                child: Text('Procesando archivo, no cierres esta ventana...'),
              ),
            ],
          ],
        ),
        footerActions: [
          TextButton(
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            key: const ValueKey('import_catalog_submit_btn'),
            onPressed:
                (_isLoading || _selectedFilename == null) ? null : _importData,
            icon: const Icon(Icons.upload, size: 18),
            label: const Text('Comenzar Importación'),
          ),
        ],
      ),
    );
  }
}
