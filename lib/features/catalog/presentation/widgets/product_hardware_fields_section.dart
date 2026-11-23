import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';

class ProductHardwareAndSupplierFieldsSection extends StatefulWidget {
  final bool isHardwareStore;
  final bool isService;
  final bool isCombo;
  final bool isNarrow;
  final String unitLabel;
  final TextEditingController supplierSkuCtrl;
  final TextEditingController technicalSpecCtrl;
  final TextEditingController storageLocationCtrl;
  final TextEditingController purchasePackageCtrl;
  final TextEditingController conversionFactorCtrl;
  final TextEditingController packageCostCtrl;
  final TextEditingController unitCostCtrl;

  const ProductHardwareAndSupplierFieldsSection({
    super.key,
    required this.isHardwareStore,
    required this.isService,
    required this.isCombo,
    required this.isNarrow,
    required this.unitLabel,
    required this.supplierSkuCtrl,
    required this.technicalSpecCtrl,
    required this.storageLocationCtrl,
    required this.purchasePackageCtrl,
    required this.conversionFactorCtrl,
    required this.packageCostCtrl,
    required this.unitCostCtrl,
  });

  @override
  State<ProductHardwareAndSupplierFieldsSection> createState() =>
      _ProductHardwareAndSupplierFieldsSectionState();
}

