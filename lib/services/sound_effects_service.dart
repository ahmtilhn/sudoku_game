import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SoundEffect {
  uiClick('audio/ui/ui_click.mp3', .35),
  uiPrimaryClick('audio/ui/ui_back.mp3', .42),
  uiBack('audio/ui/ui_back.mp3', .32),
  uiModalOpen('audio/online/countdown_tick.mp3', .28),
  uiModalClose('audio/ui/ui_click.mp3', .25),
  uiToggleOn('audio/gameplay/correct_move.mp3', .30),
  uiToggleOff('audio/ui/ui_back.mp3', .27),
  uiTab('audio/ui/ui_click.mp3', .28),
  uiSelect('audio/gameplay/number_input.mp3', .28),
  uiError('audio/gameplay/wrong_move.mp3', .32),

  gameStart('audio/online/match_start.mp3', .40),
  cellSelect('audio/ui/ui_click.mp3', .18),
  numberInput('audio/gameplay/number_input.mp3', .34),
  correctMove('audio/gameplay/correct_move.mp3', .32),
  wrongMove('audio/gameplay/wrong_move.mp3', .42),
  notesModeOn('audio/gameplay/correct_move.mp3', .25),
  notesModeOff('audio/ui/ui_back.mp3', .22),
  noteAdd('audio/gameplay/number_input.mp3', .20),
  noteRemove('audio/ui/ui_back.mp3', .18),
  erase('audio/ui/ui_back.mp3', .25),
  undo('audio/online/countdown_tick.mp3', .28),
  hintActivate('audio/online/countdown_tick.mp3', .32),
  hintApply('audio/gameplay/correct_move.mp3', .38),
  unitComplete('audio/gameplay/unit_complete.mp3', .45),
  puzzleComplete('audio/gameplay/puzzle_complete.mp3', .65),
  perfectGame('audio/rewards/achievement_unlocked.mp3', .70),
  puzzleFailed('audio/online/online_defeat.mp3', .52),
  pauseOpen('audio/ui/ui_back.mp3', .22),
  pauseResume('audio/gameplay/correct_move.mp3', .25),
  timerWarning('audio/online/countdown_tick.mp3', .32),
  newBestTime('audio/rewards/achievement_unlocked.mp3', .60),

  careerLevelStart('audio/online/match_start.mp3', .40),
  careerLevelComplete('audio/gameplay/puzzle_complete.mp3', .62),
  careerStageUnlock('audio/online/match_start.mp3', .58),

  matchmakingStarted('audio/online/countdown_tick.mp3', .30),
  matchFound('audio/online/match_found.mp3', .65),
  matchmakingCancelled('audio/ui/ui_back.mp3', .25),
  matchmakingFailed('audio/gameplay/wrong_move.mp3', .38),
  ready('audio/gameplay/correct_move.mp3', .40),
  opponentReady('audio/online/match_found.mp3', .48),
  countdownTick('audio/online/countdown_tick.mp3', .34),
  countdown3('audio/online/countdown_tick.mp3', .46),
  countdown2('audio/online/countdown_tick.mp3', .52),
  countdown1('audio/online/countdown_tick.mp3', .60),
  matchStart('audio/online/match_start.mp3', .62),
  opponentMistake('audio/gameplay/wrong_move.mp3', .25),
  takeLead('audio/gameplay/correct_move.mp3', .30),
  loseLead('audio/gameplay/wrong_move.mp3', .27),
  onlineVictory('audio/online/online_victory.mp3', .72),
  onlineDefeat('audio/online/online_defeat.mp3', .55),
  opponentSurrendered('audio/gameplay/puzzle_complete.mp3', .58),
  opponentDisconnected('audio/gameplay/wrong_move.mp3', .35),
  reconnected('audio/gameplay/correct_move.mp3', .32),

  emoteSend('audio/ui/ui_click.mp3', .25),
  emoteReceive('audio/online/match_found.mp3', .34),
  friendRequestSent('audio/gameplay/correct_move.mp3', .34),
  friendRequestReceived('audio/online/match_found.mp3', .42),
  friendRequestAccepted('audio/rewards/daily_reward_claim.mp3', .48),
  friendRemoved('audio/ui/ui_back.mp3', .24),
  challengeSent('audio/gameplay/correct_move.mp3', .34),
  challengeReceived('audio/online/match_found.mp3', .48),
  challengeAccepted('audio/rewards/daily_reward_claim.mp3', .48),

  eloGain('audio/rank/elo_gain.mp3', .52),
  eloLoss('audio/gameplay/wrong_move.mp3', .36),
  rankStepUp('audio/rank/elo_gain.mp3', .58),
  rankPromotion('audio/rewards/achievement_unlocked.mp3', .72),
  rankDemotion('audio/online/online_defeat.mp3', .48),
  leaderboardUp('audio/rank/elo_gain.mp3', .42),
  leaderboardDown('audio/gameplay/wrong_move.mp3', .28),

  coinSmall('audio/economy/coin_small.mp3', .42),
  coinBundle('audio/economy/reward_x2.mp3', .52),
  coinLarge('audio/rewards/daily_reward_claim.mp3', .58),
  rewardX2('audio/economy/reward_x2.mp3', .60),
  coinSpend('audio/economy/coin_small.mp3', .30),
  insufficientCoins('audio/gameplay/wrong_move.mp3', .35),

  dailyRewardClaim('audio/rewards/daily_reward_claim.mp3', .58),
  dailyRewardX2('audio/economy/reward_x2.mp3', .64),
  streakMilestone('audio/rewards/achievement_unlocked.mp3', .68),
  achievementUnlocked('audio/rewards/achievement_unlocked.mp3', .68),
  rareAchievement('audio/online/online_victory.mp3', .72),

  profileItemSelect('audio/ui/ui_click.mp3', .25),
  profileItemEquipped('audio/gameplay/correct_move.mp3', .38),
  cosmeticUnlocked('audio/rewards/daily_reward_claim.mp3', .52),
  lockedItem('audio/gameplay/wrong_move.mp3', .30),

  shopItemSelect('audio/ui/ui_click.mp3', .25),
  shopBuyButton('audio/ui/ui_back.mp3', .34),
  purchaseSuccess('audio/rewards/daily_reward_claim.mp3', .58),
  purchaseFailed('audio/gameplay/wrong_move.mp3', .38),
  purchaseRestored('audio/gameplay/correct_move.mp3', .45),

  adRewardGranted('audio/rewards/daily_reward_claim.mp3', .55),
  adRewardDoubled('audio/economy/reward_x2.mp3', .62),

  genericSuccess('audio/gameplay/correct_move.mp3', .32),
  genericError('audio/gameplay/wrong_move.mp3', .34),
  connectionLost('audio/gameplay/wrong_move.mp3', .38),
  connectionRestored('audio/gameplay/correct_move.mp3', .36);

  const SoundEffect(this.assetPath, this.volume);

  final String assetPath;
  final double volume;

  bool get useMediaPlayer => const <SoundEffect>{
    SoundEffect.puzzleComplete,
    SoundEffect.perfectGame,
    SoundEffect.puzzleFailed,
    SoundEffect.careerLevelComplete,
    SoundEffect.onlineVictory,
    SoundEffect.onlineDefeat,
    SoundEffect.opponentSurrendered,
    SoundEffect.rankPromotion,
    SoundEffect.rankDemotion,
    SoundEffect.streakMilestone,
    SoundEffect.achievementUnlocked,
    SoundEffect.rareAchievement,
  }.contains(this);
}

