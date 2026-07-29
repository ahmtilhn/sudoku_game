import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/economy_api_client.dart';
import '../../services/economy_service.dart';
import '../../services/online_duel_controller.dart';
import '../../services/online_duel_models.dart';
import '../../services/online_duel_transport.dart';
import '../../services/social_api_client.dart';
import '../../widgets/number_pad.dart';
import '../../widgets/player_avatar.dart';
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
  OnlineDuelController? _controller;
  StreamSubscription<OnlineDuelSnapshot>? _subscription;
  StreamSubscription<OnlineDuelFeedback>? _feedbackSubscription;
  OnlineDuelSnapshot? _snapshot;
  Object? _error;
  int? _selectedIndex;
  int? _feedbackCell;
  final Set<int> _localMoveIndexes = <int>{};
  final Set<int> _opponentMoveIndexes = <int>{};
  bool _loading = true;
  bool _screenLoadedSent = false;
  Timer? _feedbackTimer;
  Timer? _progressTimer;
  String? _shownResultFor;

  @override
  void initState() {
    super.initState();
    unawaited(_connect());
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_feedbackSubscription?.cancel());
    unawaited(_controller?.dispose());
    _feedbackTimer?.cancel();
    _progressTimer?.cancel();
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
        final previous = _snapshot;
        final previousLocalTurn = _snapshot?.isLocalTurn ?? false;
        _markProgress(previous, snapshot);
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
            if (feedback.cellIndex != null) {
              _localMoveIndexes
                ..clear()
                ..add(feedback.cellIndex!);
              _opponentMoveIndexes.clear();
            }
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
        _scheduleProgressClear();
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

  void _markProgress(
    OnlineDuelSnapshot? previous,
    OnlineDuelSnapshot snapshot,
  ) {
    if (previous == null || previous.matchId != snapshot.matchId) return;
    final changed = <int>{};
    final max = previous.board.length < snapshot.board.length
        ? previous.board.length
        : snapshot.board.length;
    for (var index = 0; index < max; index++) {
      if (previous.board[index] == 0 && snapshot.board[index] != 0) {
        changed.add(index);
      }
    }
    if (changed.isEmpty) return;
    final localChanged = _localMoveIndexes.any(changed.contains);
    setState(() {
      if (!localChanged) {
        _opponentMoveIndexes
          ..clear()
          ..addAll(changed);
      }
    });
    _scheduleProgressClear();
  }

  void _scheduleProgressClear() {
    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        _localMoveIndexes.clear();
        _opponentMoveIndexes.clear();
      });
    });
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
    final activeArena = snapshot?.status == OnlineDuelStatus.active;
    final inputLocked =
        snapshot != null &&
        (snapshot.isFinished ||
            !snapshot.isLocalTurn ||
            _controller?.pendingMove == true);
    return PopScope(
      canPop: snapshot?.isFinished ?? true,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await _confirmLeave() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: activeArena ? const Color(0xFF050A18) : null,
        appBar: activeArena
            ? null
            : AppBar(
                toolbarHeight: 48,
                titleSpacing: 16,
                title: Text(
                  snapshot == null
                      ? context.tr('online_duel')
                      : context.strings.difficultyLabel(
                          _difficulty(snapshot.difficulty),
                        ),
                ),
              ),
        bottomNavigationBar: snapshot == null
            ? null
            : Theme(
                data: activeArena ? _arenaTheme(context) : Theme.of(context),
                child: IgnorePointer(
                  ignoring: inputLocked,
                  child: NumberPadDock(
                    child: NumberPad(
                      maxValue: 9,
                      completedValues: completedSudokuNumbers(
                        board: snapshot.board,
                        maxValue: 9,
                      ),
                      enabled: !inputLocked,
                      onNumber: _enterNumber,
                      onErase: () => setState(() => _selectedIndex = null),
                    ),
                  ),
                ),
              ),
        body: Theme(
          data: activeArena ? _arenaTheme(context) : Theme.of(context),
          child: SafeArea(child: _buildBody(context)),
        ),
      ),
    );
  }

  ThemeData _arenaTheme(BuildContext context) {
    final base = Theme.of(context);
    const scheme = ColorScheme.dark(
      primary: Color(0xFF159BFF),
      onPrimary: Colors.white,
      secondary: Color(0xFF8B63FF),
      onSecondary: Colors.white,
      tertiary: Color(0xFFB64DFF),
      surface: Color(0xFF091226),
      surfaceContainerLow: Color(0xFF0B1428),
      surfaceContainerHighest: Color(0xFF111C34),
      outline: Color(0xFF263957),
      outlineVariant: Color(0xFF1A2943),
      error: Color(0xFFFF6B7A),
      errorContainer: Color(0xFF4A1720),
      onSurface: Color(0xFFE7EEFF),
      onSurfaceVariant: Color(0xFF91A0BC),
    );
    return base.copyWith(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF050A18),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxHeight < 520 || constraints.maxWidth < 380;
        final board = RepaintBoundary(
          child: IgnorePointer(
            ignoring: snapshot.isFinished || !snapshot.isLocalTurn,
            child: SudokuBoard(
              puzzle: puzzle,
              board: snapshot.board,
              selectedIndex: _selectedIndex,
              errorIndex: _feedbackCell,
              localMoveIndexes: _localMoveIndexes,
              opponentMoveIndexes: _opponentMoveIndexes,
              enabled: !snapshot.isFinished && snapshot.isLocalTurn,
              onCellTap: _selectCell,
            ),
          ),
        );
        if (snapshot.status == OnlineDuelStatus.active) {
          return _ArenaMatchLayout(
            snapshot: snapshot,
            compact: compact,
            board: board,
            statusText: _controller?.pendingMove == true
                ? context.tr('sending_move')
                : snapshot.isLocalTurn
                ? context.tr('select_empty_cell_enter_number')
                : context.tr('waiting_opponent_move'),
          );
        }
        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 8 : 12,
            compact ? 3 : 8,
            compact ? 8 : 12,
            compact ? 3 : 10,
          ),
          child: Column(
            children: [
              if (snapshot.status == OnlineDuelStatus.readyWindow ||
                  snapshot.status == OnlineDuelStatus.waiting)
                Padding(
                  padding: EdgeInsets.only(bottom: compact ? 4 : 8),
                  child: _ReadyPanel(
                    snapshot: snapshot,
                    onReady: _controller?.ready,
                    compact: compact,
                  ),
                ),
              Expanded(
                child: Center(child: AspectRatio(aspectRatio: 1, child: board)),
              ),
            ],
          ),
        );
      },
    );
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

  OnlineDuelPlayer get winnerPlayer {
    final winnerSeat = snapshot.winnerSeat;
    if (winnerSeat == null) return snapshot.players[snapshot.youSeat]!;
    return snapshot.players[winnerSeat]!;
  }

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
    final entryFee = _economy.entryFeeForDifficulty(snapshot.difficulty);
    final winnerPot = _economy.winnerPotForDifficulty(snapshot.difficulty);
    final resultTitle = snapshot.winnerSeat == null
        ? context.tr('draw')
        : won
        ? context.tr('you_won')
        : context.tr('you_lost');
    final balance = _economy.balance;
    final canPlay = _economy.balance >= entryFee;
    final invite = _invitation;
    final seconds = invite == null
        ? 0
        : invite.expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 10);
    final coinDelta = snapshot.coinSettlement?.deltas[snapshot.youSeat];
    final coinValue = coinDelta == null
        ? (won
              ? '+${context.tr('coin_amount', <Object>[winnerPot])}'
              : snapshot.winnerSeat == null
              ? '+${context.tr('coin_amount', <Object>[entryFee])}'
              : context.tr('coin_amount', const <Object>[0]))
        : '${coinDelta >= 0 ? '+' : ''}${context.tr('coin_amount', <Object>[coinDelta])}';

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
          PlayerAvatar(
            displayName: winnerPlayer.displayName,
            avatarKey: winnerPlayer.avatarKey,
            radius: 32,
            semanticLabel: context.tr('winner_avatar_semantics', <Object>[
              winnerPlayer.displayName,
            ]),
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
            snapshot.winnerSeat == null
                ? context.tr('draw')
                : context.tr('winner_name', <Object>[winnerPlayer.displayName]),
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
                    label: context.tr('match_type'),
                    value:
                        '${snapshot.mode.toUpperCase()} · ${snapshot.difficulty}',
                  ),
                  _ResultLine(
                    label: context.tr('online_turns_label'),
                    value: '${snapshot.turnNumber}',
                  ),
                  _ResultLine(
                    label: context.tr('final_score_label'),
                    value: '$localScore – $opponentScore',
                  ),
                  _ResultLine(
                    label: context.tr('entry_fee'),
                    value: context.tr('coin_amount', <Object>[entryFee]),
                  ),
                  _ResultLine(
                    label: won
                        ? context.tr('winner_pot')
                        : snapshot.winnerSeat == null
                        ? context.tr('refund')
                        : context.tr('match_result'),
                    value: coinValue,
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
                  _ResultLine(
                    label: context.tr('mistakes'),
                    value: '${snapshot.mistakes[snapshot.youSeat] ?? 0}',
                  ),
                  _ResultLine(
                    label: context.tr('correct_moves'),
                    value: '${snapshot.correctMoves[snapshot.youSeat] ?? 0}',
                  ),
                  _ResultLine(
                    label: context.tr('timeouts'),
                    value: '${snapshot.timeouts[snapshot.youSeat] ?? 0}',
                  ),
                  _ResultLine(
                    label: context.tr('hints'),
                    value: context.tr('not_available_short'),
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
              context.tr('not_enough_coins_online', <Object>[entryFee]),
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

class _ArenaMatchLayout extends StatelessWidget {
  const _ArenaMatchLayout({
    required this.snapshot,
    required this.compact,
    required this.board,
    required this.statusText,
  });

  final OnlineDuelSnapshot snapshot;
  final bool compact;
  final Widget board;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF050A18), Color(0xFF071226), Color(0xFF050A18)],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 8 : 12,
          compact ? 6 : 10,
          compact ? 8 : 12,
          compact ? 6 : 10,
        ),
        child: Column(
          children: [
            _MatchHeader(snapshot: snapshot, compact: compact),
            SizedBox(height: compact ? 8 : 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 720;
                  final boardMax = constraints.maxHeight < constraints.maxWidth
                      ? constraints.maxHeight
                      : constraints.maxWidth;
                  final boardSize = wide
                      ? (boardMax - 10).clamp(280.0, 520.0)
                      : boardMax.clamp(260.0, 520.0);
                  final boardWidget = Center(
                    child: SizedBox.square(
                      dimension: boardSize,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF159BFF,
                              ).withValues(alpha: .18),
                              blurRadius: 24,
                            ),
                          ],
                        ),
                        child: board,
                      ),
                    ),
                  );
                  if (!wide) return boardWidget;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(width: 88, child: _ArenaToolRail()),
                      Expanded(child: boardWidget),
                      SizedBox(
                        width: 120,
                        child: _MoveHistoryPanel(snapshot: snapshot),
                      ),
                    ],
                  );
                },
              ),
            ),
            SizedBox(height: compact ? 4 : 8),
            Text(
              statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: .58),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArenaToolRail extends StatelessWidget {
  const _ArenaToolRail();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ArenaToolButton(
          icon: Icons.lightbulb_outline,
          label: context.tr('hint'),
        ),
        const SizedBox(height: 8),
        _ArenaToolButton(icon: Icons.edit_outlined, label: context.tr('notes')),
        const SizedBox(height: 8),
        _ArenaToolButton(icon: Icons.undo, label: context.tr('undo')),
      ],
    );
  }
}

