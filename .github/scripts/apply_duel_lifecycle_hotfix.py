from pathlib import Path


def read(path: str) -> str:
    return Path(path).read_text(encoding='utf-8')


def write(path: str, text: str) -> None:
    Path(path).write_text(text, encoding='utf-8')


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    if old not in text:
        raise SystemExit(f'pattern not found in {path}: {old[:160]!r}')
    write(path, text.replace(old, new, 1))


def replace_section(path: str, start: str, end: str, replacement: str) -> None:
    text = read(path)
    i = text.find(start)
    if i < 0:
        raise SystemExit(f'start marker not found in {path}: {start!r}')
    j = text.find(end, i + len(start))
    if j < 0:
        raise SystemExit(f'end marker not found in {path}: {end!r}')
    write(path, text[:i] + replacement + text[j:])


screen = 'lib/features/duel/online_duel_screen.dart'

replace_once(
    screen,
    "  StreamSubscription<OnlineDuelSnapshot>? _subscription;\n  StreamSubscription<OnlineDuelFeedback>? _feedbackSubscription;\n  OnlineDuelSnapshot? _snapshot;",
    "  StreamSubscription<OnlineDuelSnapshot>? _subscription;\n  StreamSubscription<OnlineDuelFeedback>? _feedbackSubscription;\n  StreamSubscription<OnlineDuelConnectionState>? _connectionSubscription;\n  OnlineDuelSnapshot? _snapshot;",
)
replace_once(
    screen,
    "  Timer? _resultSettlementTimer;\n  String? _shownResultFor;\n  int _resultSettlementAttempts = 0;\n  bool _forfeiting = false;",
    "  Timer? _resultSettlementTimer;\n  Timer? _disconnectEscapeTimer;\n  DateTime? _localDisconnectDeadline;\n  OnlineDuelConnectionState _connectionState = OnlineDuelConnectionState.connecting;\n  String? _shownResultFor;\n  int _resultSettlementAttempts = 0;\n  bool _forfeiting = false;\n  bool _exitingToMenu = false;\n\n  static const Duration _disconnectFailSafe = Duration(seconds: 30);",
)
replace_once(
    screen,
    "    unawaited(_feedbackSubscription?.cancel());\n    unawaited(_controller?.dispose());\n    _feedbackTimer?.cancel();\n    _progressTimer?.cancel();\n    _resultSettlementTimer?.cancel();",
    "    unawaited(_feedbackSubscription?.cancel());\n    unawaited(_connectionSubscription?.cancel());\n    unawaited(_controller?.dispose());\n    _feedbackTimer?.cancel();\n    _progressTimer?.cancel();\n    _resultSettlementTimer?.cancel();\n    _disconnectEscapeTimer?.cancel();",
)
replace_once(
    screen,
    "      controller.start();\n      final subscription = controller.snapshots.listen((snapshot) {",
    "      controller.start();\n      final connectionSubscription = controller.connectionStates.listen(\n        _handleConnectionState,\n      );\n      final subscription = controller.snapshots.listen((snapshot) {",
)
replace_once(
    screen,
    "      setState(() {\n        _controller = controller;\n        _subscription = subscription;\n        _feedbackSubscription = feedbackSubscription;\n      });\n      controller.requestSnapshot();",
    "      setState(() {\n        _controller = controller;\n        _subscription = subscription;\n        _feedbackSubscription = feedbackSubscription;\n        _connectionSubscription = connectionSubscription;\n        _connectionState = controller.connectionState;\n      });\n      _handleConnectionState(controller.connectionState);\n      controller.requestSnapshot();",
)

