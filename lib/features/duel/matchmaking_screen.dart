import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../widgets/responsive_layout.dart';

import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/economy_service.dart';
import '../../services/firebase_session_service.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../economy/coin_store_screen.dart';
import 'duel_screen.dart';
import 'pre_match_ready_screen.dart';

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
  int _pollAttempt = 0;
  DateTime? _lastQueueRefresh;

  int get _selectedEntryFee =>
      _economy.entryFeeForDifficulty(_difficulty.name);

  bool get _canEnterSelectedDifficulty =>
      _economy.balance >= _selectedEntryFee;

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
    if (_searching) {
      return _FullScreenSearchingStage(onCancel: _cancelSearch, error: _error);
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      body: AppBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth >= 840 ? 720.0 : 640.0;
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: MaterialLocalizations.of(
                              context,
                            ).backButtonTooltip,
                            onPressed: () => Navigator.of(context).pop(),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white.withValues(
                                alpha: .08,
                              ),
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: .12),
                              ),
                            ),
                            icon: const DuelAssetIcon(DuelAsset.back, size: 22),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              context.tr('online_duel'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _EntrySummary(economy: _economy, difficulty: _difficulty),
                      const SizedBox(height: 16),
                      Text(
                        context.tr('choose_duel_difficulty'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context.tr('same_difficulty_match'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .72),
                          fontWeight: FontWeight.w600,
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
                      _StartActions(
                        canEnterOnline: _canEnterSelectedDifficulty,
                        loading: _economy.loading,
                        onFindOpponent: _findOpponent,
                        onInsufficientCoins: _showInsufficientCoins,
                        onLocalPractice: _openLocalPractice,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Material(
                          color: const Color(0xFF3A151D),
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const DuelAssetIcon(
                                  DuelAsset.cloud,
                                  size: 22,
                                  color: Color(0xFFFFD7DC),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: Color(0xFFFFD7DC),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: context.tr('dismiss'),
                                  onPressed: () =>
                                      setState(() => _error = null),
                                  icon: const DuelAssetIcon(
                                    DuelAsset.close,
                                    size: 18,
                                    color: Color(0xFFFFD7DC),
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
      ),
    );
  }

  void _openLocalPractice() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DuelScreen(difficulty: _difficulty)),
    );
  }

  Future<void> _showInsufficientCoins() async {
    await _economy.refresh();
    if (!mounted) return;
    if (_canEnterSelectedDifficulty) {
      await _findOpponent();
      return;
    }
    await showAdaptiveBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DuelAssetIcon(
                DuelAsset.lock,
                size: 42,
                color: Color(0xFF29D398),
              ),
              const SizedBox(height: 10),
              Text(
                context.tr('coin_required_title_dynamic', <Object>[
                  _selectedEntryFee,
                ]),
                style: Theme.of(sheetContext).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.tr('coin_required_body_dynamic', <Object>[
                  _selectedEntryFee,
                  _economy.winnerPotForDifficulty(_difficulty.name),
                ]),
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
                  icon: const DuelAssetIcon(DuelAsset.store, size: 22),
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
                    icon: const DuelAssetIcon(DuelAsset.gift, size: 22),
                    label: Text(
                      context.tr('claim_daily_coin', <Object>[
                        _economy.wallet!.dailyLoginAmount,
                      ]),
                    ),
                  ),
                ),
              ],
              if (_economy.wallet?.dailyAdAvailable == true &&
                  !_economy.noAds) ...[
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
                    icon: const DuelAssetIcon(DuelAsset.video, size: 22),
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
    if (!_canEnterSelectedDifficulty) {
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
        _pollAttempt = 0;
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
        _pollAttempt = 0;
      });
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => PreMatchReadyScreen(roomId: roomId),
          ),
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
    _pollAttempt = 0;
    unawaited(_pollForMatch());
  }

  void _scheduleNextPoll() {
    _pollTimer?.cancel();
    if (!_searching || !mounted) return;
    final delay = matchmakingFallbackDelay(_pollAttempt);
    _pollAttempt++;
    _pollTimer = Timer(delay, () => unawaited(_pollForMatch()));
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
          _pollAttempt = 0;
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
      _scheduleNextPoll();
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
      _pollAttempt = 0;
    });
  }
}

@visibleForTesting
Duration matchmakingFallbackDelay(int attempt) {
  if (attempt <= 0) return const Duration(seconds: 3);
  if (attempt <= 4) return const Duration(seconds: 5);
  return const Duration(seconds: 10);
}

class _EntrySummary extends StatelessWidget {
  const _EntrySummary({required this.economy, required this.difficulty});

  final EconomyService economy;
  final SudokuDifficulty difficulty;

