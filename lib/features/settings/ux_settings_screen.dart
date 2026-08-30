import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/user_safe_error.dart';
import '../../data/local_progress_store.dart';
import '../../localization/app_strings.dart';
import '../../localization/settings_strings.dart';
import '../../services/account_deletion_service.dart';
import '../../services/ads_service.dart';
import '../../services/economy_service.dart';
import '../../services/firebase_services.dart';
import '../../services/firebase_session_service.dart';
import '../../services/haptic_feedback_service.dart';
import '../../services/player_profile_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/reminder_notification_service.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/in_page_header.dart';

class UxSettingsScreen extends StatefulWidget {
  const UxSettingsScreen({super.key, required this.store});

  final LocalProgressStore store;

  @override
  State<UxSettingsScreen> createState() => _UxSettingsScreenState();
}

class _UxSettingsScreenState extends State<UxSettingsScreen> {
  static const Color _playAccent = Color(0xFF66C7FF);
  static const Color _notificationAccent = Color(0xFFFFC94D);
  static const Color _privacyAccent = Color(0xFFB7A9FF);
  static const Color _dataAccent = Color(0xFFFF8A3D);
  static final Uri _privacyPolicyUri = Uri.parse(
    'https://devoviastudio.com/privacy/sudoku-duel',
  );

  bool _pushBusy = false;
  bool _analyticsBusy = false;
  bool _crashBusy = false;
  bool _profileBusy = false;
  bool _adPrivacyBusy = false;
  bool _deleteBusy = false;
  int _section = 0;

  @override
  void initState() {
    super.initState();
    unawaited(HapticFeedbackService.instance.initialize());
    if (SocialApiClient.instance.configured) {
      unawaited(_loadProfile());
    }
  }

