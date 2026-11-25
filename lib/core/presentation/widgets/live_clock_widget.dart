import 'dart:async';
import 'package:flutter/material.dart';

class LiveClockWidget extends StatefulWidget {
  final bool compact;
  final bool showSeconds;
  final Color? backgroundColor;
  final Color? textColor;
  final double fontSize;

  const LiveClockWidget({
    super.key,
    this.compact = false,
    this.showSeconds = true,
    this.backgroundColor,
    this.textColor,
    this.fontSize = 13,
  });

  @override
  State<LiveClockWidget> createState() => _LiveClockWidgetState();
}

class _LiveClockWidgetState extends State<LiveClockWidget> {
  late DateTime _now;
  Timer? _timer;

  static const List<String> _days = [
    'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'
  ];

  static const List<String> _months = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
  ];

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dayName = _days[_now.weekday - 1];
    final dayNum = _now.day.toString().padLeft(2, '0');
    final monthName = _months[_now.month - 1];
    final hour = _now.hour.toString().padLeft(2, '0');
    final minute = _now.minute.toString().padLeft(2, '0');
    final second = _now.second.toString().padLeft(2, '0');

    final timeString = widget.showSeconds ? '$hour:$minute:$second' : '$hour:$minute';
    final dateString = widget.compact ? '$dayNum $monthName' : '$dayName $dayNum $monthName ${_now.year}';

    final effectiveTextColor = widget.textColor ?? const Color(0xFFCBD5E1);
    final effectiveBgColor = widget.backgroundColor ?? Colors.white.withValues(alpha: 0.06);

    return RepaintBoundary(
      child: ExcludeSemantics(
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: effectiveBgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.access_time_rounded,
                size: widget.fontSize + 2,
                color: const Color(0xFF34D399),
              ),
              const SizedBox(width: 6),
              Text(
                dateString,
                style: TextStyle(
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.w600,
                  color: effectiveTextColor,
                  letterSpacing: 0.2,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: Colors.white38,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Text(
                timeString,
                style: TextStyle(
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontFamily: 'monospace',
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
