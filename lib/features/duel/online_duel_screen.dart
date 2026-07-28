import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/economy_api_client.dart';
import '../../services/economy_service.dart';
import '../../services/online_duel_controller.dart';
import '../../services/online_duel_models.dart';
import '../../services/online_duel_transport.dart';
import '../../services/social_api_client.dart';
import '../../widgets/number_pad.dart';
import '../../widgets/sudoku_board.dart';
import '../economy/coin_store_screen.dart';

class OnlineDuelScreen extends StatefulWidget {
  const OnlineDuelScreen({super.key, required this.roomId, this.controller});

  final String roomId;
  final OnlineDuelController? controller;

  @override
  State<OnlineDuelScreen> createState() => _OnlineDuelScreenState();
}

class _OnlineDuelScreenState extends State<OnlineDuelScreen> {
  static const List<double> _grayscaleMatrix = <double>[
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  OnlineDuelController? _controller;
  StreamSubscription<OnlineDuelSnapshot>? _subscription;
  StreamSubscription<OnlineDuelFeedback>? _feedbackSubscription;
  OnlineDuelSnapshot? _snapshot;
  Object? _error;
  int? _selectedIndex;
  int? _feedbackCell;
  bool _loading = true;
  bool _screenLoadedSent = false;
  Timer? _ticker;
  Timer? _feedbackTimer;
  String? _shownResultFor;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    unawaited(_connect());
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_feedbackSubscription?.cancel());
    unawaited(_controller?.dispose());
    _ticker?.cancel();
    _feedbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      final controller =
          widget.controller ??
          OnlineDuelController(
            await WebSocketOnlineDuelTransport.connect(widget.roomId),
          );
      controller.start();
      final subscription = controller.snapshots.listen((snapshot) {
        if (!mounted) return;
        final previousLocalTurn = _snapshot?.isLocalTurn ?? false;
        setState(() {
          _snapshot = snapshot;
          _loading = false;
          _error = null;
          if (!snapshot.isLocalTurn) _selectedIndex = null;
        });
        if (!previousLocalTurn && snapshot.isLocalTurn) {
          unawaited(HapticFeedback.mediumImpact());
        }
        _sendScreenLoadedAfterRender(snapshot);
        _showResultOnce(snapshot);
      });
      final feedbackSubscription = controller.feedback.listen((feedback) {
        if (!mounted) return;

        _feedbackTimer?.cancel();
        setState(() {
          if (feedback.accepted) {
            _selectedIndex = null;
            _feedbackCell = null;
          } else {
            _feedbackCell = feedback.cellIndex;
          }
        });

        if (!feedback.accepted) {
          final messenger = ScaffoldMessenger.of(context);
          messenger.clearSnackBars();
          messenger.showSnackBar(
            SnackBar(
              content: Text(feedback.message),
              duration: const Duration(seconds: 1),
            ),
          );
        }

        if (_feedbackCell != null) {
          _feedbackTimer = Timer(const Duration(milliseconds: 650), () {
            if (mounted) setState(() => _feedbackCell = null);
          });
        }
      });
      setState(() {
        _controller = controller;
        _subscription = subscription;
        _feedbackSubscription = feedbackSubscription;
      });
      controller.requestSnapshot();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<bool> _confirmLeave() async {
    final snapshot = _snapshot;
    if (snapshot == null || snapshot.isFinished) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('online_forfeit_title')),
        content: Text(context.tr('online_forfeit_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.tr('stay')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.tr('forfeit_and_leave')),
          ),
        ],
      ),
    );
    if (leave == true) _controller?.forfeit();
    return leave == true;
  }

  void _selectCell(int index) {
    final snapshot = _snapshot;
    if (snapshot == null || snapshot.isFinished) {
      return;
    }
    if (snapshot.puzzle[index] != 0 ||
        snapshot.board[index] != 0 ||
        _controller?.pendingMove == true) {
      return;
    }
    setState(() => _selectedIndex = index);
  }

  void _enterNumber(int value) {
    final snapshot = _snapshot;
    final index = _selectedIndex;
    if (snapshot == null || index == null) return;
    _controller?.move(index, value);
  }

  void _sendScreenLoadedAfterRender(OnlineDuelSnapshot snapshot) {
    if (_screenLoadedSent ||
        snapshot.status == OnlineDuelStatus.active ||
        snapshot.isFinished) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _screenLoadedSent) return;
      _screenLoadedSent = true;
      _controller?.screenLoaded();
    });
  }

  void _showResultOnce(OnlineDuelSnapshot snapshot) {
    if (!snapshot.isFinished || _shownResultFor == snapshot.matchId) return;
    _shownResultFor = snapshot.matchId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await EconomyService.instance.refresh(showLoading: false);
      if (!mounted) return;
      final action = await showModalBottomSheet<String>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        isScrollControlled: true,
        useSafeArea: true,
        constraints: const BoxConstraints(maxWidth: 560),
        builder: (sheetContext) => _OnlineResultSheet(snapshot: snapshot),
      );
      if (!mounted) return;
      if (action == 'new_match' || action == 'menu') {
        Navigator.of(context).pop(action);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final waitingForOpponent =
        snapshot != null &&
        snapshot.status == OnlineDuelStatus.active &&
        !snapshot.isLocalTurn;
    return PopScope(
      canPop: snapshot?.isFinished ?? true,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await _confirmLeave() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 48,
          titleSpacing: 16,
          title: Text(context.tr('online_duel')),
        ),
        bottomNavigationBar: snapshot == null
            ? null
            : AnimatedOpacity(
                duration: const Duration(milliseconds: 240),
                opacity: waitingForOpponent ? 0.58 : 1,
                child: ColorFiltered(
                  colorFilter: ColorFilter.matrix(
                    waitingForOpponent
                        ? _grayscaleMatrix
                        : const <double>[
                            1,
                            0,
                            0,
                            0,
                            0,
                            0,
                            1,
                            0,
                            0,
                            0,
                            0,
                            0,
                            1,
                            0,
                            0,
                            0,
                            0,
                            0,
                            1,
                            0,
                          ],
                  ),
                  child: IgnorePointer(
                    ignoring:
                        snapshot.isFinished || _controller?.pendingMove == true,
                    child: NumberPadDock(
                      child: NumberPad(
                        maxValue: 9,
                        completedValues: completedSudokuNumbers(
                          board: snapshot.board,
                          maxValue: 9,
                        ),
                        enabled:
                            _controller?.pendingMove != true &&
                            !snapshot.isFinished,
                        onNumber: _enterNumber,
                        onErase: () => setState(() => _selectedIndex = null),
                      ),
                    ),
                  ),
                ),
              ),
        body: SafeArea(child: _buildBody(context)),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 44),
              const SizedBox(height: 12),
              Text(
                context.tr('online_connection_failed', <Object>[_error!]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _error = null;
                    _loading = true;
                  });
                  unawaited(_connect());
                },
                icon: const Icon(Icons.refresh),
                label: Text(context.tr('refresh')),
              ),
            ],
          ),
        ),
      );
    }
    final snapshot = _snapshot;
    if (snapshot == null) {
      return Center(child: Text(context.tr('online_waiting_snapshot')));
    }
    final puzzle = SudokuPuzzle(
      id: 'online-${snapshot.matchId}',
      title: 'Online Duel',
      difficulty: _difficulty(snapshot.difficulty),
      puzzle: snapshot.puzzle,
      solution: List<int>.filled(81, 1),
    );
    final waitingForOpponent =
        snapshot.status == OnlineDuelStatus.active && !snapshot.isLocalTurn;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxHeight < 520 || constraints.maxWidth < 380;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 8 : 12,
            compact ? 3 : 8,
            compact ? 8 : 12,
            compact ? 3 : 10,
          ),
          child: Column(
            children: [
              _TurnBanner(
                snapshot: snapshot,
                readySeconds: _secondsUntil(snapshot.readyDeadline),
                turnSeconds: _secondsUntil(snapshot.turnDeadline),
                compact: compact,
              ),
              SizedBox(height: compact ? 4 : 8),
              if (snapshot.status == OnlineDuelStatus.readyWindow ||
                  snapshot.status == OnlineDuelStatus.waiting)
                Padding(
                  padding: EdgeInsets.only(bottom: compact ? 4 : 8),
                  child: _ReadyPanel(
                    snapshot: snapshot,
                    seconds: _secondsUntil(snapshot.readyDeadline),
                    onReady: _controller?.ready,
                    compact: compact,
                  ),
                ),
              Expanded(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOut,
                  opacity: waitingForOpponent ? 0.58 : 1,
                  child: ColorFiltered(
                    colorFilter: ColorFilter.matrix(
                      waitingForOpponent
                          ? _grayscaleMatrix
                          : const <double>[
                              1,
                              0,
                              0,
                              0,
                              0,
                              0,
                              1,
                              0,
                              0,
                              0,
                              0,
                              0,
                              1,
                              0,
                              0,
                              0,
                              0,
                              0,
                              1,
                              0,
                            ],
                    ),
                    child: Column(
                      children: [
                        _ScoreHeader(snapshot: snapshot, compact: compact),
                        SizedBox(height: compact ? 4 : 8),
                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: IgnorePointer(
                                ignoring: snapshot.isFinished,
                                child: SudokuBoard(
                                  puzzle: puzzle,
                                  board: snapshot.board,
                                  selectedIndex: _selectedIndex,
                                  errorIndex: _feedbackCell,
                                  enabled: !snapshot.isFinished,
                                  onCellTap: _selectCell,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (!compact) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 24,
                            child: Center(
                              child: Text(
                                _controller?.pendingMove == true
                                    ? context.tr('sending_move')
                                    : snapshot.isLocalTurn
                                    ? context.tr(
                                        'select_empty_cell_enter_number',
                                      )
                                    : context.tr('waiting_opponent_move'),
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  int? _secondsUntil(DateTime? deadline) {
    if (deadline == null) return null;
    final diff = deadline.difference(DateTime.now()).inMilliseconds;
    return diff <= 0 ? 0 : (diff / 1000).ceil();
  }

  SudokuDifficulty _difficulty(String value) {
    return SudokuDifficulty.values.firstWhere(
      (difficulty) => difficulty.name == value,
      orElse: () => SudokuDifficulty.easy,
    );
  }
}

class _OnlineResultSheet extends StatefulWidget {
  const _OnlineResultSheet({required this.snapshot});

  final OnlineDuelSnapshot snapshot;

  @override
  State<_OnlineResultSheet> createState() => _OnlineResultSheetState();
}

class _OnlineResultSheetState extends State<_OnlineResultSheet> {
  final EconomyService _economy = EconomyService.instance;
  Timer? _pollTimer;
  Timer? _clockTimer;
  RematchInvitation? _invitation;
  bool _busy = false;
  String? _statusMessage;

  OnlineDuelSnapshot get snapshot => widget.snapshot;

  OnlineDuelSeat get opponentSeat => snapshot.youSeat == OnlineDuelSeat.a
      ? OnlineDuelSeat.b
      : OnlineDuelSeat.a;

  OnlineDuelPlayer get opponent => snapshot.players[opponentSeat]!;

  @override
  void initState() {
    super.initState();
    _economy.addListener(_onEconomyChanged);
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 700),
      (_) => unawaited(_pollRematches()),
    );
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    unawaited(_pollRematches());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _clockTimer?.cancel();
    _economy.removeListener(_onEconomyChanged);
    super.dispose();
  }

  void _onEconomyChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final localScore = snapshot.scores[snapshot.youSeat] ?? 0;
    final opponentScore = snapshot.scores[opponentSeat] ?? 0;
    final rating = snapshot.rating?[snapshot.youSeat];
    final won = snapshot.winnerSeat == snapshot.youSeat;
    final lost = snapshot.winnerSeat != null && !won;
    final resultTitle = snapshot.winnerSeat == null
        ? context.tr('draw')
        : won
        ? context.tr('you_won')
        : context.tr('you_lost');
    final balance = _economy.balance;
    final canPlay = _economy.canEnterOnline;
    final invite = _invitation;
    final seconds = invite == null
        ? 0
        : invite.expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 10);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            won
                ? Icons.emoji_events_rounded
                : lost
                ? Icons.sports_esports_outlined
                : Icons.handshake_outlined,
            size: 52,
          ),
          const SizedBox(height: 8),
          Text(
            resultTitle,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            context.tr('vs_opponent', <Object>[opponent.displayName]),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _ResultLine(
                    label: context.tr('final_score_label'),
                    value: '$localScore – $opponentScore',
                  ),
                  _ResultLine(
                    label: context.tr('entry_fee'),
                    value: context.tr('coin_amount', const <Object>[100]),
                  ),
                  _ResultLine(
                    label: won
                        ? context.tr('winner_pot')
                        : snapshot.winnerSeat == null
                        ? context.tr('refund')
                        : context.tr('match_result'),
                    value: won
                        ? '+${context.tr('coin_amount', const <Object>[200])}'
                        : snapshot.winnerSeat == null
                        ? '+${context.tr('coin_amount', const <Object>[100])}'
                        : context.tr('coin_amount', const <Object>[0]),
                  ),
                  _ResultLine(
                    label: context.tr('current_balance'),
                    value: context.tr('coin_amount', <Object>[balance]),
                  ),
                  if (rating != null)
                    _ResultLine(
                      label: context.tr('rating'),
                      value:
                          '${rating.beforeGlobal} → ${rating.afterGlobal} (${rating.deltaGlobal >= 0 ? '+' : ''}${rating.deltaGlobal})',
                    ),
                  if (snapshot.finishReason != null)
                    _ResultLine(
                      label: context.tr('finish_reason'),
                      value: snapshot.finishReason!.replaceAll('_', ' '),
                    ),
                ],
              ),
            ),
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _statusMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ],
          if (invite != null && invite.status == 'pending') ...[
            const SizedBox(height: 12),
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: invite.isSender
                    ? Row(
                        children: [
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              context.tr('waiting_for_player_seconds', <Object>[
                                opponent.displayName,
                                seconds,
                              ]),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            context.tr('wants_rematch_seconds', <Object>[
                              invite.sender.displayName,
                              seconds,
                            ]),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _respond(invite, false),
                                  child: Text(context.tr('decline')),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton(
                                  onPressed: _busy || !canPlay
                                      ? null
                                      : () => _respond(invite, true),
                                  child: Text(context.tr('accept')),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 430;
              final actions = <Widget>[
                FilledButton.icon(
                  onPressed: _busy || !canPlay || invite?.status == 'pending'
                      ? null
                      : _createRematch,
                  icon: const Icon(Icons.replay_rounded),
                  label: Text(context.tr('challenge_again')),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || !canPlay
                      ? null
                      : () => Navigator.of(context).pop('new_match'),
                  icon: const Icon(Icons.person_search_outlined),
                  label: Text(context.tr('find_new_match')),
                ),
              ];
              if (wide) {
                return Row(
                  children: [
                    Expanded(child: actions[0]),
                    const SizedBox(width: 8),
                    Expanded(child: actions[1]),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [actions[0], const SizedBox(height: 8), actions[1]],
              );
            },
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 430;
              final addFriend = OutlinedButton.icon(
                onPressed: _busy ? null : _addFriend,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: Text(context.tr('add_friend')),
              );
              final menu = TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).pop('menu'),
                icon: const Icon(Icons.home_outlined),
                label: Text(context.tr('main_menu')),
              );
              if (wide) {
                return Row(
                  children: [
                    Expanded(child: addFriend),
                    const SizedBox(width: 8),
                    Expanded(child: menu),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [addFriend, menu],
              );
            },
          ),
          if (!canPlay) ...[
            const SizedBox(height: 8),
            Text(
              context.tr('not_enough_coins_online', const <Object>[100]),
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 6),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CoinStoreScreen()),
              ),
              icon: const Icon(Icons.storefront_outlined),
              label: Text(context.tr('open_coin_store')),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _createRematch() async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final invitation = await _economy.createRematch(snapshot.matchId);
      if (!mounted) return;
      setState(() {
        _invitation = invitation;
        _statusMessage = context.tr('rematch_invitation_sent');
      });
    } on EconomyApiException catch (error) {
      if (!mounted) return;
      setState(() => _statusMessage = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _respond(RematchInvitation invitation, bool accept) async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final updated = await _economy.respondRematch(
        invitationId: invitation.id,
        accept: accept,
      );
      if (!mounted) return;
      setState(() => _invitation = updated);
      if (accept && updated.roomId?.isNotEmpty == true) {
        await _openAcceptedRoom(updated.roomId!);
      } else {
        setState(() => _statusMessage = context.tr('rematch_declined'));
      }
    } on EconomyApiException catch (error) {
      if (!mounted) return;
      setState(() => _statusMessage = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pollRematches() async {
    try {
      final invitations = await _economy.loadRematches();
      if (!mounted) return;
      RematchInvitation? relevant;
      for (final item in invitations) {
        if (item.previousMatchId == snapshot.matchId) {
          relevant = item;
          break;
        }
      }
      if (relevant == null) return;
      final previousStatus = _invitation?.status;
      setState(() => _invitation = relevant);
      if (relevant.status == 'accepted' &&
          relevant.roomId?.isNotEmpty == true) {
        await _openAcceptedRoom(relevant.roomId!);
      } else if (previousStatus == 'pending' && relevant.status == 'declined') {
        setState(() => _statusMessage = context.tr('challenge_declined'));
      } else if (previousStatus == 'pending' && relevant.status == 'expired') {
        setState(() => _statusMessage = context.tr('challenge_timed_out'));
      } else if (relevant.status == 'insufficient_coins') {
        setState(() => _statusMessage = context.tr('player_not_enough_coin'));
      }
    } catch (_) {
      // Result actions remain usable if a background poll temporarily fails.
    }
  }

  Future<void> _openAcceptedRoom(String roomId) async {
    _pollTimer?.cancel();
    if (!mounted) return;
    Navigator.of(context).pop();
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => OnlineDuelScreen(roomId: roomId)),
    );
  }

  Future<void> _addFriend() async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      await SocialApiClient.instance.sendFriendRequest(opponent.publicId);
      if (!mounted) return;
      setState(() => _statusMessage = context.tr('friend_request_sent'));
    } on SocialApiException catch (error) {
      if (!mounted) return;
      setState(() => _statusMessage = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _ScoreHeader extends StatelessWidget {
  const _ScoreHeader({required this.snapshot, required this.compact});

  final OnlineDuelSnapshot snapshot;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PlayerCard(
            snapshot: snapshot,
            seat: OnlineDuelSeat.a,
            compact: compact,
          ),
        ),
        SizedBox(width: compact ? 6 : 10),
        Expanded(
          child: _PlayerCard(
            snapshot: snapshot,
            seat: OnlineDuelSeat.b,
            compact: compact,
          ),
        ),
      ],
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.snapshot,
    required this.seat,
    required this.compact,
  });

  final OnlineDuelSnapshot snapshot;
  final OnlineDuelSeat seat;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final player = snapshot.players[seat]!;
    final active = snapshot.currentTurnSeat == seat;
    final isLocalPlayer = snapshot.youSeat == seat;
    final scheme = Theme.of(context).colorScheme;
    final displayName = isLocalPlayer ? 'You' : player.displayName;

    if (compact) {
      return Card(
        margin: EdgeInsets.zero,
        color: active ? scheme.primaryContainer : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              if (active) ...[
                Icon(Icons.circle, size: 8, color: scheme.primary),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '${snapshot.scores[seat] ?? 0}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              if (!player.connected) ...[
                const SizedBox(width: 4),
                const Icon(Icons.wifi_off_rounded, size: 15),
              ],
            ],
          ),
        ),
      );
    }

    return Card(
      color: active ? scheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '${snapshot.scores[seat] ?? 0}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              player.connected
                  ? context.tr('connected')
                  : context.tr('reconnecting'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _TurnBanner extends StatelessWidget {
  const _TurnBanner({
    required this.snapshot,
    required this.readySeconds,
    required this.turnSeconds,
    required this.compact,
  });

  final OnlineDuelSnapshot snapshot;
  final int? readySeconds;
  final int? turnSeconds;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final active = snapshot.status == OnlineDuelStatus.active;
    final text = active
        ? snapshot.isLocalTurn
              ? context.tr('your_turn')
              : context.tr('opponents_turn')
        : snapshot.status == OnlineDuelStatus.readyWindow
        ? context.tr('get_ready')
        : context.tr('connecting_players');
    final subtitle = active
        ? compact
              ? '${turnSeconds ?? 0} s'
              : context.tr('move_time_seconds', <Object>[turnSeconds ?? 0])
        : snapshot.status == OnlineDuelStatus.readyWindow
        ? compact
              ? '${readySeconds ?? 0} s'
              : context.tr('automatic_start_seconds', <Object>[
                  readySeconds ?? 0,
                ])
        : context.tr('online_turn_number', <Object>[snapshot.turnNumber]);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      label: '$text, $subtitle',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: snapshot.isLocalTurn
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: snapshot.isLocalTurn
              ? Border.all(color: scheme.primary, width: 1.5)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              snapshot.isLocalTurn
                  ? Icons.touch_app_rounded
                  : Icons.hourglass_top_rounded,
              size: compact ? 18 : 24,
            ),
            SizedBox(width: compact ? 5 : 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontWeight: FontWeight.w900),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Flexible(
              child: Text(
                subtitle,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadyPanel extends StatelessWidget {
  const _ReadyPanel({
    required this.snapshot,
    required this.seconds,
    required this.onReady,
    required this.compact,
  });

  final OnlineDuelSnapshot snapshot;
  final int? seconds;
  final VoidCallback? onReady;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final you = snapshot.players[snapshot.youSeat]!;
    final opponentSeat = snapshot.youSeat == OnlineDuelSeat.a
        ? OnlineDuelSeat.b
        : OnlineDuelSeat.a;
    final opponent = snapshot.players[opponentSeat]!;
    final opponentStatus = !opponent.connected
        ? context.tr('opponent_connecting')
        : !opponent.screenLoaded
        ? context.tr('opponent_opening_game')
        : context.tr('opponent_ready');
    final countdownText = seconds == null ? '' : ' · $seconds s';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$opponentStatus$countdownText',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: compact
                  ? Theme.of(context).textTheme.bodySmall
                  : Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          SizedBox(width: compact ? 5 : 8),
          FilledButton.icon(
            onPressed: you.ready ? null : onReady,
            style: compact
                ? FilledButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 7,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  )
                : null,
            icon: Icon(
              you.ready ? Icons.check_circle : Icons.check_circle_outline,
              size: compact ? 17 : 24,
            ),
            label: Text(
              you.ready ? context.tr('ready') : context.tr('i_am_ready'),
            ),
          ),
        ],
      ),
    );
  }
}
