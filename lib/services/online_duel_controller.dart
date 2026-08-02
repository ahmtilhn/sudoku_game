import 'dart:async';

import 'package:flutter/widgets.dart';

import 'online_duel_models.dart';
import 'online_duel_transport.dart';
import 'platform_game_stats_service.dart';
import 'platform_leaderboard_service.dart';

class OnlineDuelController with WidgetsBindingObserver {
  OnlineDuelController(
    this._transport, {
    PlatformLeaderboardMirror? platformLeaderboardMirror,
    PlatformGameStatsMirror? platformGameStatsMirror,
    WidgetsBinding? binding,
  }) : _platformLeaderboardMirror =
           platformLeaderboardMirror ?? PlatformLeaderboardService.instance,
       _platformGameStatsMirror =
           platformGameStatsMirror ?? PlatformGameStatsService.instance,
       _binding = binding;

  final OnlineDuelTransport _transport;
  final PlatformLeaderboardMirror _platformLeaderboardMirror;
  final PlatformGameStatsMirror _platformGameStatsMirror;
  final WidgetsBinding? _binding;
  final StreamController<OnlineDuelSnapshot> _snapshots =
      StreamController<OnlineDuelSnapshot>.broadcast();
  final StreamController<OnlineDuelFeedback> _feedback =
      StreamController<OnlineDuelFeedback>.broadcast();
  StreamSubscription<OnlineDuelEvent>? _subscription;
  StreamSubscription<OnlineDuelConnectionState>? _connectionSubscription;
  OnlineDuelSnapshot? _snapshot;
  Map<String, Object?>? _pendingMoveEnvelope;
  bool _pendingMove = false;
  bool _started = false;
  bool _observerRegistered = false;

  Stream<OnlineDuelSnapshot> get snapshots => _snapshots.stream;
  Stream<OnlineDuelFeedback> get feedback => _feedback.stream;
  Stream<OnlineDuelConnectionState> get connectionStates =>
      _transport.connectionStates;
  OnlineDuelConnectionState get connectionState =>
      _transport.connectionState;
  OnlineDuelSnapshot? get current => _snapshot;
  bool get pendingMove => _pendingMove;