  @override
  Widget build(BuildContext context) {
    final reminders = ReminderNotificationService.instance;
    final push = PushNotificationService.instance;
    final firebase = FirebaseServices.instance;
    final haptics = HapticFeedbackService.instance;
    final ads = AdsService.instance;
    final socialAvailable =
        push.configured && SocialApiClient.instance.configured;
    final sections = <_SettingsSectionData>[
      _SettingsSectionData(
        label: context.tr('play'),
        icon: Icons.touch_app_outlined,
        accent: _playAccent,
      ),
      _SettingsSectionData(
        label: context.tr('notifications'),
        icon: Icons.notifications_outlined,
        accent: _notificationAccent,
      ),
      _SettingsSectionData(
        label: context.tr('privacy'),
        icon: Icons.privacy_tip_outlined,
        accent: _privacyAccent,
      ),
      _SettingsSectionData(
        label: context.tr('data'),
        icon: Icons.storage_outlined,
        accent: _dataAccent,
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      body: AppBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 650;
              final horizontal = constraints.maxWidth < 360 ? 12.0 : 16.0;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 740),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      compact ? 4 : 8,
                      horizontal,
                      compact ? 8 : 18,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        InPageHeader(
                          title: context.tr('settings'),
                          padding: EdgeInsets.only(bottom: compact ? 6 : 10),
                        ),
                        _SettingsSectionPicker(
                          sections: sections,
                          selected: _section,
                          compact: compact,
                          onSelected: (value) =>
                              setState(() => _section = value),
                        ),
                        SizedBox(height: compact ? 8 : 12),
                        Expanded(
                          child: AnimatedBuilder(
                            animation: widget.store,
                            builder: (context, _) => SingleChildScrollView(
                              physics: const ClampingScrollPhysics(),
                              child: _sectionBody(
                                context,
                                reminders: reminders,
                                push: push,
                                firebase: firebase,
                                haptics: haptics,
                                ads: ads,
                                socialAvailable: socialAvailable,
                                compact: compact,
                              ),
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
      ),
    );
  }

  Widget _sectionBody(
    BuildContext context, {
    required ReminderNotificationService reminders,
    required PushNotificationService push,
    required FirebaseServices firebase,
    required HapticFeedbackService haptics,
    required AdsService ads,
    required bool socialAvailable,
    required bool compact,
  }) {
    switch (_section) {
      case 0:
        return _SettingsPanel(
          title: context.tr('play'),
          accent: _playAccent,
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
      case 1:
        return _SettingsPanel(
          title: context.tr('notifications'),
          accent: _notificationAccent,
          compact: compact,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: reminders.enabled,
                builder: (context, enabled, _) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: const Icon(Icons.notifications_active_outlined),
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
                  trailing: Icon(
                    enabled
                        ? Icons.check_circle_rounded
                        : Icons.notifications_paused_outlined,
                    size: 20,
                    color: enabled
                        ? _notificationAccent
                        : Colors.white.withValues(alpha: .46),
                  ),
                ),
              ),
              const _SettingsDivider(),
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
      case 2:
        return _SettingsPanel(
          title: context.tr('privacy'),
          accent: _privacyAccent,
          compact: compact,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: const Icon(Icons.policy_outlined),
                title: Text(
                  SettingsStrings.privacyPolicyTitle(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  SettingsStrings.privacyPolicySubtitle(context),
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.open_in_new_rounded, size: 19),
                onTap: _openPrivacyPolicy,
              ),
              const _SettingsDivider(),
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
              const _SettingsDivider(),
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
              const _SettingsDivider(),
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
              ValueListenableBuilder<bool>(
                valueListenable: ads.privacyOptionsRequired,
                builder: (context, required, _) {
                  if (!required || ads.noAds) return const SizedBox.shrink();
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _SettingsDivider(),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        leading: const Icon(Icons.ads_click_rounded),
                        title: Text(
                          context.tr('ad_privacy_choices'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          context.tr('ad_privacy_choices_subtitle'),
                          maxLines: compact ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: _adPrivacyBusy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.chevron_right_rounded),
                        onTap: _adPrivacyBusy
                            ? null
                            : () => _showAdPrivacy(ads),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      default:
        return _SettingsPanel(
          title: context.tr('data'),
          accent: _dataAccent,
          compact: compact,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: const Icon(Icons.restart_alt_rounded),
                title: Text(
                  context.tr('clear_career_progress'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  context.tr('completed_levels', <Object>[
                    widget.store.completedCareerLevelCount,
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _confirmClear,
              ),
              const _SettingsDivider(),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: Icon(
                  Icons.delete_forever_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  context.tr('delete_player_account'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  context.tr('delete_player_account_body'),
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: _deleteBusy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right_rounded),
                onTap: _deleteBusy ? null : _deleteAccount,
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

  Future<void> _openPrivacyPolicy() async {
    try {
      final opened = await launchUrl(
        _privacyPolicyUri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) _snack('try_again_when_connected');
    } catch (_) {
      if (mounted) _snack('try_again_when_connected');
    }
  }

  Future<void> _showAdPrivacy(AdsService service) async {
    if (_adPrivacyBusy) return;
    setState(() => _adPrivacyBusy = true);
    try {
      await service.showPrivacyOptions();
    } catch (_) {
      if (mounted) _snack('try_again_when_connected');
    } finally {
      if (mounted) setState(() => _adPrivacyBusy = false);
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

  Future<void> _deleteAccount() async {
    final user = FirebaseSessionService.currentUser;
    final passwordRequired =
        user != null &&
        !user.isAnonymous &&
        user.providerData.any((provider) => provider.providerId == 'password');
    final confirmation = TextEditingController();
    final password = TextEditingController();
    var hidden = true;

    final result = await showDialog<({String confirmation, String password})>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final valid =
              confirmation.text.trim().toUpperCase() == 'DELETE' &&
              (!passwordRequired || password.text.length >= 8);
          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
            title: Text(context.tr('delete_player_account_question')),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(context.tr('delete_player_account_warning')),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmation,
                      autofocus: true,
                      autocorrect: false,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: context.tr('type_delete'),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    if (passwordRequired) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: password,
                        obscureText: hidden,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: context.tr('current_password'),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setDialogState(() => hidden = !hidden),
                            icon: Icon(
                              hidden
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(context.tr('cancel')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: valid
                    ? () => Navigator.of(dialogContext).pop((
                        confirmation: confirmation.text,
                        password: password.text,
                      ))
                    : null,
                child: Text(context.tr('delete_permanently')),
              ),
            ],
          );
        },
      ),
    );

    confirmation.dispose();
    password.dispose();
    if (result == null || !mounted) return;

    setState(() => _deleteBusy = true);
    try {
      await AccountDeletionService.instance.deleteCurrentAccount(
        password: passwordRequired ? result.password : null,
      );
      PlayerProfileService.instance.current.value = null;
      await EconomyService.instance.refresh(showLoading: false);
      if (mounted) _snack('player_account_deleted');
    } on AccountDeletionException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserSafeError.message(context, error))),
        );
      }
    } finally {
      if (mounted) setState(() => _deleteBusy = false);
    }
  }

  void _snack(String key) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.tr(key))));
  }
}

class _SettingsSectionData {
  const _SettingsSectionData({
    required this.label,
    required this.icon,
    required this.accent,
  });

  final String label;
  final IconData icon;
  final Color accent;
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
        final columns = constraints.maxWidth >= 560 ? 4 : 2;
        final spacing = compact ? 7.0 : 9.0;
        final width =
            (constraints.maxWidth - ((columns - 1) * spacing)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (var index = 0; index < sections.length; index++)
              SizedBox(
                width: width,
                height: compact ? 42 : 48,
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
    final foreground = selected
        ? data.accent
        : Colors.white.withValues(alpha: .70);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: data.accent.withValues(alpha: selected ? .12 : .035),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected
                  ? data.accent.withValues(alpha: .42)
                  : Colors.white.withValues(alpha: .07),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(data.icon, size: compact ? 17 : 19, color: foreground),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: compact ? 10.5 : 11.5,
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
    required this.accent,
    required this.compact,
    required this.child,
  });

  final String title;
  final Color accent;
  final bool compact;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: .16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 6 : 8,
          compact ? 9 : 12,
          compact ? 6 : 8,
          compact ? 7 : 10,
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            listTileTheme: ListTileThemeData(
              iconColor: Colors.white.withValues(alpha: .76),
              textColor: Colors.white,
              subtitleTextStyle: TextStyle(
                color: Colors.white.withValues(alpha: .58),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            dividerColor: Colors.white.withValues(alpha: .06),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 20,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: compact ? 3 : 6),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 12,
      endIndent: 12,
      color: Colors.white.withValues(alpha: .06),
    );
  }
}
