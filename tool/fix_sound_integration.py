from pathlib import Path

ROOT = Path('.')


def replace_once(path: str, old: str, new: str) -> None:
    p = ROOT / path
    text = p.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{path}: expected one match, got {count}: {old[:120]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


service = 'lib/services/sound_effects_service.dart'

# Keep singleton construction plugin-free. Widget tests and non-main entrypoints can
# reference the service safely before Flutter platform plugins are registered.
replace_once(
    service,
    "  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();\n  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);\n  final List<AudioPlayer> _players = List<AudioPlayer>.generate(\n    _poolSize,\n    (_) => AudioPlayer(),\n  );\n",
    "  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);\n  List<AudioPlayer>? _players;\n",
)

replace_once(
    service,
    """    try {
      enabled.value = await _preferences.getBool(_enabledKey) ?? true;
    } catch (error) {
      debugPrint('Sound preference unavailable: $error');
    }
    _initialized = true;
""",
    """    try {
      final preferences = SharedPreferencesAsync();
      enabled.value = await preferences.getBool(_enabledKey) ?? true;
    } catch (error) {
      debugPrint('Sound preference unavailable: $error');
    }
    _initialized = true;
""",
)

replace_once(
    service,
    """    try {
      await _preferences.setBool(_enabledKey, value);
    } catch (error) {
      debugPrint('Sound preference could not be saved: $error');
    }
""",
    """    try {
      final preferences = SharedPreferencesAsync();
      await preferences.setBool(_enabledKey, value);
    } catch (error) {
      debugPrint('Sound preference could not be saved: $error');
    }
""",
)

replace_once(
    service,
    """    final player = _players[_nextPlayer];
    _nextPlayer = (_nextPlayer + 1) % _players.length;
    final volume = (effect.volume * volumeScale).clamp(0.0, 1.0).toDouble();
    try {
      await player.play(
        AssetSource(effect.assetPath),
        volume: volume,
        mode: PlayerMode.lowLatency,
        ctx: _audioContext,
      );
""",
    """    final volume = (effect.volume * volumeScale).clamp(0.0, 1.0).toDouble();
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
""",
)

replace_once(
    service,
    """  Future<void> stopAll() async {
    await Future.wait(
      _players.map((player) async {
        try {
          await player.stop();
        } catch (_) {}
      }),
    );
  }
""",
    """  Future<void> stopAll() async {
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
""",
)

replace_once(
    service,
    """  final String assetPath;
  final double volume;
}
""",
    """  final String assetPath;
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
""",
)

# Final number should hand off directly to the completion sound instead of
# stacking number_input underneath a victory cue.
replace_once(
    'lib/features/game/enhanced_game_screen.dart',
    """    unawaited(
      SoundEffectsService.instance.play(
        unitCompleted ? SoundEffect.unitComplete : SoundEffect.numberInput,
      ),
    );
    _scheduleSave();
""",
    """    if (!puzzleCompleted) {
      unawaited(
        SoundEffectsService.instance.play(
          unitCompleted ? SoundEffect.unitComplete : SoundEffect.numberInput,
        ),
      );
    }
    _scheduleSave();
""",
)

# Strengthen the regression test: merely touching the singleton and calling play
# before bootstrap must be a safe no-op with no platform plugin dependency.
test_path = ROOT / 'test/sound_effects_integration_test.dart'
test_text = test_path.read_text(encoding='utf-8')
if "package:sudoku_game/services/sound_effects_service.dart" not in test_text:
    test_text = test_text.replace(
        "import 'package:flutter_test/flutter_test.dart';\n",
        "import 'package:flutter_test/flutter_test.dart';\nimport 'package:sudoku_game/services/sound_effects_service.dart';\n",
        1,
    )
insert = """
  test('sound service is safe before platform bootstrap', () async {
    final service = SoundEffectsService.instance;
    expect(service.enabled.value, isTrue);
    await service.play(SoundEffect.uiClick);
  });

"""
marker = "  test('sound assets and production integration remain wired', () {\n"
if insert.strip() not in test_text:
    test_text = test_text.replace(marker, insert + marker, 1)
test_path.write_text(test_text, encoding='utf-8')

print('Sound integration safety/quality fixes applied.')
