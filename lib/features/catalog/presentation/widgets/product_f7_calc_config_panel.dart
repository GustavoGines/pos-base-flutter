import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/features/pos/domain/services/hardware_calculator_engine.dart';

class ProductF7CalcConfigPanel extends StatefulWidget {
  final Map<String, dynamic>? calcConfig;
  final ValueChanged<Map<String, dynamic>?> onChanged;
  final String? productNameHint;
  final ValueListenable<TextEditingValue>? productNameListenable;

  const ProductF7CalcConfigPanel({
    super.key,
    required this.calcConfig,
    required this.onChanged,
    this.productNameHint,
    this.productNameListenable,
  });

  @override
  State<ProductF7CalcConfigPanel> createState() =>
      _ProductF7CalcConfigPanelState();
}

class _ProductF7CalcConfigPanelState extends State<ProductF7CalcConfigPanel> {
  bool _isExpanded = false;
  String _selectedType = 'none'; // 'none' | 'wood' | 'roof' | 'paint'

  // Wood fields
  String _woodInchPreset = '4';
  final _woodNomCmCtrl = TextEditingController(text: '10.16');
  final _woodUseCmCtrl = TextEditingController(text: '8.8');
  final _woodLengthMCtrl = TextEditingController(text: '3');
  String _woodPricingMode = 'per_board';
  String _woodM2Basis = 'nominal';
  final _woodPackCtrl = TextEditingController(text: '10');
  bool _woodRoundToPack = false;
  final _woodWasteCtrl = TextEditingController(text: '10');

  // Roof fields
  final _roofNomMCtrl = TextEditingController(text: '1.1');
  final _roofUseMCtrl = TextEditingController(text: '1');
  final _roofLengthMCtrl = TextEditingController(text: '4.5');
  final _roofOverlapCmCtrl = TextEditingController(text: '20');
  String _roofPricingMode = 'per_sheet';

  // Paint fields
  final _paintYieldCtrl = TextEditingController(text: '10');
  String _paintYieldMode = 'per_coat';
  final _paintLitersCtrl = TextEditingController(text: '4');
  final _paintCoatsCtrl = TextEditingController(text: '2');

  @override
  void initState() {
    super.initState();
    widget.productNameListenable?.addListener(_onProductNameListenableChanged);
    _loadFromConfig(widget.calcConfig);
    if (widget.calcConfig != null && widget.calcConfig!.isNotEmpty) {
      _isExpanded = true;
    }
  }

