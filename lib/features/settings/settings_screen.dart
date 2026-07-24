import 'package:flutter/material.dart';

import '../../data/local_progress_store.dart';
import '../../localization/app_strings.dart';
import '../../services/reminder_notification_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store});
  final LocalProgressStore store;

  @override
  Widget build(BuildContext context) {
    final reminders = ReminderNotificationService.instance;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings'))),
      body: AnimatedBuilder(
        animation: store,
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
                      selected: <ThemeMode>{store.themeMode},
                      onSelectionChanged: (values) =>
                          store.setThemeMode(values.first),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: store.highContrast,
                      onChanged: store.setHighContrast,
                      title: Text(context.tr('high_contrast')),
                      subtitle: Text(context.tr('high_contrast_subtitle')),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Notifications',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Card(
              child: ValueListenableBuilder<bool>(
                valueListenable: reminders.enabled,
                builder: (context, enabled, _) => SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_outlined),
                  value: enabled,
                  title: const Text('Daily Sudoku challenges'),
                  subtitle: const Text(
                    'Three optional reminders each day at 09:00, 15:00, and 20:30. You can turn them off at any time.',
                  ),
                  onChanged: (value) =>
                      _setDailyReminders(context, reminders, value),
                ),
              ),
            ),
            const SizedBox(height: 22),
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
                    store.completedLevelCount,
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
    BuildContext context,
    ReminderNotificationService service,
    bool value,
  ) async {
    if (!value) {
      await service.disable();
      return;
    }

    final enabled = await service.requestPermissionAndEnable();
    if (!enabled && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Notification permission was not granted. Daily reminders remain off.',
          ),
        ),
      );
    }
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
    if (approved == true) await store.clearProgress();
  }
}
