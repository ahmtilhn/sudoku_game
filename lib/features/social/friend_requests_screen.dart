import 'package:flutter/material.dart';

import '../../services/push_notification_service.dart';
import '../../services/social_api_client.dart';

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

  bool get _configured => _social.configured && _push.configured;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_configured) {
      setState(() {
        _loading = false;
        _error =
            'Deploy the social backend and configure Firebase before using friend requests.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _push.initialize();
      await _social.ensureProfile();
      final requests = await _social.loadIncomingFriendRequests();
      if (mounted) setState(() => _requests = requests);
    } on SocialApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
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
                ? '${player.displayName} is now your friend.'
                : 'Friend request declined.',
          ),
        ),
      );
      await _load();
    } on SocialApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friend requests'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
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
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(_error!),
                      ),
                    )
                  else if (_requests.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text('You have no pending friend requests.'),
                      ),
                    )
                  else
                    for (final player in _requests)
                      Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person_add_alt_1_outlined),
                          ),
                          title: Text(
                            player.displayName,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            '@${player.username} · ${player.rating} rating',
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                tooltip: 'Decline',
                                onPressed: () => _respond(player, false),
                                icon: const Icon(Icons.close),
                              ),
                              FilledButton(
                                onPressed: () => _respond(player, true),
                                child: const Text('Accept'),
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
