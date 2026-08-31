import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/services/haptic_feedback_service.dart';

class _MemoryHapticPreferences implements HapticPreferenceStore {
  _MemoryHapticPreferences(this.value);
  bool? value;
  @override
  Future<bool?> getBool(String key) async => value;
  @override
  Future<void> setBool(String key, bool value) async {
    this.value = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('disabled haptics suppress every platform vibration', () async {
    final preferences = _MemoryHapticPreferences(false);
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final service = HapticFeedbackService.forTesting(preferences);
    await service.initialize();
    expect(service.enabled.value, isFalse);
    await service.selectionClick();
    await service.lightImpact();
    await service.mediumImpact();
    await service.heavyImpact();
    await service.vibrate();
    expect(calls, isEmpty);

    await service.setEnabled(true);
    expect(service.enabled.value, isTrue);
    expect(preferences.value, isTrue);
    expect(calls, isNotEmpty);
    calls.clear();
    await service.heavyImpact();
    expect(calls, hasLength(1));

    await service.setEnabled(false);
    expect(service.enabled.value, isFalse);
    expect(preferences.value, isFalse);
    calls.clear();
    await service.selectionClick();
    expect(calls, isEmpty);
  });

  test('feature code cannot bypass HapticFeedbackService', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalized = entity.path.replaceAll('\\', '/');
      if (normalized.endsWith('lib/services/haptic_feedback_service.dart'))
        continue;
      if (entity.readAsStringSync().contains('HapticFeedback.'))
        offenders.add(normalized);
    }
    expect(offenders, isEmpty, reason: 'All app haptics must honor Settings.');
  });
}
