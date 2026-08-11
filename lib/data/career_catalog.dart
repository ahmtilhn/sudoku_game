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
    this.isEndless = false,
  });

  final String id;
  final int number;
  final int chapter;
  final int chapterLevel;
  final SudokuDifficulty difficulty;
  final int size;
  final int seed;
  final bool isEndless;

  bool get isChapterStart => chapterLevel == 1;

  int get coinReward => switch (difficulty) {
    SudokuDifficulty.beginner => 20,
    SudokuDifficulty.easy => 25,
    SudokuDifficulty.medium => 35,
    SudokuDifficulty.hard => 40,
    SudokuDifficulty.expert => 50,
  };

  int get hintReward => chapterLevel == 10 ? 2 : chapterLevel == 5 ? 1 : 0;
}

class CareerCatalog {
  const CareerCatalog._();

  static const int designedLevelCount = 50;
  static const int _endlessSeedOffset = 7_000_000;
  static const int _endlessSeedStep = 104_729;

  static final List<CareerLevel> levels = List<CareerLevel>.unmodifiable(
    _buildDesignedLevels(),
  );

  static final Map<String, SudokuPuzzle> _puzzleCache =
      <String, SudokuPuzzle>{};

  static String idForLevel(int number) {
    if (number < 1) {
      throw ArgumentError.value(number, 'number', 'Must be at least 1.');
    }
    return 'career-${number.toString().padLeft(3, '0')}';
  }

  static int? numberFromId(String id) {
    if (!id.startsWith('career-')) return null;
    return int.tryParse(id.substring('career-'.length));
  }

  static CareerLevel levelAt(int number) {
    if (number < 1) {
      throw ArgumentError.value(number, 'number', 'Must be at least 1.');
    }
    if (number <= designedLevelCount) return levels[number - 1];

    final endlessIndex = number - designedLevelCount - 1;
    return CareerLevel(
      id: idForLevel(number),
      number: number,
      chapter: 6 + endlessIndex ~/ 10,
      chapterLevel: endlessIndex % 10 + 1,
      difficulty: SudokuDifficulty.expert,
      size: 9,
      seed: _endlessSeedOffset + number * _endlessSeedStep,
      isEndless: true,
    );
  }

  static List<CareerLevel> levelsThrough(int number) {
    if (number < 1) return const <CareerLevel>[];
    return List<CareerLevel>.unmodifiable(
      List<CareerLevel>.generate(number, (index) => levelAt(index + 1)),
    );
  }

  static CareerLevel? byId(String id) {
    final number = numberFromId(id);
    return number == null || number < 1 ? null : levelAt(number);
  }

  static List<CareerLevel> chapterLevels(int chapter) {
    return List<CareerLevel>.unmodifiable(
      levels.where((level) => level.chapter == chapter),
    );
  }

  static CareerLevel? previousOf(CareerLevel level) {
    return level.number <= 1 ? null : levelAt(level.number - 1);
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
    final attempts = level.size == 4 || level.isEndless ? 1 : 8;
    for (var attempt = 0; attempt < attempts; attempt++) {
      final generated = SudokuEngine.generate(
        difficulty: level.difficulty,
        size: level.size,
        seed: level.seed + attempt * 101,
      );
      if (level.size == 4 || level.isEndless) {
        return _withCareerId(generated, level);
      }

      final analysis = SudokuDifficultyAnalyzer.analyze(generated);
      final distance =
          (analysis.difficulty.index - level.difficulty.index).abs();
      if (distance < closestDistance) {
        closest = generated;
        closestDistance = distance;
      }
      if (analysis.difficulty == level.difficulty) {
        return _withCareerId(generated, level);
      }
    }
    return _withCareerId(closest!, level);
  }

  static SudokuPuzzle _withCareerId(
    SudokuPuzzle source,
    CareerLevel level,
  ) {
    return SudokuPuzzle(
      id: level.id,
      title: source.title,
      difficulty: source.difficulty,
      puzzle: List<int>.unmodifiable(source.puzzle),
      solution: List<int>.unmodifiable(source.solution),
      size: source.size,
      boxRows: source.boxRows,
      boxColumns: source.boxColumns,
    );
  }

  static List<CareerLevel> _buildDesignedLevels() {
    final result = <CareerLevel>[];
    var global = 1;
    for (var chapter = 1; chapter <= 5; chapter++) {
      final difficulty = SudokuDifficulty.values[chapter - 1];
      for (var chapterLevel = 1; chapterLevel <= 10; chapterLevel++) {
        result.add(
          CareerLevel(
            id: idForLevel(global),
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
