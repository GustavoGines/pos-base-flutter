import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Muestra una ventana compacta y ágil para elegir un rango de fechas (Desde / Hasta),
/// permitiendo navegar fácilmente por mes y año (flechas y desplegables directos)
/// además de atajos rápidos (Hoy, Últimos 7 días, Este Mes, Mes Anterior, Este Año).
Future<DateTimeRange?> showCompactDateRangePicker({
  required BuildContext context,
  DateTimeRange? initialDateRange,
  DateTime? firstDate,
  DateTime? lastDate,
  String helpText = 'Seleccionar Rango de Fechas',
}) {
  final minDate = firstDate ?? DateTime(2020, 1, 1);
  final maxDate = lastDate ?? DateTime(DateTime.now().year + 5, 12, 31);
  return showDialog<DateTimeRange>(
    context: context,
    builder: (ctx) => CompactDateRangePickerDialog(
      initialDateRange: initialDateRange,
      firstDate: minDate,
      lastDate: maxDate,
      title: helpText,
      singleDateMode: false,
    ),
  );
}

/// Muestra la misma ventana compacta y ágil en modo de Fecha Única (ej. vencimientos, emisión).
Future<DateTime?> showCompactDatePicker({
  required BuildContext context,
  DateTime? initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  String helpText = 'Seleccionar Fecha',
}) async {
  final minDate = firstDate ?? DateTime(2020, 1, 1);
  final maxDate = lastDate ?? DateTime(DateTime.now().year + 10, 12, 31);
  final init = initialDate ?? DateTime.now();
  final range = await showDialog<DateTimeRange>(
    context: context,
    builder: (ctx) => CompactDateRangePickerDialog(
      initialDateRange: DateTimeRange(start: init, end: init),
      firstDate: minDate,
      lastDate: maxDate,
      title: helpText,
      singleDateMode: true,
    ),
  );
  return range?.start;
}

class CompactDateRangePickerDialog extends StatefulWidget {
  final DateTimeRange? initialDateRange;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;
  final bool singleDateMode;

  const CompactDateRangePickerDialog({
    super.key,
    this.initialDateRange,
    required this.firstDate,
    required this.lastDate,
    this.title = 'Seleccionar Rango de Fechas',
    this.singleDateMode = false,
  });

  @override
  State<CompactDateRangePickerDialog> createState() =>
      _CompactDateRangePickerDialogState();
}

