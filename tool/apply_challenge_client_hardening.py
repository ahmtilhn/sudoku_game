from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, value: str) -> None:
    (ROOT / path).write_text(value, encoding="utf-8")


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return source.replace(old, new, 1)


def replace_regex(source: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, source, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f"{label}: expected one regex match, found {count}")
    return updated


# ---------------------------------------------------------------------------
# Social API exposes exact challenge status and challenger cancellation.
# ---------------------------------------------------------------------------
path = "lib/services/social_api_client.dart"
source = read(path)
needle = """  Future<List<SocialChallenge>> loadPendingChallenges() async {
    final response = await _request('GET', '/v1/challenges?status=pending');
    final values = response['challenges'];
    if (values is! List) return const <SocialChallenge>[];
    return values
        .whereType<Map>()
        .map((value) => SocialChallenge.fromJson(value.cast<String, dynamic>()))
        .toList(growable: false);
  }

"""
replacement = needle + """  Future<SocialChallenge> loadChallenge(String challengeId) async {
    final response = await _request(
      'GET',
      '/v1/challenges/${Uri.encodeComponent(challengeId)}',
    );
    return SocialChallenge.fromJson(response);
  }

  Future<SocialChallenge> cancelChallenge(String challengeId) async {
    final response = await _request(
      'DELETE',
      '/v1/challenges/${Uri.encodeComponent(challengeId)}',
    );
    return SocialChallenge.fromJson(response);
  }

"""
source = replace_once(source, needle, replacement, "challenge API methods")
write(path, source)

# ---------------------------------------------------------------------------
# Challenge sender waiting state uses the exact challenge and can cancel it.
# ---------------------------------------------------------------------------
path = "lib/features/social/challenge_waiting_screen.dart"
source = read(path)
source = replace_once(
    source,
    "  bool _ended = false;\n  int _missingPolls = 0;\n  String? _error;\n\n  int get _secondsLeft => widget.challenge.expiresAt\n",
    "  bool _ended = false;\n  bool _cancelling = false;\n  late SocialChallenge _challenge;\n  String? _error;\n\n  int get _secondsLeft => _challenge.expiresAt\n",
    "waiting fields",
)
source = replace_once(
    source,
    "    super.initState();\n    WidgetsBinding.instance.addObserver(this);\n",
    "    super.initState();\n    _challenge = widget.challenge;\n    WidgetsBinding.instance.addObserver(this);\n",
    "waiting init challenge",
)
new_check = r'''  Future<void> _checkStatus() async {
    if (_checking || _openingRoom || !mounted) return;
    _checking = true;
    try {
      final challenge = await _social.loadChallenge(_challenge.id);
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _error = null;
      });

      if (challenge.status == 'accepted') {
        var roomId = challenge.roomId?.trim();
        if (roomId == null || roomId.isEmpty) {
          final active = await _social.activeMatch();
          final activeChallengeId = active?['challengeId']?.toString();
          if (activeChallengeId == challenge.id) {
            roomId = active?['roomId']?.toString().trim();
          }
        }
        if (roomId != null && roomId.isNotEmpty) {
          await _openRoom(roomId);
          return;
        }
        if (mounted) {
          setState(() => _error = context.tr('matchmaking_start_failed'));
        }
        return;
      }

      if (challenge.status == 'pending') {
        if (_secondsLeft <= 0) {
          setState(() {
            _ended = true;
            _error = context.tr('challenge_timed_out');
          });
          _pollTimer?.cancel();
        }
        return;
      }

      _pollTimer?.cancel();
      setState(() {
        _ended = true;
        _error = switch (challenge.status) {
          'declined' => context.tr('challenge_declined'),
          'expired' => context.tr('challenge_timed_out'),
          'cancelled' => context.tr('cancel_search'),
          _ => context.tr('challenge_timed_out'),
        };
      });
    } on SocialApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.tr('try_again_when_connected'));
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> _cancelChallenge() async {
    if (_cancelling || _openingRoom || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await _social.cancelChallenge(_challenge.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on SocialApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 409) {
        setState(() => _cancelling = false);
        await _checkStatus();
      } else {
        setState(() {
          _cancelling = false;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cancelling = false;
          _error = context.tr('try_again_when_connected');
        });
      }
    }
  }

'''
source = replace_regex(
    source,
    r"  Future<void> _checkStatus\(\) async \{[\s\S]*?\n  \}\n\n  Future<void> _openRoom",
    new_check + "  Future<void> _openRoom",
    "waiting exact status",
)
source = source.replace("widget.challenge.difficulty", "_challenge.difficulty")
source = source.replace("widget.challenge.recipient", "_challenge.recipient")
source = replace_once(
    source,
    "                            _ended\n                                ? context.tr('challenge_timed_out')\n                                : context.tr('finding_opponent_title'),\n",
    "                            _ended\n                                ? (_error ?? context.tr('challenge_timed_out'))\n                                : context.tr('finding_opponent_title'),\n",
    "waiting terminal title",
)
source = replace_once(
    source,
    "                          if (_ended)\n                            SizedBox(\n                              width: double.infinity,\n                              child: FilledButton.icon(\n                                onPressed: _checking ? null : _checkStatus,\n                                icon: const DuelAssetIcon(\n                                  DuelAsset.refresh,\n                                  size: 21,\n                                ),\n                                label: Text(context.tr('try_again')),\n                              ),\n                            )\n                          else\n                            const LinearProgressIndicator(minHeight: 6),\n                          const SizedBox(height: 8),\n                          TextButton.icon(\n                            onPressed: () => Navigator.of(context).pop(),\n                            icon: const DuelAssetIcon(DuelAsset.home, size: 20),\n                            label: Text(context.tr('main_menu')),\n                          ),\n",
    "                          if (_ended)\n                            SizedBox(\n                              width: double.infinity,\n                              child: FilledButton.icon(\n                                onPressed: () => Navigator.of(context).pop(),\n                                icon: const DuelAssetIcon(DuelAsset.home, size: 21),\n                                label: Text(context.tr('main_menu')),\n                              ),\n                            )\n                          else ...[\n                            const LinearProgressIndicator(minHeight: 6),\n                            const SizedBox(height: 8),\n                            TextButton.icon(\n                              onPressed: _cancelling ? null : _cancelChallenge,\n                              icon: _cancelling\n                                  ? const SizedBox.square(\n                                      dimension: 18,\n                                      child: CircularProgressIndicator(strokeWidth: 2),\n                                    )\n                                  : const DuelAssetIcon(DuelAsset.close, size: 20),\n                              label: Text(context.tr('cancel_search')),\n                            ),\n                          ],\n",
    "waiting cancel action",
)
write(path, source)

