import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_permissions.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/auth/presentation/widgets/admin_pin_dialog.dart';
import '../../../../features/settings/presentation/providers/settings_provider.dart';
import 'app_modal_shell.dart';

class SharedUserMenu extends StatelessWidget {
  const SharedUserMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 500;

    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final userName = auth.currentUser?['name'] ?? 'Sesión';
        return Padding(
          padding: EdgeInsets.only(right: isCompact ? 2 : 4),
          child: PopupMenuButton<String>(
            position: PopupMenuPosition.under,
            offset: const Offset(0, 6),
            elevation: 14,
            color: const Color(0xFF16233F),
            surfaceTintColor: Colors.transparent,
            shadowColor: const Color(0x73020617),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFF2A3F66), width: 1.5),
            ),
            tooltip: 'Opciones de Usuario ($userName)',
            child: Container(
              height: 34,
              padding: EdgeInsets.symmetric(horizontal: isCompact ? 8 : 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_outline, size: 17, color: Color(0xFF34D399)),
                  if (!isCompact) ...[
                    const SizedBox(width: 7),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 110),
                      child: Text(
                        userName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.white70),
                  ],
                ],
              ),
            ),
            onSelected: (value) async {
              switch (value) {
                case 'shift_audit':
                  final pin = await AdminPinDialog.verifyAndGetPin(
                    context,
                    action: 'Auditoría General',
                    permissionKey: AppPermissions.manageShifts,
                  );
                  if (pin != null && context.mounted) {
                    Navigator.of(context).pushNamed(
                      '/general-audit',
                      arguments: {'unlocked_pin': pin == 'ALREADY_AUTHORIZED' ? null : pin},
                    );
                  }
                  break;
                case 'users':
                  final pin = await AdminPinDialog.verifyAndGetPin(
                    context,
                    action: 'Gestión de Personal',
                    permissionKey: AppPermissions.manageUsers,
                  );
                  if (pin != null && context.mounted) {
                    Navigator.of(context).pushNamed(
                      '/users',
                      arguments: {'unlocked_pin': pin == 'ALREADY_AUTHORIZED' ? null : pin},
                    );
                  }
                  break;
                case 'trash':
                  final pin = await AdminPinDialog.verifyAndGetPin(
                    context,
                    action: 'Papelera de Reciclaje',
                    permissionKey: AppPermissions.manageTrash,
                  );
                  if (pin != null && context.mounted) {
                    Navigator.of(context).pushNamed(
                      '/trash',
                      arguments: {'unlocked_pin': pin == 'ALREADY_AUTHORIZED' ? null : pin},
                    );
                  }
                  break;
                case 'settings':
                  final pin = await AdminPinDialog.verifyAndGetPin(
                    context,
                    action: 'Configuración del Sistema',
                    permissionKey: AppPermissions.manageSettings,
                  );
                  if (pin != null && context.mounted) {
                    Navigator.of(context).pushNamed(
                      '/settings',
                      arguments: {'unlocked_pin': pin == 'ALREADY_AUTHORIZED' ? null : pin},
                    );
                  }
                  break;
                case 'logout':
                  final confirmed = await AppConfirmDialog.show(
                    context,
                    title: 'Cambiar Usuario',
                    message:
                        '¿Deseas cerrar la sesión actual y volver a la pantalla de ingreso de PIN?',
                    confirmLabel: 'Cambiar',
                    cancelLabel: 'Cancelar',
                    icon: Icons.swap_horiz_rounded,
                    isDestructive: false,
                  );
                  if (confirmed == true && context.mounted) {
                    context.read<AuthProvider>().logout();
                    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                  }
                  break;
                case 'close_shift':
                  Navigator.of(context).pushNamed('/close-shift');
                  break;
              }
            },
            itemBuilder: (BuildContext context) {
              final settings = context.read<SettingsProvider>();
              final hasZReports = settings.features.zReports;

              return <PopupMenuEntry<String>>[
                if (isCompact) ...[
                  PopupMenuItem<String>(
                    enabled: false,
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF34D399),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            userName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFF34D399).withValues(alpha: 0.45),
                            ),
                          ),
                          child: const Text(
                            'SESIÓN ACTIVA',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF34D399),
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildDivider(),
                ],
                if (hasZReports)
                  _buildMenuItem(
                    value: 'shift_audit',
                    icon: Icons.manage_search_rounded,
                    label: 'Auditoría General',
                    accentColor: const Color(0xFF38BDF8),
                  ),
                _buildMenuItem(
                  value: 'users',
                  icon: Icons.manage_accounts_outlined,
                  label: 'Personal y Accesos',
                  accentColor: const Color(0xFF818CF8),
                ),
                _buildDivider(),
                _buildMenuItem(
                  value: 'trash',
                  icon: Icons.delete_outline,
                  label: 'Papelera de Reciclaje',
                  accentColor: const Color(0xFF94A3B8),
                ),
                _buildMenuItem(
                  value: 'settings',
                  icon: Icons.settings_outlined,
                  label: 'Configuración del Sistema',
                  accentColor: const Color(0xFF34D399),
                ),
                _buildMenuItem(
                  value: 'logout',
                  icon: Icons.swap_horiz_rounded,
                  label: 'Cambiar Usuario / Bloquear',
                  accentColor: const Color(0xFFFBBF24),
                ),
                if (hasZReports) ...[
                  _buildDivider(),
                  _buildMenuItem(
                    value: 'close_shift',
                    icon: Icons.lock_outline,
                    label: 'Cerrar Turno / Caja',
                    isDanger: true,
                  ),
                ],
              ];
            },
          ),
        );
      },
    );
  }

  PopupMenuEntry<String> _buildDivider() {
    return const PopupMenuItem<String>(
      enabled: false,
      height: 10,
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Color(0xFF263859),
      ),
    );
  }

  PopupMenuItem<String> _buildMenuItem({
    required String value,
    required IconData icon,
    required String label,
    Color? accentColor,
    bool isDanger = false,
  }) {
    final effectiveAccent = isDanger
        ? const Color(0xFFFB7185)
        : (accentColor ?? const Color(0xFF94A3B8));
    return PopupMenuItem<String>(
      value: value,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: effectiveAccent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: effectiveAccent.withValues(alpha: 0.32),
              ),
            ),
            child: Icon(icon, size: 16.5, color: effectiveAccent),
          ),
          const SizedBox(width: 11),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: isDanger ? FontWeight.w700 : FontWeight.w500,
                color: isDanger
                    ? const Color(0xFFFCA5A5)
                    : const Color(0xFFF1F5F9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
