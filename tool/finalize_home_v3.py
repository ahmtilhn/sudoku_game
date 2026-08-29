from pathlib import Path

path = Path('lib/features/home/professional_home_screen.dart')
text = path.read_text()


def once(old: str, new: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'Expected 1 match, got {count}: {old[:100]!r}')
    text = text.replace(old, new, 1)


once(
    """              final compact = constraints.maxHeight < 760;\n              final wide =\n""",
    """              final compact = constraints.maxHeight < 760;\n              final tight =\n                  constraints.maxHeight < 420 &&\n                  constraints.maxWidth > constraints.maxHeight * 1.35;\n              final narrowHeader = constraints.maxWidth < 350;\n              final wide =\n""",
)
once(
    """                      14,\n                      compact ? 6 : 10,\n                      14,\n                      compact ? 8 : 14,\n""",
    """                      narrowHeader ? 8 : 14,\n                      tight ? 2 : compact ? 6 : 10,\n                      narrowHeader ? 8 : 14,\n                      tight ? 4 : compact ? 8 : 14,\n""",
)
once(
    """                        _HomeHeader(\n                          profile: _profile,\n""",
    """                        _HomeHeader(\n                          narrow: narrowHeader,\n                          profile: _profile,\n""",
)
once(
    """                                  _HomeLogo(compact: compact),\n                                  if (_activeSession != null) ...[\n                                    SizedBox(height: compact ? 4 : 6),\n""",
    """                                  _HomeLogo(compact: compact, tight: tight),\n                                  if (_activeSession != null) ...[\n                                    SizedBox(\n                                      height: tight ? 2 : compact ? 4 : 6,\n                                    ),\n""",
)
once(
    """                                  SizedBox(height: compact ? 8 : 12),\n                                  _PrimaryModes(\n                                    items: primaryItems,\n                                    compact: compact,\n                                    wide: wide,\n                                  ),\n                                  SizedBox(height: compact ? 8 : 10),\n                                  _SecondaryModes(\n                                    items: secondaryItems,\n                                    compact: compact,\n                                    wide: wide,\n                                  ),\n""",
    """                                  SizedBox(\n                                    height: tight ? 4 : compact ? 8 : 12,\n                                  ),\n                                  _PrimaryModes(\n                                    items: primaryItems,\n                                    compact: compact,\n                                    tight: tight,\n                                    wide: wide,\n                                  ),\n                                  SizedBox(\n                                    height: tight ? 4 : compact ? 8 : 10,\n                                  ),\n                                  _SecondaryModes(\n                                    items: secondaryItems,\n                                    compact: compact,\n                                    tight: tight,\n                                    wide: wide,\n                                  ),\n""",
)

once(
    """class _HomeLogo extends StatelessWidget {\n  const _HomeLogo({required this.compact});\n\n  final bool compact;\n""",
    """class _HomeLogo extends StatelessWidget {\n  const _HomeLogo({required this.compact, required this.tight});\n\n  final bool compact;\n  final bool tight;\n""",
)
once('      height: compact ? 72 : 180,\n', '      height: tight ? 44 : compact ? 72 : 180,\n')
once('                    fontSize: compact ? 28 : 42,\n', '                    fontSize: tight ? 22 : compact ? 28 : 42,\n')

once(
    """  const _HomeHeader({\n    required this.profile,\n""",
    """  const _HomeHeader({\n    required this.narrow,\n    required this.profile,\n""",
)
once('  final PlayerProfilePreferences? profile;\n', '  final bool narrow;\n  final PlayerProfilePreferences? profile;\n')
once('      height: 44,\n      child: Row(\n', '      height: narrow ? 38 : 44,\n      child: Row(\n')
once('                      radius: 18,\n', '                      radius: narrow ? 15 : 18,\n')
once('                    const SizedBox(width: 7),\n', '                    SizedBox(width: narrow ? 5 : 7),\n')

for tooltip in [
    'home_daily_reward_title',
    'leaderboards',
    'friends_challenges',
    'settings',
]:
    once(
        f"""          _HeaderButton(\n            tooltip: context.tr('{tooltip}'),\n""",
        f"""          _HeaderButton(\n            compact: narrow,\n            tooltip: context.tr('{tooltip}'),\n""",
    )

