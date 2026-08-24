import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/services/social_api_client.dart';

void main() {
  test('builds resolve a valid social backend URL by default', () {
    final client = SocialApiClient.instance;

    expect(client.configured, isTrue);
    expect(client.baseUrl, SocialApiClient.defaultSocialBackendUrl);
    expect(client.baseUrl, isNot(endsWith('/')));
    expect(client.usingBundledDefault, isTrue);
  });

  group('backend URL resolver', () {
    test('debug build without an explicit URL uses production', () {
      final url = SocialApiClient.resolveBaseUrlForTest(
        configuredBaseUrl: '',
        debugMode: true,
      );

      expect(url, SocialApiClient.productionSocialBackendUrl);
      expect(url, isNotEmpty);
    });

    test('non-debug build without an explicit URL uses production', () {
      final url = SocialApiClient.resolveBaseUrlForTest(
        configuredBaseUrl: '',
        debugMode: false,
      );

      expect(url, SocialApiClient.productionSocialBackendUrl);
      expect(url, isNotEmpty);
      expect(url, SocialApiClient.defaultSocialBackendUrl);
    });

    test('explicit backend always wins over bundled fallback', () {
      const explicitUrl =
          'https://sudoku-duel-social-production.ilhanahmet246.workers.dev/';

      final debugUrl = SocialApiClient.resolveBaseUrlForTest(
        configuredBaseUrl: explicitUrl,
        debugMode: true,
      );

      final releaseUrl = SocialApiClient.resolveBaseUrlForTest(
        configuredBaseUrl: explicitUrl,
        debugMode: false,
      );

      expect(debugUrl, SocialApiClient.productionSocialBackendUrl);
      expect(releaseUrl, SocialApiClient.productionSocialBackendUrl);
    });

    test('release resolver can never return an empty backend URL', () {
      final url = SocialApiClient.resolveBaseUrlForTest(
        configuredBaseUrl: '',
        debugMode: false,
      );

      expect(url, isNotEmpty);
      expect(Uri.parse(url).scheme, 'https');
      expect(Uri.parse(url).host, isNotEmpty);
    });
  });

  test('websocket URL uses the same backend host over wss', () {
    final client = SocialApiClient.instance;
    final uri = client.websocketUri('/v1/rooms/test-room/connect');

    expect(uri.scheme, 'wss');
    expect(uri.host, Uri.parse(client.baseUrl).host);
    expect(uri.path, '/v1/rooms/test-room/connect');
  });
}
