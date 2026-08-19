import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../localization/app_strings.dart';
import '../../services/firebase_runtime_config.dart';
import '../../services/firebase_session_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/rank_identity_service.dart';
import '../../services/social_api_client.dart';
import '../../widgets/in_page_header.dart';
import '../../widgets/player_avatar.dart';
import '../../widgets/ux_feedback.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  final SocialApiClient _social = SocialApiClient.instance;
  final PushNotificationService _push = PushNotificationService.instance;

  bool _loading = true;
  String? _error;
  List<SocialPlayer> _requests = const <SocialPlayer>[];
  final Map<String, PublicRankSummary> _rankSummaries =
      <String, PublicRankSummary>{};

  bool get _configured =>
      _social.configured && FirebaseRuntimeConfig.configured;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_configured) {
      setState(() {
        _loading = false;
        _error = context.tr('online_account_unavailable');
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await FirebaseSessionService.ensureAnonymousSession();
      await _push.initialize();
      await _social.ensureProfile();
      final requests = await _social.loadIncomingFriendRequests();
      if (mounted) {
        setState(() => _requests = requests);
        unawaited(_loadRankSummaries(requests));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = UserSafeError.message(context, error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadRankSummaries(List<SocialPlayer> players) async {
    final loaded = await Future.wait<MapEntry<String, PublicRankSummary>?>(
      players.map((player) async {
        final id = player.publicId.trim();
        if (id.length < 3 || _rankSummaries.containsKey(id)) return null;
        try {
          final summary = await RankIdentityService.instance
              .loadPublicRankSummary(id);
          return MapEntry<String, PublicRankSummary>(id, summary);
        } catch (_) {
          return null;
        }
      }),
    );
    if (!mounted) return;
    setState(() {
      for (final entry in loaded) {
        if (entry != null) _rankSummaries[entry.key] = entry.value;
      }
    });
  }

  Future<void> _respond(SocialPlayer player, bool accept) async {
    try {
      await _social.respondToFriendRequest(
        requesterPublicId: player.publicId,
        accept: accept,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? context.tr('friend_request_accepted', <Object>[
                    player.displayName,
                  ])
                : context.tr('friend_request_declined'),
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(UserSafeError.message(context, error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  InPageHeader(
                    title: context.tr('friend_requests'),
                    actions: [
                      IconButton(
                        tooltip: context.tr('refresh'),
                        onPressed: _loading ? null : _load,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  if (_error != null)
                    UxStatePanel.error(
                      context,
                      message: _error!,
                      onRetry: _load,
                    )
                  else if (_requests.isEmpty)
                    UxStatePanel.empty(
                      context,
                      title: context.tr('friend_requests_empty'),
                      message: context.tr('friend_requests_empty'),
                      icon: Icons.mark_email_read_outlined,
                    )
                  else
                    for (final player in _requests)
                      _RequestCard(
                        player: player,
                        rank: _rankSummaries[player.publicId.trim()],
                        onAccept: () => _respond(player, true),
                        onDecline: () => _respond(player, false),
                      ),
                ],
              ),
            ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.player,
    required this.rank,
    required this.onAccept,
    required this.onDecline,
  });

  final SocialPlayer player;
  final PublicRankSummary? rank;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: PlayerAvatar(
                displayName: player.displayName,
                avatarKey: rank?.avatarKey ?? 'friend-${player.publicId}',
                radius: 24,
              ),
              title: Text(
                player.displayName,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                rank == null
                    ? '@${player.username} · ${context.tr('games_count', <Object>[player.gamesPlayed])}'
                    : '${rank!.rankName} · ${rank!.rankPoints} RP',
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  IconButton.outlined(
                    tooltip: context.tr('decline'),
                    onPressed: onDecline,
                    icon: const Icon(Icons.close),
                  ),
                  FilledButton(
                    onPressed: onAccept,
                    child: Text(context.tr('accept')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
