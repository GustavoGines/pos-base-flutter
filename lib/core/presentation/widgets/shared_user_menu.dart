import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_permissions.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/auth/presentation/widgets/admin_pin_dialog.dart';
import '../../../../features/settings/presentation/providers/settings_provider.dart';

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
          padding: EdgeInsets.only(right: isCompact ? 4 : 16),
          child: PopupMenuButton<String>(
            position: PopupMenuPosition.under,
            offset: const Offset(0, 6),
            elevation: 8,
            color: Colors.white,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.black.withValues(alpha: 0.16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            tooltip: 'Opciones de Usuario ($userName)',
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: isCompact ? 10 : 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.blueGrey.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_outline, size: 20, color: Colors.blueGrey),
                  if (!isCompact) ...[
                    const SizedBox(width: 8),
                    Text(
                      userName,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down, color: Colors.blueGrey),
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
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Row(
                        children: [
                          Icon(Icons.swap_horiz_rounded, color: Colors.blueGrey),
                          SizedBox(width: 8),
                          Text('Cambiar Usuario'),
                        ],
                      ),
                      content: const Text(
                        '¿Deseas cerrar la sesión actual y volver a la pantalla de ingreso de PIN?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancelar'),
                        ),
                        FilledButton.icon(
                          onPressed: () => Navigator.pop(ctx, true),
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Cambiar'),
                          style: FilledButton.styleFrom(backgroundColor: Colors.blueGrey.shade700),
                        ),
                      ],
                    ),
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
                if (hasZReports)
                  _buildMenuItem(
                    value: 'shift_audit',
                    icon: Icons.manage_search_rounded,
                    label: 'Auditoría General',
                  ),
                _buildMenuItem(
                  value: 'users',
                  icon: Icons.manage_accounts_outlined,
                  label: 'Personal y Accesos',
                ),
                const PopupMenuDivider(height: 8),
                _buildMenuItem(
                  value: 'trash',
                  icon: Icons.delete_outline,
                  label: 'Papelera de Reciclaje',
                ),
                _buildMenuItem(
                  value: 'settings',
                  icon: Icons.settings_outlined,
                  label: 'Configuración del Sistema',
                ),
                _buildMenuItem(
                  value: 'logout',
                  icon: Icons.swap_horiz_rounded,
                  label: 'Cambiar Usuario / Bloquear',
                ),
                if (hasZReports) ...[
                  const PopupMenuDivider(height: 8),
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

  PopupMenuItem<String> _buildMenuItem({
    required String value,
    required IconData icon,
    required String label,
    bool isDanger = false,
  }) {
    final color = isDanger ? Colors.redAccent : Colors.blueGrey.shade700;
    return PopupMenuItem<String>(
      value: value,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: isDanger ? FontWeight.bold : FontWeight.w500,
              color: isDanger ? Colors.redAccent : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