  @override
  void didUpdateWidget(covariant ProductF7CalcConfigPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productNameListenable != widget.productNameListenable) {
      oldWidget.productNameListenable
          ?.removeListener(_onProductNameListenableChanged);
      widget.productNameListenable
          ?.addListener(_onProductNameListenableChanged);
    }
    if (widget.calcConfig == null && oldWidget.calcConfig != null) {
      _loadFromConfig(null);
      setState(() => _isExpanded = false);
    } else if (widget.calcConfig != null &&
        !mapEquals(oldWidget.calcConfig, widget.calcConfig)) {
      _loadFromConfig(widget.calcConfig);
    }
  }

  void _onProductNameListenableChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.productNameListenable
        ?.removeListener(_onProductNameListenableChanged);
    _woodNomCmCtrl.dispose();
    _woodUseCmCtrl.dispose();
    _woodLengthMCtrl.dispose();
    _woodPackCtrl.dispose();
    _woodWasteCtrl.dispose();
    _roofNomMCtrl.dispose();
    _roofUseMCtrl.dispose();
    _roofLengthMCtrl.dispose();
    _roofOverlapCmCtrl.dispose();
    _paintYieldCtrl.dispose();
    _paintLitersCtrl.dispose();
    _paintCoatsCtrl.dispose();
    super.dispose();
  }

  double _toDouble(dynamic val, double fallback) {
    if (val is num) return val.toDouble();
    if (val != null) {
      return double.tryParse(val.toString().replaceAll(',', '.')) ?? fallback;
    }
    return fallback;
  }

  String _fmtNum(double val, {int decimals = 2}) {
    if ((val - val.roundToDouble()).abs() < 0.001) {
      return val.round().toString();
    }
    return val
        .toStringAsFixed(decimals)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  double _parseCtrl(TextEditingController c, double fallback) {
    return double.tryParse(c.text.trim().replaceAll(',', '.')) ?? fallback;
  }

  void _loadFromConfig(Map<String, dynamic>? cfg) {
    if (cfg == null || cfg.isEmpty) {
      _selectedType = 'none';
      return;
    }
    final type = cfg['type']?.toString() ?? 'wood';
    if (type == 'roof') {
      _selectedType = 'roof';
      _roofNomMCtrl.text = _fmtNum(_toDouble(cfg['nominal_width_m'], 1.10));
      _roofUseMCtrl.text = _fmtNum(_toDouble(cfg['useful_width_m'], 1.00));
      _roofLengthMCtrl.text = _fmtNum(_toDouble(cfg['length_m'], 4.50));
      _roofOverlapCmCtrl.text =
          _fmtNum(_toDouble(cfg['longitudinal_overlap_m'], 0.20) * 100, decimals: 0);
      final pm = cfg['pricing_mode']?.toString() ?? 'per_sheet';
      _roofPricingMode = const ['per_sheet', 'per_linear_meter', 'per_m2']
              .contains(pm)
          ? pm
          : 'per_sheet';
    } else if (type == 'paint') {
      _selectedType = 'paint';
      _paintYieldCtrl.text =
          _fmtNum(_toDouble(cfg['yield_m2_per_liter'], 10.0));
      _paintLitersCtrl.text =
          _fmtNum(_toDouble(cfg['container_liters'], 4.0));
      _paintCoatsCtrl.text =
          ((cfg['default_coats'] as num?)?.toInt() ?? 2).clamp(1, 20).toString();
      final ym = cfg['yield_mode']?.toString() ?? 'per_coat';
      _paintYieldMode = ym == 'final_total' ? 'final_total' : 'per_coat';
    } else {
      _selectedType = 'wood';
      final preset = cfg['inch_preset']?.toString() ?? '4';
      final isKnownPreset = HardwareCalculatorEngine.woodInchPresets
              .any((p) => p.key == preset) ||
          preset == 'custom';
      _woodInchPreset = isKnownPreset ? preset : 'custom';
      _woodNomCmCtrl.text =
          _fmtNum(_toDouble(cfg['nominal_width_m'], 0.1016) * 100);
      _woodUseCmCtrl.text =
          _fmtNum(_toDouble(cfg['useful_width_m'], 0.088) * 100);
      _woodLengthMCtrl.text = _fmtNum(_toDouble(cfg['length_m'], 3.00));
      final pm = cfg['pricing_mode']?.toString() ?? 'per_board';
      _woodPricingMode = const [
        'per_board',
        'per_pack',
        'per_linear_meter',
        'per_m2',
      ].contains(pm)
          ? pm
          : 'per_board';
      final basis = cfg['m2_billing_basis']?.toString() ?? 'nominal';
      _woodM2Basis = basis == 'useful' ? 'useful' : 'nominal';
      _woodPackCtrl.text =
          ((cfg['boards_per_pack'] as num?)?.toInt() ?? 10).toString();
      _woodRoundToPack = cfg['round_to_full_pack'] == true;
      _woodWasteCtrl.text =
          _fmtNum(_toDouble(cfg['default_waste_pct'], 10.0), decimals: 1);
    }
  }

  void _emitSnapshot() {
    if (_selectedType == 'none') {
      widget.onChanged(null);
      return;
    }
    if (_selectedType == 'wood') {
      final nomM = (_parseCtrl(_woodNomCmCtrl, 10.16) / 100.0).clamp(0.001, 50.0);
      final useM = (_parseCtrl(_woodUseCmCtrl, 8.8) / 100.0).clamp(0.001, nomM);
      final lenM = _parseCtrl(_woodLengthMCtrl, 3.00).clamp(0.05, 50.0);
      final pack =
          (int.tryParse(_woodPackCtrl.text.trim()) ?? 10).clamp(1, 500);
      final waste = _parseCtrl(_woodWasteCtrl, 10.0).clamp(0.0, 100.0);
      widget.onChanged({
        'type': 'wood',
        'inch_preset': _woodInchPreset,
        'nominal_width_m': nomM,
        'useful_width_m': useM,
        'length_m': lenM,
        'pricing_mode': _woodPricingMode,
        'm2_billing_basis': _woodM2Basis,
        'boards_per_pack': pack,
        'round_to_full_pack': _woodRoundToPack,
        'default_waste_pct': waste,
      });
      return;
    }
    if (_selectedType == 'roof') {
      final nomM = _parseCtrl(_roofNomMCtrl, 1.10).clamp(0.001, 50.0);
      final useM = _parseCtrl(_roofUseMCtrl, 1.00).clamp(0.001, nomM);
      final lenM = _parseCtrl(_roofLengthMCtrl, 4.50).clamp(0.05, 50.0);
      final overlapM = (_parseCtrl(_roofOverlapCmCtrl, 20.0) / 100.0)
          .clamp(0.0, (lenM - 0.01).clamp(0.0, 5.0));
      widget.onChanged({
        'type': 'roof',
        'nominal_width_m': nomM,
        'useful_width_m': useM,
        'length_m': lenM,
        'longitudinal_overlap_m': overlapM,
        'pricing_mode': _roofPricingMode,
      });
      return;
    }
    if (_selectedType == 'paint') {
      final yld = _parseCtrl(_paintYieldCtrl, 10.0).clamp(0.05, 500.0);
      final cap = _parseCtrl(_paintLitersCtrl, 4.0).clamp(0.05, 1000.0);
      final coats =
          (int.tryParse(_paintCoatsCtrl.text.trim()) ?? 2).clamp(1, 20);
      widget.onChanged({
        'type': 'paint',
        'yield_m2_per_liter': yld,
        'yield_mode': _paintYieldMode,
        'container_liters': cap,
        'default_coats': coats,
        'default_waste_pct': 0.0,
      });
    }
  }

  void _applyWoodPreset(String presetKey) {
    setState(() {
      _woodInchPreset = presetKey;
      final preset = HardwareCalculatorEngine.woodInchPresets
          .where((p) => p.key == presetKey)
          .firstOrNull;
      if (preset != null) {
        _woodNomCmCtrl.text = _fmtNum(preset.nominalWidthM * 100);
        _woodUseCmCtrl.text = _fmtNum(preset.usefulWidthM * 100);
      }
    });
    _emitSnapshot();
  }

  String get _resolvedProductName {
    final fromListenable = widget.productNameListenable?.value.text.trim();
    if (fromListenable != null && fromListenable.isNotEmpty) {
      return fromListenable;
    }
    return widget.productNameHint?.trim() ?? '';
  }

  void _autoDetectFromName() {
    final name = _resolvedProductName;
    if (name.isEmpty) {
      if (mounted) {
        SnackBarService.info(
          context,
          'Escribí primero el nombre del artículo (ej: Machimbre 1/2 x 4 x 3.00m) para auto-detectar sus medidas.',
        );
      }
      return;
    }
    final inferred = HardwareCalculatorEngine.inferConfigFromName(name);
    setState(() {
      _isExpanded = true;
      _loadFromConfig(inferred);
    });
    _emitSnapshot();
  }

  String _activeTypeBadge() {
    switch (_selectedType) {
      case 'wood':
        return 'Machimbre / Maderas';
      case 'roof':
        return 'Chapas / Techos';
      case 'paint':
        return 'Pintura / Membrana';
      default:
        return 'Sin configurar';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConfigured = _selectedType != 'none';
    final hasNameHint = _resolvedProductName.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isConfigured
            ? const Color(0xFFF0FDF4)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isConfigured
              ? const Color(0xFF86EFAC)
              : const Color(0xFFE2E8F0),
        ),
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
                  Icon(
                    Icons.straighten_rounded,
                    size: 18,
                    color: isConfigured
                        ? const Color(0xFF0F766E)
                        : const Color(0xFF475569),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      isConfigured
                          ? 'Calculadora F7 · ${_activeTypeBadge()}'
                          : 'Calculadora Rápida F7 (Maderas / Chapas / Pintura)',
                      style: TextStyle(
                        fontSize: 12.2,
                        fontWeight: FontWeight.w700,
                        color: isConfigured
                            ? const Color(0xFF0F766E)
                            : const Color(0xFF334155),
                      ),
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: const Color(0xFF0F766E),
                ),
                onPressed: () => setState(() => _isExpanded = !_isExpanded),
                icon: Icon(
                  _isExpanded
                      ? Icons.expand_less_rounded
                      : Icons.calculate_outlined,
                  size: 16,
                ),
                label: Text(
                  _isExpanded
                      ? 'Ocultar'
                      : (isConfigured ? 'Editar F7' : 'Configurar F7'),
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (_isExpanded) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('f7_type_$_selectedType'),
                    initialValue: _selectedType,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de cálculo en mostrador',
                      filled: true,
                      fillColor: Colors.white,
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'none',
                        child: Text('Sin calculadora específica'),
                      ),
                      DropdownMenuItem(
                        value: 'wood',
                        child: Text('Madera / Machimbre / Deck'),
                      ),
                      DropdownMenuItem(
                        value: 'roof',
                        child: Text('Chapa / Techo'),
                      ),
                      DropdownMenuItem(
                        value: 'paint',
                        child: Text('Pintura / Membrana Líquida'),
                      ),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedType = val ?? 'none';
                      });
                      _emitSnapshot();
                    },
                  ),
                ),
                if (hasNameHint)
                  OutlinedButton.icon(
                    key: const ValueKey('f7_auto_detect_btn'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: const Color(0xFF0F766E),
                      side: const BorderSide(color: Color(0xFF5EEAD4)),
                      backgroundColor: Colors.white,
                    ),
                    onPressed: _autoDetectFromName,
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 15),
                    label: const Text(
                      'Auto-detectar medidas',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
              ],
            ),
            if (_selectedType == 'wood') ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ...HardwareCalculatorEngine.woodInchPresets.map(
                    (preset) => ChoiceChip(
                      label: Text('${preset.key}"',
                          style: const TextStyle(fontSize: 11)),
                      selected: _woodInchPreset == preset.key,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => _applyWoodPreset(preset.key),
                    ),
                  ),
                  ChoiceChip(
                    label:
                        const Text('Otro', style: TextStyle(fontSize: 11)),
                    selected: _woodInchPreset == 'custom',
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) {
                      setState(() => _woodInchPreset = 'custom');
                      _emitSnapshot();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _woodNomCmCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) {
                        _woodInchPreset = 'custom';
                        _emitSnapshot();
                      },
                      decoration: const InputDecoration(
                        labelText: 'Ancho nominal (cm)',
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _woodUseCmCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) {
                        _woodInchPreset = 'custom';
                        _emitSnapshot();
                      },
                      validator: (_) {
                        final nom = _parseCtrl(_woodNomCmCtrl, 10.16);
                        final use = _parseCtrl(_woodUseCmCtrl, 8.8);
                        if (use > nom + 0.001) {
                          return 'No > nominal';
                        }
                        return null;
                      },
                      decoration: const InputDecoration(
                        labelText: 'Ancho útil (cm)',
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _woodLengthMCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _emitSnapshot(),
                      decoration: const InputDecoration(
                        labelText: 'Largo tabla (m)',
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('wood_pm_$_woodPricingMode'),
                      initialValue: _woodPricingMode,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Precio cargado por',
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'per_board', child: Text('Tabla individual')),
                        DropdownMenuItem(
                            value: 'per_m2', child: Text('Metro cuadrado (m²)')),
                        DropdownMenuItem(
                            value: 'per_linear_meter',
                            child: Text('Metro lineal (ml)')),
                        DropdownMenuItem(
                            value: 'per_pack', child: Text('Paquete cerrado')),
                      ],
                      onChanged: (v) {
                        setState(() => _woodPricingMode = v ?? 'per_board');
                        _emitSnapshot();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _woodPackCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => _emitSnapshot(),
                      decoration: const InputDecoration(
                        labelText: 'Tablas/paq.',
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
                      controller: _woodWasteCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _emitSnapshot(),
                      decoration: const InputDecoration(
                        labelText: '% Desperd.',
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (_selectedType == 'roof') ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _roofNomMCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _emitSnapshot(),
                      decoration: const InputDecoration(
                        labelText: 'Ancho total (m)',
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _roofUseMCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _emitSnapshot(),
                      validator: (_) {
                        final nom = _parseCtrl(_roofNomMCtrl, 1.10);
                        final use = _parseCtrl(_roofUseMCtrl, 1.00);
                        if (use > nom + 0.001) {
                          return 'No > total';
                        }
                        return null;
                      },
                      decoration: const InputDecoration(
                        labelText: 'Ancho útil (m)',
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _roofLengthMCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _emitSnapshot(),
                      decoration: const InputDecoration(
                        labelText: 'Largo chapa (m)',
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 6,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('roof_pm_$_roofPricingMode'),
                      initialValue: _roofPricingMode,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Precio cargado por',
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'per_sheet', child: Text('Chapa individual')),
                        DropdownMenuItem(
                            value: 'per_linear_meter',
                            child: Text('Metro lineal (ml)')),
                        DropdownMenuItem(
                            value: 'per_m2', child: Text('Metro cuadrado (m²)')),
                      ],
                      onChanged: (v) {
                        setState(() => _roofPricingMode = v ?? 'per_sheet');
                        _emitSnapshot();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: TextFormField(
                      controller: _roofOverlapCmCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _emitSnapshot(),
                      decoration: const InputDecoration(
                        labelText: 'Solape largo (cm)',
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (_selectedType == 'paint') ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _paintLitersCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _emitSnapshot(),
                      decoration: const InputDecoration(
                        labelText: 'Envase (L o Kg)',
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _paintYieldCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _emitSnapshot(),
                      decoration: const InputDecoration(
                        labelText: 'Rendimiento (m²/L)',
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _paintCoatsCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => _emitSnapshot(),
                      decoration: const InputDecoration(
                        labelText: 'Manos por defecto',
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey('paint_ym_$_paintYieldMode'),
                initialValue: _paintYieldMode,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Criterio de rendimiento',
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'per_coat',
                    child: Text('Por mano (L = m² × manos / rendimiento)'),
                  ),
                  DropdownMenuItem(
                    value: 'final_total',
                    child: Text('Trabajo terminado (membrana líquida)'),
                  ),
                ],
                onChanged: (v) {
                  setState(() => _paintYieldMode = v ?? 'per_coat');
                  _emitSnapshot();
                },
              ),
            ],
          ],
        ],
      ),
    );
  }
}
