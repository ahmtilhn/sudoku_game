import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('monitor-only App Check does not client-block reward traffic', () {
    final firebase = File(
      'lib/services/firebase_services.dart',
    ).readAsStringSync();
    final production = File(
      'backend/social_worker/wrangler.production.toml',
    ).readAsStringSync();

    expect(production, contains('REQUIRE_APP_CHECK = "false"'));
    expect(
      firebase,
      contains('continuing without client-side block'),
      reason:
          'When the Worker is monitor-only, an attestation failure must not stop authenticated reward calls before they reach the server.',
    );
    expect(firebase, contains("return '';"));
    expect(firebase, contains('AndroidPlayIntegrityProvider()'));
    expect(firebase, contains('AppleAppAttestWithDeviceCheckFallbackProvider()'));
  });
}
