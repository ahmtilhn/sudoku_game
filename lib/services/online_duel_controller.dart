import 'dart:async';

import 'online_duel_models.dart';
import 'online_duel_transport.dart';

class OnlineDuelController {
  OnlineDuelController(this._transport);

  final OnlineDuelTransport _transport;
  final StreamController<OnlineDuelSnapshot> _snapshots =
      StreamController<OnlineDuelSnapshot>.broadcast();
  final StreamController<OnlineDuelFeedback> _feedback =
      StreamController<OnlineDuelFeedback>.broadcast();
  StreamSubscription<OnlineDuelEvent>? _subscription;
  OnlineDuelSnapshot? _snapshot;
  bool _pendingMove = false;

  Stream<OnlineDuelSnapshot> get snapshots => _snapshots.stream;
  Stream<OnlineDuelFeedback> get feedback => _feedback.stream;
  OnlineDuelSnapshot? get current => _snapshot;
  bool get pendingMove => _pendingMove;

  void start() {
    _subscription = _transport.events.listen(_handleEvent);
  }

  void ready() => _send('ready');

  void screenLoaded() => _send('game_screen_loaded');

  bool move(int cellIndex, int value) {
    final current = _snapshot;
    if (current == null || !current.isLocalTurn || _pendingMove) return false;
    if (cellIndex < 0 ||
        cellIndex >= current.board.length ||
        current.puzzle[cellIndex] != 0 ||
        current.board[cellIndex] != 0) {
      return false;
    }
    _pendingMove = true;
    _send('move', <String, Object>{'cellIndex': cellIndex, 'value': value});
    return true;
  }

  void forfeit() => _send('forfeit');

  void requestSnapshot() => _send('request_snapshot');

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _transport.close();
    await _feedback.close();
    await _snapshots.close();
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
      final isLocalAction =
          snapshot != null && actorSeat == snapshot.youSeat;

      if (isLocalAction) _pendingMove = false;

      final cellIndex = (event.payload['cellIndex'] as num?)?.toInt();
      final value = (event.payload['value'] as num?)?.toInt();
      if (snapshot != null && cellIndex != null && value != null) {
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
            message: 'Hamle kabul edildi',
          ),
        );
      }
      return;
    }
    if (event.type == 'move_rejected' || event.type == 'protocol_error') {
      final snapshot = _snapshot;
      final actorSeat = _seat(event.payload['seat']?.toString());

      if (event.type == 'move_rejected' &&
          actorSeat != null &&
          snapshot != null &&
          actorSeat != snapshot.youSeat) {
        return;
      }

      _pendingMove = false;
      final reason =
          event.payload['reason']?.toString() ??
          event.payload['code']?.toString() ??
          'network';
      _feedback.add(OnlineDuelFeedback.rejected(reason: reason));
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
        turnDeadline: _dateFromMillis(event.payload['turnDeadline']),
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
    _pendingMove = false;
    _snapshot = OnlineDuelSnapshot.fromJson(payload);
    _snapshots.add(_snapshot!);
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
      readyDeadline:
          _dateFromMillis(event.payload['readyDeadline']) ??
          snapshot.readyDeadline,
      revision: event.revision,
      serverTime: event.serverTime,
    );
    _snapshots.add(_snapshot!);
  }

  void _send(String type, [Map<String, Object?> payload = const {}]) {
    _transport.send(<String, Object?>{
      'v': 1,
      'type': type,
      'requestId': DateTime.now().microsecondsSinceEpoch.toString(),
      'expectedRevision': _snapshot?.revision,
      'payload': payload,
    });
  }
}

class OnlineDuelFeedback {
  const OnlineDuelFeedback._({
    required this.accepted,
    required this.message,
    this.cellIndex,
    this.reason,
  });

  final bool accepted;
  final String message;
  final int? cellIndex;
  final String? reason;

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
}

Map<OnlineDuelSeat, OnlineDuelPlayer> _playersWithPatch(
  Map<OnlineDuelSeat, OnlineDuelPlayer> current,
  Map<String, dynamic> payload,
) {
  final ready = (payload['ready'] as Map?)?.cast<String, dynamic>();
  final presence = (payload['presence'] as Map?)?.cast<String, dynamic>();
  final screenLoaded = (payload['screenLoaded'] as Map?)
      ?.cast<String, dynamic>();
  return {
    for (final entry in current.entries)
      entry.key: OnlineDuelPlayer(
        publicId: entry.value.publicId,
        username: entry.value.username,
        displayName: entry.value.displayName,
        avatarKey: entry.value.avatarKey,
        ready: (ready?[_seatKey(entry.key)] as bool?) ?? entry.value.ready,
        screenLoaded:
            (screenLoaded?[_seatKey(entry.key)] as bool?) ??
            entry.value.screenLoaded,
        connected:
            (presence?[_seatKey(entry.key)] as bool?) ?? entry.value.connected,
        disconnectDeadline: entry.value.disconnectDeadline,
      ),
  };
}

OnlineDuelStatus? _status(String? value) => switch (value) {
  'waiting' => OnlineDuelStatus.waiting,
  'ready_window' => OnlineDuelStatus.readyWindow,
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
  'not_your_turn' || 'out_of_turn' => 'Sıra sende değil.',
  'cell_not_editable' || 'cell_locked' => 'Bu hücre değiştirilemez.',
  'cell_already_filled' => 'Bu hücre dolu.',
  'invalid_move' ||
  'wrong_value' ||
  'incorrect_value' => 'Bu sayı bu hücre için doğru değil.',
  'game_not_active' || 'match_not_active' => 'Oyun henüz başlamadı.',
  'stale_revision' => 'Oyun güncellendi, tahta yenileniyor.',
  'timeout' => 'İstek zaman aşımına uğradı.',
  'disconnected' || 'network' => 'Bağlantı sorunu oluştu.',
  _ => 'Hamle reddedildi.',
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