  @override
  Widget build(BuildContext context) {
    final fee = economy.entryFeeForDifficulty(difficulty.name);
    final pot = economy.winnerPotForDifficulty(difficulty.name);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            Expanded(
              child: Ink(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF071014).withValues(alpha: .78),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: const Color(0xFF29D398).withValues(alpha: .30),
                  ),
                ),
                child: Row(
                  children: [
                    const DuelAssetIcon(DuelAsset.homeDuelEmblem, size: 54),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            economy.loading && economy.wallet == null
                                ? context.tr('balance_loading')
                                : context.tr('balance_coin', <Object>[
                                    NumberFormat.compact().format(
                                      economy.balance,
                                    ),
                                  ]),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _MatchMetaPill(
                                asset: DuelAsset.coin,
                                text: context.tr('duel_fee_summary', <Object>[
                                  fee,
                                  pot,
                                ]),
                                color: const Color(0xFFFFC94D),
                              ),
                              _MatchMetaPill(
                                asset: DuelAsset.people,
                                text: context.tr('online_duel_subtitle'),
                                color: const Color(0xFF29D398),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: context.tr('coin_store'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CoinStoreScreen(),
                        ),
                      ),
                      style: IconButton.styleFrom(
                        fixedSize: const Size(46, 46),
                        backgroundColor: const Color(
                          0xFF123429,
                        ).withValues(alpha: .70),
                        side: BorderSide(
                          color: const Color(0xFF29D398).withValues(alpha: .22),
                        ),
                      ),
                      icon: const DuelAssetIcon(DuelAsset.store, size: 22),
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

class _MatchMetaPill extends StatelessWidget {
  const _MatchMetaPill({
    required this.asset,
    required this.text,
    required this.color,
  });

  final String asset;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DuelAssetIcon(asset, size: 13, color: color),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
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
  });

  final bool canEnterOnline;
  final bool loading;
  final VoidCallback onFindOpponent;
  final VoidCallback onInsufficientCoins;
  final VoidCallback onLocalPractice;

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
          style: FilledButton.styleFrom(
            backgroundColor: canEnterOnline
                ? const Color(0xFF29D398)
                : const Color(0xFFFFC94D),
            foregroundColor: canEnterOnline
                ? const Color(0xFF08110E)
                : const Color(0xFF352500),
          ),
          icon: DuelAssetIcon(
            canEnterOnline ? DuelAsset.search : DuelAsset.lock,
            size: 22,
          ),
          label: Text(
            canEnterOnline
                ? context.tr('find_opponent')
                : context.tr('open_coin_store'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: onLocalPractice,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white.withValues(alpha: .86),
          ),
          icon: const DuelAssetIcon(DuelAsset.people, size: 22),
          label: Text(context.tr('local_practice')),
        ),
      ],
    );
  }
}

class _FullScreenSearchingStage extends StatefulWidget {
  const _FullScreenSearchingStage({required this.onCancel, this.error});

  final VoidCallback onCancel;
  final String? error;

  @override
  State<_FullScreenSearchingStage> createState() =>
      _FullScreenSearchingStageState();
}

