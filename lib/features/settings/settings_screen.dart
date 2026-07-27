import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/local_progress_store.dart';
import '../../localization/app_strings.dart';
import '../../services/ads_service.dart';
import '../../services/economy_service.dart';
import '../../services/firebase_services.dart';
import '../../services/firebase_session_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/reminder_notification_service.dart';
import '../../services/social_api_client.dart';
import '../economy/coin_store_screen.dart';
import '../economy/wallet_history_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store});
  final LocalProgressStore store;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final EconomyService _economy = EconomyService.instance;
  bool _updatingDailyReminders = false;
  bool _updatingChallengePush = false;
  bool _updatingAnalytics = false;
  bool _updatingCrashReports = false;
  bool _loadingProfile = false;
  SocialPlayer? _profile;
  String? _profileError;

  @override
  void initState() {
    super.initState();
    _economy.addListener(_onEconomyChanged);
    _economy.initialize();
    _loadProfile();
  }

  @override
  void dispose() {
    _economy.removeListener(_onEconomyChanged);
    super.dispose();
  }

  void _onEconomyChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final reminders = ReminderNotificationService.instance;
    final push = PushNotificationService.instance;
    final firebase = FirebaseServices.instance;
    final ads = AdsService.instance;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings'))),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth >= 840 ? 760.0 : 680.0;
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: AnimatedBuilder(
                  animation: widget.store,
                  builder: (context, _) => ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    children: [
                      _sectionTitle(context, 'Player account'),
                      const SizedBox(height: 10),
                      _PlayerAccountCard(
                        profile: _profile,
                        profileError: _profileError,
                        loading: _loadingProfile,
                        balance: _economy.balance,
                        onRetry: _loadProfile,
                        onEditName: _editDisplayName,
                        onCopyId: _copyPublicId,
                        onOpenStore: () => _open(const CoinStoreScreen()),
                        onOpenHistory: () =>
                            _open(const WalletHistoryScreen()),
                      ),
                      const SizedBox(height: 22),
                      _sectionTitle(context, context.tr('appearance')),
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
                                    icon: const Icon(
                                      Icons.settings_brightness,
                                    ),
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
                                subtitle: Text(
                                  context.tr('high_contrast_subtitle'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      _sectionTitle(context, context.tr('notifications')),
                      const SizedBox(height: 10),
                      Card(
                        child: ValueListenableBuilder<bool>(
                          valueListenable: reminders.enabled,
                          builder: (context, enabled, _) => SwitchListTile(
                            secondary: const Icon(
                              Icons.notifications_active_outlined,
                            ),
                            value: enabled && !_updatingDailyReminders,
                            title: Text(
                              context.tr('daily_sudoku_challenges'),
                            ),
                            subtitle: Text(
                              context.tr(
                                'daily_sudoku_challenges_subtitle',
                              ),
                            ),
                            onChanged: _updatingDailyReminders
                                ? null
                                : (value) =>
                                      _setDailyReminders(reminders, value),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Card(
                        child: ValueListenableBuilder<bool>(
                          valueListenable: push.enabled,
                          builder: (context, enabled, _) {
                            final available =
                                push.configured &&
                                SocialApiClient.instance.configured;
                            return SwitchListTile(
                              secondary: const Icon(
                                Icons.notifications_outlined,
                              ),
                              value: enabled && !_updatingChallengePush,
                              title: Text(
                                context.tr('online_challenge_notifications'),
                              ),
                              subtitle: Text(
                                available
                                    ? context.tr(
                                        'online_challenge_notifications_subtitle',
                                      )
                                    : context.tr(
                                        'online_challenge_notifications_unavailable',
                                      ),
                              ),
                              onChanged:
                                  !available || _updatingChallengePush
                                  ? null
                                  : (value) =>
                                        _setChallengeNotifications(push, value),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 22),
                      _sectionTitle(context, context.tr('privacy')),
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
                                subtitle: Text(
                                  context.tr('analytics_sharing_subtitle'),
                                ),
                                onChanged: _updatingAnalytics
                                    ? null
                                    : (value) =>
                                          _setAnalytics(firebase, value),
                              ),
                            ),
                            const Divider(height: 1),
                            ValueListenableBuilder<bool>(
                              valueListenable: firebase.crashReportingEnabled,
                              builder: (context, enabled, _) => SwitchListTile(
                                secondary: const Icon(
                                  Icons.bug_report_outlined,
                                ),
                                value: enabled && !_updatingCrashReports,
                                title: Text(
                                  context.tr('crash_reports_sharing'),
                                ),
                                subtitle: Text(
                                  context.tr(
                                    'crash_reports_sharing_subtitle',
                                  ),
                                ),
                                onChanged: _updatingCrashReports
                                    ? null
                                    : (value) =>
                                          _setCrashReports(firebase, value),
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
                              _sectionTitle(context, context.tr('ad_privacy')),
                              const SizedBox(height: 10),
                              Card(
                                child: ListTile(
                                  leading: const Icon(
                                    Icons.privacy_tip_outlined,
                                  ),
                                  title: Text(
                                    context.tr('ad_privacy_choices'),
                                  ),
                                  subtitle: Text(
                                    context.tr(
                                      'ad_privacy_choices_subtitle',
                                    ),
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
                      _sectionTitle(context, context.tr('data')),
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
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(text, style: Theme.of(context).textTheme.titleLarge);
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _loadProfile() async {
    if (_loadingProfile) return;
    setState(() {
      _loadingProfile = true;
      _profileError = null;
    });
    try {
      await FirebaseSessionService.ensureAnonymousSession();
      final profile = await SocialApiClient.instance.ensureProfile();
      if (!mounted) return;
      setState(() => _profile = profile);
    } catch (error) {
      if (!mounted) return;
      setState(() => _profileError = error.toString());
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _editDisplayName() async {
    final controller = TextEditingController(text: _profile?.displayName ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Player name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Display name',
            hintText: 'How other players see you',
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().length < 2) return;
    setState(() => _loadingProfile = true);
    try {
      final updated = await SocialApiClient.instance.ensureProfile(
        displayName: value.trim(),
      );
      if (mounted) setState(() => _profile = updated);
    } catch (error) {
      if (mounted) setState(() => _profileError = error.toString());
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _copyPublicId() async {
    final id = _profile?.publicId;
    if (id == null || id.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Friend ID copied.')),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr(key))),
    );
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

class _PlayerAccountCard extends StatelessWidget {
  const _PlayerAccountCard({
    required this.profile,
    required this.profileError,
    required this.loading,
    required this.balance,
    required this.onRetry,
    required this.onEditName,
    required this.onCopyId,
    required this.onOpenStore,
    required this.onOpenHistory,
  });

  final SocialPlayer? profile;
  final String? profileError;
  final bool loading;
  final int balance;
  final VoidCallback onRetry;
  final VoidCallback onEditName;
  final VoidCallback onCopyId;
  final VoidCallback onOpenStore;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    if (loading && profile == null) {
      return const Card(
        child: SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (profile == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.cloud_off_outlined),
          title: const Text('Online account unavailable'),
          subtitle: Text(profileError ?? 'Try again when connected.'),
          trailing: IconButton(
            tooltip: 'Retry',
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
          ),
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(
              profile!.displayName,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text('@${profile!.username}'),
            trailing: IconButton(
              tooltip: 'Edit display name',
              onPressed: loading ? null : onEditName,
              icon: const Icon(Icons.edit_outlined),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Friend ID'),
            subtitle: Text(profile!.publicId),
            trailing: IconButton(
              tooltip: 'Copy friend ID',
              onPressed: onCopyId,
              icon: const Icon(Icons.copy_outlined),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.monetization_on_outlined),
            title: Text('$balance Coin'),
            subtitle: const Text('Server wallet and purchase history'),
            trailing: Wrap(
              spacing: 2,
              children: [
                IconButton(
                  tooltip: 'Coin history',
                  onPressed: onOpenHistory,
                  icon: const Icon(Icons.receipt_long_outlined),
                ),
                IconButton.filledTonal(
                  tooltip: 'Coin Store',
                  onPressed: onOpenStore,
                  icon: const Icon(Icons.storefront_outlined),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
