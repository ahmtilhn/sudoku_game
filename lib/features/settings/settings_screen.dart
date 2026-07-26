import 'package:flutter/material.dart';

import '../../data/local_progress_store.dart';
import '../../localization/app_strings.dart';
import '../../services/ads_service.dart';
import '../../services/firebase_services.dart';
import '../../services/push_notification_service.dart';
import '../../services/reminder_notification_service.dart';
import '../../services/social_api_client.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store});
  final LocalProgressStore store;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _updatingDailyReminders = false;
  bool _updatingChallengePush = false;
  bool _updatingAnalytics = false;
  bool _updatingCrashReports = false;

  @override
  Widget build(BuildContext context) {
    final reminders = ReminderNotificationService.instance;
    final push = PushNotificationService.instance;
    final firebase = FirebaseServices.instance;
    final ads = AdsService.instance;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings'))),
      body: AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Text(
              context.tr('appearance'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<ThemeMode>(
                      segments: [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text(context.tr('system')),
                          icon: const Icon(Icons.settings_brightness),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text(context.tr('light')),
                          icon: const Icon(Icons.light_mode_outlined),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text(context.tr('dark')),
                          icon: const Icon(Icons.dark_mode_outlined),
                        ),
                      ],
                      selected: <ThemeMode>{widget.store.themeMode},
                      onSelectionChanged: (values) =>
                          widget.store.setThemeMode(values.first),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: widget.store.highContrast,
                      onChanged: widget.store.setHighContrast,
                      title: Text(context.tr('high_contrast')),
                      subtitle: Text(context.tr('high_contrast_subtitle')),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              context.tr('notifications'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Card(
              child: ValueListenableBuilder<bool>(
                valueListenable: reminders.enabled,
                builder: (context, enabled, _) => SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_outlined),
                  value: enabled && !_updatingDailyReminders,
                  title: Text(context.tr('daily_sudoku_challenges')),
                  subtitle: Text(
                    context.tr('daily_sudoku_challenges_subtitle'),
                  ),
                  onChanged: _updatingDailyReminders
                      ? null
                      : (value) => _setDailyReminders(reminders, value),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Card(
              child: ValueListenableBuilder<bool>(
                valueListenable: push.enabled,
                builder: (context, enabled, _) {
                  final available =
                      push.configured && SocialApiClient.instance.configured;
                  return SwitchListTile(
                    secondary: const Icon(Icons.notifications_outlined),
                    value: enabled && !_updatingChallengePush,
                    title: Text(context.tr('online_challenge_notifications')),
                    subtitle: Text(
                      available
                          ? context.tr(
                              'online_challenge_notifications_subtitle',
                            )
                          : context.tr(
                              'online_challenge_notifications_unavailable',
                            ),
                    ),
                    onChanged: !available || _updatingChallengePush
                        ? null
                        : (value) => _setChallengeNotifications(push, value),
                  );
                },
              ),
            ),
            const SizedBox(height: 22),
            Text(
              context.tr('privacy'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Card(
              child: Column(
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: firebase.analyticsEnabled,
                    builder: (context, enabled, _) => SwitchListTile(
                      secondary: const Icon(Icons.insights_outlined),
                      value: enabled && !_updatingAnalytics,
                      title: Text(context.tr('analytics_sharing')),
                      subtitle: Text(context.tr('analytics_sharing_subtitle')),
                      onChanged: _updatingAnalytics
                          ? null
                          : (value) => _setAnalytics(firebase, value),
                    ),
                  ),
                  const Divider(height: 1),
                  ValueListenableBuilder<bool>(
                    valueListenable: firebase.crashReportingEnabled,
                    builder: (context, enabled, _) => SwitchListTile(
                      secondary: const Icon(Icons.bug_report_outlined),
                      value: enabled && !_updatingCrashReports,
                      title: Text(context.tr('crash_reports_sharing')),
                      subtitle: Text(
                        context.tr('crash_reports_sharing_subtitle'),
                      ),
                      onChanged: _updatingCrashReports
                          ? null
                          : (value) => _setCrashReports(firebase, value),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            ValueListenableBuilder<bool>(
              valueListenable: ads.privacyOptionsRequired,
              builder: (context, required, _) {
                if (!required) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.tr('ad_privacy'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.privacy_tip_outlined),
                        title: Text(context.tr('ad_privacy_choices')),
                        subtitle: Text(
                          context.tr('ad_privacy_choices_subtitle'),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: ads.showPrivacyOptions,
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],
                );
              },
            ),
            Text(
              context.tr('data'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(context.tr('clear_career_progress')),
                subtitle: Text(
                  context.tr('completed_levels', <Object>[
                    widget.store.completedLevelCount,
                  ]),
                ),
                onTap: () => _confirmClear(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setDailyReminders(
    ReminderNotificationService service,
    bool value,
  ) async {
    setState(() => _updatingDailyReminders = true);
    try {
      if (!value) {
        await service.disable();
        return;
      }

      final enabled = await service.requestPermissionAndEnable();
      if (!enabled && mounted) {
        _showSnack('daily_reminder_permission_denied');
      }
    } finally {
      if (mounted) setState(() => _updatingDailyReminders = false);
    }
  }

  Future<void> _setChallengeNotifications(
    PushNotificationService service,
    bool value,
  ) async {
    setState(() => _updatingChallengePush = true);
    try {
      if (!value) {
        await service.disableChallengeNotifications();
        return;
      }

      final enabled = await service.requestPermissionAndRegister();
      if (!enabled && mounted) {
        _showSnack('challenge_notification_permission_denied');
      }
    } finally {
      if (mounted) setState(() => _updatingChallengePush = false);
    }
  }

  Future<void> _setAnalytics(FirebaseServices service, bool value) async {
    setState(() => _updatingAnalytics = true);
    try {
      await service.setAnalyticsEnabled(value);
    } finally {
      if (mounted) setState(() => _updatingAnalytics = false);
    }
  }

  Future<void> _setCrashReports(FirebaseServices service, bool value) async {
    setState(() => _updatingCrashReports = true);
    try {
      await service.setCrashReportingEnabled(value);
    } finally {
      if (mounted) setState(() => _updatingCrashReports = false);
    }
  }

  void _showSnack(String key) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.tr(key))));
  }

  Future<void> _confirmClear(BuildContext context) async {
    final approved = await showDialog<bool>(
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
    if (approved == true) await widget.store.clearProgress();
  }
}
