import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_runtime_config.dart';

class FirebaseServices {
  FirebaseServices._();

  static final FirebaseServices instance = FirebaseServices._();

  static const String _analyticsEnabledKey = 'analytics_collection_enabled_v1';
  static const String _crashReportingEnabledKey = 'crash_reporting_enabled_v1';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  final ValueNotifier<bool> analyticsEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<bool> crashReportingEnabled = ValueNotifier<bool>(false);

  Future<void>? _initialization;
  Future<void>? _appCheckInitialization;
  bool _initialized = false;
  bool _appCheckActivated = false;

  bool get initialized => _initialized;
  bool get appCheckActivated => _appCheckActivated;

  Future<void> ensureAppCheckReady() {
    if (_appCheckActivated) return Future<void>.value();

    final pending = _appCheckInitialization;
    if (pending != null) return pending;

    final operation = _ensureAppCheckReadyOnce().whenComplete(() {
      _appCheckInitialization = null;
    });

    _appCheckInitialization = operation;
    return operation;
  }

  Future<void> _ensureAppCheckReadyOnce() async {
    final initialized = await FirebaseRuntimeConfig.initializeIfConfigured();

    if (!initialized) {
      throw StateError(
        'Firebase must be configured before App Check can be activated.',
      );
    }

    await _activateAppCheck();
    _appCheckActivated = true;
  }

  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initialization ??= _initializeOnce().whenComplete(() {
      _initialization = null;
    });
  }

  Future<void> _initializeOnce() async {
    final initialized = await FirebaseRuntimeConfig.initializeIfConfigured();
    if (!initialized) return;

    try {
      await ensureAppCheckReady();
    } catch (error, stackTrace) {
      debugPrint('Firebase App Check activation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    await _loadPrivacyPreferences();
    await _configureCrashlytics();
    await _configureAnalytics();

    _initialized = true;
  }

  Future<void> setAnalyticsEnabled(bool enabled) async {
    analyticsEnabled.value = enabled;
    await _preferences.setBool(_analyticsEnabledKey, enabled);
    if (FirebaseRuntimeConfig.configured) {
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(enabled);
    }
  }

  Future<void> setCrashReportingEnabled(bool enabled) async {
    crashReportingEnabled.value = enabled;
    await _preferences.setBool(_crashReportingEnabledKey, enabled);
    if (FirebaseRuntimeConfig.configured) {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        enabled,
      );
    }
  }

  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    if (!analyticsEnabled.value || !FirebaseRuntimeConfig.configured) return;
    await FirebaseAnalytics.instance.logEvent(
      name: name,
      parameters: parameters,
    );
  }

  Future<void> recordNonFatal(Object error, StackTrace stackTrace) async {
    if (!crashReportingEnabled.value || !FirebaseRuntimeConfig.configured) {
      return;
    }
    await FirebaseCrashlytics.instance.recordError(
      error,
      stackTrace,
      fatal: false,
    );
  }

  Future<void> _activateAppCheck() async {
    const AndroidAppCheckProvider androidProvider = kDebugMode
        ? AndroidDebugProvider()
        : AndroidPlayIntegrityProvider();
    const AppleAppCheckProvider appleProvider = kDebugMode
        ? AppleDebugProvider()
        : AppleAppAttestWithDeviceCheckFallbackProvider();

    await FirebaseAppCheck.instance.activate(
      providerAndroid: androidProvider,
      providerApple: appleProvider,
    );
  }

  Future<void> _loadPrivacyPreferences() async {
    analyticsEnabled.value =
        await _preferences.getBool(_analyticsEnabledKey) ?? false;
    crashReportingEnabled.value =
        await _preferences.getBool(_crashReportingEnabledKey) ?? !kDebugMode;
  }

  Future<void> _configureCrashlytics() async {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      crashReportingEnabled.value,
    );

    final previousFlutterErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      if (previousFlutterErrorHandler != null) {
        previousFlutterErrorHandler(details);
      } else {
        FlutterError.presentError(details);
      }
      if (crashReportingEnabled.value) {
        unawaited(
          FirebaseCrashlytics.instance.recordFlutterFatalError(details),
        );
      }
    };

    final previousPlatformErrorHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      if (crashReportingEnabled.value) {
        unawaited(
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true),
        );
      }
      return previousPlatformErrorHandler?.call(error, stack) ??
          crashReportingEnabled.value;
    };
  }

  Future<void> _configureAnalytics() async {
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(
      analyticsEnabled.value,
    );
  }
}
