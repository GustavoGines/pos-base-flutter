import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:frontend_desktop/core/utils/search_text_utils.dart';

/// Opción seleccionable dentro de [SearchableSelectField].
class SearchableSelectOption<T> {
  final T value;
  final String label;
  final String? subtitle;
  final String? badgeText;
  final List<String> searchKeywords;
  final bool isResetOption;

  const SearchableSelectOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.badgeText,
    this.searchKeywords = const [],
    this.isResetOption = false,
  });
}

/// Selector desplegable con buscador integrado, ordenamiento A->Z y botón rápido de limpieza.
/// Mantiene compatibilidad visual con los campos [InputDecoration] del formulario de catálogo
/// y evita desbordes incluso en viewports compactos (`320x480`).
class SearchableSelectField<T> extends StatelessWidget {
  final T? value;
  final List<SearchableSelectOption<T>> options;
  final String labelText;
  final IconData? prefixIcon;
  final String? helperText;
  final TextStyle? helperStyle;
  final String? hintText;
  final String? dialogTitle;
  final String searchHintText;
  final String emptySearchText;
  final bool enabled;
  final bool isDense;
  final InputBorder? border;
  final ValueChanged<T?> onChanged;
  final bool showClearButton;
  final T? clearValue;
  final bool sortAlphabetically;
  final Future<void> Function(String initialQuery)? onCreateNew;
  final String Function(String query)? createLabelBuilder;

  const SearchableSelectField({
    super.key,
    required this.value,
    required this.options,
    required this.labelText,
    required this.onChanged,
    this.prefixIcon,
    this.helperText,
    this.helperStyle,
    this.hintText,
    this.dialogTitle,
    this.searchHintText = 'Buscar por nombre...',
    this.emptySearchText = 'Sin coincidencias para tu búsqueda.',
    this.enabled = true,
    this.isDense = false,
    this.border,
    this.showClearButton = true,
    this.clearValue,
    this.sortAlphabetically = true,
    this.onCreateNew,
    this.createLabelBuilder,
  });

  SearchableSelectOption<T>? _findSelectedOption() {
    for (final option in options) {
      if (option.value == value) {
        return option;
      }
    }
    return null;
  }

  SearchableSelectOption<T>? _findResetOption() {
    for (final option in options) {
      if (option.isResetOption) {
        return option;
      }
    }
    return null;
  }

  bool _canQuickClear(SearchableSelectOption<T>? selected) {
    if (!enabled || !showClearButton) return false;
    if (value == clearValue) return false;
    if (selected == null) return false;
    return !selected.isResetOption;
  }

  Future<void> _openPicker(BuildContext context) async {
    final result = await showDialog<_PickerResult<T>>(
      context: context,
      builder: (_) => _SearchableSelectPickerDialog<T>(
        title: dialogTitle ?? labelText,
        currentValue: value,
        options: options,
        searchHintText: searchHintText,
        emptySearchText: emptySearchText,
        sortAlphabetically: sortAlphabetically,
        canCreateNew: onCreateNew != null,
        createLabelBuilder: createLabelBuilder,
      ),
    );

    if (result == null) return;
    if (result.createQuery != null && onCreateNew != null) {
      await onCreateNew!(result.createQuery!);
      return;
    }
    if (result.hasSelection) {
      onChanged(result.selectedValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _findSelectedOption();
    final fallbackReset = _findResetOption();
    final displayText =
        selected?.label ?? hintText ?? fallbackReset?.label ?? '';
    final isShowingHint =
        selected == null || (selected.isResetOption && value == clearValue);
    final canClear = _canQuickClear(selected);

    final baseStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontSize: 15,
          color: !enabled
              ? Colors.grey.shade500
              : (isShowingHint
                  ? const Color(0xFF475569)
                  : const Color(0xFF0F172A)),
        );

    final decoration = InputDecoration(
      labelText: labelText,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
      helperText: helperText,
      helperStyle: helperStyle,
      isDense: isDense,
      border: border,
      suffixIcon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canClear)
            Tooltip(
              message: 'Quitar selección',
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onChanged(clearValue),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.clear_rounded,
                    size: 17,
                    color: Colors.blueGrey.shade500,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8, left: 2),
            child: Icon(
              Icons.arrow_drop_down,
              color: enabled ? const Color(0xFF475569) : Colors.grey.shade400,
            ),
          ),
        ],
      ),
      suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: labelText,
      value: displayText,
      child: InkWell(
        onTap: enabled ? () => _openPicker(context) : null,
        borderRadius: BorderRadius.circular(8),
        child: InputDecorator(
          decoration: decoration,
          isEmpty: displayText.isEmpty,
          child: Text(
            displayText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: baseStyle,
          ),
        ),
      ),
    );
  }
}

class _PickerResult<T> {
  final bool hasSelection;
  final T? selectedValue;
  final String? createQuery;

  const _PickerResult.selected(this.selectedValue)
      : hasSelection = true,
        createQuery = null;

  const _PickerResult.create(String query)
      : hasSelection = false,
        selectedValue = null,
        createQuery = query;
}

class _SearchableSelectPickerDialog<T> extends StatefulWidget {
  final String title;
  final T? currentValue;
  final List<SearchableSelectOption<T>> options;
  final String searchHintText;
  final String emptySearchText;
  final bool sortAlphabetically;
  final bool canCreateNew;
  final String Function(String query)? createLabelBuilder;

  const _SearchableSelectPickerDialog({
    required this.title,
    required this.currentValue,
    required this.options,
    required this.searchHintText,
    required this.emptySearchText,
    required this.sortAlphabetically,
    required this.canCreateNew,
    this.createLabelBuilder,
  });

