import '../domain/sudoku.dart';

class PuzzleCatalog {
  const PuzzleCatalog._();

  static final List<SudokuPuzzle> careerPuzzles = _buildCareerPuzzles();

  static SudokuPuzzle dailyPuzzle(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    final seed = normalized.difference(DateTime(2025)).inDays.abs();
    final source = careerPuzzles[seed % careerPuzzles.length];
    return source.copyWith(
      id: 'daily-${normalized.toIso8601String().split('T').first}',
      title: 'Daily Sudoku',
    );
  }

  static SudokuPuzzle duelPuzzle({int seed = 0}) {
    final candidates = careerPuzzles
        .where((puzzle) => puzzle.difficulty == SudokuDifficulty.easy)
        .toList(growable: false);
    return candidates[seed.abs() % candidates.length].copyWith(
      id: 'duel-${seed.abs() % candidates.length}',
      title: 'Local Duel',
    );
  }

  static const SudokuPuzzle tutorialPuzzle = SudokuPuzzle(
    id: 'tutorial-4x4',
    title: 'Mini Sudoku',
    difficulty: SudokuDifficulty.beginner,
    size: 4,
    boxRows: 2,
    boxColumns: 2,
    puzzle: <int>[1, 0, 0, 4, 0, 4, 1, 0, 0, 1, 4, 0, 4, 0, 0, 1],
    solution: <int>[1, 2, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1],
  );

  static List<SudokuPuzzle> _buildCareerPuzzles() {
    final result = <SudokuPuzzle>[];
    final definitions = <_PuzzleDefinition>[
      const _PuzzleDefinition(
        difficulty: SudokuDifficulty.beginner,
        puzzle:
            '530678012602195308198042067850761023420853701713024806961037280280419635045086179',
        solution:
            '534678912672195348198342567859761423426853791713924856961537284287419635345286179',
      ),
      const _PuzzleDefinition(
        difficulty: SudokuDifficulty.easy,
        puzzle:
            '530070000600195000098000060800060003400803001700020006060000280000419005000080079',
        solution:
            '534678912672195348198342567859761423426853791713924856961537284287419635345286179',
      ),
      const _PuzzleDefinition(
        difficulty: SudokuDifficulty.medium,
        puzzle:
            '003020600900305001001806400008102900700000008006708200002609500800203009005010300',
        solution:
            '483921657967345821251876493548132976729564138136798245372689514814253769695417382',
      ),
      const _PuzzleDefinition(
        difficulty: SudokuDifficulty.hard,
        puzzle:
            '200080300060070084030500209000105408000000000402706000301007040720040060004010003',
        solution:
            '245981376169273584837564219976125438513498627482736951391657842728349165654812793',
      ),
      const _PuzzleDefinition(
        difficulty: SudokuDifficulty.expert,
        puzzle:
            '100007090030020008009600500005300900010080002600004000300000010040000007007000300',
        solution:
            '162857493534129678789643521475312986913586742628794135356478219241935867897261354',
      ),
    ];

    for (final definition in definitions) {
      for (var variant = 0; variant < 6; variant++) {
        final transformed = _transform(
          definition.puzzle,
          definition.solution,
          rotation: variant % 4,
          transpose: variant.isOdd,
          digitShift: variant,
        );
        result.add(
          SudokuPuzzle(
            id: '${definition.difficulty.name}-${variant + 1}',
            title: '${definition.difficulty.label} ${variant + 1}',
            difficulty: definition.difficulty,
            puzzle: transformed.$1,
            solution: transformed.$2,
          ),
        );
      }
    }
    return result;
  }

  static (List<int>, List<int>) _transform(
    String puzzle,
    String solution, {
    required int rotation,
    required bool transpose,
    required int digitShift,
  }) {
    var puzzleValues = _parse(puzzle);
    var solutionValues = _parse(solution);

    List<int> transformGrid(List<int> source) {
      var current = List<int>.from(source);
      if (transpose) {
        current = List<int>.generate(81, (index) {
          final row = index ~/ 9;
          final column = index % 9;
          return source[column * 9 + row];
        });
      }
      for (var turn = 0; turn < rotation; turn++) {
        final previous = current;
        current = List<int>.generate(81, (index) {
          final row = index ~/ 9;
          final column = index % 9;
          return previous[(8 - column) * 9 + row];
        });
      }
      if (digitShift > 0) {
        current = current
<<<<<<< HEAD
            .map((value) => value == 0 ? 0 : ((value - 1 + digitShift) % 9) + 1)
=======
            .map(
              (value) =>
                  value == 0 ? 0 : ((value - 1 + digitShift) % 9) + 1,
            )
>>>>>>> 8fe6ccd91d5db3ce3d8e23617e404a1b183eb2fe
            .toList(growable: false);
      }
      return current;
    }

    puzzleValues = transformGrid(puzzleValues);
    solutionValues = transformGrid(solutionValues);
    return (puzzleValues, solutionValues);
  }

  static List<int> _parse(String source) => source
      .split('')
      .map((character) => int.parse(character))
      .toList(growable: false);
}

class _PuzzleDefinition {
  const _PuzzleDefinition({
    required this.difficulty,
    required this.puzzle,
    required this.solution,
  });

  final SudokuDifficulty difficulty;
  final String puzzle;
  final String solution;
}
