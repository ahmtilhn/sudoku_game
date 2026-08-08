import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import 'firebase_runtime_config.dart';
import 'firebase_session_service.dart';
import 'platform_game_services.dart';
import 'social_api_client.dart';

class ServiceDiagnosticEntry {
  const ServiceDiagnosticEntry({
    required this.name,
    required this.status,
    required this.detail,
  });

  final String name;
  final String status;
  final String detail;

  bool get ok => status == 'PASS';
}

class ServiceDiagnosticsReport {
  const ServiceDiagnosticsReport({
    required this.generatedAt,
    required this.entries,
  });

  final DateTime generatedAt;
  final List<ServiceDiagnosticEntry> entries;

  bool get passed => entries.every((entry) => entry.ok);

  String asText() {
    final buffer = StringBuffer()
      ..writeln('Sudoku Duel service diagnostics')
      ..writeln('Generated: ${generatedAt.toUtc().toIso8601String()}');
    for (final entry in entries) {
      buffer.writeln('${entry.status} ${entry.name}: ${entry.detail}');
    }
    return buffer.toString().trimRight();
  }
}

class ServiceDiagnosticsService {
  ServiceDiagnosticsService({http.Client? client})
    : _client = client ?? http.Client();

  static const String buildCommit = String.fromEnvironment(
    'BUILD_COMMIT',
    defaultValue: 'unknown',
  );
  static const String appEnvironment = String.fromEnvironment(
    'APP_ENVIRONMENT',
    defaultValue: 'release',
  );
  static const bool internalTesting = bool.fromEnvironment('INTERNAL_TESTING');
  static const Duration _timeout = Duration(seconds: 15);

  final http.Client _client;

  Future<ServiceDiagnosticsReport> run() async {
    final entries = <ServiceDiagnosticEntry>[
      _entry(
        'Build defines',
        'PASS',
        'environment=$appEnvironment, internalTesting=$internalTesting, '
            'buildCommit=$buildCommit',
      ),
      _entry(
        'Social backend config',
        SocialApiClient.instance.configured ? 'PASS' : 'FAIL',
        'configured=${SocialApiClient.instance.configured}, '
            'baseUrl=${SocialApiClient.instance.baseUrl}',
      ),
      _entry(
        'Firebase runtime config',
        FirebaseRuntimeConfig.configured ? 'PASS' : 'FAIL',
        'expectedProject=${FirebaseRuntimeConfig.expectedProjectId}',
      ),
    ];

    await _addPlayGames(entries);
    await _addFirebase(entries);
    await _addWorkerHealth(entries);
    await _addAuthenticatedSocial(entries);

    return ServiceDiagnosticsReport(
      generatedAt: DateTime.now(),
      entries: List<ServiceDiagnosticEntry>.unmodifiable(entries),
    );
  }

  Future<void> _addPlayGames(List<ServiceDiagnosticEntry> entries) async {
    try {
      final diagnostics = await PlatformGameServices.instance.getDiagnostics();
      final configured = await PlatformGameServices.instance.isConfigured();
      entries.add(
        _entry(
          'Play Games runtime',
          configured ? 'PASS' : 'FAIL',
          diagnostics.conciseSummary.isEmpty
              ? 'configured=$configured'
              : 'configured=$configured, ${diagnostics.conciseSummary}',
        ),
      );
    } catch (error) {
      entries.add(_entry('Play Games runtime', 'WARN', _safeError(error)));
    }
  }

