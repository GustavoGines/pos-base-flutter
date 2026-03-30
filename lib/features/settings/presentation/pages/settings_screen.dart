import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../../../../core/utils/snack_bar_service.dart';
import '../../../../core/utils/receipt_printer_service.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../cash_register/presentation/providers/cash_register_provider.dart';
import '../../../../core/config/app_config.dart';


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

  // Licencia
  final _licenseKeyCtrl = TextEditingController();
  bool _isActivatingLicense = false;
  bool _isSyncingLicense = false;

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
    _licenseKeyCtrl.dispose();
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

  Future<void> _activateLicense() async {
    final key = _licenseKeyCtrl.text.trim();
    if (key.isEmpty) {
      SnackBarService.error(context, 'Ingresá la clave de licencia antes de continuar.');
      return;
    }

    setState(() => _isActivatingLicense = true);

    try {
      final provider = context.read<SettingsProvider>();
      // The baseUrl matches the one set in main.dart for settings
      // We read it from the datasource's baseUrl via the provider's usecase chain.
      // As a shortcut on the local network, we rely on the same base URL used for the app.
      final newPlan = await provider.activateLicense(AppConfig.kApiBaseUrl, key);
      if (!mounted) return;
      _licenseKeyCtrl.clear();
      SnackBarService.success(context, '✅ Licencia activada. Plan: ${newPlan.toUpperCase()}');
    } catch (e) {
      if (!mounted) return;
      SnackBarService.error(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isActivatingLicense = false);
    }
  }

  Future<void> _syncLicense() async {
    setState(() => _isSyncingLicense = true);
    try {
      final provider = context.read<SettingsProvider>();
      await provider.syncLicenseWithServer(AppConfig.kApiBaseUrl);
      if (!mounted) return;
      SnackBarService.success(context, '✅ Permisos sincronizados con éxito.');
    } catch (e) {
      if (!mounted) return;
      SnackBarService.error(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSyncingLicense = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: GlobalAppBar(
        currentRoute: '/settings',
        title: 'Ajustes del Sistema',
        showBackButton: true,
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
                    // --- COLUMNA IZQUIERDA: LICENCIA + DATOS DE NEGOCIO ---
                    Expanded(
                      child: Column(
                        children: [
                          // --- TARJETA DE LICENCIA ---
                          _buildLicenseCard(provider),
                          const SizedBox(height: 24),
                          // --- DATOS DE NEGOCIO ---
                          _buildSectionCard(
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
                        ],
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
                          
                          // --- TARJETA ADMINISTRACIÓN ---
                          _buildSectionCard(
                            title: 'Administración y Red',
                            icon: Icons.admin_panel_settings_outlined,
                            child: Column(
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.computer, color: Colors.blueGrey),
                                  title: const Text('Gestión de Cajas Físicas'),
                                  subtitle: const Text('Añadir, renombrar o desactivar terminales físicas'),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () {
                                    if (!provider.hasFeature('multi_caja')) {
                                      _showUpsellDialog(context);
                                    } else {
                                      Navigator.pushNamed(context, '/settings/registers');
                                    }
                                  },
                                ),
                                const Divider(indent: 16, endIndent: 16),
                                ListTile(
                                  leading: const Icon(Icons.dns_outlined, color: Colors.blueGrey),
                                  title: const Text('Configuración del Servidor y Red'),
                                  subtitle: const Text('Cambiar la IP o dominio del servidor Backend'),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _showServerConfigDialog(context),
                                ),
                                const Divider(indent: 16, endIndent: 16),
                                ListTile(
                                  leading: const Icon(Icons.desktop_windows, color: Colors.blueGrey),
                                  title: const Text('Terminal Local Asignada'),
                                  subtitle: Text('ID de Hardware actual: ${provider.assignedRegisterId}'),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _showTerminalAssignmentDialog(context, provider),
                                ),
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

  Widget _buildLicenseCard(SettingsProvider provider) {
    final plan = provider.currentPlan;

    Color planColor;
    Color planBgColor;
    IconData planIcon;
    String planLabel;

    switch (plan) {
      case 'pro':
        planColor = Colors.purple.shade700;
        planBgColor = Colors.purple.shade50;
        planIcon = Icons.workspace_premium;
        planLabel = 'PRO';
        break;
      case 'enterprise':
        planColor = Colors.amber.shade800;
        planBgColor = Colors.amber.shade50;
        planIcon = Icons.diamond_outlined;
        planLabel = 'ENTERPRISE';
        break;
      case 'blocked':
        planColor = Colors.red.shade700;
        planBgColor = Colors.red.shade50;
        planIcon = Icons.block;
        planLabel = 'BLOQUEADO';
        break;
      default: // basic
        planColor = Colors.blueGrey.shade600;
        planBgColor = Colors.blueGrey.shade50;
        planIcon = Icons.lock_outline;
        planLabel = 'BÁSICO';
    }

    final rawKey = provider.settings?.licenseStatus ?? '';
    final maskedKey = rawKey.length > 4
        ? '****-****-****-${rawKey.substring(rawKey.length - 4)}'
        : (rawKey.isEmpty ? 'Sin clave registrada' : rawKey);

    return _buildSectionCard(
      title: 'Licencia del Sistema',
      icon: Icons.verified_user_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: planBgColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: planColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(planIcon, size: 16, color: planColor),
                    const SizedBox(width: 6),
                    Text(
                      'Plan $planLabel',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: planColor,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  maskedKey,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    letterSpacing: 1.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          
          if (provider.isLicenseActive) ...[
            const Text(
              'Módulos Activos',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
            ),
            const SizedBox(height: 12),
            if (provider.allowedAddons.isEmpty)
              const Text('Ninguno', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: provider.allowedAddons.map((addon) {
                  final formattedAddon = addon.split('_').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');
                  return Chip(label: Text(formattedAddon), backgroundColor: Colors.indigo.shade50, side: BorderSide.none);
                }).toList(),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isSyncingLicense ? null : _syncLicense,
                icon: _isSyncingLicense
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.sync_rounded),
                label: Text(
                  _isSyncingLicense ? 'Sincronizando...' : '🔄 Sincronizar Permisos',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ] else ...[
            const Text(
              'Activar Nueva Clave',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _licenseKeyCtrl,
              decoration: InputDecoration(
                labelText: 'Nueva Clave de Licencia',
                hintText: 'Ej: XXXX-XXXX-XXXX-XXXX',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.vpn_key_outlined),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => _licenseKeyCtrl.clear(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isActivatingLicense ? null : _activateLicense,
                icon: _isActivatingLicense
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.verified_outlined),
                label: Text(
                  _isActivatingLicense ? 'Verificando...' : 'Verificar y Activar',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
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

  void _showUpsellDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.workspace_premium, color: Colors.purple),
            SizedBox(width: 8),
            Text('Mejora a PRO'),
          ],
        ),
        content: const Text(
            'La administración de múltiples Cajas Físicas es una función exclusiva del Plan PRO.\n\n'
            'Adquiere el complemento "Múltiples Cajas" para habilitar el manejo de terminales simultáneas.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              final url = Uri.parse('https://wa.me/5493704787285?text=Hola,%20quiero%20mejorar%20mi%20licencia%20a%20PRO%20para%20M%C3%BAltiples%20Cajas.');
              if (await canLaunchUrl(url)) {
                await launchUrl(url);
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir WhatsApp.')));
                }
              }
            },
            child: const Text('Contactar a Ventas'),
          )
        ],
      ),
    );
  }

  Future<void> _showServerConfigDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final currentUrl = prefs.getString('pos_api') ?? 'http://127.0.0.1:8000/api';
    
    if (!context.mounted) return;
    final ctrl = TextEditingController(text: currentUrl);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.dns_outlined, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('Red y Servidor', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Apunta este frontend a la computadora principal (Servidor).\n'
              'Ejemplo: http://192.168.1.50:8000/api',
              style: TextStyle(color: Colors.blueGrey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              decoration: InputDecoration(
                labelText: 'URL de la API',
                prefixIcon: const Icon(Icons.link),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final newUrl = ctrl.text.trim();
              if (newUrl.isNotEmpty) {
                await prefs.setString('pos_api', newUrl);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                SnackBarService.success(context, 'Configuración de red guardada.\nPor favor reinicia la aplicación para aplicar.');
              }
            },
            icon: const Icon(Icons.save),
            label: const Text('Guardar'),
            style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade800),
          ),
        ],
      ),
    );
  }

  Future<void> _showTerminalAssignmentDialog(BuildContext context, SettingsProvider settingsProvider) async {
    final cashProvider = context.read<CashRegisterProvider>();
    
    // Si no están precargadas las cajas, las traemos
    if (cashProvider.availableRegisters == null || cashProvider.availableRegisters!.isEmpty) {
      await cashProvider.loadRegisters();
    }

    if (!context.mounted) return;

    final registers = cashProvider.availableRegisters ?? [];

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.desktop_windows, color: Colors.indigo),
              SizedBox(width: 8),
              Text('Asignar Terminal Local'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Selecciona qué Caja Física representa esta computadora. '
                'Si usas Plan Básico, solo estará disponible la Caja Principal.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              if (registers.isEmpty)
                const Text('No hay cajas disponibles en red.', style: TextStyle(color: Colors.red))
              else
                DropdownButtonFormField<int>(
                  value: registers.any((r) => r.id == settingsProvider.assignedRegisterId) 
                         ? settingsProvider.assignedRegisterId 
                         : registers.first.id,
                  decoration: InputDecoration(
                    labelText: 'Caja Asignada a esta PC',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: registers.map((reg) {
                    return DropdownMenuItem<int>(
                      value: reg.id,
                      child: Text('${reg.name} (ID: ${reg.id})'),
                    );
                  }).toList(),
                  onChanged: (newId) async {
                    if (newId != null) {
                      // 1. Guardar la nueva terminal en SharedPreferences
                      await settingsProvider.setAssignedRegisterId(newId);
                      Navigator.pop(ctx);

                      // 2. Re-verificar si hay turno activo en la nueva terminal
                      //    Esto actualiza el currentShift en memoria
                      if (context.mounted) {
                        await context
                            .read<CashRegisterProvider>()
                            .checkCurrentShift(registerId: newId);
                      }

                      // 3. Navegar a /home para que el router reactivo decida:
                      //    - Si hay turno abierto → va directo al POS
                      //    - Si no hay turno → muestra pantalla de Apertura de Caja
                      if (context.mounted) {
                        Navigator.of(context).pushNamedAndRemoveUntil(
                          '/home',
                          (route) => false,
                        );
                      }
                    }
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar / Cerrar'),
            ),
          ],
        );
      },
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
