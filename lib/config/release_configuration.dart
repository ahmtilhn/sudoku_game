import 'package:flutter/foundation.dart';

class ReleaseConfiguration {
  const ReleaseConfiguration._();

  static const String environment = String.fromEnvironment(
    'APP_ENVIRONMENT',
    defaultValue: 'development',
  );
  static const bool internalTesting = bool.fromEnvironment(
    'INTERNAL_TESTING',
    defaultValue: false,
  );
  static const String socialBackendUrl = String.fromEnvironment(
    'SOCIAL_BACKEND_URL',
  );
  static const String buildCommit = String.fromEnvironment('BUILD_COMMIT');

  static void validate() {
    if (!kReleaseMode) return;

    final errors = <String>[];
    final normalizedEnvironment = environment.trim().toLowerCase();
    final isProduction = normalizedEnvironment == 'production';
    final isInternalStaging =
        internalTesting && normalizedEnvironment == 'staging';

    if (!isProduction && !isInternalStaging) {
      errors.add(
        'APP_ENVIRONMENT must be production, or staging together with '
        'INTERNAL_TESTING=true for a Play internal-testing build.',
      );
    }

    final uri = Uri.tryParse(socialBackendUrl.trim());
    final host = uri?.host.trim().toLowerCase() ?? '';
    final isLocalHost = host == 'localhost' || host == '127.0.0.1';
    final isPlaceholderHost =
        host.contains('gercek-production-worker-adresi') ||
        host.contains('replace_with') ||
        host.contains('example');
    final isStagingHost = host.contains('staging');

    if (uri == null || uri.scheme != 'https' || host.isEmpty) {
      errors.add('SOCIAL_BACKEND_URL must be a valid HTTPS URL.');
    } else if (isLocalHost || isPlaceholderHost) {
      errors.add(
        'SOCIAL_BACKEND_URL must not point to localhost or a placeholder host.',
      );
    } else if (isProduction && isStagingHost) {
      errors.add(
        'A production release must not use a staging SOCIAL_BACKEND_URL.',
      );
    } else if (isInternalStaging && !isStagingHost) {
      errors.add(
        'An internal staging build must use a staging SOCIAL_BACKEND_URL.',
      );
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
