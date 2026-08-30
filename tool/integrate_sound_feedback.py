from pathlib import Path

ROOT = Path('.')


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8-sig')


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding='utf-8')


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{path}: expected exactly one match, got {count}: {old[:100]!r}')
    write(path, text.replace(old, new, 1))


# ---------------------------------------------------------------------------
# pubspec: add the playback dependency and only the 17 unique master-equivalent
# runtime files. The repository contains many semantic aliases that are byte-for-
# byte duplicates; explicitly listing the unique sources keeps APK/IPA size sane.
# ---------------------------------------------------------------------------
replace_once(
    'pubspec.yaml',
    '  app_tracking_transparency: ^2.0.7\n',
    '  app_tracking_transparency: ^2.0.7\n  audioplayers: ^6.8.1\n',
)

unique_assets = '''    - assets/audio/ui/ui_click.mp3
    - assets/audio/ui/ui_back.mp3
    - assets/audio/gameplay/number_input.mp3
    - assets/audio/gameplay/correct_move.mp3
    - assets/audio/gameplay/wrong_move.mp3
    - assets/audio/online/countdown_tick.mp3
    - assets/audio/gameplay/unit_complete.mp3
    - assets/audio/gameplay/puzzle_complete.mp3
    - assets/audio/online/match_found.mp3
    - assets/audio/online/match_start.mp3
    - assets/audio/rewards/daily_reward_claim.mp3
    - assets/audio/economy/reward_x2.mp3
    - assets/audio/rank/elo_gain.mp3
    - assets/audio/rewards/achievement_unlocked.mp3
    - assets/audio/economy/coin_small.mp3
    - assets/audio/online/online_victory.mp3
    - assets/audio/online/online_defeat.mp3
'''
replace_once(
    'pubspec.yaml',
    '    - assets/localization/Localizable.xcstrings\n',
    '    - assets/localization/Localizable.xcstrings\n' + unique_assets,
)

for rel in [line.strip()[2:].strip() for line in unique_assets.splitlines() if line.strip()]:
    if not (ROOT / rel).is_file():
        raise RuntimeError(f'Missing required sound asset: {rel}')

# ---------------------------------------------------------------------------
# Sound service: test-safe singleton, persistent setting, pooled low-latency SFX,
# mix-with-others audio focus, respect device silent mode, preload unique masters.
# ---------------------------------------------------------------------------
service = r'''import 'dart:async';

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

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);
  final List<AudioPlayer> _players = List<AudioPlayer>.generate(
    _poolSize,
    (_) => AudioPlayer(),
  );
  final AudioContext _audioContext = AudioContextConfig(
    route: AudioContextConfigRoute.system,
    focus: AudioContextConfigFocus.mixWithOthers,
    respectSilence: true,
    stayAwake: false,
  ).build();

  int _nextPlayer = 0;
  bool _initialized = false;
  bool _preloaded = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      enabled.value = await _preferences.getBool(_enabledKey) ?? true;
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
      await _preferences.setBool(_enabledKey, value);
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

  Future<void> play(
    SoundEffect effect, {
    double volumeScale = 1,
  }) async {
    // Do not touch plugins/preferences from isolated widget tests that did not
    // bootstrap the app services. Normal app startup initializes this service.
    if (!_initialized || !enabled.value) return;

    final player = _players[_nextPlayer];
    _nextPlayer = (_nextPlayer + 1) % _players.length;
    final volume = (effect.volume * volumeScale).clamp(0.0, 1.0).toDouble();
    try {
      await player.play(
        AssetSource(effect.assetPath),
        volume: volume,
        mode: PlayerMode.lowLatency,
        ctx: _audioContext,
      );
    } catch (error) {
      // Audio must never interrupt Sudoku or an online duel.
      debugPrint('Sound effect ${effect.name} unavailable: $error');
    }
  }

  Future<void> stopAll() async {
    await Future.wait(
      _players.map((player) async {
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
'''
service_path = ROOT / 'lib/services/sound_effects_service.dart'
service_path.write_text(service, encoding='utf-8')

# ---------------------------------------------------------------------------
# Startup.
# ---------------------------------------------------------------------------
replace_once(
    'lib/main.dart',
    "import 'services/reminder_notification_service.dart';\n",
    "import 'services/reminder_notification_service.dart';\nimport 'services/sound_effects_service.dart';\n",
)
replace_once(
    'lib/main.dart',
    '  await HapticFeedbackService.instance.initialize();\n',
    '  await HapticFeedbackService.instance.initialize();\n  await SoundEffectsService.instance.initialize();\n',
)

