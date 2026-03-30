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
import 'package:intl/intl.dart';

enum SettingsSection { general, hardware, subscription, network }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  SettingsSection _activeSection = SettingsSection.subscription; // Start in Subscription as requested

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
        if (mounted) setState(() {}); 
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
      await ReceiptPrinterService.instance.reconfigureFromSettings(provider.settings!);
      SnackBarService.success(context, 'Configuración guardada correctamente');
    } else {
      SnackBarService.error(context, provider.errorMessage ?? 'Error al guardar');
    }
  }

  Future<void> _activateLicense() async {
    final key = _licenseKeyCtrl.text.trim();
    if (key.isEmpty) {
      SnackBarService.error(context, 'Ingresá la clave de licencia.');
      return;
    }
    setState(() => _isActivatingLicense = true);
    try {
      final provider = context.read<SettingsProvider>();
      final newPlan = await provider.activateLicense(AppConfig.kApiBaseUrl, key);
      if (!mounted) return;
      _licenseKeyCtrl.clear();
      SnackBarService.success(context, '✅ Licencia activada: ${newPlan.toUpperCase()}');
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
      SnackBarService.success(context, '✅ Permisos sincronizados.');
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
        title: 'Configuración del Sistema',
        showBackButton: true,
      ),
      backgroundColor: const Color(0xFFF8F9FA),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                // --- SIDEBAR (Xbox Style) ---
                _buildSidebar(),
                
                // --- CONTENT AREA ---
                Expanded(
                  child: Form(
                    key: _formKey,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Padding(
                        key: ValueKey(_activeSection),
                        padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 48),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 900),
                            child: _buildActiveSection(provider),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 32),
          _buildSidebarItem(
            icon: Icons.storefront_outlined,
            title: 'General',
            section: SettingsSection.general,
          ),
          _buildSidebarItem(
            icon: Icons.print_outlined,
            title: 'Hardware',
            section: SettingsSection.hardware,
          ),
          _buildSidebarItem(
            icon: Icons.verified_user_outlined,
            title: 'Suscripción',
            section: SettingsSection.subscription,
          ),
          _buildSidebarItem(
            icon: Icons.dns_outlined,
            title: 'Red y Terminales',
            section: SettingsSection.network,
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                onPressed: _saveSettings,
                icon: const Icon(Icons.save_outlined),
                label: const Text('GUARDAR', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF673AB7),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem({required IconData icon, required String title, required SettingsSection section}) {
    final isActive = _activeSection == section;
    final activeColor = const Color(0xFF673AB7);

    return InkWell(
      onTap: () => setState(() => _activeSection = section),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: isActive ? activeColor : Colors.grey.shade600, size: 22),
            const SizedBox(width: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                color: isActive ? activeColor : Colors.grey.shade700,
              ),
            ),
            if (isActive) ...[
              const Spacer(),
              Container(width: 4, height: 20, decoration: BoxDecoration(color: activeColor, borderRadius: BorderRadius.circular(2))),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSection(SettingsProvider provider) {
    switch (_activeSection) {
      case SettingsSection.general:
        return _buildGeneralSection();
      case SettingsSection.hardware:
        return _buildHardwareSection();
      case SettingsSection.subscription:
        return _buildSubscriptionSection(provider);
      case SettingsSection.network:
        return _buildNetworkSection(provider);
    }
  }

  Widget _buildGeneralSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Datos del Negocio', 'Configurá los datos que aparecerán en tus tickets y facturas.'),
        const SizedBox(height: 32),
        _buildTextField('Nombre del Comercio', _companyNameCtrl, icon: Icons.badge_outlined),
        const SizedBox(height: 24),
        _buildTextField('Dirección / Sucursal', _addressCtrl, icon: Icons.location_on_outlined),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: _buildTextField('Teléfono', _phoneCtrl, icon: Icons.phone_outlined)),
            const SizedBox(width: 24),
            Expanded(child: _buildTextField('CUIT / Tax ID', _taxIdCtrl, icon: Icons.receipt_long_outlined)),
          ],
        ),
        const SizedBox(height: 24),
        _buildTextField('Mensaje Pie de Ticket', _footerCtrl, icon: Icons.message_outlined, maxLines: 3),
      ],
    );
  }

  Widget _buildHardwareSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Hardware y Periféricos', 'Impresoras térmicas y balanzas de mostrador.'),
        const SizedBox(height: 32),
        _buildSectionTitle('Impresora Térmica'),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _printerType,
          decoration: _inputDecoration('Tipo de Conexión', Icons.cable_outlined),
          items: const [
            DropdownMenuItem(value: 'none', child: Text('Desactivada')),
            DropdownMenuItem(value: 'usb', child: Text('USB / Puerto Serial (Windows)')),
            DropdownMenuItem(value: 'network', child: Text('Red (TCP/IP)')),
          ],
          onChanged: (val) => setState(() => _printerType = val!),
        ),
        if (_printerType != 'none') ...[
          const SizedBox(height: 24),
          if (_printerType == 'usb')
            _buildTextField('Puerto COM', _comPortCtrl, hint: 'Ej: COM3', icon: Icons.usb)
          else
            Row(
              children: [
                Expanded(flex: 2, child: _buildTextField('Dirección IP', _ipAddressCtrl, hint: '192.168.1.100', icon: Icons.wifi)),
                const SizedBox(width: 16),
                Expanded(child: _buildTextField('Puerto', _ipPortCtrl, hint: '9100')),
              ],
            ),
        ],
        const SizedBox(height: 48),
        _buildSectionTitle('Balanza'),
        const SizedBox(height: 16),
        _buildTextField('Puerto COM Balanza', _comPortScaleCtrl, hint: 'Ej: COM4', icon: Icons.scale_outlined),
      ],
    );
  }

  Widget _buildSubscriptionSection(SettingsProvider provider) {
    final settings = provider.settings;
    final isLifetime = settings?.isLifetime ?? false;
    final plan = provider.currentPlan.toUpperCase();
    final expiresAt = settings?.licenseExpiresAt;
    final manageUrl = settings?.licenseManageUrl;

    // --- COLORES POR PLAN ---
    List<Color> gradientColors;
    switch (provider.currentPlan.toLowerCase()) {
      case 'pro':
        gradientColors = [const Color(0xFF673AB7), const Color(0xFF512DA8)]; // Púrpura Premium
        break;
      case 'enterprise':
        gradientColors = [const Color(0xFF1A237E), const Color(0xFF0D47A1)]; // Azul Real / Deep Sea
        break;
      default:
        gradientColors = [const Color(0xFF455A64), const Color(0xFF263238)]; // Slate / Gray (Basic)
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Suscripción y Licencia', 'Gestioná tu acceso pro, addons y facturación.'),
        const SizedBox(height: 32),
        
        if (provider.isLicenseActive) ...[
          // --- TARJETA PREMIUM ---
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: gradientColors[0].withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(30)),
                      child: Text('PLAN $plan', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    const Icon(Icons.verified, color: Colors.white, size: 28),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  isLifetime ? 'Acceso Vitalicio (LifeTime)' : 'Suscripción Activa',
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  isLifetime 
                    ? 'Disfrutás de todas las funciones PRO sin límites de tiempo.'
                    : (expiresAt != null 
                        ? 'Expira el: ${DateFormat('dd MMMM, yyyy').format(expiresAt)}' 
                        : (settings?.lastLicenseCheck != null 
                            ? 'Sincronizado el: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(settings!.lastLicenseCheck!))}'
                            : 'Estado: Activo y Protegido')),
                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 15),
                ),
                const SizedBox(height: 32),
                if (!isLifetime && manageUrl != null)
                  ElevatedButton(
                    onPressed: () => launchUrl(Uri.parse(manageUrl)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF673AB7),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('GESTIONAR SUSCRIPCIÓN', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          _buildSectionTitle('Módulos Adicionales'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: (provider.allowedAddons.isEmpty) 
              ? [const Text('No hay addons específicos activos.', style: TextStyle(color: Colors.grey))]
              : provider.allowedAddons.map((addon) => Chip(
                  label: Text(addon.toUpperCase()),
                  backgroundColor: Colors.white,
                  side: BorderSide(color: Colors.grey.shade200),
                )).toList(),
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: _isSyncingLicense ? null : _syncLicense,
            icon: _isSyncingLicense ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
            label: const Text('FORZAR SINCRONIZACIÓN'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              side: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ] else ...[
          // --- ESTADO SIN LICENCIA ---
          _buildTextField('Clave de Licencia', _licenseKeyCtrl, icon: Icons.vpn_key_outlined, hint: 'XXXX-XXXX-XXXX-XXXX'),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isActivatingLicense ? null : _activateLicense,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF673AB7), foregroundColor: Colors.white),
              child: _isActivatingLicense ? const CircularProgressIndicator(color: Colors.white) : const Text('ACTIVAR AHORA'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNetworkSection(SettingsProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Red y Terminales', 'Configurá la conexión con el servidor y las cajas físicas.'),
        const SizedBox(height: 32),
        ListTile(
          contentPadding: const EdgeInsets.all(24),
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
          leading: const CircleAvatar(backgroundColor: Color(0xFFE8EAF6), child: Icon(Icons.dns, color: Color(0xFF3F51B5))),
          title: const Text('Dirección del Servidor', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('Configurá la IP de la base de datos principal.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showServerConfigDialog(context),
        ),
        const SizedBox(height: 24),
        ListTile(
          contentPadding: const EdgeInsets.all(24),
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
          leading: const CircleAvatar(backgroundColor: Color(0xFFFBE9E7), child: Icon(Icons.desktop_windows, color: Color(0xFFD84315))),
          title: const Text('Terminal Local', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('Esta PC está asignada a: Caja ID ${provider.assignedRegisterId}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showTerminalAssignmentDialog(context, provider),
        ),
        const SizedBox(height: 24),
        ListTile(
          contentPadding: const EdgeInsets.all(24),
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
          leading: const CircleAvatar(backgroundColor: Color(0xFFFFF3E0), child: Icon(Icons.settings_suggest_outlined, color: Colors.orange)),
          title: const Text('Administración de Cajas', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('Crea, edita o elimina las terminales físicas del sistema.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            if (provider.hasFeature('multi_caja')) {
              Navigator.pushNamed(context, '/settings/registers');
            } else {
              _showUpsellDialog(context, 'Gestión Multi-Caja', 'La administración de múltiples terminales físicas es una función exclusiva de los planes PRO y ENTERPRISE.');
            }
          },
        ),
      ],
    );
  }

  void _showUpsellDialog(BuildContext context, String featureName, String description) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.stars_rounded, color: Colors.amber, size: 28),
            const SizedBox(width: 12),
            Text('Plan Premium Requerido'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('La función "$featureName" no está disponible en tu plan actual.', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(description),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _activeSection = SettingsSection.subscription);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF673AB7), foregroundColor: Colors.white),
            child: const Text('MEJORAR PLAN'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF212121))),
        const SizedBox(height: 8),
        Text(subtitle, style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF424242)));
  }

  Widget _buildTextField(String label, TextEditingController controller, {IconData? icon, String? hint, int maxLines = 1}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: _inputDecoration(label, icon, hint: hint),
    );
  }

  InputDecoration _inputDecoration(String label, IconData? icon, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, size: 20) : null,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    );
  }

  // Los modales (_showUpsellDialog, _showServerConfigDialog, _showTerminalAssignmentDialog) 
  // se mantienen funcionalmente igual pero podrían estilizarse más.
  // Re-implementando los esenciales para que el archivo compile.

  Future<void> _showServerConfigDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final currentUrl = prefs.getString('pos_api') ?? 'http://127.0.0.1:8000/api';
    if (!context.mounted) return;
    final ctrl = TextEditingController(text: currentUrl);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configuración de Servidor'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'URL API')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              await prefs.setString('pos_api', ctrl.text.trim());
              if (mounted) Navigator.pop(ctx);
              SnackBarService.success(context, 'Reinicia para aplicar cambios.');
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showTerminalAssignmentDialog(BuildContext context, SettingsProvider settingsProvider) async {
    final cashProvider = context.read<CashRegisterProvider>();
    if (cashProvider.availableRegisters == null || cashProvider.availableRegisters!.isEmpty) {
      await cashProvider.loadRegisters();
    }
    if (!context.mounted) return;
    final registers = cashProvider.availableRegisters ?? [];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Asignar Terminal'),
        content: DropdownButtonFormField<int>(
          value: registers.any((r) => r.id == settingsProvider.assignedRegisterId) ? settingsProvider.assignedRegisterId : registers.firstOrNull?.id,
          items: registers.map((r) => DropdownMenuItem(value: r.id, child: Text(r.name))).toList(),
          onChanged: (id) async {
            if (id != null) {
              await settingsProvider.setAssignedRegisterId(id);
              Navigator.pop(ctx);
            }
          },
        ),
      ),
    );
  }
}
