import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../../providers/supplier_provider.dart';
import '../../../pos/presentation/providers/pos_provider.dart';
import '../../../catalog/domain/entities/product.dart';
import '../../../cash_movements/presentation/widgets/movement_form_dialog.dart';
import '../../../cash_register/presentation/providers/cash_register_provider.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../catalog/presentation/providers/catalog_provider.dart';
import '../../../catalog/presentation/pages/catalog_screen.dart' show ProductFormDialog;
import 'dart:async';

class _InvoiceItemModel {
  final Product product;
  double quantity = 1;
  double newCost;
  double? suggestedPrice;
  double manualPrice;
  bool updatePrice = false;

  _InvoiceItemModel({
    required this.product,
    required this.newCost,
    required this.manualPrice,
  });

  double get subtotal => quantity * newCost;
}

class SupplierInvoiceFormDialog extends StatefulWidget {
  final int supplierId;
  final String supplierName;

  const SupplierInvoiceFormDialog({
    super.key,
    required this.supplierId,
    required this.supplierName,
  });

  @override
  State<SupplierInvoiceFormDialog> createState() => _SupplierInvoiceFormDialogState();
}

class _SupplierInvoiceFormDialogState extends State<SupplierInvoiceFormDialog> {
  final _formKey = GlobalKey<FormState>();
  String _type = 'invoice'; 
  final _invoiceNumberController = TextEditingController();
  final _descriptionController = TextEditingController(text: 'Mercadería');

  final _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;
  List<Product> _searchResults = [];
  bool _isSearching = false;

  final List<_InvoiceItemModel> _items = [];

  bool _isLoading = false;
  bool _payNow = false;

  DateTime? _issueDate = DateTime.now();
  DateTime? _dueDate;
  
  double _taxAmount = 0.0;
  double _freightAmount = 0.0;
  double _discountAmount = 0.0;
  
  String? _attachmentUrl;
  bool _isUploading = false;

  @override
  void dispose() {
    _invoiceNumberController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _isSearching = true);
      try {
        final results = await context.read<PosProvider>().search(query);
        if (mounted) {
          setState(() {
            _searchResults = results;
            _isSearching = false;
          });
          // Auto-agregar si es un código de barras exacto (Modo Escáner Continuo)
          if (results.length == 1 && results.first.barcode != null && results.first.barcode!.trim() == query.trim()) {
            _addProduct(results.first);
          }
        }
      } catch (e) {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  void _addProduct(Product product) {
    // Si ya existe, sumamos cantidad
    final existingIndex = _items.indexWhere((i) => i.product.id == product.id);
    if (existingIndex >= 0) {
      setState(() {
        _items[existingIndex].quantity += 1;
      });
    } else {
      setState(() {
        _items.insert(0, _InvoiceItemModel(
          product: product,
          newCost: product.costPrice,
          manualPrice: product.sellingPrice,
        ));
      });
    }
    _searchController.clear();
    _searchResults = [];
    _searchFocus.requestFocus();
  }

  void _handleCostChange(_InvoiceItemModel item, String val) {
    final parsed = double.tryParse(val);
    if (parsed == null) return;
    
    setState(() {
      item.newCost = parsed;
      if (item.newCost > item.product.costPrice && item.product.costPrice > 0) {
        // Alerta de Margen Dinámico
        final margin = (item.product.sellingPrice - item.product.costPrice) / item.product.costPrice;
        item.suggestedPrice = item.newCost * (1 + margin);
        item.manualPrice = item.suggestedPrice!;
        item.updatePrice = true;
      } else {
        item.suggestedPrice = null;
        item.updatePrice = false;
      }
    });
  }

  Future<void> _pickAndUploadFile() async {
    // FIXME: file_picker platform property is not resolving correctly in this environment.
    // Uncomment when file_picker version issue is resolved.
    /*
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _isUploading = true);
      try {
        final supplierProv = context.read<SupplierProvider>();
        final apiClient = context.read<ApiClient>();
        
        final request = http.MultipartRequest('POST', Uri.parse('${supplierProv.baseUrl}/supplier-invoices/upload'));
        if (apiClient.sessionToken != null) {
           request.headers['X-Session-Token'] = apiClient.sessionToken!;
        }
        
        request.files.add(await http.MultipartFile.fromPath('file', result.files.single.path!));
        
        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          setState(() {
            _uploadedFilePath = data['path'];
            _isUploading = false;
          });
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Comprobante subido.')));
        } else {
          throw Exception('Error al subir comprobante');
        }
      } catch (e) {
        setState(() => _isUploading = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fallo la subida.')));
      }
    }
    */
  }

  double get _totalAmount {
    if (_items.isEmpty) return 0.0;
    final sub = _items.fold(0.0, (sum, item) => sum + item.subtotal);
    return sub + _freightAmount + _taxAmount - _discountAmount;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Debe agregar al menos un producto')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final itemsData = _items.map((i) => {
        'product_id': i.product.id,
        'quantity': i.quantity,
        'unit_cost': i.newCost,
        'subtotal': i.quantity * i.newCost,
        'update_price': i.updatePrice,
        'new_selling_price': i.updatePrice ? i.manualPrice : null,
      }).toList();

