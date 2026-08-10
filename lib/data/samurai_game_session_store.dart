import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/samurai_sudoku.dart';
import '../domain/sudoku.dart';

class SamuraiGameSession {
  const SamuraiGameSession({
    required this.puzzle,
    required this.board,
    required this.notes,
    required this.hintedIndexes,
    required this.elapsedSeconds,
    required this.mistakes,
    required this.hintsUsed,
    required this.notesMode,
    required this.updatedAt,
  });

  final SamuraiPuzzle puzzle;
  final List<int> board;
  final Map<int, Set<int>> notes;
  final Set<int> hintedIndexes;
  final int elapsedSeconds;
  final int mistakes;
  final int hintsUsed;
  final bool notesMode;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'puzzle': <String, Object?>{
      'id': puzzle.id,
      'title': puzzle.title,
      'difficulty': puzzle.difficulty.name,
      'puzzle': puzzle.puzzle,
      'solution': puzzle.solution,
    },
    'board': board,
    'notes': <String, Object?>{
      for (final entry in notes.entries)
        '${entry.key}': entry.value.toList()..sort(),
    },
    'hintedIndexes': hintedIndexes.toList()..sort(),
    'elapsedSeconds': elapsedSeconds,
    'mistakes': mistakes,
    'hintsUsed': hintsUsed,
    'notesMode': notesMode,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory SamuraiGameSession.fromJson(Map<String, dynamic> json) {
    if ((json['version'] as num?)?.toInt() != 1) {
      throw const FormatException('Unsupported Samurai session version.');
    }
    final puzzleJson = (json['puzzle'] as Map?)?.cast<String, dynamic>();
    if (puzzleJson == null) {
      throw const FormatException('Missing Samurai puzzle.');
    }
    final difficultyName = puzzleJson['difficulty']?.toString();
    final difficulty = SudokuDifficulty.values.where(
      (value) => value.name == difficultyName,
    );
    if (difficulty.isEmpty) {
      throw const FormatException('Invalid Samurai difficulty.');
    }
    final puzzle = SamuraiPuzzle(
      id: puzzleJson['id']?.toString() ?? 'samurai-session',
      title: puzzleJson['title']?.toString() ?? 'Samurai Sudoku',
      difficulty: difficulty.first,
      puzzle: _intList(puzzleJson['puzzle']),
      solution: _intList(puzzleJson['solution']),
    );
    final board = _intList(json['board']);
    if (!SamuraiEngine.isPuzzleShapeValid(puzzle) ||
        board.length != SamuraiTopology.canvasCellCount) {
      throw const FormatException('Invalid Samurai session shape.');
    }
    for (var index = 0; index < board.length; index++) {
      final value = board[index];
      if (!SamuraiTopology.isActiveIndex(index)) {
        if (value != SamuraiTopology.inactiveCell) {
          throw const FormatException('Invalid inactive Samurai cell.');
        }
        continue;
      }
      if (value < 0 || value > 9) {
        throw const FormatException('Invalid Samurai board value.');
      }
      if (puzzle.puzzle[index] > 0 && value != puzzle.puzzle[index]) {
        throw const FormatException('Samurai clue was modified.');
      }
      if (value > 0 && value != puzzle.solution[index]) {
        throw const FormatException('Samurai session contains a wrong value.');
      }
    }

    final notesSource = (json['notes'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final notes = <int, Set<int>>{};
    for (final entry in notesSource.entries) {
      final index = int.tryParse(entry.key);
      if (index == null ||
          !SamuraiTopology.isActiveIndex(index) ||
          board[index] != 0) {
        continue;
      }
      final values = _intList(entry.value)
          .where((value) => value >= 1 && value <= 9)
          .toSet();
      if (values.isNotEmpty) notes[index] = values;
    }

    final hinted = _intList(json['hintedIndexes'])
        .where(SamuraiTopology.isActiveIndex)
        .where((index) => board[index] == puzzle.solution[index])
        .toSet();
    final updatedAt = DateTime.tryParse(json['updatedAt']?.toString() ?? '');

    return SamuraiGameSession(
      puzzle: puzzle,
      board: List<int>.unmodifiable(board),
      notes: Map<int, Set<int>>.unmodifiable(<int, Set<int>>{
        for (final entry in notes.entries)
          entry.key: Set<int>.unmodifiable(entry.value),
      }),
      hintedIndexes: Set<int>.unmodifiable(hinted),
      elapsedSeconds: ((json['elapsedSeconds'] as num?)?.toInt() ?? 0)
          .clamp(0, 24 * 60 * 60)
          .toInt(),
      mistakes: ((json['mistakes'] as num?)?.toInt() ?? 0)
          .clamp(0, 999)
          .toInt(),
      hintsUsed: ((json['hintsUsed'] as num?)?.toInt() ?? 0)
          .clamp(0, 369)
          .toInt(),
      notesMode: json['notesMode'] == true,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  static List<int> _intList(Object? value) {
    if (value is! List) return const <int>[];
    return value.map((item) => (item as num?)?.toInt() ?? -999).toList();
  }
}

class SamuraiGameSessionStore {
  SamuraiGameSessionStore._();

  static final SamuraiGameSessionStore instance = SamuraiGameSessionStore._();
  static const String _storageKey = 'active_samurai_game_session_v1';

  final ValueNotifier<SamuraiGameSession?> activeSession =
      ValueNotifier<SamuraiGameSession?>(null);

  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) {
      activeSession.value = null;
      return;
    }
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) throw const FormatException('Invalid session JSON.');
      activeSession.value = SamuraiGameSession.fromJson(
        decoded.cast<String, dynamic>(),
      );
    } catch (_) {
      await preferences.remove(_storageKey);
      activeSession.value = null;
    }
  }

  Future<void> save(SamuraiGameSession session) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(session.toJson()));
    activeSession.value = session;
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
    activeSession.value = null;
  }
}
