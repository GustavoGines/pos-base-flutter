import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/config/app_config.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/utils/receipt_printer_service.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/ticket_preview_dialog.dart';
import 'package:frontend_desktop/features/logistics/services/delivery_note_pdf_service.dart';


class DeliveryNotesScreen extends StatefulWidget {
  const DeliveryNotesScreen({Key? key}) : super(key: key);

  @override
  State<DeliveryNotesScreen> createState() => _DeliveryNotesScreenState();
}

class _DeliveryNotesScreenState extends State<DeliveryNotesScreen> {
  List<dynamic> _notes = [];
  bool _isLoading = true;
  String? _error;
  final TextEditingController _scanController = TextEditingController();
  final FocusNode _scanFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _fetchNotes();
  }

  @override
  void dispose() {
    _scanController.dispose();
    _scanFocusNode.dispose();
    super.dispose();
  }

  /// Parsea el resultado escaneado (ej: "REM000042") y abre el modal del remito.
  void _onBarcodeScanned(String value) {
    _scanController.clear();
    if (value.isEmpty) return;

    // Formato esperado: REM + 6 dígitos (ej: REM000042)
    final cleaned = value.trim().toUpperCase();
    final idStr = cleaned.startsWith('REM') ? cleaned.substring(3) : cleaned;
    final noteId = int.tryParse(idStr);

    if (noteId == null) {
      SnackBarService.error(context, 'Código de remito no válido: $value');
      return;
    }

    final note = _notes.firstWhere(
      (n) => n['id'] == noteId,
      orElse: () => null,
    );

    if (note == null) {
      SnackBarService.error(context, 'Remito #${idStr.padLeft(6, "0")} no encontrado o ya fue completado.');
    } else {
      _openDispatchModal(note as Map<String, dynamic>);
    }
  }

  Future<void> _fetchNotes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      // Fallback seguro a prefs locales
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;
      final uri = Uri.parse('$baseUrl/delivery-notes');
      
      debugPrint('Fetching delivery notes from: $uri');
      
      final client = authProvider.apiClient!;
      final response = await client.get(
        uri,
        headers: {
          'Accept': 'application/json',
          // Session token is injected automatically by ApiClient!
        },
      );
      
      debugPrint('Status Code Delivery Notes: ${response.statusCode}');
      debugPrint('Body Delivery Notes: ${response.body}');

      if (response.statusCode == 200) {
        setState(() {
          _notes = jsonDecode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Error de servidor: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error de red: $e';
        _isLoading = false;
      });
    }
  }

  Color _getStatusColor(String status) {
    if (status == 'pending') return Colors.orange;
    if (status == 'partial') return Colors.blue;
    if (status == 'delivered') return Colors.green;
    return Colors.grey;
  }

  String _getStatusTranslation(String status) {
    if (status == 'pending') return 'Pendiente';
    if (status == 'partial') return 'Entrega Parcial';
    if (status == 'delivered') return 'Completado';
    return status;
  }

  void _openDispatchModal(Map<String, dynamic> note) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _DispatchModal(
        note: note,
        onDispatchComplete: () {
          Navigator.pop(ctx);
          _fetchNotes();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlobalAppBar(
        currentRoute: '/delivery-notes',
        title: 'Depósito: Remitos y Entregas',
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'scan_fab',
            backgroundColor: Colors.green.shade700,
            onPressed: () {
              // Forzar foco en el campo de escaneo
              _scanFocusNode.requestFocus();
              SnackBarService.success(context, 'Escaneá el código de barras del remito...');
            },
            child: const Icon(Icons.qr_code_scanner, color: Colors.white),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'refresh_fab',
            onPressed: _fetchNotes,
            child: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Campo de entrada del escáner (invisible pero activo) ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: TextField(
              controller: _scanController,
              focusNode: _scanFocusNode,
              decoration: InputDecoration(
                hintText: '📦 Escaneá o escribí el código del remito (ej: REM000001)',
                prefixIcon: const Icon(Icons.qr_code_scanner, color: Colors.green),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.green.shade50,
              ),
              onSubmitted: _onBarcodeScanned,
              textInputAction: TextInputAction.search,
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 60),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchNotes,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_notes.isEmpty) {
      return const Center(
        child: Text(
          'No hay remitos pendientes de entrega 🎉',
          style: TextStyle(fontSize: 24, color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _notes.length,
      itemBuilder: (context, index) {
        final note = _notes[index];
        final sale = note['sale'] ?? {};
        final customer = sale['customer'];
        final customerName = customer?['name'] ?? 'Consumidor Final';
        
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openDispatchModal(note),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    height: 60,
                    width: 60,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.airport_shuttle, color: Colors.blue.shade800, size: 32),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Comprobante #${sale['id']} - $customerName',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Generado: ${note['created_at']?.split('T')[0]}',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                  Chip(
                    label: Text(
                      _getStatusTranslation(note['status']),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: _getStatusColor(note['status']),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.chevron_right, size: 32, color: Colors.grey),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DispatchModal extends StatefulWidget {
  final Map<String, dynamic> note;
  final VoidCallback onDispatchComplete;

  const _DispatchModal({
    required this.note,
    required this.onDispatchComplete,
  });

  @override
  State<_DispatchModal> createState() => _DispatchModalState();
}

class _DispatchModalState extends State<_DispatchModal> {
  late List<dynamic> _items;
  final Map<int, TextEditingController> _controllers = {};
  bool _isSubmitting = false;
  bool _showPreview = false;
  bool _printOnDispatch = true;
  bool _printA4 = false;
  bool _showA4Preview = true;

  @override
  void initState() {
    super.initState();
    _items = widget.note['items'] ?? [];
    _loadPrefs();
    
    for (var item in _items) {
      final purchased = double.parse(item['quantity_purchased'].toString());
      final delivered = double.parse(item['quantity_delivered'].toString());
      final remaining = purchased - delivered;
      
      _controllers[item['id']] = TextEditingController(text: remaining > 0 ? remaining.toString() : '0');
    }
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _showPreview = prefs.getBool('show_preview_remito') ?? false;
        _printOnDispatch = prefs.getBool('print_on_dispatch') ?? true;
        _printA4 = prefs.getBool('print_a4_remito') ?? false;
        _showA4Preview = prefs.getBool('show_a4_preview_remito') ?? true;
      });
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submitDispatch() async {
    List<Map<String, dynamic>> payload = [];
    bool hasInvalidAmmount = false;

    for (var item in _items) {
      final ctrl = _controllers[item['id']];
      final deliverNow = double.tryParse(ctrl?.text ?? '0') ?? 0;
      
      final purchased = double.parse(item['quantity_purchased'].toString());
      final delivered = double.parse(item['quantity_delivered'].toString());
      final remaining = purchased - delivered;

      if (deliverNow < 0 || deliverNow > remaining) {
        hasInvalidAmmount = true;
        break;
      }

      if (deliverNow > 0) {
        payload.add({
          'id': item['id'],
          'delivered_now': deliverNow,
        });
      }
    }

    if (hasInvalidAmmount) {
      SnackBarService.error(context, 'Las cantidades a entregar no pueden superar a lo faltante de entregar.');
      return;
    }

    if (payload.isEmpty) {
      SnackBarService.warning(context, 'No ingresó ninguna cantidad a entregar.');
      return;
    }

    // Si está activado "Vista Previa", mostrar ticket simulado antes de confirmar
    if (_printOnDispatch && _showPreview) {
      final sale = widget.note['sale'] ?? {};
      final customerName = sale['customer']?['name'] ?? 'Consumidor Final';
      final previewLines = <TicketLine>[
        TicketLine('COMPROBANTE DE ENTREGA / REMITO', align: TicketAlign.center, isBold: true, isLarge: true),
        const TicketLine.hr(bold: true),
        TicketLine('REMITO N°: ${widget.note['id'].toString().padLeft(6, '0')}', isBold: true),
        TicketLine('CLIENTE: $customerName'),
        const TicketLine.hr(),
        ...payload.map((d) {
          final item = (widget.note['items'] as List).firstWhere((i) => i['id'] == d['id'], orElse: () => null);
          if (item == null) return [const TicketLine.space()];
          final name = (item['product']?['name'] ?? 'Producto').toUpperCase();
          final purchased = double.parse(item['quantity_purchased'].toString());
          final deliveredBefore = double.parse(item['quantity_delivered'].toString());
          final deliveredNow = d['delivered_now'] as double;
          final remaining = purchased - (deliveredBefore + deliveredNow);
          return [
            TicketLine(name, isBold: true),
            TicketLine('Comprado: ${purchased.toStringAsFixed(1)} | Entregando: ${deliveredNow.toStringAsFixed(1)}'),
            TicketLine('SALDO PENDIENTE: ${remaining.toStringAsFixed(1)}', isBold: true),
            const TicketLine.space(),
          ];
        }).expand((l) => l),
        const TicketLine.hr(bold: true),
        const TicketLine('FIRMA CONFORMIDAD:', align: TicketAlign.center),
      ];

      if (!mounted) return;
      final confirmed = await TicketPreviewDialog.show(
        context,
        title: 'Vista Previa — Remito #${widget.note['id']}',
        lines: previewLines,
      );
      if (!mounted || !confirmed) {
        setState(() => _isSubmitting = false);
        return;
      }
    }

    setState(() => _isSubmitting = true);

    try {
      final authProvider = context.read<AuthProvider>();
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;

      final client = authProvider.apiClient!;
      final response = await client.put(
        Uri.parse('$baseUrl/delivery-notes/${widget.note['id']}/deliver'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'items': payload}),
      );

      if (response.statusCode == 200) {
        // 1. Imprimir remito térmico
        try {
          if (!mounted) return;
          final settings = context.read<SettingsProvider>().settings;
          if (settings != null && _printOnDispatch) {
            final sale = widget.note['sale'] ?? {};
            final customerName = sale['customer']?['name'];
            
            await ReceiptPrinterService.instance.printDeliveryNoteTicket(
              note: widget.note,
              deliveredItemsData: payload,
              settings: settings,
              customerName: customerName,
            );
          }
        } catch (e) {
          debugPrint('Error comprobante remito térmico: $e');
        }

        // 2. Imprimir / mostrar Remito A4
        if (_printA4) {
          try {
            if (!mounted) return;
            final settings = context.read<SettingsProvider>().settings;
            // Construir mapa de cantidades entregadas para resaltar en el PDF
            final deliveredNowMap = <int, double>{
              for (final p in payload)
                if (p['id'] != null) (p['id'] as int): ((p['delivered_now'] as num?)?.toDouble() ?? 0.0)
            };
            if (_showA4Preview) {
              await DeliveryNotePdfService.preview(
                context: context,
                note: widget.note,
                businessName: settings?.companyName ?? 'Mi Negocio',
                businessAddress: settings?.address,
                businessPhone: settings?.phone,
                businessTaxId: settings?.taxId,
                deliveredNow: deliveredNowMap,
              );
            } else {
              await DeliveryNotePdfService.printDirect(
                note: widget.note,
                businessName: settings?.companyName ?? 'Mi Negocio',
                businessAddress: settings?.address,
                businessPhone: settings?.phone,
                businessTaxId: settings?.taxId,
                deliveredNow: deliveredNowMap,
              );
            }
          } catch (e) {
            debugPrint('Error imprimiendo remito A4: $e');
          }
        }

        if (!mounted) return;
        SnackBarService.success(context, 'Entrega registrada${_printOnDispatch ? ' e impresa' : ''}${_printA4 ? ' (+ A4)' : ''}.');
        widget.onDispatchComplete();
      } else {
        final body = jsonDecode(response.body);
        if (!mounted) return;
        SnackBarService.error(context, body['message'] ?? 'Error desconocido');
        setState(() => _isSubmitting = false);
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarService.error(context, 'Error de red: $e');
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Padding bottom for keyboard
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 32,
        right: 32,
        top: 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Preparación de Despacho #${widget.note['id']}',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 32),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _items.length,
              separatorBuilder: (context, index) => const Divider(height: 32),
              itemBuilder: (context, index) {
                final item = _items[index];
                final product = item['product'] ?? {};
                final purchased = double.parse(item['quantity_purchased'].toString());
                final delivered = double.parse(item['quantity_delivered'].toString());
                final remaining = purchased - delivered;
                
                final isCompleted = remaining <= 0;

                return Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(product['name'] ?? 'Producto Desconocido', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                                child: Text('Pagado: $purchased', style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                                child: Text('Aún Restan: $remaining', style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: isCompleted 
                        ? const Chip(label: Text('Finalizado', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green)
                        : TextField(
                            controller: _controllers[item['id']],
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Entrega AHORA',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              filled: true,
                              fillColor: Colors.orange.shade50,
                            ),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                    )
                  ],
                );
              },
            ),
          ),
          
          const SizedBox(height: 12),

          // ── Opciones de impresión ────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Opciones de Impresión',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 10),

                // ── Fila: Remito Térmico ──────────────────────────────────
                Row(
                  children: [
                    Checkbox(
                      value: _printOnDispatch,
                      activeColor: Colors.green,
                      onChanged: (val) async {
                        if (val != null) {
                          setState(() => _printOnDispatch = val);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('print_on_dispatch', val);
                        }
                      },
                    ),
                    const Icon(Icons.receipt_long, size: 18, color: Colors.green),
                    const SizedBox(width: 6),
                    const Text('Remito Térmico (58/80mm)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    if (_printOnDispatch) ...[
                      const SizedBox(width: 20),
                      Checkbox(
                        value: _showPreview,
                        activeColor: Colors.orange,
                        onChanged: (val) async {
                          if (val != null) {
                            setState(() => _showPreview = val);
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('show_preview_remito', val);
                          }
                        },
                      ),
                      const Text('Vista Previa antes de imprimir', style: TextStyle(fontSize: 13)),
                    ],
                  ],
                ),

                const Divider(height: 12),

                // ── Fila: Remito A4 ───────────────────────────────────────
                Row(
                  children: [
                    Checkbox(
                      value: _printA4,
                      activeColor: Colors.blue.shade700,
                      onChanged: (val) async {
                        if (val != null) {
                          setState(() => _printA4 = val);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('print_a4_remito', val);
                        }
                      },
                    ),
                    Icon(Icons.picture_as_pdf, size: 18, color: Colors.blue.shade700),
                    const SizedBox(width: 6),
                    const Text('Remito A4 (Impresora Láser)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    if (_printA4) ...[
                      const SizedBox(width: 20),
                      Checkbox(
                        value: _showA4Preview,
                        activeColor: Colors.blue.shade400,
                        onChanged: (val) async {
                          if (val != null) {
                            setState(() => _showA4Preview = val);
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('show_a4_preview_remito', val);
                          }
                        },
                      ),
                      const Text('Ver PDF antes de imprimir', style: TextStyle(fontSize: 13)),
                    ],
                  ],
                ),

                const Divider(height: 12),

                // ── Botón rápido: solo ver el PDF A4 sin despachar ─────────
                TextButton.icon(
                  onPressed: () {
                    final settings = context.read<SettingsProvider>().settings;
                    DeliveryNotePdfService.preview(
                      context: context,
                      note: widget.note,
                      businessName: settings?.companyName ?? 'Mi Negocio',
                      businessAddress: settings?.address,
                      businessPhone: settings?.phone,
                      businessTaxId: settings?.taxId,
                    );
                  },
                  icon: Icon(Icons.preview, color: Colors.blue.shade700),
                  label: Text('Ver Remito A4 sin despachar',
                      style: TextStyle(color: Colors.blue.shade700, fontSize: 12)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            height: 60,
            child: FilledButton.icon(
              onPressed: _isSubmitting ? null : _submitDispatch,
              icon: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.check_circle_outline, size: 28),
              label: Text(_isSubmitting ? 'Procesando...' : 'Confirmar Salida de Bodega', style: const TextStyle(fontSize: 20)),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                backgroundColor: Colors.green.shade700,
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
