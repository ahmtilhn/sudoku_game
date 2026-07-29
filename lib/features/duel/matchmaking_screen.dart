import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/economy_service.dart';
import '../../services/firebase_session_service.dart';
import '../../services/social_api_client.dart';
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
    final canEnterSelected =
        _economy.balance >= _economy.entryFeeForDifficulty(_difficulty.name);
    if (_searching) {
      return _FullScreenSearchingStage(onCancel: _cancelSearch, error: _error);
    }
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('online_duel'))),
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
                    _EntrySummary(economy: _economy, difficulty: _difficulty),
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
                    _StartActions(
                      canEnterOnline: canEnterSelected,
                      loading: _economy.loading,
                      onFindOpponent: _findOpponent,
                      onInsufficientCoins: _showInsufficientCoins,
                      onLocalPractice: _openLocalPractice,
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
                context.tr('coin_required_title_dynamic', <Object>[
                  _economy.entryFeeForDifficulty(_difficulty.name),
                ]),
                style: Theme.of(sheetContext).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.tr('coin_required_body_dynamic', <Object>[
                  _economy.entryFeeForDifficulty(_difficulty.name),
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
                    economy.loading && economy.wallet == null
                        ? context.tr('balance_loading')
                        : context.tr('balance_coin', <Object>[economy.balance]),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.tr('duel_fee_summary', <Object>[
                      economy.entryFeeForDifficulty(difficulty.name),
                      economy.winnerPotForDifficulty(difficulty.name),
                    ]),
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
          icon: Icon(canEnterOnline ? Icons.public : Icons.lock_outline),
          label: Text(
            canEnterOnline
                ? context.tr('find_opponent')
                : context.tr('open_coin_store'),
          ),
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

class _FullScreenSearchingStage extends StatelessWidget {
  const _FullScreenSearchingStage({required this.onCancel, this.error});

  final VoidCallback onCancel;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF061124),
      body: SafeArea(
        child: Stack(
          children: [
            const _SearchBackground(),
            Positioned(
              left: 12,
              top: 8,
              child: IconButton.filledTonal(
                tooltip: context.tr('cancel_search'),
                onPressed: onCancel,
                icon: const Icon(Icons.arrow_back),
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
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .62),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final side = constraints.maxWidth < 390 ? 6.0 : 8.0;
                        final top = constraints.maxHeight < 560 ? 18.0 : 28.0;
                        const cardWidth = 128.0;
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
                              bottom: top,
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
                    text: error ?? context.tr('elo_hint'),
                    icon: error == null
                        ? Icons.shield_outlined
                        : Icons.cloud_off_outlined,
                    error: error != null,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onCancel,
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

class _SearchBackground extends StatelessWidget {
  const _SearchBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SearchBackgroundPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _SearchBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF061124), Color(0xFF081A36), Color(0xFF120D32)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    final start = Offset(size.width * .64, size.height * .1);
    final end = Offset(size.width * .36, size.height * .9);
    final line = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          const Color(0xFF58A8FF).withValues(alpha: .85),
          const Color(0xFFB64DFF).withValues(alpha: .55),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size)
      ..strokeWidth = 1.6;
    canvas.drawLine(start, end, line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SearchPreviewCard extends StatelessWidget {
  const _SearchPreviewCard({required this.title, required this.known});

  final String title;
  final bool known;

  @override
  Widget build(BuildContext context) {
    final border = known ? const Color(0xFF2E7BFF) : const Color(0xFF9B4DFF);
    return Container(
      width: 128,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1B36).withValues(alpha: .86),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border.withValues(alpha: .75)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: border.withValues(alpha: .2),
            child: Icon(
              known ? Icons.person : Icons.person_search,
              color: Colors.white,
              size: 32,
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
              const Icon(
                Icons.emoji_events_rounded,
                color: Color(0xFFFFC547),
                size: 18,
              ),
              const SizedBox(width: 4),
              Text(
                known ? '1000' : '?',
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
                    0xFF58A8FF,
                  ).withValues(alpha: .34 * (1 - pulse)),
                ),
              ),
            ),
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF13274E),
                border: Border.all(color: const Color(0xFF9B4DFF), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF9B4DFF).withValues(alpha: .35),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: const Icon(Icons.search, color: Colors.white, size: 30),
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
        ..color = (i.isEven ? const Color(0xFF58A8FF) : const Color(0xFFB64DFF))
            .withValues(alpha: .35 + (i / dots) * .45);
      canvas.drawCircle(offset, 2.2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SearchInfoBar extends StatelessWidget {
  const _SearchInfoBar({
    required this.text,
    required this.icon,
    required this.error,
  });

  final String text;
  final IconData icon;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: (error ? Colors.red.shade900 : const Color(0xFF172344))
            .withValues(alpha: .82),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: error ? Colors.red.shade100 : const Color(0xFF8B63FF),
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
