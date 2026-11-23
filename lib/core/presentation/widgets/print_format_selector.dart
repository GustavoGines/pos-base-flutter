import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'app_modal_shell.dart';

class PrintFormatSelector {
  static Future<String?> show(BuildContext context, {String? subtitle}) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AppModalShell(
          title: 'Formato de Impresión',
          subtitle: subtitle ?? '¿En qué formato deseas imprimir el comprobante?',
          icon: Icons.print_rounded,
          accent: AppModalAccent.blue,
          compact: true,
          maxWidth: 380,
          onClose: () => Navigator.of(ctx).pop(),
          bodyPadding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          body: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: _buildOption(
                  ctx,
                  title: 'Ticket\nTérmico',
                  icon: Icons.receipt_long,
                  color: AppColors.primary,
                  bgColor: AppColors.primarySoft,
                  borderColor: AppColors.primaryBorder,
                  value: 'thermal',
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildOption(
                  ctx,
                  title: 'Hoja A4\n(PDF)',
                  icon: Icons.picture_as_pdf,
                  color: AppColors.danger,
                  bgColor: const Color(0xFFFEF2F2),
                  borderColor: const Color(0xFFFECACA),
                  value: 'a4',
                ),
              ),
            ],
          ),
          footerActions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
  }

  static Widget _buildOption(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required Color borderColor,
    required String value,
  }) {
    return Material(
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(value),
        child: Container(
          height: 122,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 38, color: color),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontSize: 13.5,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
