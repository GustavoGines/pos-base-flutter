import 'package:flutter/material.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';

/// Asistente rápido de Talles y Colores (`👕`) para Indumentaria / Ropería / Calzado.
/// Devuelve una cadena limpia con separador ASCII `' - '` (ej. `"Talle XL - Negro"`,
/// `"Talle Único - Blanco"`, `"Calz. 40 - Negro"`), manteniendo el campo destino 100% editable.
class ApparelVariantHelperDialog extends StatefulWidget {
  final String initialValue;

  const ApparelVariantHelperDialog({
    super.key,
    this.initialValue = '',
  });

  static Future<String?> show(
    BuildContext context, {
    String initialValue = '',
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => ApparelVariantHelperDialog(initialValue: initialValue),
    );
  }

  @override
  State<ApparelVariantHelperDialog> createState() =>
      _ApparelVariantHelperDialogState();
}

class _ApparelVariantHelperDialogState
    extends State<ApparelVariantHelperDialog> {
  static const List<String> _letterSizes = [
    'Único',
    'XS',
    'S',
    'M',
    'L',
    'XL',
    'XXL',
    'XXXL',
  ];

  static const List<String> _numericSizes = [
    '36',
    '38',
    '40',
    '42',
    '44',
    '46',
    '48',
    '50',
    '52',
    '54',
  ];

  static const List<String> _footwearSizes = [
    '35',
    '36',
    '37',
    '38',
    '39',
    '40',
    '41',
    '42',
    '43',
    '44',
    '45',
  ];

  static const List<String> _kidsSizes = [
    '2',
    '4',
    '6',
    '8',
    '10',
    '12',
    '14',
    '16',
  ];

  static const List<String> _colorPresets = [
    'Negro',
    'Blanco',
    'Azul',
    'Azul Marino',
    'Gris',
    'Beige',
    'Rojo',
    'Verde',
    'Rosa',
    'Celeste',
    'Bordó',
    'Marrón',
    'Estampado',
  ];

  String _mode = 'letras'; // 'letras' | 'pantalon' | 'calzado' | 'infantil'
  final TextEditingController _sizeCtrl = TextEditingController();
  final TextEditingController _colorCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initFromInitialValue();
  }

  void _initFromInitialValue() {
    final raw = widget.initialValue.trim();
    if (raw.isEmpty) return;

    final parts = raw
        .split(RegExp(r'\s*[-·/]\s*'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    for (final part in parts) {
      final lower = part.toLowerCase();
      if (lower.startsWith('calz')) {
        _mode = 'calzado';
        final cleaned =
            part.replaceFirst(RegExp(r'^calz(?:ado|\.)?\s*', caseSensitive: false), '').trim();
        if (_sizeCtrl.text.isEmpty && cleaned.isNotEmpty) {
          _sizeCtrl.text = cleaned;
        }
        continue;
      }
      if (lower.startsWith('talle')) {
        final cleaned =
            part.replaceFirst(RegExp(r'^talle\s*', caseSensitive: false), '').trim();
        if (_sizeCtrl.text.isEmpty && cleaned.isNotEmpty) {
          _sizeCtrl.text = cleaned;
          _inferModeForSize(cleaned);
        }
        continue;
      }
      if (_isKnownSize(part)) {
        if (_sizeCtrl.text.isEmpty) {
          _sizeCtrl.text = part;
          _inferModeForSize(part);
        }
      } else if (_colorCtrl.text.isEmpty) {
        _colorCtrl.text = part;
      }
    }
  }

  bool _isKnownSize(String val) {
    final clean = val.trim().toUpperCase();
    return _letterSizes.any((s) => s.toUpperCase() == clean) ||
        _numericSizes.contains(val.trim()) ||
        _footwearSizes.contains(val.trim()) ||
        _kidsSizes.contains(val.trim());
  }

  void _inferModeForSize(String size) {
    final clean = size.trim().toUpperCase();
    if (_letterSizes.any((s) => s.toUpperCase() == clean)) {
      _mode = 'letras';
    } else if (_kidsSizes.contains(size.trim())) {
      _mode = 'infantil';
    } else if (_footwearSizes.contains(size.trim()) &&
        !_numericSizes.contains(size.trim())) {
      _mode = 'calzado';
    } else if (_numericSizes.contains(size.trim())) {
      _mode = 'pantalon';
    }
  }

  @override
  void dispose() {
    _sizeCtrl.dispose();
    _colorCtrl.dispose();
    super.dispose();
  }

  List<String> get _currentSizes {
    switch (_mode) {
      case 'pantalon':
        return _numericSizes;
      case 'calzado':
        return _footwearSizes;
      case 'infantil':
        return _kidsSizes;
      case 'letras':
      default:
        return _letterSizes;
    }
  }

  String _formatSizeToken(String rawSize) {
    final clean = rawSize.trim();
    if (clean.isEmpty) return '';
    if (RegExp(r'^(talle|calz)', caseSensitive: false).hasMatch(clean)) {
      return clean;
    }
    if (_mode == 'calzado') {
      return 'Calz. $clean';
    }
    return 'Talle $clean';
  }

  String _buildPreview() {
    final sizeToken = _formatSizeToken(_sizeCtrl.text);
    final colorToken = _colorCtrl.text.trim();
    return [
      if (sizeToken.isNotEmpty) sizeToken,
      if (colorToken.isNotEmpty) colorToken,
    ].join(' - ');
  }

  @override
  Widget build(BuildContext context) {
    final preview = _buildPreview();
    final selectedSizeNorm = _sizeCtrl.text.trim().toLowerCase();
    final selectedColorNorm = _colorCtrl.text.trim().toLowerCase();

    return AppModalShell(
      title: 'Armar Talle y Color',
      subtitle: 'Seleccioná chips o escribí libremente tu variante',
      icon: Icons.checkroom_rounded,
      accent: AppModalAccent.indigo,
      maxWidth: 560,
      onClose: () => Navigator.of(context).pop(),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'letras',
                  label: Text('Letras / Único', style: TextStyle(fontSize: 12)),
                ),
                ButtonSegment<String>(
                  value: 'pantalon',
                  label: Text('36–54', style: TextStyle(fontSize: 12)),
                ),
                ButtonSegment<String>(
                  value: 'calzado',
                  label: Text('Calzado 35–45', style: TextStyle(fontSize: 12)),
                ),
                ButtonSegment<String>(
                  value: 'infantil',
                  label: Text('Infantil 2–16', style: TextStyle(fontSize: 12)),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (sel) => setState(() => _mode = sel.first),
            ),
            const SizedBox(height: 12),
            const Text(
              '1. Talle / Numeración:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('Sin talle', style: TextStyle(fontSize: 11.5)),
                  selected: selectedSizeNorm.isEmpty,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _sizeCtrl.clear()),
                ),
                ..._currentSizes.map((s) {
                  final selected = selectedSizeNorm == s.toLowerCase();
                  return ChoiceChip(
                    key: ValueKey('apparel_size_$s'),
                    label: Text(s, style: const TextStyle(fontSize: 11.5)),
                    selected: selected,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _sizeCtrl.text = s),
                  );
                }),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('apparel_custom_size_field'),
              controller: _sizeCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Talle personalizado (opcional)',
                hintText: 'Ej: XL, 42, Único, XXL...',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '2. Color / Estampa:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('Sin color', style: TextStyle(fontSize: 11.5)),
                  selected: selectedColorNorm.isEmpty,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _colorCtrl.clear()),
                ),
                ..._colorPresets.map((c) {
                  final selected = selectedColorNorm == c.toLowerCase();
                  return ChoiceChip(
                    key: ValueKey('apparel_color_$c'),
                    label: Text(c, style: const TextStyle(fontSize: 11.5)),
                    selected: selected,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _colorCtrl.text = c),
                  );
                }),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('apparel_custom_color_field'),
              controller: _colorCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Color / Diseño personalizado (opcional)',
                hintText: 'Ej: Negro, Azul Francia, Rayado...',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFC7D2FE)),
              ),
              child: Text(
                preview.isEmpty
                    ? 'Elegí un talle o color (o escribí libremente).'
                    : 'Resultado a guardar: $preview',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF3730A3),
                ),
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
          key: const ValueKey('apparel_helper_apply_btn'),
          onPressed: preview.isEmpty
              ? null
              : () => Navigator.of(context).pop(preview),
          icon: const Icon(Icons.check_rounded, size: 17),
          label: const Text('Aplicar Talle/Color'),
        ),
      ],
    );
  }
}
