import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HapticFeedbackService {
  HapticFeedbackService._();

  static final HapticFeedbackService instance = HapticFeedbackService._();
  static const String _enabledKey = 'haptic_feedback_enabled_v1';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    enabled.value = await _preferences.getBool(_enabledKey) ?? true;
    _initialized = true;
  }

  Future<void> setEnabled(bool value) async {
    if (!_initialized) await initialize();
    if (enabled.value == value) return;
    enabled.value = value;
    await _preferences.setBool(_enabledKey, value);
    if (value) {
      await HapticFeedback.selectionClick();
    }
  }

  Future<void> selectionClick() => _run(HapticFeedback.selectionClick);

  Future<void> lightImpact() => _run(HapticFeedback.lightImpact);

  Future<void> mediumImpact() => _run(HapticFeedback.mediumImpact);

  Future<void> heavyImpact() => _run(HapticFeedback.heavyImpact);

  Future<void> vibrate() => _run(HapticFeedback.vibrate);

  Future<void> _run(Future<void> Function() feedback) async {
    if (!_initialized) await initialize();
    if (!enabled.value) return;
    await feedback();
  }
}
