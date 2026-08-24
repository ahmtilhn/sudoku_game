import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../services/online_duel_emote_hub.dart';

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
  const NumberPadDock({super.key, required this.child, this.compact = false});

  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: compact ? 4 : 10,
      color: Theme.of(
        context,
      ).colorScheme.surface.withValues(alpha: compact ? .94 : 1),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.fromLTRB(
          10,
          compact ? 6 : 10,
          10,
          compact ? 8 : 12,
        ),
        child: Align(
          alignment: Alignment.center,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 500 : 560),
            child: OnlineDuelEmoteDock(compact: compact, child: child),
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
    this.showErase = true,
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
  final bool showErase;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth <= 520;
        final dense = maxValue == 9;
        final spacing = dense ? 3.0 : 4.0;
        final oneRowWidth = constraints.maxWidth - (spacing * (maxValue - 1));
        final oneRowButtonWidth = oneRowWidth / maxValue;
        final minTap = dense ? 38.0 : 34.0;
        final maxTap = dense ? 46.0 : 40.0;
        final buttonWidth = oneRowButtonWidth >= minTap
            ? oneRowButtonWidth.clamp(minTap, maxTap)
            : maxTap;
        final buttonHeight = dense ? 40.0 : 36.0;

        return AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: enabled ? 1 : 0.58,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                spacing: spacing,
                runSpacing: dense ? 3 : 4,
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
                              minimumSize: Size(minTap, buttonHeight),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              backgroundColor: scheme.secondaryContainer,
                              foregroundColor: scheme.onSecondaryContainer,
                            ),
                            child: Text(
                              '$value',
                              style: TextStyle(
                                fontSize: dense ? 16 : 14,
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
              SizedBox(height: compact ? 5 : 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                runSpacing: 4,
                children: [
                  if (showErase)
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: const Size(42, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
