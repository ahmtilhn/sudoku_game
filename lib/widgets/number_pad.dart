import 'package:flutter/material.dart';

import '../domain/sudoku_symbols.dart';
import '../localization/app_strings.dart';

Set<int> completedSudokuNumbers({
  required List<int> board,
  required int maxValue,
}) {
  final counts = List<int>.filled(maxValue + 1, 0);
  for (final value in board) {
    if (value >= 1 && value <= maxValue) counts[value]++;
  }
  return <int>{
    for (var value = 1; value <= maxValue; value++)
      if (counts[value] >= maxValue) value,
  };
}

class NumberPadDock extends StatelessWidget {
  const NumberPadDock({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 10,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Align(
          alignment: Alignment.center,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: child,
          ),
        ),
      ),
    );
  }
}

class NumberPad extends StatelessWidget {
  const NumberPad({
    super.key,
    required this.maxValue,
    required this.onNumber,
    required this.onErase,
    this.completedValues = const <int>{},
    this.notesEnabled = false,
    this.onToggleNotes,
    this.onUndo,
    this.onHint,
    this.hintCount,
    this.unlimitedHints = false,
    this.enabled = true,
  });

  final int maxValue;
  final ValueChanged<int> onNumber;
  final VoidCallback onErase;
  final Set<int> completedValues;
  final bool notesEnabled;
  final VoidCallback? onToggleNotes;
  final VoidCallback? onUndo;
  final VoidCallback? onHint;
  final int? hintCount;
  final bool unlimitedHints;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: enabled ? 1 : .52,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (maxValue > 9)
                _LargeNumberGrid(
                  maxValue: maxValue,
                  width: constraints.maxWidth,
                  enabled: enabled,
                  completedValues: completedValues,
                  onNumber: onNumber,
                )
              else
                _ClassicNumberRow(
                  maxValue: maxValue,
                  width: constraints.maxWidth,
                  enabled: enabled,
                  completedValues: completedValues,
                  onNumber: onNumber,
                ),
              SizedBox(height: maxValue > 9 ? 6 : 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  _ActionButton(
                    buttonKey: const ValueKey<String>('action-erase'),
                    icon: Icons.backspace_rounded,
                    label: context.tr('erase'),
                    onPressed: enabled ? onErase : null,
                  ),
                  if (onToggleNotes != null)
                    _ActionButton(
                      buttonKey: const ValueKey<String>('action-notes'),
                      icon: notesEnabled
                          ? Icons.edit_note_rounded
                          : Icons.edit_note_outlined,
                      label: notesEnabled
                          ? context.tr('notes_on')
                          : context.tr('notes'),
                      selected: notesEnabled,
                      onPressed: enabled ? onToggleNotes : null,
                    ),
                  if (onUndo != null)
                    _ActionButton(
                      buttonKey: const ValueKey<String>('action-undo'),
                      icon: Icons.undo_rounded,
                      label: context.tr('undo'),
                      onPressed: enabled ? onUndo : null,
                    ),
                  if (onHint != null)
                    _ActionButton(
                      buttonKey: const ValueKey<String>('action-hint'),
                      icon: Icons.lightbulb_outline_rounded,
                      label: unlimitedHints
                          ? '${context.tr('hint')} (∞)'
                          : hintCount == null
                              ? context.tr('hint')
                              : '${context.tr('hint')} ($hintCount)',
                      onPressed: enabled ? onHint : null,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ClassicNumberRow extends StatelessWidget {
  const _ClassicNumberRow({
    required this.maxValue,
    required this.width,
    required this.enabled,
    required this.completedValues,
    required this.onNumber,
  });

  final int maxValue;
  final double width;
  final bool enabled;
  final Set<int> completedValues;
  final ValueChanged<int> onNumber;

  @override
  Widget build(BuildContext context) {
    final compact = maxValue == 9 && width <= 520;
    final spacing = compact ? 4.0 : 8.0;
    final oneRowWidth = width - spacing * (maxValue - 1);
    final oneRowButtonWidth = oneRowWidth / maxValue;
    final buttonWidth = oneRowButtonWidth >= 48
        ? oneRowButtonWidth.clamp(48.0, maxValue == 9 ? 58.0 : 72.0)
        : 56.0;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: spacing,
      runSpacing: compact ? 4 : 8,
      children: [
        for (var value = 1; value <= maxValue; value++)
          SizedBox(
            width: buttonWidth,
            height: compact ? 48 : 54,
            child: _NumberButton(
              value: value,
              enabled: enabled,
              completed: completedValues.contains(value),
              onNumber: onNumber,
            ),
          ),
      ],
    );
  }
}

class _LargeNumberGrid extends StatelessWidget {
  const _LargeNumberGrid({
    required this.maxValue,
    required this.width,
    required this.enabled,
    required this.completedValues,
    required this.onNumber,
  });

  final int maxValue;
  final double width;
  final bool enabled;
  final Set<int> completedValues;
  final ValueChanged<int> onNumber;

  @override
  Widget build(BuildContext context) {
    final columns = width >= 540 ? 8 : 4;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 5,
        mainAxisSpacing: 5,
        childAspectRatio: width >= 540 ? 1.45 : 1.75,
      ),
      itemCount: maxValue,
      itemBuilder: (context, index) {
        final value = index + 1;
        return _NumberButton(
          value: value,
          enabled: enabled,
          completed: completedValues.contains(value),
          onNumber: onNumber,
        );
      },
    );
  }
}

class _NumberButton extends StatelessWidget {
  const _NumberButton({
    required this.value,
    required this.enabled,
    required this.completed,
    required this.onNumber,
  });

  final int value;
  final bool enabled;
  final bool completed;
  final ValueChanged<int> onNumber;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton.tonal(
      key: ValueKey<String>('number-$value'),
      onPressed: enabled && !completed ? () => onNumber(value) : null,
      style: FilledButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.padded,
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
      ),
      child: Text(
        sudokuSymbol(value),
        style: TextStyle(
          fontSize: 20,
          height: 1,
          fontWeight: FontWeight.w900,
          decoration: completed ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeColor = selected ? scheme.primary : scheme.outlineVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: buttonKey,
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: 92,
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primaryContainer.withValues(alpha: .72)
                : scheme.surfaceContainerHighest.withValues(alpha: .58),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: onPressed == null
                  ? scheme.outlineVariant.withValues(alpha: .45)
                  : activeColor,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 19,
                color: onPressed == null
                    ? scheme.onSurface.withValues(alpha: .38)
                    : selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onPressed == null
                        ? scheme.onSurface.withValues(alpha: .38)
                        : selected
                            ? scheme.onPrimaryContainer
                            : scheme.onSurface,
                    fontSize: 11,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