# ---------------------------------------------------------------------------
# Settings localization and toggle.
# ---------------------------------------------------------------------------
replace_once(
    'lib/localization/settings_strings.dart',
    "  static String hapticsSubtitle(BuildContext context) =>\n      _value(context, _hapticsSubtitle);\n\n",
    "  static String hapticsSubtitle(BuildContext context) =>\n      _value(context, _hapticsSubtitle);\n\n  static String soundEffectsTitle(BuildContext context) =>\n      _value(context, _soundEffectsTitle);\n\n  static String soundEffectsSubtitle(BuildContext context) =>\n      _value(context, _soundEffectsSubtitle);\n\n",
)

sound_maps = r'''  static const Map<String, String> _soundEffectsTitle = <String, String>{
    'en': 'Sound effects',
    'tr': 'Ses efektleri',
    'de': 'Soundeffekte',
    'fr': 'Effets sonores',
    'es': 'Efectos de sonido',
    'pt': 'Efeitos sonoros',
    'it': 'Effetti sonori',
    'nl': 'Geluidseffecten',
    'pl': 'Efekty dźwiękowe',
    'ru': 'Звуковые эффекты',
    'uk': 'Звукові ефекти',
    'ar': 'المؤثرات الصوتية',
    'hi': 'ध्वनि प्रभाव',
    'id': 'Efek suara',
    'ja': '効果音',
    'ko': '효과음',
    'zh': '音效',
    'th': 'เอฟเฟกต์เสียง',
    'vi': 'Hiệu ứng âm thanh',
    'bn': 'সাউন্ড ইফেক্ট',
    'ur': 'صوتی اثرات',
  };

  static const Map<String, String> _soundEffectsSubtitle = <String, String>{
    'en': 'Play sounds for moves, results, rewards and important game actions.',
    'tr': 'Hamleler, sonuçlar, ödüller ve önemli oyun işlemlerinde ses çal.',
    'de': 'Sounds bei Zügen, Ergebnissen, Belohnungen und wichtigen Spielaktionen.',
    'fr': 'Joue des sons pour les coups, résultats, récompenses et actions importantes.',
    'es': 'Reproduce sonidos para movimientos, resultados, recompensas y acciones importantes.',
    'pt': 'Reproduz sons em jogadas, resultados, recompensas e ações importantes.',
    'it': 'Riproduce suoni per mosse, risultati, ricompense e azioni importanti.',
    'nl': 'Speel geluiden bij zetten, resultaten, beloningen en belangrijke spelacties.',
    'pl': 'Odtwarza dźwięki ruchów, wyników, nagród i ważnych akcji w grze.',
    'ru': 'Звуки ходов, результатов, наград и важных игровых действий.',
    'uk': 'Звуки ходів, результатів, нагород і важливих ігрових дій.',
    'ar': 'تشغيل أصوات للحركات والنتائج والمكافآت وإجراءات اللعب المهمة.',
    'hi': 'चाल, परिणाम, इनाम और महत्वपूर्ण गेम क्रियाओं के लिए ध्वनि चलाएँ।',
    'id': 'Putar suara untuk langkah, hasil, hadiah, dan aksi game penting.',
    'ja': '手、結果、報酬、重要なゲーム操作で効果音を再生します。',
    'ko': '수, 결과, 보상 및 중요한 게임 동작에 효과음을 재생합니다.',
    'zh': '在落子、结果、奖励和重要游戏操作时播放音效。',
    'th': 'เล่นเสียงสำหรับการเดิน ผลลัพธ์ รางวัล และการกระทำสำคัญในเกม',
    'vi': 'Phát âm thanh cho nước đi, kết quả, phần thưởng và thao tác quan trọng.',
    'bn': 'চাল, ফলাফল, পুরস্কার ও গুরুত্বপূর্ণ গেম অ্যাকশনে শব্দ চালান।',
    'ur': 'چالوں، نتائج، انعامات اور اہم گیم ایکشنز کے لیے آواز چلائیں۔',
  };

'''
replace_once(
    'lib/localization/settings_strings.dart',
    '  static const Map<String, String> _privacyPolicyTitle = <String, String>{\n',
    sound_maps + '  static const Map<String, String> _privacyPolicyTitle = <String, String>{\n',
)