  @override
  State<_SearchableSelectPickerDialog<T>> createState() =>
      _SearchableSelectPickerDialogState<T>();
}

class _SearchableSelectPickerDialogState<T>
    extends State<_SearchableSelectPickerDialog<T>> {
  final TextEditingController _searchCtrl = TextEditingController();
  late final List<SearchableSelectOption<T>> _orderedOptions;
  String _rawQuery = '';

  @override
  void initState() {
    super.initState();
    final resets = widget.options.where((o) => o.isResetOption).toList();
    final normals = widget.options.where((o) => !o.isResetOption).toList();
    if (widget.sortAlphabetically) {
      normals.sort((a, b) => compareSpanishAlphabetical(a.label, b.label));
    }
    _orderedOptions = [...resets, ...normals];
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matchesQuery(SearchableSelectOption<T> option, String normQuery) {
    if (normQuery.isEmpty) return true;
    if (normalizeSearchText(option.label).contains(normQuery)) return true;
    if (option.subtitle != null &&
        normalizeSearchText(option.subtitle!).contains(normQuery)) {
      return true;
    }
    if (option.badgeText != null &&
        normalizeSearchText(option.badgeText!).contains(normQuery)) {
      return true;
    }
    for (final keyword in option.searchKeywords) {
      if (normalizeSearchText(keyword).contains(normQuery)) return true;
    }
    return false;
  }

  List<SearchableSelectOption<T>> _buildFilteredOptions(String normQuery) {
    if (normQuery.isEmpty) return _orderedOptions;
    final matchedResets = <SearchableSelectOption<T>>[];
    final matchedNormals = <SearchableSelectOption<T>>[];
    for (final option in _orderedOptions) {
      if (!_matchesQuery(option, normQuery)) continue;
      if (option.isResetOption) {
        matchedResets.add(option);
      } else {
        matchedNormals.add(option);
      }
    }
    return [...matchedResets, ...matchedNormals];
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final isCompactWidth = screen.width < 480;
    final normQuery = normalizeSearchText(_rawQuery);
    final filtered = _buildFilteredOptions(normQuery);
    final nonResetFiltered =
        filtered.where((option) => !option.isResetOption).toList();
    final hasExactLabelMatch = normQuery.isNotEmpty &&
        _orderedOptions.any(
          (o) => !o.isResetOption && normalizeSearchText(o.label) == normQuery,
        );
    final trimmedRaw = _rawQuery.trim();
    final showCreateAction =
        widget.canCreateNew && trimmedRaw.isNotEmpty && !hasExactLabelMatch;
    final double maxListHeight = math.max(
      140.0,
      math.min(280.0, screen.height * 0.48),
    );

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompactWidth ? 12 : 24,
        vertical: screen.height < 520 ? 10 : 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: math.min(500.0, screen.height * 0.86),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded, size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchCtrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (val) => setState(() => _rawQuery = val),
                onSubmitted: (_) {
                  final exact = filtered.where(
                    (o) =>
                        !o.isResetOption &&
                        normQuery.isNotEmpty &&
                        normalizeSearchText(o.label) == normQuery,
                  );
                  if (exact.length == 1) {
                    Navigator.of(context)
                        .pop(_PickerResult<T>.selected(exact.first.value));
                    return;
                  }
                  if (nonResetFiltered.length == 1) {
                    Navigator.of(context).pop(
                      _PickerResult<T>.selected(nonResetFiltered.first.value),
                    );
                  }
                },
                decoration: InputDecoration(
                  hintText: widget.searchHintText,
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 19),
                  suffixIcon: _rawQuery.isNotEmpty
                      ? InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() => _rawQuery = '');
                          },
                          child: const Icon(Icons.clear_rounded, size: 17),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (filtered.isEmpty)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 28,
                        color: Colors.blueGrey.shade300,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.emptySearchText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blueGrey.shade600,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Flexible(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxListHeight),
                    child: Scrollbar(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final option = filtered[index];
                          final isSelected = option.value == widget.currentValue;
                          return InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => Navigator.of(context)
                                .pop(_PickerResult<T>.selected(option.value)),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 9,
                              ),
                              margin: const EdgeInsets.only(bottom: 2),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFFEEF2FF)
                                    : (option.isResetOption
                                        ? const Color(0xFFF8FAFC)
                                        : Colors.transparent),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          option.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: isSelected ||
                                                    option.isResetOption
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: isSelected
                                                ? const Color(0xFF4338CA)
                                                : (option.isResetOption
                                                    ? const Color(0xFF475569)
                                                    : const Color(0xFF0F172A)),
                                          ),
                                        ),
                                        if (option.subtitle != null &&
                                            option.subtitle!.trim().isNotEmpty)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 1.5),
                                            child: Text(
                                              option.subtitle!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: Colors.blueGrey.shade600,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (option.badgeText != null &&
                                      option.badgeText!.trim().isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 120),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          border: Border.all(
                                            color: const Color(0xFFE2E8F0),
                                          ),
                                        ),
                                        child: Text(
                                          option.badgeText!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF475569),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (isSelected) ...[
                                    const SizedBox(width: 6),
                                    const Icon(
                                      Icons.check_rounded,
                                      size: 18,
                                      color: Color(0xFF4338CA),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              if (showCreateAction) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context)
                      .pop(_PickerResult<T>.create(trimmedRaw)),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(
                    widget.createLabelBuilder?.call(trimmedRaw) ??
                        'Crear "$trimmedRaw"',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
