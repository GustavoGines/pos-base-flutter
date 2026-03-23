import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../../../../core/utils/snack_bar_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String _pin = '';
  String? _errorDetail;
  static const int _pinLength = 4;

  void _onKeypadTap(String value) {
    if (value == 'clr') {
      setState(() => _pin = '');
    } else if (value == 'del') {
      if (_pin.isNotEmpty) {
        setState(() => _pin = _pin.substring(0, _pin.length - 1));
      }
    } else {
      if (_pin.length < _pinLength) {
        setState(() => _pin += value);
        if (_pin.length == _pinLength) {
          _submitPin();
        }
      }
    }
  }

  Future<void> _submitPin() async {
    final provider = context.read<AuthProvider>();
    final success = await provider.verifyPin(_pin);

    if (mounted) {
      if (success) {
        SnackBarService.success(context, '¡Bienvenido, ${provider.currentUser?['name']}!');
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        // Muestra el mensaje exacto que viene del backend
        final errorMsg = provider.errorMessage ?? 'Error desconocido';
        SnackBarService.error(context, errorMsg);
        setState(() {
          _pin = '';
          _errorDetail = errorMsg; // Para mostrar en pantalla
        });
      }
    }
  }

  Future<void> _showServerConfigDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUrl = prefs.getString('pos_api') ?? 'http://127.0.0.1:8000/api';
    
    if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF1E2D45),
      body: Stack(
        children: [
          // Botón de configuración
          Positioned(
            top: 24,
            right: 24,
            child: IconButton(
              icon: const Icon(Icons.settings_ethernet, color: Colors.white54, size: 28),
              tooltip: 'Configurar Servidor',
              onPressed: _showServerConfigDialog,
            ),
          ),
          Center(
            child: SingleChildScrollView(
              child: Container(
                width: 400,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 20,
                offset: Offset(0, 10),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.point_of_sale_rounded, size: 64, color: Color(0xFF3B82F6)),
              const SizedBox(height: 16),
              const Text('Sistema POS', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(height: 8),
              const Text('Ingreso al sistema', style: TextStyle(fontSize: 14, color: Colors.black54)),
              const SizedBox(height: 32),

              // Indicadores de PIN o Spinner de carga
              SizedBox(
                height: 24,
                child: provider.isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_pinLength, (index) {
                          final isActive = index < _pin.length;
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isActive ? const Color(0xFF3B82F6) : Colors.grey.shade200,
                              border: Border.all(
                                color: isActive ? const Color(0xFF3B82F6) : Colors.grey.shade400,
                                width: 2,
                              ),
                            ),
                          );
                        }),
                      ),
              ),
              const SizedBox(height: 16),

              // Error Detail (debug)
              if (_errorDetail != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorDetail!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),

              const SizedBox(height: 24),


              // Teclado Numérico
              SizedBox(
                width: 280,
                child: GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  children: [
                    for (var i = 1; i <= 9; i++) _buildKey(i.toString()),
                    _buildKey('clr', icon: Icons.clear_all),
                    _buildKey('0'),
                    _buildKey('del', icon: Icons.backspace_outlined),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
   ],
  ),
 );
}

  Widget _buildKey(String value, {IconData? icon}) {
    return Material(
      color: Colors.grey.shade100,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: context.read<AuthProvider>().isLoading ? null : () => _onKeypadTap(value),
        child: Container(
          alignment: Alignment.center,
          child: icon != null
              ? Icon(icon, color: Colors.black87, size: 28)
              : Text(
                  value,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
        ),
      ),
    );
  }
}
