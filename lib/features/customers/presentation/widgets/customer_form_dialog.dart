import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/customer_model.dart';
import '../../providers/customer_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/widgets/admin_pin_dialog.dart';
import 'package:frontend_desktop/core/constants/app_permissions.dart';

class CustomerFormDialog extends StatefulWidget {
  final Customer? customer; // Null = Nuevo, No-null = Editar

  const CustomerFormDialog({super.key, this.customer});

  @override
  State<CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _documentController;
  late TextEditingController _phoneController;
  late TextEditingController _creditLimitController;
  late TextEditingController _deliveryAddressController;
  late TextEditingController _fiscalAddressController;
  int _documentType = 96;
  String _taxCondition = 'consumidor_final';
  bool _isInternalAccount = false;
  bool _appliesIibbPerception = false;
  late TextEditingController _iibbRateController;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.customer?.name ?? '');
    _documentController =
        TextEditingController(text: widget.customer?.documentNumber ?? '');
    _documentType = widget.customer?.documentType ?? 96;
    if (![80, 86, 96].contains(_documentType)) _documentType = 96;
    _taxCondition = widget.customer?.taxCondition ?? 'consumidor_final';
    _phoneController =
        TextEditingController(text: widget.customer?.phone ?? '');
    _creditLimitController = TextEditingController(
        text: widget.customer != null
            ? widget.customer!.creditLimit.toString()
            : '');
    _deliveryAddressController =
        TextEditingController(text: widget.customer?.deliveryAddress ?? '');
    _fiscalAddressController =
        TextEditingController(text: widget.customer?.fiscalAddress ?? '');
    _isInternalAccount = widget.customer?.isInternalAccount ?? false;
    _appliesIibbPerception = widget.customer?.appliesIibbPerception ?? false;
    _iibbRateController = TextEditingController(
      text: widget.customer?.iibbPerceptionRate != null
          ? widget.customer!.iibbPerceptionRate.toString()
          : '',
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    await AdminPinDialog.protectAction(
      context,
      action: widget.customer == null ? 'Crear Cliente' : 'Editar Cliente',
      permissionKey: AppPermissions.manageCustomers,
      onAuthorized: () async {
        try {
          final payload = {
            'name': _nameController.text.trim(),
            'document_number': _documentController.text.trim(),
            'document_type': _documentType,
            'tax_condition': _taxCondition,
            'fiscal_address': _fiscalAddressController.text.trim().isEmpty
                ? null
                : _fiscalAddressController.text.trim(),
            'phone': _phoneController.text.trim(),
            'credit_limit':
                double.tryParse(_creditLimitController.text.trim()) ?? 0.0,
            'delivery_address': _deliveryAddressController.text.trim(),
            'is_internal_account': _isInternalAccount,
            'applies_iibb_perception': _appliesIibbPerception,
            'iibb_perception_rate': _appliesIibbPerception
                ? double.tryParse(_iibbRateController.text.trim().replaceAll(',', '.'))
                : null,
          };

          bool success;
          if (widget.customer == null) {
            success =
                await context.read<CustomerProvider>().createCustomer(payload);
          } else {
            success = await context
                .read<CustomerProvider>()
                .updateCustomer(widget.customer!.id, payload);
          }

          if (success && mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(widget.customer == null
                      ? 'Cliente creado exitosamente'
                      : 'Cliente actualizado exitosamente'),
                  backgroundColor: Colors.green),
            );
          }
        } catch (e) {
          if (mounted) {
            final msg = e.toString().replaceAll('Exception: ', '');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg), backgroundColor: Colors.red),
            );
          }
        } finally {
          if (mounted) {
            setState(() => _isSubmitting = false);
          }
        }
      },
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _documentController.dispose();
    _phoneController.dispose();
    _creditLimitController.dispose();
    _deliveryAddressController.dispose();
    _fiscalAddressController.dispose();
    _iibbRateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.customer != null;

    return AlertDialog(
      title: Text(isEditing ? 'Editar Cliente' : 'Nuevo Cliente'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                    labelText: 'Nombre / Razón Social *',
                    border: OutlineInputBorder()),
                validator: (val) =>
                    val == null || val.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _documentType,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Tipo de Documento AFIP',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 80, child: Text('80 - CUIT')),
                  DropdownMenuItem(value: 86, child: Text('86 - CUIL')),
                  DropdownMenuItem(value: 96, child: Text('96 - DNI')),
                  
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _documentType = val);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _documentController,
                decoration: InputDecoration(
                  labelText: _documentType == 80
                      ? 'CUIT (11 dígitos sin guiones) *'
                      : (_documentType == 86
                          ? 'CUIL (11 dígitos) *'
                          : (_documentType == 96
                              ? 'DNI (7 u 8 dígitos) *'
                              : 'Nro de Documento')),
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (val) {
                  final text = val?.trim() ?? '';
                  if (text.isEmpty) {
                    
                    return 'Requerido';
                  }
                  if (_documentType == 80 || _documentType == 86) {
                    if (!AfipModulo11.validateCuit(text)) {
                      return 'CUIT/CUIL inválido (Módulo 11)';
                    }
                  } else if (_documentType == 96) {
                    if (!AfipModulo11.validateDni(text)) {
                      return 'DNI inválido (7-8 dígitos)';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _taxCondition,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Condición frente al IVA',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'consumidor_final', child: Text('Consumidor Final')),
                  DropdownMenuItem(
                      value: 'responsable_inscripto',
                      child: Text('IVA Responsable Inscripto')),
                  DropdownMenuItem(
                      value: 'monotributo',
                      child: Text('Responsable Monotributo')),
                  DropdownMenuItem(
                      value: 'exento', child: Text('IVA Exento')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _taxCondition = val);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _fiscalAddressController,
                decoration: const InputDecoration(
                    labelText: 'Dirección Fiscal (AFIP) (Opcional)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'Teléfono (Opcional)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _deliveryAddressController,
                decoration: const InputDecoration(
                    labelText: 'Dirección de Entrega (Opcional)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _creditLimitController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Límite de Crédito (\$) (Opcional)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text(
                    'Cuenta de Consumo Interno (Ej: Repostería / Uso Propio)',
                    style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                    'Excluye estas ventas de los reportes de ganancias y facturación.',
                    style: TextStyle(fontSize: 12)),
                value: _isInternalAccount,
                activeThumbColor: Colors.indigo,
                onChanged: (val) => setState(() => _isInternalAccount = val),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              SwitchListTile(
                key: const ValueKey('switch_applies_iibb_perception'),
                title: const Text('Aplica Percepción IIBB',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text(
                    'Calcular percepción de Ingresos Brutos en compras mayoristas.',
                    style: TextStyle(fontSize: 12)),
                value: _appliesIibbPerception,
                activeThumbColor: Theme.of(context).colorScheme.primary,
                onChanged: (val) {
                  setState(() {
                    _appliesIibbPerception = val;
                    if (val && _iibbRateController.text.trim().isEmpty) {
                      try {
                        final defaultRate = context.read<SettingsProvider?>()?.settings?.defaultIibbPerceptionRate;
                        if (defaultRate != null && defaultRate > 0) {
                          _iibbRateController.text = defaultRate.toString();
                        }
                      } catch (_) {}
                    }
                  });
                },
              ),
              if (_appliesIibbPerception) ...[
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('field_iibb_perception_rate'),
                  controller: _iibbRateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*[\.,]?\d{0,2}')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Alícuota IIBB (%) *',
                    hintText: 'Ej: 3.0',
                    prefixIcon: Icon(Icons.percent),
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (!_appliesIibbPerception) return null;
                    if (val == null || val.trim().isEmpty) {
                      return 'La alícuota es requerida si aplica percepción';
                    }
                    final n = double.tryParse(val.trim().replaceAll(',', '.'));
                    if (n == null || n < 0 || n > 100) {
                      return 'Ingrese un porcentaje válido (0 - 100)';
                    }
                    return null;
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary),
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Text('Guardar', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
