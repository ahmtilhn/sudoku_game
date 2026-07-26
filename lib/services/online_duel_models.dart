enum OnlineDuelStatus {
  waiting,
  countdown,
  active,
  paused,
  completed,
  forfeited,
  cancelled,
  abandoned,
}

enum OnlineDuelSeat { a, b }

class OnlineDuelPlayer {
  const OnlineDuelPlayer({
    required this.publicId,
    required this.username,
    required this.displayName,
    required this.avatarKey,
    required this.ready,
    required this.connected,
    this.disconnectDeadline,
  });

  final String publicId;
  final String username;
  final String displayName;
  final String avatarKey;
  final bool ready;
  final bool connected;
  final DateTime? disconnectDeadline;

  factory OnlineDuelPlayer.fromJson(Map<String, dynamic> json) {
    return OnlineDuelPlayer(
      publicId: json['publicId']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? 'Player',
      avatarKey: json['avatarKey']?.toString() ?? 'default',
      ready: json['ready'] == true,
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
    this.turnDeadline,
    this.winnerSeat,
    this.finishReason,
    this.rating,
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
  final DateTime? turnDeadline;
  final DateTime serverTime;
  final int revision;
  final OnlineDuelSeat? winnerSeat;
  final String? finishReason;
  final Map<OnlineDuelSeat, OnlineDuelRatingChange>? rating;

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
    DateTime? turnDeadline,
    DateTime? serverTime,
    int? revision,
    OnlineDuelSeat? winnerSeat,
    String? finishReason,
    Map<OnlineDuelSeat, OnlineDuelRatingChange>? rating,
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
      turnDeadline: turnDeadline ?? this.turnDeadline,
      serverTime: serverTime ?? this.serverTime,
      revision: revision ?? this.revision,
      winnerSeat: winnerSeat ?? this.winnerSeat,
      finishReason: finishReason ?? this.finishReason,
      rating: rating ?? this.rating,
    );
  }

  factory OnlineDuelSnapshot.fromJson(Map<String, dynamic> json) {
    return OnlineDuelSnapshot(
      roomId: json['roomId']?.toString() ?? '',
      matchId: json['matchId']?.toString() ?? '',
      mode: json['mode']?.toString() ?? 'friendly',
      difficulty: json['difficulty']?.toString() ?? 'easy',
      status: _status(json['status']?.toString()),
      youSeat: _seat(json['youSeat']?.toString()) ?? OnlineDuelSeat.a,
      players: _players(json['players']),
      puzzle: _intList(json['puzzle']),
      board: _intList(json['board']),
      scores: _seatIntMap(json['scores']),
      mistakes: _seatIntMap(json['mistakes']),
      correctMoves: _seatIntMap(json['correctMoves']),
      timeouts: _seatIntMap(json['timeouts']),
      currentTurnSeat:
          _seat(json['currentTurnSeat']?.toString()) ?? OnlineDuelSeat.a,
      turnNumber: (json['turnNumber'] as num?)?.toInt() ?? 1,
      turnDeadline: _dateFromMillis(json['turnDeadline']),
      serverTime: _dateFromMillis(json['serverTime']) ?? DateTime.now(),
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      winnerSeat: _seat(json['winnerSeat']?.toString()),
      finishReason: json['finishReason']?.toString(),
      rating: _rating(json['rating']),
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
  return value.map((item) => (item as num?)?.toInt() ?? 0).toList();
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
