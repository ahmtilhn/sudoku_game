import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../data/local_progress_store.dart';
import '../../localization/app_strings.dart';
import '../../localization/settings_strings.dart';
import '../../services/firebase_services.dart';
import '../../services/haptic_feedback_service.dart';
import '../../services/player_profile_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/reminder_notification_service.dart';
import '../../services/social_api_client.dart';
import '../../widgets/in_page_header.dart';
import '../economy/wallet_history_screen.dart';
import 'account_protection_screen.dart';

class UxSettingsScreen extends StatefulWidget {
  const UxSettingsScreen({super.key, required this.store});

  // Kept in the constructor for route compatibility. Settings no longer owns
  // career/theme state; LocalProgressStore remains the app-level route model.
  final LocalProgressStore store;

  @override
  State<UxSettingsScreen> createState() => _UxSettingsScreenState();
}

class _UxSettingsScreenState extends State<UxSettingsScreen> {
  bool _dailyBusy = false;
  bool _pushBusy = false;
  bool _analyticsBusy = false;
  bool _crashBusy = false;
  bool _profileBusy = false;
  int _section = 0;

  @override
  void initState() {
    super.initState();
    unawaited(HapticFeedbackService.instance.initialize());
    if (SocialApiClient.instance.configured) {
      unawaited(_loadProfile());
    }
  }

