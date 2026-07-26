import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/social_api_client.dart';
import '../social/friend_requests_screen.dart';
import '../social/platform_social_screen.dart';
import 'duel_screen.dart';
import 'leaderboards_screen.dart';
import 'online_duel_screen.dart';

class MatchmakingScreen extends StatefulWidget {
  const MatchmakingScreen({super.key});

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends State<MatchmakingScreen> {
  SudokuDifficulty _difficulty = SudokuDifficulty.easy;
  bool _searching = false;
  String? _error;
  Timer? _pollTimer;

  String get _queueKey => 'duel_${_difficulty.name}';

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('online_duel')),
        actions: [
          IconButton(
            tooltip: 'Friend requests',
            onPressed: _openFriendRequests,
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
          IconButton(
            tooltip: 'Friends & challenges',
            onPressed: _openPlatformFriends,
            icon: const Icon(Icons.people_alt_outlined),
          ),
          IconButton(
            tooltip: context.tr('leaderboards'),
            onPressed: _openLeaderboards,
            icon: const Icon(Icons.leaderboard_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          OutlinedButton.icon(
            onPressed: _openPlatformFriends,
            icon: const Icon(Icons.person_search_outlined),
            label: const Text('Friends, profiles & challenges'),
          ),
          const SizedBox(height: 18),
          Text(
            context.tr('choose_duel_difficulty'),
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('same_difficulty_match'),
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          for (final difficulty in SudokuDifficulty.values) ...[
            _DifficultyCard(
              difficulty: difficulty,
              selected: _difficulty == difficulty,
              enabled: !_searching,
              onSelected: () => setState(() => _difficulty = difficulty),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
          if (_searching)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('searching_opponent'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr('queue_key', <Object>[_queueKey]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr('waiting_for_ranked_opponent'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.error),
                    ),
                  ],
                  const SizedBox(height: 14),
                  OutlinedButton(
                    onPressed: _cancelSearch,
                    child: Text(context.tr('cancel_search')),
                  ),
                ],
              ),
            )
          else ...[
            FilledButton.icon(
              onPressed: _findOpponent,
              icon: const Icon(Icons.public),
              label: Text(context.tr('find_opponent')),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _openLocalPractice,
              icon: const Icon(Icons.people_outline),
              label: Text(context.tr('local_practice')),
            ),
          ],
        ],
      ),
    );
  }

  void _openFriendRequests() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FriendRequestsScreen()));
  }

  void _openPlatformFriends() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PlatformSocialScreen()));
  }

  void _openLeaderboards() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LeaderboardsScreen()));
  }

  void _openLocalPractice() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DuelScreen(difficulty: _difficulty)),
    );
  }

  Future<void> _findOpponent() async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final result = await SocialApiClient.instance.joinRankedQueue(
        difficulty: _difficulty.name,
      );
      if (!mounted) return;
      if (result.roomId != null) {
        setState(() => _searching = false);
        _openOnlineRoom(result.roomId!);
      } else {
        _startPollingForMatch();
      }
    } on SocialApiException catch (error) {
      if (mounted) {
        setState(() {
          _searching = false;
          _error = error.message;
        });
      }
    }
  }

  Future<void> _cancelSearch() async {
    _pollTimer?.cancel();
    try {
      await SocialApiClient.instance.cancelRankedQueue();
    } catch (_) {
      // Offline/local play must remain available even if queue cancel fails.
    }
    if (mounted) setState(() => _searching = false);
  }

  void _openOnlineRoom(String roomId) {
    _pollTimer?.cancel();
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => OnlineDuelScreen(roomId: roomId)));
  }

  void _startPollingForMatch() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final match = await SocialApiClient.instance.activeMatch();
        final roomId = match?['roomId']?.toString();
        if (!mounted || roomId == null || roomId.isEmpty) return;
        setState(() => _searching = false);
        _openOnlineRoom(roomId);
      } on SocialApiException catch (error) {
        if (mounted) setState(() => _error = error.message);
      }
    });
  }
}

class _DifficultyCard extends StatelessWidget {
  const _DifficultyCard({
    required this.difficulty,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final SudokuDifficulty difficulty;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: selected ? scheme.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        enabled: enabled,
        onTap: enabled ? onSelected : null,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        ),
        title: Text(
          context.strings.difficultyLabel(difficulty),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          context.tr('difficulty_queue', <Object>[
            context.strings.difficultyLabel(difficulty),
          ]),
        ),
        trailing: selected ? const Icon(Icons.check_rounded) : null,
      ),
    );
  }
}
