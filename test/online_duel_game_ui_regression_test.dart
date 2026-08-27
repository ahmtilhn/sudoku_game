import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('active duel keeps one timer and a timer-free turn strip', () {
    final source = File(
      'lib/features/duel/online_duel_screen.dart',
    ).readAsStringSync();

    expect(source, contains('class _MatchHeader extends StatelessWidget'));
    expect(source, contains('class _TimerPill extends StatefulWidget'));
    expect(source, contains('class _TurnStatusStrip extends StatelessWidget'));
    expect(source, contains("context.tr('your_turn').toUpperCase()"));
    expect(source, contains("'Make your move'"));
    expect(source, isNot(contains("'YOUR TURN · 30'")));
  });

  test('forfeit remains behind match options and confirmation', () {
    final source = File(
      'lib/features/duel/online_duel_screen.dart',
    ).readAsStringSync();

    expect(source, contains('class _ArenaBottomControls extends StatelessWidget'));
    expect(source, contains("'MATCH OPTIONS'"));
    expect(source, contains("'Forfeit match'"));
    expect(source, contains("'A second confirmation is required.'"));
    expect(source, contains('_requestForfeit()'));
  });

  test('nine number pad stays centered in responsive five plus four rows', () {
    final source = File('lib/widgets/number_pad.dart').readAsStringSync();

    expect(source, contains('MediaQuery.sizeOf(context)'));
    expect(source, contains('shortScreen'));
    expect(source, contains('veryShortScreen'));
    expect(source, contains('row(const [1, 2, 3, 4, 5])'));
    expect(source, contains('row(const [6, 7, 8, 9])'));
    expect(source, isNot(contains('row(const [1, 2, 3, 4, 5, 6, 7])')));
  });

  test('active duel keeps avatar-linked emotes and separate options control', () {
    final source = File(
      'lib/features/duel/online_duel_screen.dart',
    ).readAsStringSync();

    expect(source, contains('OnlineDuelEmoteBubble'));
    expect(source, contains('showOnlineDuelEmotePicker'));
    expect(source, contains("tooltip: 'Emotes'"));
    expect(source, contains("tooltip: 'Match options'"));
  });
}
