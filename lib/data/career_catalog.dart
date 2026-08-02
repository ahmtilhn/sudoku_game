import '../domain/sudoku.dart';
import '../domain/sudoku_difficulty_analyzer.dart';

class CareerLevel {
  const CareerLevel({
    required this.id,
    required this.number,
    required this.chapter,
    required this.chapterLevel,
    required this.difficulty,
    required this.size,
    required this.seed,
  });

  final String id;
  final int number;
  final int chapter;
  final int chapterLevel;
  final SudokuDifficulty difficulty;
  final int size;
  final int seed;

  bool get isChapterStart => chapterLevel == 1;

  int get coinReward => switch (difficulty) {
    SudokuDifficulty.beginner => 10,
    SudokuDifficulty.easy => 15,
    SudokuDifficulty.medium => 20,
    SudokuDifficulty.hard => 30,
    SudokuDifficulty.expert => 45,
  };

  int get hintReward => chapterLevel == 10 ? 2 : chapterLevel == 5 ? 1 : 0;
}

class CareerCatalog {
  const CareerCatalog._();

  static final List<CareerLevel> levels = List<CareerLevel>.unmodifiable(
    _buildLevels(),
  );
  static final Map<String, SudokuPuzzle> _puzzleCache =
      <String, SudokuPuzzle>{};

  static CareerLevel? byId(String id) {
    for (final level in levels) {
      if (level.id == id) return level;
    }
    return null;
  }

  static List<CareerLevel> chapterLevels(int chapter) {
    return List<CareerLevel>.unmodifiable(
      levels.where((level) => level.chapter == chapter),
    );
  }

  static CareerLevel? previousOf(CareerLevel level) {
    final index = levels.indexWhere((item) => item.id == level.id);
    return index <= 0 ? null : levels[index - 1];
  }

  static CareerLevel? nextOf(CareerLevel level) {
    final index = levels.indexWhere((item) => item.id == level.id);
    if (index < 0 || index >= levels.length - 1) return null;
    return levels[index + 1];
  }

  static bool isUnlocked(
    CareerLevel level,
    bool Function(String levelId) isCompleted,
  ) {
    if (level.number == 1) return true;
    final previous = previousOf(level);
    return previous != null && isCompleted(previous.id);
  }

  static CareerLevel? firstPlayable(
    bool Function(String levelId) isCompleted,
  ) {
    for (final level in levels) {
      if (!isCompleted(level.id) && isUnlocked(level, isCompleted)) {
        return level;
      }
    }
    return null;
  }

  static SudokuPuzzle puzzleFor(CareerLevel level) {
    return _puzzleCache.putIfAbsent(level.id, () => _generate(level));
  }

  static SudokuPuzzle _generate(CareerLevel level) {
    SudokuPuzzle? closest;
    var closestDistance = 100;
    final attempts = level.size == 4 ? 1 : 8;
    for (var attempt = 0; attempt < attempts; attempt++) {
      final generated = SudokuEngine.generate(
        difficulty: level.difficulty,
        size: level.size,
        seed: level.seed + attempt * 101,
      );
      if (level.size == 4) return _withCareerId(generated, level.id);

      final analysis = SudokuDifficultyAnalyzer.analyze(generated);
      final distance =
          (analysis.difficulty.index - level.difficulty.index).abs();
      if (distance < closestDistance) {
        closest = generated;
        closestDistance = distance;
      }
      if (analysis.difficulty == level.difficulty) {
        return _withCareerId(generated, level.id);
      }
    }
    return _withCareerId(closest!, level.id);
  }

  static SudokuPuzzle _withCareerId(SudokuPuzzle source, String id) {
    return SudokuPuzzle(
      id: id,
      title: source.title,
      difficulty: source.difficulty,
      puzzle: List<int>.unmodifiable(source.puzzle),
      solution: List<int>.unmodifiable(source.solution),
      size: source.size,
      boxRows: source.boxRows,
      boxColumns: source.boxColumns,
    );
  }

  static List<CareerLevel> _buildLevels() {
    final result = <CareerLevel>[];
    var global = 1;
    for (var chapter = 1; chapter <= 5; chapter++) {
      final difficulty = SudokuDifficulty.values[chapter - 1];
      for (var chapterLevel = 1; chapterLevel <= 10; chapterLevel++) {
        result.add(
          CareerLevel(
            id: 'career-${global.toString().padLeft(3, '0')}',
            number: global,
            chapter: chapter,
            chapterLevel: chapterLevel,
            difficulty: difficulty,
            size: chapter == 1 && chapterLevel <= 5 ? 4 : 9,
            seed: chapter * 10_000 + chapterLevel * 317,
          ),
        );
        global++;
      }
    }
    return result;
  }
}
