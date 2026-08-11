import '../domain/sudoku.dart';

class FantasySudokuCatalog {
  const FantasySudokuCatalog._();

  static SudokuPuzzle puzzleForSeed(int seed) {
    final normalizedSeed = seed.abs();
    final rotation = normalizedSeed % 4;
    final symbolShift = (normalizedSeed ~/ 4) % 16;

    List<int> transform(List<int> source) {
      return List<int>.generate(256, (targetIndex) {
        final row = targetIndex ~/ 16;
        final column = targetIndex % 16;
        final sourcePosition = switch (rotation) {
          0 => (row, column),
          1 => (15 - column, row),
          2 => (15 - row, 15 - column),
          _ => (column, 15 - row),
        };
        final sourceIndex = sourcePosition.$1 * 16 + sourcePosition.$2;
        final value = source[sourceIndex];
        if (value == 0) return 0;
        return ((value - 1 + symbolShift) % 16) + 1;
      }, growable: false);
    }

    return SudokuPuzzle(
      id: 'fantasy-16-$normalizedSeed',
      title: '16×16 Fantasy',
      difficulty: SudokuDifficulty.expert,
      puzzle: List<int>.unmodifiable(transform(_basePuzzle)),
      solution: List<int>.unmodifiable(transform(_baseSolution)),
      size: 16,
      boxRows: 4,
      boxColumns: 4,
    );
  }

  // Generated from the same Sudoku rules as the production engine and
  // verified to have exactly one solution. Transformations above preserve
  // row, column, 4×4-box validity and uniqueness.
  static const List<int> _basePuzzle = <int>[
    1,2,3,4,0,0,7,0,0,0,11,0,13,0,0,16,
    0,0,0,8,9,0,0,12,0,14,0,16,0,0,3,4,
    0,10,0,0,0,14,15,0,1,2,3,0,5,6,7,8,
    13,14,0,0,1,2,0,4,0,0,7,8,0,0,0,0,
    0,3,4,0,6,7,0,0,0,11,0,0,14,15,0,0,
    0,0,8,0,10,0,12,13,0,15,16,0,0,0,4,5,
    10,0,12,13,0,0,0,0,0,3,4,0,0,0,8,9,
    0,15,0,0,0,3,0,0,6,0,0,9,0,0,0,13,
    0,4,5,0,7,0,9,10,0,0,13,0,0,16,1,2,
    7,0,0,10,11,12,13,0,15,0,0,0,3,0,0,0,
    11,0,0,0,0,16,0,2,0,4,0,6,0,0,9,0,
    15,16,0,0,0,4,0,6,7,0,9,10,11,0,13,0,
    0,5,6,0,0,9,0,11,0,0,0,15,16,1,0,0,
    0,9,0,11,12,13,14,0,0,0,2,0,4,0,0,7,
    12,0,0,0,16,0,2,0,0,0,0,0,0,0,10,0,
    0,1,2,0,0,0,0,0,8,0,0,11,0,13,14,15,
  ];

  static const List<int> _baseSolution = <int>[
    1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,
    5,6,7,8,9,10,11,12,13,14,15,16,1,2,3,4,
    9,10,11,12,13,14,15,16,1,2,3,4,5,6,7,8,
    13,14,15,16,1,2,3,4,5,6,7,8,9,10,11,12,
    2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,1,
    6,7,8,9,10,11,12,13,14,15,16,1,2,3,4,5,
    10,11,12,13,14,15,16,1,2,3,4,5,6,7,8,9,
    14,15,16,1,2,3,4,5,6,7,8,9,10,11,12,13,
    3,4,5,6,7,8,9,10,11,12,13,14,15,16,1,2,
    7,8,9,10,11,12,13,14,15,16,1,2,3,4,5,6,
    11,12,13,14,15,16,1,2,3,4,5,6,7,8,9,10,
    15,16,1,2,3,4,5,6,7,8,9,10,11,12,13,14,
    4,5,6,7,8,9,10,11,12,13,14,15,16,1,2,3,
    8,9,10,11,12,13,14,15,16,1,2,3,4,5,6,7,
    12,13,14,15,16,1,2,3,4,5,6,7,8,9,10,11,
    16,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,
  ];
}
