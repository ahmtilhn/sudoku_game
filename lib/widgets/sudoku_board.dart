import 'package:flutter/material.dart';

import '../domain/sudoku.dart';
import '../localization/app_strings.dart';

class SudokuBoard extends StatelessWidget {
  const SudokuBoard({
    super.key,
    required this.puzzle,
    required this.board,
    required this.selectedIndex,
    required this.onCellTap,
    this.notes = const <int, Set<int>>{},
    this.errorIndex,
    this.hintedIndexes = const <int>{},
    this.localMoveIndexes = const <int>{},
    this.opponentMoveIndexes = const <int>{},
    this.enabled = true,
  });

  final SudokuPuzzle puzzle;
  final List<int> board;
  final int? selectedIndex;
  final ValueChanged<int> onCellTap;
  final Map<int, Set<int>> notes;
  final int? errorIndex;
  final Set<int> hintedIndexes;
  final Set<int> localMoveIndexes;
  final Set<int> opponentMoveIndexes;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedValue = selectedIndex == null ? 0 : board[selectedIndex!];
    final matchingValueBackground = Color.alphaBlend(
      scheme.secondaryContainer.withAlpha(105),
      scheme.surface,
    );

    return Semantics(
      label: context.tr('board_label', <Object>[puzzle.size]),
      child: AspectRatio(
        aspectRatio: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.onSurface, width: 2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: puzzle.size,
              ),
              itemCount: puzzle.cellCount,
              itemBuilder: (context, index) {
                final value = board[index];
                final row = index ~/ puzzle.size;
                final column = index % puzzle.size;
                final selected = selectedIndex == index;
                final hinted = hintedIndexes.contains(index);
                final localMove = localMoveIndexes.contains(index);
                final opponentMove = opponentMoveIndexes.contains(index);
                final fixed = puzzle.isFixed(index);
                final locked = fixed || hinted;
                final related =
                    selectedIndex != null &&
                    (selectedIndex! ~/ puzzle.size == row ||
                        selectedIndex! % puzzle.size == column ||
                        SudokuEngine.relatedBoxIndex(puzzle, selectedIndex!) ==
                            SudokuEngine.relatedBoxIndex(puzzle, index));
                final sameValue = selectedValue != 0 && value == selectedValue;
                final background = errorIndex == index
                    ? scheme.errorContainer
                    : selected
                    ? scheme.primaryContainer
                    : localMove
                    ? Color.alphaBlend(
                        scheme.primary.withAlpha(45),
                        scheme.surface,
                      )
                    : opponentMove
                    ? Color.alphaBlend(
                        scheme.tertiary.withAlpha(45),
                        scheme.surface,
                      )
                    : hinted
                    ? scheme.tertiaryContainer
                    : sameValue
                    ? matchingValueBackground
                    : related
                    ? scheme.surfaceContainerHighest
                    : scheme.surface;

                return Semantics(
                  button: !locked,
                  selected: selected,
                  label: context.tr('cell_label', <Object>[
                    row + 1,
                    column + 1,
                    value == 0 ? context.tr('empty') : value,
                  ]),
                  child: InkWell(
                    key: ValueKey<String>('sudoku-cell-$index'),
                    onTap: enabled ? () => onCellTap(index) : null,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: background,
                            border: Border(
                              top: selected || errorIndex == index
                                  ? BorderSide(
                                      color: errorIndex == index
                                          ? scheme.error
                                          : scheme.primary,
                                      width: 1.4,
                                    )
                                  : BorderSide.none,
                              left: selected || errorIndex == index
                                  ? BorderSide(
                                      color: errorIndex == index
                                          ? scheme.error
                                          : scheme.primary,
                                      width: 1.4,
                                    )
                                  : BorderSide.none,
                              right: BorderSide(
                                color: scheme.outline,
                                width:
                                    (column + 1) % puzzle.boxColumns == 0 &&
                                        column != puzzle.size - 1
                                    ? 1.8
                                    : 0.35,
                              ),
                              bottom: BorderSide(
                                color: scheme.outline,
                                width:
                                    (row + 1) % puzzle.boxRows == 0 &&
                                        row != puzzle.size - 1
                                    ? 1.8
                                    : 0.35,
                              ),
                            ),
                          ),
                          child: value == 0
                              ? _NotesCell(
                                  values: notes[index] ?? const <int>{},
                                  size: puzzle.size,
                                )
                              : Center(
                                  child: Text(
                                    '$value',
                                    style: TextStyle(
                                      fontSize: puzzle.size == 9 ? 25 : 34,
                                      fontWeight: locked
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      color: hinted
                                          ? scheme.onTertiaryContainer
                                          : fixed
                                          ? scheme.onSurface
                                          : scheme.primary,
                                    ),
                                  ),
                                ),
                        ),
                        if (errorIndex == index)
                          Align(
                            alignment: Alignment.topRight,
                            child: Icon(
                              Icons.error_rounded,
                              size: puzzle.size == 9 ? 12 : 16,
                              color: scheme.error,
                            ),
                          )
                        else if (localMove || opponentMove)
                          Align(
                            alignment: Alignment.topRight,
                            child: Icon(
                              localMove
                                  ? Icons.check_circle_rounded
                                  : Icons.north_east_rounded,
                              size: puzzle.size == 9 ? 11 : 15,
                              color: localMove
                                  ? scheme.primary
                                  : scheme.tertiary,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NotesCell extends StatelessWidget {
  const _NotesCell({required this.values, required this.size});

  final Set<int> values;
  final int size;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(2),
      child: GridView.count(
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: size == 4 ? 2 : 3,
        children: [
          for (var value = 1; value <= size; value++)
            Center(
              child: Text(
                values.contains(value) ? '$value' : '',
                style: TextStyle(fontSize: size == 9 ? 9 : 12),
              ),
            ),
        ],
      ),
    );
  }
}