class SoundEffectsService {
  SoundEffectsService._();

  static final SoundEffectsService instance = SoundEffectsService._();
  static const String _enabledKey = 'sound_effects_enabled_v1';
  static const int _poolSize = 6;

  static final List<String> _preloadAssets = SoundEffect.values
      .map((effect) => effect.assetPath)
      .toSet()
      .toList(growable: false);

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);
  List<AudioPlayer>? _players;

  // Short Sudoku/game SFX should obey the iOS Ring/Silent switch and should
  // not interrupt music or podcasts already playing on the device. The generic
  // AudioContextConfig cannot represent that iOS combination because
  // respectSilence + mixWithOthers is intentionally rejected by audioplayers.
  // AVAudioSessionCategory.ambient provides both behaviors natively.
  final AudioContext _audioContext = AudioContext(
    android: AudioContextAndroid(
      stayAwake: false,
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.game,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  int _nextPlayer = 0;
  bool _initialized = false;
  bool _preloaded = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final preferences = SharedPreferencesAsync();
      enabled.value = await preferences.getBool(_enabledKey) ?? true;
    } catch (error) {
      debugPrint('Sound preference unavailable: $error');
    }
    _initialized = true;
    if (enabled.value) unawaited(_preload());
  }

  Future<void> setEnabled(bool value) async {
    if (!_initialized) await initialize();
    if (enabled.value == value) return;
    enabled.value = value;
    try {
      final preferences = SharedPreferencesAsync();
      await preferences.setBool(_enabledKey, value);
    } catch (error) {
      debugPrint('Sound preference could not be saved: $error');
    }
    if (value) {
      unawaited(_preload());
      await play(SoundEffect.uiToggleOn);
    } else {
      await stopAll();
    }
  }

  Future<void> play(SoundEffect effect, {double volumeScale = 1}) async {
    // Do not touch plugins/preferences from isolated widget tests that did not
    // bootstrap the app services. Normal app startup initializes this service.
    if (!_initialized || !enabled.value) return;

    final volume = (effect.volume * volumeScale).clamp(0.0, 1.0).toDouble();
    try {
      final players = _players ??= List<AudioPlayer>.generate(
        _poolSize,
        (_) => AudioPlayer(),
      );
      final player = players[_nextPlayer];
      _nextPlayer = (_nextPlayer + 1) % players.length;
      await player.play(
        AssetSource(effect.assetPath),
        volume: volume,
        mode: effect.useMediaPlayer
            ? PlayerMode.mediaPlayer
            : PlayerMode.lowLatency,
        ctx: _audioContext,
      );
    } catch (error) {
      // Audio must never interrupt Sudoku or an online duel.
      debugPrint('Sound effect ${effect.name} unavailable: $error');
    }
  }

  Future<void> stopAll() async {
    final players = _players;
    if (players == null) return;
    await Future.wait(
      players.map((player) async {
        try {
          await player.stop();
        } catch (_) {}
      }),
    );
  }

  Future<void> _preload() async {
    if (_preloaded || !_initialized || !enabled.value) return;
    try {
      await AudioCache.instance.loadAll(_preloadAssets);
      _preloaded = true;
    } catch (error) {
      // Lazy playback remains available if preloading is not supported.
      debugPrint('Sound preload unavailable: $error');
    }
  }
}
