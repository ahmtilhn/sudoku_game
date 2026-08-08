import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/services/platform_game_services.dart';

void main() {
  group('GameCenterIdentityProof', () {
    test('accepts the iOS bridge playerId fallback', () {
      final proof = GameCenterIdentityProof.fromMap(<Object?, Object?>{
        'playerId': 'G:12345',
        'displayName': 'Sudoku Pilot',
        'publicKeyUrl': 'https://static.gc.apple.com/public-key.cer',
        'signature': 'c2lnbmF0dXJl',
        'salt': 'c2FsdA==',
        'timestamp': 1234567890,
        'bundleId': 'com.devovia.sudokuduel',
      });

      expect(proof.hasSignatureMaterial, isTrue);
      expect(proof.gamePlayerId, 'G:12345');
      expect(proof.toJson()['platformPlayerId'], 'G:12345');
      expect(proof.toJson()['bundleId'], 'com.devovia.sudokuduel');
    });
  });

  group('PlayGamesDiagnostics', () {
    test('recognizes the Google Play app-signing certificate', () {
      final diagnostics = PlayGamesDiagnostics.fromMap(<Object?, Object?>{
        'packageName': 'com.devoviastudio.sudoku',
        'projectId': '917838292556',
        'certificateSha1':
            'c0:4c:3a:ab:7d:76:6c:2e:87:c9:53:98:eb:4b:59:97:52:cd:25:a1',
        'installer': 'com.android.vending',
        'apiStatusCode': 'none',
      });

      expect(diagnostics.installedFromGooglePlay, isTrue);
      expect(diagnostics.certificateMatchesPlayAppSigning, isTrue);
      expect(diagnostics.conciseSummary, contains('com.devoviastudio.sudoku'));
    });

    test(
      'reports a certificate mismatch without treating it as configured',
      () {
        final diagnostics = PlayGamesDiagnostics.fromMap(<Object?, Object?>{
          'certificateSha1':
              'D4:EA:36:D4:6C:F9:58:07:45:6B:A3:6D:28:1D:6A:DC:6D:2C:E9:48',
          'installer': 'com.android.vending',
        });

        expect(diagnostics.installedFromGooglePlay, isTrue);
        expect(diagnostics.certificateMatchesPlayAppSigning, isFalse);
      },
    );
  });

  test('platform exceptions retain native diagnostic details', () {
    const exception = PlatformGameServicesException(
      'authentication_failed',
      'Google Play Games authentication failed.',
      diagnostics: <String, String>{
        'certificateSha1': 'AA:BB',
        'apiStatusCode': '10',
        'apiStatusName': 'DEVELOPER_ERROR',
      },
    );

    expect(exception.toString(), contains('status=10 (DEVELOPER_ERROR)'));
    expect(exception.diagnostics['certificateSha1'], 'AA:BB');
  });

  test('platform exceptions summarize Game Center diagnostics', () {
    const exception = PlatformGameServicesException(
      'not_configured',
      'Game Center is not configured.',
      diagnostics: <String, String>{
        'platform': 'game_center',
        'bundleIdentifier': 'com.devovia.sudokuduel',
        'configured': 'false',
        'gameCenterEntitlement': 'false',
      },
    );

    expect(exception.toString(), contains('platform=game_center'));
    expect(exception.toString(), contains('bundle=com.devovia.sudokuduel'));
    expect(exception.toString(), contains('gameCenterEntitlement=false'));
  });
}
