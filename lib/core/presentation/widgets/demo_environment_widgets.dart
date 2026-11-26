import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/config/business_vertical_profile.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/features/cash_movements/providers/expense_category_provider.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/customers/providers/customer_provider.dart';
import 'package:frontend_desktop/features/offers/presentation/providers/offer_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

/// Coordina la carga y limpieza del Modo Exploración Demo y re-hidrata
/// todos los providers en memoria para evitar datos obsoletos en pantalla.
class DemoEnvironmentCoordinator {
  DemoEnvironmentCoordinator._();

  static T? _maybeRead<T>(BuildContext context) {
    try {
      return Provider.of<T>(context, listen: false);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _hydrateAllProviders(
    BuildContext context, {
    required bool isReset,
  }) async {
    final localTerminal = _maybeRead<LocalTerminalProvider>(context);
    final posProv = _maybeRead<PosProvider>(context);
    final catalogProv = _maybeRead<CatalogProvider>(context);
    final cashProv = _maybeRead<CashRegisterProvider>(context);
    final customerProv = _maybeRead<CustomerProvider>(context);
    final supplierProv = _maybeRead<SupplierProvider>(context);
    final offerProv = _maybeRead<OfferProvider>(context);
    final expenseCatProv = _maybeRead<ExpenseCategoryProvider>(context);
    final alertsProv = _maybeRead<InventoryAlertsProvider>(context);

    if (isReset && localTerminal != null) {
      await localTerminal.clearDemoExplorationState();
    }

    if (posProv != null) {
      posProv.clearCart();
      posProv.clearCheckoutDraft();
      if (isReset) {
        posProv.clearRecall();
      }
      await posProv.loadPaymentMethods().catchError((_) {});
    }

    if (catalogProv != null) {
      catalogProv.clearAllCatalogFilters(reload: false);
      await catalogProv.loadMetadata(force: true).catchError((_) {});
      await catalogProv.loadProducts().catchError((_) {});
    }

    if (cashProv != null) {
      await cashProv.loadRegisters().catchError((_) {});
      await cashProv.checkCurrentShift().catchError((_) {});
    }

    await Future.wait([
      if (customerProv != null) customerProv.fetchCustomers().catchError((_) {}),
      if (supplierProv != null) supplierProv.fetchSuppliers().catchError((_) {}),
      if (offerProv != null) offerProv.loadActiveOffers().catchError((_) {}),
      if (expenseCatProv != null) expenseCatProv.fetchCategories().catchError((_) {}),
      if (alertsProv != null) alertsProv.fetchAlerts().catchError((_) {}),
    ]);
  }

  static Future<bool> seedAndHydrate(BuildContext context) async {
    final settingsProv = context.read<SettingsProvider>();
    final res = await settingsProv.seedDemoEnvironment();
    if (!context.mounted) return res['success'] == true;

    if (res['success'] != true) {
      SnackBarService.error(
        context,
        res['message']?.toString() ?? 'No se pudieron cargar los datos de ejemplo.',
      );
      return false;
    }

    await _hydrateAllProviders(context, isReset: false);
    if (!context.mounted) return true;

    SnackBarService.success(
      context,
      res['message']?.toString() ??
          'Datos de ejemplo cargados. ¡Ya podés explorar el sistema completo!',
    );
    return true;
  }

  static Future<Map<String, dynamic>> resetAndHydrateResult(
    BuildContext context, {
    required String adminPin,
    required String confirmationText,
    GlobalKey<NavigatorState>? navigatorKey,
    bool navigateHomeOnSuccess = true,
  }) async {
    final settingsProv = context.read<SettingsProvider>();
    final res = await settingsProv.resetDemoEnvironment(
      adminPin: adminPin,
      confirmationText: confirmationText,
    );

    if (res['success'] != true || !context.mounted) {
      return res;
    }

    await _hydrateAllProviders(context, isReset: true);
    if (!context.mounted) return res;

    if (navigateHomeOnSuccess) {
      final nav = navigatorKey?.currentState ?? Navigator.maybeOf(context);
      nav?.pushNamedAndRemoveUntil('/pos', (route) => false);
    }

    SnackBarService.success(
      context,
      res['message']?.toString() ??
          'Datos de ejemplo eliminados. Tu negocio quedó limpio y listo para operar.',
    );
    return res;
  }
}

/// Invitación inicial mostrada una única vez a administradores cuando abren
/// una licencia Demo 15 días con catálogo y ventas completamente vacíos.
class DemoOnboardingDialog extends StatefulWidget {
  final BusinessVerticalProfile verticalProfile;

  const DemoOnboardingDialog({
    super.key,
    required this.verticalProfile,
  });

  static Future<void> show(
    BuildContext context, {
    required BusinessVerticalProfile verticalProfile,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DemoOnboardingDialog(verticalProfile: verticalProfile),
    );
  }

  @override
  State<DemoOnboardingDialog> createState() => _DemoOnboardingDialogState();
}

class _DemoOnboardingDialogState extends State<DemoOnboardingDialog> {
  bool _isBusy = false;
  String? _errorMessage;

  Future<void> _handleSeedDemo() async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });

