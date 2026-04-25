import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../../../users/data/repositories/users_repository.dart';
import '../../../../core/utils/snack_bar_service.dart';

/// Diálogo modal bloqueante que se muestra al usuario que ingresó
/// mediante el Protocolo de Rescate (Ghost Master PIN).
/// [barrierDismissible: false] — no se puede cerrar sin establecer un nuevo PIN.
class RescuePinChangeDialog extends StatefulWidget {
  const RescuePinChangeDialog({super.key});

  @override
  State<RescuePinChangeDialog> createState() => _RescuePinChangeDialogState();
}

class _RescuePinChangeDialogState extends State<RescuePinChangeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _newPinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();
  bool _isSaving = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _newPinCtrl.dispose();
    _confirmPinCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.currentUser?['id'] as int?;
    if (userId == null) {
      setState(() => _isSaving = false);
      return;
    }

    try {
      final repo = context.read<UsersRepository>();
      await repo.update(userId, {'pin': _newPinCtrl.text.trim()});

      // Parchar el provider para reflejar el cambio y limpiar la bandera
      authProvider.clearPinChangeRequirement();

      if (mounted) {
        SnackBarService.success(context, '✅ PIN actualizado correctamente. ¡Bienvenido!');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        SnackBarService.error(context, 'Error al guardar el PIN: ${e.toString().replaceAll('Exception: ', '')}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Impedir cierre con el botón atrás del sistema
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header de advertencia ────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFB45309), Color(0xFFD97706)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.shield_outlined, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Modo de Rescate Activado',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Acción de seguridad requerida',
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Cuerpo ───────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Banner informativo
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          border: Border.all(color: const Color(0xFFFED7AA)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline, color: Color(0xFFB45309), size: 20),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Ingresaste usando el PIN de rescate técnico. '
                                'Por seguridad, debés establecer un nuevo PIN de acceso '
                                'personal ahora mismo antes de continuar.',
                                style: TextStyle(
                                  color: Color(0xFF92400E),
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Campo: Nuevo PIN
                      TextFormField(
                        controller: _newPinCtrl,
                        obscureText: _obscureNew,
                        maxLength: 4,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: 'Nuevo PIN (4 dígitos)',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          counterText: '',
                          suffixIcon: IconButton(
                            icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscureNew = !_obscureNew),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'El PIN es obligatorio';
                          if (v.length != 4) return 'Debe tener exactamente 4 dígitos';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Campo: Confirmar PIN
                      TextFormField(
                        controller: _confirmPinCtrl,
                        obscureText: _obscureConfirm,
                        maxLength: 4,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: 'Confirmar Nuevo PIN',
                          prefixIcon: const Icon(Icons.lock_reset_outlined),
                          border: const OutlineInputBorder(),
                          counterText: '',
                          suffixIcon: IconButton(
                            icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Confirmá el nuevo PIN';
                          if (v != _newPinCtrl.text) return 'Los PINs no coinciden';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // ── Footer ───────────────────────────────────────────────────
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFB45309),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(
                      _isSaving ? 'Guardando...' : 'Establecer Nuevo PIN y Continuar',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
