import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/services/remote_scanner_service.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
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
  final Future<List<SearchableSelectOption<T>>> Function(String query)?
      onRemoteSearch;

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
    this.onRemoteSearch,
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
        onRemoteSearch: onRemoteSearch,
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

  /// Abre directamente el diálogo buscador (útil para acciones como "+ Agregar insumo"
  /// sin requerir un cuadro intermedio y con soporte de lector USB/Android).
  static Future<T?> showPickerModal<T>(
    BuildContext context, {
    required String title,
    required List<SearchableSelectOption<T>> options,
    T? currentValue,
    String searchHintText = 'Buscar por nombre, código o barras...',
    String emptySearchText = 'Sin coincidencias para tu búsqueda.',
    bool sortAlphabetically = true,
    Future<List<SearchableSelectOption<T>>> Function(String query)?
        onRemoteSearch,
  }) async {
    final result = await showDialog<_PickerResult<T>>(
      context: context,
      builder: (_) => _SearchableSelectPickerDialog<T>(
        title: title,
        currentValue: currentValue,
        options: options,
        searchHintText: searchHintText,
        emptySearchText: emptySearchText,
        sortAlphabetically: sortAlphabetically,
        canCreateNew: false,
        onRemoteSearch: onRemoteSearch,
      ),
    );
    if (result != null && result.hasSelection) {
      return result.selectedValue;
    }
    return null;
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
  final Future<List<SearchableSelectOption<T>>> Function(String query)?
      onRemoteSearch;

  const _SearchableSelectPickerDialog({
    required this.title,
    required this.currentValue,
    required this.options,
    required this.searchHintText,
    required this.emptySearchText,
    required this.sortAlphabetically,
    required this.canCreateNew,
    this.createLabelBuilder,
    this.onRemoteSearch,
  });

  @override
  State<_SearchableSelectPickerDialog<T>> createState() =>
      _SearchableSelectPickerDialogState<T>();
}