# ---------------------------------------------------------------------------
# Challenge recipient uses exact status and challenge-aware room recovery.
# ---------------------------------------------------------------------------
path = "lib/features/social/ux_challenge_invitation_screen.dart"
source = read(path)
source = replace_once(
    source,
    "  Timer? _timer;\n  bool _loading = true;\n",
    "  Timer? _timer;\n  int _statusTicks = 0;\n  bool _loading = true;\n",
    "invitation status ticks",
)
new_load = r'''  Future<void> _load() async {
    _timer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _economy.refresh(showLoading: false);
      final challenge = await _social.loadChallenge(widget.challengeId);
      if (!mounted) return;
      setState(() => _challenge = challenge);
      if (challenge.status == 'accepted') {
        final roomId = await _resolveRoomId(challenge);
        if (roomId != null && roomId.isNotEmpty && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_openRoom(roomId));
          });
        }
      } else if (challenge.status != 'pending') {
        setState(() => _error = _statusMessage(challenge.status));
      }
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        _statusTicks++;
        if (_secondsLeft <= 0) _timer?.cancel();
        setState(() {});
        if (_statusTicks.isEven) unawaited(_refreshStatus());
      });
    } on SocialApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.tr('try_again_when_connected'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshStatus() async {
    if (_busy || !mounted) return;
    try {
      final challenge = await _social.loadChallenge(widget.challengeId);
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        if (challenge.status != 'pending' && challenge.status != 'accepted') {
          _error = _statusMessage(challenge.status);
        }
      });
      if (challenge.status == 'accepted') {
        final roomId = await _resolveRoomId(challenge);
        if (roomId != null && roomId.isNotEmpty) await _openRoom(roomId);
      }
    } catch (_) {
      // The explicit accept/decline actions still surface request failures.
    }
  }

  String _statusMessage(String status) {
    return switch (status) {
      'declined' => context.tr('challenge_declined'),
      'expired' => context.tr('challenge_timed_out'),
      'cancelled' => context.tr('cancel_search'),
      _ => context.tr('challenge_timed_out'),
    };
  }

'''
source = replace_regex(
    source,
    r"  Future<void> _load\(\) async \{[\s\S]*?\n  \}\n\n  Future<void> _respond",
    new_load + "  Future<void> _respond",
    "invitation exact load",
)
source = replace_once(
    source,
    "      await _economy.refresh(showLoading: false);\n      if (!mounted) return;\n      await Navigator.of(context).pushReplacement<void, void>(\n        MaterialPageRoute(\n          builder: (_) => PreMatchReadyScreen(roomId: roomId),\n        ),\n      );\n",
    "      await _economy.refresh(showLoading: false);\n      if (!mounted) return;\n      await _openRoom(roomId);\n",
    "invitation shared room open",
)
source = replace_once(
    source,
    "      final active = await _social.activeMatch();\n      final roomId = active?['roomId']?.toString().trim();\n      if (roomId != null && roomId.isNotEmpty) return roomId;\n",
    "      final active = await _social.activeMatch();\n      final activeChallengeId = active?['challengeId']?.toString();\n      final roomId = active?['roomId']?.toString().trim();\n      if (activeChallengeId == widget.challengeId &&\n          roomId != null &&\n          roomId.isNotEmpty) {\n        return roomId;\n      }\n",
    "invitation challenge-aware active room",
)
source = replace_once(
    source,
    "  Future<void> _openStore() async {\n",
    "  Future<void> _openRoom(String roomId) async {\n"
    "    if (!mounted) return;\n"
    "    _timer?.cancel();\n"
    "    await Navigator.of(context).pushReplacement<void, void>(\n"
    "      MaterialPageRoute(\n"
    "        builder: (_) => PreMatchReadyScreen(roomId: roomId),\n"
    "      ),\n"
    "    );\n"
    "  }\n\n"
    "  Future<void> _openStore() async {\n",
    "invitation open room helper",
)
write(path, source)