request_forfeit_start = "  Future<void> _requestForfeit() async {"
request_forfeit_end = "  void _selectCell(int index) {"
replace_section(
    screen,
    request_forfeit_start,
    request_forfeit_end,
    '''  bool get _localConnectionInterrupted =>
      _snapshot != null &&
      (_connectionState == OnlineDuelConnectionState.reconnecting ||
          _connectionState == OnlineDuelConnectionState.resyncing ||
          _connectionState == OnlineDuelConnectionState.failed);

  void _handleConnectionState(OnlineDuelConnectionState state) {
    if (!mounted) return;
    final shouldStartFailSafe =
        _snapshot != null &&
        (state == OnlineDuelConnectionState.reconnecting ||
            state == OnlineDuelConnectionState.failed);

    if (state == OnlineDuelConnectionState.connected) {
      _disconnectEscapeTimer?.cancel();
      _disconnectEscapeTimer = null;
      if (_connectionState != state || _localDisconnectDeadline != null) {
        setState(() {
          _connectionState = state;
          _localDisconnectDeadline = null;
        });
      }
      return;
    }

    if (shouldStartFailSafe && _localDisconnectDeadline == null) {
      final deadline = DateTime.now().add(_disconnectFailSafe);
      _disconnectEscapeTimer?.cancel();
      _disconnectEscapeTimer = Timer(_disconnectFailSafe, () {
        if (!mounted || _connectionState == OnlineDuelConnectionState.connected) {
          return;
        }
        unawaited(_returnToMainMenu());
      });
      setState(() {
        _connectionState = state;
        _localDisconnectDeadline = deadline;
      });
      return;
    }

    if (_connectionState != state) {
      setState(() => _connectionState = state);
    }
  }

  Future<void> _returnToMainMenu({bool sendForfeit = false}) async {
    if (_exitingToMenu || !mounted) return;
    _disconnectEscapeTimer?.cancel();
    _disconnectEscapeTimer = null;
    setState(() {
      _exitingToMenu = true;
      if (sendForfeit) _forfeiting = true;
    });

    if (sendForfeit) {
      _controller?.forfeit();
      if (_connectionState == OnlineDuelConnectionState.connected ||
          _connectionState == OnlineDuelConnectionState.resyncing) {
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
    }

    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _requestForfeit() async {
    final snapshot = _snapshot;
    if (snapshot == null ||
        snapshot.isFinished ||
        _forfeiting ||
        _exitingToMenu ||
        !mounted) {
      return;
    }
    final forfeit = await showDialog<bool>(
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
    if (forfeit != true || !mounted) return;
    await _returnToMainMenu(sendForfeit: true);
  }

''',
)

replace_once(
    screen,
    "        (snapshot.isFinished ||\n            !snapshot.isLocalTurn ||\n            _controller?.pendingMove == true);",
    "        (snapshot.isFinished ||\n            snapshot.status == OnlineDuelStatus.paused ||\n            _localConnectionInterrupted ||\n            _exitingToMenu ||\n            !snapshot.isLocalTurn ||\n            _controller?.pendingMove == true);",
)
replace_once(
    screen,
    "      canPop: snapshot?.isFinished ?? true,",
    "      canPop: _exitingToMenu || (snapshot?.isFinished ?? true),",
)
replace_once(
    screen,
    "            ignoring: snapshot.isFinished || !snapshot.isLocalTurn,",
    "            ignoring:\n                snapshot.isFinished ||\n                snapshot.status == OnlineDuelStatus.paused ||\n                _localConnectionInterrupted ||\n                !snapshot.isLocalTurn,",
)
replace_once(
    screen,
    "              enabled: !snapshot.isFinished && snapshot.isLocalTurn,",
    "              enabled:\n                  !snapshot.isFinished &&\n                  snapshot.status != OnlineDuelStatus.paused &&\n                  !_localConnectionInterrupted &&\n                  snapshot.isLocalTurn,",
)
replace_once(
    screen,
    "            statusText: snapshot.status == OnlineDuelStatus.paused\n                ? context.tr('connection_interrupted_retrying')",
    "            localConnectionInterrupted: _localConnectionInterrupted,\n            localDisconnectDeadline: _localDisconnectDeadline,\n            statusText:\n                snapshot.status == OnlineDuelStatus.paused ||\n                    _localConnectionInterrupted\n                ? context.tr('connection_interrupted_retrying')",
)

