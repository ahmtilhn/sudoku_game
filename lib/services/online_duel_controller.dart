import 'dart:async';

import 'online_duel_models.dart';
import 'online_duel_transport.dart';

class OnlineDuelController {
  OnlineDuelController(this._transport);

  final OnlineDuelTransport _transport;
  final StreamController<OnlineDuelSnapshot> _snapshots =
      StreamController<OnlineDuelSnapshot>.broadcast();
  StreamSubscription<OnlineDuelEvent>? _subscription;
  OnlineDuelSnapshot? _snapshot;
  bool _pendingMove = false;

  Stream<OnlineDuelSnapshot> get snapshots => _snapshots.stream;
  OnlineDuelSnapshot? get current => _snapshot;
  bool get pendingMove => _pendingMove;

  void start() {
    _subscription = _transport.events.listen(_handleEvent);
  }

  void ready() => _send('ready');

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
    await _snapshots.close();
  }

  void _handleEvent(OnlineDuelEvent event) {
    if (event.type == 'connected' || event.type == 'snapshot') {
      _applySnapshot(event.payload);
      return;
    }
    if (event.type == 'move_accepted') {
      _pendingMove = false;
      final snapshot = _snapshot;
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
      return;
    }
    if (event.type == 'move_rejected' || event.type == 'protocol_error') {
      _pendingMove = false;
      final recovery = event.payload['snapshot'];
      if (recovery is Map) {
        _applySnapshot(recovery.cast<String, dynamic>());
      } else {
        requestSnapshot();
      }
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