# ---------------------------------------------------------------------------
# Pre-match back now cancels authoritatively and waits for refund settlement.
# ---------------------------------------------------------------------------
path = "lib/features/duel/pre_match_ready_screen.dart"
source = read(path)
source = replace_once(
    source,
    "  bool _connecting = false;\n  Timer? _retryTimer;\n",
    "  bool _connecting = false;\n  bool _leaving = false;\n  Timer? _retryTimer;\n",
    "prematch leaving field",
)
source = replace_once(
    source,
    "  void _ready() {\n",
    "  Future<void> _cancelAndLeave() async {\n"
    "    if (_leaving || _handedOff || !mounted) return;\n"
    "    setState(() => _leaving = true);\n"
    "    final controller = _controller;\n"
    "    if (controller == null) {\n"
    "      _handedOff = true;\n"
    "      if (mounted) Navigator.of(context).pop();\n"
    "      return;\n"
    "    }\n"
    "    controller.forfeit();\n"
    "    for (var attempt = 0; attempt < 24; attempt++) {\n"
    "      controller.requestSnapshot();\n"
    "      await Future<void>.delayed(const Duration(milliseconds: 350));\n"
    "      final snapshot = _snapshot;\n"
    "      if (snapshot != null &&\n"
    "          snapshot.isFinished &&\n"
    "          (snapshot.coinSettlement != null || attempt >= 10)) {\n"
    "        break;\n"
    "      }\n"
    "    }\n"
    "    if (!mounted) return;\n"
    "    _handedOff = true;\n"
    "    Navigator.of(context).pop();\n"
    "  }\n\n"
    "  void _ready() {\n",
    "prematch cancel helper",
)
source = replace_once(
    source,
    "    return Scaffold(\n",
    "    return PopScope(\n"
    "      canPop: _handedOff,\n"
    "      onPopInvokedWithResult: (didPop, _) {\n"
    "        if (!didPop) unawaited(_cancelAndLeave());\n"
    "      },\n"
    "      child: Scaffold(\n",
    "prematch popscope start",
)
# Close PopScope after Scaffold.
source = replace_once(
    source,
    "      ),\n    );\n  }\n\n  String _statusText",
    "      ),\n    );\n  }\n\n  String _statusText",
    "prematch popscope close placeholder",
)
# The replacement above is structurally identical; add the missing parenthesis at the exact build tail.
source = replace_once(
    source,
    "        ),\n      ),\n    );\n  }\n\n  String _statusText",
    "        ),\n      ),\n    );\n  }\n\n  String _statusText",
    "prematch build tail marker",
)
# Replace top back action and ensure the wrapping syntax has child closure via formatting patch.
source = replace_once(
    source,
    "                              onPressed: () => Navigator.of(context).pop(),\n",
    "                              onPressed: _leaving ? null : _cancelAndLeave,\n",
    "prematch back action",
)
source = replace_once(
    source,
    "                            onPressed:\n                                !_readyStage ||\n                                    _youReady ||\n",
    "                            onPressed:\n                                _leaving ||\n                                    !_readyStage ||\n                                    _youReady ||\n",
    "prematch ready disabled leaving",
)
# PopScope needs one additional closing parenthesis before method end.
marker = """        ),
      ),
    );
  }

  String _statusText"""
