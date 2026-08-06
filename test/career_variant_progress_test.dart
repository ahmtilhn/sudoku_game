import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/data/local_progress_store.dart';
import 'package:sudoku_game/domain/sudoku_variant.dart';

void main() {
  test('classic9 and classic16 career progress stay independent', () async {
    final store = await LocalProgressStore.createInMemory();

    await store.recordResult(
      puzzleId: 'career-001',
      seconds: 90,
      mistakes: 0,
      hints: 0,
      variant: SudokuVariant.classic9,
    );
    await store.recordResult(
      puzzleId: 'career-001',
      seconds: 240,
      mistakes: 2,
      hints: 1,
      variant: SudokuVariant.classic16,
    );

    expect(
      store.progressForCareerLevel(
        1,
        variant: SudokuVariant.classic9,
      )?.stars,
      3,
    );
    expect(
      store.progressForCareerLevel(
        1,
        variant: SudokuVariant.classic16,
      )?.stars,
      2,
    );
    expect(store.completedCareerLevelCountFor(SudokuVariant.classic9), 1);
    expect(store.completedCareerLevelCountFor(SudokuVariant.classic16), 1);
    expect(store.nextCareerLevelNumberFor(SudokuVariant.classic9), 2);
    expect(store.nextCareerLevelNumberFor(SudokuVariant.classic16), 2);
  });

  test('legacy career_progress_v1 migrates to classic9 only', () async {
    final store = await LocalProgressStore.createInMemory(
      initialValues: <String, Object>{
        'career_progress_v1': jsonEncode(<String, Object>{
          'career-001': <String, Object>{
            'stars': 3,
            'bestSeconds': 80,
            'bestMistakes': 0,
          },
        }),
      },
    );

    expect(store.completedCareerLevelCountFor(SudokuVariant.classic9), 1);
    expect(store.completedCareerLevelCountFor(SudokuVariant.classic16), 0);
    expect(
      store.progressForCareerLevel(
        1,
        variant: SudokuVariant.classic9,
      )?.bestSeconds,
      80,
    );
    expect(
      store.progressForCareerLevel(
        1,
        variant: SudokuVariant.classic16,
      ),
      isNull,
    );
  });

  test('variant rewards and clearing do not affect the other board', () async {
    final store = await LocalProgressStore.createInMemory();
    for (final variant in SudokuVariant.values) {
      await store.recordResult(
        puzzleId: 'career-001',
        seconds: variant.boardSize * 10,
        mistakes: 0,
        hints: 0,
        variant: variant,
      );
    }

    await store.markCareerRewardClaimed(
      levelNumber: 1,
      variant: SudokuVariant.classic16,
    );
    expect(
      store.progressForCareerLevel(
        1,
        variant: SudokuVariant.classic16,
      )?.rewardClaimed,
      isTrue,
    );
    expect(
      store.progressForCareerLevel(
        1,
        variant: SudokuVariant.classic9,
      )?.rewardClaimed,
      isFalse,
    );

    await store.clearProgressForVariant(SudokuVariant.classic16);
    expect(store.completedCareerLevelCountFor(SudokuVariant.classic16), 0);
    expect(store.completedCareerLevelCountFor(SudokuVariant.classic9), 1);
  });
}