replace_once(
    screen,
    "    required this.statusText,\n    required this.onForfeit,\n    required this.forfeiting,",
    "    required this.statusText,\n    required this.onForfeit,\n    required this.forfeiting,\n    required this.localConnectionInterrupted,\n    required this.localDisconnectDeadline,",
)
replace_once(
    screen,
    "  final VoidCallback onForfeit;\n  final bool forfeiting;",
    "  final VoidCallback onForfeit;\n  final bool forfeiting;\n  final bool localConnectionInterrupted;\n  final DateTime? localDisconnectDeadline;",
)
replace_once(
    screen,
    "                  final pauseLabel = disconnectedSeat != null &&\n                          disconnectedSeat != snapshot.youSeat\n                      ? context.tr('opponent_connecting')\n                      : context.tr('reconnecting');",
    "                  final connectionInterrupted =\n                      snapshot.status == OnlineDuelStatus.paused ||\n                      localConnectionInterrupted;\n                  final pauseLabel = localConnectionInterrupted\n                      ? context.tr('reconnecting')\n                      : disconnectedSeat != null &&\n                            disconnectedSeat != snapshot.youSeat\n                      ? context.tr('opponent_connecting')\n                      : context.tr('reconnecting');\n                  final reconnectDeadline = localConnectionInterrupted\n                      ? localDisconnectDeadline\n                      : disconnectedPlayer?.disconnectDeadline;",
)
replace_once(
    screen,
    "                          if (snapshot.status == OnlineDuelStatus.paused)\n                            _ReconnectPauseOverlay(\n                              label: pauseLabel,\n                              deadline: disconnectedPlayer?.disconnectDeadline,\n                            ),",
    "                          if (connectionInterrupted)\n                            _ReconnectPauseOverlay(\n                              label: pauseLabel,\n                              deadline: reconnectDeadline,\n                              onLeave: onForfeit,\n                            ),",
)
replace_once(
    screen,
    "class _ReconnectPauseOverlay extends StatefulWidget {\n  const _ReconnectPauseOverlay({required this.label, this.deadline});\n\n  final String label;\n  final DateTime? deadline;",
    "class _ReconnectPauseOverlay extends StatefulWidget {\n  const _ReconnectPauseOverlay({\n    required this.label,\n    required this.onLeave,\n    this.deadline,\n  });\n\n  final String label;\n  final DateTime? deadline;\n  final VoidCallback onLeave;",
)
replace_once(
    screen,
    "                  if (remaining != null) ...[\n                    const SizedBox(height: 5),\n                    Text(\n                      context.tr('turn_timer_seconds', <Object>[remaining]),\n                      style: const TextStyle(\n                        color: Color(0xFFFFC94D),\n                        fontWeight: FontWeight.w900,\n                        fontSize: 18,\n                      ),\n                    ),\n                  ],",
    "                  if (remaining != null) ...[\n                    const SizedBox(height: 5),\n                    Text(\n                      context.tr('turn_timer_seconds', <Object>[remaining]),\n                      style: const TextStyle(\n                        color: Color(0xFFFFC94D),\n                        fontWeight: FontWeight.w900,\n                        fontSize: 18,\n                      ),\n                    ),\n                  ],\n                  const SizedBox(height: 10),\n                  OutlinedButton.icon(\n                    onPressed: widget.onLeave,\n                    icon: const Icon(Icons.flag_rounded, size: 17),\n                    label: Text(context.tr('forfeit_and_leave')),\n                  ),",
)

replace_once(
    screen,
    "    final height = compact ? 76.0 : 88.0;",
    "    final height = compact ? 106.0 : 122.0;",
)

