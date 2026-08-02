enum OnlineDuelStatus {
  waiting,
  readyWindow,
  countdown,
  active,
  paused,
  completed,
  forfeited,
  cancelled,
  abandoned,
}

enum OnlineDuelSeat { a, b }

const Object _unsetOnlineDuelValue = Object();

class OnlineDuelPlayer {
  const OnlineDuelPlayer({
    required this.publicId,
    required this.username,
    required this.displayName,
    required this.avatarKey,
    required this.ready,
    required this.screenLoaded,
    required this.connected,
    this.disconnectDeadline,
  });

  final String publicId;
  final String username;
  final String displayName;
  final String avatarKey;
  final bool ready;
  final bool screenLoaded;
  final bool connected;
  final DateTime? disconnectDeadline;

  OnlineDuelPlayer copyWith({
    bool? ready,
    bool? screenLoaded,
    bool? connected,
    Object? disconnectDeadline = _unsetOnlineDuelValue,
  }) {
    return OnlineDuelPlayer(
      publicId: publicId,
      username: username,
      displayName: displayName,
      avatarKey: avatarKey,
      ready: ready ?? this.ready,
      screenLoaded: screenLoaded ?? this.screenLoaded,
      connected: connected ?? this.connected,
      disconnectDeadline: identical(
        disconnectDeadline,
        _unsetOnlineDuelValue,
      )
          ? this.disconnectDeadline
          : disconnectDeadline as DateTime?,
    );
  }

  factory OnlineDuelPlayer.fromJson(Map<String, dynamic> json) {
    return OnlineDuelPlayer(
      publicId: json['publicId']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? 'Player',
      avatarKey: json['avatarKey']?.toString() ?? 'default',
      ready: json['ready'] == true,
      screenLoaded: json['screenLoaded'] == true,
      connected: json['connected'] == true,
      disconnectDeadline: _dateFromMillis(json['disconnectDeadline']),
    );
  }
}

class OnlineDuelRatingChange {
  const OnlineDuelRatingChange({
    required this.beforeGlobal,
    required this.afterGlobal,
    required this.deltaGlobal,
    required this.beforeDifficulty,
    required this.afterDifficulty,
    required this.deltaDifficulty,
  });

  final int beforeGlobal;
  final int afterGlobal;
  final int deltaGlobal;
  final int beforeDifficulty;
  final int afterDifficulty;
  final int deltaDifficulty;

  factory OnlineDuelRatingChange.fromJson(Map<String, dynamic> json) {
    return OnlineDuelRatingChange(
      beforeGlobal: (json['beforeGlobal'] as num?)?.toInt() ?? 1000,
      afterGlobal: (json['afterGlobal'] as num?)?.toInt() ?? 1000,
      deltaGlobal: (json['deltaGlobal'] as num?)?.toInt() ?? 0,
      beforeDifficulty: (json['beforeDifficulty'] as num?)?.toInt() ?? 1000,
      afterDifficulty: (json['afterDifficulty'] as num?)?.toInt() ?? 1000,
      deltaDifficulty: (json['deltaDifficulty'] as num?)?.toInt() ?? 0,
    );
  }
}

class OnlineDuelSnapshot {
  const OnlineDuelSnapshot({
    required this.roomId,
    required this.matchId,
    required this.mode,
    required this.difficulty,
    required this.status,
    required this.youSeat,
    required this.players,
    required this.puzzle,
    required this.board,
    required this.scores,
    required this.mistakes,
    required this.correctMoves,
    required this.timeouts,
    required this.currentTurnSeat,
    required this.turnNumber,
    required this.serverTime,
    required this.revision,
    this.readyDeadline,
    this.turnDeadline,
    this.winnerSeat,
    this.finishReason,
    this.rating,
    this.coinSettlement,
  });

  final String roomId;
  final String matchId;
  final String mode;
  final String difficulty;
  final OnlineDuelStatus status;
  final OnlineDuelSeat youSeat;
  final Map<OnlineDuelSeat, OnlineDuelPlayer> players;
  final List<int> puzzle;
  final List<int> board;
  final Map<OnlineDuelSeat, int> scores;
  final Map<OnlineDuelSeat, int> mistakes;
  final Map<OnlineDuelSeat, int> correctMoves;
  final Map<OnlineDuelSeat, int> timeouts;
  final OnlineDuelSeat currentTurnSeat;
  final int turnNumber;
  final DateTime? readyDeadline;
  final DateTime? turnDeadline;
  final DateTime serverTime;
  final int revision;
  final OnlineDuelSeat? winnerSeat;
  final String? finishReason;
  final Map<OnlineDuelSeat, OnlineDuelRatingChange>? rating;
  final OnlineDuelCoinSettlement? coinSettlement;

