import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../../../../core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import 'package:frontend_desktop/core/presentation/widgets/plan_upgrade_dialog.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../cash_register/presentation/providers/cash_register_provider.dart';
import '../../../../core/config/app_config.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../updater/data/services/update_service.dart';
import '../../../updater/presentation/widgets/update_dialog.dart';

enum SettingsSection { general, prices, hardware, subscription, network }

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

  // Listas de Precios Personalizadas
  List<Map<String, dynamic>> _customTiers = [];
  final _tierNameCtrl = TextEditingController();
  final _tierModCtrl = TextEditingController();

  // Precios Globales
  final _cardPercentageCtrl = TextEditingController();
  final _wholesalePercentageCtrl = TextEditingController();
  bool _advancedPriceTiersEnabled = false; // Feature Toggle Multi-Tenant

  // Licencia
  final _licenseKeyCtrl = TextEditingController();
  bool _isActivatingLicense = false;
  bool _isSyncingLicense = false;
  bool _isCheckingUpdate = false;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<SettingsProvider>();
      final settings = provider.settings;
      if (settings != null) {
        _companyNameCtrl.text = settings.companyName ?? '';
        _addressCtrl.text = settings.address ?? '';
        _phoneCtrl.text = settings.phone ?? '';
        _taxIdCtrl.text = settings.taxId ?? '';
        _footerCtrl.text = settings.receiptFooterMessage ?? '';
        
        _cardPercentageCtrl.text = settings.globalCardPercentage.toString();
        _wholesalePercentageCtrl.text = settings.globalWholesalePercentage.toString();
        _advancedPriceTiersEnabled = settings.enableAdvancedPriceTiers;
        
        _customTiers = List<Map<String, dynamic>>.from(settings.customPriceTiers.map((e) => Map<String, dynamic>.from(e)));
        
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
    _licenseKeyCtrl.dispose();
    _tierNameCtrl.dispose();
    _tierModCtrl.dispose();
    _cardPercentageCtrl.dispose();
    _wholesalePercentageCtrl.dispose();
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
      'card_percentage': double.tryParse(_cardPercentageCtrl.text.trim().replaceAll(',', '.')) ?? 15.0,
      'wholesale_percentage': double.tryParse(_wholesalePercentageCtrl.text.trim().replaceAll(',', '.')) ?? -15.0,
      'custom_price_tiers': _customTiers,
      'enable_advanced_price_tiers': _advancedPriceTiersEnabled ? '1' : '0',
    };

    final success = await provider.saveSettings(data);
    if (!mounted) return;

    if (success) {
      // Hardware config ya no se reconfigura desde settings globales.
      // Cada terminal usa su LocalTerminalProvider local (SharedPreferences).
      SnackBarService.success(context, 'Configuración guardada correctamente');
    } else {
      SnackBarService.error(context, provider.errorMessage ?? 'Error al guardar');
    }
  }

  String _translateFeature(String featureCode) {
    const dictionary = {
      'fast_pos': '⚡ Caja Rápida',
      'z_reports': '🔍 Auditoría General (Turnos y Stock)',
      'quotes': '📝 Presupuestos (PDF/WA)',
      'current_accounts': '💳 Cuentas Corrientes (Fiado)',
      'multiple_prices': '🏷️ Listas de Precios (Mayorista/Tarjeta)',
      'multi_caja': '💻 Múltiples Cajas / Terminales',
      'advanced_reports': '📊 Reportes Gerenciales (Balances, Excel, PDF)',
      'predictive_alerts': '🧠 Alertas Inteligentes (Logística Predictiva)',
      'logistics': '🚚 Logística y Remitos',
      'checks': '💵 Gestión de Cheques',
    };
    return dictionary[featureCode] ?? featureCode.toUpperCase();
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

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = packageInfo.version);
  }

  Future<void> _checkForUpdate() async {
    setState(() => _isCheckingUpdate = true);
    try {
      final result = await UpdateService().checkUpdate(throwErrors: true);
      if (!mounted) return;

      final frontendUpdate = result.frontendUpdate;
      final backendUpdate = result.backendUpdate;

      if (frontendUpdate != null) {
        showDialog(
          context: context,
          barrierDismissible: !frontendUpdate.isCritical,
          builder: (_) => UpdateDialog(updateInfo: frontendUpdate),
        );
      } else if (backendUpdate != null) {
        // El backend ya se actualiza automáticamente, solo informamos
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (_) => UpdateDialog(updateInfo: backendUpdate),
        );
      } else {
        SnackBarService.success(context, 'Tu sistema está actualizado (v$_appVersion)');
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarService.error(context, 'Error chequeando actualizaciones: $e');
    } finally {
      if (mounted) setState(() => _isCheckingUpdate = false);
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
                      child: SingleChildScrollView(
                        key: ValueKey(_activeSection),
                        child: Padding(
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
            icon: Icons.price_change_outlined,
            title: 'Precios Globales',
            section: SettingsSection.prices,
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
        return _buildGeneralSection(provider);
      case SettingsSection.prices:
        return _buildPricesSection(provider);
      case SettingsSection.hardware:
        return _buildHardwareSection();
      case SettingsSection.subscription:
        return _buildSubscriptionSection(provider);
      case SettingsSection.network:
        return _buildNetworkSection(provider);
    }
  }

  Widget _buildGeneralSection(SettingsProvider provider) {
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

  Widget _buildPricesSection(SettingsProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Precios y Factores', 'Configurá los porcentajes matemáticos para las listas de precios globales.'),
        const SizedBox(height: 32),

        // ── Feature Toggle Multi-Tenant ──────────────────────────────────────
        Builder(builder: (context) {
          final hasMultiPrices = provider.settings?.features.multiplePrices == true;
          final isLocked = !hasMultiPrices;

          return Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: isLocked
                      ? Colors.grey.shade50
                      : _advancedPriceTiersEnabled
                          ? const Color(0xFF1A237E).withOpacity(0.06)
                          : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isLocked
                        ? Colors.grey.shade200
                        : _advancedPriceTiersEnabled
                            ? const Color(0xFF3F51B5).withOpacity(0.4)
                            : Colors.grey.shade200,
                    width: 1.5,
                  ),
                ),
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  secondary: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isLocked
                              ? Colors.grey.shade100
                              : _advancedPriceTiersEnabled
                                  ? const Color(0xFF3F51B5).withOpacity(0.12)
                                  : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isLocked
                              ? Icons.lock_outline_rounded
                              : _advancedPriceTiersEnabled
                                  ? Icons.price_change_rounded
                                  : Icons.storefront_rounded,
                          color: isLocked
                              ? Colors.grey.shade400
                              : _advancedPriceTiersEnabled
                                  ? const Color(0xFF3F51B5)
                                  : Colors.grey.shade500,
                          size: 26,
                        ),
                      ),
                      if (isLocked)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade600,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.workspace_premium, size: 10, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                  title: Text(
                    isLocked
                        ? 'Multi-Listas de Precios (Plan Avanzado)'
                        : _advancedPriceTiersEnabled
                            ? 'Modo Avanzado (Multi-Listas Activo)'
                            : 'Modo Básico (Retail / Minorista)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isLocked
                          ? Colors.grey.shade500
                          : _advancedPriceTiersEnabled
                              ? const Color(0xFF1A237E)
                              : Colors.grey.shade700,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      isLocked
                          ? 'Activá el Plan Avanzado para habilitar el selector de Listas de Precios (Mayorista / Tarjeta) en el POS.'
                          : _advancedPriceTiersEnabled
                              ? 'El POS muestra el selector de Listas (Mayorista / Tarjeta / Custom). Los recargos del método de pago se desactivan automáticamente para evitar doble cobro.'
                              : 'El POS opera con precio único. Los recargos configurados en cada Método de Pago se aplican normalmente al momento del cobro.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4),
                    ),
                  ),
                  value: _advancedPriceTiersEnabled,
                  // Switch visualmente desactivado si el plan no incluye el feature
                  activeColor: isLocked ? Colors.grey.shade400 : const Color(0xFF3F51B5),
                  onChanged: (val) {
                    if (isLocked) {
                      // Mostrar upsell — no cambiar el estado local
                      PlanUpgradeDialog.show(
                        context,
                        title: 'Plan Avanzado Requerido',
                        featureName: 'Múltiples Listas de Precios',
                        description:
                            'El modo Multi-Listas (Mayorista, Tarjeta, Listas Custom) '
                            'es una función exclusiva del plan AVANZADO.\n\n'
                            'Permite aplicar precios diferenciados por tipo de cliente '
                            'directamente desde la caja, sin recargos duplicados.',
                        onNavigateToSettings: () =>
                            setState(() => _activeSection = SettingsSection.subscription),
                      );
                      return; // ← bloquea el setState
                    }
                    setState(() => _advancedPriceTiersEnabled = val);
                  },
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(child: _buildTextField('Recargo por Tarjeta (%)', _cardPercentageCtrl, icon: Icons.credit_card, hint: 'Ej: 15.0', enabled: !isLocked && _advancedPriceTiersEnabled)),
                  const SizedBox(width: 24),
                  Expanded(child: _buildTextField('Descuento Mayorista (%)', _wholesalePercentageCtrl, icon: Icons.factory_outlined, hint: 'Ej: -15.0', enabled: !isLocked && _advancedPriceTiersEnabled)),
                ],
              ),
            ],
          );
        }),
        if (provider.settings?.features.multiplePrices == true) ...[
          const SizedBox(height: 48),
          _buildCustomTiersSection(enabled: _advancedPriceTiersEnabled),
        ]
      ],
    );
  }

  Widget _buildCustomTiersSection({bool enabled = true}) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Listas de Precios Especiales', 'Creá modificadores dinámicos para clientes (Ej: "Gremio" con -10%).'),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              flex: 3,
              child: _buildTextField('Nombre de la Lista', _tierNameCtrl, hint: 'Ej: Gremio', icon: Icons.label_outline),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: _buildTextField('Modificador (%)', _tierModCtrl, hint: 'Ej: -10', icon: Icons.percent),
            ),
            const SizedBox(width: 16),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: () {
                  final name = _tierNameCtrl.text.trim();
                  final modStr = _tierModCtrl.text.trim();
                  final mod = double.tryParse(modStr);
                  if (name.isNotEmpty && mod != null) {
                    setState(() {
                      _customTiers.add({'name': name, 'modifier': mod});
                      _tierNameCtrl.clear();
                      _tierModCtrl.clear();
                    });
                  } else {
                    SnackBarService.warning(context, 'Ingresá un nombre y un porcentaje válido numérico.');
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('AÑADIR LISTA'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_customTiers.isEmpty)
          const Text('No hay listas de precios activas.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _customTiers.asMap().entries.map((entry) {
              final idx = entry.key;
              final tier = entry.value;
              final name = tier['name'];
              final mod = (tier['modifier'] as num).toDouble();
              final sign = mod >= 0 ? '+' : '';
              return GestureDetector(
                onTap: () {
                  final editNameCtrl = TextEditingController(text: name);
                  final editModCtrl = TextEditingController(text: mod.toString());
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Editar Lista de Precios'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: editNameCtrl,
                            decoration: const InputDecoration(labelText: 'Nombre de la Lista', border: OutlineInputBorder()),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: editModCtrl,
                            keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                            decoration: const InputDecoration(labelText: 'Modificador (%)', border: OutlineInputBorder()),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                        FilledButton(
                          onPressed: () {
                            final newName = editNameCtrl.text.trim();
                            final newMod = double.tryParse(editModCtrl.text.replaceAll(',', '.').trim());
                            if (newName.isNotEmpty && newMod != null) {
                              setState(() {
                                _customTiers[idx] = {'name': newName, 'modifier': newMod};
                              });
                              Navigator.pop(ctx);
                            }
                          },
                          child: const Text('Guardar'),
                        ),
                      ],
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    border: Border.all(color: Colors.purple.shade200),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sell_outlined, size: 16, color: Colors.purple),
                      const SizedBox(width: 8),
                      Text(
                        '$name ($sign${mod.toStringAsFixed(0)}%)',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple.shade900),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => setState(() => _customTiers.removeAt(idx)),
                        child: const Icon(Icons.cancel, size: 18, color: Colors.redAccent),
                      )
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildHardwareSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'Hardware Migrado a Local',
          'La configuración de impresoras y balanzas es ahora independiente por caja.',
        ),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF673AB7).withOpacity(0.08), Color(0xFF3F51B5).withOpacity(0.06)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Color(0xFF673AB7).withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Color(0xFF673AB7).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.computer_outlined, color: Color(0xFF673AB7), size: 28),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Arquitectura Multi-Caja Activa',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF311B92)),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Cada terminal configura su propio hardware de forma independiente.',
                          style: TextStyle(fontSize: 13, color: Color(0xFF4527A0)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(color: Color(0xFFD1C4E9)),
              const SizedBox(height: 16),
              _buildMigrationInfoRow(
                Icons.print_outlined,
                'Impresora Térmica',
                'Configurá la conexión (USB/Red) desde el ícono ⚙️ en la pantalla del POS.',
              ),
              const SizedBox(height: 12),
              _buildMigrationInfoRow(
                Icons.scale_outlined,
                'Balanza (Puerto COM)',
                'El puerto COM de la balanza se asigna desde el mismo modal de ajustes del POS.',
              ),
              const SizedBox(height: 12),
              _buildMigrationInfoRow(
                Icons.straighten_outlined,
                'Formato de Papel',
                'Seleccioná entre 58mm, 80mm o A4 individualmente para cada caja física.',
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Color(0xFF673AB7).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: Color(0xFF673AB7), size: 20),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Estos ajustes se guardan en esta PC únicamente (SharedPreferences) y no se sincronizan con la nube.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF4527A0)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMigrationInfoRow(IconData icon, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: const Color(0xFF7E57C2)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF311B92))),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF5E35B1))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubscriptionSection(SettingsProvider provider) {
    final settings = provider.settings;
    final isLifetime = settings?.isLifetime ?? false;
    final expiresAt = settings?.licenseExpiresAt;
    final manageUrl = settings?.licenseManageUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Suscripción y Licencia', 'Gestioná tu acceso Premium, Módulos y facturación.'),
        const SizedBox(height: 32),
        
        if (provider.isLicenseActive) ...[
          AnimatedSubscriptionCard(
            isPremium: provider.currentPlan.toLowerCase() == 'premium' || provider.currentPlan.toLowerCase() == 'pro',
            isLifetime: isLifetime,
            expiresAt: expiresAt,
            lastSync: settings?.lastLicenseCheck,
            manageUrl: manageUrl,
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
                  label: Text(
                    _translateFeature(addon),
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF424242)),
                  ),
                  backgroundColor: Colors.white,
                  side: BorderSide(color: Colors.grey.shade300),
                )).toList(),
          ),
          const SizedBox(height: 32),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isSyncingLicense ? null : _syncLicense,
                  icon: _isSyncingLicense ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
                  label: const Text('FORZAR SINCRONIZACIÓN'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isCheckingUpdate ? null : _checkForUpdate,
                  icon: _isCheckingUpdate ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.system_update_alt),
                  label: const Text('BUSCAR ACTUALIZACIONES'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    backgroundColor: const Color(0xFF3F51B5),
                  ),
                ),
              ),
            ],
          ),
          if (_appVersion.isNotEmpty) ...[
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Versión actual del sistema: v$_appVersion',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ],
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
            if (provider.features.multiCaja) {
              Navigator.pushNamed(context, '/settings/registers');
            } else {
              PlanUpgradeDialog.show(
                context,
                title: 'Plan Premium Requerido',
                featureName: 'Gestión Multi-Caja',
                description:
                    'La administración de múltiples terminales físicas es '
                    'una función exclusiva del plan PREMIUM.\n\n'
                    'Actualizá para organizar tu negocio y sincronizar las cajas.',
                onNavigateToSettings: () =>
                    setState(() => _activeSection = SettingsSection.subscription),
              );
            }
          },
        ),
      ],
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

  Widget _buildTextField(String label, TextEditingController controller, {IconData? icon, String? hint, int maxLines = 1, bool enabled = true}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      enabled: enabled,
      decoration: _inputDecoration(label, icon, hint: hint, enabled: enabled),
    );
  }

  InputDecoration _inputDecoration(String label, IconData? icon, {String? hint, bool enabled = true}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, size: 20, color: enabled ? null : Colors.grey) : null,
      filled: true,
      fillColor: enabled ? Colors.white : Colors.grey.shade50,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
      disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade100)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      labelStyle: enabled ? null : TextStyle(color: Colors.grey.shade500),
      hintStyle: enabled ? null : TextStyle(color: Colors.grey.shade400),
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