  void start() {
    if (_started) return;
    _started = true;
    final binding = _binding;
    if (binding != null) {
      binding.addObserver(this);
      _observerRegistered = true;
    }
    _subscription = _transport.events.listen(
      _handleEvent,
      onError: (Object error, StackTrace stackTrace) {
        if (!_feedback.isClosed) {
          _feedback.add(
            OnlineDuelFeedback.rejected(reason: 'disconnected'),
          );
        }
      },
    );
    _connectionSubscription = _transport.connectionStates.listen(
      _handleConnectionState,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_transport.reconnectNow());
    }
  }

  void ready() => _send('ready');

  void screenLoaded() => _send('game_screen_loaded');

  bool move(int cellIndex, int value) {
    final current = _snapshot;
    if (current == null || _pendingMove) return false;
    if (cellIndex < 0 ||
        cellIndex >= current.board.length ||
        current.puzzle[cellIndex] != 0 ||
        current.board[cellIndex] != 0) {
      return false;
    }
    _pendingMove = true;
    _pendingMoveEnvelope = _buildEnvelope(
      'move',
      <String, Object>{'cellIndex': cellIndex, 'value': value},
    );
    _transport.send(_pendingMoveEnvelope!);
    return true;
  }

  void forfeit() => _send('forfeit');

  void requestSnapshot() => _send('request_snapshot');

  Future<void> dispose() async {
    if (_observerRegistered) {
      _binding?.removeObserver(this);
      _observerRegistered = false;
    }
    await _subscription?.cancel();
    await _connectionSubscription?.cancel();
    await _transport.close();
    await _feedback.close();
    await _snapshots.close();
  }

  void _handleConnectionState(OnlineDuelConnectionState state) {
    if (state == OnlineDuelConnectionState.resyncing) {
      final pendingMove = _pendingMoveEnvelope;
      if (pendingMove != null) {
        _transport.send(pendingMove);
      }
      requestSnapshot();
    }
  }

  void _handleEvent(OnlineDuelEvent event) {
    final current = _snapshot;
    if (current != null &&
        event.revision < current.revision &&
        event.type != 'protocol_error') {
      return;
    }
    if (event.type == 'connected' ||
        event.type == 'snapshot' ||
        event.type == 'match_started' ||
        event.type == 'game_started') {
      _applySnapshot(event.payload);
      return;
    }
    if (event.type == 'move_accepted') {
      final snapshot = _snapshot;
      final actorSeat = _seat(event.payload['seat']?.toString());
      final forYou = event.payload['forYou'];
      final isLocalAction = forYou is bool
          ? forYou
          : actorSeat != null && snapshot != null
          ? actorSeat == snapshot.youSeat
          : _pendingMove;

      if (isLocalAction) _clearPendingMove();

      final cellIndex = (event.payload['cellIndex'] as num?)?.toInt();
      final value = (event.payload['value'] as num?)?.toInt();
      if (snapshot != null &&
          cellIndex != null &&
          value != null &&
          cellIndex >= 0 &&
          cellIndex < snapshot.board.length) {
        final board = List<int>.from(snapshot.board)..[cellIndex] = value;
        _snapshot = snapshot.copyWith(
          board: board,
          scores: _seatIntMap(event.payload['scores']) ?? snapshot.scores,
          revision: event.revision,
          serverTime: event.serverTime,
        );
        _snapshots.add(_snapshot!);
      }

      if (isLocalAction) {
        _feedback.add(
          OnlineDuelFeedback.accepted(
            cellIndex: cellIndex,
            message: 'Move accepted.',
          ),
        );
      }
      return;
    }
    if (event.type == 'move_rejected' || event.type == 'protocol_error') {
      final snapshot = _snapshot;
      final actorSeat = _seat(event.payload['seat']?.toString());

      final forYou = event.payload['forYou'];
      final isLocalRejection =
          event.type == 'protocol_error' ||
          (forYou is bool
              ? forYou
              : actorSeat != null && snapshot != null
              ? actorSeat == snapshot.youSeat
              : _pendingMove);

      if (isLocalRejection) {
        _clearPendingMove();
        final reason =
            event.payload['reason']?.toString() ??
            event.payload['code']?.toString() ??
            'network';
        _feedback.add(OnlineDuelFeedback.rejected(reason: reason));
      }

      final recovery = event.payload['snapshot'];
      if (recovery is Map) {
        _applySnapshot(recovery.cast<String, dynamic>());
      } else {
        requestSnapshot();
      }
      return;
    }
    if (event.type == 'player_ready' ||
        event.type == 'player_presence' ||
        event.type == 'screen_loaded' ||
        event.type == 'ready_window_started' ||
        event.type == 'ready_window_cancelled') {
      _applyPartialState(event);
      return;
    }
    if (event.type == 'turn_changed') {
      final snapshot = _snapshot;
      if (snapshot == null) return;
      _snapshot = snapshot.copyWith(
        currentTurnSeat: _seat(event.payload['currentTurnSeat']?.toString()),
        turnNumber: (event.payload['turnNumber'] as num?)?.toInt(),
        turnDeadline: event.payload.containsKey('turnDeadline')
            ? _dateFromMillis(event.payload['turnDeadline'])
            : snapshot.turnDeadline,
        revision: event.revision,
        serverTime: event.serverTime,
      );
      _snapshots.add(_snapshot!);
      return;
    }
    if (event.type == 'match_completed' ||
        event.type == 'player_forfeited' ||
        event.type == 'rating_updated') {
      requestSnapshot();
    }
  }

  void _applySnapshot(Map<String, dynamic> payload) {
    _clearPendingMove();
    final snapshot = OnlineDuelSnapshot.fromJson(payload);
    final previousMatchId = _snapshot?.matchId;
    _snapshot = snapshot;
    if (previousMatchId != null && previousMatchId != snapshot.matchId) {
      _feedback.add(OnlineDuelFeedback.matchChanged());
    }
    _platformGameStatsMirror.observeSnapshot(snapshot);
    _snapshots.add(snapshot);
    if (snapshot.isFinished) {
      unawaited(_platformLeaderboardMirror.mirrorFinalRatings(snapshot));
      unawaited(_platformGameStatsMirror.mirrorFinalStats(snapshot));
    }
  }

  void _applyPartialState(OnlineDuelEvent event) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      requestSnapshot();
      return;
    }
    _snapshot = snapshot.copyWith(
      status: _status(event.payload['status']?.toString()) ?? snapshot.status,
      players: _playersWithPatch(snapshot.players, event.payload),
      readyDeadline: event.payload.containsKey('readyDeadline')
          ? _dateFromMillis(event.payload['readyDeadline'])
          : snapshot.readyDeadline,
      revision: event.revision,
      serverTime: event.serverTime,
    );
    _snapshots.add(_snapshot!);
  }

  void _send(String type, [Map<String, Object?> payload = const {}]) {
    _transport.send(_buildEnvelope(type, payload));
  }

  Map<String, Object?> _buildEnvelope(
    String type,
    Map<String, Object?> payload,
  ) {
    return <String, Object?>{
      'v': 1,
      'type': type,
      'requestId': DateTime.now().microsecondsSinceEpoch.toString(),
      'expectedRevision': _snapshot?.revision,
      'payload': payload,
    };
  }

  void _clearPendingMove() {
    _pendingMove = false;
    _pendingMoveEnvelope = null;
  }
}

