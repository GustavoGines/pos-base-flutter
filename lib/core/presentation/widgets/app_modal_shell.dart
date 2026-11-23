import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';

/// Acentos semánticos del badge del ícono en la cabecera Dark Navy.
enum AppModalAccent {
  blue,
  teal,
  amber,
  emerald,
  indigo,
  orange,
  red,
  slate;

  Color get iconColor {
    switch (this) {
      case AppModalAccent.blue:
        return const Color(0xFF60A5FA);
      case AppModalAccent.teal:
        return AppColors.tealLight;
      case AppModalAccent.amber:
        return AppColors.amberLight;
      case AppModalAccent.emerald:
        return AppColors.emeraldLight;
      case AppModalAccent.indigo:
        return AppColors.indigoLight;
      case AppModalAccent.orange:
        return AppColors.orangeLight;
      case AppModalAccent.red:
        return AppColors.dangerLight;
      case AppModalAccent.slate:
        return const Color(0xFFCBD5E1);
    }
  }

  Color get solidColor {
    switch (this) {
      case AppModalAccent.blue:
        return AppColors.primary;
      case AppModalAccent.teal:
        return AppColors.teal;
      case AppModalAccent.amber:
        return AppColors.amber;
      case AppModalAccent.emerald:
        return AppColors.emerald;
      case AppModalAccent.indigo:
        return AppColors.indigo;
      case AppModalAccent.orange:
        return AppColors.orange;
      case AppModalAccent.red:
        return AppColors.danger;
      case AppModalAccent.slate:
        return AppColors.textSecondary;
    }
  }

  Color get badgeBg => solidColor.withValues(alpha: 0.24);

  Color get badgeBorder => iconColor.withValues(alpha: 0.48);
}

/// Cabecera unificada Dark Navy (`#0F172A -> #1E293B`) alineada con `GlobalAppBar`
/// y `PosHardwareCalculatorDialog`.
class AppModalHeader extends StatelessWidget {
  final String? title;
  final Widget? titleWidget;
  final String? subtitle;
  final IconData? icon;
  final Widget? iconWidget;
  final AppModalAccent accent;
  final Widget? trailing;
  final bool showCloseButton;
  final VoidCallback? onClose;
  final String closeTooltip;
  final bool compact;
  final double borderRadius;

  const AppModalHeader({
    super.key,
    this.title,
    this.titleWidget,
    this.subtitle,
    this.icon,
    this.iconWidget,
    this.accent = AppModalAccent.blue,
    this.trailing,
    this.showCloseButton = true,
    this.onClose,
    this.closeTooltip = 'Cerrar (Esc)',
    this.compact = false,
    this.borderRadius = 16.0,
  }) : assert(
          title != null || titleWidget != null,
          'Debe especificar title o titleWidget en AppModalHeader.',
        );

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = compact || screenWidth < 480;

    return Container(
      padding: EdgeInsets.fromLTRB(
        isNarrow ? 14 : 20,
        isNarrow ? 11 : 14,
        isNarrow ? 10 : 14,
        isNarrow ? 11 : 13,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.navyStart, AppColors.navyEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(borderRadius),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null || iconWidget != null) ...[
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.all(isNarrow ? 7 : 8),
              decoration: BoxDecoration(
                color: accent.badgeBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.badgeBorder),
              ),
              child: iconWidget ??
                  Icon(
                    icon,
                    color: accent.iconColor,
                    size: isNarrow ? 20 : 22,
                  ),
            ),
            SizedBox(width: isNarrow ? 10 : 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                DefaultTextStyle(
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isNarrow ? 15.0 : 16.5,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  child: titleWidget ??
                      Text(
                        title!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.darkSubtitle,
                      fontSize: isNarrow ? 11.0 : 11.5,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
          if (showCloseButton) ...[
            const SizedBox(width: 4),
            IconButton(
              onPressed: onClose ?? () => Navigator.of(context).maybePop(),
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.white70,
                size: 20,
              ),
              tooltip: closeTooltip,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }
}

/// Barra inferior fija para acciones y resumen de modales.
class AppModalFooter extends StatelessWidget {
  final Widget? leading;
  final List<Widget> actions;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;

  const AppModalFooter({
    super.key,
    this.leading,
    this.actions = const [],
    this.padding,
    this.borderRadius = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 480;
    final resolvedPadding = padding ??
        EdgeInsets.fromLTRB(
          isNarrow ? 14 : 20,
          12,
          isNarrow ? 14 : 20,
          14,
        );

    return Container(
      width: double.infinity,
      padding: resolvedPadding,
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        border: const Border(top: BorderSide(color: AppColors.border)),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(borderRadius),
        ),
      ),
      child: leading != null
          ? Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                leading!,
                if (actions.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actions,
                  ),
              ],
            )
          : Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
    );
  }
}