replace_once(
    'lib/features/settings/ux_settings_screen.dart',
    "import '../../services/social_api_client.dart';\n",
    "import '../../services/social_api_client.dart';\nimport '../../services/sound_effects_service.dart';\n",
)
replace_once(
    'lib/features/settings/ux_settings_screen.dart',
    '    unawaited(HapticFeedbackService.instance.initialize());\n',
    '    unawaited(HapticFeedbackService.instance.initialize());\n    unawaited(SoundEffectsService.instance.initialize());\n',
)
old_play_panel = '''        return _SettingsPanel(
          title: context.tr('play'),
          accent: _playAccent,
          compact: compact,
          child: ValueListenableBuilder<bool>(
            valueListenable: haptics.enabled,
            builder: (context, enabled, _) => SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              secondary: const Icon(Icons.vibration_rounded),
              value: enabled,
              onChanged: haptics.setEnabled,
              title: Text(
                SettingsStrings.hapticsTitle(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                SettingsStrings.hapticsSubtitle(context),
                maxLines: compact ? 2 : 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        );
'''
new_play_panel = '''        return _SettingsPanel(
          title: context.tr('play'),
          accent: _playAccent,
          compact: compact,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: SoundEffectsService.instance.enabled,
                builder: (context, enabled, _) => SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  secondary: Icon(
                    enabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                  ),
                  value: enabled,
                  onChanged: SoundEffectsService.instance.setEnabled,
                  title: Text(
                    SettingsStrings.soundEffectsTitle(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    SettingsStrings.soundEffectsSubtitle(context),
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const _SettingsDivider(),
              ValueListenableBuilder<bool>(
                valueListenable: haptics.enabled,
                builder: (context, enabled, _) => SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  secondary: const Icon(Icons.vibration_rounded),
                  value: enabled,
                  onChanged: haptics.setEnabled,
                  title: Text(
                    SettingsStrings.hapticsTitle(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    SettingsStrings.hapticsSubtitle(context),
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        );
'''
replace_once('lib/features/settings/ux_settings_screen.dart', old_play_panel, new_play_panel)

