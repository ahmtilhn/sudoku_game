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
  const NumberPadDock({super.key, required this.child, this.compact = false});

  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screen = MediaQuery.sizeOf(context);
    final shortScreen = screen.height < 720;
    final veryShortScreen = screen.height < 650;
    final horizontal = screen.width >= 600;
    final horizontalPadding = horizontal
        ? 18.0
        : screen.width <= 350
        ? 7.0
        : 10.0;
    final topPadding = compact
        ? veryShortScreen
              ? 3.0
              : shortScreen
              ? 4.0
              : 6.0
        : 10.0;
    final bottomPadding = compact
        ? veryShortScreen
              ? 4.0
              : shortScreen
              ? 5.0
              : 8.0
        : 12.0;

    return Material(
      elevation: compact ? 4 : 10,
      color: scheme.surface.withValues(alpha: compact ? .96 : 1),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: .055)),
          ),
          boxShadow: compact
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .18),
                    blurRadius: 18,
                    offset: const Offset(0, -6),
                  ),
                ],
        ),
        child: SafeArea(
          top: false,
          minimum: EdgeInsets.fromLTRB(
            horizontalPadding,
            topPadding,
            horizontalPadding,
            bottomPadding,
          ),
          child: Align(
            alignment: Alignment.center,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: compact ? 500 : 560),
              child: child,
            ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = MediaQuery.sizeOf(context).height;
        final compact = constraints.maxWidth <= 520;
        final dense = maxValue == 9;
        final shortScreen = screenHeight < 720;
        final veryShortScreen = screenHeight < 650;

        return AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: enabled ? 1 : 0.58,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dense)
                _NineNumberGrid(
                  maxWidth: constraints.maxWidth,
                  enabled: enabled,
                  completedValues: completedValues,
                  onNumber: onNumber,
                  shortScreen: shortScreen,
                  veryShortScreen: veryShortScreen,
                )
              else
                _FlexibleNumberGrid(
                  maxWidth: constraints.maxWidth,
                  maxValue: maxValue,
                  enabled: enabled,
                  completedValues: completedValues,
                  onNumber: onNumber,
                ),
              if (showErase ||
                  onToggleNotes != null ||
                  onUndo != null ||
                  onHint != null) ...[
                SizedBox(
                  height: veryShortScreen
                      ? 3
                      : compact
                      ? 5
                      : 8,
                ),
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
            ],
          ),
        );
      },
    );
  }
}

class _NineNumberGrid extends StatelessWidget {
  const _NineNumberGrid({
    required this.maxWidth,
    required this.enabled,
    required this.completedValues,
    required this.onNumber,
    required this.shortScreen,
    required this.veryShortScreen,
  });

  final double maxWidth;
  final bool enabled;
  final Set<int> completedValues;
  final ValueChanged<int> onNumber;
  final bool shortScreen;
  final bool veryShortScreen;

  @override
  Widget build(BuildContext context) {
    final spacing = maxWidth <= 350 ? 5.0 : 7.0;
    final rawWidth = (maxWidth - spacing * 4) / 5;
    final maxButtonWidth = veryShortScreen
        ? 58.0
        : shortScreen
        ? 64.0
        : 72.0;
    final minButtonWidth = maxWidth <= 350 ? 42.0 : 46.0;
    final width = rawWidth.clamp(minButtonWidth, maxButtonWidth).toDouble();
    final height = veryShortScreen
        ? width.clamp(40.0, 45.0).toDouble()
        : shortScreen
        ? width.clamp(43.0, 50.0).toDouble()
        : width.clamp(46.0, 56.0).toDouble();
    final rowGap = veryShortScreen
        ? 4.0
        : shortScreen
        ? 5.0
        : 7.0;

    Widget row(List<int> values) => Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < values.length; index++) ...[
          if (index > 0) SizedBox(width: spacing),
          _NumberButton(
            value: values[index],
            width: width,
            height: height,
            enabled: enabled,
            completed: completedValues.contains(values[index]),
            onTap: () => onNumber(values[index]),
          ),
        ],
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row(const [1, 2, 3, 4, 5]),
        SizedBox(height: rowGap),
        row(const [6, 7, 8, 9]),
      ],
    );
  }
}

class _FlexibleNumberGrid extends StatelessWidget {
  const _FlexibleNumberGrid({
    required this.maxWidth,
    required this.maxValue,
    required this.enabled,
    required this.completedValues,
    required this.onNumber,
  });

  final double maxWidth;
  final int maxValue;
  final bool enabled;
  final Set<int> completedValues;
  final ValueChanged<int> onNumber;

  @override
  Widget build(BuildContext context) {
    const spacing = 4.0;
    final oneRowWidth = maxWidth - (spacing * (maxValue - 1));
    final oneRowButtonWidth = oneRowWidth / maxValue;
    final buttonWidth = oneRowButtonWidth >= 34
        ? oneRowButtonWidth.clamp(34.0, 40.0).toDouble()
        : 40.0;

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: spacing,
      runSpacing: spacing,
      children: [
        for (var value = 1; value <= maxValue; value++)
          _NumberButton(
            value: value,
            width: buttonWidth,
            height: 36,
            enabled: enabled,
            completed: completedValues.contains(value),
            onTap: () => onNumber(value),
            compact: true,
          ),
      ],
    );
  }
}

class _NumberButton extends StatelessWidget {
  const _NumberButton({
    required this.value,
    required this.width,
    required this.height,
    required this.enabled,
    required this.completed,
    required this.onTap,
    this.compact = false,
  });

  final int value;
  final double width;
  final double height;
  final bool enabled;
  final bool completed;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = enabled && !completed;
    return SizedBox(
      width: width,
      height: height,
      child: FilledButton.tonal(
        key: ValueKey<String>('number-$value'),
        onPressed: active ? onTap : null,
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size(width, height),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: scheme.secondaryContainer.withValues(alpha: .92),
          foregroundColor: scheme.onSecondaryContainer,
          disabledBackgroundColor: scheme.surfaceContainerHigh.withValues(
            alpha: .62,
          ),
          disabledForegroundColor: scheme.onSurface.withValues(alpha: .30),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(compact ? 12 : 15),
            side: BorderSide(
              color: active
                  ? scheme.secondary.withValues(alpha: .20)
                  : Colors.white.withValues(alpha: .035),
            ),
          ),
          elevation: 0,
        ),
        child: Text(
          '$value',
          style: TextStyle(
            fontSize: compact ? 14 : 18,
            fontWeight: FontWeight.w900,
            decoration: completed ? TextDecoration.lineThrough : null,
          ),
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
    return TextButton(
      key: buttonKey,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: selected ? scheme.primary : scheme.onSurfaceVariant,
        backgroundColor: selected
            ? scheme.primary.withValues(alpha: .12)
            : Colors.white.withValues(alpha: .025),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: const Size(42, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: BorderSide(
            color: selected
                ? scheme.primary.withValues(alpha: .26)
                : Colors.white.withValues(alpha: .055),
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