/// Tarjeta interna estándar para agrupar secciones dentro de un modal.
class AppSectionCard extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final Color accent;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AppSectionCard({
    super.key,
    this.title,
    this.icon,
    this.accent = AppColors.primaryDark,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null || icon != null || trailing != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: accent),
                  const SizedBox(width: 6),
                ],
                if (title != null)
                  Expanded(
                    child: Text(
                      title!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                  ),
                if (trailing != null) trailing!,
              ],
            ),
            const Divider(height: 16),
          ],
          child,
        ],
      ),
    );
  }
}

/// Contenedor maestro para modales Nivel 1 (workspaces / formularios)
/// y Nivel 2 (compactos / seguridad / acciones rápidas).
class AppModalShell extends StatelessWidget {
  final String? title;
  final Widget? titleWidget;
  final String? subtitle;
  final IconData? icon;
  final Widget? iconWidget;
  final AppModalAccent accent;
  final Widget? headerTrailing;
  final bool showCloseButton;
  final VoidCallback? onClose;
  final String closeTooltip;
  final Widget? topBar;
  final Widget body;
  final EdgeInsetsGeometry? bodyPadding;
  final bool expandBody;
  final Widget? footerLeading;
  final List<Widget>? footerActions;
  final Widget? customFooter;
  final double maxWidth;
  final double? maxHeight;
  final bool compact;
  final double borderRadius;
  final bool useAlertDialogWrapper;