# ---------------------------------------------------------------------------
# Offline/career gameplay core events.
# ---------------------------------------------------------------------------
replace_once(
    'lib/features/game/enhanced_game_screen.dart',
    "import '../../services/offline_reward_service.dart';\n",
    "import '../../services/offline_reward_service.dart';\nimport '../../services/sound_effects_service.dart';\n",
)
replace_once(
    'lib/features/game/enhanced_game_screen.dart',
    '''    setState(() => _ready = true);
    if (_roundLost) {
''',
    '''    setState(() => _ready = true);
    if (saved == null && !_roundLost) {
      unawaited(SoundEffectsService.instance.play(SoundEffect.gameStart));
    }
    if (_roundLost) {
''',
)
replace_once(
    'lib/features/game/enhanced_game_screen.dart',
    '''  Future<void> _showPauseSheet() async {
    if (!_ready || _completed || _roundLost || _paused) return;
    _pauseClock();
''',
    '''  Future<void> _showPauseSheet() async {
    if (!_ready || _completed || _roundLost || _paused) return;
    unawaited(SoundEffectsService.instance.play(SoundEffect.pauseOpen));
    _pauseClock();
''',
)
replace_once(
    'lib/features/game/enhanced_game_screen.dart',
    '''      case 'continue':
      case null:
        if (!_completed && !_roundLost) _startClock();
''',
    '''      case 'continue':
      case null:
        if (!_completed && !_roundLost) {
          unawaited(SoundEffectsService.instance.play(SoundEffect.pauseResume));
          _startClock();
        }
''',
)
replace_once(
    'lib/features/game/enhanced_game_screen.dart',
    '''    setState(() {
      _selectedIndex = index;
      _errorIndex = null;
    });
    _scheduleSave();
''',
    '''    setState(() {
      _selectedIndex = index;
      _errorIndex = null;
    });
    unawaited(SoundEffectsService.instance.play(SoundEffect.cellSelect));
    _scheduleSave();
''',
)
replace_once(
    'lib/features/game/enhanced_game_screen.dart',
    '''    if (_notesMode && widget.allowNotes && _board[index] == 0) {
      setState(() {
        final values = _notes.putIfAbsent(index, () => <int>{});
        values.contains(value) ? values.remove(value) : values.add(value);
        if (values.isEmpty) _notes.remove(index);
      });
      _scheduleSave();
      return;
    }
''',
    '''    if (_notesMode && widget.allowNotes && _board[index] == 0) {
      final removingNote = _notes[index]?.contains(value) == true;
      setState(() {
        final values = _notes.putIfAbsent(index, () => <int>{});
        values.contains(value) ? values.remove(value) : values.add(value);
        if (values.isEmpty) _notes.remove(index);
      });
      unawaited(
        SoundEffectsService.instance.play(
          removingNote ? SoundEffect.noteRemove : SoundEffect.noteAdd,
        ),
      );
      _scheduleSave();
      return;
    }
''',
)
replace_once(
    'lib/features/game/enhanced_game_screen.dart',
    '''    if (widget.puzzle.solution[index] != value) {
      unawaited(HapticFeedback.heavyImpact());
''',
    '''    if (widget.puzzle.solution[index] != value) {
      unawaited(SoundEffectsService.instance.play(SoundEffect.wrongMove));
      unawaited(HapticFeedback.heavyImpact());
''',
)
replace_once(
    'lib/features/game/enhanced_game_screen.dart',
    '''    _scheduleSave();
    unawaited(_checkCompletion());
  }

  void _erase() {
''',
    '''    final puzzleCompleted = SudokuEngine.isComplete(widget.puzzle, _board);
    final unitCompleted = !puzzleCompleted && _hasCompletedUnitAt(index);
    unawaited(
      SoundEffectsService.instance.play(
        unitCompleted ? SoundEffect.unitComplete : SoundEffect.numberInput,
      ),
    );
    _scheduleSave();
    unawaited(_checkCompletion());
  }

  void _erase() {
''',
)
replace_once(
    'lib/features/game/enhanced_game_screen.dart',
    '''      _board[index] = 0;
      _notes.remove(index);
    });
    _scheduleSave();
  }

  void _undo() {
''',
    '''      _board[index] = 0;
      _notes.remove(index);
    });
    unawaited(SoundEffectsService.instance.play(SoundEffect.erase));
    _scheduleSave();
  }

  void _undo() {
''',
)
replace_once(
    'lib/features/game/enhanced_game_screen.dart',
    '''      _selectedIndex = move.index;
      _errorIndex = null;
    });
    _scheduleSave();
  }

  void _toggleNotes() {
''',
    '''      _selectedIndex = move.index;
      _errorIndex = null;
    });
    unawaited(SoundEffectsService.instance.play(SoundEffect.undo));
    _scheduleSave();
  }

  void _toggleNotes() {
''',
)
replace_once(
    'lib/features/game/enhanced_game_screen.dart',
    '''  void _toggleNotes() {
    if (!_ready || _completed || _roundLost) return;
    setState(() => _notesMode = !_notesMode);
    _scheduleSave();
  }
''',
    '''  void _toggleNotes() {
    if (!_ready || _completed || _roundLost) return;
    setState(() => _notesMode = !_notesMode);
    unawaited(
      SoundEffectsService.instance.play(
        _notesMode ? SoundEffect.notesModeOn : SoundEffect.notesModeOff,
      ),
    );
    _scheduleSave();
  }
''',
)
replace_once(
    'lib/features/game/enhanced_game_screen.dart',
    '''    setState(() => _hintBusy = true);
    try {
      final allowed = await HintEconomy.consumeOrAcquire(context, widget.store);
''',
    '''    setState(() => _hintBusy = true);
    unawaited(SoundEffectsService.instance.play(SoundEffect.hintActivate));
    try {
      final allowed = await HintEconomy.consumeOrAcquire(context, widget.store);
''',
)
replace_once(
    'lib/features/game/enhanced_game_screen.dart',
    '''        _hintsUsed++;
      });
      _scheduleSave();
      await _checkCompletion();
''',
    '''        _hintsUsed++;
      });
      unawaited(SoundEffectsService.instance.play(SoundEffect.hintApply));
      _scheduleSave();
      await _checkCompletion();
''',
)
replace_once(
    'lib/features/game/enhanced_game_screen.dart',
    '''  Future<void> _showLossSheet() async {
    if (!mounted || _lossVisible || _completed) return;
    _pauseClock();
''',
    '''  Future<void> _showLossSheet() async {
    if (!mounted || _lossVisible || _completed) return;
    final firstPresentation = !_roundLost;
    if (firstPresentation) {
      unawaited(SoundEffectsService.instance.play(SoundEffect.puzzleFailed));
    }
    _pauseClock();
''',
)
replace_once(
    'lib/features/game/enhanced_game_screen.dart',
    '''  void _restartPuzzle() {
    _pauseClock();
''',
    '''  void _restartPuzzle() {
    unawaited(SoundEffectsService.instance.play(SoundEffect.gameStart));
    _pauseClock();
''',
)
unit_helper = r'''  bool _hasCompletedUnitAt(int index) {
    final size = widget.puzzle.size;
    bool complete(Iterable<int> indexes) => indexes.every(
      (candidate) =>
          _board[candidate] != 0 &&
          _board[candidate] == widget.puzzle.solution[candidate],
    );

    final row = index ~/ size;
    final column = index % size;
    if (complete(Iterable<int>.generate(size, (offset) => row * size + offset))) {
      return true;
    }
    if (complete(Iterable<int>.generate(size, (offset) => offset * size + column))) {
      return true;
    }

    final box = SudokuEngine.relatedBoxIndex(widget.puzzle, index);
    final boxIndexes = <int>[];
    for (var candidate = 0; candidate < _board.length; candidate++) {
      if (SudokuEngine.relatedBoxIndex(widget.puzzle, candidate) == box) {
        boxIndexes.add(candidate);
      }
    }
    return boxIndexes.isNotEmpty && complete(boxIndexes);
  }

'''
replace_once(
    'lib/features/game/enhanced_game_screen.dart',
    '  void _removeRelatedNotes(int index, int value) {\n',
    unit_helper + '  void _removeRelatedNotes(int index, int value) {\n',
)
replace_once(
    'lib/features/game/enhanced_game_screen.dart',
    '''    _pauseClock();
    setState(() => _completed = true);
    _saveDebounce?.cancel();
''',
    '''    _pauseClock();
    setState(() => _completed = true);
    unawaited(
      SoundEffectsService.instance.play(
        _totalMistakes == 0 && _hintsUsed == 0
            ? SoundEffect.perfectGame
            : SoundEffect.puzzleComplete,
      ),
    );
    _saveDebounce?.cancel();
''',
)

