import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import '../providers/logistics_provider.dart';
import '../views/delivery_notes_tab_view.dart';

// Helper para mostrar el dialog de ajustes de terminal
void _showTerminalSettingsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(children: [
        Icon(Icons.print, color: Colors.blue),
        SizedBox(width: 8),
        Text('Ajustes de Impresión'),
      ]),
      content: Consumer<LocalTerminalProvider>(
        builder: (context, p, _) => SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Formato:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: p.printerFormat,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'thermal_80', child: Text('Térmica 80mm')),
                    DropdownMenuItem(value: 'thermal_58', child: Text('Térmica 58mm')),
                    DropdownMenuItem(value: 'a4', child: Text('Hoja Completa (A4/Carta)')),
                  ],
                  onChanged: (v) { if (v != null) p.setPrinterFormat(v); },
                ),
                if (p.printerFormat == 'a4') ...[
                  const SizedBox(height: 12),
                  const Text('Tamaño de papel:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: p.pdfPaperSize,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'a4', child: Text('A4 (Predeterminado)')),
                      DropdownMenuItem(value: 'letter', child: Text('Carta (Letter)')),
                    ],
                    onChanged: (v) { if (v != null) p.setPdfPaperSize(v); },
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                  child: const Row(children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 16),
                    SizedBox(width: 8),
                    Expanded(child: Text('Se aplica solo a esta terminal.', style: TextStyle(fontSize: 12, color: Colors.blue))),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
    ),
  );
}

class LogisticsDashboardScreen extends StatefulWidget {
  const LogisticsDashboardScreen({Key? key}) : super(key: key);

  @override
  State<LogisticsDashboardScreen> createState() => _LogisticsDashboardScreenState();
}

class _LogisticsDashboardScreenState extends State<LogisticsDashboardScreen> {
  final TextEditingController _searchController = TextEditingController();
  late LogisticsProvider _logisticsProvider;

  @override
  void initState() {
    super.initState();
    _logisticsProvider = context.read<LogisticsProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _logisticsProvider.startPolling();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _logisticsProvider.stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: const GlobalAppBar(
          currentRoute: '/delivery-notes',
          title: 'Dashboard Logístico',
        ),
        body: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  // ── TabBar (Izquierda) ──
                  const Expanded(
                    flex: 2,
                    child: TabBar(
                      labelColor: Colors.blue,
                      unselectedLabelColor: Colors.grey,
                      indicatorWeight: 3,
                      tabs: [
                        Tab(text: 'PENDIENTES', icon: Icon(Icons.pending_actions, size: 20)),
                        Tab(text: 'EN CURSO', icon: Icon(Icons.timelapse, size: 20)),
                        Tab(text: 'COMPLETADOS', icon: Icon(Icons.check_circle, size: 20)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  // ── Buscador (Derecha) ──
                  Expanded(
                    flex: 1,
                    child: SizedBox(
                      height: 40,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) {
                          context.read<LogisticsProvider>().onSearchChanged(value);
                          setState(() {}); 
                        },
                        decoration: InputDecoration(
                          hintText: 'Buscar remito o cliente...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    context.read<LogisticsProvider>().onSearchChanged('');
                                    setState(() {});
                                  },
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // ── Ícono de Ajustes de Impresión ──
                  IconButton(
                    icon: const Icon(Icons.print, color: Colors.blueGrey),
                    tooltip: 'Ajustes de Impresión de esta Terminal',
                    onPressed: () => _showTerminalSettingsDialog(context),
                  ),
                ],
              ),
            ),
            
            const Divider(height: 1, thickness: 1),

            // ── TabBarView ──
            const Expanded(
              child: TabBarView(
                children: [
                  DeliveryNotesTabView(status: 'pending'),
                  DeliveryNotesTabView(status: 'partial'),
                  DeliveryNotesTabView(status: 'delivered'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
