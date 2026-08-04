import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../localization/ux_copy.dart';

Future<T?> showAdaptiveBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useSafeArea = false,
  bool showDragHandle = true,
  bool isScrollControlled = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useSafeArea: useSafeArea,
    showDragHandle: showDragHandle,
    isScrollControlled: isScrollControlled,
  );
}

class UxStatePanel extends StatelessWidget {
  const UxStatePanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  factory UxStatePanel.error(
    BuildContext context, {
    required String message,
    VoidCallback? onRetry,
  }) {
    return UxStatePanel(
      icon: Icons.cloud_off_rounded,
      title: context.tr('online_account_unavailable'),
      message: message,
      actionLabel: onRetry == null ? null : context.tr('retry'),
      onAction: onRetry,
    );
  }

  factory UxStatePanel.empty(
    BuildContext context, {
    String? title,
    String? message,
    IconData icon = Icons.inbox_outlined,
  }) {
    return UxStatePanel(
      icon: icon,
      title: title ?? UxCopy.noData(context),
      message: message ?? UxCopy.noData(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.all(compact ? 14 : 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 34 : 46, color: scheme.primary),
              SizedBox(height: compact ? 8 : 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              if (onAction != null && actionLabel != null) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class UxMetricTile extends StatelessWidget {
  const UxMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 118),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(height: 5),
          ],
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class UxOutcomeHeader extends StatelessWidget {
  const UxOutcomeHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.accent,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accent ?? scheme.primary;
    return Semantics(
      liveRegion: true,
      header: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: .16),
                border: Border.all(color: color.withValues(alpha: .45)),
              ),
              child: Icon(icon, size: 42, color: color),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class UxOutcomeSheet extends StatelessWidget {
  const UxOutcomeSheet({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.metrics = const <Widget>[],
    this.details,
    this.footer,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.tertiaryLabel,
    this.onTertiary,
    this.accent,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> metrics;
  final Widget? details;
  final Widget? footer;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final String? tertiaryLabel;
  final VoidCallback? onTertiary;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UxOutcomeHeader(
              icon: icon,
              title: title,
              subtitle: subtitle,
              accent: accent,
            ),
            if (metrics.isNotEmpty) ...[
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: metrics,
              ),
            ],
            if (details != null) ...[
              const SizedBox(height: 18),
              details!,
            ],
            if (footer != null) ...[
              const SizedBox(height: 16),
              footer!,
            ],
            if (onPrimary != null && primaryLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onPrimary, child: Text(primaryLabel!)),
            ],
            if (onSecondary != null && secondaryLabel != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: onSecondary,
                child: Text(secondaryLabel!),
              ),
            ],
            if (onTertiary != null && tertiaryLabel != null)
              TextButton(onPressed: onTertiary, child: Text(tertiaryLabel!)),
          ],
        ),
      ),
    );
  }
}
