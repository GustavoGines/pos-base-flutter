import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/users_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/widgets/admin_pin_dialog.dart';
import '../widgets/employee_form_dialog.dart';
import '../../../../core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import 'package:frontend_desktop/core/constants/app_permissions.dart';

class UsersManagerScreen extends StatefulWidget {
  const UsersManagerScreen({super.key});

  @override
  State<UsersManagerScreen> createState() => _UsersManagerScreenState();
}

class _UsersManagerScreenState extends State<UsersManagerScreen> {
  final Set<dynamic> _expandedEmployeeIds = {};
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
      final rawId = employee['id'];
      final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '') ?? 0;
      success = await provider.updateUser(id, result);
    }

    if (!mounted) return;
    if (success) {
      if (employee != null) {
        final auth = context.read<AuthProvider>();
        if (auth.currentUser?['id'] == employee['id']) {
          auth.patchCurrentUser(result);
        }
      }
      SnackBarService.success(context, employee == null ? 'Empleado creado correctamente' : 'Empleado actualizado');
    } else {
      SnackBarService.error(context, provider.errorMessage ?? 'Error al guardar');
    }
  }

  Future<void> _deleteEmployee(Map<String, dynamic> employee) async {
    final name = employee['name']?.toString() ?? 'Empleado';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Empleado'),
        content: Text('¿Estás seguro de que deseás eliminar a $name?'),
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

    final rawId = employee['id'];
    final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
    if (id == null) {
      SnackBarService.error(context, 'ID de empleado inválido');
      return;
    }

    await AdminPinDialog.protectAction(
      context,
      action: 'Eliminar al empleado "$name"',
      permissionKey: AppPermissions.manageUsers,
      onAuthorized: () async {
        final provider = context.read<UsersProvider>();
        // FIX U-3: Ya no pasamos currentUserId — el backend lo obtiene del header X-Session-Token.
        final success = await provider.deleteUser(id);
        if (!mounted) return;
        if (success) {
          SnackBarService.success(context, 'Empleado eliminado');
        } else {
          SnackBarService.error(context, provider.errorMessage ?? 'Error al eliminar');
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlobalAppBar(
        currentRoute: '/staff',
        title: 'Personal y Permisos',
        showBackButton: true,
      ),
      backgroundColor: Colors.grey.shade50,
      body: Consumer<UsersProvider>(
        builder: (context, provider, _) {
          final isCompact = MediaQuery.of(context).size.width < 500;
          return Padding(
            padding: EdgeInsets.all(isCompact ? 16 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Text('${provider.users.length} empleado(s) registrado(s)',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => context.read<UsersProvider>().loadUsers(),
                          icon: const Icon(Icons.refresh, color: Colors.blueAccent),
                          tooltip: 'Recargar lista',
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          icon: const Icon(Icons.person_add),
                          label: const Text('Nuevo Empleado'),
                          onPressed: () => _openForm(),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: provider.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : provider.users.isEmpty
                          ? const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.people_outline, size: 72, color: Colors.grey),
                                  SizedBox(height: 16),
                                  Text('No hay empleados registrados', style: TextStyle(fontSize: 18, color: Colors.grey)),
                                ],
                              ),
                            )
                          : ListView.separated(
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
    final roleStr = emp['role']?.toString().toLowerCase().trim();
    final isAdmin = roleStr == 'admin';
    List<String> perms = [];
    final rawPerms = emp['permissions'];
    if (rawPerms is Iterable) {
      perms = rawPerms.whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    } else if (rawPerms is Map) {
      perms = rawPerms.entries
          .where((e) => e.value == true || e.value == 1 || e.value == 'true')
          .map((e) => e.key.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else if (rawPerms is String) {
      try {
        final parsed = jsonDecode(rawPerms);
        if (parsed is Iterable) {
          perms = parsed.whereType<String>().where((s) => s.trim().isNotEmpty).toList();
        } else if (parsed is Map) {
          perms = parsed.entries
              .where((e) => e.value == true || e.value == 1 || e.value == 'true')
              .map((e) => e.key.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList();
        }
      } catch (_) {}
    }
    // Deduplicate permissions to prevent duplicate chips
    perms = perms.toSet().toList();

    final empId = emp['id']?.toString() ?? emp['name']?.toString() ?? emp.hashCode.toString();
    final isExpanded = _expandedEmployeeIds.contains(empId);
    final color = isAdmin ? Colors.blue.shade800 : Colors.blueGrey.shade600;

    final isCompact = MediaQuery.of(context).size.width < 500;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 20, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          radius: 26,
          child: Icon(
            isAdmin ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
            color: color,
            size: 28,
          ),
        ),
        title: Text(
          emp['name'] ?? '',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isAdmin ? 'ADMINISTRADOR' : 'CAJERO',
                style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ),
            if (!isAdmin && perms.isNotEmpty) ...[
              const SizedBox(height: 6),
              _buildPermissionsWrap(empId, perms, isExpanded),
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
              visualDensity: VisualDensity.compact,
              onPressed: () => _openForm(employee: emp),
            ),
            IconButton(
              tooltip: 'Eliminar',
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              visualDensity: VisualDensity.compact,
              onPressed: () => _deleteEmployee(emp),
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  Widget _buildPermissionsWrap(dynamic empId, List<String> perms, bool isExpanded) {
    const int maxCollapsed = 3;
    final bool shouldCollapse = perms.length > 4 && !isExpanded;
    final visiblePerms = shouldCollapse ? perms.take(maxCollapsed).toList() : perms;
    final remainingCount = perms.length - maxCollapsed;

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...visiblePerms.map((perm) {
          final meta = kAllPermissions.firstWhere(
            (p) => p['key'] == perm,
            orElse: () => {'label': perm, 'key': perm, 'icon': 'settings', 'description': ''},
          );
          return Chip(
            label: Text(meta['label']!, style: const TextStyle(fontSize: 10, color: Color(0xFF1B5E20))),
            backgroundColor: Colors.green.shade50,
            side: BorderSide(color: Colors.green.shade200),
            visualDensity: VisualDensity.compact,
            labelPadding: EdgeInsets.zero,
            padding: const EdgeInsets.symmetric(horizontal: 6),
          );
        }),
        if (shouldCollapse)
          Tooltip(
            message: perms.skip(maxCollapsed).map((p) {
              final meta = kAllPermissions.firstWhere(
                (item) => item['key'] == p,
                orElse: () => {'label': p},
              );
              return '• ${meta['label']}';
            }).join('\n'),
            child: InkWell(
              onTap: () {
                setState(() {
                  _expandedEmployeeIds.add(empId);
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Chip(
                avatar: const Icon(Icons.add_circle_outline, size: 13, color: Color(0xFF1565C0)),
                label: Text(
                  '+$remainingCount más',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
                ),
                backgroundColor: Colors.blue.shade50,
                side: BorderSide(color: Colors.blue.shade200),
                visualDensity: VisualDensity.compact,
                labelPadding: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
            ),
          ),
        if (isExpanded && perms.length > 4)
          InkWell(
            onTap: () {
              setState(() {
                _expandedEmployeeIds.remove(empId);
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Chip(
              avatar: const Icon(Icons.expand_less, size: 13, color: Colors.blueGrey),
              label: const Text(
                'Ver menos',
                style: TextStyle(fontSize: 10, color: Colors.blueGrey),
              ),
              backgroundColor: Colors.grey.shade100,
              side: BorderSide(color: Colors.grey.shade300),
              visualDensity: VisualDensity.compact,
              labelPadding: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
          ),
      ],
    );
  }
}
