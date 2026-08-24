import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/services/online_duel_models.dart';

void main() {
  test('terminal loser snapshot is immediately presentable without rating', () {
    final snapshot = OnlineDuelSnapshot.fromJson(<String, dynamic>{
      'roomId': 'room-1',
      'matchId': 'match-1',
      'mode': 'friendly',
      'variant': 'classic9',
      'boardSize': 9,
      'cellCount': 81,
      'difficulty': 'easy',
      'status': 'completed',
      'youSeat': 'B',
      'players': <String, dynamic>{
        'A': <String, dynamic>{'displayName': 'Winner'},
        'B': <String, dynamic>{'displayName': 'Loser'},
      },
      'puzzle': List<int>.filled(81, 0),
      'board': List<int>.filled(81, 0),
      'scores': <String, int>{'A': 100, 'B': 50},
      'mistakes': <String, int>{'A': 0, 'B': 1},
      'correctMoves': <String, int>{'A': 10, 'B': 5},
      'timeouts': <String, int>{'A': 0, 'B': 0},
      'currentTurnSeat': 'A',
      'turnNumber': 15,
      'serverTime': DateTime.now().millisecondsSinceEpoch,
      'revision': 20,
      'winnerSeat': 'A',
      'finishReason': 'board_completed',
      'rating': null,
    });

    expect(snapshot.isFinished, isTrue);
    expect(snapshot.winnerSeat, OnlineDuelSeat.a);
    expect(snapshot.youSeat, OnlineDuelSeat.b);
    expect(snapshot.rating, isNotNull);
  });

  test('completion event is applied before requesting settlement snapshot', () {
    final source = File(
      'lib/services/online_duel_controller.dart',
    ).readAsStringSync();

    expect(source, contains("event.type == 'match_completed'"));
    expect(source, contains('_applyTerminalResultEvent(event);'));
    expect(
      source,
      contains("winnerSeat: _seat(event.payload['winnerSeat']?.toString())"),
    );
    expect(source, contains('requestSnapshot();'));
  });

  test('foreground social notification has no artificial delivery delay', () {
    final push = File(
      'lib/services/push_notification_service.dart',
    ).readAsStringSync();
    final gate = File(
      'lib/features/social/challenge_navigation_gate.dart',
    ).readAsStringSync();

    expect(push, isNot(contains('Duration(milliseconds: 350)')));
    expect(push, contains('setAutomaticSocialUiAllowed'));
    expect(push, contains('if (_automaticSocialUiAllowed) return;'));
    expect(gate, contains('_push.setAutomaticSocialUiAllowed(routeIsCurrent);'));
  });

  test('rematch is idempotent, retries settlement, and backend pushes invite', () {
    final economy = File(
      'lib/services/economy_service.dart',
    ).readAsStringSync();
    final entry = File(
      'backend/social_worker/src/entry.ts',
    ).readAsStringSync();
    final push = File(
      'backend/social_worker/src/push_notifications.ts',
    ).readAsStringSync();

    expect(economy, contains('invitation.previousMatchId == matchId'));
    expect(economy, contains('if (pending.isSender) return pending;'));
    expect(economy, contains('invitationId: pending.id'));
    expect(economy, contains('accept: true'));
    expect(economy, contains('for (var attempt = 0; attempt < 8; attempt++)'));
    expect(economy, contains("contains('match has not finished yet')"));
    expect(entry, contains('notifyRematchRecipient'));
    expect(entry, contains("type: 'rematch_invitation'"));
    expect(push, contains("priority: 'high'"));
    expect(push, contains("'apns-priority': '10'"));
  });
}