class OnlineDuelFeedback {
  const OnlineDuelFeedback._({
    required this.accepted,
    required this.message,
    this.cellIndex,
    this.reason,
    this.matchChanged = false,
  });

  final bool accepted;
  final String message;
  final int? cellIndex;
  final String? reason;
  final bool matchChanged;

  factory OnlineDuelFeedback.accepted({
    int? cellIndex,
    required String message,
  }) {
    return OnlineDuelFeedback._(
      accepted: true,
      message: message,
      cellIndex: cellIndex,
    );
  }

  factory OnlineDuelFeedback.rejected({required String reason}) {
    return OnlineDuelFeedback._(
      accepted: false,
      reason: reason,
      message: _messageForReason(reason),
    );
  }

  factory OnlineDuelFeedback.matchChanged() {
    return const OnlineDuelFeedback._(
      accepted: true,
      message: '',
      matchChanged: true,
    );
  }
}

Map<OnlineDuelSeat, OnlineDuelPlayer> _playersWithPatch(
  Map<OnlineDuelSeat, OnlineDuelPlayer> current,
  Map<String, dynamic> payload,
) {
  final ready = (payload['ready'] as Map?)?.cast<String, dynamic>();
  final presence = (payload['presence'] as Map?)?.cast<String, dynamic>();
  final screenLoaded = (payload['screenLoaded'] as Map?)
      ?.cast<String, dynamic>();
  final disconnectDeadlines = (payload['disconnectDeadlines'] as Map?)
      ?.cast<String, dynamic>();
  return {
    for (final entry in current.entries)
      entry.key: entry.value.copyWith(
        ready: (ready?[_seatKey(entry.key)] as bool?) ?? entry.value.ready,
        screenLoaded:
            (screenLoaded?[_seatKey(entry.key)] as bool?) ??
            entry.value.screenLoaded,
        connected:
            (presence?[_seatKey(entry.key)] as bool?) ?? entry.value.connected,
        disconnectDeadline:
            disconnectDeadlines?.containsKey(_seatKey(entry.key)) == true
            ? _dateFromMillis(disconnectDeadlines![_seatKey(entry.key)])
            : entry.value.disconnectDeadline,
      ),
  };
}

OnlineDuelStatus? _status(String? value) => switch (value) {
  'waiting' => OnlineDuelStatus.waiting,
  'ready_window' => OnlineDuelStatus.readyWindow,
  'countdown' => OnlineDuelStatus.countdown,
  'active' => OnlineDuelStatus.active,
  'paused' => OnlineDuelStatus.paused,
  'completed' => OnlineDuelStatus.completed,
  'forfeited' => OnlineDuelStatus.forfeited,
  'cancelled' => OnlineDuelStatus.cancelled,
  'abandoned' => OnlineDuelStatus.abandoned,
  _ => null,
};

String _seatKey(OnlineDuelSeat seat) => seat == OnlineDuelSeat.a ? 'A' : 'B';

String _messageForReason(String reason) => switch (reason) {
  'not_your_turn' || 'out_of_turn' => "It is not your turn.",
  'cell_not_editable' || 'cell_locked' => 'This cell cannot be changed.',
  'cell_already_filled' => 'This cell is already filled.',
  'invalid_move' ||
  'wrong_value' ||
  'incorrect_value' => 'That number is not correct for this cell.',
  'game_not_active' || 'match_not_active' => 'The game has not started yet.',
  'stale_revision' => 'The game changed. Refreshing the board.',
  'timeout' => 'The request timed out.',
  'disconnected' || 'network' => 'The connection was interrupted.',
  _ => 'The move was rejected.',
};

Map<OnlineDuelSeat, int>? _seatIntMap(Object? value) {
  final source = (value as Map?)?.cast<String, dynamic>();
  if (source == null) return null;
  return {
    OnlineDuelSeat.a: (source['A'] as num?)?.toInt() ?? 0,
    OnlineDuelSeat.b: (source['B'] as num?)?.toInt() ?? 0,
  };
}

OnlineDuelSeat? _seat(String? value) => switch (value) {
  'A' || 'a' => OnlineDuelSeat.a,
  'B' || 'b' => OnlineDuelSeat.b,
  _ => null,
};

DateTime? _dateFromMillis(Object? value) {
  final millis = (value as num?)?.toInt();
  return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
}
