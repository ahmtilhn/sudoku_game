from pathlib import Path

ROOT = Path('.')


def patch_once(path: str, needle: str, replacement: str) -> None:
    p = ROOT / path
    text = p.read_text(encoding='utf-8-sig')
    if replacement in text:
        return
    if text.count(needle) != 1:
        raise RuntimeError(f'{path}: expected exactly one patch point for {needle[:80]!r}')
    p.write_text(text.replace(needle, replacement, 1), encoding='utf-8')


# Latest main.dart + sound bootstrap.
patch_once(
    'lib/main.dart',
    "import 'services/reminder_notification_service.dart';\n",
    "import 'services/reminder_notification_service.dart';\nimport 'services/sound_effects_service.dart';\n",
)
patch_once(
    'lib/main.dart',
    '  await HapticFeedbackService.instance.initialize();\n',
    '  await HapticFeedbackService.instance.initialize();\n  await SoundEffectsService.instance.initialize();\n',
)

# Latest Settings keeps notification permission semantics from main while adding
# a separate persistent Sound Effects preference in the Play section.
patch_once(
    'lib/features/settings/ux_settings_screen.dart',
    "import '../../services/social_api_client.dart';\n",
    "import '../../services/social_api_client.dart';\nimport '../../services/sound_effects_service.dart';\n",
)
patch_once(
    'lib/features/settings/ux_settings_screen.dart',
    '    unawaited(HapticFeedbackService.instance.initialize());\n',
    '    unawaited(HapticFeedbackService.instance.initialize());\n    unawaited(SoundEffectsService.instance.initialize());\n',
)

settings = ROOT / 'lib/features/settings/ux_settings_screen.dart'
settings_text = settings.read_text(encoding='utf-8')
if 'valueListenable: SoundEffectsService.instance.enabled' not in settings_text:
    old = '''        return _SettingsPanel(
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
    new = '''        return _SettingsPanel(
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
    if settings_text.count(old) != 1:
        raise RuntimeError('settings play panel patch point not found')
    settings.write_text(settings_text.replace(old, new, 1), encoding='utf-8')

# Latest main pubspec has url_launcher; preserve it and add audio dependency/assets.
pubspec = ROOT / 'pubspec.yaml'
pubspec_text = pubspec.read_text(encoding='utf-8-sig')
if '  audioplayers: ^6.8.1\n' not in pubspec_text:
    pubspec_text = pubspec_text.replace(
        '  app_tracking_transparency: ^2.0.7\n',
        '  app_tracking_transparency: ^2.0.7\n  audioplayers: ^6.8.1\n',
        1,
    )

sound_assets = '''    - assets/audio/ui/ui_click.mp3
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
if '    - assets/audio/ui/ui_click.mp3\n' not in pubspec_text:
    marker = '    - assets/localization/Localizable.xcstrings\n'
    if pubspec_text.count(marker) != 1:
        raise RuntimeError('pubspec asset insertion point not found')
    pubspec_text = pubspec_text.replace(marker, marker + sound_assets, 1)
pubspec.write_text(pubspec_text, encoding='utf-8')

print('Reconciled audio integration with latest main.')
