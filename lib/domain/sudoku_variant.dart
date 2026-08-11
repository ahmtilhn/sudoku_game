import 'sudoku.dart';

enum SudokuVariantId { classic9, classic16 }

class SudokuVariant {
  const SudokuVariant({
    required this.id,
    required this.boardSize,
    required this.boxRows,
    required this.boxColumns,
    required this.availableValues,
    required this.minimumCellSize,
    required this.zoomSupport,
    required this.careerSupport,
    required this.onlineSupport,
    required this.persistenceKey,
    required this.statsCategory,
    required this.achievementCategory,
  });

  final SudokuVariantId id;
  final int boardSize;
  final int boxRows;
  final int boxColumns;
  final List<int> availableValues;
  final double minimumCellSize;
  final bool zoomSupport;
  final bool careerSupport;
  final bool onlineSupport;
  final String persistenceKey;
  final String statsCategory;
  final String achievementCategory;

  int get cellCount => boardSize * boardSize;
  String get key => id.name;
  String get label => '$boardSize×$boardSize';

  bool supportsValue(int value) => availableValues.contains(value);
  bool supportsCellIndex(int index) => index >= 0 && index < cellCount;

  Map<String, Object> toJson() => <String, Object>{
    'variant': key,
    'boardSize': boardSize,
    'cellCount': cellCount,
    'boxRows': boxRows,
    'boxColumns': boxColumns,
  };

  static const SudokuVariant classic9 = SudokuVariant(
    id: SudokuVariantId.classic9,
    boardSize: 9,
    boxRows: 3,
    boxColumns: 3,
    availableValues: <int>[1, 2, 3, 4, 5, 6, 7, 8, 9],
    minimumCellSize: 36,
    zoomSupport: false,
    careerSupport: true,
    onlineSupport: true,
    persistenceKey: 'classic9',
    statsCategory: 'classic9',
    achievementCategory: 'classic9',
  );

  static const SudokuVariant classic16 = SudokuVariant(
    id: SudokuVariantId.classic16,
    boardSize: 16,
    boxRows: 4,
    boxColumns: 4,
    availableValues: <int>[
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
      11,
      12,
      13,
      14,
      15,
      16,
    ],
    minimumCellSize: 30,
    zoomSupport: true,
    careerSupport: true,
    onlineSupport: true,
    persistenceKey: 'classic16',
    statsCategory: 'classic16',
    achievementCategory: 'classic16',
  );

  static const List<SudokuVariant> values = <SudokuVariant>[
    classic9,
    classic16,
  ];

  static SudokuVariant fromBoardSize(int boardSize) => switch (boardSize) {
    9 => classic9,
    16 => classic16,
    _ => throw ArgumentError.value(
      boardSize,
      'boardSize',
      'Supported Sudoku board sizes are 9 and 16.',
    ),
  };

  static SudokuVariant fromKey(String key) {
    final normalized = key.trim().toLowerCase();
    if (normalized == 'classic' ||
        normalized == 'classic_9' ||
        normalized == '9x9') {
      return classic9;
    }
    if (normalized == 'classic_16' || normalized == '16x16') {
      return classic16;
    }
    for (final variant in values) {
      if (variant.key.toLowerCase() == normalized ||
          variant.persistenceKey.toLowerCase() == normalized) {
        return variant;
      }
    }
    throw ArgumentError.value(
      key,
      'key',
      'Supported Sudoku variants are classic9 and classic16.',
    );
  }
}

extension SudokuPuzzleVariant on SudokuPuzzle {
  SudokuVariant get variant => SudokuVariant.fromBoardSize(size);
}
