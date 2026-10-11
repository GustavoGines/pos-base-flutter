import 'dart:io';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
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
import '../../../pos/presentation/providers/pos_provider.dart';
import '../widgets/mobile_app_qr_section.dart';
import '../widgets/ecommerce_sync_logs_dialog.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/widgets/admin_pin_dialog.dart';
import '../../../../core/constants/app_permissions.dart';
import '../../domain/entities/ecommerce_integration.dart';

enum SettingsSection { general, prices, subscription, network, integrations, mobileApp }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  SettingsSection _activeSection =
      SettingsSection.subscription; // Start in Subscription as requested

  // Negocio
  final _companyNameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _taxIdCtrl = TextEditingController();
  final _footerCtrl = TextEditingController();

  // Logotipo del Negocio
  String? _selectedLogoPath;
  Uint8List? _selectedLogoBytes;
  String? _selectedLogoName;
  bool _isUploadingLogo = false;

  // Listas de Precios Personalizadas
  List<Map<String, dynamic>> _customTiers = [];
  final _tierNameCtrl = TextEditingController();
  final _tierModCtrl = TextEditingController();

  // Precios Globales
  final _cardPercentageCtrl = TextEditingController();
  final _wholesalePercentageCtrl = TextEditingController();
  bool _advancedPriceTiersEnabled = false; // ━━━━━━━━ Feature Toggle Multi-Tenant ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  bool _isIibbPerceptionAgent = false;
  final _defaultIibbRateCtrl = TextEditingController();

  // Red y Rutas Locales
  final _backendPathCtrl = TextEditingController();
  final _serverUrlCtrl =
      TextEditingController(); // Para unificar la edición de URL en el form

  // Licencia
  final _licenseKeyCtrl = TextEditingController();
  bool _isActivatingLicense = false;
  bool _isSyncingLicense = false;
  bool _isCheckingUpdate = false;
  String _appVersion = '';

  // Developer Mode
  int _versionTaps = 0;
  String _currentChannel = 'stable';

  // Integraciones (Mercado Pago & ARCA/AFIP)
  final _mpAccessTokenCtrl = TextEditingController();
  final _mpWebhookSecretCtrl = TextEditingController();
  final _mpPointDeviceIdCtrl = TextEditingController();
  final _mpWebhookUrlCtrl = TextEditingController();
  bool _mpQrEnabled = false;
  bool _obscureMpToken = true;
  bool _obscureMpSecret = true;
  bool _isTestingMpConnection = false;
  bool _isSavingIntegrations = false;

  final _afipCuitCtrl = TextEditingController();
  final _afipPtoVtaCtrl = TextEditingController();
  final _afipKeyPassphraseCtrl = TextEditingController();
  bool _obscureAfipPassphrase = true;
  Uint8List? _selectedCertBytes;
  String? _selectedCertName;
  Uint8List? _selectedKeyBytes;
  String? _selectedKeyName;
  bool _isUploadingCertificates = false;
  String _afipEnvironment = 'testing';
  bool _afipEnabled = false;
  bool _afipHasCert = false;
  bool _afipHasKey = false;
  final ExpansibleController _mpExpCtrl = ExpansibleController();
  final ExpansibleController _afipExpCtrl = ExpansibleController();
  String? _afipCertExpiresAt;
  final ExpansibleController _ecommerceExpCtrl = ExpansibleController();
  final ExpansibleController _meliExpCtrl = ExpansibleController();
  final ExpansibleController _wooExpCtrl = ExpansibleController();
  final ExpansibleController _tnExpCtrl = ExpansibleController();
  bool _ecommerceEnabled = false;
  final _tiendanubeStoreIdCtrl = TextEditingController();
  final _tiendanubeAccessTokenCtrl = TextEditingController();
  final _wooCommerceBaseUrlCtrl = TextEditingController();
  final _wooCommerceConsumerKeyCtrl = TextEditingController();
  final _wooCommerceConsumerSecretCtrl = TextEditingController();
  final _meliClientIdCtrl = TextEditingController();
  final _meliClientSecretCtrl = TextEditingController();

  bool _obscureTiendanubeToken = true;
  bool _obscureWooSecret = true;
  bool _obscureMeliSecret = true;

  int? _meliIntegrationId;
  bool _meliActive = true;
  bool _meliSyncStock = true;
  bool _meliAutoPause = true;
  String _meliHealthStatus = 'unknown';
  bool _isTestingMeli = false;
  String? _originalMeliSecret;

  int? _wooIntegrationId;
  bool _wooActive = true;
  bool _wooSyncStock = true;
  bool _wooAutoPause = true;
  String _wooHealthStatus = 'unknown';
  bool _isTestingWoo = false;
  String? _originalWooSecret;

  int? _tiendanubeIntegrationId;
  bool _tiendanubeActive = true;
  bool _tiendanubeSyncStock = true;
  bool _tiendanubeAutoPause = true;
  String _tiendanubeHealthStatus = 'unknown';
  bool _isTestingTiendanube = false;
  String? _originalTiendanubeToken;

  bool _integrationsLoaded = false;
  bool _isLoadingIntegrations = false;

  String? _selectedTaxCondition = 'IVA Responsable Inscripto';
  final _iibbCtrl = TextEditingController();
  final _activityStartDateCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadChannel();

    // Listener para auto-completar la ruta del backend si el tí©cnico cambia la URL
    _serverUrlCtrl.addListener(_handleUrlChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<SettingsProvider>();
      final settings = provider.settings;
      if (settings != null) {
        _companyNameCtrl.text = settings.companyName ?? '';
        _addressCtrl.text = settings.address ?? '';
        _phoneCtrl.text = settings.phone ?? '';
        _taxIdCtrl.text = settings.taxId ?? '';
        _footerCtrl.text = settings.receiptFooterMessage ?? '';
        
        _selectedTaxCondition = settings.taxCondition;
        if (_selectedTaxCondition == null || _selectedTaxCondition!.isEmpty) {
           _selectedTaxCondition = 'IVA Responsable Inscripto';
        }
        _iibbCtrl.text = (settings.iibb == null || settings.iibb!.isEmpty) ? 'Exento' : settings.iibb!;
        _activityStartDateCtrl.text = settings.activityStartDate ?? '';

        _cardPercentageCtrl.text = settings.globalCardPercentage.toString();
        _wholesalePercentageCtrl.text =
            settings.globalWholesalePercentage.toString();
        _advancedPriceTiersEnabled = settings.enableAdvancedPriceTiers;
        _isIibbPerceptionAgent = settings.isIibbPerceptionAgent;
        _defaultIibbRateCtrl.text = settings.defaultIibbPerceptionRate > 0
            ? settings.defaultIibbPerceptionRate.toString()
            : '';

        _customTiers = List<Map<String, dynamic>>.from(
            settings.customPriceTiers.map((e) => Map<String, dynamic>.from(e)));

        if (mounted) setState(() {});
      }

      // Cargar configuraciones locales de SharedPreferences
      SharedPreferences.getInstance().then((prefs) {
        if (mounted) {
          setState(() {
            _backendPathCtrl.text =
                prefs.getString('backend_install_path') ?? '';
            _serverUrlCtrl.text =
                prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;

            // Si la ruta estí¡ vací­a al iniciar, intentamos auto-detectar una sugerencia
            if (_backendPathCtrl.text.isEmpty) {
              _autoDetectBackendPath();
            }
          });
        }
      });

      final auth = context.read<AuthProvider?>();
      final canManageSettings =
          auth != null && (auth.isAdmin || auth.hasPermission(AppPermissions.manageSettings));
      if (canManageSettings) {
        _loadIntegrationsData();
      }
    });
  }

  void _handleUrlChange() {
    // Si el tí©cnico estí¡ escribiendo la URL y la ruta estí¡ vací­a, intentamos ayudar
    if (_backendPathCtrl.text.isEmpty) {
      _autoDetectBackendPath();
    }
  }

  void _autoDetectBackendPath() {
    // Estrategia 1: Carpeta hermana (Estructura de producción ideal)
    // exe en: <raí­z>/pos-frontend/app.exe  -> busca <raí­z>/pos-backend
    try {
      final installDir = File(Platform.resolvedExecutable).parent;
      final siblingBackend = p.join(installDir.parent.path, 'pos-backend');
      if (Directory(siblingBackend).existsSync()) {
        setState(() => _backendPathCtrl.text = siblingBackend);
        debugPrint(
            '[Settings] Ruta detectada por estructura de carpetas: $siblingBackend');
        return;
      }
    } catch (_) {}

    // Estrategia 2: Derivación desde la URL (Estructura Laragon estándar)
    // Solo si es localhost/127.0.0.1 y no pudimos por Estrategia 1
    try {
      final uri = Uri.parse(_serverUrlCtrl.text);
      if (uri.host == '127.0.0.1' || uri.host == 'localhost') {
        final webPath = uri.path.replaceAll(RegExp(r'/public/api$'), '');
        final guessedPath = r'C:\laragon\www' + webPath.replaceAll('/', r'\');
        if (Directory(guessedPath).existsSync()) {
          setState(() => _backendPathCtrl.text = guessedPath);
          debugPrint('[Settings] Ruta detectada por URL Laragon: $guessedPath');
        }
      }
    } catch (_) {}
  }

  Future<void> _loadIntegrationsData() async {
    final auth = context.read<AuthProvider?>();
    final canManageSettings =
        auth != null && (auth.isAdmin || auth.hasPermission(AppPermissions.manageSettings));
    if (!canManageSettings) return;

    setState(() => _isLoadingIntegrations = true);
    try {
      final provider = context.read<SettingsProvider>();
      final data = await provider.loadIntegrations(isSilent: true);
      List<EcommerceIntegration> ecomList = [];
      try {
        ecomList = await provider.loadEcommerceIntegrations(isSilent: true);
      } catch (e) {
        debugPrint('[SettingsScreen] Info: no se cargaron integraciones e-commerce: $e');
      }
      if (data != null && mounted) {
        setState(() {
          _mpAccessTokenCtrl.text = data['mp_access_token']?.toString() ?? '';
          _mpWebhookSecretCtrl.text = data['mp_webhook_secret']?.toString() ?? '';
          _mpPointDeviceIdCtrl.text = data['mp_point_device_id']?.toString() ?? '';
          _mpQrEnabled = data['mp_qr_enabled'] == true ||
              data['mp_qr_enabled'] == '1' ||
              data['mp_qr_enabled'] == 1;

          final webhookUrl = data['mp_webhook_url']?.toString();
          if (webhookUrl != null && webhookUrl.isNotEmpty) {
            _mpWebhookUrlCtrl.text = webhookUrl;
          } else {
            final activeUrl = _serverUrlCtrl.text.isNotEmpty
                ? _serverUrlCtrl.text
                : provider.currentApiUrl;
            _mpWebhookUrlCtrl.text = '$activeUrl/webhooks/mercadopago';
          }

          _afipEnabled = data['afip_enabled'] == true ||
              data['afip_enabled'] == '1' ||
              data['afip_enabled'] == 1;
          _afipCuitCtrl.text = data['afip_cuit']?.toString() ?? '';
          _afipPtoVtaCtrl.text =
              (data['afip_pto_vta'] != null && data['afip_pto_vta'].toString() != '0')
                  ? data['afip_pto_vta'].toString()
                  : '';
          _afipEnvironment = data['afip_environment']?.toString() ?? 'testing';
          _afipHasCert = data['afip_has_cert'] == true;
          _afipHasKey = data['afip_has_key'] == true;
          _afipCertExpiresAt = data['afip_cert_expires_at']?.toString();
          
          _ecommerceEnabled = data['ecommerce_enabled'] == true ||
              data['ecommerce_enabled'] == '1' ||
              data['ecommerce_enabled'] == 1;
          _tiendanubeAccessTokenCtrl.text = data['tiendanube_token']?.toString() ?? '';
          _wooCommerceConsumerKeyCtrl.text = data['woo_key']?.toString() ?? '';
          _wooCommerceConsumerSecretCtrl.text = data['woo_secret']?.toString() ?? '';
          _meliClientIdCtrl.text = data['meli_client_id']?.toString() ?? '';
          _meliClientSecretCtrl.text = data['meli_client_secret']?.toString() ?? '';

          for (final item in ecomList) {
            if (item.platform == 'mercadolibre') {
              _meliIntegrationId = item.id;
              _meliClientIdCtrl.text = item.clientId ?? '';
              _meliClientSecretCtrl.text = item.clientSecret ?? '';
              _originalMeliSecret = item.clientSecret;
              _meliActive = item.isActive;
              _meliSyncStock = item.syncStockEnabled;
              _meliAutoPause = item.autoPauseOnZeroStock;
              _meliHealthStatus = item.lastHealthStatus;
            } else if (item.platform == 'woocommerce') {
              _wooIntegrationId = item.id;
              _wooCommerceBaseUrlCtrl.text = item.baseUrl ?? '';
              _wooCommerceConsumerKeyCtrl.text = item.clientId ?? '';
              _wooCommerceConsumerSecretCtrl.text = item.clientSecret ?? '';
              _originalWooSecret = item.clientSecret;
              _wooActive = item.isActive;
              _wooSyncStock = item.syncStockEnabled;
              _wooAutoPause = item.autoPauseOnZeroStock;
              _wooHealthStatus = item.lastHealthStatus;
            } else if (item.platform == 'tiendanube') {
              _tiendanubeIntegrationId = item.id;
              _tiendanubeStoreIdCtrl.text = item.storeId ?? '';
              _tiendanubeAccessTokenCtrl.text = item.accessToken ?? '';
              _originalTiendanubeToken = item.accessToken;
              _tiendanubeActive = item.isActive;
              _tiendanubeSyncStock = item.syncStockEnabled;
              _tiendanubeAutoPause = item.autoPauseOnZeroStock;
              _tiendanubeHealthStatus = item.lastHealthStatus;
            }
          }
          if (ecomList.any((e) => e.isActive)) {
            _ecommerceEnabled = true;
          }
          
          _integrationsLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('[SettingsScreen] Error al cargar integraciones: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingIntegrations = false);
      }
    }
  }

  void _collapseAllIntegrations() {
    try {
      if (_mpExpCtrl.isExpanded) _mpExpCtrl.collapse();
    } catch (_) {}
    try {
      if (_afipExpCtrl.isExpanded) _afipExpCtrl.collapse();
    } catch (_) {}
    try {
      if (_ecommerceExpCtrl.isExpanded) _ecommerceExpCtrl.collapse();
    } catch (_) {}
    try {
      if (_meliExpCtrl.isExpanded) _meliExpCtrl.collapse();
    } catch (_) {}
    try {
      if (_wooExpCtrl.isExpanded) _wooExpCtrl.collapse();
    } catch (_) {}
    try {
      if (_tnExpCtrl.isExpanded) _tnExpCtrl.collapse();
    } catch (_) {}
  }

  Future<void> _testMercadoPagoConnection() async {
    if (_isSavingIntegrations) return;
    final auth = context.read<AuthProvider?>();
    final canManageSettings =
        auth != null && (auth.isAdmin || auth.hasPermission(AppPermissions.manageSettings));
    if (!canManageSettings) {
      if (mounted) {
        SnackBarService.error(
            context, 'No tienes permisos para probar la conexión.');
      }
      return;
    }

    final token = _mpAccessTokenCtrl.text.trim();
    if (token.isEmpty) {
      if (mounted) {
        SnackBarService.warning(
            context, 'Debe ingresar un Access Token para probar la conexión.');
      }
      return;
    }

    setState(() => _isTestingMpConnection = true);
    try {
      final provider = context.read<SettingsProvider>();
      final result = await provider.testMercadoPagoConnection(
        mpAccessToken: token,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        final nickname = result['nickname'];
        final detail = nickname != null ? ' (Usuario: $nickname)' : '';
        SnackBarService.success(context, 'Conexión con Mercado Pago exitosa$detail.');
      } else {
        final message =
            result['message']?.toString() ?? 'Error al conectar con Mercado Pago.';
        SnackBarService.error(context, message);
      }
    } catch (_) {
      if (mounted) {
        SnackBarService.error(
            context, 'No se pudo verificar la conexión con Mercado Pago.');
      }
    } finally {
      if (mounted) {
        setState(() => _isTestingMpConnection = false);
      }
    }
  }

  Future<void> _pickAfipCert() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['crt'],
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;
        List<int>? bytes = file.bytes;
        if (bytes == null && file.path != null && file.path!.isNotEmpty) {
          try {
            bytes = await File(file.path!).readAsBytes();
          } catch (_) {}
        }
        if (bytes != null) {
          setState(() {
            _selectedCertBytes = Uint8List.fromList(bytes!);
            _selectedCertName = file.name;
          });
        }
      }
    } catch (e) {
      debugPrint('[SettingsScreen] Error al seleccionar certificado: $e');
      if (mounted) {
        SnackBarService.error(context, 'Error al seleccionar el certificado');
      }
    }
  }

  Future<void> _pickAfipKey() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['key'],
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;
        List<int>? bytes = file.bytes;
        if (bytes == null && file.path != null && file.path!.isNotEmpty) {
          try {
            bytes = await File(file.path!).readAsBytes();
          } catch (_) {}
        }
        if (bytes != null) {
          setState(() {
            _selectedKeyBytes = Uint8List.fromList(bytes!);
            _selectedKeyName = file.name;
          });
        }
      }
    } catch (e) {
      debugPrint('[SettingsScreen] Error al seleccionar clave privada: $e');
      if (mounted) {
        SnackBarService.error(context, 'Error al seleccionar la clave privada');
      }
    }
  }

  Future<void> _uploadAfipCertificates() async {
    if (_isUploadingCertificates || _isSavingIntegrations) return;

    final auth = context.read<AuthProvider?>();
    final canManageSettings =
        auth != null && (auth.isAdmin || auth.hasPermission(AppPermissions.manageSettings));
    if (!canManageSettings) {
      if (mounted) {
        SnackBarService.error(context, 'No tienes permisos para modificar la configuración de ARCA.');
      }
      return;
    }

    final cuit = _afipCuitCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
    if (cuit.isEmpty || cuit.length < 10) {
      if (mounted) {
        SnackBarService.warning(context, 'Debe ingresar un CUIT comercial válido.');
      }
      return;
    }

    if (_selectedCertBytes == null || _selectedKeyBytes == null) {
      if (mounted) {
        SnackBarService.warning(context, 'Debe seleccionar tanto el certificado (.crt) como la clave privada (.key).');
      }
      return;
    }

    setState(() => _isUploadingCertificates = true);
    try {
      final provider = context.read<SettingsProvider>();
      final result = await provider.uploadAfipCertificates(
        cuit: cuit,
        certBytes: _selectedCertBytes!,
        certFilename: _selectedCertName ?? 'cert.crt',
        keyBytes: _selectedKeyBytes!,
        keyFilename: _selectedKeyName ?? 'cert.key',
        keyPassphrase: _afipKeyPassphraseCtrl.text.trim().isNotEmpty
            ? _afipKeyPassphraseCtrl.text.trim()
            : null,
      );

      if (!mounted) return;

      setState(() {
        _selectedCertBytes = null;
        _selectedCertName = null;
        _selectedKeyBytes = null;
        _selectedKeyName = null;
        _afipKeyPassphraseCtrl.clear();
        _afipHasCert = result['afip_has_cert'] == true || provider.integrations?['afip_has_cert'] == true;
        _afipHasKey = result['afip_has_key'] == true || provider.integrations?['afip_has_key'] == true;
        if (result['afip_cert_expires_at'] != null) {
          _afipCertExpiresAt = result['afip_cert_expires_at'].toString();
        } else if (provider.integrations?['afip_cert_expires_at'] != null) {
          _afipCertExpiresAt = provider.integrations!['afip_cert_expires_at'].toString();
        }
      });

      SnackBarService.success(context, result['message']?.toString() ?? 'Certificados de AFIP guardados y validados correctamente.');
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceAll('Exception: ', '');
        SnackBarService.error(context, msg.isNotEmpty ? msg : 'Error al subir certificados de AFIP.');
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingCertificates = false);
      }
    }
  }

  Future<void> _toggleSecretVisibility({
    required String action,
    required bool isCurrentlyObscured,
    required void Function(bool) onToggle,
  }) async {
    if (isCurrentlyObscured) {
      final ok = await AdminPinDialog.verify(
        context,
        action: action,
        permissionKey: null,
      );
      if (!ok || !mounted) return;
    }
    setState(() => onToggle(!isCurrentlyObscured));
  }

  Future<bool> _saveIntegrations({bool showFeedback = true}) async {
    final auth = context.read<AuthProvider?>();
    final canManageSettings =
        auth != null && (auth.isAdmin || auth.hasPermission(AppPermissions.manageSettings));
    if (!canManageSettings) {
      if (showFeedback && mounted) {
        SnackBarService.error(
            context, 'No tienes permisos para modificar integraciones.');
      }
      return false;
    }

    final authorized = await AdminPinDialog.verify(
      context,
      action: 'Guardar Credenciales de Integración',
      permissionKey: AppPermissions.manageSettings,
    );
    if (!authorized) return false;

    if (_isTestingMpConnection) {
      if (showFeedback && mounted) {
        SnackBarService.warning(
            context, 'Espere a que finalice la prueba de conexión.');
      }
      return false;
    }

    if (!_integrationsLoaded) {
      if (showFeedback && mounted) {
        SnackBarService.warning(
            context, 'No se cargaron los datos de integraciones. Reintente antes de guardar.');
      }
      return false;
    }

    setState(() => _isSavingIntegrations = true);
    try {
      final provider = context.read<SettingsProvider>();
      final ptoVtaText = _afipPtoVtaCtrl.text.trim();
      int? ptoVta;
      if (ptoVtaText.isNotEmpty) {
        final parsed = int.tryParse(ptoVtaText);
        if (parsed == null || parsed < 1 || parsed > 99999) {
          if (showFeedback && mounted) {
            SnackBarService.error(
                context, 'El Punto de Venta debe ser un número entre 1 y 99999.');
          }
          return false;
        }
        ptoVta = parsed;
      }

      final data = <String, dynamic>{
        'mp_qr_enabled': _mpQrEnabled ? '1' : '0',
        'mp_point_device_id': _mpPointDeviceIdCtrl.text.trim(),
        'mp_access_token': _mpAccessTokenCtrl.text.trim(),
        'mp_webhook_secret': _mpWebhookSecretCtrl.text.trim(),
        'afip_enabled': _afipEnabled ? '1' : '0',
        'afip_cuit': _afipCuitCtrl.text.trim(),
        'afip_pto_vta': ptoVta,
        'afip_environment': _afipEnvironment,
        'ecommerce_enabled': _ecommerceEnabled ? '1' : '0',
        'tiendanube_token': _tiendanubeAccessTokenCtrl.text.trim(),
        'woo_key': _wooCommerceConsumerKeyCtrl.text.trim(),
        'woo_secret': _wooCommerceConsumerSecretCtrl.text.trim(),
        'meli_client_id': _meliClientIdCtrl.text.trim(),
        'meli_client_secret': _meliClientSecretCtrl.text.trim(),
      };

      final success = await provider.saveIntegrations(data);
      if (!mounted) return false;

      // Guardar también plataformas de E-Commerce si tienen credenciales o IDs
      if (_meliClientIdCtrl.text.isNotEmpty || _meliIntegrationId != null) {
        await _saveMeliIntegration(showFeedback: false);
      }
      if (_wooCommerceBaseUrlCtrl.text.isNotEmpty || _wooCommerceConsumerKeyCtrl.text.isNotEmpty || _wooIntegrationId != null) {
        await _saveWooIntegration(showFeedback: false);
      }
      if (_tiendanubeStoreIdCtrl.text.isNotEmpty || _tiendanubeAccessTokenCtrl.text.isNotEmpty || _tiendanubeIntegrationId != null) {
        await _saveTiendanubeIntegration(showFeedback: false);
      }

      if (success) {
        if (showFeedback) {
          SnackBarService.success(
              context, 'Configuración de integraciones guardada correctamente.');
        }
        await _loadIntegrationsData();
        return true;
      } else {
        if (showFeedback) {
          SnackBarService.error(
              context, provider.errorMessage ?? 'Error al guardar integraciones.');
        }
        return false;
      }
    } catch (e) {
      if (mounted && showFeedback) {
        SnackBarService.error(context, 'Error al guardar integraciones.');
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _isSavingIntegrations = false);
      }
    }
  }

  Future<bool> _saveMeliIntegration({bool showFeedback = true}) async {
    final clientId = _meliClientIdCtrl.text.trim();
    final clientSecret = _meliClientSecretCtrl.text.trim();

    if (clientId.isEmpty) {
      if (showFeedback && mounted) {
        SnackBarService.warning(context, 'Debe ingresar Client ID para guardar Mercado Libre.');
      }
      return false;
    }

    try {
      final provider = context.read<SettingsProvider>();
      final data = <String, dynamic>{
        'platform': 'mercadolibre',
        'name': 'Mercado Libre',
        'client_id': clientId,
        'is_active': _meliActive,
        'sync_stock_enabled': _meliSyncStock,
        'auto_pause_on_zero_stock': _meliAutoPause,
      };

      if (clientSecret.isNotEmpty) {
        data['client_secret'] = clientSecret;
      }

      final saved = await provider.saveEcommerceIntegration(data, id: _meliIntegrationId);
      if (saved != null) {
        if (mounted) {
          setState(() {
            _meliIntegrationId = saved.id;
            _originalMeliSecret = saved.clientSecret;
            if (saved.clientSecret != null && saved.clientSecret!.isNotEmpty) {
              _meliClientSecretCtrl.text = saved.clientSecret!;
            }
          });
          if (showFeedback) {
            SnackBarService.success(context, 'Configuración de Mercado Libre guardada correctamente.');
          }
        }
        return true;
      }
      return false;
    } catch (e) {
      if (showFeedback && mounted) {
        SnackBarService.error(context, 'Error al guardar Mercado Libre: $e');
      }
      return false;
    }
  }

  Future<bool> _saveWooIntegration({bool showFeedback = true}) async {
    final baseUrl = _wooCommerceBaseUrlCtrl.text.trim();
    final clientId = _wooCommerceConsumerKeyCtrl.text.trim();
    final clientSecret = _wooCommerceConsumerSecretCtrl.text.trim();

    if (baseUrl.isEmpty || clientId.isEmpty) {
      if (showFeedback && mounted) {
        SnackBarService.warning(context, 'Debe ingresar URL de la tienda y Consumer Key para guardar WooCommerce.');
      }
      return false;
    }

    try {
      final provider = context.read<SettingsProvider>();
      final data = <String, dynamic>{
        'platform': 'woocommerce',
        'name': 'WooCommerce',
        'base_url': baseUrl,
        'client_id': clientId,
        'is_active': _wooActive,
        'sync_stock_enabled': _wooSyncStock,
        'auto_pause_on_zero_stock': _wooAutoPause,
      };

      if (clientSecret.isNotEmpty) {
        data['client_secret'] = clientSecret;
      }

      final saved = await provider.saveEcommerceIntegration(data, id: _wooIntegrationId);
      if (saved != null) {
        if (mounted) {
          setState(() {
            _wooIntegrationId = saved.id;
            _originalWooSecret = saved.clientSecret;
            if (saved.clientSecret != null && saved.clientSecret!.isNotEmpty) {
              _wooCommerceConsumerSecretCtrl.text = saved.clientSecret!;
            }
          });
          if (showFeedback) {
            SnackBarService.success(context, 'Configuración de WooCommerce guardada correctamente.');
          }
        }
        return true;
      }
      return false;
    } catch (e) {
      if (showFeedback && mounted) {
        SnackBarService.error(context, 'Error al guardar WooCommerce: $e');
      }
      return false;
    }
  }

  Future<bool> _saveTiendanubeIntegration({bool showFeedback = true}) async {
    final storeId = _tiendanubeStoreIdCtrl.text.trim();
    final accessToken = _tiendanubeAccessTokenCtrl.text.trim();

    if (storeId.isEmpty) {
      if (showFeedback && mounted) {
        SnackBarService.warning(context, 'Debe ingresar Store ID para guardar Tienda Nube.');
      }
      return false;
    }

    try {
      final provider = context.read<SettingsProvider>();
      final data = <String, dynamic>{
        'platform': 'tiendanube',
        'name': 'Tienda Nube',
        'store_id': storeId,
        'is_active': _tiendanubeActive,
        'sync_stock_enabled': _tiendanubeSyncStock,
        'auto_pause_on_zero_stock': _tiendanubeAutoPause,
      };

      if (accessToken.isNotEmpty) {
        data['access_token'] = accessToken;
      }

      final saved = await provider.saveEcommerceIntegration(data, id: _tiendanubeIntegrationId);
      if (saved != null) {
        if (mounted) {
          setState(() {
            _tiendanubeIntegrationId = saved.id;
            _originalTiendanubeToken = saved.accessToken;
            if (saved.accessToken != null && saved.accessToken!.isNotEmpty) {
              _tiendanubeAccessTokenCtrl.text = saved.accessToken!;
            }
          });
          if (showFeedback) {
            SnackBarService.success(context, 'Configuración de Tienda Nube guardada correctamente.');
          }
        }
        return true;
      }
      return false;
    } catch (e) {
      if (showFeedback && mounted) {
        SnackBarService.error(context, 'Error al guardar Tienda Nube: $e');
      }
      return false;
    }
  }

  Future<void> _testMeliConnection() async {
    if (_isTestingMeli) return;
    final auth = context.read<AuthProvider?>();
    final canManageSettings =
        auth != null && (auth.isAdmin || auth.hasPermission(AppPermissions.manageSettings));
    if (!canManageSettings) {
      if (mounted) SnackBarService.error(context, 'No tienes permisos para probar la conexión.');
      return;
    }

    final clientId = _meliClientIdCtrl.text.trim();
    final clientSecret = _meliClientSecretCtrl.text.trim();
    if (clientId.isEmpty) {
      if (mounted) SnackBarService.warning(context, 'Debe ingresar Client ID / App ID para probar la conexión con Mercado Libre.');
      return;
    }
    if (clientSecret.isEmpty && (_originalMeliSecret == null || _originalMeliSecret!.isEmpty)) {
      if (mounted) SnackBarService.warning(context, 'Debe ingresar Client Secret para probar la conexión con Mercado Libre.');
      return;
    }

    setState(() => _isTestingMeli = true);
    try {
      final provider = context.read<SettingsProvider>();
      final saved = await _saveMeliIntegration(showFeedback: false);
      if (!saved) {
        if (mounted) SnackBarService.error(context, 'No se pudo guardar la configuración de Mercado Libre antes de probar.');
        return;
      }

      if (_meliIntegrationId != null) {
        final result = await provider.testEcommerceConnection(_meliIntegrationId!);
        if (!mounted) return;
        if (result['success'] == true) {
          setState(() => _meliHealthStatus = 'connected');
          SnackBarService.success(context, 'Conexión con Mercado Libre exitosa. ${result['message'] ?? ''}'.trim());
        } else {
          setState(() => _meliHealthStatus = 'error');
          SnackBarService.error(context, result['message']?.toString() ?? 'Error al conectar con Mercado Libre.');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _meliHealthStatus = 'error');
        SnackBarService.error(context, 'Error al probar conexión con Mercado Libre: $e');
      }
    } finally {
      if (mounted) setState(() => _isTestingMeli = false);
    }
  }

  Future<void> _testWooConnection() async {
    if (_isTestingWoo) return;
    final auth = context.read<AuthProvider?>();
    final canManageSettings =
        auth != null && (auth.isAdmin || auth.hasPermission(AppPermissions.manageSettings));
    if (!canManageSettings) {
      if (mounted) SnackBarService.error(context, 'No tienes permisos para probar la conexión.');
      return;
    }

    final baseUrl = _wooCommerceBaseUrlCtrl.text.trim();
    final clientId = _wooCommerceConsumerKeyCtrl.text.trim();
    final clientSecret = _wooCommerceConsumerSecretCtrl.text.trim();

    if (baseUrl.isEmpty) {
      if (mounted) SnackBarService.warning(context, 'Debe ingresar la URL base para probar la conexión con WooCommerce.');
      return;
    }
    if (clientId.isEmpty) {
      if (mounted) SnackBarService.warning(context, 'Debe ingresar Consumer Key para probar la conexión con WooCommerce.');
      return;
    }
    if (clientSecret.isEmpty && (_originalWooSecret == null || _originalWooSecret!.isEmpty)) {
      if (mounted) SnackBarService.warning(context, 'Debe ingresar Consumer Secret para probar la conexión con WooCommerce.');
      return;
    }

    setState(() => _isTestingWoo = true);
    try {
      final provider = context.read<SettingsProvider>();
      final saved = await _saveWooIntegration(showFeedback: false);
      if (!saved) {
        if (mounted) SnackBarService.error(context, 'No se pudo guardar la configuración de WooCommerce antes de probar.');
        return;
      }

      if (_wooIntegrationId != null) {
        final result = await provider.testEcommerceConnection(_wooIntegrationId!);
        if (!mounted) return;
        if (result['success'] == true) {
          setState(() => _wooHealthStatus = 'connected');
          SnackBarService.success(context, 'Conexión con WooCommerce exitosa. ${result['message'] ?? ''}'.trim());
        } else {
          setState(() => _wooHealthStatus = 'error');
          SnackBarService.error(context, result['message']?.toString() ?? 'Error al conectar con WooCommerce.');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _wooHealthStatus = 'error');
        SnackBarService.error(context, 'Error al probar conexión con WooCommerce: $e');
      }
    } finally {
      if (mounted) setState(() => _isTestingWoo = false);
    }
  }

  Future<void> _testTiendanubeConnection() async {
    if (_isTestingTiendanube) return;
    final auth = context.read<AuthProvider?>();
    final canManageSettings =
        auth != null && (auth.isAdmin || auth.hasPermission(AppPermissions.manageSettings));
    if (!canManageSettings) {
      if (mounted) SnackBarService.error(context, 'No tienes permisos para probar la conexión.');
      return;
    }

    final storeId = _tiendanubeStoreIdCtrl.text.trim();
    final accessToken = _tiendanubeAccessTokenCtrl.text.trim();

    if (storeId.isEmpty) {
      if (mounted) SnackBarService.warning(context, 'Debe ingresar Store ID para probar la conexión con Tienda Nube.');
      return;
    }
    if (accessToken.isEmpty && (_originalTiendanubeToken == null || _originalTiendanubeToken!.isEmpty)) {
      if (mounted) SnackBarService.warning(context, 'Debe ingresar Access Token para probar la conexión con Tienda Nube.');
      return;
    }

    setState(() => _isTestingTiendanube = true);
    try {
      final provider = context.read<SettingsProvider>();
      final saved = await _saveTiendanubeIntegration(showFeedback: false);
      if (!saved) {
        if (mounted) SnackBarService.error(context, 'No se pudo guardar la configuración de Tienda Nube antes de probar.');
        return;
      }

      if (_tiendanubeIntegrationId != null) {
        final result = await provider.testEcommerceConnection(_tiendanubeIntegrationId!);
        if (!mounted) return;
        if (result['success'] == true) {
          setState(() => _tiendanubeHealthStatus = 'connected');
          SnackBarService.success(context, 'Conexión con Tienda Nube exitosa. ${result['message'] ?? ''}'.trim());
        } else {
          setState(() => _tiendanubeHealthStatus = 'error');
          SnackBarService.error(context, result['message']?.toString() ?? 'Error al conectar con Tienda Nube.');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _tiendanubeHealthStatus = 'error');
        SnackBarService.error(context, 'Error al probar conexión con Tienda Nube: $e');
      }
    } finally {
      if (mounted) setState(() => _isTestingTiendanube = false);
    }
  }

  Future<void> _toggleMeliActive(bool val) async {
    setState(() => _meliActive = val);
    if (_meliIntegrationId != null) {
      try {
        final provider = context.read<SettingsProvider>();
        await provider.toggleEcommerceActive(_meliIntegrationId!);
      } catch (e) {
        debugPrint('[SettingsScreen] Error toggling meli active: $e');
      }
    }
  }

  Future<void> _toggleWooActive(bool val) async {
    setState(() => _wooActive = val);
    if (_wooIntegrationId != null) {
      try {
        final provider = context.read<SettingsProvider>();
        await provider.toggleEcommerceActive(_wooIntegrationId!);
      } catch (e) {
        debugPrint('[SettingsScreen] Error toggling woo active: $e');
      }
    }
  }

  Future<void> _toggleTiendanubeActive(bool val) async {
    setState(() => _tiendanubeActive = val);
    if (_tiendanubeIntegrationId != null) {
      try {
        final provider = context.read<SettingsProvider>();
        await provider.toggleEcommerceActive(_tiendanubeIntegrationId!);
      } catch (e) {
        debugPrint('[SettingsScreen] Error toggling tiendanube active: $e');
      }
    }
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
    _defaultIibbRateCtrl.dispose();
    _serverUrlCtrl.removeListener(_handleUrlChange);
    _backendPathCtrl.dispose();
    _serverUrlCtrl.dispose();
    _mpAccessTokenCtrl.dispose();
    _mpWebhookSecretCtrl.dispose();
    _mpPointDeviceIdCtrl.dispose();
    _mpWebhookUrlCtrl.dispose();
    _afipCuitCtrl.dispose();
    _afipPtoVtaCtrl.dispose();
    _afipKeyPassphraseCtrl.dispose();
    _tiendanubeStoreIdCtrl.dispose();
    _tiendanubeAccessTokenCtrl.dispose();
    _wooCommerceBaseUrlCtrl.dispose();
    _wooCommerceConsumerKeyCtrl.dispose();
    _wooCommerceConsumerSecretCtrl.dispose();
    _meliClientIdCtrl.dispose();
    _meliClientSecretCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    if (_activeSection == SettingsSection.integrations) {
      await _saveIntegrations(showFeedback: true);
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<SettingsProvider>();

    // ━━━━━━━━ IMPORTANTE: guardar URL y ruta local PRIMERO ━━━━━━━━━━━━━━━━━━━━━━━━━
    // Si el usuario cambió la URL del servidor, el request de saveSettings debe
    // usar ya la nueva URL. De lo contrario falla con "No se puede conectar".
    final newUrl = _serverUrlCtrl.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pos_api', newUrl);
    await prefs.setString('backend_install_path', _backendPathCtrl.text.trim());

    // Actualizar el provider en memoria con la nueva URL antes del request HTTP
    provider.updateBaseUrl(newUrl);

    final data = {
      'company_name': _companyNameCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'tax_id': _taxIdCtrl.text.trim(),
      'receipt_footer_message': _footerCtrl.text.trim(),
      'card_percentage': double.tryParse(
              _cardPercentageCtrl.text.trim().replaceAll(',', '.')) ??
          15.0,
      'wholesale_percentage': double.tryParse(
              _wholesalePercentageCtrl.text.trim().replaceAll(',', '.')) ??
          -15.0,
      'custom_price_tiers': _customTiers,
      'enable_advanced_price_tiers': _advancedPriceTiersEnabled ? '1' : '0',
      'is_iibb_perception_agent': _isIibbPerceptionAgent ? '1' : '0',
      'default_iibb_perception_rate': double.tryParse(
              _defaultIibbRateCtrl.text.trim().replaceAll(',', '.')) ??
          0.0,
      'tax_condition': _selectedTaxCondition ?? 'IVA Responsable Inscripto',
      'iibb': _iibbCtrl.text.trim(),
      'activity_start_date': _activityStartDateCtrl.text.trim(),
    };

    final success = await provider.saveSettings(data);

    if (!mounted) return;

    if (success) {
      if (_selectedLogoPath != null || _selectedLogoBytes != null) {
        setState(() => _isUploadingLogo = true);
        final logoSuccess = await provider.uploadLogo(
          _selectedLogoPath ?? '',
          bytes: _selectedLogoBytes,
          filename: _selectedLogoName,
        );
        if (mounted) setState(() => _isUploadingLogo = false);
        if (logoSuccess) {
          setState(() {
            _selectedLogoPath = null;
            _selectedLogoBytes = null;
            _selectedLogoName = null;
          });
          if (mounted) {
            SnackBarService.success(context, 'Configuración y logotipo guardados correctamente');
          }
          return;
        } else {
          if (mounted) {
            final err = provider.errorMessage?.replaceAll('Exception: ', '') ?? 'falló la subida del logotipo';
            SnackBarService.warning(context, 'Configuración guardada, pero $err');
          }
          return;
        }
      }
      SnackBarService.success(context, 'Configuración guardada correctamente');
    } else {
      SnackBarService.error(
          context, provider.errorMessage ?? 'Error al guardar');
    }
  }

  Future<void> _pickLogo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;
        final fileSize = file.size > 0 ? file.size : (file.bytes?.length ?? 0);
        if (fileSize > 2 * 1024 * 1024) {
          if (mounted) {
            SnackBarService.error(context, 'El logotipo no puede superar los 2MB permitidos (mí¡x 2048 KB).');
          }
          return;
        }
        setState(() {
          _selectedLogoPath = file.path;
          _selectedLogoBytes = file.bytes;
          _selectedLogoName = file.name;
        });
      }
    } catch (e) {
      debugPrint('Error seleccionando logo: $e');
      if (mounted) {
        SnackBarService.error(context, 'Error al seleccionar imagen: $e');
      }
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
      'mobile_app': '📱 App Móvil (Inventario y Ventas)',
      'remote_access': '🌐 Acceso Remoto (Cloudflare / Internet)',
      'suppliers': '📦 Gestión de Proveedores (B2B)',
      'expenses': '💸 Gestión de Gastos y Movimientos',
      'multi_rubro': '🏬 Gestión Multi-Rubro',
      'ecommerce_sync': '🌐 Sincronización E-Commerce',
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
      // ⚠️ Usar la URL activa (SharedPrefs) y NO AppConfig.kApiBaseUrl hardcodeado
      final prefs = await SharedPreferences.getInstance();
      final activeUrl = prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;
      final newPlan = await provider.activateLicense(activeUrl, key);
      if (!mounted) return;
      _licenseKeyCtrl.clear();
      SnackBarService.success(
          context, '✅ Licencia activada: ${newPlan.toUpperCase()}');
    } catch (e) {
      if (!mounted) return;
      SnackBarService.error(
          context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isActivatingLicense = false);
    }
  }

  Future<void> _syncLicense() async {
    setState(() => _isSyncingLicense = true);
    try {
      final provider = context.read<SettingsProvider>();
      // ⚠️ Usar la URL activa (SharedPrefs) y NO AppConfig.kApiBaseUrl hardcodeado
      final prefs = await SharedPreferences.getInstance();
      final activeUrl = prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;
      await provider.syncLicenseWithServer(activeUrl);
      if (!mounted) return;
      SnackBarService.success(context, '✅ Permisos sincronizados.');
    } catch (e) {
      if (!mounted) return;
      SnackBarService.error(
          context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSyncingLicense = false);
    }
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = packageInfo.version);
  }

  Future<void> _loadChannel() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() =>
          _currentChannel = prefs.getString('update_channel') ?? 'stable');
    }
  }

  Future<void> _handleVersionTap() async {
    _versionTaps++;
    if (_versionTaps >= 7) {
      _versionTaps = 0;
      final prefs = await SharedPreferences.getInstance();
      final newChannel = _currentChannel == 'stable' ? 'beta' : 'stable';
      await prefs.setString('update_channel', newChannel);
      setState(() => _currentChannel = newChannel);

      if (!mounted) return;
      if (newChannel == 'beta') {
        SnackBarService.success(
            context, 'Modo Desarrollador: Canal Beta Activado 🐛');
      } else {
        SnackBarService.success(
            context, 'Modo Producción: Canal Stable Activado 🚀');
      }
    }
  }

  Future<void> _checkForUpdate() async {
    setState(() => _isCheckingUpdate = true);
    try {
      final result = await UpdateService().checkUpdate(throwErrors: true);
      if (!mounted) return;

      final frontendUpdate = result.frontendUpdate;
      final backendUpdate = result.backendUpdate;

      if (!mounted) return;

      if (frontendUpdate != null && backendUpdate != null) {
        // ESCENARIO 1: ACTUALIZACIíƒ“N DOBLE (INTEGRAL)
        // No damos a elegir, forzamos el flujo integral empezando por el frontend
        showDialog(
          context: context,
          barrierDismissible: !frontendUpdate.isCritical,
          builder: (_) => UpdateDialog(
            updateInfo: frontendUpdate,
            isFullSystemUpdate: true,
          ),
        );
      } else if (frontendUpdate != null) {
        // ESCENARIO 2: Solo Frontend
        showDialog(
          context: context,
          barrierDismissible: !frontendUpdate.isCritical,
          builder: (_) => UpdateDialog(updateInfo: frontendUpdate),
        );
      } else if (backendUpdate != null) {
        // ESCENARIO 3: Solo Backend
        // El backend ya se actualiza automí¡ticamente, solo informamos
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (_) => UpdateDialog(updateInfo: backendUpdate),
        );
      } else {
        SnackBarService.success(
            context, 'Tu sistema estí¡ actualizado (v$_appVersion)');
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
    final auth = context.watch<AuthProvider?>();
    final canManageSettings =
        auth != null && (auth.isAdmin || auth.hasPermission(AppPermissions.manageSettings));

    final isBusy =
        provider.isLoading || _isUploadingLogo || _isSavingIntegrations || _isTestingMpConnection;

    return PopScope(
      canPop: !isBusy,
      child: Scaffold(
        appBar: GlobalAppBar(
          currentRoute: '/settings',
          title: 'Configuración del Sistema',
          showBackButton: true,
        ),
        backgroundColor: const Color(0xFFF8F9FA),
        body: provider.isLoading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 700;

                  if (isCompact) {
                    return Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          _buildCompactTabBar(isBusy, canManageSettings),
                          Expanded(
                            child: SingleChildScrollView(
                              key: ValueKey(_activeSection),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 16),
                                child: _buildActiveSection(provider),
                              ),
                            ),
                          ),
                          _buildCompactBottomBar(isBusy),
                        ],
                      ),
                    );
                  }

                  return Row(
                    children: [
                      // --- SIDEBAR (Xbox Style) ---
                      _buildSidebar(provider, canManageSettings: canManageSettings),

                      // --- CONTENT AREA ---
                      Expanded(
                        child: Form(
                          key: _formKey,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: SingleChildScrollView(
                              key: ValueKey(_activeSection),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 64, vertical: 48),
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
                  );
                },
              ),
      ),
    );
  }

  Widget _buildCompactTabBar(bool isBusy, bool canManageSettings) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            _buildCompactTabChip('General', Icons.storefront_outlined,
                SettingsSection.general, isBusy),
            _buildCompactTabChip('Precios', Icons.price_change_outlined,
                SettingsSection.prices, isBusy),
            _buildCompactTabChip('Suscripción', Icons.verified_user_outlined,
                SettingsSection.subscription, isBusy),
            _buildCompactTabChip(
                'Red', Icons.dns_outlined, SettingsSection.network, isBusy),
            if (canManageSettings)
              _buildCompactTabChip('Integraciones', Icons.hub_outlined,
                  SettingsSection.integrations, isBusy),
            if (Platform.isWindows)
              _buildCompactTabChip('App Móvil', Icons.phone_android,
                  SettingsSection.mobileApp, isBusy),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactTabChip(
      String label, IconData icon, SettingsSection section, bool isBusy) {
    final isSelected = _activeSection == section;
    const activeColor = Color(0xFF673AB7);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: isSelected,
        avatar: Icon(icon,
            size: 16,
            color: isSelected ? Colors.white : Colors.grey.shade700),
        label: Text(label),
        selectedColor: activeColor,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.grey.shade800,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 13,
        ),
        onSelected: isBusy
            ? null
            : (_) {
                if (_activeSection == SettingsSection.integrations && section != SettingsSection.integrations) {
                  _collapseAllIntegrations();
                }
                setState(() => _activeSection = section);
                if (section == SettingsSection.integrations &&
                    !_integrationsLoaded) {
                  _loadIntegrationsData();
                }
              },
      ),
    );
  }

  Widget _buildCompactBottomBar(bool isBusy) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton.icon(
          onPressed: isBusy ? null : _saveSettings,
          icon: isBusy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('GUARDAR',
              style: TextStyle(fontWeight: FontWeight.bold)),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF673AB7),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(SettingsProvider provider,
      {bool canManageSettings = true}) {
    final isBusy =
        provider.isLoading || _isUploadingLogo || _isSavingIntegrations || _isTestingMpConnection;
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
            isBusy: isBusy,
          ),
          _buildSidebarItem(
            icon: Icons.price_change_outlined,
            title: 'Precios Globales',
            section: SettingsSection.prices,
            isBusy: isBusy,
          ),
          _buildSidebarItem(
            icon: Icons.verified_user_outlined,
            title: 'Suscripción',
            section: SettingsSection.subscription,
            isBusy: isBusy,
          ),
          _buildSidebarItem(
            icon: Icons.dns_outlined,
            title: 'Red y Terminales',
            section: SettingsSection.network,
            isBusy: isBusy,
          ),
          if (canManageSettings)
            _buildSidebarItem(
              icon: Icons.hub_outlined,
              title: 'Integraciones',
              section: SettingsSection.integrations,
              isBusy: isBusy,
            ),
          if (Platform.isWindows)
            _buildSidebarItem(
              icon: Icons.phone_android,
              title: 'App Móvil',
              section: SettingsSection.mobileApp,
              isBusy: isBusy,
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                onPressed: isBusy ? null : _saveSettings,
                icon: isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('GUARDAR',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, letterSpacing: 1)),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF673AB7),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(
      {required IconData icon,
      required String title,
      required SettingsSection section,
      bool isBusy = false}) {
    final isActive = _activeSection == section;
    final activeColor = const Color(0xFF673AB7);

    return InkWell(
      onTap: isBusy
          ? null
          : () {
              if (_activeSection == SettingsSection.integrations && section != SettingsSection.integrations) {
                _collapseAllIntegrations();
              }
              setState(() => _activeSection = section);
              if (section == SettingsSection.integrations &&
                  !_integrationsLoaded) {
                _loadIntegrationsData();
              }
            },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: isActive ? activeColor : Colors.grey.shade600, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  color: isActive ? activeColor : Colors.grey.shade700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 8),
              Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                      color: activeColor,
                      borderRadius: BorderRadius.circular(2))),
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
      case SettingsSection.subscription:
        return _buildSubscriptionSection(provider);
      case SettingsSection.network:
        return _buildNetworkSection(provider);
      case SettingsSection.integrations:
        final auth = context.watch<AuthProvider?>();
        final canManageSettings =
            auth != null && (auth.isAdmin || auth.hasPermission(AppPermissions.manageSettings));
        if (!canManageSettings) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(48.0),
              child: Text(
                'No tienes permisos para gestionar integraciones.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          );
        }
        return _buildIntegrationsSection(provider);
      case SettingsSection.mobileApp:
        return MobileAppQrSection(r2PublicBaseUrl: 'https://pub-xxxx.r2.dev'); // Will fix the URL via config if needed or leave a placeholder as they might be doing elsewhere
    }
  }

  Widget _buildIntegrationsSection(SettingsProvider provider) {
    if (_isLoadingIntegrations) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!_integrationsLoaded) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'No se pudo cargar la configuración de integraciones',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Ocurrió un error al consultar el servidor. Verificá la conexión e intentá nuevamente.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const ValueKey('btn_retry_load_integrations'),
                onPressed: _loadIntegrationsData,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF673AB7),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Integraciones',
            'Gestioná de forma avanzada las integraciones de tu cuenta con servicios externos.'),
            const SizedBox(height: 32),

            // Mercado Pago Card
            _buildMercadoPagoCard(isNarrow),
            const SizedBox(height: 32),

            // ARCA / AFIP Card
            _buildAfipCard(isNarrow),
            const SizedBox(height: 32),

            // E-Commerce Card
            _buildEcommerceCard(isNarrow),
            const SizedBox(height: 32),
          ],
        );
      },
    );
  }

  Widget _buildMpStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _mpQrEnabled ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: _mpQrEnabled ? Colors.green.shade200 : Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _mpQrEnabled ? Colors.green.shade600 : Colors.grey.shade500,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              _mpQrEnabled ? 'Activo' : 'Inactivo',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _mpQrEnabled ? Colors.green.shade700 : Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAfipStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _afipEnabled ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: _afipEnabled ? Colors.green.shade200 : Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _afipEnabled ? Colors.green.shade600 : Colors.grey.shade500,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              _afipEnabled ? 'Activo' : 'Inactivo',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _afipEnabled ? Colors.green.shade700 : Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEcommerceStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _ecommerceEnabled ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: _ecommerceEnabled ? Colors.green.shade200 : Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _ecommerceEnabled ? Colors.green.shade600 : Colors.grey.shade500,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              _ecommerceEnabled ? 'Activo' : 'Inactivo',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _ecommerceEnabled ? Colors.green.shade700 : Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelActiveBadge(bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: active ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: active ? Colors.green.shade200 : Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? Colors.green.shade600 : Colors.grey.shade500,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              active ? 'Activo' : 'Inactivo',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: active ? Colors.green.shade700 : Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelHealthBadge(String status) {
    final isConnected = status == 'connected';
    final isError = status == 'error';
    final color = isConnected
        ? Colors.teal
        : (isError ? Colors.red : Colors.grey);
    final label = isConnected
        ? 'Conectado'
        : (isError ? 'Error Conexión' : 'Sin probar');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isConnected
                ? Icons.check_circle_outline
                : (isError ? Icons.error_outline : Icons.help_outline),
            size: 11,
            color: color.shade700,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchRow({
    required Key key,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color activeColor = const Color(0xFF673AB7),
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            key: key,
            value: value,
            activeThumbColor: activeColor,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildMercadoLibreSection(bool isNarrow) {
    const brandColor = Color(0xFFF57F17);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.grey.shade50,
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          controller: _meliExpCtrl,
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: brandColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.storefront, color: brandColor, size: 22),
          ),
          title: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Mercado Libre',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              _buildChannelActiveBadge(_meliActive),
              _buildChannelHealthBadge(_meliHealthStatus),
            ],
          ),
          trailing: Switch(
            key: const ValueKey('switch_meli_active'),
            value: _meliActive,
            activeThumbColor: brandColor,
            onChanged: _toggleMeliActive,
          ),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('field_meli_id'),
              controller: _meliClientIdCtrl,
              decoration: InputDecoration(
                labelText: 'Client ID / App ID',
                prefixIcon: const Icon(Icons.app_registration),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                helperText: 'App ID provisto en el portal de desarrolladores de Mercado Libre',
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const ValueKey('field_meli_secret'),
              controller: _meliClientSecretCtrl,
              obscureText: _obscureMeliSecret,
              decoration: InputDecoration(
                labelText: 'Client Secret',
                prefixIcon: const Icon(Icons.vpn_key),
                suffixIcon: IconButton(
                  icon: Icon(_obscureMeliSecret ? Icons.visibility : Icons.visibility_off),
                  tooltip: _obscureMeliSecret ? 'Mostrar secreto' : 'Ocultar secreto',
                  onPressed: () => _toggleSecretVisibility(
                    action: 'Revelar Secreto de Mercado Libre',
                    isCurrentlyObscured: _obscureMeliSecret,
                    onToggle: (v) => _obscureMeliSecret = v,
                  ),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                helperText: 'Clave secreta. Los valores guardados se protegen en el servidor.',
              ),
            ),
            const SizedBox(height: 14),
            _buildSwitchRow(
              key: const ValueKey('switch_meli_sync_stock'),
              title: 'Sincronizar Stock',
              subtitle: 'Replicar automáticamente el stock de ventas físicas hacia Mercado Libre',
              value: _meliSyncStock,
              activeColor: brandColor,
              onChanged: (val) => setState(() => _meliSyncStock = val),
            ),
            _buildSwitchRow(
              key: const ValueKey('switch_meli_auto_pause'),
              title: 'Pausar publicación al agotar stock',
              subtitle: 'Pausa automáticamente la publicación al quedar en cero para evitar sobreventas',
              value: _meliAutoPause,
              activeColor: brandColor,
              onChanged: (val) => setState(() => _meliAutoPause = val),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('btn_test_meli_connection'),
                  onPressed: _isTestingMeli ? null : _testMeliConnection,
                  icon: _isTestingMeli
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.wifi_tethering, size: 18),
                  label: const Text('Probar Conexión'),
                  style: FilledButton.styleFrom(
                    backgroundColor: brandColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('btn_save_meli'),
                  onPressed: () => _saveMeliIntegration(showFeedback: true),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Guardar Mercado Libre'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: brandColor,
                    side: const BorderSide(color: brandColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWooCommerceSection(bool isNarrow) {
    const brandColor = Color(0xFF7F54B3);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.grey.shade50,
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          controller: _wooExpCtrl,
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: brandColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.shopping_basket_outlined, color: brandColor, size: 22),
          ),
          title: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'WooCommerce',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              _buildChannelActiveBadge(_wooActive),
              _buildChannelHealthBadge(_wooHealthStatus),
            ],
          ),
          trailing: Switch(
            key: const ValueKey('switch_woo_active'),
            value: _wooActive,
            activeThumbColor: brandColor,
            onChanged: _toggleWooActive,
          ),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('field_woo_url'),
              controller: _wooCommerceBaseUrlCtrl,
              decoration: InputDecoration(
                labelText: 'URL de la Tienda (Base URL)',
                hintText: 'https://mitienda.com',
                prefixIcon: const Icon(Icons.language),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                helperText: 'Dirección completa del sitio WordPress donde corre WooCommerce',
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const ValueKey('field_woo_key'),
              controller: _wooCommerceConsumerKeyCtrl,
              decoration: InputDecoration(
                labelText: 'Consumer Key (client_id)',
                prefixIcon: const Icon(Icons.key),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const ValueKey('field_woo_secret'),
              controller: _wooCommerceConsumerSecretCtrl,
              obscureText: _obscureWooSecret,
              decoration: InputDecoration(
                labelText: 'Consumer Secret (client_secret)',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscureWooSecret ? Icons.visibility : Icons.visibility_off),
                  tooltip: _obscureWooSecret ? 'Mostrar secreto' : 'Ocultar secreto',
                  onPressed: () => _toggleSecretVisibility(
                    action: 'Revelar Secreto de WooCommerce',
                    isCurrentlyObscured: _obscureWooSecret,
                    onToggle: (v) => _obscureWooSecret = v,
                  ),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                helperText: 'Clave secreta Consumer Secret generada en WooCommerce REST API',
              ),
            ),
            const SizedBox(height: 14),
            _buildSwitchRow(
              key: const ValueKey('switch_woo_sync_stock'),
              title: 'Sincronizar Stock',
              subtitle: 'Replicar automáticamente el stock de ventas físicas hacia WooCommerce',
              value: _wooSyncStock,
              activeColor: brandColor,
              onChanged: (val) => setState(() => _wooSyncStock = val),
            ),
            _buildSwitchRow(
              key: const ValueKey('switch_woo_auto_pause'),
              title: 'Pausar compras al agotar stock',
              subtitle: 'Forzar "outofstock" y deshabilitar pedidos en espera (backorders: no)',
              value: _wooAutoPause,
              activeColor: brandColor,
              onChanged: (val) => setState(() => _wooAutoPause = val),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('btn_test_woo_connection'),
                  onPressed: _isTestingWoo ? null : _testWooConnection,
                  icon: _isTestingWoo
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.wifi_tethering, size: 18),
                  label: const Text('Probar Conexión'),
                  style: FilledButton.styleFrom(
                    backgroundColor: brandColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('btn_save_woo'),
                  onPressed: () => _saveWooIntegration(showFeedback: true),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Guardar WooCommerce'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: brandColor,
                    side: const BorderSide(color: brandColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTiendaNubeSection(bool isNarrow) {
    const brandColor = Color(0xFF2B358F);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.grey.shade50,
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          controller: _tnExpCtrl,
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: brandColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.cloud_outlined, color: brandColor, size: 22),
          ),
          title: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Tienda Nube',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              _buildChannelActiveBadge(_tiendanubeActive),
              _buildChannelHealthBadge(_tiendanubeHealthStatus),
            ],
          ),
          trailing: Switch(
            key: const ValueKey('switch_tiendanube_active'),
            value: _tiendanubeActive,
            activeThumbColor: brandColor,
            onChanged: _toggleTiendanubeActive,
          ),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('field_tiendanube_store_id'),
              controller: _tiendanubeStoreIdCtrl,
              decoration: InputDecoration(
                labelText: 'Store ID (store_id)',
                hintText: '1234567',
                prefixIcon: const Icon(Icons.numbers),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                helperText: 'Identificador numérico de la tienda asignado por Tienda Nube',
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const ValueKey('field_tiendanube_token'),
              controller: _tiendanubeAccessTokenCtrl,
              obscureText: _obscureTiendanubeToken,
              decoration: InputDecoration(
                labelText: 'Access Token',
                prefixIcon: const Icon(Icons.security),
                suffixIcon: IconButton(
                  icon: Icon(_obscureTiendanubeToken ? Icons.visibility : Icons.visibility_off),
                  tooltip: _obscureTiendanubeToken ? 'Mostrar token' : 'Ocultar token',
                  onPressed: () => _toggleSecretVisibility(
                    action: 'Revelar Token de Tienda Nube',
                    isCurrentlyObscured: _obscureTiendanubeToken,
                    onToggle: (v) => _obscureTiendanubeToken = v,
                  ),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                helperText: 'Token de acceso API provisto por Tienda Nube / Nuvemshop',
              ),
            ),
            const SizedBox(height: 14),
            _buildSwitchRow(
              key: const ValueKey('switch_tiendanube_sync_stock'),
              title: 'Sincronizar Stock',
              subtitle: 'Replicar automáticamente el stock de ventas físicas hacia Tienda Nube',
              value: _tiendanubeSyncStock,
              activeColor: brandColor,
              onChanged: (val) => setState(() => _tiendanubeSyncStock = val),
            ),
            _buildSwitchRow(
              key: const ValueKey('switch_tiendanube_auto_pause'),
              title: 'Pausar variantes al agotar stock',
              subtitle: 'Establecer cantidad cero en todas las variantes al agotarse en local',
              value: _tiendanubeAutoPause,
              activeColor: brandColor,
              onChanged: (val) => setState(() => _tiendanubeAutoPause = val),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('btn_test_tiendanube_connection'),
                  onPressed: _isTestingTiendanube ? null : _testTiendanubeConnection,
                  icon: _isTestingTiendanube
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.wifi_tethering, size: 18),
                  label: const Text('Probar Conexión'),
                  style: FilledButton.styleFrom(
                    backgroundColor: brandColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('btn_save_tiendanube'),
                  onPressed: () => _saveTiendanubeIntegration(showFeedback: true),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Guardar Tienda Nube'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: brandColor,
                    side: const BorderSide(color: brandColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEcommerceCard(bool isNarrow) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          controller: _ecommerceExpCtrl,
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          childrenPadding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
          trailing: Switch(
            value: _ecommerceEnabled,
            activeThumbColor: const Color(0xFF673AB7),
            onChanged: (val) {
              setState(() => _ecommerceEnabled = val);
              if (val) {
                _ecommerceExpCtrl.expand();
              } else {
                _ecommerceExpCtrl.collapse();
              }
            },
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF673AB7).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.shopping_cart_outlined,
                    color: Color(0xFF673AB7), size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isNarrow) ...[
                      const Text(
                        'E-Commerce y Omnicanalidad',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      _buildEcommerceStatusBadge(),
                    ] else ...[
                      Row(
                        children: [
                          Flexible(
                            child: const Text(
                              'E-Commerce y Omnicanalidad',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          _buildEcommerceStatusBadge(),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Sincronizá tu stock local con Mercado Libre, WooCommerce y Tienda Nube.',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('btn_view_ecommerce_logs'),
                    onPressed: () => EcommerceSyncLogsDialog.show(context),
                    icon: const Icon(Icons.history_outlined, size: 18),
                    label: const Text('Bitácora de Sincronización'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF673AB7),
                      side: const BorderSide(color: Color(0xFF673AB7)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
            _buildMercadoLibreSection(isNarrow),
            _buildWooCommerceSection(isNarrow),
            _buildTiendaNubeSection(isNarrow),
          ],
        ),
      ),
    );
  }

  Widget _buildMercadoPagoCard(bool isNarrow) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          controller: _mpExpCtrl,
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          childrenPadding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
          trailing: Switch(
            value: _mpQrEnabled,
            activeThumbColor: const Color(0xFF009EE3),
            onChanged: (val) {
              setState(() => _mpQrEnabled = val);
              if (val) {
                _mpExpCtrl.expand();
              } else {
                _mpExpCtrl.collapse();
              }
            },
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF009EE3).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.qr_code_2,
                    color: Color(0xFF009EE3), size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isNarrow) ...[
                      const Text(
                        'Mercado Pago',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      _buildMpStatusBadge(),
                    ] else ...[
                      Row(
                        children: [
                          Flexible(
                            child: const Text(
                              'Mercado Pago',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          _buildMpStatusBadge(),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Cobro con QR In-Store y terminales físicas Point',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 16),


            // Access Token
            TextFormField(
              key: const ValueKey('field_mp_access_token'),
              controller: _mpAccessTokenCtrl,
              obscureText: _obscureMpToken,
              decoration: _inputDecoration(
                'Access Token',
                Icons.vpn_key_outlined,
                hint: 'APP_USR-...',
              ).copyWith(
                helperText:
                    'Credencial de Mercado Pago. Si no se modifica, se preserva el secreto guardado.',
                helperMaxLines: 2,
                suffixIcon: IconButton(
                  icon: Icon(_obscureMpToken
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  tooltip:
                      _obscureMpToken ? 'Mostrar token' : 'Ocultar token',
                  onPressed: () => _toggleSecretVisibility(
                    action: 'Revelar Token de Mercado Pago',
                    isCurrentlyObscured: _obscureMpToken,
                    onToggle: (v) => _obscureMpToken = v,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Webhook Secret
            TextFormField(
              key: const ValueKey('field_mp_webhook_secret'),
              controller: _mpWebhookSecretCtrl,
              obscureText: _obscureMpSecret,
              decoration: _inputDecoration(
                'Webhook Secret',
                Icons.lock_outline,
                hint: 'whsec_...',
              ).copyWith(
                helperText:
                    'Clave de firma para validar notificaciones automáticas de pago.',
                helperMaxLines: 2,
                suffixIcon: IconButton(
                  icon: Icon(_obscureMpSecret
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  tooltip:
                      _obscureMpSecret ? 'Mostrar secret' : 'Ocultar secret',
                  onPressed: () => _toggleSecretVisibility(
                    action: 'Revelar Webhook Secret de Mercado Pago',
                    isCurrentlyObscured: _obscureMpSecret,
                    onToggle: (v) => _obscureMpSecret = v,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Device ID Posnet
            TextFormField(
              key: const ValueKey('field_mp_point_device_id'),
              controller: _mpPointDeviceIdCtrl,
              decoration: _inputDecoration(
                'Device ID Posnet (Point)',
                Icons.point_of_sale_outlined,
                hint: 'Ej: POINT_SMART_01',
              ).copyWith(
                helperText:
                    'Identificador del dispositivo Point asociado a esta caja (opcional).',
              ),
            ),
            const SizedBox(height: 20),

            // Webhook URL (solo lectura con botón copiar)
            TextFormField(
              key: const ValueKey('field_mp_webhook_url'),
              controller: _mpWebhookUrlCtrl,
              readOnly: true,
              decoration: _inputDecoration(
                'URL Webhook (Solo lectura)',
                Icons.link_outlined,
                hint: 'https://...',
              ).copyWith(
                helperText:
                    'Copia esta URL en tu panel de desarrolladores de Mercado Pago.',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.copy_outlined, size: 20),
                  tooltip: 'Copiar URL al portapapeles',
                  onPressed: () {
                    final text = _mpWebhookUrlCtrl.text.trim();
                    if (text.isNotEmpty) {
                      Clipboard.setData(ClipboardData(text: text));
                      SnackBarService.info(
                          context, 'URL de webhook copiada al portapapeles');
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Botón Probar conexión
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('btn_test_mp_connection'),
                  onPressed: (_isTestingMpConnection || _isSavingIntegrations)
                      ? null
                      : _testMercadoPagoConnection,
                  icon: _isTestingMpConnection
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering, size: 18),
                  label: const Text('Probar conexión'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                Text(
                  'Verifica que el Access Token sea ví¡lido contra la API oficial',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAfipCard(bool isNarrow) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          controller: _afipExpCtrl,
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          childrenPadding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
          trailing: Switch(
            value: _afipEnabled,
            activeThumbColor: const Color(0xFF2E7D32),
            onChanged: (val) {
              setState(() => _afipEnabled = val);
              if (val) {
                _afipExpCtrl.expand();
              } else {
                _afipExpCtrl.collapse();
              }
            },
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.receipt_long,
                    color: Color(0xFF2E7D32), size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isNarrow) ...[
                      const Text(
                        'ARCA / AFIP (Facturación Electrónica)',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      _buildAfipStatusBadge(),
                    ] else ...[
                      Row(
                        children: [
                          Flexible(
                            child: const Text(
                              'ARCA / AFIP (Facturación Electrónica)',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          _buildAfipStatusBadge(),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Emisión de Facturas y Comprobantes Fiscales Oficiales (WebService WSFEv1)',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 16),


            // CUIT y Punto de Venta (responsive: column si es estrecho)
            if (isNarrow) ...[
              TextFormField(
                key: const ValueKey('field_afip_cuit'),
                controller: _afipCuitCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 11,
                decoration: _inputDecoration(
                  'CUIT Comercial',
                  Icons.badge_outlined,
                  hint: 'Ej: 20123456789',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('field_afip_pto_vta'),
                controller: _afipPtoVtaCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 5,
                decoration: _inputDecoration(
                  'Punto de Venta',
                  Icons.store_outlined,
                  hint: 'Ej: 1',
                ),
              ),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      key: const ValueKey('field_afip_cuit'),
                      controller: _afipCuitCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 11,
                      decoration: _inputDecoration(
                        'CUIT Comercial',
                        Icons.badge_outlined,
                        hint: 'Ej: 20123456789',
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      key: const ValueKey('field_afip_pto_vta'),
                      controller: _afipPtoVtaCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 5,
                      decoration: _inputDecoration(
                        'Punto de Venta',
                        Icons.store_outlined,
                        hint: 'Ej: 1',
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),

            // Selector de Entorno (Testing / Producción)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Entorno de Facturación',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: const ValueKey('dropdown_afip_environment'),
                  isExpanded: true,
                  initialValue: _afipEnvironment,
                  decoration: _inputDecoration(
                    'Entorno',
                    Icons.cloud_outlined,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'testing',
                      child: Text(
                        'Testing (Homologación ARCA)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'production',
                      child: Text(
                        'Producción (Servidores Reales)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _afipEnvironment = val);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Indicadores visuales de estado de certificado y llave
            Text(
              'Estado de Certificados en Servidor',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                _buildStatusChip(
                  keyName: 'chip_afip_cert',
                  label: _afipHasCert
                      ? 'Certificado (.crt) Instalado'
                      : 'Certificado (.crt) No Instalado',
                  isOk: _afipHasCert,
                  icon: _afipHasCert
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_rounded,
                  subtitle: _afipCertExpiresAt != null
                      ? 'Vence: $_afipCertExpiresAt'
                      : null,
                ),
                _buildStatusChip(
                  keyName: 'chip_afip_key',
                  label: _afipHasKey
                      ? 'Clave Privada (.key) Instalada'
                      : 'Clave Privada (.key) No Instalada',
                  isOk: _afipHasKey,
                  icon: _afipHasKey
                      ? Icons.key_outlined
                      : Icons.key_off_outlined,
                ),
              ],
            ),
            const Divider(height: 32),

            // Sección de Carga y Actualización de Certificados
            Text(
              'Carga de Certificados Digitales (X.509)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Seleccione el certificado emitido por AFIP (.crt) y la clave privada generada (.key).',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),

            // Selectores de archivo
            if (isNarrow) ...[
              _buildFilePickerTile(
                title: 'Certificado AFIP (.crt)',
                selectedFileName: _selectedCertName,
                buttonKey: const ValueKey('btn_pick_afip_cert'),
                onPick: _pickAfipCert,
                onClear: _selectedCertName != null
                    ? () => setState(() {
                          _selectedCertBytes = null;
                          _selectedCertName = null;
                        })
                    : null,
                icon: Icons.verified_user_outlined,
              ),
              const SizedBox(height: 12),
              _buildFilePickerTile(
                title: 'Clave Privada (.key)',
                selectedFileName: _selectedKeyName,
                buttonKey: const ValueKey('btn_pick_afip_key'),
                onPick: _pickAfipKey,
                onClear: _selectedKeyName != null
                    ? () => setState(() {
                          _selectedKeyBytes = null;
                          _selectedKeyName = null;
                        })
                    : null,
                icon: Icons.vpn_key_outlined,
              ),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildFilePickerTile(
                      title: 'Certificado AFIP (.crt)',
                      selectedFileName: _selectedCertName,
                      buttonKey: const ValueKey('btn_pick_afip_cert'),
                      onPick: _pickAfipCert,
                      onClear: _selectedCertName != null
                          ? () => setState(() {
                                _selectedCertBytes = null;
                                _selectedCertName = null;
                              })
                          : null,
                      icon: Icons.verified_user_outlined,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildFilePickerTile(
                      title: 'Clave Privada (.key)',
                      selectedFileName: _selectedKeyName,
                      buttonKey: const ValueKey('btn_pick_afip_key'),
                      onPick: _pickAfipKey,
                      onClear: _selectedKeyName != null
                          ? () => setState(() {
                                _selectedKeyBytes = null;
                                _selectedKeyName = null;
                              })
                          : null,
                      icon: Icons.vpn_key_outlined,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),

            // Campo de contraseña de clave privada (opcional)
            TextFormField(
              key: const ValueKey('field_afip_key_passphrase'),
              controller: _afipKeyPassphraseCtrl,
              obscureText: _obscureAfipPassphrase,
              decoration: _inputDecoration(
                'Contraseña de Clave Privada (Opcional)',
                Icons.lock_outline,
                hint: 'Dejar vacío si la clave no tiene contraseña',
              ).copyWith(
                helperText:
                    'Solo requerida si la clave privada (.key) fue cifrada con contraseña.',
                suffixIcon: IconButton(
                  icon: Icon(_obscureAfipPassphrase
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  tooltip: _obscureAfipPassphrase
                      ? 'Mostrar contraseña'
                      : 'Ocultar contraseña',
                  onPressed: () => _toggleSecretVisibility(
                    action: 'Revelar Clave de Certificado AFIP',
                    isCurrentlyObscured: _obscureAfipPassphrase,
                    onToggle: (v) => _obscureAfipPassphrase = v,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Botón de subida
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  key: const ValueKey('btn_upload_afip_certs'),
                  onPressed: (_isUploadingCertificates || _isSavingIntegrations)
                      ? null
                      : _uploadAfipCertificates,
                  icon: _isUploadingCertificates
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.cloud_upload_outlined, size: 18),
                  label: Text(_isUploadingCertificates
                      ? 'Subiendo certificados...'
                      : 'Subir Certificados a ARCA'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                Text(
                  'Valida criptogrí¡ficamente el par y lo almacena de forma segura en el servidor.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilePickerTile({
    required String title,
    required String? selectedFileName,
    required Key buttonKey,
    required VoidCallback onPick,
    VoidCallback? onClear,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF2E7D32)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: buttonKey,
            onPressed: onPick,
            icon: const Icon(Icons.folder_open, size: 16),
            label: const Text('Seleccionar'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  selectedFileName ?? 'Sin archivo seleccionado',
                  style: TextStyle(
                    fontSize: 12,
                    color: selectedFileName != null
                        ? Colors.black87
                        : Colors.grey.shade600,
                    fontWeight: selectedFileName != null
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onClear != null)
                Tooltip(
                  message: 'Quitar archivo',
                  child: InkWell(
                    onTap: onClear,
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 16, color: Colors.grey),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip({
    required String keyName,
    required String label,
    required bool isOk,
    required IconData icon,
    String? subtitle,
  }) {
    final color = isOk ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F);
    final bgColor = isOk ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE);

    return Container(
      key: ValueKey(keyName),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                        color: color.withValues(alpha: 0.8), fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralSection(SettingsProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Datos del Negocio',
            'Configurá los datos que aparecerán en tus tickets y facturas.'),
        const SizedBox(height: 32),
        _buildLogoPicker(provider),
        const SizedBox(height: 32),
        _buildTextField('Nombre del Comercio', _companyNameCtrl,
            icon: Icons.badge_outlined),
        const SizedBox(height: 24),
        _buildTextField('Dirección / Sucursal', _addressCtrl,
            icon: Icons.location_on_outlined),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
                child: _buildTextField('Telí©fono', _phoneCtrl,
                    icon: Icons.phone_outlined)),
            const SizedBox(width: 24),
            Expanded(
                child: _buildTextField('CUIT / Tax ID', _taxIdCtrl,
                    icon: Icons.receipt_long_outlined)),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Condición frente al IVA', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedTaxCondition,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.account_balance_outlined, color: Colors.black54),
                      filled: true,
                      fillColor: const Color(0xFFF8F9FA),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'IVA Responsable Inscripto', child: Text('IVA Responsable Inscripto')),
                      DropdownMenuItem(value: 'Responsable Monotributo', child: Text('Responsable Monotributo')),
                      DropdownMenuItem(value: 'IVA Exento', child: Text('IVA Exento')),
                      DropdownMenuItem(value: 'Consumidor Final', child: Text('Consumidor Final')),
                    ],
                    onChanged: (val) {
                      setState(() { _selectedTaxCondition = val; });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
                child: _buildTextField('Nro. Ingresos Brutos (IIBB)', _iibbCtrl,
                    icon: Icons.assignment_outlined)),
          ],
        ),
        const SizedBox(height: 24),
        _buildTextField('Fecha de Inicio de Actividades (ej: 01/01/2020)', _activityStartDateCtrl,
            icon: Icons.calendar_today_outlined),
        const SizedBox(height: 24),
        _buildTextField('Mensaje Pie de Ticket', _footerCtrl,
            icon: Icons.message_outlined, maxLines: 3),
        const SizedBox(height: 32),
        Container(
          decoration: BoxDecoration(
            color: _isIibbPerceptionAgent
                ? const Color(0xFF2E7D32).withValues(alpha: 0.05)
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isIibbPerceptionAgent
                  ? const Color(0xFF2E7D32).withValues(alpha: 0.4)
                  : Colors.grey.shade200,
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Material(
                  color: Colors.transparent,
                  child: SwitchListTile(
                    key: const ValueKey('switch_iibb_perception_agent'),
                    contentPadding: EdgeInsets.zero,
                    secondary: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.account_balance, color: Color(0xFF2E7D32)),
                    ),
                    title: const Text(
                      'Agente de Percepción Ingresos Brutos (IIBB)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    subtitle: const Text(
                      'Habilita el cálculo automático de percepciones de Ingresos Brutos en las facturas A y B.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: _isIibbPerceptionAgent,
                    activeThumbColor: const Color(0xFF2E7D32),
                    onChanged: (val) => setState(() => _isIibbPerceptionAgent = val),
                  ),
                ),
                if (_isIibbPerceptionAgent) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('field_default_iibb_rate'),
                    controller: _defaultIibbRateCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*[\.,]?\d{0,2}')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Alcuota por defecto IIBB (%)',
                      hintText: 'Ej: 3.0',
                      prefixIcon: const Icon(Icons.percent, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    validator: (val) {
                      if (!_isIibbPerceptionAgent) return null;
                      if (val == null || val.trim().isEmpty) return null;
                      final parsed = double.tryParse(val.trim().replaceAll(',', '.'));
                      if (parsed == null || parsed < 0 || parsed > 100) {
                        return 'Ingrese una alícuota válida (0 - 100%)';
                      }
                      return null;
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildLogoPicker(SettingsProvider provider) {
    final currentLogoUrl = provider.settings?.effectiveLogoUrl;
    final currentLogoUri = currentLogoUrl != null ? Uri.tryParse(currentLogoUrl) : null;
    final hasValidCurrentLogo = currentLogoUri != null &&
        currentLogoUri.hasScheme &&
        currentLogoUri.hasAuthority &&
        currentLogoUri.host.isNotEmpty;
    final hasSelectedImage = _selectedLogoBytes != null || (_selectedLogoPath != null && _selectedLogoPath!.isNotEmpty);
    final hasAnyLogo = hasSelectedImage || hasValidCurrentLogo;

    Widget imageContent;
    if (_isUploadingLogo) {
      imageContent = const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    } else if (_selectedLogoBytes != null) {
      imageContent = Image.memory(
        _selectedLogoBytes!,
        width: 130,
        height: 130,
        fit: BoxFit.contain,
      );
    } else if (_selectedLogoPath != null && _selectedLogoPath!.isNotEmpty) {
      imageContent = Image.file(
        File(_selectedLogoPath!),
        width: 130,
        height: 130,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40, color: Colors.grey),
      );
    } else if (hasValidCurrentLogo) {
      imageContent = Image.network(
        currentLogoUrl!,
        width: 130,
        height: 130,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40, color: Colors.grey),
      );
    } else {
      imageContent = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate_outlined, size: 40, color: Colors.grey.shade500),
          const SizedBox(height: 8),
          Text(
            'Subir Logo',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 2),
          Text(
            '130x130',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Logotipo del Negocio',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
        ),
        const SizedBox(height: 4),
        Text(
          'Aparecerá en el encabezado del POS y en los comprobantes impresos (PNG, JPG o WEBP).',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            InkWell(
              onTap: _isUploadingLogo ? null : _pickLogo,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                key: const ValueKey('settings_logo_container'),
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hasSelectedImage ? const Color(0xFF673AB7) : Colors.grey.shade300,
                    width: hasSelectedImage ? 2 : 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Center(child: imageContent),
              ),
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OutlinedButton.icon(
                  onPressed: _isUploadingLogo ? null : _pickLogo,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: Text(hasAnyLogo ? 'Cambiar Logo' : 'Seleccionar Logo'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                if (hasSelectedImage) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _isUploadingLogo
                        ? null
                        : () {
                            setState(() {
                              _selectedLogoPath = null;
                              _selectedLogoBytes = null;
                              _selectedLogoName = null;
                            });
                          },
                    icon: const Icon(Icons.close, size: 18, color: Colors.red),
                    label: const Text('Descartar selección', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPricesSection(SettingsProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Precios y Factores',
            'Configurá los porcentajes matemí¡ticos para las listas de precios globales.'),
        const SizedBox(height: 32),

        // ━━━━━━━━ Feature Toggle Multi-Tenant ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        Builder(builder: (context) {
          final hasMultiPrices =
              provider.settings?.features.multiplePrices == true;
          final isLocked = !hasMultiPrices;

          return Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: isLocked
                      ? Colors.grey.shade50
                      : _advancedPriceTiersEnabled
                          ? const Color(0xFF1A237E).withValues(alpha: 0.06)
                          : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isLocked
                        ? Colors.grey.shade200
                        : _advancedPriceTiersEnabled
                            ? const Color(0xFF3F51B5).withValues(alpha: 0.4)
                            : Colors.grey.shade200,
                    width: 1.5,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  child: SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  secondary: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isLocked
                              ? Colors.grey.shade100
                              : _advancedPriceTiersEnabled
                                  ? const Color(0xFF3F51B5)
                                      .withValues(alpha: 0.12)
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
                            child: const Icon(Icons.workspace_premium,
                                size: 10, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                  title: Text(
                    isLocked
                        ? 'Multi-Listas de Precios (Plan Avanzado)'
                        : _advancedPriceTiersEnabled
                            ? 'Modo Avanzado (Multi-Listas Activo)'
                            : 'Modo Bí¡sico (Retail / Minorista)',
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
                          ? 'Activí¡ el Plan Avanzado para habilitar el selector de Listas de Precios (Mayorista / Tarjeta) en el POS.'
                          : _advancedPriceTiersEnabled
                              ? 'El POS muestra el selector de Listas (Mayorista / Tarjeta / Custom). Los recargos del mí©todo de pago se desactivan automí¡ticamente para evitar doble cobro.'
                              : 'El POS opera con precio íºnico. Los recargos configurados en cada Mí©todo de Pago se aplican normalmente al momento del cobro.',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          height: 1.4),
                    ),
                  ),
                  value: _advancedPriceTiersEnabled,
                  // Switch visualmente desactivado si el plan no incluye el feature
                  activeThumbColor:
                      isLocked ? Colors.grey.shade400 : const Color(0xFF3F51B5),
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
                        onNavigateToSettings: () => setState(() =>
                            _activeSection = SettingsSection.subscription),
                      );
                      return; // Bloquea el setState
                    }
                    setState(() => _advancedPriceTiersEnabled = val);
                  },
                ),
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                      child: _buildTextField(
                          'Recargo por Tarjeta (%)', _cardPercentageCtrl,
                          icon: Icons.credit_card,
                          hint: 'Ej: 15.0',
                          enabled: !isLocked && _advancedPriceTiersEnabled)),
                  const SizedBox(width: 24),
                  Expanded(
                      child: _buildTextField(
                          'Descuento Mayorista (%)', _wholesalePercentageCtrl,
                          icon: Icons.factory_outlined,
                          hint: 'Ej: -15.0',
                          enabled: !isLocked && _advancedPriceTiersEnabled)),
                ],
              ),
            ],
          );
        }),
        // ── Percepciones IIBB (Módulo Mayorista) ───────────────────────
        Container(
          margin: const EdgeInsets.only(top: 24),
          decoration: BoxDecoration(
            color: _isIibbPerceptionAgent
                ? const Color(0xFF2E7D32).withValues(alpha: 0.05)
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isIibbPerceptionAgent
                  ? const Color(0xFF2E7D32).withValues(alpha: 0.4)
                  : Colors.grey.shade200,
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Material(
                  color: Colors.transparent,
                  child: SwitchListTile(
                    key: const ValueKey('switch_iibb_perception_agent'),
                    contentPadding: EdgeInsets.zero,
                    secondary: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.account_balance, color: Color(0xFF2E7D32)),
                    ),
                    title: const Text(
                      'Agente de Percepción IIBB (Módulo Mayorista)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    subtitle: const Text(
                      'Habilita la aplicación de percepciones de Ingresos Brutos a clientes alcanzados en ventas.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: _isIibbPerceptionAgent,
                    activeThumbColor: const Color(0xFF2E7D32),
                    onChanged: (val) => setState(() => _isIibbPerceptionAgent = val),
                  ),
                ),
                if (_isIibbPerceptionAgent) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('field_default_iibb_rate'),
                    controller: _defaultIibbRateCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*[\.,]?\d{0,2}')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Alícuota por defecto IIBB (%)',
                      hintText: 'Ej: 3.0',
                      prefixIcon: const Icon(Icons.percent, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    validator: (val) {
                      if (!_isIibbPerceptionAgent) return null;
                      if (val == null || val.trim().isEmpty) return null;
                      final parsed = double.tryParse(val.trim().replaceAll(',', '.'));
                      if (parsed == null || parsed < 0 || parsed > 100) {
                        return 'Ingrese una alícuota válida (0 - 100%)';
                      }
                      return null;
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
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
            _buildSectionHeader('Listas de Precios Especiales',
                'Creí¡ modificadores diní¡micos para clientes (Ej: "Gremio" con -10%).'),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 3,
                  child: _buildTextField('Nombre de la Lista', _tierNameCtrl,
                      hint: 'Ej: Gremio', icon: Icons.label_outline),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: _buildTextField('Modificador (%)', _tierModCtrl,
                      hint: 'Ej: -10', icon: Icons.percent),
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
                        SnackBarService.warning(context,
                            'Ingresá un nombre y un porcentaje ví¡lido numí©rico.');
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
              const Text('No hay listas de precios activas.',
                  style: TextStyle(
                      color: Colors.grey, fontStyle: FontStyle.italic))
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _customTiers.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final tier = entry.value;
                  final name = tier['name']?.toString() ?? '';
                  final modVal = tier['modifier'] ?? tier['percentage'] ?? 0.0;
                  final mod = (modVal is num)
                      ? modVal.toDouble()
                      : (double.tryParse(modVal.toString()) ?? 0.0);
                  final sign = mod >= 0 ? '+' : '';
                  return GestureDetector(
                    onTap: () async {
                      final editNameCtrl = TextEditingController(text: name);
                      final editModCtrl =
                          TextEditingController(text: mod.toString());
                      try {
                        await showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Editar Lista de Precios'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextField(
                                  controller: editNameCtrl,
                                  decoration: const InputDecoration(
                                      labelText: 'Nombre de la Lista',
                                      border: OutlineInputBorder()),
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: editModCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          signed: true, decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'Modificador (%)',
                                      border: OutlineInputBorder()),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Cancelar')),
                              FilledButton(
                                onPressed: () {
                                  final newName = editNameCtrl.text.trim();
                                  final newMod = double.tryParse(editModCtrl.text
                                      .replaceAll(',', '.')
                                      .trim());
                                  if (newName.isNotEmpty && newMod != null) {
                                    setState(() {
                                      _customTiers[idx] = {
                                        'name': newName,
                                        'modifier': newMod
                                      };
                                    });
                                    Navigator.pop(ctx);
                                  }
                                },
                                child: const Text('Guardar'),
                              ),
                            ],
                          ),
                        );
                      } finally {
                        editNameCtrl.dispose();
                        editModCtrl.dispose();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        border: Border.all(color: Colors.purple.shade200),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.sell_outlined,
                              size: 16, color: Colors.purple),
                          const SizedBox(width: 8),
                          Text(
                            '$name ($sign${mod.toStringAsFixed(0)}%)',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.purple.shade900),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () =>
                                setState(() => _customTiers.removeAt(idx)),
                            child: const Icon(Icons.cancel,
                                size: 18, color: Colors.redAccent),
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



  Widget _buildSubscriptionSection(SettingsProvider provider) {
    final settings = provider.settings;
    final isLifetime = settings?.isLifetime ?? false;
    final expiresAt = settings?.licenseExpiresAt;
    final manageUrl = settings?.licenseManageUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Suscripción y Licencia',
            'Gestioná tus cajas registradoras físicas y sus permisos desde aquí.'),
        const SizedBox(height: 32),
        if (provider.isLicenseActive) ...[
          AnimatedSubscriptionCard(
            isPremium: provider.currentPlan.toLowerCase() == 'premium' ||
                provider.currentPlan.toLowerCase() == 'pro',
            isLifetime: isLifetime,
            licenseKey: settings?.licenseStatus,
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
                ? [
                    const Text('No hay addons específicos activos.',
                        style: TextStyle(color: Colors.grey))
                  ]
                : provider.allowedAddons
                    .map((addon) => Chip(
                          label: Text(
                            _translateFeature(addon),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF424242)),
                          ),
                          backgroundColor: Colors.white,
                          side: BorderSide(color: Colors.grey.shade300),
                        ))
                    .toList(),
          ),
          const SizedBox(height: 32),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 500;
              final syncBtn = OutlinedButton.icon(
                onPressed: _isSyncingLicense ? null : _syncLicense,
                icon: _isSyncingLicense
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync),
                label: const Text('FORZAR SINCRONIZACIÓN'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 16),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
              );

              final updateBtn = FilledButton.icon(
                onPressed: _isCheckingUpdate ? null : _checkForUpdate,
                icon: _isCheckingUpdate
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.system_update_alt),
                label: const Text('BUSCAR ACTUALIZACIONES'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 16),
                  backgroundColor: const Color(0xFF3F51B5),
                ),
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    syncBtn,
                    const SizedBox(height: 12),
                    updateBtn,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: syncBtn),
                  const SizedBox(width: 16),
                  Expanded(child: updateBtn),
                ],
              );
            },
          ),
          if (_appVersion.isNotEmpty) ...[
            const SizedBox(height: 16),
            Center(
              child: GestureDetector(
                onTap: _handleVersionTap,
                child: Text(
                  'Versión actual del sistema: v$_appVersion${_currentChannel == 'beta' ? ' (BETA)' : ''}',
                  style: TextStyle(
                      color: _currentChannel == 'beta'
                          ? Colors.orange.shade600
                          : Colors.grey.shade500,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ] else ...[
          // --- ESTADO SIN LICENCIA ---
          _buildTextField('Clave de Licencia', _licenseKeyCtrl,
              icon: Icons.vpn_key_outlined, hint: 'XXXX-XXXX-XXXX-XXXX'),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isActivatingLicense ? null : _activateLicense,
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF673AB7),
                  foregroundColor: Colors.white),
              child: _isActivatingLicense
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('ACTIVAR AHORA'),
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
        _buildSectionHeader('Red y Terminales',
            'Configurá la conexión con el servidor y las rutas de instalación.'),
        const SizedBox(height: 32),

        // Campo de URL del Servidor (Integrado en el flujo de guardado principal)
        _buildTextField('Dirección URL del Servidor (API)', _serverUrlCtrl,
            icon: Icons.dns_outlined,
            hint: 'Ej: http://127.0.0.1/Sistema_POS/pos-backend/public/api'),

        const SizedBox(height: 24),

        // NUEVO CAMPO: Ruta del Backend
        _buildTextField(
          'Ruta Local del Backend (Servidor)',
          _backendPathCtrl,
          icon: Icons.folder_open_outlined,
          hint: 'Ej: C:\\laragon\\www\\Sistema_POS\\pos-backend',
          maxLines: 1,
        ),
        const Padding(
          padding: EdgeInsets.only(left: 12, top: 8),
          child: Text(
            '⚠️  Esta ruta es necesaria para que las actualizaciones automáticas puedan reemplazar los archivos del servidor local.',
            style: TextStyle(
                fontSize: 12,
                color: Colors.orange,
                fontWeight: FontWeight.w500),
          ),
        ),

        const SizedBox(height: 48),
        const Divider(),
        const SizedBox(height: 24),

        _buildSectionTitle('Terminal y Cajas'),
        const SizedBox(height: 16),

        ListTile(
          contentPadding: const EdgeInsets.all(20),
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200)),
          leading: const CircleAvatar(
              backgroundColor: Color(0xFFFBE9E7),
              child: Icon(Icons.desktop_windows, color: Color(0xFFD84315))),
          title: const Text('Asignación de Terminal',
              style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(
              'Esta PC estí¡ configurada como: Caja ID ${provider.assignedRegisterId}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showTerminalAssignmentDialog(context, provider),
        ),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: const EdgeInsets.all(20),
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200)),
          leading: const CircleAvatar(
              backgroundColor: Color(0xFFFFF3E0),
              child:
                  Icon(Icons.settings_suggest_outlined, color: Colors.orange)),
          title: const Text('Administración de Cajas',
              style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text(
              'Configurá los nombres y permisos de cada terminal fí­sica.'),
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
                    'La administración de míºltiples terminales fí­sicas es '
                    'una función exclusiva del plan PREMIUM.',
                onNavigateToSettings: () => setState(
                    () => _activeSection = SettingsSection.subscription),
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
        Text(title,
            style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFF212121))),
        const SizedBox(height: 8),
        Text(subtitle,
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title,
        style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF424242)));
  }

  Widget _buildTextField(String label, TextEditingController controller,
      {IconData? icon, String? hint, int maxLines = 1, bool enabled = true}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      enabled: enabled,
      decoration: _inputDecoration(label, icon, hint: hint, enabled: enabled),
    );
  }

  InputDecoration _inputDecoration(String label, IconData? icon,
      {String? hint, bool enabled = true}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null
          ? Icon(icon, size: 20, color: enabled ? null : Colors.grey)
          : null,
      filled: true,
      fillColor: enabled ? Colors.white : Colors.grey.shade50,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200)),
      disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade100)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      labelStyle: enabled ? null : TextStyle(color: Colors.grey.shade500),
      hintStyle: enabled ? null : TextStyle(color: Colors.grey.shade400),
    );
  }

  // Los modales se mantienen funcionalmente igual pero podrí­an estilizarse mí¡s.
  // Re-implementando los esenciales para que el archivo compile.

  Future<void> _showTerminalAssignmentDialog(
      BuildContext context, SettingsProvider settingsProvider) async {
    final cashProvider = context.read<CashRegisterProvider>();
    if (cashProvider.availableRegisters == null ||
        cashProvider.availableRegisters!.isEmpty) {
      await cashProvider.loadRegisters();
    }
    if (!context.mounted) return;
    final registers = cashProvider.availableRegisters ?? [];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Asignar Terminal'),
        content: DropdownButtonFormField<int>(
          initialValue:
              registers.any((r) => r.id == settingsProvider.assignedRegisterId)
                  ? settingsProvider.assignedRegisterId
                  : registers.firstOrNull?.id,
          items: registers
              .map((r) => DropdownMenuItem(value: r.id, child: Text(r.name)))
              .toList(),
          onChanged: (id) async {
            if (id != null) {
              await settingsProvider.setAssignedRegisterId(id);
              if (ctx.mounted) Navigator.pop(ctx);

              // Forzar recarga del turno con la nueva caja asignada.
              // Esto actualizarí¡ globalmente el CashRegisterProvider y el Consumer en /home
              // echarí¡ al usuario a la pantalla de "Abrir Caja" si la nueva terminal estí¡ cerrada.
              await cashProvider.checkCurrentShift(registerId: id);

              // Limpiar carrito para que no quede huí©rfano de la terminal anterior
              if (AppConfig.navigatorKey.currentContext != null) {
                AppConfig.navigatorKey.currentContext!
                    .read<PosProvider>()
                    .clearCart();
              }

              // Redirigir a /home para que reevalíºe el estado y muestre la apertura de caja si es necesario
              AppConfig.navigatorKey.currentState
                  ?.pushNamedAndRemoveUntil('/home', (route) => false);
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
  final String? licenseKey;
  final DateTime? expiresAt;
  final String? lastSync;
  final String? manageUrl;

  const AnimatedSubscriptionCard({
    super.key,
    required this.isPremium,
    required this.isLifetime,
    this.licenseKey,
    this.expiresAt,
    this.lastSync,
    this.manageUrl,
  });

  @override
  State<AnimatedSubscriptionCard> createState() =>
      _AnimatedSubscriptionCardState();
}

class _AnimatedSubscriptionCardState extends State<AnimatedSubscriptionCard>
    with SingleTickerProviderStateMixin {
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
    final title = widget.isPremium ? 'PLAN PREMIUM' : 'PLAN BíSICO';

    final gradientColors = widget.isPremium
        ? [
            const Color(0xFF7C3AED),
            const Color(0xFF3B82F6),
            const Color(0xFF9333EA)
          ] // Vibrant purple -> blue -> violet
        : [
            const Color(0xFF1E293B),
            const Color(0xFF334155),
            const Color(0xFF0F172A)
          ]; // Sleek dark slate

    final shadowColor =
        widget.isPremium ? const Color(0xFF7C3AED) : const Color(0xFF000000);

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
                    color: shadowColor.withValues(
                        alpha: 0.3 * _glowAnimation.value),
                    blurRadius: 30 * _glowAnimation.value,
                    offset: const Offset(0, 15),
                  ),
                ],
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: widget.isPremium
                                ? Colors.amber.shade400.withValues(alpha: 0.9)
                                : Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: widget.isPremium
                                ? [
                                    BoxShadow(
                                        color:
                                            Colors.amber.withValues(alpha: 0.5),
                                        blurRadius: 10)
                                  ]
                                : [],
                          ),
                          child: Text(
                            title,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.isPremium
                                  ? Colors.black87
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        widget.isPremium
                            ? Icons.workspace_premium
                            : Icons.verified_user,
                        color: widget.isPremium
                            ? Colors.amber.shade300
                            : Colors.blue.shade300,
                        size: 36,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.isLifetime
                        ? 'Acceso Vitalicio (LifeTime)'
                        : 'Suscripción Activa',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.isLifetime
                        ? 'Disfrutí¡s de todas las funciones Premium sin lí­mites de tiempo.'
                        : (widget.expiresAt != null
                            ? 'Expira el: ${DateFormat('dd MMMM, yyyy').format(widget.expiresAt!)}'
                            : (widget.lastSync != null
                                ? 'Sincronizado el: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(widget.lastSync!).toLocal())}'
                                : 'Estado: Activo y Protegido')),
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 16),
                  ),
                  if (widget.licenseKey != null && widget.licenseKey!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.key, color: Colors.white.withValues(alpha: 0.7), size: 18),
                          const SizedBox(width: 8),
                          Text(
                            widget.licenseKey!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 16),
                          InkWell(
                            onTap: () async {
                              await Clipboard.setData(ClipboardData(text: widget.licenseKey!));
                              if (context.mounted) {
                                SnackBarService.success(context, 'Licencia copiada al portapapeles');
                              }
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Icon(Icons.copy, color: Colors.white.withValues(alpha: 0.9), size: 18),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 36),
                  if (!widget.isLifetime && widget.manageUrl != null)
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              launchUrl(Uri.parse(widget.manageUrl!)),
                          icon: Icon(Icons.manage_accounts,
                              color: widget.isPremium
                                  ? const Color(0xFF7C3AED)
                                  : Colors.white,
                              size: 20),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.isPremium
                                ? Colors.white
                                : Colors.blue.shade600,
                            foregroundColor: widget.isPremium
                                ? const Color(0xFF7C3AED)
                                : Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 28, vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            elevation: 8,
                          ),
                          label: const Text('GESTIONAR SUSCRIPCIÓN',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14)),
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

