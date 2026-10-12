import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../core/network/api_client.dart';
import '../providers/settings_provider.dart';

class EcommerceSyncLogsDialog extends StatefulWidget {
  const EcommerceSyncLogsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => const EcommerceSyncLogsDialog(),
    );
  }

  @override
  State<EcommerceSyncLogsDialog> createState() => _EcommerceSyncLogsDialogState();
}

class _EcommerceSyncLogsDialogState extends State<EcommerceSyncLogsDialog> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _logs = [];
  int _currentPage = 1;
  int _lastPage = 1;
  int _totalLogs = 0;

  String? _statusFilter; // null (todos), 'success', 'failed'
  String? _directionFilter; // null (todos), 'inbound', 'outbound'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchLogs();
    });
  }

  Future<void> _fetchLogs({int page = 1}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final settingsProv = context.read<SettingsProvider>();
      final client = context.read<ApiClient>();
      final baseUrl = settingsProv.currentApiUrl;

      final queryParams = <String, String>{
        'page': page.toString(),
        'per_page': '25',
      };
      if (_statusFilter != null) {
        queryParams['status'] = _statusFilter!;
      }
      if (_directionFilter != null) {
        queryParams['direction'] = _directionFilter!;
      }

      final uri = Uri.parse('$baseUrl/ecommerce/logs').replace(queryParameters: queryParams);
      final response = await client.get(uri);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final rawData = decoded['data'] as List<dynamic>? ?? [];
        final items = rawData.map((e) => Map<String, dynamic>.from(e as Map)).toList();

        setState(() {
          _logs = items;
          _currentPage = decoded['current_page'] ?? page;
          _lastPage = decoded['last_page'] ?? 1;
          _totalLogs = decoded['total'] ?? items.length;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Error ${response.statusCode} al obtener bitácora de sincronización.';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Fallo de conexión: $e';
        _isLoading = false;
      });
    }
  }

  Color _getPlatformColor(String? platform) {
    switch (platform?.toLowerCase()) {
      case 'mercadolibre':
        return const Color(0xFFF57F17);
      case 'woocommerce':
        return const Color(0xFF7F54B3);
      case 'tiendanube':
        return const Color(0xFF00897B);
      case 'ecommerce_platform':
        return const Color(0xFF0D9488);
      default:
        return Colors.blueGrey;
    }
  }

  String _getPlatformLabel(String? platform) {
    switch (platform?.toLowerCase()) {
      case 'mercadolibre':
        return 'Mercado Libre';
      case 'woocommerce':
        return 'WooCommerce';
      case 'tiendanube':
        return 'Tienda Nube';
      case 'ecommerce_platform':
        return 'Plataforma Web (Propia)';
      default:
        return platform ?? 'E-Commerce';
    }
  }

  String _formatAction(String? action) {
    switch (action) {
      case 'stock_update':
        return 'Actualización de Stock';
      case 'order_deduction':
        return 'Descuento por Venta Online';
      case 'order_cancellation':
        return 'Reversión por Cancelación';
      case 'webhook_received':
        return 'Recepción de Webhook';
      default:
        return action ?? 'Operación';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 850, maxHeight: 680),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF673AB7).withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF673AB7).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.history_outlined, color: Color(0xFF673AB7), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bitácora de Sincronización E-Commerce',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Trazabilidad auditada de stock y ventas omnicanal ($_totalLogs registros)',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Actualizar',
                    icon: const Icon(Icons.refresh),
                    onPressed: _isLoading ? null : () => _fetchLogs(page: _currentPage),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Filtros rápidos
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              color: Colors.grey.shade50,
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Filtros:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ChoiceChip(
                    label: const Text('Todos'),
                    selected: _statusFilter == null && _directionFilter == null,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _statusFilter = null;
                          _directionFilter = null;
                        });
                        _fetchLogs(page: 1);
                      }
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Solo Exitosos'),
                    selected: _statusFilter == 'success',
                    selectedColor: Colors.green.shade100,
                    onSelected: (selected) {
                      setState(() => _statusFilter = selected ? 'success' : null);
                      _fetchLogs(page: 1);
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Solo Fallidos'),
                    selected: _statusFilter == 'failed',
                    selectedColor: Colors.red.shade100,
                    onSelected: (selected) {
                      setState(() => _statusFilter = selected ? 'failed' : null);
                      _fetchLogs(page: 1);
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Entrantes (Webhooks)'),
                    selected: _directionFilter == 'inbound',
                    selectedColor: Colors.blue.shade100,
                    onSelected: (selected) {
                      setState(() => _directionFilter = selected ? 'inbound' : null);
                      _fetchLogs(page: 1);
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Salientes (Hacia Tiendas)'),
                    selected: _directionFilter == 'outbound',
                    selectedColor: Colors.purple.shade100,
                    onSelected: (selected) {
                      setState(() => _directionFilter = selected ? 'outbound' : null);
                      _fetchLogs(page: 1);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Content
            Expanded(
              child: _buildBody(),
            ),

            // Footer / Pagination
            if (_lastPage > 1)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Página $_currentPage de $_lastPage',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: _currentPage > 1 && !_isLoading
                              ? () => _fetchLogs(page: _currentPage - 1)
                              : null,
                          child: const Text('Anterior'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _currentPage < _lastPage && !_isLoading
                              ? () => _fetchLogs(page: _currentPage + 1)
                              : null,
                          child: const Text('Siguiente'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
              const SizedBox(height: 12),
              Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _fetchLogs(page: _currentPage),
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.rule_folder_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'No hay registros de sincronización para los filtros seleccionados.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _logs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final log = _logs[index];
        final isSuccess = log['status'] == 'success';
        final isInbound = log['direction'] == 'inbound';
        final integration = log['integration'] as Map<String, dynamic>?;
        final platform = integration?['platform']?.toString();
        final brandColor = _getPlatformColor(platform);
        final platformName = integration?['name']?.toString() ?? _getPlatformLabel(platform);

        DateTime? createdAt;
        if (log['created_at'] != null) {
          try {
            createdAt = DateTime.parse(log['created_at'].toString()).toLocal();
          } catch (_) {}
        }
        final dateStr = createdAt != null
            ? DateFormat('dd/MM/yyyy HH:mm:ss').format(createdAt)
            : 'Fecha desconocida';

        final stockBefore = log['stock_before'];
        final stockAfter = log['stock_after'];
        final durationMs = log['duration_ms'];
        final errorMsg = log['error_message'];
        final externalOrderId = log['external_order_id'];

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: isSuccess ? Colors.grey.shade200 : Colors.red.shade200,
            ),
          ),
          color: isSuccess ? Colors.white : Colors.red.shade50.withValues(alpha: 0.3),
          child: ExpansionTile(
            key: ValueKey('log_${log['id']}'),
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            childrenPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: isSuccess ? Colors.green.shade50 : Colors.red.shade50,
              child: Icon(
                isSuccess ? Icons.check_circle_outline : Icons.cancel_outlined,
                color: isSuccess ? Colors.green.shade700 : Colors.red.shade700,
                size: 20,
              ),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: brandColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    platformName,
                    style: TextStyle(
                      color: brandColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isInbound ? Colors.blue.shade50 : Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isInbound ? Icons.arrow_downward : Icons.arrow_upward,
                        size: 11,
                        color: isInbound ? Colors.blue.shade700 : Colors.purple.shade700,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        isInbound ? 'Entrante' : 'Saliente',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isInbound ? Colors.blue.shade700 : Colors.purple.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  dateStr,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _formatAction(log['action']?.toString()),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  if (stockBefore != null && stockAfter != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Text(
                        'Stock: $stockBefore ➔ $stockAfter',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (durationMs != null)
                    Text(
                      '${durationMs}ms',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                ],
              ),
            ),
            children: [
              if (errorMsg != null && errorMsg.toString().isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 18, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Detalle del error: $errorMsg',
                          style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              if (externalOrderId != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      const Text('Orden Externa: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      Text('$externalOrderId', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              if (log['http_status'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      const Text('Código HTTP: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      Text('${log['http_status']}', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              if (log['request_payload'] != null) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Payload Enviado:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(log['request_payload']),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ],
              if (log['response_payload'] != null) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Respuesta del Servidor:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(log['response_payload']),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
