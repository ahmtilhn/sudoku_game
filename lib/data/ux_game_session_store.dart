import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/sudoku.dart';

class UxSessionMove {
  const UxSessionMove({
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

  factory UxSessionMove.fromJson(Map<String, dynamic> json) {
    return UxSessionMove(
      index: (json['index'] as num?)?.toInt() ?? -1,
      previousValue: (json['previousValue'] as num?)?.toInt() ?? 0,
      previousNotes: _intSet(json['previousNotes']),
    );
  }
}

class UxGameSession {
  const UxGameSession({
    required this.puzzle,
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

  static const int schemaVersion = 2;

  final SudokuPuzzle puzzle;
  final List<int> board;
  final Map<int, Set<int>> notes;
  final List<UxSessionMove> history;
  final Set<int> hintedIndexes;
  final int? selectedIndex;
  final int elapsedSeconds;
  final int mistakes;
  final int totalMistakes;
  final int hintsUsed;
  final bool notesMode;
  final bool roundLost;
  final DateTime savedAt;

  String get mode {
    if (puzzle.id.startsWith('career-') &&
        !puzzle.id.startsWith('career-random-')) {
      return 'career';
    }
    if (puzzle.id.startsWith('daily-')) return 'daily';
    return 'practice';
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'puzzle': <String, Object>{
      'id': puzzle.id,
      'title': puzzle.title,
      'difficulty': puzzle.difficulty.name,
      'size': puzzle.size,
      'boxRows': puzzle.boxRows,
      'boxColumns': puzzle.boxColumns,
      'clues': puzzle.puzzle,
      'solution': puzzle.solution,
    },
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

  factory UxGameSession.fromJson(Map<String, dynamic> json) {
    final rawPuzzle = json['puzzle'];
    if (rawPuzzle is! Map) throw const FormatException('Missing puzzle.');
    final puzzleJson = rawPuzzle.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final difficultyName = puzzleJson['difficulty']?.toString() ?? 'easy';
    final difficulty = SudokuDifficulty.values.firstWhere(
      (value) => value.name == difficultyName,
      orElse: () => SudokuDifficulty.easy,
    );
    final puzzle = SudokuPuzzle(
      id: puzzleJson['id']?.toString() ?? '',
      title: puzzleJson['title']?.toString() ?? '',
      difficulty: difficulty,
      size: (puzzleJson['size'] as num?)?.toInt() ?? 9,
      boxRows: (puzzleJson['boxRows'] as num?)?.toInt() ?? 3,
      boxColumns: (puzzleJson['boxColumns'] as num?)?.toInt() ?? 3,
      puzzle: _intList(puzzleJson['clues']),
      solution: _intList(puzzleJson['solution']),
    );

    final notes = <int, Set<int>>{};
    final rawNotes = json['notes'];
    if (rawNotes is Map) {
      for (final entry in rawNotes.entries) {
        final index = int.tryParse(entry.key.toString());
        if (index != null) notes[index] = _intSet(entry.value);
      }
    }

    final history = <UxSessionMove>[];
    final rawHistory = json['history'];
    if (rawHistory is List) {
      for (final item in rawHistory.whereType<Map>()) {
        history.add(
          UxSessionMove.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        );
      }
    }

    return UxGameSession(
      puzzle: puzzle,
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

  bool get isValid {
    if (!SudokuEngine.isPuzzleShapeValid(puzzle)) return false;
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
    return true;
  }
}

class UxGameSessionStore {
  UxGameSessionStore._();

  static final UxGameSessionStore instance = UxGameSessionStore._();
  static const String _key = 'ux_active_game_session_v2';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  final ValueNotifier<UxGameSession?> activeSession =
      ValueNotifier<UxGameSession?>(null);

  Future<UxGameSession?> initialize() => latest();

  Future<UxGameSession?> latest() async {
    final raw = await _preferences.getString(_key);
    if (raw == null || raw.isEmpty) {
      _publish(null);
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException();
      final session = UxGameSession.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (!session.isValid) throw const FormatException();
      _publish(session);
      return session;
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<UxGameSession?> load(SudokuPuzzle puzzle) async {
    final session = await latest();
    if (session == null || session.puzzle.id != puzzle.id) return null;
    if (!_samePuzzle(session.puzzle, puzzle)) {
      await clear();
      return null;
    }
    return session;
  }

  Future<void> save(UxGameSession session) async {
    if (!session.isValid) return;
    await _preferences.setString(_key, jsonEncode(session.toJson()));
    _publish(session);
  }

  Future<void> clear() async {
    await _preferences.remove(_key);
    _publish(null);
  }

  bool _samePuzzle(SudokuPuzzle a, SudokuPuzzle b) {
    return a.id == b.id &&
        a.size == b.size &&
        listEquals(a.puzzle, b.puzzle) &&
        listEquals(a.solution, b.solution);
  }

  void _publish(UxGameSession? session) {
    final current = activeSession.value;
    if (current?.puzzle.id == session?.puzzle.id &&
        current?.elapsedSeconds == session?.elapsedSeconds &&
        current?.savedAt == session?.savedAt) {
      return;
    }
    activeSession.value = session;
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
