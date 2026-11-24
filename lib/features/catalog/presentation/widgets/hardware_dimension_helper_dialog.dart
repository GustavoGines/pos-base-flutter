import 'package:flutter/material.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/features/pos/domain/services/hardware_calculator_engine.dart';

/// Resultado devuelto por el asistente rápido de medidas ferreteras (`📏`).
class HardwareDimensionSelection {
  final String specText;
  final Map<String, dynamic> calcConfig;

  const HardwareDimensionSelection({
    required this.specText,
    required this.calcConfig,
  });
}

/// Asistente compacto para armar medidas de Maderas (`Grosor × Ancho × Largo`)
/// o Chapas (`Ancho × Largo`) generando tanto la especificación legible como
/// el JSON `calc_config` listo para la Calculadora F7.
class HardwareDimensionHelperDialog extends StatefulWidget {
  final String initialName;
  final String initialSpec;
  final Map<String, dynamic>? initialConfig;

  const HardwareDimensionHelperDialog({
    super.key,
    this.initialName = '',
    this.initialSpec = '',
    this.initialConfig,
  });

  static Future<HardwareDimensionSelection?> show(
    BuildContext context, {
    String initialName = '',
    String initialSpec = '',
    Map<String, dynamic>? initialConfig,
  }) {
    return showDialog<HardwareDimensionSelection>(
      context: context,
      builder: (_) => HardwareDimensionHelperDialog(
        initialName: initialName,
        initialSpec: initialSpec,
        initialConfig: initialConfig,
      ),
    );
  }

  @override
  State<HardwareDimensionHelperDialog> createState() =>
      _HardwareDimensionHelperDialogState();
}