# ---------------------------------------------------------------------------
# Ready countdown: one cue per second, no build() side effects.
# ---------------------------------------------------------------------------
replace_once(
    'lib/features/duel/online_ready_countdown_overlay.dart',
    "import '../../services/online_duel_models.dart';\n",
    "import '../../services/online_duel_models.dart';\nimport '../../services/sound_effects_service.dart';\n",
)
replace_once(
    'lib/features/duel/online_ready_countdown_overlay.dart',
    '''  Duration _serverClockOffset = Duration.zero;
  bool _startingFlashVisible = true;
''',
    '''  Duration _serverClockOffset = Duration.zero;
  bool _startingFlashVisible = true;
  int? _lastSoundSecond;
  bool _matchStartSoundSent = false;
''',
)
replace_once(
    'lib/features/duel/online_ready_countdown_overlay.dart',
    '''    _syncServerClock();
    _syncTimers();
  }
''',
    '''    _syncServerClock();
    _syncTimers();
    _syncSoundCue();
  }
''',
)
replace_once(
    'lib/features/duel/online_ready_countdown_overlay.dart',
    '''    _syncTimers();
  }

  @override
  void dispose() {
''',
    '''    _syncTimers();
    _syncSoundCue();
  }

  @override
  void dispose() {
''',
)
replace_once(
    'lib/features/duel/online_ready_countdown_overlay.dart',
    '''      _ticker ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (mounted) setState(() {});
      });
''',
    '''      _ticker ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted) return;
        _syncSoundCue();
        setState(() {});
      });
''',
)
sound_cue_helper = r'''  void _syncSoundCue() {
    if (widget.showStartingFlash) {
      if (!_matchStartSoundSent) {
        _matchStartSoundSent = true;
        unawaited(SoundEffectsService.instance.play(SoundEffect.matchStart));
      }
      return;
    }

    if (widget.snapshot.status != OnlineDuelStatus.readyWindow ||
        widget.snapshot.readyDeadline == null) {
      _lastSoundSecond = null;
      return;
    }

    final seconds = _remainingSeconds();
    if (seconds <= 0 || seconds == _lastSoundSecond) return;
    _lastSoundSecond = seconds;
    final effect = switch (seconds) {
      3 => SoundEffect.countdown3,
      2 => SoundEffect.countdown2,
      1 => SoundEffect.countdown1,
      _ => SoundEffect.countdownTick,
    };
    unawaited(SoundEffectsService.instance.play(effect));
  }

'''
replace_once(
    'lib/features/duel/online_ready_countdown_overlay.dart',
    '  int _remainingSeconds() {\n',
    sound_cue_helper + '  int _remainingSeconds() {\n',
)

