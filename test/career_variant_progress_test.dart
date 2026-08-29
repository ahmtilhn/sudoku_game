import 'dart:convert';
import 'dart:io';

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
      store.progressForCareerLevel(1, variant: SudokuVariant.classic9)?.stars,
      3,
    );
    expect(
      store.progressForCareerLevel(1, variant: SudokuVariant.classic16)?.stars,
      2,
    );
    expect(store.completedCareerLevelCountFor(SudokuVariant.classic9), 1);
    expect(store.completedCareerLevelCountFor(SudokuVariant.classic16), 1);
    expect(store.nextCareerLevelNumberFor(SudokuVariant.classic9), 2);
    expect(store.nextCareerLevelNumberFor(SudokuVariant.classic16), 2);
  });

  test('runtime career-1 result unlocks level 2 and exposes stars', () async {
    final store = await LocalProgressStore.createInMemory();

    await store.recordResult(
      puzzleId: 'career-1',
      seconds: 75,
      mistakes: 0,
      hints: 0,
      variant: SudokuVariant.classic9,
    );

    expect(store.isCareerLevelUnlocked(2), isTrue);
    expect(store.nextCareerLevelNumberFor(SudokuVariant.classic9), 2);
    expect(store.progressForCareerLevel(1)?.stars, 3);
    expect(store.progressFor('career-001')?.stars, 3);
    expect(store.progressFor('career-1')?.stars, 3);
  });

  test('unpadded v2 progress migrates without duplicate levels', () async {
    final store = await LocalProgressStore.createInMemory(
      initialValues: <String, Object>{
        'career_progress_v2': jsonEncode(<String, Object>{
          'classic9:career-1': <String, Object>{
            'stars': 2,
            'bestSeconds': 100,
            'bestMistakes': 1,
            'bestHints': 1,
          },
          'classic9:career-001': <String, Object>{
            'stars': 3,
            'bestSeconds': 90,
            'bestMistakes': 0,
            'bestHints': 0,
          },
        }),
      },
    );

    expect(store.completedCareerLevelCountFor(SudokuVariant.classic9), 1);
    expect(store.nextCareerLevelNumberFor(SudokuVariant.classic9), 2);
    expect(store.progressForCareerLevel(1)?.stars, 3);
    expect(store.progressForCareerLevel(1)?.bestSeconds, 90);
    expect(store.isCareerLevelUnlocked(2), isTrue);
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
      store
          .progressForCareerLevel(1, variant: SudokuVariant.classic9)
          ?.bestSeconds,
      80,
    );
    expect(
      store.progressForCareerLevel(1, variant: SudokuVariant.classic16),
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
      store
          .progressForCareerLevel(1, variant: SudokuVariant.classic16)
          ?.rewardClaimed,
      isTrue,
    );
    expect(
      store
          .progressForCareerLevel(1, variant: SudokuVariant.classic9)
          ?.rewardClaimed,
      isFalse,
    );

    await store.clearProgressForVariant(SudokuVariant.classic16);
    expect(store.completedCareerLevelCountFor(SudokuVariant.classic16), 0);
    expect(store.completedCareerLevelCountFor(SudokuVariant.classic9), 1);
  });

  test('career hub exposes 16x16 career and records variant progress', () {
    final source = File(
      'lib/features/career/career_hub_screen.dart',
    ).readAsStringSync();

    expect(source, contains('_CareerVariantSelector'));
    expect(source, contains('_CareerVariantCard'));
    expect(source, contains('_CareerHeaderControls'));
    expect(source, isNot(contains('bottom: TabBar(')));
    expect(source, isNot(contains('appBar: AppBar(')));
    expect(source, contains('return Row('));
    expect(source, contains('final pageSize = columns * rows;'));
    expect(source, contains('_CareerChapterBar('));
    expect(source, contains('_CareerPager('));
    expect(
      source,
      contains('physics: const NeverScrollableScrollPhysics()'),
    );
    expect(source, isNot(contains('ListView(')));
    expect(source, contains('SudokuVariantId.classic16'));
    expect(source, contains('Classic16PuzzleFactory.generate'));
    expect(source, contains('nextCareerLevelNumberFor(variant)'));
    expect(source, contains('recordResult('));
    expect(source, contains('variant: variant'));
    expect(source, isNot(contains('maxStars')));
  });

  test('feature screens do not reintroduce scaffold app bars', () {
    final sourceFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in sourceFiles) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('appBar:')));
      expect(source, isNot(contains('AppBar(')));
    }
  });
}