header_start = text.index('class _HomeHeader extends StatelessWidget')
header_end = text.index('class _DailyRewardDialog', header_start)
header = text[header_start:header_end]
if header.count('          const SizedBox(width: 4),\n') != 4:
    raise SystemExit('Unexpected HomeHeader gap count')
header = header.replace(
    '          const SizedBox(width: 4),\n',
    '          SizedBox(width: narrow ? 2 : 4),\n',
)
text = text[:header_start] + header + text[header_end:]

once(
    """          Container(\n            height: 38,\n            padding: const EdgeInsets.only(left: 3, right: 8),\n""",
    """          Container(\n            height: narrow ? 34 : 38,\n            padding: EdgeInsets.only(\n              left: narrow ? 2 : 3,\n              right: narrow ? 5 : 8,\n            ),\n""",
)
once(
    """                const DuelAssetIcon(\n                  DuelAsset.coin,\n                  size: 30,\n                  fit: BoxFit.contain,\n                ),\n                const SizedBox(width: 2),\n""",
    """                DuelAssetIcon(\n                  DuelAsset.coin,\n                  size: narrow ? 24 : 30,\n                  fit: BoxFit.contain,\n                ),\n                SizedBox(width: narrow ? 1 : 2),\n""",
)

button_start = text.index('class _HeaderButton extends StatelessWidget')
button_end = text.index('class _ResumeStrip extends StatelessWidget', button_start)
button = """class _HeaderButton extends StatelessWidget {\n  const _HeaderButton({\n    required this.compact,\n    required this.tooltip,\n    required this.onTap,\n    required this.child,\n    this.accent,\n  });\n\n  final bool compact;\n  final String tooltip;\n  final VoidCallback? onTap;\n  final Widget child;\n  final Color? accent;\n\n  @override\n  Widget build(BuildContext context) {\n    final size = compact ? 34.0 : 38.0;\n    return SizedBox.square(\n      dimension: size,\n      child: IconButton(\n        tooltip: tooltip,\n        onPressed: onTap,\n        padding: EdgeInsets.zero,\n        constraints: const BoxConstraints(),\n        style: IconButton.styleFrom(\n          backgroundColor: const Color(0xFF0A1728).withValues(alpha: .92),\n          side: BorderSide(\n            color: (accent ?? Colors.white).withValues(\n              alpha: accent == null ? .13 : .34,\n            ),\n          ),\n        ),\n        icon: child,\n      ),\n    );\n  }\n}\n\n"""
text = text[:button_start] + button + text[button_end:]

once(
    """    required this.compact,\n    required this.wide,\n  });\n\n  final List<_HomeModeData> items;\n  final bool compact;\n  final bool wide;\n\n  @override\n  Widget build(BuildContext context) {\n    if (wide) {\n      return SizedBox(\n        height: compact ? 84 : 124,\n""",
    """    required this.compact,\n    required this.tight,\n    required this.wide,\n  });\n\n  final List<_HomeModeData> items;\n  final bool compact;\n  final bool tight;\n  final bool wide;\n\n  @override\n  Widget build(BuildContext context) {\n    if (wide) {\n      return SizedBox(\n        height: tight ? 68 : compact ? 84 : 124,\n""",
)
once(
    """    required this.compact,\n    required this.wide,\n  });\n\n  final List<_HomeModeData> items;\n  final bool compact;\n  final bool wide;\n\n  @override\n  Widget build(BuildContext context) {\n    final columns = wide ? 4 : 2;\n    final itemHeight = compact ? 58.0 : 88.0;\n""",
    """    required this.compact,\n    required this.tight,\n    required this.wide,\n  });\n\n  final List<_HomeModeData> items;\n  final bool compact;\n  final bool tight;\n  final bool wide;\n\n  @override\n  Widget build(BuildContext context) {\n    final columns = wide ? 4 : 2;\n    final itemHeight = tight ? 52.0 : compact ? 58.0 : 88.0;\n""",
)

path.write_text(text)