  const AppModalShell({
    super.key,
    this.title,
    this.titleWidget,
    this.subtitle,
    this.icon,
    this.iconWidget,
    this.accent = AppModalAccent.blue,
    this.headerTrailing,
    this.showCloseButton = true,
    this.onClose,
    this.closeTooltip = 'Cerrar (Esc)',
    this.topBar,
    required this.body,
    this.bodyPadding,
    this.expandBody = false,
    this.footerLeading,
    this.footerActions,
    this.customFooter,
    this.maxWidth = 680,
    this.maxHeight,
    this.compact = false,
    this.borderRadius = 16.0,
    this.useAlertDialogWrapper = false,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isCompactWidth = screenSize.width < 480;
    final isShortScreen = screenSize.height < 580;
    final isUltraShortScreen = screenSize.height < 380;
    final effectiveMaxWidth = compact ? maxWidth.clamp(240.0, 520.0) : maxWidth;
    final horizontalInset = isCompactWidth ? 10.0 : 20.0;
    final verticalInset = isShortScreen ? 8.0 : 16.0;
    final dialogWidth =
        (screenSize.width - (horizontalInset * 2)).clamp(240.0, effectiveMaxWidth);
    final viewportMaxHeight =
        screenSize.height * (isShortScreen ? 0.96 : 0.92);
    final resolvedMaxHeight = maxHeight != null
        ? math.min(maxHeight!, viewportMaxHeight)
        : viewportMaxHeight;

    final header = AppModalHeader(
      title: title,
      titleWidget: titleWidget,
      subtitle: subtitle,
      icon: icon,
      iconWidget: iconWidget,
      accent: accent,
      trailing: headerTrailing,
      showCloseButton: showCloseButton,
      onClose: onClose,
      closeTooltip: closeTooltip,
      compact: compact || isCompactWidth || isShortScreen,
      borderRadius: borderRadius,
    );

    final EdgeInsetsGeometry? effectiveBodyPadding = bodyPadding ??
        (expandBody
            ? null
            : EdgeInsets.fromLTRB(
                isCompactWidth ? 14 : 20,
                isShortScreen ? 12 : 16,
                isCompactWidth ? 14 : 20,
                isShortScreen ? 12 : 16,
              ));

    final Widget paddedBody = effectiveBodyPadding != null
        ? Padding(padding: effectiveBodyPadding, child: body)
        : body;

    final Widget? footer = customFooter ??
        ((footerLeading != null ||
                (footerActions != null && footerActions!.isNotEmpty))
            ? AppModalFooter(
                leading: footerLeading,
                actions: footerActions ?? const [],
                borderRadius: borderRadius,
              )
            : null);

    Widget contentTree;
    if (!expandBody && isUltraShortScreen) {
      contentTree = SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            if (topBar != null) topBar!,
            paddedBody,
            if (footer != null) footer,
          ],
        ),
      );
    } else if (expandBody) {
      contentTree = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (topBar != null) topBar!,
          Expanded(child: paddedBody),
          if (footer != null) footer,
        ],
      );
    } else {
      contentTree = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (topBar != null) topBar!,
          Flexible(
            child: SingleChildScrollView(child: paddedBody),
          ),
          if (footer != null) footer,
        ],
      );
    }

    final innerBox = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: effectiveMaxWidth,
        maxHeight: resolvedMaxHeight,
      ),
      child: SizedBox(
        width: dialogWidth,
        height: (useAlertDialogWrapper && expandBody) ? resolvedMaxHeight : null,
        child: contentTree,
      ),
    );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadius),
    );

    if (useAlertDialogWrapper) {
      return AlertDialog(
        alignment: Alignment.center,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        insetPadding: EdgeInsets.symmetric(
          horizontal: horizontalInset,
          vertical: verticalInset,
        ),
        titlePadding: EdgeInsets.zero,
        contentPadding: EdgeInsets.zero,
        actionsPadding: EdgeInsets.zero,
        content: innerBox,
      );
    }

    return Dialog(
      alignment: Alignment.center,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: verticalInset,
      ),
      child: innerBox,
    );
  }
}

/// Modal Nivel 3 para confirmaciones simples o destructivas sin cabecera pesada.
class AppConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final IconData icon;
  final bool isDestructive;
  final bool useAlertDialogWrapper;

  const AppConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Confirmar',
    this.cancelLabel = 'Cancelar',
    this.icon = Icons.warning_amber_rounded,
    this.isDestructive = false,
    this.useAlertDialogWrapper = true,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirmar',
    String cancelLabel = 'Cancelar',
    IconData icon = Icons.warning_amber_rounded,
    bool isDestructive = false,
    bool barrierDismissible = true,
    bool useAlertDialogWrapper = true,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) => AppConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        icon: icon,
        isDestructive: isDestructive,
        useAlertDialogWrapper: useAlertDialogWrapper,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final toneColor = isDestructive ? AppColors.danger : AppColors.amber;
    final badgeBg =
        isDestructive ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7);
    final actionColor = isDestructive ? AppColors.danger : AppColors.primary;

    final body = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: badgeBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: toneColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        message,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                  ),
                  child: Text(cancelLabel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: actionColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 11,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(confirmLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );

    if (useAlertDialogWrapper) {
      return AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        contentPadding: EdgeInsets.zero,
        titlePadding: EdgeInsets.zero,
        actionsPadding: EdgeInsets.zero,
        content: body,
      );
    }

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: body,
    );
  }
}