class _CompactDateRangePickerDialogState
    extends State<CompactDateRangePickerDialog> {
  static const List<String> _monthNames = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];

  static const List<String> _weekDays = [
    'Lun',
    'Mar',
    'Mié',
    'Jue',
    'Vie',
    'Sáb',
    'Dom',
  ];

  late DateTime _startDate;
  late DateTime _endDate;
  late DateTime _displayedMonth;
  bool _selectingEnd = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (widget.initialDateRange != null) {
      _startDate = DateTime(
        widget.initialDateRange!.start.year,
        widget.initialDateRange!.start.month,
        widget.initialDateRange!.start.day,
      );
      _endDate = DateTime(
        widget.initialDateRange!.end.year,
        widget.initialDateRange!.end.month,
        widget.initialDateRange!.end.day,
      );
    } else {
      _startDate = today;
      _endDate = today;
    }
    _displayedMonth = DateTime(_endDate.year, _endDate.month, 1);
  }

  void _changeMonth(int deltaMonths) {
    _setDisplayedMonthClamped(
      _displayedMonth.year,
      _displayedMonth.month + deltaMonths,
    );
  }

  void _setDisplayedMonthClamped(int year, int month) {
    setState(() {
      final next = DateTime(year, month, 1);
      final minMonth = DateTime(widget.firstDate.year, widget.firstDate.month, 1);
      final maxMonth = DateTime(widget.lastDate.year, widget.lastDate.month, 1);
      if (next.isBefore(minMonth)) {
        _displayedMonth = minMonth;
      } else if (next.isAfter(maxMonth)) {
        _displayedMonth = maxMonth;
      } else {
        _displayedMonth = next;
      }
    });
  }

  void _onDayTapped(DateTime day) {
    setState(() {
      if (widget.singleDateMode) {
        _startDate = day;
        _endDate = day;
        _selectingEnd = false;
        return;
      }
      if (!_selectingEnd) {
        _startDate = day;
        _endDate = day;
        _selectingEnd = true;
      } else {
        if (day.isBefore(_startDate)) {
          _endDate = _startDate;
          _startDate = day;
        } else {
          _endDate = day;
        }
        _selectingEnd = false;
      }
    });
  }

  void _applyPreset(DateTime start, DateTime end) {
    setState(() {
      _startDate = DateTime(start.year, start.month, start.day);
      _endDate = DateTime(end.year, end.month, end.day);
      _displayedMonth = DateTime(_endDate.year, _endDate.month, 1);
      _selectingEnd = false;
    });
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isInRange(DateTime day) =>
      (day.isAfter(_startDate) && day.isBefore(_endDate)) ||
      _isSameDay(day, _startDate) ||
      _isSameDay(day, _endDate);

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final screenSize = MediaQuery.of(context).size;

    final minYear = widget.firstDate.year;
    final maxYear = widget.lastDate.year < minYear
        ? minYear
        : widget.lastDate.year;
    final years = List<int>.generate(
      (maxYear - minYear) + 1,
      (i) => minYear + i,
    );

    // Construcción de grilla mensual (Lunes = 1 .. Domingo = 7)
    final firstDayOfMonth =
        DateTime(_displayedMonth.year, _displayedMonth.month, 1);
    final daysInMonth =
        DateTime(_displayedMonth.year, _displayedMonth.month + 1, 0).day;
    final leadingEmptyDays = firstDayOfMonth.weekday - 1; // 0 para Lunes

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      child: Container(
        width: (screenSize.width * 0.92).clamp(310.0, 440.0),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Cabecera ──────────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.date_range_rounded,
                      color: Colors.indigo.shade700,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey.shade900,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _selectingEnd
                              ? 'Ahora hacé clic en la fecha de fin (Hasta)'
                              : 'Hacé clic en un día para iniciar o usá un atajo rápido',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: _selectingEnd
                                ? Colors.indigo.shade700
                                : Colors.blueGrey.shade500,
                            fontWeight: _selectingEnd
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Indicadores Desde / Hasta (o Fecha Seleccionada) ──────────
              if (widget.singleDateMode)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.indigo.shade400, width: 1.4),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'FECHA SELECCIONADA',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      Text(
                        df.format(_startDate),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey.shade900,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          setState(() {
                            _displayedMonth =
                                DateTime(_startDate.year, _startDate.month, 1);
                            _selectingEnd = false;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: !_selectingEnd
                                ? Colors.indigo.shade50
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: !_selectingEnd
                                  ? Colors.indigo.shade400
                                  : Colors.grey.shade300,
                              width: !_selectingEnd ? 1.4 : 1.0,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'DESDE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo.shade700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                df.format(_startDate),
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: Colors.blueGrey.shade400,
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          setState(() {
                            _displayedMonth =
                                DateTime(_endDate.year, _endDate.month, 1);
                            _selectingEnd = true;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectingEnd
                                ? Colors.indigo.shade50
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _selectingEnd
                                  ? Colors.indigo.shade400
                                  : Colors.grey.shade300,
                              width: _selectingEnd ? 1.4 : 1.0,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'HASTA',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo.shade700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                df.format(_endDate),
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 10),

              // ── Atajos Rápidos ────────────────────────────────────────────
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: widget.singleDateMode
                    ? [
                        _buildPresetChip(
                            'Hoy', () => _applyPreset(today, today)),
                        _buildPresetChip(
                          '+7 días',
                          () {
                            final d = today.add(const Duration(days: 7));
                            _applyPreset(d, d);
                          },
                        ),
                        _buildPresetChip(
                          '+15 días',
                          () {
                            final d = today.add(const Duration(days: 15));
                            _applyPreset(d, d);
                          },
                        ),
                        _buildPresetChip(
                          '+1 Mes',
                          () {
                            final d =
                                DateTime(today.year, today.month + 1, today.day);
                            _applyPreset(d, d);
                          },
                        ),
                        _buildPresetChip(
                          '+6 Meses',
                          () {
                            final d =
                                DateTime(today.year, today.month + 6, today.day);
                            _applyPreset(d, d);
                          },
                        ),
                      ]
                    : [
                        _buildPresetChip(
                            'Hoy', () => _applyPreset(today, today)),
                        _buildPresetChip(
                          'Últ. 7 días',
                          () => _applyPreset(
                              today.subtract(const Duration(days: 6)), today),
                        ),
                        _buildPresetChip(
                          'Este Mes',
                          () => _applyPreset(
                              DateTime(today.year, today.month, 1), today),
                        ),
                        _buildPresetChip(
                          'Mes Anterior',
                          () {
                            final firstPrev =
                                DateTime(today.year, today.month - 1, 1);
                            final lastPrev =
                                DateTime(today.year, today.month, 0);
                            _applyPreset(firstPrev, lastPrev);
                          },
                        ),
                        _buildPresetChip(
                          'Este Año',
                          () => _applyPreset(DateTime(today.year, 1, 1), today),
                        ),
                      ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),

              // ── Barra de Navegación por Mes y Año ─────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Año anterior',
                          icon: const Icon(
                              Icons.keyboard_double_arrow_left_rounded,
                              size: 18),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _changeMonth(-12),
                        ),
                        IconButton(
                          tooltip: 'Mes anterior',
                          icon:
                              const Icon(Icons.chevron_left_rounded, size: 20),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _changeMonth(-1),
                        ),
                      ],
                    ),
                    // Selectores directos de Mes y Año
                    Flexible(
                      child: Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.center,
                        children: [
                          DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: _displayedMonth.month,
                              isDense: true,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo.shade900,
                              ),
                              items: List.generate(12, (idx) {
                                final m = idx + 1;
                                return DropdownMenuItem<int>(
                                  value: m,
                                  child: Text(_monthNames[idx]),
                                );
                              }),
                              onChanged: (m) {
                                if (m != null) {
                                  _setDisplayedMonthClamped(_displayedMonth.year, m);
                                }
                              },
                            ),
                          ),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: years.contains(_displayedMonth.year)
                                  ? _displayedMonth.year
                                  : years.last,
                              isDense: true,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo.shade900,
                              ),
                              items: years
                                  .map(
                                    (y) => DropdownMenuItem<int>(
                                      value: y,
                                      child: Text('$y'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (y) {
                                if (y != null) {
                                  _setDisplayedMonthClamped(y, _displayedMonth.month);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Mes siguiente',
                          icon:
                              const Icon(Icons.chevron_right_rounded, size: 20),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _changeMonth(1),
                        ),
                        IconButton(
                          tooltip: 'Año siguiente',
                          icon: const Icon(
                              Icons.keyboard_double_arrow_right_rounded,
                              size: 18),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _changeMonth(12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // ── Cabecera de días de la semana ─────────────────────────────
              Row(
                children: _weekDays
                    .map(
                      (d) => Expanded(
                        child: Center(
                          child: Text(
                            d,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.blueGrey.shade500,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 6),

              // ── Grilla de días del mes ────────────────────────────────────
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 0,
                  childAspectRatio: 1.35,
                ),
                itemCount: leadingEmptyDays + daysInMonth,
                itemBuilder: (ctx, index) {
                  if (index < leadingEmptyDays) {
                    return const SizedBox.shrink();
                  }
                  final dayNum = index - leadingEmptyDays + 1;
                  final date = DateTime(
                      _displayedMonth.year, _displayedMonth.month, dayNum);
                  final isStart = _isSameDay(date, _startDate);
                  final isEnd = _isSameDay(date, _endDate);
                  final isSelectedEndpoint = isStart || isEnd;
                  final inRange = _isInRange(date);
                  final isToday = _isSameDay(date, today);

                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _onDayTapped(date),
                    child: Container(
                      margin: EdgeInsets.symmetric(
                        horizontal: (inRange && !isSelectedEndpoint) ? 0 : 2,
                      ),
                      decoration: BoxDecoration(
                        color: isSelectedEndpoint
                            ? Colors.indigo.shade700
                            : inRange
                                ? Colors.indigo.shade50
                                : Colors.transparent,
                        borderRadius: BorderRadius.horizontal(
                          left: Radius.circular(
                              isStart || !inRange ? 8 : 0),
                          right:
                              Radius.circular(isEnd || !inRange ? 8 : 0),
                        ),
                        border: isToday && !isSelectedEndpoint
                            ? Border.all(
                                color: Colors.indigo.shade400, width: 1.2)
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$dayNum',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelectedEndpoint || isToday
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isSelectedEndpoint
                              ? Colors.white
                              : inRange
                                  ? Colors.indigo.shade900
                                  : Colors.blueGrey.shade800,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // ── Botones de Acción ─────────────────────────────────────────
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(
                      DateTimeRange(start: _startDate, end: _endDate),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.indigo.shade700,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: Text(
                      widget.singleDateMode
                          ? 'Aplicar Fecha'
                          : 'Aplicar Rango',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetChip(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Colors.indigo.shade800,
        ),
      ),
      backgroundColor: Colors.indigo.shade50.withValues(alpha: 0.6),
      side: BorderSide(color: Colors.indigo.shade100),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      onPressed: onTap,
    );
  }
}
