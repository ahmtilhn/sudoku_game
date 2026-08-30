import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/services/sound_effects_service.dart';

void main() {
  test('sound service is safe before platform bootstrap', () async {
    final service = SoundEffectsService.instance;
    expect(service.enabled.value, isTrue);
    await service.play(SoundEffect.uiClick);
  });

  test('sound assets and production integration remain wired', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('audioplayers: ^6.8.1'));

    const assets = <String>[
      'assets/audio/ui/ui_click.mp3',
      'assets/audio/ui/ui_back.mp3',
      'assets/audio/gameplay/number_input.mp3',
      'assets/audio/gameplay/correct_move.mp3',
      'assets/audio/gameplay/wrong_move.mp3',
      'assets/audio/online/countdown_tick.mp3',
      'assets/audio/gameplay/unit_complete.mp3',
      'assets/audio/gameplay/puzzle_complete.mp3',
      'assets/audio/online/match_found.mp3',
      'assets/audio/online/match_start.mp3',
      'assets/audio/rewards/daily_reward_claim.mp3',
      'assets/audio/economy/reward_x2.mp3',
      'assets/audio/rank/elo_gain.mp3',
      'assets/audio/rewards/achievement_unlocked.mp3',
      'assets/audio/economy/coin_small.mp3',
      'assets/audio/online/online_victory.mp3',
      'assets/audio/online/online_defeat.mp3',
    ];
    for (final asset in assets) {
      expect(File(asset).existsSync(), isTrue, reason: 'Missing $asset');
      expect(pubspec, contains('- $asset'));
    }

    final service = File(
      'lib/services/sound_effects_service.dart',
    ).readAsStringSync();
    expect(service, contains('sound_effects_enabled_v1'));
    expect(service, contains('AudioContextConfigFocus.mixWithOthers'));
    expect(service, contains('respectSilence: true'));
    expect(service, contains('PlayerMode.lowLatency'));
    expect(service, contains('enum SoundEffect'));
    expect(service, contains('onlineVictory'));
    expect(service, contains('rankPromotion'));
    expect(service, contains('purchaseSuccess'));
    expect(service, contains('adRewardGranted'));

    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('SoundEffectsService.instance.initialize()'));

    final settings = File(
      'lib/features/settings/ux_settings_screen.dart',
    ).readAsStringSync();
    expect(settings, contains('SoundEffectsService.instance.enabled'));
    expect(settings, contains('SettingsStrings.soundEffectsTitle(context)'));

    final gameplay = File(
      'lib/features/game/enhanced_game_screen.dart',
    ).readAsStringSync();
    for (final event in <String>[
      'SoundEffect.cellSelect',
      'SoundEffect.numberInput',
      'SoundEffect.wrongMove',
      'SoundEffect.noteAdd',
      'SoundEffect.erase',
      'SoundEffect.undo',
      'SoundEffect.hintActivate',
      'SoundEffect.unitComplete',
      'SoundEffect.puzzleComplete',
      'SoundEffect.puzzleFailed',
    ]) {
      expect(gameplay, contains(event), reason: event);
    }

    final countdown = File(
      'lib/features/duel/online_ready_countdown_overlay.dart',
    ).readAsStringSync();
    expect(countdown, contains('SoundEffect.countdown3'));
    expect(countdown, contains('SoundEffect.countdown2'));
    expect(countdown, contains('SoundEffect.countdown1'));
    expect(countdown, contains('SoundEffect.matchStart'));

    final duel = File(
      'lib/features/duel/online_duel_screen.dart',
    ).readAsStringSync();
    expect(duel, contains('SoundEffect.onlineVictory'));
    expect(duel, contains('SoundEffect.onlineDefeat'));
    expect(duel, contains('SoundEffect.connectionLost'));
  });
}