class _HardwareDimensionHelperDialogState
    extends State<HardwareDimensionHelperDialog> {
  static const List<String> _thicknessOptions = [
    '1/2"',
    '3/4"',
    '1"',
    '1 1/2"',
    '2"',
    '3"',
    '4"',
  ];

  static const List<double> _woodLengthPresets = [
    1.5,
    2.0,
    2.1,
    2.4,
    3.0,
    3.6,
    4.0,
    4.5,
    5.0,
    6.0,
  ];

  static const List<double> _roofLengthPresets = [
    3.0,
    3.5,
    4.0,
    4.5,
    5.0,
    6.0,
  ];

  String _mode = 'wood'; // 'wood' | 'roof'

  // Wood state
  String? _thickness = '1"';
  String _woodInch = '4';
  final TextEditingController _woodCustomNomCmCtrl =
      TextEditingController(text: '10.16');
  final TextEditingController _woodCustomUseCmCtrl =
      TextEditingController(text: '8.8');
  final TextEditingController _woodLengthCtrl = TextEditingController(text: '4');
  String _woodPricingMode = 'per_board';

  // Roof state
  final TextEditingController _roofNomMCtrl =
      TextEditingController(text: '1.10');
  final TextEditingController _roofUseMCtrl =
      TextEditingController(text: '1.00');
  final TextEditingController _roofLengthCtrl =
      TextEditingController(text: '4.50');
  String _roofPricingMode = 'per_sheet';

  @override
  void initState() {
    super.initState();
    _initFromInputs();
  }

  void _initFromInputs() {
    final cfg = widget.initialConfig;
    final detected = HardwareCalculatorEngine.analyzeProductText(
      name: widget.initialName,
      technicalSpec: widget.initialSpec,
    );

    if (detected.detectedThicknessLabel != null) {
      final rawThick = detected.detectedThicknessLabel!.trim();
      final mappedThick = rawThick == '1.5"' ? '1 1/2"' : rawThick;
      if (_thicknessOptions.contains(mappedThick)) {
        _thickness = mappedThick;
      }
    }

    final effectiveCfg =
        (cfg != null && cfg.isNotEmpty) ? cfg : detected.config;
    final type = effectiveCfg['type']?.toString() ?? 'wood';

    if (type == 'roof') {
      _mode = 'roof';
      _roofNomMCtrl.text =
          _fmtNum(_toDouble(effectiveCfg['nominal_width_m'], 1.10));
      _roofUseMCtrl.text =
          _fmtNum(_toDouble(effectiveCfg['useful_width_m'], 1.00));
      _roofLengthCtrl.text =
          _fmtNum(_toDouble(effectiveCfg['length_m'], 4.50));
      final pm = effectiveCfg['pricing_mode']?.toString() ?? 'per_sheet';
      _roofPricingMode = const ['per_sheet', 'per_linear_meter', 'per_m2']
              .contains(pm)
          ? pm
          : 'per_sheet';
    } else {
      _mode = 'wood';
      final presetKey = effectiveCfg['inch_preset']?.toString() ?? '4';
      final known = HardwareCalculatorEngine.woodInchPresets
          .any((p) => p.key == presetKey);
      _woodInch = known ? presetKey : 'custom';
      _woodCustomNomCmCtrl.text =
          _fmtNum(_toDouble(effectiveCfg['nominal_width_m'], 0.1016) * 100);
      _woodCustomUseCmCtrl.text =
          _fmtNum(_toDouble(effectiveCfg['useful_width_m'], 0.088) * 100);
      _woodLengthCtrl.text =
          _fmtNum(_toDouble(effectiveCfg['length_m'], 3.00));
      final pm = effectiveCfg['pricing_mode']?.toString() ?? 'per_board';
      _woodPricingMode = const [
        'per_board',
        'per_pack',
        'per_linear_meter',
        'per_m2',
      ].contains(pm)
          ? pm
          : 'per_board';
    }
  }

  @override
  void dispose() {
    _woodCustomNomCmCtrl.dispose();
    _woodCustomUseCmCtrl.dispose();
    _woodLengthCtrl.dispose();
    _roofNomMCtrl.dispose();
    _roofUseMCtrl.dispose();
    _roofLengthCtrl.dispose();
    super.dispose();
  }

  double _toDouble(dynamic val, double fallback) {
    if (val is num) return val.toDouble();
    if (val != null) {
      return double.tryParse(val.toString().replaceAll(',', '.')) ?? fallback;
    }
    return fallback;
  }

  double _parseCtrl(TextEditingController c, double fallback) {
    return double.tryParse(c.text.trim().replaceAll(',', '.')) ?? fallback;
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

  HardwareDimensionSelection _buildSelection() {
    if (_mode == 'roof') {
      final nomM = _parseCtrl(_roofNomMCtrl, 1.10).clamp(0.05, 50.0);
      final useM = _parseCtrl(_roofUseMCtrl, 1.00).clamp(0.05, nomM);
      final lenM = _parseCtrl(_roofLengthCtrl, 4.50).clamp(0.10, 50.0);
      final spec = '${nomM.toStringAsFixed(2)}m × ${lenM.toStringAsFixed(2)}m';
      return HardwareDimensionSelection(
        specText: spec,
        calcConfig: {
          'type': 'roof',
          'nominal_width_m': nomM,
          'useful_width_m': useM,
          'length_m': lenM,
          'longitudinal_overlap_m': 0.20,
          'pricing_mode': _roofPricingMode,
        },
      );
    }

    final preset = HardwareCalculatorEngine.woodInchPresets
        .where((p) => p.key == _woodInch)
        .firstOrNull;
    final double nomM;
    final double useM;
    final String widthLabel;
    if (preset != null) {
      nomM = preset.nominalWidthM;
      useM = preset.usefulWidthM;
      widthLabel = '${preset.key}"';
    } else {
      final nomCm = _parseCtrl(_woodCustomNomCmCtrl, 10.16).clamp(0.5, 500.0);
      final useCm = _parseCtrl(_woodCustomUseCmCtrl, 8.8).clamp(0.5, nomCm);
      nomM = nomCm / 100.0;
      useM = useCm / 100.0;
      widthLabel = '${_fmtNum(nomCm)}cm';
    }
    final lenM = _parseCtrl(_woodLengthCtrl, 3.00).clamp(0.10, 50.0);
    final lenLabel = '${lenM.toStringAsFixed(2)}m';
    final specText = _thickness != null && _thickness!.trim().isNotEmpty
        ? '${_thickness!.trim()} × $widthLabel × $lenLabel'
        : '$widthLabel × $lenLabel';

    return HardwareDimensionSelection(
      specText: specText,
      calcConfig: {
        'type': 'wood',
        'inch_preset': _woodInch,
        'nominal_width_m': nomM,
        'useful_width_m': useM,
        'length_m': lenM,
        'pricing_mode': _woodPricingMode,
        'm2_billing_basis': 'nominal',
        'boards_per_pack': 10,
        'round_to_full_pack': false,
        'default_waste_pct': 10.0,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _buildSelection();
    final nomCmPreview =
        ((preview.calcConfig['nominal_width_m'] as double? ?? 0.1016) * 100);
    final useCmPreview =
        ((preview.calcConfig['useful_width_m'] as double? ?? 0.088) * 100);

    return AppModalShell(
      title: 'Armar Medida Técnica (F7)',
      subtitle: 'Estandariza Grosor × Ancho × Largo y deja lista la Calculadora F7',
      icon: Icons.straighten_rounded,
      accent: AppModalAccent.teal,
      maxWidth: 560,
      maxHeight: 680,
      onClose: () => Navigator.of(context).pop(),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'wood',
                  icon: Icon(Icons.forest_outlined, size: 16),
                  label: Text('Madera / Machimbre'),
                ),
                ButtonSegment<String>(
                  value: 'roof',
                  icon: Icon(Icons.roofing_rounded, size: 16),
                  label: Text('Chapa / Techo'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (sel) => setState(() => _mode = sel.first),
            ),
            const SizedBox(height: 12),
            if (_mode == 'wood') ...[
              const Text(
                '1. Grosor / Espesor (opcional):',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Sin esp.', style: TextStyle(fontSize: 11.5)),
                    selected: _thickness == null,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _thickness = null),
                  ),
                  ..._thicknessOptions.map(
                    (t) => ChoiceChip(
                      key: ValueKey('dim_helper_thick_$t'),
                      label: Text(t, style: const TextStyle(fontSize: 11.5)),
                      selected: _thickness == t,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _thickness = t),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                '2. Ancho de la tabla (para cálculo de m²):',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ...HardwareCalculatorEngine.woodInchPresets.map(
                    (p) => ChoiceChip(
                      key: ValueKey('dim_helper_inch_${p.key}'),
                      label: Text('${p.key}"',
                          style: const TextStyle(fontSize: 11.5)),
                      selected: _woodInch == p.key,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() {
                        _woodInch = p.key;
                        _woodCustomNomCmCtrl.text =
                            _fmtNum(p.nominalWidthM * 100);
                        _woodCustomUseCmCtrl.text =
                            _fmtNum(p.usefulWidthM * 100);
                      }),
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('Otro', style: TextStyle(fontSize: 11.5)),
                    selected: _woodInch == 'custom',
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _woodInch = 'custom'),
                  ),
                ],
              ),
              if (_woodInch == 'custom') ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _woodCustomNomCmCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Ancho nominal (cm)',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _woodCustomUseCmCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Ancho útil (cm)',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                '3. Largo de la tabla (metros):',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _woodLengthPresets.map((len) {
                  final current = _parseCtrl(_woodLengthCtrl, 3.0);
                  final selected = (current - len).abs() < 0.01;
                  return ChoiceChip(
                    key: ValueKey('dim_helper_len_${_fmtNum(len)}'),
                    label: Text('${_fmtNum(len)}m',
                        style: const TextStyle(fontSize: 11.5)),
                    selected: selected,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() {
                      _woodLengthCtrl.text = _fmtNum(len);
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: TextFormField(
                      key: const ValueKey('dim_helper_wood_length_field'),
                      controller: _woodLengthCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Largo exacto (m)',
                        suffixText: 'm',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 6,
                    child: DropdownButtonFormField<String>(
                      initialValue: _woodPricingMode,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Precio cargado por',
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
                      onChanged: (v) => setState(
                          () => _woodPricingMode = v ?? 'per_board'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _roofNomMCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Ancho total (m)',
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
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Ancho útil (m)',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Largo de la chapa (metros):',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _roofLengthPresets.map((len) {
                  final current = _parseCtrl(_roofLengthCtrl, 4.5);
                  final selected = (current - len).abs() < 0.01;
                  return ChoiceChip(
                    label: Text('${_fmtNum(len)}m',
                        style: const TextStyle(fontSize: 11.5)),
                    selected: selected,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() {
                      _roofLengthCtrl.text = _fmtNum(len);
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: TextFormField(
                      controller: _roofLengthCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Largo exacto (m)',
                        suffixText: 'm',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 6,
                    child: DropdownButtonFormField<String>(
                      initialValue: _roofPricingMode,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Precio cargado por',
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
                      onChanged: (v) => setState(
                          () => _roofPricingMode = v ?? 'per_sheet'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDFA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF99F6E4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Medida a guardar: ${preview.specText}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                  if (_mode == 'wood') ...[
                    const SizedBox(height: 2),
                    Text(
                      'F7: Ancho ${_fmtNum(nomCmPreview)} cm nom. (${_fmtNum(useCmPreview)} cm útil) × ${_fmtNum(_parseCtrl(_woodLengthCtrl, 3.0))}m',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF115E59),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      footerActions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          key: const ValueKey('dim_helper_apply_btn'),
          onPressed: () => Navigator.of(context).pop(preview),
          icon: const Icon(Icons.check_rounded, size: 17),
          label: const Text('Aplicar Medida'),
        ),
      ],
    );
  }
}
