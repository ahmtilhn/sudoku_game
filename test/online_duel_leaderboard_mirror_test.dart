import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/services/online_duel_controller.dart';
import 'package:sudoku_game/services/online_duel_models.dart';
import 'package:sudoku_game/services/online_duel_transport.dart';
import 'package:sudoku_game/services/platform_leaderboard_service.dart';

void main() {
  test('settled ranked snapshot is forwarded to the platform mirror', () async {
    final transport = FakeOnlineDuelTransport();
    final mirror = _RecordingMirror();
    final controller = OnlineDuelController(
      transport,
      platformLeaderboardMirror: mirror,
    )..start();

    transport.emit(
      OnlineDuelEvent(
        type: 'snapshot',
        revision: 8,
        serverTime: DateTime.fromMillisecondsSinceEpoch(1000),
        payload: _settledSnapshot(),
      ),
    );
    await pumpEventQueue();

    expect(mirror.snapshots, hasLength(1));
    expect(mirror.snapshots.single.matchId, 'settled-match');
    expect(
      mirror.snapshots.single.rating?[OnlineDuelSeat.a]?.afterGlobal,
      1220,
    );

    await controller.dispose();
  });
}

class _RecordingMirror implements PlatformLeaderboardMirror {
  final List<OnlineDuelSnapshot> snapshots = <OnlineDuelSnapshot>[];

  @override
  Future<PlatformLeaderboardMirrorResult> mirrorFinalRatings(
    OnlineDuelSnapshot snapshot,
  ) async {
    snapshots.add(snapshot);
    return const PlatformLeaderboardMirrorResult(
      status: PlatformLeaderboardMirrorStatus.submitted,
    );
  }
}

Map<String, dynamic> _settledSnapshot() {
  final puzzle = List<int>.filled(81, 0)..[0] = 1;
  return <String, dynamic>{
    'roomId': 'room',
    'matchId': 'settled-match',
    'mode': 'ranked',
    'difficulty': 'medium',
    'status': 'completed',
    'youSeat': 'A',
    'players': <String, dynamic>{
      'A': <String, dynamic>{
        'publicId': 'a',
        'username': 'alice',
        'displayName': 'Alice',
        'avatarKey': 'default',
        'ready': true,
        'screenLoaded': true,
        'connected': true,
      },
      'B': <String, dynamic>{
        'publicId': 'b',
        'username': 'bob',
        'displayName': 'Bob',
        'avatarKey': 'default',
        'ready': true,
        'screenLoaded': true,
        'connected': true,
      },
    },
    'puzzle': puzzle,
    'board': List<int>.filled(81, 1),
    'scores': <String, int>{'A': 100, 'B': 80},
    'mistakes': <String, int>{'A': 0, 'B': 1},
    'correctMoves': <String, int>{'A': 10, 'B': 8},
    'timeouts': <String, int>{'A': 0, 'B': 0},
    'currentTurnSeat': 'A',
    'turnNumber': 19,
    'serverTime': 1000,
    'revision': 8,
    'winnerSeat': 'A',
    'finishReason': 'board_completed',
    'rating': <String, dynamic>{
      'A': <String, int>{
        'beforeGlobal': 1200,
        'afterGlobal': 1220,
        'deltaGlobal': 20,
        'beforeDifficulty': 1100,
        'afterDifficulty': 1120,
        'deltaDifficulty': 20,
      },
      'B': <String, int>{
        'beforeGlobal': 1000,
        'afterGlobal': 980,
        'deltaGlobal': -20,
        'beforeDifficulty': 1000,
        'afterDifficulty': 980,
        'deltaDifficulty': -20,
      },
    },
  };
}
