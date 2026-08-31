import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

@visibleForTesting
abstract interface class HapticPreferenceStore {
  Future<bool?> getBool(String key);
  Future<void> setBool(String key, bool value);
}

class _SharedPreferencesHapticStore implements HapticPreferenceStore {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  Future<bool?> getBool(String key) => _preferences.getBool(key);

  @override
  Future<void> setBool(String key, bool value) =>
      _preferences.setBool(key, value);
}

class HapticFeedbackService {
  HapticFeedbackService._({HapticPreferenceStore? preferences})
    : _preferences = preferences ?? _SharedPreferencesHapticStore();

  static final HapticFeedbackService instance = HapticFeedbackService._();
  static const String _enabledKey = 'haptic_feedback_enabled_v1';

  @visibleForTesting
  factory HapticFeedbackService.forTesting(HapticPreferenceStore preferences) =>
      HapticFeedbackService._(preferences: preferences);

  final HapticPreferenceStore _preferences;
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);
  Future<void>? _initialization;
  Future<void> _writeTail = Future<void>.value();
  bool _initialized = false;

  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initialization ??= _initializeOnce().whenComplete(() {
      _initialization = null;
    });
  }

  Future<void> _initializeOnce() async {
    enabled.value = await _preferences.getBool(_enabledKey) ?? true;
    _initialized = true;
  }

  Future<void> setEnabled(bool value) async {
    await initialize();
    if (enabled.value == value) return;
    enabled.value = value;
    final write = _writeTail.then<void>(
      (_) => _preferences.setBool(_enabledKey, value),
    );
    _writeTail = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    await write;
    if (value && enabled.value) {
      await HapticFeedback.selectionClick();
    }
  }

  Future<void> selectionClick() => _run(HapticFeedback.selectionClick);
  Future<void> lightImpact() => _run(HapticFeedback.lightImpact);
  Future<void> mediumImpact() => _run(HapticFeedback.mediumImpact);
  Future<void> heavyImpact() => _run(HapticFeedback.heavyImpact);
  Future<void> vibrate() => _run(HapticFeedback.vibrate);

  Future<void> _run(Future<void> Function() feedback) async {
    await initialize();
    if (!enabled.value) return;
    await feedback();
  }
}