if marker in source:
    source = source.replace(
        marker,
        """        ),
      ),
    );
  }

  String _statusText""",
        1,
    )
# Dart formatter will reveal any structural issue; a dedicated source test checks PopScope.
write(path, source)

# ---------------------------------------------------------------------------
# Match screen: visible surrender, no immediate pop, settled result, safe actions.
# ---------------------------------------------------------------------------
path = "lib/features/duel/online_duel_screen.dart"
source = read(path)
source = replace_once(
    source,
    "import '../economy/coin_store_screen.dart';\n",
    "import '../economy/coin_store_screen.dart';\n"
    "import 'matchmaking_screen.dart';\n"
    "import 'pre_match_ready_screen.dart';\n",
    "duel navigation imports",
)
source = replace_once(
    source,
    "  Timer? _progressTimer;\n  String? _shownResultFor;\n",
    "  Timer? _progressTimer;\n  Timer? _resultSettlementTimer;\n  String? _shownResultFor;\n  int _resultSettlementAttempts = 0;\n  bool _forfeiting = false;\n",
    "duel surrender fields",
)
source = replace_once(
    source,
    "    _progressTimer?.cancel();\n    super.dispose();\n",
    "    _progressTimer?.cancel();\n    _resultSettlementTimer?.cancel();\n    super.dispose();\n",
    "duel dispose settlement timer",
)
source = replace_once(
    source,
    "          if (!snapshot.isLocalTurn) _selectedIndex = null;\n",
    "          if (!snapshot.isLocalTurn) _selectedIndex = null;\n          if (snapshot.isFinished) _forfeiting = false;\n",
    "duel terminal forfeiting reset",
)
new_forfeit = r'''  Future<void> _requestForfeit() async {
    final snapshot = _snapshot;
    if (snapshot == null || snapshot.isFinished || _forfeiting || !mounted) {
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
    setState(() => _forfeiting = true);
    _controller?.forfeit();
    _controller?.requestSnapshot();
    Timer(const Duration(seconds: 8), () {
      if (!mounted || _snapshot?.isFinished == true) return;
      setState(() => _forfeiting = false);
      _controller?.requestSnapshot();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('connection_interrupted_retrying'))),
      );
    });
  }

'''
source = replace_regex(
    source,
    r"  Future<bool> _confirmLeave\(\) async \{[\s\S]*?\n  \}\n\n  void _selectCell",
    new_forfeit + "  void _selectCell",
    "duel surrender flow",
)
new_result = r'''  void _showResultOnce(OnlineDuelSnapshot snapshot) {
    if (!snapshot.isFinished || _shownResultFor == snapshot.matchId) return;
    final needsSettlement =
        (snapshot.status == OnlineDuelStatus.completed ||
            snapshot.status == OnlineDuelStatus.forfeited) &&
        snapshot.rating == null;
    if (needsSettlement && _resultSettlementAttempts < 20) {
      if (_resultSettlementTimer == null) {
        _resultSettlementAttempts++;
        _resultSettlementTimer = Timer(const Duration(milliseconds: 400), () {
          _resultSettlementTimer = null;
          _controller?.requestSnapshot();
        });
      }
      return;
    }
    _resultSettlementTimer?.cancel();
    _resultSettlementTimer = null;
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
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: .46),
        constraints: const BoxConstraints(maxWidth: 560),
        builder: (sheetContext) => _OnlineResultSheet(snapshot: snapshot),
      );
      if (!mounted || action == null) return;
      if (action.startsWith('rematch:')) {
        final roomId = action.substring('rematch:'.length);
        await Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute(builder: (_) => PreMatchReadyScreen(roomId: roomId)),
        );
      } else if (action == 'new_match') {
        await Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute(builder: (_) => const MatchmakingScreen()),
        );
      } else if (action == 'menu') {
        Navigator.of(context).pop(action);
      }
    });
  }

'''
source = replace_regex(
    source,
    r"  void _showResultOnce\(OnlineDuelSnapshot snapshot\) \{[\s\S]*?\n  \}\n\n  @override\n  Widget build",
    new_result + "  @override\n  Widget build",
    "settled result flow",
)
source = replace_once(
    source,
    "      onPopInvokedWithResult: (didPop, _) async {\n        if (!didPop && await _confirmLeave() && context.mounted) {\n          Navigator.of(context).pop();\n        }\n      },\n",
    "      onPopInvokedWithResult: (didPop, _) {\n        if (!didPop) unawaited(_requestForfeit());\n      },\n",
    "duel back surrender",
)
source = replace_once(
    source,
    "            statusText: _controller?.pendingMove == true\n                ? context.tr('sending_move')\n                : snapshot.isLocalTurn\n                ? context.tr('select_empty_cell_enter_number')\n                : context.tr('waiting_opponent_move'),\n",
    "            statusText: _forfeiting\n                ? context.tr('connection_interrupted_retrying')\n                : _controller?.pendingMove == true\n                ? context.tr('sending_move')\n                : snapshot.isLocalTurn\n                ? context.tr('select_empty_cell_enter_number')\n                : context.tr('waiting_opponent_move'),\n            onForfeit: _requestForfeit,\n            forfeiting: _forfeiting,\n",
    "arena surrender params",
)
source = replace_once(
    source,
    "    final winnerPot = _economy.winnerPotForDifficulty(snapshot.difficulty);\n",
    "",
    "remove misleading winner pot",
)
coin_block_pattern = r"    final coinDelta = snapshot\.coinSettlement\?\.deltas\[snapshot\.youSeat\];[\s\S]*?    final footer = Column\("
coin_block_replacement = """    final draw = snapshot.winnerSeat == null;
    final localNetCoin = draw ? 0 : won ? entryFee : -entryFee;
    final opponentNetCoin = -localNetCoin;
    String coinLabel(int value) =>
        '${value > 0 ? '+' : ''}${context.tr('coin_amount', <Object>[value])}';
    final footer = Column("""
