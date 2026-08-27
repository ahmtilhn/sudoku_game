from pathlib import Path

path = Path('lib/features/duel/online_duel_screen.dart')
source = path.read_text()

# 1) Runtime fix: the result player Row used stretch under an unbounded Column.
old = """    return Row(\n      crossAxisAlignment: CrossAxisAlignment.stretch,\n      children: [\n"""
new = """    return SizedBox(\n      height: compact ? 82 : 92,\n      child: Row(\n        crossAxisAlignment: CrossAxisAlignment.stretch,\n        children: [\n"""
if old not in source:
    raise SystemExit('ResultPlayers row anchor missing')
source = source.replace(old, new, 1)

old = """        Expanded(\n          child: _ResultPlayerPanel(\n            player: localPlayer,\n            score: localScore,\n            accent: localAccent,\n            compact: compact,\n            isLocal: true,\n          ),\n        ),\n      ],\n    );\n  }\n}\n\nclass _ResultPlayerPanel"""
new = """        Expanded(\n          child: _ResultPlayerPanel(\n            player: localPlayer,\n            score: localScore,\n            accent: localAccent,\n            compact: compact,\n            isLocal: true,\n          ),\n        ),\n        ],\n      ),\n    );\n  }\n}\n\nclass _ResultPlayerPanel"""
if old not in source:
    raise SystemExit('ResultPlayers closing anchor missing')
source = source.replace(old, new, 1)

# 2) Use project assets for result metrics.
old = """class _ResultMetric {\n  const _ResultMetric({\n    required this.label,\n    required this.localValue,\n    required this.opponentValue,\n    required this.icon,\n  });\n\n  final String label;\n  final String localValue;\n  final String opponentValue;\n  final IconData icon;\n}\n"""
new = """class _ResultMetric {\n  const _ResultMetric({\n    required this.label,\n    required this.localValue,\n    required this.opponentValue,\n    required this.icon,\n    this.asset,\n  });\n\n  final String label;\n  final String localValue;\n  final String opponentValue;\n  final IconData icon;\n  final String? asset;\n}\n"""
if old not in source:
    raise SystemExit('ResultMetric anchor missing')
source = source.replace(old, new, 1)

asset_replacements = {
    "icon: Icons.check_rounded,": "icon: Icons.check_rounded,\n            asset: 'assets/images/ui/check.png',",
    "icon: Icons.close_rounded,": "icon: Icons.close_rounded,\n            asset: 'assets/images/ui/close.png',",
    "icon: Icons.timer_outlined,": "icon: Icons.timer_outlined,\n            asset: 'assets/images/ui/timer.png',",
    "icon: Icons.lightbulb_outline_rounded,": "icon: Icons.lightbulb_outline_rounded,\n            asset: 'assets/images/ui/lightbulb.png',",
    "icon: Icons.monetization_on_outlined,": "icon: Icons.monetization_on_outlined,\n            asset: 'assets/images/ui/coin.png',",
}
for before, after in asset_replacements.items():
    if before not in source:
        raise SystemExit(f'metric icon anchor missing: {before}')
    source = source.replace(before, after, 1)

# 3) Win keeps the approved cup.png; loss uses the existing defeat artwork.
old = """          _ResultHero(\n            asset: _cupAsset,\n"""
new = """          _ResultHero(\n            asset: draw\n                ? 'assets/images/ui/shield.png'\n                : won\n                ? _cupAsset\n                : 'assets/images/ui/defeat_trophy.png',\n"""
if old not in source:
    raise SystemExit('ResultHero asset anchor missing')
source = source.replace(old, new, 1)

# 4) Render metric assets when available, with colored utility glyphs and native coin art.
old = """                Icon(\n                  metric.icon,\n                  color: const Color(0xFFFFC94D),\n                  size: compact ? 13 : 14,\n                ),\n"""
new = """                _ResultMetricIcon(metric: metric, compact: compact),\n"""
if old not in source:
    raise SystemExit('metric icon renderer anchor missing')
source = source.replace(old, new, 1)

anchor = """class _ResultRankPanel extends StatelessWidget {\n"""
helper = """class _ResultMetricIcon extends StatelessWidget {\n  const _ResultMetricIcon({required this.metric, required this.compact});\n\n  final _ResultMetric metric;\n  final bool compact;\n\n  @override\n  Widget build(BuildContext context) {\n    final size = compact ? 13.0 : 14.0;\n    final asset = metric.asset;\n    if (asset == null) {\n      return Icon(metric.icon, color: const Color(0xFFFFC94D), size: size);\n    }\n    final image = Image.asset(\n      asset,\n      width: size,\n      height: size,\n      fit: BoxFit.contain,\n      filterQuality: FilterQuality.high,\n    );\n    if (asset.endsWith('/coin.png')) return image;\n    return ColorFiltered(\n      colorFilter: const ColorFilter.mode(Color(0xFFFFC94D), BlendMode.srcIn),\n      child: image,\n    );\n  }\n}\n\n"""
if anchor not in source:
    raise SystemExit('rank panel anchor missing')
source = source.replace(anchor, helper + anchor, 1)

path.write_text(source)