class _ArenaToolButton extends StatelessWidget {
  const _ArenaToolButton({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF111C34).withValues(alpha: .88),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF263957)),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF9AB8FF), size: 20),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .72),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MoveHistoryPanel extends StatelessWidget {
  const _MoveHistoryPanel({required this.snapshot});

  final OnlineDuelSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final opponentSeat = snapshot.youSeat == OnlineDuelSeat.a
        ? OnlineDuelSeat.b
        : OnlineDuelSeat.a;
    final opponent = snapshot.players[opponentSeat]!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D172C).withValues(alpha: .88),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF263957)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('last_move'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: .68),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          _HistoryDot(
            color: const Color(0xFF9B4DFF),
            label: opponent.displayName,
            value: '${snapshot.scores[opponentSeat] ?? 0}',
          ),
          const SizedBox(height: 8),
          _HistoryDot(
            color: const Color(0xFF159BFF),
            label: context.tr('you'),
            value: '${snapshot.scores[snapshot.youSeat] ?? 0}',
          ),
        ],
      ),
    );
  }
}

class _HistoryDot extends StatelessWidget {
  const _HistoryDot({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .7),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _MatchHeader extends StatelessWidget {
  const _MatchHeader({required this.snapshot, required this.compact});

  final OnlineDuelSnapshot snapshot;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scoreA = snapshot.scores[OnlineDuelSeat.a] ?? 0;
    final scoreB = snapshot.scores[OnlineDuelSeat.b] ?? 0;
    final total = (scoreA + scoreB).clamp(1, 999999);
    final aShare = scoreA / total;
    final scheme = Theme.of(context).colorScheme;
    final height = compact ? 76.0 : 88.0;
    final timerSize = compact ? 58.0 : 70.0;

    return Semantics(
      label: context.tr('match_header_semantics'),
      child: SizedBox(
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Positioned.fill(
              top: compact ? 10 : 12,
              bottom: compact ? 6 : 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF071124).withValues(alpha: .84),
                  border: Border(
                    top: BorderSide(
                      color: const Color(0xFF1B2C50).withValues(alpha: .9),
                    ),
                    bottom: BorderSide(
                      color: const Color(0xFF162743).withValues(alpha: .9),
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .28),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: .08),
                      blurRadius: 22,
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              top: compact ? 10 : 12,
              bottom: compact ? 6 : 8,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _HeaderCircuitPainter(
                    primary: scheme.primary,
                    tertiary: scheme.tertiary,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              top: compact ? 12 : 14,
              bottom: compact ? 11 : 13,
              child: Row(
                children: [
                  Expanded(
                    child: _DuelPlayerPlate(
                      snapshot: snapshot,
                      seat: OnlineDuelSeat.a,
                      compact: compact,
                    ),
                  ),
                  SizedBox(width: timerSize + (compact ? 10 : 18)),
                  Expanded(
                    child: _DuelPlayerPlate(
                      snapshot: snapshot,
                      seat: OnlineDuelSeat.b,
                      compact: compact,
                      alignEnd: true,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              child: _TimerPill(
                deadline: snapshot.turnDeadline,
                compact: compact,
                size: timerSize,
              ),
            ),
            Positioned(
              left: compact ? 18 : 30,
              right: compact ? 18 : 30,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: .24),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: compact ? 4 : 5,
                    child: Row(
                      children: [
                        Expanded(
                          flex: (aShare * 1000).round().clamp(1, 999).toInt(),
                          child: ColoredBox(color: scheme.primary),
                        ),
                        Expanded(
                          flex: ((1 - aShare) * 1000)
                              .round()
                              .clamp(1, 999)
                              .toInt(),
                          child: ColoredBox(color: scheme.tertiary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCircuitPainter extends CustomPainter {
  const _HeaderCircuitPainter({required this.primary, required this.tertiary});

  final Color primary;
  final Color tertiary;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height * .5;
    final center = size.width * .5;
    final gap = size.height * .62;
    final linePaint = Paint()
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..shader = LinearGradient(
        colors: [
          primary.withValues(alpha: .42),
          Colors.white.withValues(alpha: .08),
          tertiary.withValues(alpha: .42),
        ],
      ).createShader(Offset.zero & size);

    canvas.drawLine(Offset(0, midY), Offset(center - gap, midY), linePaint);
    canvas.drawLine(
      Offset(center + gap, midY),
      Offset(size.width, midY),
      linePaint,
    );

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: .06);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center, midY),
        width: size.height * .98,
        height: size.height * .98,
      ),
      glow,
    );
  }

  @override
  bool shouldRepaint(covariant _HeaderCircuitPainter oldDelegate) {
    return oldDelegate.primary != primary || oldDelegate.tertiary != tertiary;
  }
}

class _TimerPill extends StatefulWidget {
  const _TimerPill({required this.deadline, required this.compact, this.size});

  final DateTime? deadline;
  final bool compact;
  final double? size;

  @override
  State<_TimerPill> createState() => _TimerPillState();
}

class _TimerPillState extends State<_TimerPill> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gameColors = Theme.of(context).extension<GameColors>()!;
    final seconds = _secondsUntil(widget.deadline);
    final color = seconds != null && seconds <= 5
        ? gameColors.timerCritical
        : seconds != null && seconds <= 10
        ? gameColors.warning
        : scheme.primary;
    final size = widget.size ?? (widget.compact ? 52.0 : 70.0);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFF17294C), Color(0xFF071124)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .18)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: .48), blurRadius: 18),
          BoxShadow(
            color: Colors.black.withValues(alpha: .36),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.all(5),
            child: CircularProgressIndicator(
              value: seconds == null ? null : (seconds / 30).clamp(0.0, 1.0),
              strokeWidth: widget.compact ? 2.4 : 3,
              backgroundColor: Colors.white.withValues(alpha: .08),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${seconds ?? 0}',
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.compact ? 22 : 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    context.tr('seconds_short'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .64),
                      fontSize: widget.compact ? 8 : 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  int? _secondsUntil(DateTime? deadline) {
    if (deadline == null) return null;
    final diff = deadline.difference(DateTime.now()).inMilliseconds;
    return diff <= 0 ? 0 : (diff / 1000).ceil();
  }
}

class _DuelPlayerPlate extends StatelessWidget {
  const _DuelPlayerPlate({
    required this.snapshot,
    required this.seat,
    required this.compact,
    this.alignEnd = false,
  });

  final OnlineDuelSnapshot snapshot;
  final OnlineDuelSeat seat;
  final bool compact;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final player = snapshot.players[seat]!;
    final active = snapshot.currentTurnSeat == seat;
    final isLocalPlayer = snapshot.youSeat == seat;
    final scheme = Theme.of(context).colorScheme;
    final accent = seat == OnlineDuelSeat.a ? scheme.primary : scheme.tertiary;
    final displayName = isLocalPlayer ? context.tr('you') : player.displayName;
    final score = snapshot.scores[seat] ?? 0;
    final avatarRadius = compact ? 17.0 : 23.0;
    final avatar = _AvatarRing(
      color: accent,
      active: active,
      child: PlayerAvatar(
        displayName: player.displayName,
        avatarKey: player.avatarKey,
        radius: avatarRadius,
        semanticLabel: context.tr('player_avatar_semantics', <Object>[
          displayName,
        ]),
      ),
    );
    final children = <Widget>[
      avatar,
      SizedBox(width: compact ? 6 : 9),
      Expanded(
        child: Column(
          crossAxisAlignment: alignEnd
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (compact)
              Align(
                alignment: alignEnd
                    ? AlignmentDirectional.centerEnd
                    : AlignmentDirectional.centerStart,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: alignEnd
                      ? AlignmentDirectional.centerEnd
                      : AlignmentDirectional.centerStart,
                  child: Column(
                    crossAxisAlignment: alignEnd
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _ScoreLine(
                        score: score,
                        connected: player.connected,
                        color: accent,
                      ),
                    ],
                  ),
                ),
              )
            else
              Row(
                mainAxisAlignment: alignEnd
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 3),
            Align(
              alignment: alignEnd
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              child: _ScoreLine(
                score: score,
                connected: player.connected,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    ];
    final compactChildren = <Widget>[
      children[0],
      children[1],
      if (children[2] case final Expanded info) info.child else children[2],
    ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: Colors.transparent,
        boxShadow: active
            ? [BoxShadow(color: accent.withValues(alpha: .18), blurRadius: 14)]
            : null,
      ),
      child: compact
          ? Align(
              alignment: alignEnd
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  textDirection: alignEnd
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  children: compactChildren,
                ),
              ),
            )
          : Row(
              textDirection: alignEnd ? TextDirection.rtl : TextDirection.ltr,
              children: children,
            ),
    );
  }
}

class _AvatarRing extends StatelessWidget {
  const _AvatarRing({
    required this.child,
    required this.color,
    required this.active,
  });

  final Widget child;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? color : Colors.white.withValues(alpha: .24),
          width: active ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: active ? .54 : .24),
            blurRadius: active ? 16 : 10,
          ),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(2), child: child),
    );
  }
}