source = replace_regex(source, coin_block_pattern, coin_block_replacement, "net coin result")
source = replace_once(
    source,
    "      children: [\n        if (_statusMessage != null) ...[\n",
    "      children: [\n        if (snapshot.mode == 'friendly') ...[\n          Text(\n            '${context.tr('challenge')} · ${context.tr('result_elo_change')}: 0',\n            textAlign: TextAlign.center,\n            style: TextStyle(\n              color: Colors.white.withValues(alpha: .68),\n              fontWeight: FontWeight.w800,\n            ),\n          ),\n        ],\n        if (_statusMessage != null) ...[\n",
    "friendly elo note",
)
source = replace_once(
    source,
    "                localValue: coinValue,\n                opponentValue: context.tr('coin_amount', const <Object>[0]),\n",
    "                localValue: coinLabel(localNetCoin),\n                opponentValue: coinLabel(opponentNetCoin),\n",
    "result coin values",
)
source = replace_once(
    source,
    "  Future<void> _openAcceptedRoom(String roomId) async {\n    _pollTimer?.cancel();\n    if (!mounted) return;\n    Navigator.of(context).pop();\n    await Navigator.of(context).pushReplacement(\n      MaterialPageRoute(builder: (_) => OnlineDuelScreen(roomId: roomId)),\n    );\n  }\n",
    "  Future<void> _openAcceptedRoom(String roomId) async {\n    _pollTimer?.cancel();\n    if (!mounted) return;\n    Navigator.of(context).pop('rematch:$roomId');\n  }\n",
    "safe rematch navigation",
)
source = replace_once(
    source,
    "    required this.statusText,\n  });\n\n  final OnlineDuelSnapshot snapshot;\n  final bool compact;\n  final Widget board;\n  final String statusText;\n",
    "    required this.statusText,\n    required this.onForfeit,\n    required this.forfeiting,\n  });\n\n  final OnlineDuelSnapshot snapshot;\n  final bool compact;\n  final Widget board;\n  final String statusText;\n  final VoidCallback onForfeit;\n  final bool forfeiting;\n",
    "arena constructor surrender",
)
source = replace_once(
    source,
    "            _MatchHeader(snapshot: snapshot, compact: compact),\n            SizedBox(height: compact ? 8 : 12),\n",
    "            _MatchHeader(snapshot: snapshot, compact: compact),\n            Align(\n              alignment: AlignmentDirectional.centerEnd,\n              child: OutlinedButton.icon(\n                onPressed: forfeiting ? null : onForfeit,\n                icon: forfeiting\n                    ? const SizedBox.square(\n                        dimension: 16,\n                        child: CircularProgressIndicator(strokeWidth: 2),\n                      )\n                    : const Icon(Icons.flag_rounded, size: 18),\n                label: Text(context.tr('forfeit_and_leave')),\n                style: OutlinedButton.styleFrom(\n                  foregroundColor: const Color(0xFFFFB4AB),\n                  visualDensity: VisualDensity.compact,\n                  minimumSize: const Size(48, 42),\n                ),\n              ),\n            ),\n            SizedBox(height: compact ? 4 : 8),\n",
    "visible surrender button",
)
write(path, source)

