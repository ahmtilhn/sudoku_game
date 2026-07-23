import 'package:flutter/material.dart';

import '../domain/sudoku.dart';

class SudokuBoard extends StatelessWidget {
  const SudokuBoard({
    super.key,
    required this.puzzle,
    required this.board,
    required this.selectedIndex,
    required this.onCellTap,
    this.notes = const <int, Set<int>>{},
    this.errorIndex,
    this.enabled = true,
  });

  final SudokuPuzzle puzzle;
  final List<int> board;
  final int? selectedIndex;
  final ValueChanged<int> onCellTap;
  final Map<int, Set<int>> notes;
  final int? errorIndex;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedValue = selectedIndex == null ? 0 : board[selectedIndex!];
    return Semantics(
      label: '${puzzle.size} çarpı ${puzzle.size} Sudoku tahtası',
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
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: puzzle.size),
              itemCount: puzzle.cellCount,
              itemBuilder: (context, index) {
                final value = board[index];
                final row = index ~/ puzzle.size;
                final column = index % puzzle.size;
                final selected = selectedIndex == index;
                final related = selectedIndex != null &&
                    (selectedIndex! ~/ puzzle.size == row ||
                        selectedIndex! % puzzle.size == column ||
                        SudokuEngine.relatedBoxIndex(puzzle, selectedIndex!) == SudokuEngine.relatedBoxIndex(puzzle, index));
                final sameValue = selectedValue != 0 && value == selectedValue;
                final background = errorIndex == index
                    ? scheme.errorContainer
                    : selected
                        ? scheme.primaryContainer
                        : sameValue
                            ? scheme.secondaryContainer
                            : related
                                ? scheme.surfaceContainerHighest
                                : scheme.surface;
                return Semantics(
                  button: !puzzle.isFixed(index),
                  selected: selected,
                  label: 'Satır ${row + 1}, sütun ${column + 1}, ${value == 0 ? 'boş' : value}',
                  child: InkWell(
                    onTap: enabled ? () => onCellTap(index) : null,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: background,
                        border: Border(
                          right: BorderSide(
                            color: scheme.outline,
                            width: (column + 1) % puzzle.boxColumns == 0 && column != puzzle.size - 1 ? 2 : 0.4,
                          ),
                          bottom: BorderSide(
                            color: scheme.outline,
                            width: (row + 1) % puzzle.boxRows == 0 && row != puzzle.size - 1 ? 2 : 0.4,
                          ),
                        ),
                      ),
                      child: value == 0
                          ? _NotesCell(values: notes[index] ?? const <int>{}, size: puzzle.size)
                          : Center(
                              child: Text(
                                '$value',
                                style: TextStyle(
                                  fontSize: puzzle.size == 9 ? 25 : 34,
                                  fontWeight: puzzle.isFixed(index) ? FontWeight.w800 : FontWeight.w600,
                                  color: puzzle.isFixed(index) ? scheme.onSurface : scheme.primary,
                                ),
                              ),
                            ),
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
