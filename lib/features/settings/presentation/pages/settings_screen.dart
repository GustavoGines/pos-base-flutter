import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../../../../core/utils/snack_bar_service.dart';
import '../../../../core/utils/receipt_printer_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  // Negocio
  final _companyNameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _taxIdCtrl = TextEditingController();
  final _footerCtrl = TextEditingController();

  // Impresora
  String _printerType = 'none'; // 'none', 'usb', 'network'
  final _comPortCtrl = TextEditingController();
  final _ipAddressCtrl = TextEditingController();
  final _ipPortCtrl = TextEditingController();

  // Balanza
  final _comPortScaleCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-llenar datos si existen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<SettingsProvider>();
      final settings = provider.settings;
      if (settings != null) {
        _companyNameCtrl.text = settings.companyName ?? '';
        _addressCtrl.text = settings.address ?? '';
        _phoneCtrl.text = settings.phone ?? '';
        _taxIdCtrl.text = settings.taxId ?? '';
        _footerCtrl.text = settings.receiptFooterMessage ?? '';
        
        _printerType = settings.printerType;
        _comPortCtrl.text = settings.printerComPort ?? '';
        _ipAddressCtrl.text = settings.printerIpAddress ?? '';
        _ipPortCtrl.text = settings.printerIpPort ?? '';
        
        _comPortScaleCtrl.text = settings.comPortScale ?? '';
        if (mounted) {
           setState(() {}); 
        }
      }
    });
  }

  @override
  void dispose() {
    _companyNameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _taxIdCtrl.dispose();
    _footerCtrl.dispose();
    _comPortCtrl.dispose();
    _ipAddressCtrl.dispose();
    _ipPortCtrl.dispose();
    _comPortScaleCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<SettingsProvider>();
    final data = {
      'company_name': _companyNameCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'tax_id': _taxIdCtrl.text.trim(),
      'receipt_footer_message': _footerCtrl.text.trim(),
      'printer_type': _printerType,
      'printer_com_port': _comPortCtrl.text.trim(),
      'printer_ip_address': _ipAddressCtrl.text.trim(),
      'printer_ip_port': _ipPortCtrl.text.trim(),
      'com_port_scale': _comPortScaleCtrl.text.trim(),
    };

    final success = await provider.saveSettings(data);
    
    if (!mounted) return;

    if (success) {
      // Reconfigurar HW en vivo
      await ReceiptPrinterService.instance.reconfigureFromSettings(provider.settings!);
      SnackBarService.success(context, 'Configuración guardada y hardware actualizado');
    } else {
      SnackBarService.error(context, provider.errorMessage ?? 'Error al guardar configuración');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración del Sistema'),
        elevation: 0,
        actions: [
          Consumer<AuthProvider>(
            builder: (context, auth, _) {
              if (!auth.isAdmin) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pushNamed('/users'),
                  icon: const Icon(Icons.people_rounded, size: 18),
                  label: const Text('Personal y Accesos'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue.shade800,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      backgroundColor: Colors.grey.shade100,
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Form(
                key: _formKey,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- COLUMNA IZQUIERDA: DATOS DE NEGOCIO ---
                    Expanded(
                      child: _buildSectionCard(
                        title: 'Datos del Negocio',
                        icon: Icons.storefront_outlined,
                        child: Column(
                          children: [
                            _buildTextField('Nombre del Comercio', _companyNameCtrl, icon: Icons.badge_outlined),
                            const SizedBox(height: 16),
                            _buildTextField('Dirección / Sucursal', _addressCtrl, icon: Icons.location_on_outlined),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(child: _buildTextField('Teléfono', _phoneCtrl, icon: Icons.phone_outlined)),
                                const SizedBox(width: 16),
                                Expanded(child: _buildTextField('CUIT / RUT / Tax ID', _taxIdCtrl, icon: Icons.receipt_long_outlined)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildTextField('Mensaje de Pie de Página (Ticket)', _footerCtrl, 
                                icon: Icons.message_outlined, maxLines: 2, 
                                hint: 'Ej: ¡Gracias por su compra! Vuelva pronto.'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 32),

                    // --- COLUMNA DERECHA: HARDWARE ---
                    Expanded(
                      child: Column(
                        children: [
                          // --- TARJETA IMPRESORA TÉRMICA ---
                          _buildSectionCard(
                            title: 'Hardware (Impresora Térmica)',
                            icon: Icons.print_outlined,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Tipo de Conexión', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  value: _printerType,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    prefixIcon: Icon(Icons.cable_outlined),
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: 'none', child: Text('Ninguna (Silenciada)')),
                                    DropdownMenuItem(value: 'usb', child: Text('USB / Puerto COM (Windows)')),
                                    DropdownMenuItem(value: 'network', child: Text('Red Local (TCP/IP)')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) setState(() => _printerType = val);
                                  },
                                ),
                                const SizedBox(height: 16),
                                // Opciones Dinámicas según Tipo
                                if (_printerType == 'usb') ...[
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Row(
                                          children: [
                                            Icon(Icons.usb, color: Colors.blue, size: 20),
                                            SizedBox(width: 8),
                                            Text('Configuración Serial', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        _buildTextField('Puerto COM', _comPortCtrl, hint: 'Ej: COM3, COM4', icon: Icons.input),
                                      ],
                                    ),
                                  ),
                                ] else if (_printerType == 'network') ...[
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Row(
                                          children: [
                                            Icon(Icons.wifi, color: Colors.green, size: 20),
                                            SizedBox(width: 8),
                                            Text('Configuración de Red', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            Expanded(flex: 2, child: _buildTextField('Dirección IP', _ipAddressCtrl, hint: 'Ej: 192.168.1.100', icon: Icons.language)),
                                            const SizedBox(width: 16),
                                            Expanded(child: _buildTextField('Puerto', _ipPortCtrl, hint: 'Ej: 9100')),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else ...[
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                                    child: Text('La impresión física está desactivada', style: TextStyle(color: Colors.grey.shade600)),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // --- TARJETA BALANZA ---
                          _buildSectionCard(
                            title: 'Balanza de Mostrador (Hardware)',
                            icon: Icons.scale_outlined,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Conexión Serial (COM)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                const SizedBox(height: 4),
                                const Text(
                                  'Si dejas este campo vacío, la lectura de peso desde balanza estará deshabilitada.',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                const SizedBox(height: 16),
                                _buildTextField('Puerto COM Balanza', _comPortScaleCtrl, hint: 'Ej: COM3, /dev/ttyUSB0', icon: Icons.cable_outlined),
                              ],
                            ),
                          ),

                          const SizedBox(height: 32),

                          // --- BOTÓN GUARDAR (al fondo, ancho completo) ---
                          SizedBox(
                            width: double.infinity,
                            height: 60,
                            child: FilledButton.icon(
                              onPressed: provider.isLoading ? null : _saveSettings,
                              icon: provider.isLoading
                                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Icon(Icons.save_outlined, size: 28),
                              label: const Text('GUARDAR CONFIGURACIÓN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.blue.shade800,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    );
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: const Border(bottom: BorderSide(color: Colors.black12)),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.blueGrey.shade700),
                const SizedBox(width: 12),
                Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {IconData? icon, String? hint, int maxLines = 1}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        prefixIcon: icon != null ? Icon(icon, color: Colors.grey) : null,
      ),
    );
  }
}
