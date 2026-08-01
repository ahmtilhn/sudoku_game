import 'package:flutter/material.dart';

import '../localization/app_strings.dart';

Set<int> completedSudokuNumbers({
  required List<int> board,
  required int maxValue,
}) {
  final counts = List<int>.filled(maxValue + 1, 0);
  for (final value in board) {
    if (value >= 1 && value <= maxValue) {
      counts[value]++;
    }
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
        minimum: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Align(
          alignment: Alignment.center,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
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
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = maxValue == 9 && constraints.maxWidth < 430;
        final spacing = compact ? 4.0 : 8.0;
        final oneRowWidth = constraints.maxWidth - (spacing * (maxValue - 1));
        final oneRowButtonWidth = oneRowWidth / maxValue;
        final buttonWidth = oneRowButtonWidth >= 48
            ? oneRowButtonWidth.clamp(48.0, maxValue == 9 ? 58.0 : 72.0)
            : 56.0;
        final buttonHeight = compact ? 48.0 : 54.0;

        return AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: enabled ? 1 : 0.58,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                spacing: spacing,
                runSpacing: compact ? 4 : 8,
                children: [
                  for (var value = 1; value <= maxValue; value++)
                    Builder(
                      builder: (context) {
                        final isCompleted = completedValues.contains(value);
                        return SizedBox(
                          width: buttonWidth,
                          height: buttonHeight,
                          child: FilledButton.tonal(
                            key: ValueKey<String>('number-$value'),
                            onPressed: enabled && !isCompleted
                                ? () => onNumber(value)
                                : null,
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(48, 48),
                              backgroundColor: scheme.secondaryContainer,
                              foregroundColor: scheme.onSecondaryContainer,
                            ),
                            child: Text(
                              '$value',
                              style: TextStyle(
                                fontSize: compact ? 17 : 21,
                                fontWeight: FontWeight.w800,
                                decoration: isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
              SizedBox(height: compact ? 6 : 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                runSpacing: 4,
                children: [
                  _ActionButton(
                    buttonKey: const ValueKey<String>('action-erase'),
                    icon: Icons.backspace_outlined,
                    label: context.tr('erase'),
                    onPressed: enabled ? onErase : null,
                  ),
                  if (onToggleNotes != null)
                    _ActionButton(
                      buttonKey: const ValueKey<String>('action-notes'),
                      icon: notesEnabled
                          ? Icons.edit_note
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
                      icon: Icons.undo,
                      label: context.tr('undo'),
                      onPressed: enabled ? onUndo : null,
                    ),
                  if (onHint != null)
                    _ActionButton(
                      buttonKey: const ValueKey<String>('action-hint'),
                      icon: Icons.lightbulb_outline,
                      label: hintCount == null
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
    return TextButton(
      key: buttonKey,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: selected
            ? scheme.primaryContainer
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(44, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 5),
            Text(label, maxLines: 1),
          ],
        ),
      ),
    );
  }
}
