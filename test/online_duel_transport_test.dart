import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/services/online_duel_transport.dart';

void main() {
  test('websocket headers include Auth and App Check separately', () {
    final headers = onlineDuelHeadersForTest(
      firebaseIdToken: 'firebase-token',
      appCheckToken: 'app-check-token',
    );

    expect(headers['authorization'], 'Bearer firebase-token');
    expect(headers['x-firebase-appcheck'], 'app-check-token');
    expect(headers['authorization'], isNot(headers['x-firebase-appcheck']));
  });

  test('websocket headers omit empty App Check token', () {
    final headers = onlineDuelHeadersForTest(
      firebaseIdToken: 'firebase-token',
      appCheckToken: '',
    );

    expect(headers, isNot(contains('x-firebase-appcheck')));
  });
}