# ---------------------------------------------------------------------------
# Pre-match room: match found, ready, opponent ready.
# ---------------------------------------------------------------------------
replace_once(
    'lib/features/duel/pre_match_ready_screen.dart',
    "import '../../services/rank_identity_service.dart';\n",
    "import '../../services/rank_identity_service.dart';\nimport '../../services/sound_effects_service.dart';\n",
)
replace_once(
    'lib/features/duel/pre_match_ready_screen.dart',
    '''        final hadOpponent = _opponent != null;
        final opponentSeat = snapshot.youSeat == OnlineDuelSeat.a
''',
    '''        final hadOpponent = _opponent != null;
        final opponentWasReady = _opponent?.ready == true;
        final opponentSeat = snapshot.youSeat == OnlineDuelSeat.a
''',
)
replace_once(
    'lib/features/duel/pre_match_ready_screen.dart',
    '''        if (!hadOpponent && hasOpponent && !_matchHapticSent) {
          _matchHapticSent = true;
          unawaited(HapticFeedback.mediumImpact());
        }
''',
    '''        if (!hadOpponent && hasOpponent && !_matchHapticSent) {
          _matchHapticSent = true;
          unawaited(HapticFeedback.mediumImpact());
          unawaited(SoundEffectsService.instance.play(SoundEffect.matchFound));
        }
        if (!opponentWasReady && opponent?.ready == true) {
          unawaited(SoundEffectsService.instance.play(SoundEffect.opponentReady));
        }
''',
)
replace_once(
    'lib/features/duel/pre_match_ready_screen.dart',
    '''      _autoReadySent = true;
      setState(() => _readyPressed = true);
      _controller!.ready();
''',
    '''      _autoReadySent = true;
      setState(() => _readyPressed = true);
      unawaited(SoundEffectsService.instance.play(SoundEffect.ready));
      _controller!.ready();
''',
)
replace_once(
    'lib/features/duel/pre_match_ready_screen.dart',
    '''    _autoReadyTimer = null;
    setState(() => _readyPressed = true);
    _controller!.ready();
''',
    '''    _autoReadyTimer = null;
    setState(() => _readyPressed = true);
    unawaited(SoundEffectsService.instance.play(SoundEffect.ready));
    _controller!.ready();
''',
)

# ---------------------------------------------------------------------------
# Active online duel: authoritative move feedback, connectivity, result.
# ---------------------------------------------------------------------------
replace_once(
    'lib/features/duel/online_duel_screen.dart',
    "import '../../services/social_api_client.dart';\n",
    "import '../../services/social_api_client.dart';\nimport '../../services/sound_effects_service.dart';\n",
)
replace_once(
    'lib/features/duel/online_duel_screen.dart',
    '''        if (!feedback.accepted) {
          final messenger = ScaffoldMessenger.of(context);
''',
    '''        unawaited(
          SoundEffectsService.instance.play(
            feedback.accepted ? SoundEffect.correctMove : SoundEffect.wrongMove,
          ),
        );

        if (!feedback.accepted) {
          final messenger = ScaffoldMessenger.of(context);
''',
)
old_disconnect = '''  void _syncDisconnectEscape(OnlineDuelSnapshot snapshot) {
    if (snapshot.status == OnlineDuelStatus.paused && !snapshot.isFinished) {
      _localConnectionInterrupted = true;
      _disconnectEscapeTimer ??= Timer(const Duration(seconds: 30), () {
        if (!mounted || _snapshot?.isFinished == true) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
      });
      return;
    }

    _localConnectionInterrupted = false;
    _disconnectEscapeTimer?.cancel();
    _disconnectEscapeTimer = null;
  }
'''
new_disconnect = '''  void _syncDisconnectEscape(OnlineDuelSnapshot snapshot) {
    final wasInterrupted = _localConnectionInterrupted;
    if (snapshot.status == OnlineDuelStatus.paused && !snapshot.isFinished) {
      _localConnectionInterrupted = true;
      if (!wasInterrupted) {
        unawaited(
          SoundEffectsService.instance.play(SoundEffect.connectionLost),
        );
      }
      _disconnectEscapeTimer ??= Timer(const Duration(seconds: 30), () {
        if (!mounted || _snapshot?.isFinished == true) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
      });
      return;
    }

    _localConnectionInterrupted = false;
    if (wasInterrupted && !snapshot.isFinished) {
      unawaited(
        SoundEffectsService.instance.play(SoundEffect.connectionRestored),
      );
    }
    _disconnectEscapeTimer?.cancel();
    _disconnectEscapeTimer = null;
  }
'''
replace_once('lib/features/duel/online_duel_screen.dart', old_disconnect, new_disconnect)
replace_once(
    'lib/features/duel/online_duel_screen.dart',
    '''    _shownResultFor = snapshot.matchId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
''',
    '''    _shownResultFor = snapshot.matchId;
    if (snapshot.winnerSeat == snapshot.youSeat) {
      unawaited(
        SoundEffectsService.instance.play(
          snapshot.status == OnlineDuelStatus.forfeited
              ? SoundEffect.opponentSurrendered
              : SoundEffect.onlineVictory,
        ),
      );
    } else if (snapshot.winnerSeat != null) {
      unawaited(SoundEffectsService.instance.play(SoundEffect.onlineDefeat));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
''',
)

