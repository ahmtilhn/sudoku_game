import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/sudoku.dart';

class GameSessionMove {
  const GameSessionMove({
    required this.index,
    required this.previousValue,
    required this.previousNotes,
  });

  final int index;
  final int previousValue;
  final Set<int> previousNotes;

  Map<String, Object> toJson() => <String, Object>{
    'index': index,
    'previousValue': previousValue,
    'previousNotes': previousNotes.toList()..sort(),
  };

  factory GameSessionMove.fromJson(Map<String, dynamic> json) {
    return GameSessionMove(
      index: (json['index'] as num?)?.toInt() ?? -1,
      previousValue: (json['previousValue'] as num?)?.toInt() ?? 0,
      previousNotes: _intSet(json['previousNotes']),
    );
  }
}

class GameSessionSnapshot {
  const GameSessionSnapshot({
    required this.puzzleId,
    required this.puzzleSignature,
    required this.board,
    required this.notes,
    required this.history,
    required this.hintedIndexes,
    required this.selectedIndex,
    required this.elapsedSeconds,
    required this.mistakes,
    required this.totalMistakes,
    required this.hintsUsed,
    required this.notesMode,
    required this.roundLost,
    required this.savedAt,
  });

  static const int schemaVersion = 1;

  final String puzzleId;
  final String puzzleSignature;
  final List<int> board;
  final Map<int, Set<int>> notes;
  final List<GameSessionMove> history;
  final Set<int> hintedIndexes;
  final int? selectedIndex;
  final int elapsedSeconds;
  final int mistakes;
  final int totalMistakes;
  final int hintsUsed;
  final bool notesMode;
  final bool roundLost;
  final DateTime savedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'puzzleId': puzzleId,
    'puzzleSignature': puzzleSignature,
    'board': board,
    'notes': notes.map(
      (index, values) => MapEntry(index.toString(), values.toList()..sort()),
    ),
    'history': history.map((move) => move.toJson()).toList(),
    'hintedIndexes': hintedIndexes.toList()..sort(),
    'selectedIndex': selectedIndex,
    'elapsedSeconds': elapsedSeconds,
    'mistakes': mistakes,
    'totalMistakes': totalMistakes,
    'hintsUsed': hintsUsed,
    'notesMode': notesMode,
    'roundLost': roundLost,
    'savedAt': savedAt.toUtc().toIso8601String(),
  };

  factory GameSessionSnapshot.fromJson(Map<String, dynamic> json) {
    final notes = <int, Set<int>>{};
    final rawNotes = json['notes'];
    if (rawNotes is Map) {
      for (final entry in rawNotes.entries) {
        final index = int.tryParse(entry.key.toString());
        if (index != null) notes[index] = _intSet(entry.value);
      }
    }

    final history = <GameSessionMove>[];
    final rawHistory = json['history'];
    if (rawHistory is List) {
      for (final value in rawHistory) {
        if (value is Map) {
          history.add(
            GameSessionMove.fromJson(
              value.map((key, item) => MapEntry(key.toString(), item)),
            ),
          );
        }
      }
    }

    return GameSessionSnapshot(
      puzzleId: json['puzzleId']?.toString() ?? '',
      puzzleSignature: json['puzzleSignature']?.toString() ?? '',
      board: _intList(json['board']),
      notes: notes,
      history: history,
      hintedIndexes: _intSet(json['hintedIndexes']),
      selectedIndex: (json['selectedIndex'] as num?)?.toInt(),
      elapsedSeconds: (json['elapsedSeconds'] as num?)?.toInt() ?? 0,
      mistakes: (json['mistakes'] as num?)?.toInt() ?? 0,
      totalMistakes: (json['totalMistakes'] as num?)?.toInt() ?? 0,
      hintsUsed: (json['hintsUsed'] as num?)?.toInt() ?? 0,
      notesMode: json['notesMode'] == true,
      roundLost: json['roundLost'] == true,
      savedAt:
          DateTime.tryParse(json['savedAt']?.toString() ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  bool isValidFor(SudokuPuzzle puzzle) {
    if (puzzleId != puzzle.id || puzzleSignature != signatureFor(puzzle)) {
      return false;
    }
    if (board.length != puzzle.cellCount || elapsedSeconds < 0) return false;
    if (mistakes < 0 || totalMistakes < mistakes || hintsUsed < 0) {
      return false;
    }
    if (selectedIndex != null &&
        (selectedIndex! < 0 || selectedIndex! >= puzzle.cellCount)) {
      return false;
    }

    for (var index = 0; index < board.length; index++) {
      final value = board[index];
      if (value < 0 || value > puzzle.size) return false;
      if (puzzle.isFixed(index) && value != puzzle.puzzle[index]) return false;
      if (value != 0 && value != puzzle.solution[index]) return false;
    }
    for (final entry in notes.entries) {
      if (entry.key < 0 || entry.key >= puzzle.cellCount) return false;
      if (board[entry.key] != 0 || puzzle.isFixed(entry.key)) return false;
      if (entry.value.any((value) => value < 1 || value > puzzle.size)) {
        return false;
      }
    }
    if (hintedIndexes.any(
      (index) =>
          index < 0 ||
          index >= puzzle.cellCount ||
          puzzle.isFixed(index) ||
          board[index] != puzzle.solution[index],
    )) {
      return false;
    }
    for (final move in history) {
      if (move.index < 0 || move.index >= puzzle.cellCount) return false;
      if (move.previousValue < 0 || move.previousValue > puzzle.size) {
        return false;
      }
      if (move.previousNotes.any((value) => value < 1 || value > puzzle.size)) {
        return false;
      }
    }
    return true;
  }

  static String signatureFor(SudokuPuzzle puzzle) {
    final values = <Object>[
      puzzle.id,
      puzzle.size,
      puzzle.boxRows,
      puzzle.boxColumns,
      ...puzzle.puzzle,
      ...puzzle.solution,
    ];
    var hash = 0x811C9DC5;
    for (final value in values) {
      final text = value.toString();
      for (final codeUnit in text.codeUnits) {
        hash ^= codeUnit;
        hash = (hash * 0x01000193) & 0xFFFFFFFF;
      }
      hash ^= 0xFF;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

class ActiveGameSessionMetadata {
  const ActiveGameSessionMetadata({
    required this.puzzleId,
    required this.savedAt,
    required this.elapsedSeconds,
  });

  final String puzzleId;
  final DateTime savedAt;
  final int elapsedSeconds;

  Map<String, Object> toJson() => <String, Object>{
    'puzzleId': puzzleId,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'elapsedSeconds': elapsedSeconds,
  };

  factory ActiveGameSessionMetadata.fromJson(Map<String, dynamic> json) {
    return ActiveGameSessionMetadata(
      puzzleId: json['puzzleId']?.toString() ?? '',
      savedAt:
          DateTime.tryParse(json['savedAt']?.toString() ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      elapsedSeconds: (json['elapsedSeconds'] as num?)?.toInt() ?? 0,
    );
  }
}

class GameSessionStore {
  GameSessionStore._();

  static final GameSessionStore instance = GameSessionStore._();
  static const String _sessionPrefix = 'active_game_session_v1:';
  static const String _latestKey = 'active_game_session_latest_v1';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  final ValueNotifier<ActiveGameSessionMetadata?> activeSession =
      ValueNotifier<ActiveGameSessionMetadata?>(null);

  Future<GameSessionSnapshot?> load(SudokuPuzzle puzzle) async {
    final raw = await _preferences.getString(_key(puzzle.id));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException();
      final snapshot = GameSessionSnapshot.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (!snapshot.isValidFor(puzzle)) {
        await delete(puzzle.id);
        return null;
      }
      return snapshot;
    } catch (_) {
      await delete(puzzle.id);
      return null;
    }
  }

  Future<void> save(GameSessionSnapshot snapshot) async {
    final metadata = ActiveGameSessionMetadata(
      puzzleId: snapshot.puzzleId,
      savedAt: snapshot.savedAt,
      elapsedSeconds: snapshot.elapsedSeconds,
    );
    await Future.wait<void>(<Future<void>>[
      _preferences.setString(
        _key(snapshot.puzzleId),
        jsonEncode(snapshot.toJson()),
      ),
      _preferences.setString(_latestKey, jsonEncode(metadata.toJson())),
    ]);
    _publish(metadata);
  }

  Future<ActiveGameSessionMetadata?> latest() async {
    final raw = await _preferences.getString(_latestKey);
    if (raw == null || raw.isEmpty) {
      _publish(null);
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException();
      final metadata = ActiveGameSessionMetadata.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (metadata.puzzleId.isEmpty) throw const FormatException();
      _publish(metadata);
      return metadata;
    } catch (_) {
      await _preferences.remove(_latestKey);
      _publish(null);
      return null;
    }
  }

  Future<void> delete(String puzzleId) async {
    await _preferences.remove(_key(puzzleId));
    final latestSession = await latest();
    if (latestSession?.puzzleId == puzzleId) {
      await _preferences.remove(_latestKey);
      _publish(null);
    }
  }

  Future<void> clearAll() async {
    final latestSession = await latest();
    if (latestSession != null) {
      await _preferences.remove(_key(latestSession.puzzleId));
    }
    await _preferences.remove(_latestKey);
    _publish(null);
  }

  String _key(String puzzleId) => '$_sessionPrefix$puzzleId';

  void _publish(ActiveGameSessionMetadata? metadata) {
    final current = activeSession.value;
    if (current?.puzzleId == metadata?.puzzleId &&
        current?.elapsedSeconds == metadata?.elapsedSeconds &&
        current?.savedAt == metadata?.savedAt) {
      return;
    }
    activeSession.value = metadata;
  }
}

List<int> _intList(Object? value) {
  if (value is! List) return const <int>[];
  return value.map((item) => (item as num?)?.toInt() ?? -1).toList();
}

Set<int> _intSet(Object? value) {
  if (value is! List) return <int>{};
  return value.map((item) => (item as num?)?.toInt()).whereType<int>().toSet();
}