  Future<void> _addFirebase(List<ServiceDiagnosticEntry> entries) async {
    try {
      final initialized = await FirebaseRuntimeConfig.initializeIfConfigured();
      if (!initialized) {
        entries.add(
          _entry('Firebase initialization', 'FAIL', 'not configured'),
        );
        return;
      }
      final project = Firebase.app().options.projectId;
      final user = await FirebaseSessionService.ensureAnonymousSession();
      final providers = user.providerData
          .map((provider) => provider.providerId)
          .join(',');
      entries.add(
        _entry(
          'Firebase session',
          'PASS',
          'project=$project, uidPresent=${user.uid.isNotEmpty}, '
              'anonymous=${user.isAnonymous}, providers=$providers',
        ),
      );

      final idToken = await user.getIdToken().timeout(_timeout);
      entries.add(
        _entry(
          'Firebase ID token',
          idToken == null || idToken.isEmpty ? 'FAIL' : 'PASS',
          'available=${idToken != null && idToken.isNotEmpty}',
        ),
      );

      try {
        final appCheck = await FirebaseAppCheck.instance
            .getToken(false)
            .timeout(const Duration(seconds: 5));
        entries.add(
          _entry(
            'Firebase App Check',
            appCheck == null || appCheck.isEmpty ? 'WARN' : 'PASS',
            'tokenAvailable=${appCheck != null && appCheck.isNotEmpty}',
          ),
        );
      } catch (error) {
        entries.add(_entry('Firebase App Check', 'WARN', _safeError(error)));
      }
    } catch (error) {
      entries.add(_entry('Firebase session', 'FAIL', _safeError(error)));
    }
  }

  Future<void> _addWorkerHealth(List<ServiceDiagnosticEntry> entries) async {
    final baseUrl = SocialApiClient.instance.baseUrl;
    if (!SocialApiClient.instance.configured) return;
    await _addHttpCheck(entries, 'Worker health', '$baseUrl/health');
    await _addHttpCheck(entries, 'Worker version', '$baseUrl/version');
  }

  Future<void> _addAuthenticatedSocial(
    List<ServiceDiagnosticEntry> entries,
  ) async {
    if (!SocialApiClient.instance.configured ||
        FirebaseAuth.instance.currentUser == null) {
      return;
    }
    try {
      final preferences = await SocialApiClient.instance
          .ensureProfile()
          .timeout(_timeout);
      entries.add(
        _entry(
          'Authenticated social API',
          'PASS',
          'publicIdPresent=${preferences.publicId.isNotEmpty}, '
              'username=${preferences.username}',
        ),
      );
    } catch (error) {
      entries.add(
        _entry('Authenticated social API', 'FAIL', _safeError(error)),
      );
    }
  }

  Future<void> _addHttpCheck(
    List<ServiceDiagnosticEntry> entries,
    String name,
    String url,
  ) async {
    try {
      final response = await _client
          .get(
            Uri.parse(url),
            headers: const <String, String>{'accept': 'application/json'},
          )
          .timeout(_timeout);
      entries.add(
        _entry(
          name,
          response.statusCode >= 200 && response.statusCode < 300
              ? 'PASS'
              : 'FAIL',
          'status=${response.statusCode}, body=${_compactBody(response.body)}',
        ),
      );
    } catch (error) {
      entries.add(_entry(name, 'FAIL', _safeError(error)));
    }
  }

  ServiceDiagnosticEntry _entry(String name, String status, String detail) {
    return ServiceDiagnosticEntry(
      name: name,
      status: status,
      detail: _redact(detail),
    );
  }

  String _compactBody(String body) {
    if (body.trim().isEmpty) return 'empty';
    try {
      final decoded = jsonDecode(body);
      return jsonEncode(decoded);
    } catch (_) {
      return body.trim();
    }
  }

  String _safeError(Object error) => _redact(error.toString());

  String _redact(String value) {
    var result = value;
    result = result.replaceAll(
      RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
      'Bearer [redacted]',
    );
    result = result.replaceAll(
      RegExp(r'idToken[=:]\s*[A-Za-z0-9._~+/=-]+', caseSensitive: false),
      'idToken=[redacted]',
    );
    result = result.replaceAll(
      RegExp(r'api[_-]?key[=:]\s*[A-Za-z0-9._~-]+', caseSensitive: false),
      'apiKey=[redacted]',
    );
    if (result.length <= 360) return result;
    return '${result.substring(0, 357)}...';
  }
}