class AnimatedSubscriptionCard extends StatefulWidget {
  final bool isPremium;
  final bool isLifetime;
  final DateTime? expiresAt;
  final String? lastSync;
  final String? manageUrl;

  const AnimatedSubscriptionCard({
    super.key,
    required this.isPremium,
    required this.isLifetime,
    this.expiresAt,
    this.lastSync,
    this.manageUrl,
  });

  @override
  State<AnimatedSubscriptionCard> createState() => _AnimatedSubscriptionCardState();
}

class _AnimatedSubscriptionCardState extends State<AnimatedSubscriptionCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glowAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    
    _glowAnimation = Tween<double>(begin: 0.7, end: 1.3).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isPremium ? 'PLAN PREMIUM' : 'PLAN BÁSICO';
    
    final gradientColors = widget.isPremium
        ? [const Color(0xFF7C3AED), const Color(0xFF3B82F6), const Color(0xFF9333EA)] // Vibrant purple -> blue -> violet
        : [const Color(0xFF1E293B), const Color(0xFF334155), const Color(0xFF0F172A)]; // Sleek dark slate
        
    final shadowColor = widget.isPremium ? const Color(0xFF7C3AED) : const Color(0xFF000000);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.015 : 1.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        child: AnimatedBuilder(
          animation: _glowAnimation,
          builder: (context, child) {
            return Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: shadowColor.withValues(alpha: 0.3 * _glowAnimation.value),
                blurRadius: 30 * _glowAnimation.value,
                offset: const Offset(0, 15),
              ),
            ],
            border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: widget.isPremium ? Colors.amber.shade400.withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: widget.isPremium ? [BoxShadow(color: Colors.amber.withValues(alpha: 0.5), blurRadius: 10)] : [],
                    ),
                    child: Text(
                      title,
                      style: TextStyle(
                        color: widget.isPremium ? Colors.black87 : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  Icon(
                    widget.isPremium ? Icons.workspace_premium : Icons.verified_user,
                    color: widget.isPremium ? Colors.amber.shade300 : Colors.blue.shade300,
                    size: 36,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                widget.isLifetime ? 'Acceso Vitalicio (LifeTime)' : 'Suscripción Activa',
                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5),
              ),
              const SizedBox(height: 10),
              Text(
                widget.isLifetime
                    ? 'Disfrutás de todas las funciones Premium sin límites de tiempo.'
                    : (widget.expiresAt != null
                        ? 'Expira el: ${DateFormat('dd MMMM, yyyy').format(widget.expiresAt!)}'
                        : (widget.lastSync != null
                            ? 'Sincronizado el: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(widget.lastSync!))}'
                            : 'Estado: Activo y Protegido')),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 16),
              ),
              const SizedBox(height: 36),
              if (!widget.isLifetime && widget.manageUrl != null)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    child: ElevatedButton.icon(
                      onPressed: () => launchUrl(Uri.parse(widget.manageUrl!)),
                      icon: Icon(Icons.manage_accounts, color: widget.isPremium ? const Color(0xFF7C3AED) : Colors.white, size: 20),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.isPremium ? Colors.white : Colors.blue.shade600,
                        foregroundColor: widget.isPremium ? const Color(0xFF7C3AED) : Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 8,
                      ),
                      label: const Text('GESTIONAR SUSCRIPCIÓN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
      ),
    );
  }
}
