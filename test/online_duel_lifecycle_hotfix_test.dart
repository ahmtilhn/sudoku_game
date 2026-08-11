import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('online duel has a local 30 second disconnect escape hatch', () {
    final source = File(
      'lib/features/duel/online_duel_screen.dart',
    ).readAsStringSync();
    expect(source, contains('Duration(seconds: 30)'));
    expect(source, contains('_disconnectEscapeTimer'));
    expect(
      source,
      contains('Navigator.of(context).popUntil((route) => route.isFirst)'),
    );
    expect(source, contains('snapshot.status == OnlineDuelStatus.paused'));
    expect(source, contains('_localConnectionInterrupted'));
  });

  test('forfeit waits for the authoritative result before leaving', () {
    final source = File(
      'lib/features/duel/online_duel_screen.dart',
    ).readAsStringSync();
    expect(source, contains('await _returnToMainMenu(sendForfeit: true)'));
    expect(source, contains('waitForAuthoritativeResult'));
    expect(source, contains('setState(() => _forfeiting = true)'));
    expect(source, contains('_showResultOnce(snapshot);'));
    expect(
      source,
      isNot(
        contains(
          'await Future<void>.delayed(const Duration(milliseconds: 180))',
        ),
      ),
    );
  });

  test('arena identity and score layout uses inward large score placement', () {
    final source = File(
      'lib/features/duel/online_duel_screen.dart',
    ).readAsStringSync();
    expect(source, contains('fontSize: widget.compact ? 22 : 28'));
    expect(source, contains("key: ValueKey<String>('duel-name-\$seatKey')"));
    expect(source, contains('final children = <Widget>'));
    expect(source, contains('score: score'));
    expect(source, contains('_ScoreLine'));
  });

  test('all challenge acceptance paths converge on pre-match ready', () {
    final legacy = File(
      'lib/features/social/challenge_invitation_screen.dart',
    ).readAsStringSync();
    final modern = File(
      'lib/features/social/ux_challenge_invitation_screen.dart',
    ).readAsStringSync();
    final waiting = File(
      'lib/features/social/challenge_waiting_screen.dart',
    ).readAsStringSync();
    expect(legacy, contains('PreMatchReadyScreen(roomId: roomId)'));
    expect(legacy, isNot(contains('OnlineDuelScreen(roomId: roomId)')));
    expect(modern, contains('Future<void> _openRoom(String roomId)'));
    expect(waiting, contains('unawaited(_openRoom(roomId))'));
  });
}