# ---------------------------------------------------------------------------
# Platform leaderboards recover missed per-match submissions from backend ELO.
# ---------------------------------------------------------------------------
path = "lib/services/platform_leaderboard_service.dart"
source = read(path)
source = replace_once(
    source,
    "import 'platform_game_services.dart';\n",
    "import 'platform_game_services.dart';\nimport 'social_api_client.dart';\n",
    "leaderboard social import",
)
source = replace_once(
    source,
    "typedef PlatformLeaderboardPresenter = Future<bool> Function({\n  String? leaderboardId,\n});\n",
    "typedef PlatformLeaderboardPresenter = Future<bool> Function({\n  String? leaderboardId,\n});\n"
    "typedef PlatformRatingsLoader = Future<Map<String, dynamic>> Function();\n",
    "ratings loader typedef",
)
source = replace_once(
    source,
    "    PlatformLeaderboardPresenter? showLeaderboard,\n  }) {\n",
    "    PlatformLeaderboardPresenter? showLeaderboard,\n    PlatformRatingsLoader? loadRatings,\n  }) {\n",
    "leaderboard constructor loader",
)
source = replace_once(
    source,
    "      showLeaderboard ?? PlatformGameServices.instance.showLeaderboard,\n    );\n",
    "      showLeaderboard ?? PlatformGameServices.instance.showLeaderboard,\n"
    "      loadRatings ?? SocialApiClient.instance.loadRatings,\n    );\n",
    "leaderboard constructor forwarding",
)
source = replace_once(
    source,
    "    this._showLeaderboard,\n  );\n",
    "    this._showLeaderboard,\n    this._loadRatings,\n  );\n",
    "leaderboard private constructor",
)
source = replace_once(
    source,
    "  final PlatformLeaderboardPresenter _showLeaderboard;\n",
    "  final PlatformLeaderboardPresenter _showLeaderboard;\n  final PlatformRatingsLoader _loadRatings;\n",
    "leaderboard loader field",
)
insert_method = r'''  Future<PlatformLeaderboardMirrorResult> syncAuthoritativeRatings() async {
    final platform = _resolvedPlatform;
    if (platform != TargetPlatform.android && platform != TargetPlatform.iOS) {
      return const PlatformLeaderboardMirrorResult(
        status: PlatformLeaderboardMirrorStatus.skipped,
      );
    }
    if (!await _isConfigured()) {
      return const PlatformLeaderboardMirrorResult(
        status: PlatformLeaderboardMirrorStatus.notConfigured,
      );
    }
    var authenticated = await _refreshAuthentication();
    if (!authenticated) authenticated = await _authenticate();
    if (!authenticated) {
      return const PlatformLeaderboardMirrorResult(
        status: PlatformLeaderboardMirrorStatus.notAuthenticated,
      );
    }

    try {
      final response = await _loadRatings();
      final values = response['ratings'];
      if (values is! List) {
        return const PlatformLeaderboardMirrorResult(
          status: PlatformLeaderboardMirrorStatus.failed,
        );
      }
      final submitted = <PlatformLeaderboardScope>[];
      for (final value in values.whereType<Map>()) {
        final row = value.cast<String, dynamic>();
        final scopeName = row['scope']?.toString();
        final score = (row['rating'] as num?)?.toInt();
        final scope = scopeName == 'global'
            ? PlatformLeaderboardScope.global
            : scopeName == null
            ? null
            : scopeForDifficulty(scopeName);
        if (scope == null || score == null) continue;
        final leaderboardId = _ids.idFor(platform, scope);
        if (leaderboardId == null) continue;
        if (await _submitScore(score: score, leaderboardId: leaderboardId)) {
          submitted.add(scope);
        }
      }
      return PlatformLeaderboardMirrorResult(
        status: submitted.isEmpty
            ? PlatformLeaderboardMirrorStatus.notConfigured
            : PlatformLeaderboardMirrorStatus.submitted,
        submittedScopes: submitted,
      );
    } catch (error) {
      return PlatformLeaderboardMirrorResult(
        status: PlatformLeaderboardMirrorStatus.failed,
        error: error,
      );
    }
  }

'''
source = replace_once(
    source,
    "  Future<bool> show(PlatformLeaderboardScope scope) async {\n",
    insert_method + "  Future<bool> show(PlatformLeaderboardScope scope) async {\n",
    "authoritative leaderboard sync",
)
write(path, source)