  bool get isLocalTurn =>
      status == OnlineDuelStatus.active && currentTurnSeat == youSeat;

  bool get isFinished =>
      status == OnlineDuelStatus.completed ||
      status == OnlineDuelStatus.forfeited ||
      status == OnlineDuelStatus.cancelled ||
      status == OnlineDuelStatus.abandoned;

  OnlineDuelSnapshot copyWith({
    OnlineDuelStatus? status,
    Map<OnlineDuelSeat, OnlineDuelPlayer>? players,
    List<int>? board,
    Map<OnlineDuelSeat, int>? scores,
    Map<OnlineDuelSeat, int>? mistakes,
    Map<OnlineDuelSeat, int>? correctMoves,
    Map<OnlineDuelSeat, int>? timeouts,
    OnlineDuelSeat? currentTurnSeat,
    int? turnNumber,
    Object? readyDeadline = _unsetOnlineDuelValue,
    Object? turnDeadline = _unsetOnlineDuelValue,
    DateTime? serverTime,
    int? revision,
    Object? winnerSeat = _unsetOnlineDuelValue,
    Object? finishReason = _unsetOnlineDuelValue,
    Object? rating = _unsetOnlineDuelValue,
    Object? coinSettlement = _unsetOnlineDuelValue,
  }) {
    return OnlineDuelSnapshot(
      roomId: roomId,
      matchId: matchId,
      mode: mode,
      difficulty: difficulty,
      status: status ?? this.status,
      youSeat: youSeat,
      players: players ?? this.players,
      puzzle: puzzle,
      board: board ?? this.board,
      scores: scores ?? this.scores,
      mistakes: mistakes ?? this.mistakes,
      correctMoves: correctMoves ?? this.correctMoves,
      timeouts: timeouts ?? this.timeouts,
      currentTurnSeat: currentTurnSeat ?? this.currentTurnSeat,
      turnNumber: turnNumber ?? this.turnNumber,
      readyDeadline: identical(readyDeadline, _unsetOnlineDuelValue)
          ? this.readyDeadline
          : readyDeadline as DateTime?,
      turnDeadline: identical(turnDeadline, _unsetOnlineDuelValue)
          ? this.turnDeadline
          : turnDeadline as DateTime?,
      serverTime: serverTime ?? this.serverTime,
      revision: revision ?? this.revision,
      winnerSeat: identical(winnerSeat, _unsetOnlineDuelValue)
          ? this.winnerSeat
          : winnerSeat as OnlineDuelSeat?,
      finishReason: identical(finishReason, _unsetOnlineDuelValue)
          ? this.finishReason
          : finishReason as String?,
      rating: identical(rating, _unsetOnlineDuelValue)
          ? this.rating
          : rating as Map<OnlineDuelSeat, OnlineDuelRatingChange>?,
      coinSettlement: identical(coinSettlement, _unsetOnlineDuelValue)
          ? this.coinSettlement
          : coinSettlement as OnlineDuelCoinSettlement?,
    );
  }

  factory OnlineDuelSnapshot.fromJson(Map<String, dynamic> json) {
    final puzzle = _intList(json['puzzle']);
    final board = _intList(json['board']);
    _validateSnapshotShape(puzzle: puzzle, board: board);

    return OnlineDuelSnapshot(
      roomId: json['roomId']?.toString() ?? '',
      matchId: json['matchId']?.toString() ?? '',
      mode: json['mode']?.toString() ?? 'friendly',
      difficulty: json['difficulty']?.toString() ?? 'easy',
      status: _status(json['status']?.toString()),
      youSeat: _seat(json['youSeat']?.toString()) ?? OnlineDuelSeat.a,
      players: _players(json['players']),
      puzzle: puzzle,
      board: board,
      scores: _seatIntMap(json['scores']),
      mistakes: _seatIntMap(json['mistakes']),
      correctMoves: _seatIntMap(json['correctMoves']),
      timeouts: _seatIntMap(json['timeouts']),
      currentTurnSeat:
          _seat(json['currentTurnSeat']?.toString()) ?? OnlineDuelSeat.a,
      turnNumber: (json['turnNumber'] as num?)?.toInt() ?? 1,
      readyDeadline: _dateFromMillis(json['readyDeadline']),
      turnDeadline: _dateFromMillis(json['turnDeadline']),
      serverTime: _dateFromMillis(json['serverTime']) ?? DateTime.now(),
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      winnerSeat: _seat(json['winnerSeat']?.toString()),
      finishReason: json['finishReason']?.toString(),
      rating: _rating(json['rating']),
      coinSettlement: OnlineDuelCoinSettlement.parse(json['coinSettlement']),
    );
  }
}