class _FullScreenSearchingStageState extends State<_FullScreenSearchingStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _backgroundController;

  @override
  void initState() {
    super.initState();
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      body: SafeArea(
        child: Stack(
          children: [
            AppBackdrop(animation: _backgroundController),
            Positioned(
              left: 12,
              top: 8,
              child: IconButton.filledTonal(
                tooltip: context.tr('cancel_search'),
                onPressed: widget.onCancel,
                icon: const DuelAssetIcon(DuelAsset.back, size: 22),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 42, 16, 16),
              child: Column(
                children: [
                  Text(
                    context.tr('finding_opponent_title'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr('searching_similar_opponents'),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .62),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const cardWidth = 128.0;
                        final gap = constraints.maxWidth < 390 ? 58.0 : 76.0;
                        final side = math.max(
                          0.0,
                          (constraints.maxWidth - (cardWidth * 2) - gap) / 2,
                        );
                        final top = constraints.maxHeight < 560 ? 18.0 : 28.0;
                        final bottom = top;
                        final compact =
                            constraints.maxHeight < 390 ||
                            MediaQuery.textScalerOf(context).scale(1) > 1.3;
                        if (compact) {
                          return SingleChildScrollView(
                            child: Column(
                              children: [
                                _SearchPreviewCard(
                                  title: context.tr('you'),
                                  known: true,
                                ),
                                const SizedBox(height: 12),
                                const _SearchOrb(),
                                const SizedBox(height: 12),
                                _SearchPreviewCard(
                                  title: context.tr('searching_opponent_short'),
                                  known: false,
                                ),
                              ],
                            ),
                          );
                        }
                        return Stack(
                          children: [
                            Positioned(
                              left: side,
                              top: top,
                              width: cardWidth,
                              child: _SearchPreviewCard(
                                title: context.tr('you'),
                                known: true,
                              ),
                            ),
                            Positioned(
                              right: side,
                              bottom: bottom,
                              width: cardWidth,
                              child: _SearchPreviewCard(
                                title: context.tr('searching_opponent_short'),
                                known: false,
                              ),
                            ),
                            const Center(child: _SearchOrb()),
                          ],
                        );
                      },
                    ),
                  ),
                  _SearchInfoBar(
                    text: widget.error ?? context.tr('elo_hint'),
                    asset: widget.error == null
                        ? DuelAsset.shield
                        : DuelAsset.cloud,
                    error: widget.error != null,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: widget.onCancel,
                      child: Text(context.tr('cancel_search')),
                    ),
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

class _SearchPreviewCard extends StatelessWidget {
  const _SearchPreviewCard({required this.title, required this.known});

  final String title;
  final bool known;

  @override
  Widget build(BuildContext context) {
    final border = known ? const Color(0xFF29D398) : const Color(0xFF3AA9FF);
    return Container(
      width: 128,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF18242B).withValues(alpha: .94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border.withValues(alpha: .75)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: border.withValues(alpha: .2),
            child: DuelAssetIcon(
              known ? DuelAsset.avatar : DuelAsset.search,
              size: 34,
              color: known ? null : Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const DuelAssetIcon(
                DuelAsset.trophy,
                color: Color(0xFFFFC94D),
                size: 18,
              ),
              const SizedBox(width: 4),
              Text(
                '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Text(
            'ELO',
            style: TextStyle(
              color: Colors.white.withValues(alpha: .48),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchOrb extends StatefulWidget {
  const _SearchOrb();

  @override
  State<_SearchOrb> createState() => _SearchOrbState();
}

class _SearchOrbState extends State<_SearchOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final pulse = Curves.easeOut.transform(_controller.value);
        final rotation = _controller.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.rotate(
              angle: rotation * 6.28318,
              child: SizedBox(
                width: 104,
                height: 104,
                child: CustomPaint(painter: _SearchDotsPainter()),
              ),
            ),
            Container(
              width: 58 + pulse * 38,
              height: 58 + pulse * 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(
                    0xFF29D398,
                  ).withValues(alpha: .34 * (1 - pulse)),
                ),
              ),
            ),
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF18242B),
                border: Border.all(color: const Color(0xFF29D398), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF29D398).withValues(alpha: .35),
                    blurRadius: 14,
                  ),
                ],
              ),
              child: const DuelAssetIcon(
                DuelAsset.search,
                color: Colors.white,
                size: 30,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SearchDotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const dots = 12;
    for (var i = 0; i < dots; i++) {
      final angle = (i / dots) * 6.28318;
      final offset = Offset(
        center.dx + 44 * math.cos(angle),
        center.dy + 44 * math.sin(angle),
      );
      final paint = Paint()
        ..color = (i.isEven ? const Color(0xFF29D398) : const Color(0xFF3AA9FF))
            .withValues(alpha: .28 + (i / dots) * .32);
      canvas.drawCircle(offset, 2.2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SearchInfoBar extends StatelessWidget {
  const _SearchInfoBar({
    required this.text,
    required this.asset,
    required this.error,
  });

  final String text;
  final String asset;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: (error ? const Color(0xFF3A151D) : const Color(0xFF18242B))
            .withValues(alpha: .82),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Row(
        children: [
          DuelAssetIcon(
            asset,
            size: 22,
            color: error ? const Color(0xFFFFD7DC) : const Color(0xFF29D398),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.white.withValues(alpha: .78)),
            ),
          ),
        ],
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
    final accent = selected ? const Color(0xFF29D398) : const Color(0xFF3AA9FF);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: enabled ? onSelected : null,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color:
                (selected ? const Color(0xFF0D2B24) : const Color(0xFF071014))
                    .withValues(alpha: .82),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: .34)),
          ),
          child: Row(
            children: [
              _SelectionGlyph(selected: selected),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.strings.difficultyLabel(difficulty),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr('difficulty_queue', <Object>[
                        context.strings.difficultyLabel(difficulty),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .62),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              DuelAssetIcon(
                selected ? DuelAsset.check : DuelAsset.arrowForward,
                color: accent,
                size: selected ? 20 : 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionGlyph extends StatelessWidget {
  const _SelectionGlyph({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? const Color(0xFF29D398)
              : Colors.white.withValues(alpha: .38),
          width: 2,
        ),
      ),
      child: selected
          ? const DuelAssetIcon(
              DuelAsset.check,
              size: 14,
              color: Color(0xFF29D398),
            )
          : null,
    );
  }
}
