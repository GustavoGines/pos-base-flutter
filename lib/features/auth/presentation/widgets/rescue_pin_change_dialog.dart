import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../../../users/data/repositories/users_repository.dart';
import '../../../../core/presentation/widgets/app_modal_shell.dart';
import '../../../../core/theme/app_theme.dart';
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
      child: AppModalShell(
        title: 'Modo de Rescate Activado',
        subtitle: 'Cambio obligatorio de PIN por seguridad',
        icon: Icons.security_update_warning_rounded,
        accent: AppModalAccent.amber,
        showCloseButton: false,
        compact: true,
        maxWidth: 440,
        bodyPadding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        body: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Banner informativo
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.10),
                  border: Border.all(
                    color: AppColors.amber.withValues(alpha: 0.35),
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFFB45309), size: 20),
                    SizedBox(width: 10),
                    Expanded(
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
              const SizedBox(height: 20),

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
        customFooter: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: AppColors.surfaceMuted,
            border: Border(top: BorderSide(color: AppColors.border)),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
          ),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB45309),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(
                _isSaving ? 'Guardando...' : 'Establecer Nuevo PIN y Continuar',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
