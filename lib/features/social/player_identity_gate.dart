import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/local_progress_store.dart';
import '../../localization/app_strings.dart';
import '../../services/economy_api_client.dart';
import '../../services/economy_service.dart';
import '../../services/firebase_session_service.dart';
import '../../services/platform_game_services.dart';
import '../../services/player_profile_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/social_api_client.dart';
import '../../widgets/adaptive_app_shell.dart';
import '../career/career_screen.dart';
import '../daily/daily_screen.dart';
import '../duel/leaderboards_screen.dart';
import '../duel/matchmaking_screen.dart';
import '../duel/online_duel_screen.dart';
import '../home/home_screen.dart';
import 'platform_social_screen.dart';
import '../settings/settings_screen.dart';
import '../tutorial/tutorial_screen.dart';

class PlayerIdentityGate extends StatefulWidget {
  const PlayerIdentityGate({super.key, required this.store});

  final LocalProgressStore store;

  @override
  State<PlayerIdentityGate> createState() => _PlayerIdentityGateState();
}

class _PlayerIdentityGateState extends State<PlayerIdentityGate> {
  bool _promptScheduled = false;
  bool _handlingRematch = false;

  @override
  void initState() {
    super.initState();
    PushNotificationService.instance.openedRematchId.addListener(
      _onOpenedRematch,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkIdentity());
      unawaited(_handleOpenedRematch());
    });
  }

  @override
  void dispose() {
    PushNotificationService.instance.openedRematchId.removeListener(
      _onOpenedRematch,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveAppShell(
      home: HomeScreen(store: widget.store),
      play: _PlayHubScreen(store: widget.store),
      compete: const _CompeteHubScreen(),
      profile: _ProfileHubScreen(store: widget.store),
    );
  }

  void _onOpenedRematch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_handleOpenedRematch());
    });
  }

  Future<void> _handleOpenedRematch() async {
    if (!mounted || _handlingRematch) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    final push = PushNotificationService.instance;
    final invitationId = push.openedRematchId.value;
    if (invitationId == null || invitationId.isEmpty) return;

    _handlingRematch = true;
    push.openedRematchId.value = null;
    try {
      final invitations = await EconomyService.instance.loadRematches();
      if (!mounted) return;
      RematchInvitation? invitation;
      for (final item in invitations) {
        if (item.id == invitationId) {
          invitation = item;
          break;
        }
      }
      if (invitation == null ||
          !invitation.isPending ||
          invitation.isSender ||
          invitation.expiresAt.isBefore(DateTime.now())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This rematch invitation has expired.')),
        );
        return;
      }

      final response = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _RematchPushDialog(invitation: invitation!),
      );
      if (!mounted || response == null) return;
      try {
        final updated = await EconomyService.instance.respondRematch(
          invitationId: invitation.id,
          accept: response,
        );
        if (!mounted) return;
        if (response && updated.roomId?.isNotEmpty == true) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OnlineDuelScreen(roomId: updated.roomId!),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                response
                    ? context.tr('rematch_could_not_start')
                    : context.tr('rematch_declined'),
              ),
            ),
          );
        }
      } on EconomyApiException catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('rematch_invitation_load_failed'))),
        );
      }
    } finally {
      _handlingRematch = false;
    }
  }

  Future<void> _checkIdentity() async {
    if (_promptScheduled || !SocialApiClient.instance.configured) return;
    _promptScheduled = true;
    try {
      await FirebaseSessionService.ensureAnonymousSession();
      await SocialApiClient.instance.ensureProfile();
      final profile = await PlayerProfileService.instance.load();
      if (!mounted || profile.profileConfirmed) return;

      PlatformPlayer? platformPlayer;
      final platform = PlatformGameServices.instance;
      try {
        if (await platform.isConfigured() &&
            await platform.refreshAuthentication()) {
          platformPlayer = await platform.getLocalPlayer();
        }
      } catch (_) {
        platformPlayer = null;
      }

      if (!mounted) return;
      final value = await _showIdentityDialog(profile, platformPlayer);
      if (value == null) return;
      await PlayerProfileService.instance.update(
        username: value.username,
        displayName: value.displayName,
        discoverable: true,
        nameSource: value.nameSource,
      );
    } catch (_) {
      // Online identity onboarding is retried from Settings/social screens and
      // must never block offline Sudoku play.
    }
  }

  Future<({String username, String displayName, String nameSource})?>
  _showIdentityDialog(
    PlayerProfilePreferences profile,
    PlatformPlayer? platformPlayer,
  ) async {
    final suggestedName = platformPlayer?.displayName.trim();
    final displayController = TextEditingController(
      text: suggestedName?.isNotEmpty == true ? suggestedName : '',
    );
    final usernameController = TextEditingController(
      text: _suggestUsername(suggestedName, profile.publicId),
    );
    var selectedSource = suggestedName?.isNotEmpty == true
        ? _platformSource()
        : 'custom';

    final result =
        await showDialog<
          ({String username, String displayName, String nameSource})
        >(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) {
              final valid =
                  displayController.text.trim().length >= 2 &&
                  RegExp(
                    r'^[a-z0-9_]{3,20}$',
                  ).hasMatch(usernameController.text.trim().toLowerCase());
              return AlertDialog(
                title: Text(context.tr('create_player_profile')),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(context.tr('create_player_profile_body')),
                        RadioGroup<String>(
                          groupValue: selectedSource,
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() {
                              selectedSource = value;
                              if (value == _platformSource() &&
                                  suggestedName?.isNotEmpty == true) {
                                displayController.text = suggestedName!;
                                usernameController.text = _suggestUsername(
                                  suggestedName,
                                  profile.publicId,
                                );
                              }
                            });
                          },
                          child: Column(
                            children: [
                              if (suggestedName?.isNotEmpty == true) ...[
                                const SizedBox(height: 14),
                                RadioListTile<String>(
                                  value: _platformSource(),
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(suggestedName!),
                                  subtitle: Text(
                                    context.tr('use_platform_name'),
                                  ),
                                ),
                              ],
                              RadioListTile<String>(
                                value: 'custom',
                                contentPadding: EdgeInsets.zero,
                                title: Text(context.tr('use_custom_profile')),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: displayController,
                          autofocus: suggestedName?.isNotEmpty != true,
                          maxLength: 24,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: context.tr('display_name'),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) {
                            selectedSource = 'custom';
                            setDialogState(() {});
                          },
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: usernameController,
                          maxLength: 20,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.done,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp('[a-zA-Z0-9_]'),
                            ),
                          ],
                          decoration: InputDecoration(
                            labelText: context.tr('unique_username'),
                            helperText: context.tr('username_helper'),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.tr('friend_id_value', <Object>[
                            profile.publicId,
                          ]),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  FilledButton(
                    onPressed: !valid
                        ? null
                        : () => Navigator.of(dialogContext).pop((
                            username: usernameController.text
                                .trim()
                                .toLowerCase(),
                            displayName: displayController.text.trim(),
                            nameSource: selectedSource,
                          )),
                    child: Text(context.tr('continue_action')),
                  ),
                ],
              );
            },
          ),
        );
    displayController.dispose();
    usernameController.dispose();
    return result;
  }

  String _platformSource() {
    return Theme.of(context).platform == TargetPlatform.iOS
        ? 'game_center'
        : 'google_play_games';
  }

  String _suggestUsername(String? name, String publicId) {
    final normalized = (name ?? 'player')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final base = normalized.length >= 3 ? normalized : 'player';
    final suffix = publicId
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .padRight(4, '0')
        .substring(0, 4);
    final maxBaseLength = 20 - suffix.length - 1;
    final trimmed = base.length > maxBaseLength
        ? base.substring(0, maxBaseLength)
        : base;
    return '${trimmed}_$suffix';
  }
}

