import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/economy_service.dart';
import '../../services/firebase_session_service.dart';
import '../../services/social_api_client.dart';
import '../economy/coin_store_screen.dart';
import '../social/friend_requests_screen.dart';
import '../social/platform_social_screen.dart';
import 'duel_screen.dart';
import 'leaderboards_screen.dart';
import 'online_duel_screen.dart';

class MatchmakingScreen extends StatefulWidget {
  const MatchmakingScreen({super.key, this.initialDifficulty});

  final SudokuDifficulty? initialDifficulty;

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends State<MatchmakingScreen> {
  static const Duration _queueRefreshInterval = Duration(seconds: 45);

  final EconomyService _economy = EconomyService.instance;
  late SudokuDifficulty _difficulty;
  bool _searching = false;
  bool _polling = false;
  String? _error;
  Timer? _pollTimer;
  DateTime? _lastQueueRefresh;

  String get _queueKey => 'duel_${_difficulty.name}';

  @override
  void initState() {
    super.initState();
    _difficulty = widget.initialDifficulty ?? SudokuDifficulty.easy;
    _economy.addListener(_onEconomyChanged);
    _economy.initialize();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _economy.removeListener(_onEconomyChanged);
    super.dispose();
  }

  void _onEconomyChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('online_duel')),
        actions: [
          IconButton(
            tooltip: context.tr('friend_requests'),
            onPressed: _openFriendRequests,
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
          IconButton(
            tooltip: context.tr('friends_challenges'),
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
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth >= 840 ? 720.0 : 640.0;
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: [
                    _EntrySummary(economy: _economy),
                    const SizedBox(height: 16),
                    Text(
                      context.tr('choose_duel_difficulty'),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.tr('same_difficulty_match'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (final difficulty in SudokuDifficulty.values) ...[
                      _DifficultyCard(
                        difficulty: difficulty,
                        selected: _difficulty == difficulty,
                        enabled: !_searching,
                        onSelected: () =>
                            setState(() => _difficulty = difficulty),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 8),
                    if (_searching)
                      _SearchingPanel(
                        queueKey: _queueKey,
                        onCancel: _cancelSearch,
                      )
                    else
                      _StartActions(
                        canEnterOnline: _economy.canEnterOnline,
                        loading: _economy.loading,
                        onFindOpponent: _findOpponent,
                        onInsufficientCoins: _showInsufficientCoins,
                        onLocalPractice: _openLocalPractice,
                        onSocial: _openPlatformFriends,
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Material(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: scheme.onErrorContainer,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: scheme.onErrorContainer,
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: context.tr('dismiss'),
                                onPressed: () => setState(() => _error = null),
                                icon: Icon(
                                  Icons.close,
                                  color: scheme.onErrorContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
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

  Future<void> _showInsufficientCoins() async {
    await _economy.refresh();
    if (!mounted) return;
    if (_economy.canEnterOnline) {
      await _findOpponent();
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 42),
              const SizedBox(height: 10),
              Text(
                context.tr('coin_required_title'),
                style: Theme.of(sheetContext).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.tr('coin_required_body'),
                textAlign: TextAlign.center,
                style: Theme.of(sheetContext).textTheme.bodyLarge,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CoinStoreScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.storefront_outlined),
                  label: Text(context.tr('open_coin_store')),
                ),
              ),
              if (_economy.wallet?.dailyLoginAvailable == true) ...[
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final claimed = await _economy.claimDailyLogin();
                      if (sheetContext.mounted && claimed) {
                        Navigator.of(sheetContext).pop();
                      }
                    },
                    icon: const Icon(Icons.card_giftcard_outlined),
                    label: Text(
                      context.tr('claim_daily_coin', <Object>[
                        _economy.wallet!.dailyLoginAmount,
                      ]),
                    ),
                  ),
                ),
              ],
              if (_economy.wallet?.dailyAdAvailable == true) ...[
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final claimed = await _economy.claimDailyRewardedAd();
                      if (sheetContext.mounted && claimed) {
                        Navigator.of(sheetContext).pop();
                      }
                    },
                    icon: const Icon(Icons.ondemand_video_outlined),
                    label: Text(
                      context.tr('watch_ad_for_coin', <Object>[
                        _economy.wallet!.dailyAdAmount,
                      ]),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _findOpponent() async {
    if (_searching) return;
    await _economy.refresh();
    if (!mounted) return;
    if (!_economy.canEnterOnline) {
      await _showInsufficientCoins();
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
      _lastQueueRefresh = null;
    });

    try {
      await FirebaseSessionService.ensureAnonymousSession();
      final result = await SocialApiClient.instance.joinRankedQueue(
        difficulty: _difficulty.name,
      );
      if (!mounted) return;

      final roomId = result.roomId;
      if (roomId != null && roomId.isNotEmpty) {
        _openOnlineRoom(roomId);
        return;
      }

      if (result.status != 'queued') {
        throw SocialApiException(
          0,
          context.tr('matchmaking_unexpected_response'),
        );
      }
      _lastQueueRefresh = DateTime.now();
      _startPollingForMatch();
    } on FirebaseSessionException catch (error) {
      _stopSearchWithError(error.message);
    } on SocialApiException catch (error) {
      if (error.statusCode == 409) {
        await _economy.refresh(showLoading: false);
      }
      _stopSearchWithError(error.message);
    } catch (_) {
      _stopSearchWithError(context.tr('matchmaking_start_failed'));
    }
  }

  Future<void> _cancelSearch() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (mounted) {
      setState(() {
        _searching = false;
        _polling = false;
        _error = null;
        _lastQueueRefresh = null;
      });
    }

    try {
      await SocialApiClient.instance.cancelRankedQueue();
    } catch (_) {
      // Local play remains available if queue cancellation cannot reach server.
    }
  }

  void _openOnlineRoom(String roomId) {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (mounted) {
      setState(() {
        _searching = false;
        _polling = false;
        _error = null;
        _lastQueueRefresh = null;
      });
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute(builder: (_) => OnlineDuelScreen(roomId: roomId)),
        )
        .then((action) {
          unawaited(_economy.refresh(showLoading: false));
          if (!mounted) return;
          if (action == 'new_match') {
            unawaited(_findOpponent());
          } else if (action == 'menu') {
            Navigator.of(context).pop();
          }
        });
  }

  void _startPollingForMatch() {
    _pollTimer?.cancel();
    unawaited(_pollForMatch());
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_pollForMatch()),
    );
  }

  Future<void> _pollForMatch() async {
    if (!_searching || _polling) return;
    _polling = true;
    try {
      final now = DateTime.now();
      final refreshDue =
          _lastQueueRefresh == null ||
          now.difference(_lastQueueRefresh!) >= _queueRefreshInterval;
      if (refreshDue) {
        final refreshed = await SocialApiClient.instance.joinRankedQueue(
          difficulty: _difficulty.name,
        );
        _lastQueueRefresh = now;
        final refreshedRoomId = refreshed.roomId;
        if (!mounted) return;
        if (refreshedRoomId != null && refreshedRoomId.isNotEmpty) {
          _openOnlineRoom(refreshedRoomId);
          return;
        }
      }

      final match = await SocialApiClient.instance.activeMatch();
      final roomId = match?['roomId']?.toString();
      if (!mounted || roomId == null || roomId.isEmpty) return;
      _openOnlineRoom(roomId);
    } on SocialApiException catch (error) {
      if (!mounted) return;
      final terminalError = error.statusCode >= 400 && error.statusCode < 500;
      if (terminalError) {
        _pollTimer?.cancel();
        _pollTimer = null;
        setState(() {
          _searching = false;
          _error = error.message;
          _lastQueueRefresh = null;
        });
        await _economy.refresh(showLoading: false);
      } else {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = context.tr('connection_interrupted_retrying');
        });
      }
    } finally {
      _polling = false;
    }
  }

  void _stopSearchWithError(String message) {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (!mounted) return;
    setState(() {
      _searching = false;
      _polling = false;
      _error = message;
      _lastQueueRefresh = null;
    });
  }
}

class _EntrySummary extends StatelessWidget {
  const _EntrySummary({required this.economy});

