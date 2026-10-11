import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/config/app_config.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../providers/catalog_provider.dart';

class CatalogImportDialog extends StatefulWidget {
  const CatalogImportDialog({super.key});

  @override
  State<CatalogImportDialog> createState() => _CatalogImportDialogState();
}

class _CatalogImportDialogState extends State<CatalogImportDialog> {
  bool _isLoading = false;
  bool _isDragging = false;
  
  String? _selectedFilename;
  Uint8List? _selectedFileBytes;

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

    setState(() => _isLoading = true);
    try {
      final provider = context.read<CatalogProvider>();
      final result = await provider.importProducts(
        fileBytes: _selectedFileBytes!,
        filename: _selectedFilename!,
      );
      
      if (mounted) {
        Navigator.of(context).pop(true);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  result['created_count'] == 0 && result['updated_count'] == 0 
                      ? Icons.warning_amber_rounded 
                      : Icons.check_circle, 
                  color: result['created_count'] == 0 && result['updated_count'] == 0 
                      ? Colors.orange 
                      : Colors.green,
                ),
                const SizedBox(width: 8),
                Text(
                  result['created_count'] == 0 && result['updated_count'] == 0 
                      ? 'No se importó nada' 
                      : 'Importación Exitosa'
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result['created_count'] == 0 && result['updated_count'] == 0) ...[
                  const Text('El sistema no pudo encontrar productos válidos para importar.'),
                  const SizedBox(height: 8),
                  const Text('⚠️ Asegúrate de que la primera fila de tu Excel tenga exactamente los nombres de las columnas que espera el sistema (ej: "nombre", "codigo_interno", "precio"). Si usaste el archivo crudo del proveedor, debes renombrar las columnas.', style: TextStyle(fontWeight: FontWeight.bold)),
                ] else ...[
                  Text('• Productos creados: ${result['created_count']}'),
                  Text('• Productos actualizados: ${result['updated_count']}'),
                  Text('• Errores (ignorados): ${result['failed_count']}'),
                  if (result['failed_count'] > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text('Revisa tu Excel. Hubo filas vacías o sin nombre.', style: TextStyle(color: Colors.red.shade800, fontSize: 12)),
                    ),
                ]
              ],
            ),
            actions: [
              TextButton(
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
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: _handleDrop,
      child: AlertDialog(
        title: const Text('Importar Catálogo (Excel / CSV)'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Arrastra tu archivo aquí o haz clic para seleccionarlo. El sistema actualizará los precios y creará los productos nuevos automáticamente.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Descargar Plantilla (Opcional)'),
                onPressed: _downloadTemplate,
              ),
              const SizedBox(height: 24),
              InkWell(
                onTap: _pickFile,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _isDragging ? Colors.green : Colors.blue.shade300, 
                      style: BorderStyle.solid,
                      width: _isDragging ? 2.0 : 1.0,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    color: _isDragging ? Colors.green.shade50 : Colors.blue.shade50,
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _selectedFilename != null ? Icons.file_present : Icons.upload_file,
                        size: 48,
                        color: _isDragging ? Colors.green : Colors.blue.shade700,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _selectedFilename != null
                            ? 'Archivo listo: $_selectedFilename'
                            : 'Suelta el Excel aquí o haz clic',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _isDragging ? Colors.green.shade800 : Colors.blue.shade900,
                          fontWeight: _selectedFilename != null ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_isLoading) ...[
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 8),
                const Center(child: Text('Procesando archivo, no cierres esta ventana...')),
              ]
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: (_isLoading || _selectedFilename == null) ? null : _importData,
            icon: const Icon(Icons.upload, size: 18),
            label: const Text('Comenzar Importación'),
          ),
        ],
      ),
    );
  }
}