      final data = {
        'type': _type,
        'amount': _totalAmount,
        'tax_amount': _taxAmount,
        'freight_amount': _freightAmount,
        'discount_amount': _discountAmount,
        'issue_date': _issueDate?.toIso8601String().split('T')[0],
        'due_date': _dueDate?.toIso8601String().split('T')[0],
        'receipt_file_url': _attachmentUrl,
        'invoice_number': _invoiceNumberController.text.trim(),
        'description': _descriptionController.text.trim(),
        'items': itemsData,
      };

      final provider = context.read<SupplierProvider>();
      final success = await provider.createInvoice(widget.supplierId, data);

      if (success && mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Factura registrada correctamente. Stock y Costos actualizados.')));

        if (_payNow && _type == 'invoice') {
          final supplier = provider.suppliers.firstWhere((s) => s.id == widget.supplierId);
          final newBalance = supplier.balance;
          final amountToPay = newBalance > 0 ? (_totalAmount < newBalance ? _totalAmount : newBalance) : 0.0;
          final discount = _totalAmount - amountToPay;
          
          String? helperText;
          if (discount > 0 && amountToPay > 0) {
            helperText = '💡 Se han descontado \$${discount.toStringAsFixed(2).replaceAll('.00', '')} que tenías a favor.';
          }

          if (amountToPay > 0) {
            final cashProv = context.read<CashRegisterProvider>();
            if (cashProv.currentShift != null && cashProv.currentShift!.isOpen) {
               showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => MovementFormDialog(
                  initialSupplierId: widget.supplierId,
                  initialType: 'supplier_payment',
                  initialAmount: amountToPay,
                  helperText: helperText,
                ),
              );
            } else {
               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se puede abonar ahora porque no hay turno de caja abierto.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
            }
          } else {
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Factura cubierta con Saldo a Favor.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
          }
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().toString()), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 800),
        padding: const EdgeInsets.all(0),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.blue.shade800,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Text('Espejo de Ventas - Carga de Remito', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('Proveedor: ${widget.supplierName}', style: const TextStyle(color: Colors.white70, fontSize: 16)),
                  const SizedBox(width: 16),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 800;
                      
                      final itemsTable = Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _items.isEmpty 
                          ? Center(child: Text('Busque y seleccione productos para agregarlos al remito.', style: TextStyle(color: Colors.grey.shade600)))
                          : ListView.separated(
                              itemCount: _items.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = _items[index];
                                return _buildItemRow(item, index);
                              },
                            ),
                      );

                      final leftPanel = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Buscador
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Column(
                                children: [
                                  TextField(
                                    controller: _searchController,
                                    focusNode: _searchFocus,
                                    decoration: InputDecoration(
                                      hintText: 'Buscar producto por nombre o código...',
                                      prefixIcon: const Icon(Icons.search),
                                      suffixIcon: IconButton(
                                        icon: const Icon(Icons.add_circle, color: Colors.blue),
                                        tooltip: 'Nuevo Producto Rápido',
                                        onPressed: () async {
                                          final catalogProv = context.read<CatalogProvider>();
                                          await showDialog(
                                            context: context,
                                            barrierDismissible: false,
                                            builder: (_) => ProductFormDialog(provider: catalogProv),
                                          );
                                          // Al cerrar, no hacemos nada especial, si se creó el producto,
                                          // el usuario puede buscarlo y aparecerá.
                                        },
                                      ),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.all(16),
                                    ),
                                    onChanged: _onSearchChanged,
                                  ),
                                  if (_isSearching || _searchResults.isNotEmpty)
                                    Container(
                                      constraints: const BoxConstraints(maxHeight: 200),
                                      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade200))),
                                      child: _isSearching 
                                        ? const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()))
                                        : ListView.builder(
                                            shrinkWrap: true,
                                            itemCount: _searchResults.length,
                                            itemBuilder: (context, index) {
                                              final p = _searchResults[index];
                                              return ListTile(
                                                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                                subtitle: Text('Costo actual: \$${p.costPrice.toStringAsFixed(2)} | Stock: ${p.stock}'),
                                                trailing: const Icon(Icons.add_shopping_cart, color: Colors.blue),
                                                onTap: () => _addProduct(p),
                                              );
                                            },
                                          ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            // Tabla de Items
                            if (isWide)
                              Expanded(child: itemsTable)
                            else
                              SizedBox(height: 350, child: itemsTable),
                          ],
                        );

                      final rightFormContent = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Datos Generales', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: _type,
                            decoration: const InputDecoration(labelText: 'Tipo', isDense: true),
                            items: const [
                              DropdownMenuItem(value: 'invoice', child: Text('Remito / Factura')),
                              DropdownMenuItem(value: 'credit_note', child: Text('Nota de Crédito')),
                            ],
                            onChanged: (val) {
                              setState(() {
                                _type = val!;
                                if (_type == 'credit_note') _payNow = false;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () async {
                                    final date = await showDatePicker(
                                      context: context,
                                      initialDate: _issueDate ?? DateTime.now(),
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime(2100),
                                    );
                                    if (date != null) setState(() => _issueDate = date);
                                  },
                                  child: InputDecorator(
                                    decoration: const InputDecoration(labelText: 'Fecha Emisión', isDense: true),
                                    child: Text(_issueDate != null ? DateFormat('dd/MM/yyyy').format(_issueDate!) : 'Seleccionar'),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: InkWell(
                                  onTap: () async {
                                    final date = await showDatePicker(
                                      context: context,
                                      initialDate: _dueDate ?? DateTime.now(),
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime(2100),
                                    );
                                    if (date != null) setState(() => _dueDate = date);
                                  },
                                  child: InputDecorator(
                                    decoration: const InputDecoration(labelText: 'Vencimiento', isDense: true),
                                    child: Text(_dueDate != null ? DateFormat('dd/MM/yyyy').format(_dueDate!) : 'Opcional'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _invoiceNumberController,
                            decoration: const InputDecoration(labelText: 'Nº Comprobante (Opc.)', isDense: true),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _descriptionController,
                            decoration: const InputDecoration(labelText: 'Concepto', isDense: true),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 16),
                          // Attachment button
                          OutlinedButton.icon(
                            onPressed: _isUploading ? null : _pickAndUploadFile,
                            icon: _isUploading 
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.attach_file),
                            label: Text(_attachmentUrl != null ? 'Comprobante Adjunto ✓' : 'Adjuntar Comprobante (PDF/IMG)'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _attachmentUrl != null ? Colors.green.shade700 : Colors.blue.shade700,
                              side: BorderSide(color: _attachmentUrl != null ? Colors.green.shade300 : Colors.blue.shade300),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      );

                      final rightBottomContent = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_type == 'invoice')
                            Container(
                              padding: const EdgeInsets.all(8),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.shade200),
                              ),
                              child: CheckboxListTile(
                                title: const Text('Abonar en el acto', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                subtitle: const Text('Abre un movimiento de caja al guardar.', style: TextStyle(fontSize: 12)),
                                value: _payNow,
                                onChanged: (val) => setState(() => _payNow = val ?? false),
                                contentPadding: EdgeInsets.zero,
                                controlAffinity: ListTileControlAffinity.leading,
                              ),
                            ),
                          
                          // Extra charges
                          Row(
                            children: [
                              Expanded(child: TextFormField(
                                initialValue: _freightAmount > 0 ? _freightAmount.toString() : '',
                                decoration: const InputDecoration(labelText: 'Flete (\$)', isDense: true),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                onChanged: (v) {
                                  final p = double.tryParse(v);
                                  if (p != null) setState(() => _freightAmount = p);
                                  else setState(() => _freightAmount = 0);
                                },
                              )),
                              const SizedBox(width: 8),
                              Expanded(child: TextFormField(
                                initialValue: _taxAmount > 0 ? _taxAmount.toString() : '',
                                decoration: const InputDecoration(labelText: 'Impuestos (\$)', isDense: true),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                onChanged: (v) {
                                  final p = double.tryParse(v);
                                  if (p != null) setState(() => _taxAmount = p);
                                  else setState(() => _taxAmount = 0);
                                },
                              )),
                              const SizedBox(width: 8),
                              Expanded(child: TextFormField(
                                initialValue: _discountAmount > 0 ? _discountAmount.toString() : '',
                                decoration: const InputDecoration(labelText: 'Descuento (\$)', isDense: true),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                onChanged: (v) {
                                  final p = double.tryParse(v);
                                  if (p != null) setState(() => _discountAmount = p);
                                  else setState(() => _discountAmount = 0);
                                },
                              )),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade900,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                const Text('TOTAL', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                                Text(NumberFormat.currency(symbol: '\$').format(_totalAmount), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: FilledButton.icon(
                              onPressed: _isLoading ? null : _submit,
                              icon: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.save),
                              label: const Text('CONFIRMAR CARGA', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                            ),
                          ),
                        ],
                      );

                      final rightPanel = Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: isWide 
                          ? Column(
                              children: [
                                Expanded(child: SingleChildScrollView(child: rightFormContent)),
                                rightBottomContent,
                              ],
                            )
                          : Column(
                              children: [
                                rightFormContent,
                                rightBottomContent,
                              ],
                            ),
                      );

                      if (isWide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 6, child: leftPanel),
                            const SizedBox(width: 24),
                            Expanded(flex: 3, child: rightPanel),
                          ],
                        );
                      } else {
                        return SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              leftPanel,
                              const SizedBox(height: 16),
                              rightPanel,
                            ],
                          ),
                        );
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRow(_InvoiceItemModel item, int index) {
    final qtyStr = item.product.isSoldByWeight || item.product.unitType == 'kg'
        ? item.quantity.toStringAsFixed(3)
        : item.quantity.toInt().toString();

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('Costo Ant: \$${item.product.costPrice.toStringAsFixed(2)} | PVP: \$${item.product.sellingPrice.toStringAsFixed(2)}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ),
              Expanded(
                flex: 1,
                child: TextFormField(
                  initialValue: qtyStr,
                  decoration: InputDecoration(labelText: 'Cant. (${item.product.unitType ?? 'un'})', isDense: true),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (val) {
                    final p = double.tryParse(val);
                    if (p != null) setState(() => item.quantity = p);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: TextFormField(
                  initialValue: item.newCost.toString(),
                  decoration: const InputDecoration(labelText: 'Costo Un.', prefixText: '\$', isDense: true),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (val) => _handleCostChange(item, val),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 100,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(NumberFormat.currency(symbol: '\$').format(item.subtotal), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => setState(() => _items.removeAt(index))),
            ],
          ),
          
          if (item.suggestedPrice != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.trending_up, color: Colors.orange.shade800, size: 20),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text('Costo incrementado. Margen histórico: ${(((item.product.sellingPrice - item.product.costPrice) / (item.product.costPrice > 0 ? item.product.costPrice : 1)) * 100).toStringAsFixed(1)}%', style: TextStyle(color: Colors.orange.shade900, fontSize: 12)),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: item.updatePrice,
                        onChanged: (val) => setState(() => item.updatePrice = val ?? false),
                        activeColor: Colors.orange.shade800,
                      ),
                      const Text('Actualizar PVP a:', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: TextFormField(
                          initialValue: item.manualPrice.toStringAsFixed(2),
                          enabled: item.updatePrice,
                          decoration: const InputDecoration(isDense: true, prefixText: '\$', contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (val) {
                            final p = double.tryParse(val);
                            if (p != null) item.manualPrice = p;
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
