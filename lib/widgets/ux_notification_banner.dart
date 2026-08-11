import 'package:flutter/material.dart';

enum UxNotificationTone { info, success, warning, error }

class UxNotificationBanner extends StatelessWidget {
  const UxNotificationBanner({
    super.key,
    required this.message,
    this.title,
    this.tone = UxNotificationTone.info,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
  });

  final String message;
  final String? title;
  final UxNotificationTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final presentation = switch (tone) {
      UxNotificationTone.info => (
        icon: Icons.info_outline_rounded,
        background: colors.secondaryContainer,
        foreground: colors.onSecondaryContainer,
      ),
      UxNotificationTone.success => (
        icon: Icons.check_circle_outline_rounded,
        background: colors.tertiaryContainer,
        foreground: colors.onTertiaryContainer,
      ),
      UxNotificationTone.warning => (
        icon: Icons.warning_amber_rounded,
        background: colors.surfaceContainerHighest,
        foreground: colors.onSurfaceVariant,
      ),
      UxNotificationTone.error => (
        icon: Icons.error_outline_rounded,
        background: colors.errorContainer,
        foreground: colors.onErrorContainer,
      ),
    };

    return Semantics(
      liveRegion: true,
      container: true,
      label: [title, message].whereType<String>().join('. '),
      child: Material(
        color: presentation.background,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                presentation.icon,
                color: presentation.foreground,
                semanticLabel: null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (title != null && title!.trim().isNotEmpty) ...[
                      Text(
                        title!,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: presentation.foreground,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: presentation.foreground,
                      ),
                    ),
                    if (actionLabel != null && onAction != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: onAction,
                          style: TextButton.styleFrom(
                            foregroundColor: presentation.foreground,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(actionLabel!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: onDismiss,
                  color: presentation.foreground,
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class UxConfirmationSheet extends StatelessWidget {
  const UxConfirmationSheet({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    this.icon = Icons.help_outline_rounded,
    this.destructive = false,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final IconData icon;
  final bool destructive;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    required String cancelLabel,
    IconData icon = Icons.help_outline_rounded,
    bool destructive = false,
    bool dismissible = true,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      isDismissible: dismissible,
      enableDrag: dismissible,
      showDragHandle: true,
      builder: (_) => UxConfirmationSheet(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        icon: icon,
        destructive: destructive,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final actionColor = destructive ? colors.error : colors.primary;

    return Semantics(
      container: true,
      namesRoute: true,
      explicitChildNodes: true,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + bottomInset),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: destructive
                      ? colors.errorContainer
                      : colors.primaryContainer,
                  foregroundColor: destructive
                      ? colors.onErrorContainer
                      : colors.onPrimaryContainer,
                  child: Icon(icon, size: 30),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: actionColor,
                      foregroundColor: destructive
                          ? colors.onError
                          : colors.onPrimary,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: Text(confirmLabel),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(cancelLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
