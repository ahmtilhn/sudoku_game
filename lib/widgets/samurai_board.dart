import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/samurai_sudoku.dart';
import '../domain/sudoku_symbols.dart';
import '../localization/app_strings.dart';

const ColorScheme _samuraiBoardScheme = ColorScheme.dark(
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

class SamuraiBoard extends StatelessWidget {
  const SamuraiBoard({
    super.key,
    required this.puzzle,
    required this.board,
    required this.selectedIndex,
    required this.onCellTap,
    this.notes = const <int, Set<int>>{},
    this.errorIndex,
    this.hintedIndexes = const <int>{},
    this.enabled = true,
    this.minimumBoardExtent = 630,
  });

  final SamuraiPuzzle puzzle;
  final List<int> board;
  final int? selectedIndex;
  final ValueChanged<int> onCellTap;
  final Map<int, Set<int>> notes;
  final int? errorIndex;
  final Set<int> hintedIndexes;
  final bool enabled;
  final double minimumBoardExtent;

  @override
  Widget build(BuildContext context) {
    if (board.length != SamuraiTopology.canvasCellCount) {
      return const SizedBox.shrink();
    }
    final selectedValue = selectedIndex == null ? 0 : board[selectedIndex!];
    final selectedUnits = selectedIndex == null
        ? const <int>{}
        : SamuraiTopology.unitsByCell[selectedIndex!].toSet();

    return Semantics(
      label: context.tr('board_label', const <Object>[21]),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportExtent = math.min(
            constraints.maxWidth,
            constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : constraints.maxWidth,
          );
          final boardExtent = math.max(
            minimumBoardExtent,
            viewportExtent.isFinite ? viewportExtent : minimumBoardExtent,
          );
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ColoredBox(
              color: _samuraiBoardScheme.surfaceContainerLow,
              child: InteractiveViewer(
                constrained: false,
                minScale: 0.55,
                maxScale: 4.5,
                boundaryMargin: const EdgeInsets.all(96),
                panEnabled: true,
                scaleEnabled: true,
                child: SizedBox.square(
                  dimension: boardExtent,
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: SamuraiTopology.canvasSize,
                        ),
                    itemCount: SamuraiTopology.canvasCellCount,
                    itemBuilder: (context, index) {
                      if (!SamuraiTopology.isActiveIndex(index)) {
                        return const ExcludeSemantics(child: SizedBox.shrink());
                      }
                      final value = board[index];
                      final selected = selectedIndex == index;
                      final fixed = puzzle.isFixed(index);
                      final hinted = hintedIndexes.contains(index);
                      final overlap = SamuraiTopology.isOverlapIndex(index);
                      final hasError = errorIndex == index;
                      final sameValue = selectedValue > 0 && value == selectedValue;
                      final related = selectedIndex != null &&
                          SamuraiTopology.unitsByCell[index].any(
                            selectedUnits.contains,
                          );
                      final row = SamuraiTopology.rowOf(index);
                      final column = SamuraiTopology.columnOf(index);
                      final cellExtent = boardExtent / SamuraiTopology.canvasSize;

                      return Semantics(
                        button: !fixed && !hinted,
                        selected: selected,
                        label: context.tr('cell_label', <Object>[
                          row + 1,
                          column + 1,
                          value <= 0
                              ? context.tr('empty')
                              : sudokuSpokenValue(value),
                        ]),
                        child: InkWell(
                          key: ValueKey<String>('samurai-cell-$index'),
                          onTap: enabled ? () => onCellTap(index) : null,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: _backgroundColor(
                                selected: selected,
                                hasError: hasError,
                                hinted: hinted,
                                sameValue: sameValue,
                                related: related,
                                overlap: overlap,
                              ),
                              border: _cellBorder(index),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                if (value > 0)
                                  Center(
                                    child: Text(
                                      sudokuSymbol(value),
                                      textScaler: const TextScaler.linear(1),
                                      style: TextStyle(
                                        height: 1,
                                        fontSize: (cellExtent * .5).clamp(
                                          13.0,
                                          24.0,
                                        ),
                                        fontWeight: fixed || selected || hinted
                                            ? FontWeight.w900
                                            : FontWeight.w700,
                                        color: _numberColor(
                                          selected: selected,
                                          fixed: fixed,
                                          hinted: hinted,
                                          hasError: hasError,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  _SamuraiNotes(
                                    values: notes[index] ?? const <int>{},
                                    fontSize: (cellExtent * .19).clamp(5.0, 8.0),
                                    color: selected
                                        ? _samuraiBoardScheme.onPrimaryContainer
                                        : _samuraiBoardScheme.onSurfaceVariant,
                                  ),
                                if (overlap)
                                  Align(
                                    alignment: Alignment.topLeft,
                                    child: Container(
                                      width: (cellExtent * .17).clamp(4.0, 8.0),
                                      height: (cellExtent * .17).clamp(4.0, 8.0),
                                      decoration: BoxDecoration(
                                        color: _samuraiBoardScheme.tertiary,
                                        borderRadius: const BorderRadius.only(
                                          bottomRight: Radius.circular(5),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (hasError)
                                  Align(
                                    alignment: Alignment.topRight,
                                    child: Icon(
                                      Icons.error_rounded,
                                      size: (cellExtent * .28).clamp(8.0, 14.0),
                                      color: _samuraiBoardScheme.error,
                                    ),
                                  ),
                              ],
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
        },
      ),
    );
  }

  Color _backgroundColor({
    required bool selected,
    required bool hasError,
    required bool hinted,
    required bool sameValue,
    required bool related,
    required bool overlap,
  }) {
    if (hasError) return _samuraiBoardScheme.errorContainer;
    if (selected) return _samuraiBoardScheme.primaryContainer;
    if (hinted) return _samuraiBoardScheme.tertiaryContainer;
    if (sameValue) {
      return Color.alphaBlend(
        _samuraiBoardScheme.secondary.withAlpha(58),
        _samuraiBoardScheme.surface,
      );
    }
    if (related) {
      return Color.alphaBlend(
        _samuraiBoardScheme.onSurface.withAlpha(20),
        _samuraiBoardScheme.surface,
      );
    }
    if (overlap) {
      return Color.alphaBlend(
        _samuraiBoardScheme.tertiary.withAlpha(24),
        _samuraiBoardScheme.surface,
      );
    }
    return _samuraiBoardScheme.surface;
  }

  Color _numberColor({
    required bool selected,
    required bool fixed,
    required bool hinted,
    required bool hasError,
  }) {
    if (hasError) return _samuraiBoardScheme.onErrorContainer;
    if (selected) return _samuraiBoardScheme.onPrimaryContainer;
    if (hinted) return _samuraiBoardScheme.onTertiaryContainer;
    if (fixed) return _samuraiBoardScheme.onSurface;
    return _samuraiBoardScheme.primary;
  }

  Border _cellBorder(int index) {
    final row = SamuraiTopology.rowOf(index);
    final column = SamuraiTopology.columnOf(index);
    var top = .35;
    var left = .35;
    var right = .35;
    var bottom = .35;

    for (final origin in SamuraiTopology.boardOrigins) {
      final localRow = row - origin.row;
      final localColumn = column - origin.column;
      if (localRow < 0 ||
          localRow >= SamuraiTopology.boardSize ||
          localColumn < 0 ||
          localColumn >= SamuraiTopology.boardSize) {
        continue;
      }
      if (localRow == 0 || localRow % 3 == 0) top = math.max(top, 1.8);
      if (localColumn == 0 || localColumn % 3 == 0) {
        left = math.max(left, 1.8);
      }
      if (localRow == 8 || (localRow + 1) % 3 == 0) {
        bottom = math.max(bottom, 1.8);
      }
      if (localColumn == 8 || (localColumn + 1) % 3 == 0) {
        right = math.max(right, 1.8);
      }
    }

    return Border(
      top: BorderSide(color: _samuraiBoardScheme.outline, width: top),
      left: BorderSide(color: _samuraiBoardScheme.outline, width: left),
      right: BorderSide(color: _samuraiBoardScheme.outline, width: right),
      bottom: BorderSide(color: _samuraiBoardScheme.outline, width: bottom),
    );
  }
}

class _SamuraiNotes extends StatelessWidget {
  const _SamuraiNotes({
    required this.values,
    required this.fontSize,
    required this.color,
  });

  final Set<int> values;
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(1),
      child: GridView.count(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        crossAxisCount: 3,
        children: <Widget>[
          for (var value = 1; value <= 9; value++)
            Center(
              child: Text(
                values.contains(value) ? sudokuSymbol(value) : '',
                textScaler: const TextScaler.linear(1),
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