class _ProductHardwareAndSupplierFieldsSectionState
    extends State<ProductHardwareAndSupplierFieldsSection> {
  bool _showConversionPanel = false;
  bool _showRetailExtraDetails = false;

  static const List<String> _packagePresets = [
    'Rollo',
    'Caja',
    'Bolsa',
    'Pack',
    'Atado',
  ];

  @override
  void initState() {
    super.initState();
    _syncExpandedFlags();
  }

  @override
  void didUpdateWidget(
      covariant ProductHardwareAndSupplierFieldsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.purchasePackageCtrl.text !=
            widget.purchasePackageCtrl.text ||
        oldWidget.conversionFactorCtrl.text !=
            widget.conversionFactorCtrl.text ||
        oldWidget.storageLocationCtrl.text !=
            widget.storageLocationCtrl.text ||
        oldWidget.technicalSpecCtrl.text != widget.technicalSpecCtrl.text) {
      _syncExpandedFlags();
    }
  }

  void _syncExpandedFlags() {
    if (widget.purchasePackageCtrl.text.trim().isNotEmpty ||
        widget.conversionFactorCtrl.text.trim().isNotEmpty) {
      _showConversionPanel = true;
    }
    if (widget.storageLocationCtrl.text.trim().isNotEmpty ||
        widget.technicalSpecCtrl.text.trim().isNotEmpty) {
      _showRetailExtraDetails = true;
    }
  }

  double? _parseFactor() {
    final raw = widget.conversionFactorCtrl.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    final val = double.tryParse(raw);
    if (val == null || !val.isFinite || val <= 0) return null;
    return val;
  }

  void _recalculateUnitCostFromPackage() {
    final factor = _parseFactor();
    final pkgCost = ArsThousandsInputFormatter.tryParse(
      widget.packageCostCtrl.text,
    );
    if (factor != null && factor > 0 && pkgCost != null && pkgCost > 0) {
      final unitCost = (pkgCost / factor * 100).roundToDouble() / 100.0;
      final formatted = unitCost.toArsInput();
      if (widget.unitCostCtrl.text != formatted) {
        widget.unitCostCtrl.text = formatted;
      }
    }
    if (mounted) setState(() {});
  }

  Widget _buildSupplierSkuField() {
    return TextFormField(
      key: const ValueKey('product_supplier_sku_field'),
      controller: widget.supplierSkuCtrl,
      maxLength: 64,
      decoration: InputDecoration(
        labelText: 'Cód. Art. Proveedor',
        hintText: widget.isHardwareStore ? 'Ej: BRE-4021' : 'Ej: DIST-104',
        prefixIcon: const Icon(Icons.qr_code_2_outlined, size: 19),
        counterText: '',
        isDense: true,
      ),
    );
  }

  Widget _buildTechnicalSpecField() {
    return TextFormField(
      key: const ValueKey('product_technical_spec_field'),
      controller: widget.technicalSpecCtrl,
      maxLength: 120,
      decoration: InputDecoration(
        labelText: widget.isHardwareStore
            ? 'Medida / Especificación'
            : 'Presentación / Medida',
        hintText:
            widget.isHardwareStore ? 'Ej: 1/2" · 10mm · Cal. 18' : 'Ej: 500ml',
        prefixIcon: const Icon(Icons.straighten_outlined, size: 19),
        counterText: '',
        isDense: true,
      ),
    );
  }

  Widget _buildStorageLocationField() {
    return TextFormField(
      key: const ValueKey('product_storage_location_field'),
      controller: widget.storageLocationCtrl,
      maxLength: 120,
      decoration: InputDecoration(
        labelText: widget.isHardwareStore
            ? 'Ubicación / Estantería'
            : 'Góndola / Ubicación',
        hintText: widget.isHardwareStore
            ? 'Ej: Pasillo 2 - Gaveta B4'
            : 'Ej: Góndola 3',
        prefixIcon: const Icon(Icons.place_outlined, size: 19),
        counterText: '',
        isDense: true,
      ),
    );
  }

  Widget _buildConversionCard() {
    final factor = _parseFactor();
    final pkgName = widget.purchasePackageCtrl.text.trim();
    final unitCostVal = ArsThousandsInputFormatter.parse(widget.unitCostCtrl.text);
    final hasConfiguredConversion =
        pkgName.isNotEmpty || (factor != null && factor > 0);

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.swap_horiz_rounded,
                      size: 18, color: Color(0xFF0369A1)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      hasConfiguredConversion && factor != null
                          ? 'Compra por ${pkgName.isEmpty ? "Bulto" : pkgName} (×${factor.toQty()} ${widget.unitLabel})'
                          : 'Presentación de Compra y Conversión (Opcional)',
                      style: const TextStyle(
                        fontSize: 12.2,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0C4A6E),
                      ),
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: const Color(0xFF0369A1),
                ),
                onPressed: () =>
                    setState(() => _showConversionPanel = !_showConversionPanel),
                icon: Icon(
                  _showConversionPanel
                      ? Icons.expand_less_rounded
                      : Icons.tune_rounded,
                  size: 16,
                ),
                label: Text(
                  _showConversionPanel ? 'Ocultar' : 'Configurar bulto',
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (_showConversionPanel) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _packagePresets.map((preset) {
                final isSelected =
                    widget.purchasePackageCtrl.text.trim().toLowerCase() ==
                        preset.toLowerCase();
                return ChoiceChip(
                  label: Text(preset, style: const TextStyle(fontSize: 11)),
                  selected: isSelected,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (_) {
                    setState(() {
                      widget.purchasePackageCtrl.text =
                          isSelected ? '' : preset;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            if (widget.isNarrow)
              Column(
                children: [
                  TextFormField(
                    key: const ValueKey('product_purchase_package_field'),
                    controller: widget.purchasePackageCtrl,
                    maxLength: 40,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Bulto de compra (Ej: Rollo)',
                      counterText: '',
                      filled: true,
                      fillColor: Colors.white,
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const ValueKey('product_conversion_factor_field'),
                    controller: widget.conversionFactorCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    onChanged: (_) => _recalculateUnitCostFromPackage(),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final parsed =
                          double.tryParse(v.trim().replaceAll(',', '.'));
                      if (parsed == null || parsed <= 0) {
                        return 'Debe ser > 0';
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                      labelText: 'Contiene (${widget.unitLabel})',
                      hintText: 'Ej: 100',
                      filled: true,
                      fillColor: Colors.white,
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const ValueKey('product_package_cost_field'),
                    controller: widget.packageCostCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [const ArsThousandsInputFormatter()],
                    onChanged: (_) => _recalculateUnitCostFromPackage(),
                    decoration: const InputDecoration(
                      labelText: 'Costo del Bulto (Calc.)',
                      prefixText: '\$ ',
                      hintText: 'Opcional',
                      filled: true,
                      fillColor: Colors.white,
                      isDense: true,
                    ),
                  ),
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: TextFormField(
                      key: const ValueKey('product_purchase_package_field'),
                      controller: widget.purchasePackageCtrl,
                      maxLength: 40,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Presentación compra',
                        hintText: 'Ej: Rollo / Caja',
                        counterText: '',
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      key: const ValueKey('product_conversion_factor_field'),
                      controller: widget.conversionFactorCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      onChanged: (_) => _recalculateUnitCostFromPackage(),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final parsed =
                            double.tryParse(v.trim().replaceAll(',', '.'));
                        if (parsed == null || parsed <= 0) {
                          return 'Debe ser > 0';
                        }
                        return null;
                      },
                      decoration: InputDecoration(
                        labelText: 'Cant. (${widget.unitLabel})',
                        hintText: 'Ej: 100',
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: TextFormField(
                      key: const ValueKey('product_package_cost_field'),
                      controller: widget.packageCostCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [const ArsThousandsInputFormatter()],
                      onChanged: (_) => _recalculateUnitCostFromPackage(),
                      decoration: const InputDecoration(
                        labelText: 'Costo Bulto (Opc.)',
                        prefixText: '\$ ',
                        hintText: 'Divide costo',
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            if (factor != null && factor > 0) ...[
              const SizedBox(height: 6),
              Text(
                'Equivalencia: 1 ${pkgName.isEmpty ? "Bulto" : pkgName} = ${factor.toQty()} ${widget.unitLabel}'
                '${unitCostVal > 0 ? " → Costo unitario: \$${unitCostVal.toCurrency()} / ${widget.unitLabel}" : ""}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0369A1),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isService) {
      return const SizedBox.shrink();
    }

    if (widget.isHardwareStore) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.isNarrow) ...[
            _buildSupplierSkuField(),
            const SizedBox(height: 10),
            _buildTechnicalSpecField(),
            const SizedBox(height: 10),
            _buildStorageLocationField(),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _buildSupplierSkuField()),
                const SizedBox(width: 10),
                Expanded(flex: 4, child: _buildTechnicalSpecField()),
                const SizedBox(width: 10),
                Expanded(flex: 4, child: _buildStorageLocationField()),
              ],
            ),
          if (!widget.isCombo) _buildConversionCard(),
        ],
      );
    }

    // Retail: Cód. Proveedor siempre visible + opción plegable limpia para Góndola/Medida
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.isNarrow) ...[
          _buildSupplierSkuField(),
          if (_showRetailExtraDetails) ...[
            const SizedBox(height: 10),
            _buildStorageLocationField(),
            const SizedBox(height: 10),
            _buildTechnicalSpecField(),
          ],
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 5, child: _buildSupplierSkuField()),
              const SizedBox(width: 10),
              if (_showRetailExtraDetails) ...[
                Expanded(flex: 4, child: _buildStorageLocationField()),
                const SizedBox(width: 10),
                Expanded(flex: 4, child: _buildTechnicalSpecField()),
              ] else
                Expanded(
                  flex: 6,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () =>
                          setState(() => _showRetailExtraDetails = true),
                      icon: const Icon(Icons.add_location_alt_outlined,
                          size: 16),
                      label: const Text(
                        'Agregar góndola / presentación',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        if (widget.isNarrow && !_showRetailExtraDetails)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => setState(() => _showRetailExtraDetails = true),
              icon: const Icon(Icons.add_location_alt_outlined, size: 16),
              label: const Text(
                'Agregar góndola / presentación',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}
