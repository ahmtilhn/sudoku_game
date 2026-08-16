import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sudoku_game/domain/sudoku_variant.dart';
import 'package:sudoku_game/services/variant_matchmaking_client.dart';

void main() {
  test('queue payload includes complete classic16 metadata', () {
    final payload = VariantMatchmakingClient.queuePayload(
      difficulty: 'hard',
      variant: SudokuVariant.classic16,
    );

    expect(payload, <String, Object>{
      'difficulty': 'hard',
      'variant': 'classic16',
      'boardSize': 16,
      'cellCount': 256,
      'boxRows': 4,
      'boxColumns': 4,
    });
  });

  test('classic9 and classic16 responses stay distinct', () {
    final nine = VariantMatchmakingResult.fromJson(<String, dynamic>{
      'status': 'queued',
      'difficulty': 'easy',
      'variant': 'classic9',
      'boardSize': 9,
      'cellCount': 81,
    });
    final sixteen = VariantMatchmakingResult.fromJson(<String, dynamic>{
      'status': 'matched',
      'difficulty': 'easy',
      'variant': 'classic16',
      'boardSize': 16,
      'cellCount': 256,
      'roomId': 'classic16:room-1',
    });

    expect(nine.variant, same(SudokuVariant.classic9));
    expect(nine.cellCount, 81);
    expect(sixteen.variant, same(SudokuVariant.classic16));
    expect(sixteen.cellCount, 256);
    expect(sixteen.matched, isTrue);
  });

  test('rejects inconsistent variant response metadata', () {
    expect(
      () => VariantMatchmakingResult.fromJson(<String, dynamic>{
        'variant': 'classic16',
        'boardSize': 9,
        'cellCount': 81,
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('join sends numeric classic16 payload and auth headers', () async {
    late http.Request captured;
    final client = VariantMatchmakingClient(
      baseUrl: 'https://example.test',
      tokenProvider: () async => 'firebase-token',
      appCheckProvider: () async => 'app-check-token',
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, Object>{
            'status': 'matched',
            'difficulty': 'medium',
            'variant': 'classic16',
            'boardSize': 16,
            'cellCount': 256,
            'roomId': 'classic16:room-2',
          }),
          201,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final result = await client.joinRankedQueue(
      difficulty: 'medium',
      variant: SudokuVariant.classic16,
    );

    expect(captured.url.path, '/v1/matchmaking/queue');
    expect(captured.headers['authorization'], 'Bearer firebase-token');
    expect(captured.headers['x-firebase-appcheck'], 'app-check-token');
    expect(jsonDecode(captured.body), <String, Object>{
      'difficulty': 'medium',
      'variant': 'classic16',
      'boardSize': 16,
      'cellCount': 256,
      'boxRows': 4,
      'boxColumns': 4,
    });
    expect(result.variant, same(SudokuVariant.classic16));
    expect(result.roomId, 'classic16:room-2');
  });
  test(
    'does not send queue request when App Check acquisition fails',
    () async {
      var requestSent = false;

      final client = VariantMatchmakingClient(
        baseUrl: 'https://example.test',
        tokenProvider: () async => 'firebase-token',
        appCheckProvider: () async {
          throw StateError('app-check-unavailable');
        },
        client: MockClient((request) async {
          requestSent = true;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        client.joinRankedQueue(
          difficulty: 'easy',
          variant: SudokuVariant.classic9,
        ),
        throwsA(isA<StateError>()),
      );

      expect(requestSent, isFalse);
    },
  );
}