replace_section(
    screen,
    'class _DuelPlayerPlate extends StatelessWidget {',
    'class _AvatarRing extends StatelessWidget {',
    '''class _DuelPlayerPlate extends StatelessWidget {
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
    final avatarRadius = compact ? 18.0 : 24.0;
    final seatKey = seat == OnlineDuelSeat.a ? 'A' : 'B';

    final avatar = KeyedSubtree(
      key: ValueKey<String>('duel-avatar-$seatKey'),
      child: _AvatarRing(
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
      ),
    );

    final identity = Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar,
          SizedBox(height: compact ? 3 : 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  displayName,
                  key: ValueKey<String>('duel-name-$seatKey'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: compact ? 13.5 : 16.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .1,
                  ),
                ),
              ),
              SizedBox(width: compact ? 4 : 6),
              DuelAssetIcon(
                player.connected ? DuelAsset.wifi : DuelAsset.cloud,
                size: compact ? 12 : 14,
                color: player.connected ? accent : scheme.error,
              ),
            ],
          ),
        ],
      ),
    );

    final scoreValue = _ScoreValue(
      key: ValueKey<String>('duel-score-$seatKey'),
      score: score,
      compact: compact,
      color: accent,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 11,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: Colors.transparent,
        boxShadow: active
            ? [BoxShadow(color: accent.withValues(alpha: .18), blurRadius: 14)]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: alignEnd
            ? [
                scoreValue,
                SizedBox(width: compact ? 8 : 13),
                identity,
              ]
            : [
                identity,
                SizedBox(width: compact ? 8 : 13),
                scoreValue,
              ],
      ),
    );
  }
}

''',
)
replace_section(
    screen,
    'class _ScoreValue extends StatelessWidget {',
    'class _ReadyPanel extends StatelessWidget {',
    '''class _ScoreValue extends StatelessWidget {
  const _ScoreValue({
    super.key,
    required this.score,
    required this.compact,
    required this.color,
  });

  final int score;
  final bool compact;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 1 : 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuelAssetIcon(
            DuelAsset.trophy,
            size: compact ? 17 : 21,
            color: const Color(0xFFFFC94D),
          ),
          SizedBox(width: compact ? 4 : 5),
          Text(
            '$score',
            style: TextStyle(
              color: color,
              fontSize: compact ? 20 : 25,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

''',
)

legacy = 'lib/features/social/challenge_invitation_screen.dart'
replace_once(
    legacy,
    "import '../duel/online_duel_screen.dart';",
    "import '../duel/pre_match_ready_screen.dart';",
)
replace_once(
    legacy,
    "        MaterialPageRoute(builder: (_) => OnlineDuelScreen(roomId: roomId)),",
    "        MaterialPageRoute(builder: (_) => PreMatchReadyScreen(roomId: roomId)),",
)

ux = 'lib/features/social/ux_challenge_invitation_screen.dart'
replace_once(
    ux,
    "  bool _busy = false;\n  bool _showingError = false;",
    "  bool _busy = false;\n  bool _openingRoom = false;\n  bool _showingError = false;",
)
replace_once(
    ux,
    "  Future<void> _refreshStatus() async {\n    if (_busy || !mounted) return;",
    "  Future<void> _refreshStatus() async {\n    if (_busy || _openingRoom || !mounted) return;",
)
replace_once(
    ux,
    "    if (challenge == null || _busy || _expired) return;",
    "    if (challenge == null || _busy || _openingRoom || _expired) return;",
)
replace_once(
    ux,
    "  Future<void> _openRoom(String roomId) async {\n    _timer?.cancel();\n    await _economy.refresh(showLoading: false);\n    if (!mounted) return;\n    await Navigator.of(context).pushReplacement<void, void>(\n      MaterialPageRoute(builder: (_) => PreMatchReadyScreen(roomId: roomId)),\n    );\n  }",
    "  Future<void> _openRoom(String roomId) async {\n    if (_openingRoom || !mounted) return;\n    _openingRoom = true;\n    _timer?.cancel();\n    try {\n      await _economy.refresh(showLoading: false);\n      if (!mounted) return;\n      await Navigator.of(context).pushReplacement<void, void>(\n        MaterialPageRoute(builder: (_) => PreMatchReadyScreen(roomId: roomId)),\n      );\n    } catch (_) {\n      if (mounted) setState(() => _openingRoom = false);\n      rethrow;\n    }\n  }",
)

