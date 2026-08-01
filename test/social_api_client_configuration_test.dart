import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/services/social_api_client.dart';

void main() {
  test('debug builds resolve a valid social backend URL', () {
    final client = SocialApiClient.instance;

    expect(client.configured, isTrue);
    expect(client.baseUrl, startsWith('https://'));
    expect(client.baseUrl, isNot(endsWith('/')));
  });

  test('websocket URL uses the same backend host over wss', () {
    final client = SocialApiClient.instance;
    final uri = client.websocketUri('/v1/rooms/test-room/connect');

    expect(uri.scheme, 'wss');
    expect(uri.host, Uri.parse(client.baseUrl).host);
    expect(uri.path, '/v1/rooms/test-room/connect');
  });
}
