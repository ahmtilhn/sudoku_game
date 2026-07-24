import 'dart:async';
import 'dart:ui';

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
  static const String _crashReportingEnabledKey =
      'crash_reporting_enabled_v1';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  final ValueNotifier<bool> analyticsEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<bool> crashReportingEnabled = ValueNotifier<bool>(false);

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    final initialized = await FirebaseRuntimeConfig.initializeIfConfigured();
    if (!initialized) return;

    await _activateAppCheck();
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

  Future<void> logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
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
    await FirebaseCrashlytics.instance.recordError(error, stackTrace);
  }

  Future<void> _activateAppCheck() async {
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode
          ? AppleProvider.debug
          : AppleProvider.appAttestWithDeviceCheckFallback,
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
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      if (crashReportingEnabled.value) {
        unawaited(
          FirebaseCrashlytics.instance.recordFlutterFatalError(details),
        );
      }
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      if (crashReportingEnabled.value) {
        unawaited(
          FirebaseCrashlytics.instance.recordError(
            error,
            stack,
            fatal: true,
          ),
        );
      }
      return false;
    };
  }

  Future<void> _configureAnalytics() async {
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(
      analyticsEnabled.value,
    );
  }
}