  final EconomyService economy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.monetization_on_rounded,
              color: scheme.onPrimaryContainer,
              size: 34,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Balance: ${economy.loading && economy.wallet == null ? '…' : economy.balance} Coin',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${economy.entryFee} entry · ${economy.winnerPot} winner pot',
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Coin Store',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CoinStoreScreen()),
              ),
              icon: const Icon(Icons.storefront_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartActions extends StatelessWidget {
  const _StartActions({
    required this.canEnterOnline,
    required this.loading,
    required this.onFindOpponent,
    required this.onInsufficientCoins,
    required this.onLocalPractice,
    required this.onSocial,
  });

  final bool canEnterOnline;
  final bool loading;
  final VoidCallback onFindOpponent;
  final VoidCallback onInsufficientCoins;
  final VoidCallback onLocalPractice;
  final VoidCallback onSocial;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: loading
              ? null
              : canEnterOnline
              ? onFindOpponent
              : onInsufficientCoins,
          icon: Icon(canEnterOnline ? Icons.public : Icons.lock_outline),
          label: Text(
            canEnterOnline ? context.tr('find_opponent') : 'Get more Coin',
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onSocial,
          icon: const Icon(Icons.people_alt_outlined),
          label: const Text('Friends & challenges'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: onLocalPractice,
          icon: const Icon(Icons.people_outline),
          label: Text(context.tr('local_practice')),
        ),
      ],
    );
  }
}

class _SearchingPanel extends StatelessWidget {
  const _SearchingPanel({required this.queueKey, required this.onCancel});

  final String queueKey;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(
              context.tr('searching_opponent'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(context.tr('queue_key', <Object>[queueKey])),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onCancel,
              child: Text(context.tr('cancel_search')),
            ),
          ],
        ),
      ),
    );
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
      margin: EdgeInsets.zero,
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