class _ScoreLine extends StatelessWidget {
  const _ScoreLine({
    required this.score,
    required this.connected,
    required this.color,
  });

  final int score;
  final bool connected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.emoji_events, size: 13, color: scheme.tertiary),
        const SizedBox(width: 3),
        Text(
          '$score',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .92),
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          connected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
          size: 12,
          color: connected ? color : scheme.error,
        ),
      ],
    );
  }
}

class _ReadyPanel extends StatelessWidget {
  const _ReadyPanel({
    required this.snapshot,
    required this.onReady,
    required this.compact,
  });

  final OnlineDuelSnapshot snapshot;
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

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final readyButton = FilledButton.icon(
            onPressed: you.ready ? null : onReady,
            icon: Icon(
              you.ready ? Icons.check_circle : Icons.check_circle_outline,
              size: compact ? 17 : 24,
            ),
            label: Text(
              you.ready ? context.tr('ready') : context.tr('i_am_ready'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
          final status = Row(
            children: [
              Expanded(
                child: Text(
                  opponentStatus,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: compact
                      ? Theme.of(context).textTheme.bodySmall
                      : Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 6),
              _CountdownText(deadline: snapshot.readyDeadline),
            ],
          );
          if (compact || constraints.maxWidth < 360) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [status, const SizedBox(height: 6), readyButton],
            );
          }
          return Row(
            children: [
              Expanded(child: status),
              const SizedBox(width: 8),
              readyButton,
            ],
          );
        },
      ),
    );
  }
}

class _CountdownText extends StatefulWidget {
  const _CountdownText({required this.deadline});

  final DateTime? deadline;

  @override
  State<_CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends State<_CountdownText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = _secondsUntil(widget.deadline);
    if (seconds == null) return const SizedBox.shrink();
    return Text(
      context.tr('turn_timer_seconds', <Object>[seconds]),
      style: const TextStyle(fontWeight: FontWeight.w800),
    );
  }

  int? _secondsUntil(DateTime? deadline) {
    if (deadline == null) return null;
    final diff = deadline.difference(DateTime.now()).inMilliseconds;
    return diff <= 0 ? 0 : (diff / 1000).ceil();
  }
}
