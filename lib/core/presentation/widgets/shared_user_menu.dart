import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/auth/presentation/widgets/admin_pin_dialog.dart';

class SharedUserMenu extends StatelessWidget {
  const SharedUserMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final userName = auth.currentUser?['name'] ?? 'Sesión';
        return Padding(
          padding: const EdgeInsets.only(right: 16),
          child: PopupMenuButton<String>(
            offset: const Offset(0, 45),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tooltip: 'Opciones de Usuario',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.blueGrey.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_outline, size: 20, color: Colors.blueGrey),
                  const SizedBox(width: 8),
                  Text(
                    userName,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, color: Colors.blueGrey),
                ],
              ),
            ),
            onSelected: (value) async {
              switch (value) {
                case 'shift_audit':
                  final auditAuth = await AdminPinDialog.verify(context, action: 'Ver Auditoría de Turnos', permissionKey: 'view_global_history');
                  if (auditAuth && context.mounted) {
                    Navigator.of(context).pushNamed('/shift-audit');
                  }
                  break;
                case 'users':
                  Navigator.of(context).pushNamed('/users');
                  break;
                case 'trash':
                  final authorized = await AdminPinDialog.verify(context, action: 'Acceder a Papelera');
                  if (authorized && context.mounted) {
                    Navigator.of(context).pushNamed('/trash');
                  }
                  break;
                case 'settings':
                  final authorized = await AdminPinDialog.verify(context, action: 'Acceder a Configuración');
                  if (authorized && context.mounted) {
                    Navigator.of(context).pushNamed('/settings');
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
                      content: const Text('¿Deseas cerrar la sesión actual y volver a la pantalla de ingreso de PIN?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
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
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              if (auth.isAdmin) ...<PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'shift_audit',
                  child: ListTile(
                    leading: Icon(Icons.history_edu),
                    title: Text('Auditoría de Turnos (Z)'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'users',
                  child: ListTile(
                    leading: Icon(Icons.manage_accounts_outlined),
                    title: Text('Personal y Accesos'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                const PopupMenuDivider(),
              ],
              const PopupMenuItem<String>(
                value: 'trash',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Papelera de Reciclaje'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuItem<String>(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Configuración del Sistema'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuItem<String>(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.swap_horiz_rounded),
                  title: Text('Cambiar Usuario / Bloquear'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'close_shift',
                child: ListTile(
                  leading: Icon(Icons.lock_outline, color: Colors.redAccent),
                  title: Text('Cerrar Turno / Caja', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
