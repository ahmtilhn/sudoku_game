#!/usr/bin/env python3
"""Fix analyzer issues introduced or exposed by the localization migration.

Keeps compatibility helpers backed by AppStrings, adds awaits where a Future is
returned from inside a try block, and fixes the exact control-flow/context lints
reported by Flutter analyze. No product policy or game behavior is changed.
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace(path: str, old: str, new: str) -> None:
    target = ROOT / path
    source = target.read_text(encoding='utf-8')
    if old in source:
        target.write_text(source.replace(old, new), encoding='utf-8')


def fix_country_compatibility() -> None:
    path = ROOT / 'lib/models/country_catalog.dart'
    source = path.read_text(encoding='utf-8')
    marker = '  final String code;\n\n  String get flag => countryFlagEmoji(code);'
    replacement = (
        '  final String code;\n\n'
        "  String get name => AppStrings.english['country_name_${code.toLowerCase()}'] ?? code;\n\n"
        '  String get flag => countryFlagEmoji(code);'
    )
    # Only add AppStrings when this compatibility getter is actually needed.
    # Current catalog variants may already have a concrete `name` field; adding
    # the import in that case creates an unused-import analyzer warning.
    if marker in source:
        if "../localization/app_strings.dart" not in source:
            source = "import '../localization/app_strings.dart';\n\n" + source
        source = source.replace(marker, replacement, 1)
    elif 'AppStrings.' not in source:
        source = source.replace("import '../localization/app_strings.dart';\n\n", '')
    path.write_text(source, encoding='utf-8')


def wrap_safe_error_if(path: str, condition: str = 'mounted') -> None:
    replace(
        path,
        f"if ({condition}) setState(() => _error = UserSafeError.message(context, error));",
        f"""if ({condition}) {{
        setState(() => _error = UserSafeError.message(context, error));
      }}""",
    )


def fix_reported_control_flow_lints() -> None:
    # Challenge/rematch screens: these are precisely the catch branches that
    # became user-safe during the preceding migration step.
    wrap_safe_error_if('lib/features/social/challenge_invitation_screen.dart')
    wrap_safe_error_if(
        'lib/features/social/challenge_waiting_screen.dart',
        'mounted && _routeIsCurrent',
    )
    wrap_safe_error_if('lib/features/social/challenge_waiting_screen.dart')
    wrap_safe_error_if('lib/features/social/rematch_invitation_screen.dart')
    wrap_safe_error_if('lib/features/social/ux_challenge_invitation_screen.dart')

    # Social hub has five user-safe catch branches plus two pre-existing
    # single-line conditionals reported by the analyzer.
    wrap_safe_error_if('lib/features/social/social_hub_screen.dart')
    replace(
        'lib/features/social/social_hub_screen.dart',
        'if (mounted) setState(() { _loading = true; _error = null; });',
        """if (mounted) {
      setState(() { _loading = true; _error = null; });
    }""",
    )
    replace(
        'lib/features/social/social_hub_screen.dart',
        'if (entry != null) _rankSummaries[entry.key] = entry.value;',
        """if (entry != null) {
          _rankSummaries[entry.key] = entry.value;
        }""",
    )

    replace(
        'lib/services/online_duel_emote_hub.dart',
        'if (reduceMotion) return FadeTransition(opacity: animation, child: child);',
        """if (reduceMotion) {
          return FadeTransition(opacity: animation, child: child);
        }""",
    )


def fix_emote_loadout_async_context() -> None:
    replace(
        'lib/features/social/emote_loadout_screen.dart',
        """                                    await _loadout.resetToDefaults();
                                    if (mounted) {
                                      _showMessage(context.tr('default_emotes_restored'));
                                    }""",
        """                                    final restoredMessage = context.tr(
                                      'default_emotes_restored',
                                    );
                                    await _loadout.resetToDefaults();
                                    if (mounted) {
                                      _showMessage(restoredMessage);
                                    }""",
    )


def fix_emote_hub_async_context() -> None:
    replace(
        'lib/services/online_duel_emote_hub.dart',
        """    if (action != 'forfeit' || !mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    await Navigator.of(context).maybePop();""",
        """    if (action != 'forfeit' || !context.mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!context.mounted) return;
    await Navigator.of(context).maybePop();""",
    )


def main() -> int:
    fix_country_compatibility()
    replace(
        'lib/services/ads_service.dart',
        'return ConsentInformation.instance.getConsentStatus();',
        'return await ConsentInformation.instance.getConsentStatus();',
    )
    replace(
        'lib/services/ads_service.dart',
        'return ConsentInformation.instance.canRequestAds();',
        'return await ConsentInformation.instance.canRequestAds();',
    )
    replace(
        'lib/services/firebase_session_service.dart',
        'return ensureAnonymousSession(restorePlayGames: false);',
        'return await ensureAnonymousSession(restorePlayGames: false);',
    )
    replace(
        'lib/services/push_notification_service.dart',
        'return _registerCurrentToken();',
        'return await _registerCurrentToken();',
    )

    fix_emote_loadout_async_context()
    fix_emote_hub_async_context()
    fix_reported_control_flow_lints()

    print('Localization analyzer issues normalized.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