# ---------------------------------------------------------------------------
# Emotes.
# ---------------------------------------------------------------------------
replace_once(
    'lib/services/online_duel_emote_hub.dart',
    "import 'online_duel_emote_loadout_service.dart';\n",
    "import 'online_duel_emote_loadout_service.dart';\nimport 'sound_effects_service.dart';\n",
)
replace_once(
    'lib/services/online_duel_emote_hub.dart',
    '''    if (sender == null || !sender(emoteId)) return false;

    _cooldownTimer?.cancel();
''',
    '''    if (sender == null || !sender(emoteId)) return false;

    unawaited(SoundEffectsService.instance.play(SoundEffect.emoteSend));
    _cooldownTimer?.cancel();
''',
)
replace_once(
    'lib/services/online_duel_emote_hub.dart',
    '''    _incomingTimer?.cancel();
    _incomingEmoteId = emoteId;
    notifyListeners();
''',
    '''    _incomingTimer?.cancel();
    _incomingEmoteId = emoteId;
    unawaited(SoundEffectsService.instance.play(SoundEffect.emoteReceive));
    notifyListeners();
''',
)

# ---------------------------------------------------------------------------
# Friend/challenge actions.
# ---------------------------------------------------------------------------
replace_once(
    'lib/features/social/social_hub_screen.dart',
    "import '../../services/social_api_client.dart';\n",
    "import '../../services/social_api_client.dart';\nimport '../../services/sound_effects_service.dart';\n",
)
replace_once(
    'lib/features/social/social_hub_screen.dart',
    '''    if (mounted && _error == null) _snack(context.tr('friend_request_sent'));
''',
    '''    if (mounted && _error == null) {
      unawaited(
        SoundEffectsService.instance.play(SoundEffect.friendRequestSent),
      );
      _snack(context.tr('friend_request_sent'));
    }
''',
)
replace_once(
    'lib/features/social/social_hub_screen.dart',
    '''    if (mounted && _error == null && accept) {
      _snack(
''',
    '''    if (mounted && _error == null && accept) {
      unawaited(
        SoundEffectsService.instance.play(SoundEffect.friendRequestAccepted),
      );
      _snack(
''',
)
replace_once(
    'lib/features/social/social_hub_screen.dart',
    '''      final challenge = await _social.createChallenge(
        recipientPublicId: player.publicId,
        difficulty: difficulty.name,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
''',
    '''      final challenge = await _social.createChallenge(
        recipientPublicId: player.publicId,
        difficulty: difficulty.name,
      );
      if (!mounted) return;
      unawaited(SoundEffectsService.instance.play(SoundEffect.challengeSent));
      await Navigator.of(context).push<void>(
''',
)

# ---------------------------------------------------------------------------
# Source-level regression test. It also proves every unique bundled asset exists.
# ---------------------------------------------------------------------------
test = r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
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
'''
(ROOT / 'test/sound_effects_integration_test.dart').write_text(test, encoding='utf-8')

print('Sound feedback integration patch applied successfully.')
