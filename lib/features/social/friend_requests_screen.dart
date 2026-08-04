import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../localization/app_strings.dart';
import '../../services/firebase_runtime_config.dart';
import '../../services/firebase_session_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/social_api_client.dart';
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
      if (mounted) setState(() => _requests = requests);
    } catch (error) {
      if (mounted) {
        setState(() => _error = UserSafeError.message(context, error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
      appBar: AppBar(
        title: Text(context.tr('friend_requests')),
        actions: [
          IconButton(
            tooltip: context.tr('refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
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
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const CircleAvatar(
                                  child: Icon(Icons.person_add_alt_1_outlined),
                                ),
                                title: Text(
                                  player.displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                subtitle: Text(
                                  context.tr('player_rating_summary', <Object>[
                                    player.username,
                                    player.rating,
                                  ]),
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
                                      onPressed: () => _respond(player, false),
                                      icon: const Icon(Icons.close),
                                    ),
                                    FilledButton(
                                      onPressed: () => _respond(player, true),
                                      child: Text(context.tr('accept')),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}