class OnlineDuelCoinSettlement {
  const OnlineDuelCoinSettlement({
    required this.amount,
    required this.winnerSeat,
    required this.loserSeat,
    required this.balances,
    required this.deltas,
  });

  final int amount;
  final OnlineDuelSeat? winnerSeat;
  final OnlineDuelSeat? loserSeat;
  final Map<OnlineDuelSeat, int> balances;
  final Map<OnlineDuelSeat, int> deltas;

  static OnlineDuelCoinSettlement? parse(Object? value) {
    final json = (value as Map?)?.cast<String, dynamic>();
    if (json == null) return null;
    return OnlineDuelCoinSettlement(
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      winnerSeat: _seat(json['winnerSeat']?.toString()),
      loserSeat: _seat(json['loserSeat']?.toString()),
      balances: _seatIntMap(json['balances']),
      deltas: _seatIntMap(json['deltas']),
    );
  }
}

class OnlineDuelEvent {
  const OnlineDuelEvent({
    required this.type,
    required this.revision,
    required this.serverTime,
    required this.payload,
  });

  final String type;
  final int revision;
  final DateTime serverTime;
  final Map<String, dynamic> payload;

  factory OnlineDuelEvent.fromJson(Map<String, dynamic> json) {
    return OnlineDuelEvent(
      type: json['type']?.toString() ?? '',
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      serverTime: _dateFromMillis(json['serverTime']) ?? DateTime.now(),
      payload:
          (json['payload'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
    );
  }
}

OnlineDuelStatus _status(String? value) => switch (value) {
  'ready_window' => OnlineDuelStatus.readyWindow,
  'countdown' => OnlineDuelStatus.countdown,
  'active' => OnlineDuelStatus.active,
  'paused' => OnlineDuelStatus.paused,
  'completed' => OnlineDuelStatus.completed,
  'forfeited' => OnlineDuelStatus.forfeited,
  'cancelled' => OnlineDuelStatus.cancelled,
  'abandoned' => OnlineDuelStatus.abandoned,
  _ => OnlineDuelStatus.waiting,
};

OnlineDuelSeat? _seat(String? value) => switch (value) {
  'A' || 'a' => OnlineDuelSeat.a,
  'B' || 'b' => OnlineDuelSeat.b,
  _ => null,
};

DateTime? _dateFromMillis(Object? value) {
  final millis = (value as num?)?.toInt();
  return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
}

List<int> _intList(Object? value) {
  if (value is! List) return const <int>[];
  return value.map((item) => (item as num?)?.toInt() ?? -1).toList();
}

void _validateSnapshotShape({
  required List<int> puzzle,
  required List<int> board,
}) {
  if (puzzle.isEmpty || board.length != puzzle.length) {
    throw const FormatException(
      'Online duel snapshot puzzle and board lengths are invalid.',
    );
  }
  final size = switch (puzzle.length) {
    16 => 4,
    81 => 9,
    _ => 0,
  };
  if (size == 0) {
    throw FormatException(
      'Unsupported online duel board length: ${puzzle.length}.',
    );
  }
  for (var index = 0; index < puzzle.length; index++) {
    final clue = puzzle[index];
    final value = board[index];
    if (clue < 0 || clue > size || value < 0 || value > size) {
      throw FormatException('Invalid online duel cell value at index $index.');
    }
    if (clue != 0 && value != clue) {
      throw FormatException('Online duel board changed a clue at index $index.');
    }
  }
}

Map<OnlineDuelSeat, OnlineDuelPlayer> _players(Object? value) {
  final source = (value as Map?)?.cast<String, dynamic>() ?? const {};
  return {
    OnlineDuelSeat.a: OnlineDuelPlayer.fromJson(
      (source['A'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    OnlineDuelSeat.b: OnlineDuelPlayer.fromJson(
      (source['B'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
  };
}

Map<OnlineDuelSeat, int> _seatIntMap(Object? value) {
  final source = (value as Map?)?.cast<String, dynamic>() ?? const {};
  return {
    OnlineDuelSeat.a: (source['A'] as num?)?.toInt() ?? 0,
    OnlineDuelSeat.b: (source['B'] as num?)?.toInt() ?? 0,
  };
}

Map<OnlineDuelSeat, OnlineDuelRatingChange>? _rating(Object? value) {
  final source = (value as Map?)?.cast<String, dynamic>();
  if (source == null) return null;
  return {
    OnlineDuelSeat.a: OnlineDuelRatingChange.fromJson(
      (source['A'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    OnlineDuelSeat.b: OnlineDuelRatingChange.fromJson(
      (source['B'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
  };
}
