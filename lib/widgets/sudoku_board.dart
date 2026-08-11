import 'package:flutter/material.dart';

import '../domain/sudoku.dart';
import '../domain/sudoku_symbols.dart';
import '../localization/app_strings.dart';

const ColorScheme _sharedGameBoardScheme = ColorScheme.dark(
  primary: Color(0xFF29D398),
  onPrimary: Color(0xFF08110E),
  primaryContainer: Color(0xFF176C58),
  onPrimaryContainer: Color(0xFFFFFFFF),
  secondary: Color(0xFF3AA9FF),
  onSecondary: Color(0xFF071B2E),
  secondaryContainer: Color(0xFF173B52),
  onSecondaryContainer: Color(0xFFD8EEFF),
  tertiary: Color(0xFFFFC94D),
  onTertiary: Color(0xFF2B1F00),
  tertiaryContainer: Color(0xFF493B13),
  onTertiaryContainer: Color(0xFFFFE9A9),
  surface: Color(0xFF132026),
  surfaceContainerLow: Color(0xFF121B20),
  surfaceContainer: Color(0xFF18242B),
  surfaceContainerHigh: Color(0xFF22313A),
  surfaceContainerHighest: Color(0xFF293B45),
  outline: Color(0xFF7F8B94),
  outlineVariant: Color(0xFF2E414B),
  error: Color(0xFFFF5B6B),
  errorContainer: Color(0xFF3A151D),
  onErrorContainer: Color(0xFFFFD7DC),
  onSurface: Color(0xFFF8FAFC),
  onSurfaceVariant: Color(0xFFB7C3CA),
);

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
    const scheme = _sharedGameBoardScheme;
    final selectedValue = selectedIndex == null ? 0 : board[selectedIndex!];
    final matchingValueBackground = Color.alphaBlend(
      scheme.secondary.withAlpha(55),
      scheme.surface,
    );
    final relatedBackground = Color.alphaBlend(
      scheme.onSurface.withAlpha(17),
      scheme.surface,
    );
    final visualTextScale = MediaQuery.textScalerOf(context)
        .scale(1)
        .clamp(1.0, 1.2)
        .toDouble();

    return Semantics(
      label: context.tr('board_label', <Object>[puzzle.size]),
      child: AspectRatio(
        aspectRatio: 1,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cellSize = constraints.biggest.shortestSide / puzzle.size;
            final numberFontSize = (cellSize * (puzzle.size == 16 ? .58 : .52))
                .clamp(10.0, 28.0)
                .toDouble();
            final noteFontSize = (cellSize * .25)
                .clamp(5.5, 12.0)
                .toDouble();
            final markerSize = (cellSize * .25)
                .clamp(8.0, 16.0)
                .toDouble();

            return DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                border: Border.all(color: scheme.outline, width: 1.4),
                borderRadius: BorderRadius.circular(puzzle.size == 16 ? 10 : 16),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(puzzle.size == 16 ? 8 : 14),
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
                    final related = selectedIndex != null &&
                        (selectedIndex! ~/ puzzle.size == row ||
                            selectedIndex! % puzzle.size == column ||
                            SudokuEngine.relatedBoxIndex(puzzle, selectedIndex!) ==
                                SudokuEngine.relatedBoxIndex(puzzle, index));
                    final sameValue = selectedValue != 0 && value == selectedValue;
                    final hasError = errorIndex == index;
                    final background = hasError
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
                                                ? relatedBackground
                                                : scheme.surface;
                    final numberColor = hasError
                        ? scheme.onErrorContainer
                        : selected
                            ? scheme.onPrimaryContainer
                            : hinted
                                ? scheme.onTertiaryContainer
                                : fixed
                                    ? scheme.onSurface
                                    : scheme.primary;

                    return Semantics(
                      button: !locked,
                      selected: selected,
                      label: context.tr('cell_label', <Object>[
                        row + 1,
                        column + 1,
                        value == 0
                            ? context.tr('empty')
                            : sudokuSpokenValue(value),
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
                                  top: selected || hasError
                                      ? BorderSide(
                                          color: hasError
                                              ? scheme.error
                                              : scheme.primary,
                                          width: 1.6,
                                        )
                                      : BorderSide.none,
                                  left: selected || hasError
                                      ? BorderSide(
                                          color: hasError
                                              ? scheme.error
                                              : scheme.primary,
                                          width: 1.6,
                                        )
                                      : BorderSide.none,
                                  right: BorderSide(
                                    color: scheme.outline,
                                    width: (column + 1) % puzzle.boxColumns == 0 &&
                                            column != puzzle.size - 1
                                        ? 2
                                        : .35,
                                  ),
                                  bottom: BorderSide(
                                    color: scheme.outline,
                                    width: (row + 1) % puzzle.boxRows == 0 &&
                                            row != puzzle.size - 1
                                        ? 2
                                        : .35,
                                  ),
                                ),
                              ),
                              child: value == 0
                                  ? _NotesCell(
                                      values: notes[index] ?? const <int>{},
                                      size: puzzle.size,
                                      color: selected
                                          ? scheme.onPrimaryContainer
                                          : scheme.onSurfaceVariant,
                                      fontSize: noteFontSize,
                                      textScale: visualTextScale,
                                    )
                                  : Center(
                                      child: Text(
                                        sudokuSymbol(value),
                                        textScaler: TextScaler.linear(
                                          visualTextScale,
                                        ),
                                        style: TextStyle(
                                          fontSize: numberFontSize,
                                          height: 1,
                                          fontWeight: locked || selected
                                              ? FontWeight.w900
                                              : FontWeight.w700,
                                          fontFeatures: const <FontFeature>[
                                            FontFeature.tabularFigures(),
                                          ],
                                          color: numberColor,
                                          shadows: selected
                                              ? const <Shadow>[
                                                  Shadow(
                                                    color: Color(0x99000000),
                                                    blurRadius: 3,
                                                  ),
                                                ]
                                              : null,
                                        ),
                                      ),
                                    ),
                            ),
                            if (hasError)
                              Align(
                                alignment: Alignment.topRight,
                                child: Icon(
                                  Icons.error_rounded,
                                  size: markerSize,
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
                                  size: markerSize,
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
            );
          },
        ),
      ),
    );
  }
}

class _NotesCell extends StatelessWidget {
  const _NotesCell({
    required this.values,
    required this.size,
    required this.color,
    required this.fontSize,
    required this.textScale,
  });

  final Set<int> values;
  final int size;
  final Color color;
  final double fontSize;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    final columns = size == 4 ? 2 : size == 16 ? 4 : 3;
    return Padding(
      padding: EdgeInsets.all(size == 16 ? .5 : 2),
      child: GridView.count(
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: columns,
        padding: EdgeInsets.zero,
        children: <Widget>[
          for (var value = 1; value <= size; value++)
            Center(
              child: Text(
                values.contains(value) ? sudokuSymbol(value) : '',
                textScaler: TextScaler.linear(textScale),
                style: TextStyle(
                  height: 1,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