waiting = 'lib/features/social/challenge_waiting_screen.dart'
replace_once(
    waiting,
    "  void _handlePushRoom() {\n    final roomId = _push.openedRoomId.value;\n    if (roomId == null || roomId.isEmpty) return;\n    _push.openedRoomId.value = null;\n    unawaited(_checkStatus());\n  }",
    "  void _handlePushRoom() {\n    final roomId = _push.openedRoomId.value?.trim();\n    if (roomId == null || roomId.isEmpty) return;\n    _push.openedRoomId.value = null;\n    unawaited(_openRoom(roomId));\n  }",
)

ready = 'lib/features/duel/pre_match_ready_screen.dart'
replace_section(
    ready,
    '  Future<void> _cancelAndLeave() async {',
    '  void _ready() {',
    '''  Future<void> _cancelAndLeave() async {
    if (_leaving || _handedOff || !mounted) return;
    setState(() => _leaving = true);
    final controller = _controller;
    controller?.forfeit();
    if (controller != null &&
        (_connectionState == OnlineDuelConnectionState.connected ||
            _connectionState == OnlineDuelConnectionState.resyncing)) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }
    await _snapshotSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await controller?.dispose();
    _controller = null;
    _snapshotSubscription = null;
    _connectionSubscription = null;
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.of(context).pop();
  }

''',
)

contract = Path('test/online_duel_lifecycle_hotfix_test.dart')
contract.write_text(
    """import 'dart:io';\n\nimport 'package:flutter_test/flutter_test.dart';\n\nvoid main() {\n  test('online duel has a local 30 second disconnect escape hatch', () {\n    final source = File('lib/features/duel/online_duel_screen.dart').readAsStringSync();\n    expect(source, contains('Duration(seconds: 30)'));\n    expect(source, contains('_disconnectEscapeTimer'));\n    expect(source, contains('Navigator.of(context).popUntil((route) => route.isFirst)'));\n    expect(source, contains('snapshot.status == OnlineDuelStatus.paused'));\n    expect(source, contains('_localConnectionInterrupted'));\n  });\n\n  test('forfeit leaves immediately instead of waiting for a server snapshot', () {\n    final source = File('lib/features/duel/online_duel_screen.dart').readAsStringSync();\n    expect(source, contains('await _returnToMainMenu(sendForfeit: true)'));\n    expect(source, isNot(contains('Timer(const Duration(seconds: 8)')));\n  });\n\n  test('arena identity and score layout uses inward large score placement', () {\n    final source = File('lib/features/duel/online_duel_screen.dart').readAsStringSync();\n    expect(source, contains('fontSize: compact ? 20 : 25'));\n    expect(source, contains("key: ValueKey<String>('duel-name-\\$seatKey')"));\n    expect(source, contains('children: alignEnd'));\n    expect(source, contains('scoreValue'));\n    expect(source, contains('identity'));\n  });\n\n  test('all challenge acceptance paths converge on pre-match ready', () {\n    final legacy = File('lib/features/social/challenge_invitation_screen.dart').readAsStringSync();\n    final modern = File('lib/features/social/ux_challenge_invitation_screen.dart').readAsStringSync();\n    final waiting = File('lib/features/social/challenge_waiting_screen.dart').readAsStringSync();\n    expect(legacy, contains('PreMatchReadyScreen(roomId: roomId)'));\n    expect(legacy, isNot(contains('OnlineDuelScreen(roomId: roomId)')));\n    expect(modern, contains('bool _openingRoom = false'));\n    expect(waiting, contains('unawaited(_openRoom(roomId))'));\n  });\n}\n""",
    encoding='utf-8',
)
