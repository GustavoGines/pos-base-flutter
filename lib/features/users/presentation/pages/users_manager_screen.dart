import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/users_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../widgets/employee_form_dialog.dart';
import '../../../../core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';

class UsersManagerScreen extends StatefulWidget {
  const UsersManagerScreen({Key? key}) : super(key: key);

  @override
  State<UsersManagerScreen> createState() => _UsersManagerScreenState();
}

class _UsersManagerScreenState extends State<UsersManagerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UsersProvider>().loadUsers();
    });
  }

  Future<void> _openForm({Map<String, dynamic>? employee}) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EmployeeFormDialog(employee: employee),
    );
    if (result == null || !mounted) return;

    final provider = context.read<UsersProvider>();
    bool success;
    if (employee == null) {
      success = await provider.createUser(result);
    } else {
      success = await provider.updateUser(employee['id'], result);
    }

    if (!mounted) return;
    if (success) {
      SnackBarService.success(context, employee == null ? 'Empleado creado correctamente' : 'Empleado actualizado');
    } else {
      SnackBarService.error(context, provider.errorMessage ?? 'Error al guardar');
    }
  }

  Future<void> _deleteEmployee(Map<String, dynamic> employee) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Empleado'),
        content: Text('¿Estás seguro de que deseas eliminar a ${employee['name']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final auth = context.read<AuthProvider>();
    final provider = context.read<UsersProvider>();
    final currentId = auth.currentUser?['id'] ?? 0;
    final success = await provider.deleteUser(employee['id'], currentId);
    if (!mounted) return;
    if (success) {
      SnackBarService.success(context, 'Empleado eliminado');
    } else {
      SnackBarService.error(context, provider.errorMessage ?? 'Error al eliminar');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlobalAppBar(
        currentRoute: '/staff',
        title: 'Personal y Permisos',
        showBackButton: true,
        extraAction: Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: FilledButton.icon(
            icon: const Icon(Icons.person_add),
            label: const Text('Nuevo Empleado'),
            onPressed: () => _openForm(), // Reverted to original _openForm call
          ),
        ),
      ),
      backgroundColor: Colors.grey.shade50,
      body: Consumer<UsersProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.users.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline, size: 72, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No hay empleados registrados', style: TextStyle(fontSize: 18, color: Colors.grey)),
                ],
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${provider.users.length} empleado(s) registrado(s)',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.separated(
                    itemCount: provider.users.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final emp = provider.users[index];
                      return _buildEmployeeCard(emp);
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmployeeCard(Map<String, dynamic> emp) {
    final isAdmin = emp['role'] == 'admin';
    final perms = (emp['permissions'] as List?)?.cast<String>() ?? [];
    final color = isAdmin ? Colors.blue.shade800 : Colors.blueGrey.shade600;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          radius: 26,
          child: Icon(
            isAdmin ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
            color: color,
            size: 28,
          ),
        ),
        title: Text(emp['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isAdmin ? 'ADMINISTRADOR' : 'CAJERO',
                style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ),
            if (!isAdmin && perms.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: perms.map((perm) {
                  final meta = kAllPermissions.firstWhere((p) => p['key'] == perm, orElse: () => {'label': perm, 'key': perm, 'icon': 'settings', 'description': ''});
                  return Chip(
                    label: Text(meta['label']!, style: const TextStyle(fontSize: 10)),
                    backgroundColor: Colors.green.shade50,
                    side: BorderSide(color: Colors.green.shade200),
                    visualDensity: VisualDensity.compact,
                    labelPadding: EdgeInsets.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  );
                }).toList(),
              ),
            ] else if (!isAdmin && perms.isEmpty) ...[
              const SizedBox(height: 4),
              const Text('Sin permisos adicionales', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(Icons.edit_outlined, color: Colors.blueGrey),
              onPressed: () => _openForm(employee: emp),
            ),
            IconButton(
              tooltip: 'Eliminar',
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _deleteEmployee(emp),
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}