class _PlayHubScreen extends StatelessWidget {
  const _PlayHubScreen({required this.store});

  final LocalProgressStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('play'))),
      body: AdaptivePageContainer(
        child: ListView(
          children: [
            ModeTile(
              icon: Icons.casino_outlined,
              title: context.tr('career'),
              subtitle: context.tr('career_random_subtitle'),
              onTap: () => _open(context, CareerScreen(store: store)),
            ),
            const SizedBox(height: 10),
            ModeTile(
              icon: Icons.today_outlined,
              title: context.tr('daily_sudoku'),
              subtitle: context.tr('daily_subtitle'),
              onTap: () => _open(context, DailyScreen(store: store)),
            ),
            const SizedBox(height: 10),
            ModeTile(
              icon: Icons.school_outlined,
              title: context.tr('how_to_play'),
              subtitle: store.tutorialCompleted
                  ? context.tr('tutorial_repeat')
                  : context.tr('tutorial_new'),
              onTap: () => _open(context, TutorialScreen(store: store)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompeteHubScreen extends StatelessWidget {
  const _CompeteHubScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('compete'))),
      body: AdaptivePageContainer(
        child: ListView(
          children: [
            ModeTile(
              icon: Icons.public,
              title: context.tr('online_duel'),
              subtitle: context.tr('online_duel_subtitle'),
              onTap: () => _open(context, const MatchmakingScreen()),
            ),
            const SizedBox(height: 10),
            ModeTile(
              icon: Icons.leaderboard_outlined,
              title: context.tr('leaderboards'),
              subtitle: context.tr('global_elo'),
              onTap: () => _open(context, const LeaderboardsScreen()),
            ),
            const SizedBox(height: 10),
            ModeTile(
              icon: Icons.people_alt_outlined,
              title: context.tr('friends_challenges'),
              subtitle: context.tr('friend_requests'),
              onTap: () => _open(context, const PlatformSocialScreen()),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHubScreen extends StatelessWidget {
  const _ProfileHubScreen({required this.store});

  final LocalProgressStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('profile'))),
      body: AdaptivePageContainer(
        child: ListView(
          children: [
            ModeTile(
              icon: Icons.person_outline,
              title: context.tr('player_profile'),
              subtitle: context.tr('shown_to_other_players'),
              onTap: () => _open(context, const PlatformSocialScreen()),
            ),
            const SizedBox(height: 10),
            ModeTile(
              icon: Icons.settings_outlined,
              title: context.tr('settings'),
              subtitle: context.tr('appearance'),
              onTap: () => _open(context, SettingsScreen(store: store)),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _open(BuildContext context, Widget screen) {
  return Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => screen));
}

class _RematchPushDialog extends StatefulWidget {
  const _RematchPushDialog({required this.invitation});

  final RematchInvitation invitation;

  @override
  State<_RematchPushDialog> createState() => _RematchPushDialogState();
}

class _RematchPushDialogState extends State<_RematchPushDialog> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      if (_remainingMilliseconds <= 0) {
        Navigator.of(context).pop();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int get _remainingMilliseconds =>
      widget.invitation.expiresAt.difference(DateTime.now()).inMilliseconds;

  @override
  Widget build(BuildContext context) {
    final seconds = (_remainingMilliseconds / 1000).ceil().clamp(0, 10);
    return AlertDialog(
      title: Text(context.tr('rematch_invitation_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.tr('wants_to_play_again', <Object>[
              widget.invitation.sender.displayName,
            ]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Text(
            '$seconds s',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(context.tr('rematch_requires_coin', const <Object>[100])),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.tr('decline')),
        ),
        FilledButton(
          onPressed: EconomyService.instance.canEnterOnline
              ? () => Navigator.of(context).pop(true)
              : null,
          child: Text(context.tr('accept')),
        ),
      ],
    );
  }
}