    final ok = await DemoEnvironmentCoordinator.seedAndHydrate(context);
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _isBusy = false;
        _errorMessage =
            'No se pudo inicializar el entorno de exploración. Podés reintentar o empezar en limpio.';
      });
    }
  }

  Future<void> _handleStartClean() async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });

    await context.read<SettingsProvider>().dismissDemoOnboarding();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.verticalProfile;

    return AppModalShell(
      title: '¡Bienvenido a tu prueba gratuita de 15 días!',
      subtitle: 'Elegí cómo empezar en tu rubro (${profile.displayLabel})',
      icon: Icons.rocket_launch_rounded,
      accent: AppModalAccent.indigo,
      maxWidth: 640,
      showCloseButton: !_isBusy,
      onClose: _isBusy ? null : _handleStartClean,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Podés explorar el sistema ya poblado con artículos reales de ${profile.shortLabel}, ventas recientes, cuenta corriente y cierres Z, o arrancar directo con tus propios productos.',
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          _OptionCard(
            key: const Key('demo_onboarding_seed_btn'),
            icon: Icons.auto_awesome_rounded,
            accentColor: AppColors.indigo,
            title: 'Explorar con datos de ejemplo',
            subtitle:
                'Carga catálogo acorde a ${profile.shortLabel}, proveedores, clientes, lotes/presupuestos, historial de los últimos días y 1 turno listo para cobrar. Cuando quieras empezar en limpio lo reiniciás con 1 clic.',
            badgeText: 'Recomendado para evaluar',
            isLoading: _isBusy,
            onTap: _isBusy ? null : _handleSeedDemo,
          ),
          const SizedBox(height: 10),
          _OptionCard(
            key: const Key('demo_onboarding_clean_btn'),
            icon: Icons.storefront_rounded,
            accentColor: AppColors.teal,
            title: 'Empezar a cargar mi negocio real',
            subtitle:
                'Mantiene la base completamente vacía para que cargues tus productos, clientes y stock reales desde el primer día. Mientras no cargues datos, podrás activar los de ejemplo desde Ajustes > General.',
            onTap: _isBusy ? null : _handleStartClean,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF991B1B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
      footerLeading: const Text(
        'Tus usuarios, impresoras y licencia siempre permanecen intactos.',
        style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
      ),
      footerActions: [
        TextButton(
          onPressed: _isBusy ? null : _handleStartClean,
          child: const Text('Omitir por ahora'),
        ),
      ],
    );
  }
}

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final Color accentColor;
  final String title;
  final String subtitle;
  final String? badgeText;
  final bool isLoading;
  final VoidCallback? onTap;

  const _OptionCard({
    super.key,
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.subtitle,
    this.badgeText,
    this.isLoading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accentColor.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accentColor.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: accentColor,
                        ),
                      )
                    : Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (badgeText != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              badgeText!,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: accentColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: accentColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Banner persistente de 28px de altura mostrado en la parte superior mientras
/// `demo_mode_active == true`, sin entorpecer la operatoria de caja ni el AppBar.
class DemoModeBanner extends StatelessWidget {
  final bool isAdmin;
  final GlobalKey<NavigatorState>? navigatorKey;

  const DemoModeBanner({
    super.key,
    required this.isAdmin,
    this.navigatorKey,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFEF3C7),
      child: Container(
        height: 28,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFF59E0B), width: 1),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.science_outlined,
              size: 15,
              color: Color(0xFF92400E),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isAdmin
                    ? 'MODO EXPLORACIÓN: Estás operando con datos de ejemplo (facturación fiscal bloqueada hasta limpiar).'
                    : 'MODO DATOS DE EJEMPLO — Entorno de práctica (pedile a un Administrador limpiar para operar en real).',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF92400E),
                ),
              ),
            ),
            if (isAdmin) ...[
              const SizedBox(width: 8),
              SizedBox(
                height: 22,
                child: ElevatedButton.icon(
                  key: const Key('demo_banner_reset_btn'),
                  onPressed: () {
                    final targetCtx = navigatorKey?.currentContext ?? context;
                    DemoResetConfirmDialog.show(
                      targetCtx,
                      navigatorKey: navigatorKey,
                    );
                  },
                  icon: const Icon(Icons.cleaning_services_rounded, size: 12),
                  label: const Text(
                    'Limpiar datos y empezar en limpio',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB45309),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 22),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Diálogo blindado para limpiar los datos de ejemplo con palabra clave `LIMPIAR`,
/// PIN de administrador y resumen en vivo del backend.
class DemoResetConfirmDialog extends StatefulWidget {
  final GlobalKey<NavigatorState>? navigatorKey;
  final bool navigateHomeOnSuccess;

  const DemoResetConfirmDialog({
    super.key,
    this.navigatorKey,
    this.navigateHomeOnSuccess = true,
  });

  static Future<bool?> show(
    BuildContext context, {
    GlobalKey<NavigatorState>? navigatorKey,
    bool navigateHomeOnSuccess = true,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DemoResetConfirmDialog(
        navigatorKey: navigatorKey,
        navigateHomeOnSuccess: navigateHomeOnSuccess,
      ),
    );
  }

  @override
  State<DemoResetConfirmDialog> createState() => _DemoResetConfirmDialogState();
}

class _DemoResetConfirmDialogState extends State<DemoResetConfirmDialog> {
  final TextEditingController _confirmCtrl = TextEditingController();
  final TextEditingController _pinCtrl = TextEditingController();

  Map<String, dynamic>? _statusData;
  bool _loadingStatus = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStatus());
  }

  @override
  void dispose() {
    _confirmCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    final settingsProv = context.read<SettingsProvider>();
    final res = await settingsProv.fetchDemoStatus(silent: true);
    if (!mounted) return;
    setState(() {
      _loadingStatus = false;
      if (res['success'] == true) {
        _statusData = res;
      } else {
        _statusData = settingsProv.demoStatus;
      }
    });
  }

  bool get _hasFiscalBlock => _statusData?['has_fiscal_block'] == true;

  bool get _canSubmit {
    if (_isSubmitting || _hasFiscalBlock) return false;
    final wordOk = _confirmCtrl.text.trim().toUpperCase() == 'LIMPIAR';
    final pinOk = _pinCtrl.text.trim().length >= 4;
    return wordOk && pinOk;
  }

  Future<void> _submitReset() async {
    if (!_canSubmit) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final res = await DemoEnvironmentCoordinator.resetAndHydrateResult(
      context,
      adminPin: _pinCtrl.text.trim(),
      confirmationText: _confirmCtrl.text.trim(),
      navigatorKey: widget.navigatorKey,
      navigateHomeOnSuccess: widget.navigateHomeOnSuccess,
    );

    if (!mounted) return;
    if (res['success'] == true) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isSubmitting = false;
        _errorMessage =
            res['message']?.toString() ?? 'No se pudo completar el reinicio.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final counts = (_statusData?['counts'] as Map<String, dynamic>?) ?? const {};
    final productsCount = (counts['products'] as num?)?.toInt() ?? 0;
    final salesCount = (counts['sales'] as num?)?.toInt() ?? 0;
    final customersCount = (counts['customers'] as num?)?.toInt() ?? 0;
    final userAddedAfterSeed =
        (counts['user_added_products_after_seed'] as num?)?.toInt() ?? 0;

    return AppModalShell(
      title: 'Limpiar datos de ejemplo y empezar en limpio',
      subtitle: 'Dejá tu POS cero kilómetros conservando licencia, usuarios e impresoras',
      icon: Icons.cleaning_services_rounded,
      accent: AppModalAccent.amber,
      maxWidth: 600,
      showCloseButton: !_isSubmitting,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_loadingStatus)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ScopeBox(
                  title: 'Qué se limpiará',
                  color: const Color(0xFFB45309),
                  bgColor: const Color(0xFFFFFBEB),
                  items: [
                    'Productos y stock ($productsCount)',
                    'Ventas, turnos y movimientos ($salesCount)',
                    'Clientes, proveedores y compras ($customersCount)',
                    'Presupuestos, remitos y cheques demo',
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: _ScopeBox(
                  title: 'Qué queda 100% intacto',
                  color: Color(0xFF15803D),
                  bgColor: Color(0xFFF0FDF4),
                  items: [
                    'Licencia activa y datos del local',
                    'Usuarios, PINes y permisos',
                    'Impresora, balanza y punto AFIP',
                    'Medios de pago y categorías de gasto',
                  ],
                ),
              ),
            ],
          ),
          if (userAddedAfterSeed > 0) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFDBA74)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: Color(0xFFC2410C),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Atención: cargaste $userAddedAfterSeed producto(s) propio(s) durante el modo demo; también serán eliminados (guardamos un respaldo automático SQL previo en el servidor).',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF9A3412),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_hasFiscalBlock) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: const Text(
                'Bloqueo de seguridad tributaria: existen facturas electrónicas registradas ante ARCA, por lo que no se permite reiniciar automáticamente.',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF991B1B),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('demo_reset_confirm_text_field'),
                  controller: _confirmCtrl,
                  enabled: !_isSubmitting && !_hasFiscalBlock,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Escribí LIMPIAR para confirmar',
                    hintText: 'LIMPIAR',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const Key('demo_reset_pin_field'),
                  controller: _pinCtrl,
                  enabled: !_isSubmitting && !_hasFiscalBlock,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 8,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submitReset(),
                  decoration: const InputDecoration(
                    labelText: 'PIN de Administrador',
                    hintText: '••••',
                    counterText: '',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF991B1B),
                ),
              ),
            ),
          ],
        ],
      ),
      footerLeading: const Text(
        'Se genera una copia preventiva automática antes de borrar.',
        style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
      ),
      footerActions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          key: const Key('demo_reset_submit_btn'),
          onPressed: _canSubmit ? _submitReset : null,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.delete_sweep_rounded, size: 18),
          label: Text(_isSubmitting ? 'Limpiando...' : 'Confirmar y empezar en limpio'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD97706),
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _ScopeBox extends StatelessWidget {
  final String title;
  final Color color;
  final Color bgColor;
  final List<String> items;

  const _ScopeBox({
    required this.title,
    required this.color,
    required this.bgColor,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '• $item',
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.3,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
