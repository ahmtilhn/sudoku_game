import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/domain/sudoku.dart';
import 'package:sudoku_game/domain/sudoku_variant.dart';

void main() {
  group('SudokuVariant', () {
    test('classic9 exposes its complete contract', () {
      const variant = SudokuVariant.classic9;

      expect(variant.key, 'classic9');
      expect(variant.boardSize, 9);
      expect(variant.boxRows, 3);
      expect(variant.boxColumns, 3);
      expect(variant.cellCount, 81);
      expect(variant.availableValues, List<int>.generate(9, (index) => index + 1));
      expect(variant.careerSupport, isTrue);
      expect(variant.onlineSupport, isTrue);
      expect(variant.persistenceKey, 'classic9');
    });

    test('classic16 uses numeric values 1 through 16', () {
      const variant = SudokuVariant.classic16;

      expect(variant.key, 'classic16');
      expect(variant.boardSize, 16);
      expect(variant.boxRows, 4);
      expect(variant.boxColumns, 4);
      expect(variant.cellCount, 256);
      expect(
        variant.availableValues,
        List<int>.generate(16, (index) => index + 1),
      );
      expect(variant.zoomSupport, isTrue);
      expect(variant.careerSupport, isTrue);
      expect(variant.onlineSupport, isTrue);
      expect(variant.persistenceKey, 'classic16');
    });

    test('board and payload validation are dynamic', () {
      const nine = SudokuVariant.classic9;
      const sixteen = SudokuVariant.classic16;

      expect(nine.supportsCellIndex(80), isTrue);
      expect(nine.supportsCellIndex(81), isFalse);
      expect(sixteen.supportsCellIndex(255), isTrue);
      expect(sixteen.supportsCellIndex(256), isFalse);
      expect(sixteen.supportsValue(16), isTrue);
      expect(sixteen.supportsValue(17), isFalse);
      expect(sixteen.toJson()['cellCount'], 256);
    });

    test('puzzle resolves its variant from board size', () {
      final puzzle = SudokuPuzzle(
        id: 'variant-test',
        difficulty: SudokuDifficulty.medium,
        puzzle: List<int>.filled(256, 0),
        solution: List<int>.generate(256, (index) => (index % 16) + 1),
        size: 16,
        boxRows: 4,
        boxColumns: 4,
      );

      expect(puzzle.variant, same(SudokuVariant.classic16));
      expect(SudokuVariant.fromKey('classic9'), same(SudokuVariant.classic9));
      expect(SudokuVariant.fromBoardSize(16), same(SudokuVariant.classic16));
    });
  });
}
