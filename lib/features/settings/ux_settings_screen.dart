import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/local_progress_store.dart';
import '../../localization/app_strings.dart';
import '../../services/firebase_services.dart';
import '../../services/push_notification_service.dart';
import '../../services/social_api_client.dart';
import '../economy/wallet_history_screen.dart';
import 'account_protection_screen.dart';
import 'service_diagnostics_screen.dart';

class UxSettingsScreen extends StatefulWidget {
  const UxSettingsScreen({super.key, required this.store});

  final LocalProgressStore store;

  @override
  State<UxSettingsScreen> createState() => _UxSettingsScreenState();
}

class _UxSettingsScreenState extends State<UxSettingsScreen> {
  bool _pushBusy = false;
  bool _analyticsBusy = false;
  bool _crashBusy = false;

  void _open(Widget screen) {
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final push = PushNotificationService.instance;
    final firebase = FirebaseServices.instance;
    final socialAvailable =
        push.configured && SocialApiClient.instance.configured;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings'))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: AnimatedBuilder(
              animation: widget.store,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _heading(context.tr('player_account')),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          minTileHeight: 64,
                          leading: const Icon(Icons.shield_outlined),
                          title: Text(context.tr('protect_player_account')),
                          subtitle: Text(
                            context.tr('account_protection_banner_body'),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _open(const AccountProtectionScreen()),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          minTileHeight: 58,
                          leading: const Icon(Icons.health_and_safety_outlined),
                          title: Text(context.tr('service_diagnostics')),
                          subtitle: Text(
                            context.tr('service_diagnostics_subtitle'),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _open(const ServiceDiagnosticsScreen()),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          minTileHeight: 58,
                          leading: const Icon(Icons.receipt_long_outlined),
                          title: Text(context.tr('coin_history')),
                          subtitle: Text(context.tr('server_wallet_history')),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _open(const WalletHistoryScreen()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  _heading(context.tr('appearance')),
                  Card(
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      secondary: const Icon(Icons.contrast_rounded),
                      value: widget.store.highContrast,
                      onChanged: widget.store.setHighContrast,
                      title: Text(context.tr('high_contrast')),
                      subtitle: Text(context.tr('high_contrast_subtitle')),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _heading(context.tr('notifications')),
                  Card(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: push.enabled,
                      builder: (context, enabled, _) => SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        secondary: const Icon(Icons.notifications_outlined),
                        value: enabled,
                        onChanged: !socialAvailable || _pushBusy
                            ? null
                            : (value) => _setPush(push, value),
                        title: Text(
                          context.tr('online_challenge_notifications'),
                        ),
                        subtitle: Text(
                          socialAvailable
                              ? context.tr(
                                  'online_challenge_notifications_subtitle',
                                )
                              : context.tr(
                                  'online_challenge_notifications_unavailable',
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _heading(context.tr('privacy')),
                  Card(
                    child: Column(
                      children: [
                        ValueListenableBuilder<bool>(
                          valueListenable: firebase.analyticsEnabled,
                          builder: (context, enabled, _) => SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            secondary: const Icon(Icons.insights_outlined),
                            value: enabled,
                            onChanged: _analyticsBusy
                                ? null
                                : (value) => _setAnalytics(firebase, value),
                            title: Text(context.tr('analytics_sharing')),
                            subtitle: Text(
                              context.tr('analytics_sharing_subtitle'),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        ValueListenableBuilder<bool>(
                          valueListenable: firebase.crashReportingEnabled,
                          builder: (context, enabled, _) => SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            secondary: const Icon(Icons.bug_report_outlined),
                            value: enabled,
                            onChanged: _crashBusy
                                ? null
                                : (value) => _setCrash(firebase, value),
                            title: Text(context.tr('crash_reports_sharing')),
                            subtitle: Text(
                              context.tr('crash_reports_sharing_subtitle'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  _heading(context.tr('data')),
                  Card(
                    child: ListTile(
                      minTileHeight: 64,
                      leading: const Icon(Icons.delete_outline_rounded),
                      title: Text(context.tr('clear_career_progress')),
                      subtitle: Text(
                        context.tr('completed_levels', <Object>[
                          widget.store.completedCareerLevelCount,
                        ]),
                      ),
                      onTap: _confirmClear,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
      ),
    );
  }

  Future<void> _setPush(PushNotificationService service, bool value) async {
    setState(() => _pushBusy = true);
    try {
      if (value) {
        final enabled = await service.requestPermissionAndRegister();
        if (!enabled && mounted) {
          _snack('challenge_notification_permission_denied');
        }
      } else {
        await service.disableChallengeNotifications();
      }
    } finally {
      if (mounted) setState(() => _pushBusy = false);
    }
  }

  Future<void> _setAnalytics(FirebaseServices service, bool value) async {
    setState(() => _analyticsBusy = true);
    try {
      await service.setAnalyticsEnabled(value);
    } finally {
      if (mounted) setState(() => _analyticsBusy = false);
    }
  }

  Future<void> _setCrash(FirebaseServices service, bool value) async {
    setState(() => _crashBusy = true);
    try {
      await service.setCrashReportingEnabled(value);
    } finally {
      if (mounted) setState(() => _crashBusy = false);
    }
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('clear_progress_title')),
        content: Text(context.tr('clear_progress_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.tr('clear')),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.store.clearProgress();
  }

  void _snack(String key) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.tr(key))));
  }
}