  void _open(Widget screen) {
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final reminders = ReminderNotificationService.instance;
    final push = PushNotificationService.instance;
    final firebase = FirebaseServices.instance;
    final haptics = HapticFeedbackService.instance;
    final socialAvailable =
        push.configured && SocialApiClient.instance.configured;
    final sections = <_SettingsSectionData>[
      _SettingsSectionData(
        label: context.tr('player_account'),
        icon: Icons.person_outline_rounded,
      ),
      _SettingsSectionData(
        label: context.tr('play'),
        icon: Icons.touch_app_outlined,
      ),
      _SettingsSectionData(
        label: context.tr('notifications'),
        icon: Icons.notifications_outlined,
      ),
      _SettingsSectionData(
        label: context.tr('privacy'),
        icon: Icons.privacy_tip_outlined,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 650;
            final horizontal = constraints.maxWidth < 360 ? 12.0 : 16.0;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    compact ? 4 : 10,
                    horizontal,
                    compact ? 8 : 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InPageHeader(
                        title: context.tr('settings'),
                        padding: EdgeInsets.only(bottom: compact ? 5 : 10),
                      ),
                      _SettingsSectionPicker(
                        sections: sections,
                        selected: _section,
                        compact: compact,
                        onSelected: (value) => setState(() => _section = value),
                      ),
                      SizedBox(height: compact ? 7 : 12),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: _sectionBody(
                            context,
                            reminders: reminders,
                            push: push,
                            firebase: firebase,
                            haptics: haptics,
                            socialAvailable: socialAvailable,
                            compact: compact,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _sectionBody(
    BuildContext context, {
    required ReminderNotificationService reminders,
    required PushNotificationService push,
    required FirebaseServices firebase,
    required HapticFeedbackService haptics,
    required bool socialAvailable,
    required bool compact,
  }) {
    switch (_section) {
      case 0:
        return _SettingsPanel(
          title: context.tr('player_account'),
          compact: compact,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                minTileHeight: compact ? 54 : 64,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: const Icon(Icons.shield_outlined),
                title: Text(
                  context.tr('protect_player_account'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  context.tr('account_protection_banner_body'),
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _open(const AccountProtectionScreen()),
              ),
              const Divider(height: 1),
              ListTile(
                minTileHeight: compact ? 54 : 58,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text(
                  context.tr('coin_history'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  context.tr('server_wallet_history'),
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _open(const WalletHistoryScreen()),
              ),
            ],
          ),
        );
      case 1:
        return _SettingsPanel(
          title: context.tr('play'),
          compact: compact,
          child: ValueListenableBuilder<bool>(
            valueListenable: haptics.enabled,
            builder: (context, enabled, _) => SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              secondary: const Icon(Icons.vibration_rounded),
              value: enabled,
              onChanged: haptics.setEnabled,
              title: Text(
                SettingsStrings.hapticsTitle(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                SettingsStrings.hapticsSubtitle(context),
                maxLines: compact ? 2 : 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        );
      case 2:
        return _SettingsPanel(
          title: context.tr('notifications'),
          compact: compact,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: reminders.enabled,
                builder: (context, enabled, _) => SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  secondary: const Icon(Icons.notifications_active_outlined),
                  value: enabled,
                  onChanged: _dailyBusy
                      ? null
                      : (value) => _setDaily(reminders, value),
                  title: Text(
                    context.tr('daily_sudoku_challenges'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    context.tr('daily_sudoku_challenges_subtitle'),
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const Divider(height: 1),
              ValueListenableBuilder<bool>(
                valueListenable: push.enabled,
                builder: (context, enabled, _) => SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  secondary: const Icon(Icons.notifications_outlined),
                  value: enabled,
                  onChanged: !socialAvailable || _pushBusy
                      ? null
                      : (value) => _setPush(push, value),
                  title: Text(
                    context.tr('online_challenge_notifications'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    socialAvailable
                        ? context.tr('online_challenge_notifications_subtitle')
                        : context.tr(
                            'online_challenge_notifications_unavailable',
                          ),
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        );
      default:
        return _SettingsPanel(
          title: context.tr('privacy'),
          compact: compact,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<PlayerProfilePreferences?>(
                valueListenable: PlayerProfileService.instance.current,
                builder: (context, profile, _) {
                  final canChange =
                      !_profileBusy &&
                      SocialApiClient.instance.configured &&
                      profile != null &&
                      profile.profileConfirmed &&
                      profile.username.trim().isNotEmpty;
                  return SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    secondary: const Icon(Icons.manage_search_rounded),
                    value: profile?.discoverable ?? false,
                    onChanged: canChange ? _setDiscoverable : null,
                    title: Text(
                      context.tr('discoverable_by_players'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      profile == null
                          ? context.tr('discoverable_by_players_body')
                          : profile.discoverable
                          ? context.tr('profile_discovery_on')
                          : context.tr('profile_discovery_off'),
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              ValueListenableBuilder<bool>(
                valueListenable: firebase.analyticsEnabled,
                builder: (context, enabled, _) => SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  secondary: const Icon(Icons.insights_outlined),
                  value: enabled,
                  onChanged: _analyticsBusy
                      ? null
                      : (value) => _setAnalytics(firebase, value),
                  title: Text(
                    context.tr('analytics_sharing'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    context.tr('analytics_sharing_subtitle'),
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const Divider(height: 1),
              ValueListenableBuilder<bool>(
                valueListenable: firebase.crashReportingEnabled,
                builder: (context, enabled, _) => SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  secondary: const Icon(Icons.bug_report_outlined),
                  value: enabled,
                  onChanged: _crashBusy
                      ? null
                      : (value) => _setCrash(firebase, value),
                  title: Text(
                    context.tr('crash_reports_sharing'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    context.tr('crash_reports_sharing_subtitle'),
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }

  Future<void> _loadProfile() async {
    if (_profileBusy) return;
    setState(() => _profileBusy = true);
    try {
      await PlayerProfileService.instance.load();
    } catch (_) {
      // Discoverability remains disabled while the profile is unavailable.
    } finally {
      if (mounted) setState(() => _profileBusy = false);
    }
  }

  Future<void> _setDiscoverable(bool value) async {
    if (_profileBusy) return;
    final profile = PlayerProfileService.instance.current.value;
    if (profile == null || profile.username.trim().isEmpty) return;

    setState(() => _profileBusy = true);
    try {
      await PlayerProfileService.instance.update(
        username: profile.username,
        displayName: profile.displayName,
        discoverable: value,
        nameSource: profile.nameSource,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserSafeError.message(context, error))),
        );
      }
    } finally {
      if (mounted) setState(() => _profileBusy = false);
    }
  }

  Future<void> _setDaily(
    ReminderNotificationService service,
    bool value,
  ) async {
    setState(() => _dailyBusy = true);
    try {
      if (value) {
        final enabled = await service.requestPermissionAndEnable();
        if (!enabled && mounted) {
          _snack('daily_reminder_permission_denied');
        }
      } else {
        await service.disable();
      }
    } finally {
      if (mounted) setState(() => _dailyBusy = false);
    }
  }

  Future<void> _setPush(PushNotificationService service, bool value) async {
    setState(() => _pushBusy = true);
    try {
      if (value) {
        final registered = await service.requestPermissionAndRegister();
        if (!registered && mounted) {
          _snack(
            service.permissionGranted.value
                ? 'try_again_when_connected'
                : 'challenge_notification_permission_denied',
          );
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

  void _snack(String key) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.tr(key))));
  }
}

class _SettingsSectionData {
  const _SettingsSectionData({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class _SettingsSectionPicker extends StatelessWidget {
  const _SettingsSectionPicker({
    required this.sections,
    required this.selected,
    required this.compact,
    required this.onSelected,
  });

  final List<_SettingsSectionData> sections;
  final int selected;
  final bool compact;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 520 ? 4 : 2;
        final spacing = compact ? 6.0 : 8.0;
        final width =
            (constraints.maxWidth - ((columns - 1) * spacing)) / columns;

        return Wrap(
          alignment: WrapAlignment.center,
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (var index = 0; index < sections.length; index++)
              SizedBox(
                width: width,
                height: compact ? 40 : 46,
                child: _SettingsSectionButton(
                  data: sections[index],
                  selected: selected == index,
                  compact: compact,
                  onTap: () => onSelected(index),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SettingsSectionButton extends StatelessWidget {
  const _SettingsSectionButton({
    required this.data,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final _SettingsSectionData data;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(data.icon, size: compact ? 17 : 19),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 10 : 11,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.title,
    required this.compact,
    required this.child,
  });

  final String title;
  final bool compact;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 6 : 8,
          compact ? 8 : 12,
          compact ? 6 : 8,
          compact ? 6 : 10,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisSize: CrossAxisSize.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            SizedBox(height: compact ? 2 : 5),
            child,
          ],
        ),
      ),
    );
  }
}