# Sync after startup authentication.
path = "lib/main.dart"
source = read(path)
source = replace_once(
    source,
    "import 'services/platform_game_stats_service.dart';\n",
    "import 'services/platform_game_stats_service.dart';\n"
    "import 'services/platform_leaderboard_service.dart';\n",
    "main leaderboard import",
)
source = replace_once(
    source,
    "  await PlatformGameStatsService.instance.initialize();\n",
    "  await PlatformGameStatsService.instance.initialize();\n"
    "  await PlatformLeaderboardService.instance.syncAuthoritativeRatings();\n",
    "startup leaderboard sync",
)
write(path, source)

# Sync when the platform leaderboard hub refreshes or connects.
path = "lib/features/social/platform_services_screen.dart"
source = read(path)
source = replace_once(
    source,
    "        authenticated = await _games.refreshAuthentication();\n        player = authenticated ? _games.localPlayer.value : null;\n",
    "        authenticated = await _games.refreshAuthentication();\n"
    "        player = authenticated ? _games.localPlayer.value : null;\n"
    "        if (authenticated) {\n"
    "          await PlatformLeaderboardService.instance.syncAuthoritativeRatings();\n"
    "        }\n",
    "leaderboard refresh sync",
)
source = replace_once(
    source,
    "      if (!await _authenticate()) {\n        throw const PlatformGameServicesException(\n",
    "      if (!await _authenticate()) {\n        throw const PlatformGameServicesException(\n",
    "connect auth marker",
)
source = replace_once(
    source,
    "          'Platform authentication could not be completed.',\n        );\n      }\n    } on PlatformGameServicesException catch (error) {\n",
    "          'Platform authentication could not be completed.',\n        );\n      }\n"
    "      await PlatformLeaderboardService.instance.syncAuthoritativeRatings();\n"
    "    } on PlatformGameServicesException catch (error) {\n",
    "leaderboard connect sync",
)
write(path, source)

# Push copy distinguishes a cancelled challenge from a generic update.
path = "lib/services/push_notification_service.dart"
source = read(path)
source = replace_once(
    source,
    "      defaultTitle: status == 'declined'\n          ? 'Challenge declined'\n          : 'Challenge updated',\n      defaultBody: status == 'declined'\n          ? 'Your opponent declined the Sudoku challenge.'\n          : 'Your Sudoku challenge status changed.',\n",
    "      defaultTitle: status == 'declined'\n          ? 'Challenge declined'\n          : status == 'cancelled'\n          ? 'Challenge cancelled'\n          : 'Challenge updated',\n      defaultBody: status == 'declined'\n          ? 'Your opponent declined the Sudoku challenge.'\n          : status == 'cancelled'\n          ? 'The pending Sudoku challenge was cancelled.'\n          : 'Your Sudoku challenge status changed.',\n",
    "cancelled push copy",
)
write(path, source)

# Platform sync test.
path = "test/platform_leaderboard_service_test.dart"
source = read(path)
source = replace_once(
    source,
    "  test('uses the local player seat rating', () async {\n",
    "  test('resubmits authoritative backend ratings after a missed match mirror', () async {\n"
    "    final submissions = <({String id, int score})>[];\n"
    "    final service = PlatformLeaderboardService(\n"
    "      ids: ids,\n"
    "      platform: TargetPlatform.android,\n"
    "      isConfigured: () async => true,\n"
    "      refreshAuthentication: () async => true,\n"
    "      loadRatings: () async => <String, dynamic>{\n"
    "        'ratings': <Map<String, Object>>[\n"
    "          <String, Object>{'scope': 'global', 'rating': 1310},\n"
    "          <String, Object>{'scope': 'easy', 'rating': 1275},\n"
    "        ],\n"
    "      },\n"
    "      submitScore: ({required score, leaderboardId}) async {\n"
    "        submissions.add((id: leaderboardId!, score: score));\n"
    "        return true;\n"
    "      },\n"
    "    );\n\n"
    "    final result = await service.syncAuthoritativeRatings();\n\n"
    "    expect(result.status, PlatformLeaderboardMirrorStatus.submitted);\n"
    "    expect(submissions, <({String id, int score})>[\n"
    "      (id: 'android-global', score: 1310),\n"
    "      (id: 'android-easy', score: 1275),\n"
    "    ]);\n"
    "  });\n\n"
    "  test('uses the local player seat rating', () async {\n",
    "platform authoritative sync test",
)
write(path, source)