class _SearchableSelectPickerDialogState<T>
    extends State<_SearchableSelectPickerDialog<T>> {
  final TextEditingController _searchCtrl = TextEditingController();
  late final List<SearchableSelectOption<T>> _orderedOptions;
  List<SearchableSelectOption<T>> _remoteOptions = const [];
  Timer? _remoteDebounce;
  bool _isSearchingRemote = false;
  int _remoteSeq = 0;
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
    _remoteDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _triggerRemoteSearch(String query) {
    _remoteDebounce?.cancel();
    final trimmed = query.trim();
    if (widget.onRemoteSearch == null || trimmed.length < 2) {
      if (_remoteOptions.isNotEmpty || _isSearchingRemote) {
        setState(() {
          _remoteOptions = const [];
          _isSearchingRemote = false;
        });
      }
      return;
    }

    final seq = ++_remoteSeq;
    setState(() => _isSearchingRemote = true);
    _remoteDebounce = Timer(const Duration(milliseconds: 220), () async {
      try {
        final fetched = await widget.onRemoteSearch!(trimmed);
        if (!mounted || seq != _remoteSeq) return;
        setState(() {
          _remoteOptions = fetched;
          _isSearchingRemote = false;
        });
      } catch (_) {
        if (!mounted || seq != _remoteSeq) return;
        setState(() => _isSearchingRemote = false);
      }
    });
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

  bool _matchesExactOption(SearchableSelectOption<T> option, String normQuery) {
    if (option.isResetOption || normQuery.isEmpty) return false;
    if (normalizeSearchText(option.label) == normQuery) return true;
    for (final keyword in option.searchKeywords) {
      if (normalizeSearchText(keyword) == normQuery) return true;
    }
    return false;
  }

  Future<void> _handleSubmittedOrScanned(String rawInput) async {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty || !mounted) return;

    _remoteDebounce?.cancel();
    final seq = ++_remoteSeq;

    if (_searchCtrl.text != trimmed) {
      _searchCtrl.text = trimmed;
      _searchCtrl.selection = TextSelection.collapsed(offset: trimmed.length);
    }
    setState(() => _rawQuery = trimmed);

    final normQuery = normalizeSearchText(trimmed);
    var filtered = _buildFilteredOptions(normQuery);
    var exact = filtered.where((o) => _matchesExactOption(o, normQuery)).toList();

    if (exact.isEmpty &&
        widget.onRemoteSearch != null &&
        trimmed.length >= 2) {
      setState(() => _isSearchingRemote = true);
      try {
        final fetched = await widget.onRemoteSearch!(trimmed);
        if (!mounted || seq != _remoteSeq) return;
        setState(() {
          _remoteOptions = fetched;
          _isSearchingRemote = false;
        });
        filtered = _buildFilteredOptions(normQuery);
        exact =
            filtered.where((o) => _matchesExactOption(o, normQuery)).toList();
      } catch (_) {
        if (!mounted || seq != _remoteSeq) return;
        setState(() => _isSearchingRemote = false);
      }
    }

    if (!mounted) return;
    if (exact.length == 1) {
      Navigator.of(context).pop(_PickerResult<T>.selected(exact.first.value));
      return;
    }
    final nonResetFiltered = filtered.where((o) => !o.isResetOption).toList();
    if (nonResetFiltered.length == 1) {
      Navigator.of(context)
          .pop(_PickerResult<T>.selected(nonResetFiltered.first.value));
    }
  }

  List<SearchableSelectOption<T>> _buildFilteredOptions(String normQuery) {
    if (normQuery.isEmpty) return _orderedOptions;
    final matchedResets = <SearchableSelectOption<T>>[];
    final matchedNormals = <SearchableSelectOption<T>>[];
    final seenValues = <T>{};

    for (final option in _orderedOptions) {
      if (!_matchesQuery(option, normQuery)) continue;
      seenValues.add(option.value);
      if (option.isResetOption) {
        matchedResets.add(option);
      } else {
        matchedNormals.add(option);
      }
    }

    for (final remoteOpt in _remoteOptions) {
      if (seenValues.contains(remoteOpt.value)) continue;
      if (!_matchesQuery(remoteOpt, normQuery)) continue;
      seenValues.add(remoteOpt.value);
      matchedNormals.add(remoteOpt);
    }

    return [...matchedResets, ...matchedNormals];
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final normQuery = normalizeSearchText(_rawQuery);
    final filtered = _buildFilteredOptions(normQuery);
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

    return RemoteScannerListener(
      debugLabel: 'SearchableSelectPickerDialog',
      onBarcodeScanned: _handleSubmittedOrScanned,
      child: AppModalShell(
        title: widget.title,
        icon: Icons.manage_search_rounded,
        accent: AppModalAccent.blue,
        compact: true,
        maxWidth: 440,
        maxHeight: math.min(500.0, screen.height * 0.86),
        showCloseButton: true,
        onClose: () => Navigator.of(context).pop(),
        topBar: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: const BoxDecoration(
            color: AppColors.surfaceMuted,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: TextField(
            controller: _searchCtrl,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: (val) {
              setState(() => _rawQuery = val);
              _triggerRemoteSearch(val);
            },
            onSubmitted: _handleSubmittedOrScanned,
            decoration: InputDecoration(
              hintText: widget.searchHintText,
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.search, size: 19),
              suffixIcon: _isSearchingRemote
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (_rawQuery.isNotEmpty
                      ? InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() => _rawQuery = '');
                            _triggerRemoteSearch('');
                          },
                          child: const Icon(Icons.clear_rounded, size: 17),
                        )
                      : null),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ),
        bodyPadding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        body: filtered.isEmpty
            ? Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isSearchingRemote)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      Icon(
                        Icons.search_off_rounded,
                        size: 28,
                        color: Colors.blueGrey.shade300,
                      ),
                    const SizedBox(height: 6),
                    Text(
                      _isSearchingRemote
                          ? 'Buscando en todo el catálogo...'
                          : widget.emptySearchText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blueGrey.shade600,
                      ),
                    ),
                  ],
                ),
              )
            : ConstrainedBox(
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
                                ? AppColors.primarySoft
                                : (option.isResetOption
                                    ? AppColors.surfaceMuted
                                    : Colors.transparent),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                            ? AppColors.primaryDark
                                            : (option.isResetOption
                                                ? AppColors.textSecondary
                                                : AppColors.textPrimary),
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
                                      color: AppColors.surfaceAlt,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: AppColors.border,
                                      ),
                                    ),
                                    child: Text(
                                      option.badgeText!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textSecondary,
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
                                  color: AppColors.primaryDark,
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
        customFooter: showCreateAction
            ? Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: const BoxDecoration(
                  color: AppColors.surfaceMuted,
                  border: Border(top: BorderSide(color: AppColors.border)),
                  borderRadius:
                      BorderRadius.vertical(bottom: Radius.circular(16)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
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
                ),
              )
            : null,
      ),
    );
  }
}
