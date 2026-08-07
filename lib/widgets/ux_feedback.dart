import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../localization/ux_copy.dart';
import 'duel_asset_icon.dart';

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
      constraints: const BoxConstraints(minWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: scheme.primary),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 10.5,
                    height: 1.05,
                  ),
                ),
              ],
            ),
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
    final artwork = icon == Icons.emoji_events_rounded
        ? DuelAsset.resultVictoryTrophyPro
        : icon == Icons.flag_rounded
        ? DuelAsset.resultDefeatTrophyPro
        : null;
    return Semantics(
      liveRegion: true,
      header: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: artwork != null
                ? DuelAssetIcon(artwork, size: 110)
                : Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: .16),
                      border: Border.all(color: color.withValues(alpha: .45)),
                    ),
                    child: Icon(icon, size: 46, color: color),
                  ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
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
    final content = Column(
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
          FilledButton(
            onPressed: onPrimary,
            child: Text(primaryLabel!),
          ),
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
    );

    final fixedResultStyle = icon == Icons.flag_rounded;
    return SafeArea(
      top: false,
      child: fixedResultStyle
          ? Padding(
              key: const ValueKey<String>('fixed-round-lost-outcome'),
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
              child: content,
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
              child: content,
            ),
    );
  }
}