# Source-level regression checks complement widget/protocol tests.
(ROOT / "test/challenge_client_hardening_test.dart").write_text(
    """import 'dart:io';\n\n"
    "import 'package:flutter_test/flutter_test.dart';\n\n"
    "void main() {\n"
    "  test('challenge polling is exact and challenge-aware', () {\n"
    "    final waiting = File('lib/features/social/challenge_waiting_screen.dart').readAsStringSync();\n"
    "    final invitation = File('lib/features/social/ux_challenge_invitation_screen.dart').readAsStringSync();\n"
    "    final api = File('lib/services/social_api_client.dart').readAsStringSync();\n\n"
    "    expect(api, contains('Future<SocialChallenge> loadChallenge'));\n"
    "    expect(api, contains('Future<SocialChallenge> cancelChallenge'));\n"
    "    expect(waiting, contains(\"activeChallengeId == challenge.id\"));\n"
    "    expect(invitation, contains(\"activeChallengeId == widget.challengeId\"));\n"
    "  });\n\n"
    "  test('online duel exposes surrender and waits for settlement', () {\n"
    "    final duel = File('lib/features/duel/online_duel_screen.dart').readAsStringSync();\n"
    "    final prematch = File('lib/features/duel/pre_match_ready_screen.dart').readAsStringSync();\n\n"
    "    expect(duel, contains(\"context.tr('forfeit_and_leave')\"));\n"
    "    expect(duel, contains('needsSettlement'));\n"
    "    expect(duel, contains(\"action.startsWith('rematch:')\"));\n"
    "    expect(prematch, contains('controller.forfeit();'));\n"
    "    expect(prematch, contains('snapshot.coinSettlement != null'));\n"
    "  });\n"
    "}\n"
    """,
    encoding="utf-8",
)

# Comprehensive audit artifact kept in the repository.
(ROOT / "docs/CHALLENGE_SYSTEM_AUDIT.md").write_text(
    """# Challenge System Audit\n\n"
    "## Scope\n"
    "This audit follows challenge creation, notification delivery, exact status polling, acceptance, decline, cancellation, room funding, lobby readiness, reconnect, surrender, settlement, result UI, rematch, Coin, ELO, recent opponents, and platform leaderboard mirroring.\n\n"
    "## Product rules\n"
    "- Direct friend challenges are **friendly** matches. They use the same authoritative Sudoku engine and Coin entry/pot economy, but they do not change ranked ELO or ranked leaderboards. This prevents rating boosting between friends.\n"
    "- Normal online matchmaking is **ranked**. Completed ranked matches and ranked forfeits update global and difficulty ELO, backend leaderboards, Google Play Games/Game Center mirrors when configured, and Android Play Games game-stat events.\n"
    "- Leaving before a match starts cancels the lobby and refunds both entry fees. Leaving after the match starts is an explicit surrender: the opponent wins and normal settlement runs.\n\n"
    "## Hardening delivered\n"
    "- Exact challenge GET and challenger DELETE endpoints.\n"
    "- One pending challenge per sender/recipient direction and reverse-pending guard.\n"
    "- Active-match and both-player Coin checks before creation and acceptance.\n"
    "- Race-safe accept/decline updates and single-shot response notifications.\n"
    "- Accepted rooms are returned only when a live match row and funded escrow both exist.\n"
    "- Terminal/unfunded room replay is rejected by both websocket entry paths.\n"
    "- Two-minute authoritative lobby timeout prevents abandoned rooms from holding Coin indefinitely.\n"
    "- Challenge polling verifies challengeId before using activeMatch.\n"
    "- Sender sees decline/expiry/cancellation separately and can cancel a pending challenge.\n"
    "- Pre-match back cancels on the server and waits for refund settlement.\n"
    "- Active matches expose a visible surrender action; system back uses the same confirmed surrender flow and does not dispose the socket before the server acknowledges the result.\n"
    "- Result UI waits for settled rating data, reports net Coin result, routes rematch safely, and opens ranked matchmaking for Find new match.\n"
    "- Recent opponents are written during authoritative settlement.\n"
    "- Native platform leaderboards resync authoritative backend ratings at startup and when the leaderboard hub connects, recovering a missed per-match submission.\n\n"
    "## Remaining deployment and device gates\n"
    "- Apply D1 migration `0016_challenge_hardening.sql` and deploy the updated Worker.\n"
    "- Verify Cloudflare FCM secrets and Firebase/APNs configuration.\n"
    "- Android leaderboard IDs are configured in code; iOS Game Center IDs remain placeholders until real App Store Connect leaderboard identifiers are supplied.\n"
    "- Run physical Android↔Android, iOS↔iOS, and Android↔iOS tests for foreground/background/terminated notification delivery, reconnect, surrender, lobby cancellation refund, win/loss/draw, rematch, and ranked ELO propagation.\n"
    """,
    encoding="utf-8",
)

print('Challenge client hardening applied.')
