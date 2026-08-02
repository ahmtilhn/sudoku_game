import 'package:flutter/foundation.dart';

class ReleaseConfiguration {
  const ReleaseConfiguration._();

  static const String environment = String.fromEnvironment(
    'APP_ENVIRONMENT',
    defaultValue: 'development',
  );
  static const String socialBackendUrl = String.fromEnvironment(
    'SOCIAL_BACKEND_URL',
  );
  static const String buildCommit = String.fromEnvironment('BUILD_COMMIT');

  static void validate() {
    if (!kReleaseMode) return;

    final errors = <String>[];
    final normalizedEnvironment = environment.trim().toLowerCase();
    if (normalizedEnvironment != 'production') {
      errors.add('APP_ENVIRONMENT must be production for release builds.');
    }

    final uri = Uri.tryParse(socialBackendUrl.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      errors.add('SOCIAL_BACKEND_URL must be a valid HTTPS production URL.');
    } else if (
        uri.host.toLowerCase().contains('staging') ||
        uri.host == 'localhost' ||
        uri.host == '127.0.0.1') {
      errors.add('SOCIAL_BACKEND_URL must not point to staging or localhost.');
    }

    final commit = buildCommit.trim();
    if (!RegExp(r'^[0-9a-fA-F]{7,40}$').hasMatch(commit)) {
      errors.add('BUILD_COMMIT must contain the release Git commit SHA.');
    }

    if (errors.isNotEmpty) {
      throw StateError(
        'Invalid release configuration:\n${errors.map((e) => '- $e').join('\n')}',
      );
    }
  }
}
