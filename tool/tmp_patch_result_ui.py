from pathlib import Path

path = Path('lib/features/duel/online_duel_screen.dart')
source = path.read_text()

if 'final accent2 = draw' in source and 'required this.won,' in source[source.index('class _ResultPlayers'):source.index('class _ResultPlayer')]:
    print('Result UI patch already applied.')
    raise SystemExit(0)

old = '''    final accent = draw
        ? const Color(0xFF8DA2BE)
        : won
        ? const Color(0xFF29D398)
        : const Color(0xFFFF6B62);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF17283B), Color(0xFF101C2B)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: .32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .42),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),'''
new = '''    final accent = draw
        ? const Color(0xFF8DA2BE)
        : won
        ? const Color(0xFF29D398)
        : const Color(0xFFFF6B62);
    final accent2 = draw
        ? const Color(0xFF66C7FF)
        : won
        ? const Color(0xFFFFC94D)
        : const Color(0xFFFFA45B);
    final viewport = MediaQuery.sizeOf(context);
    final compact = viewport.width < 390 || viewport.height < 760;
    final surfaceTop = draw
        ? const Color(0xFF17283B)
        : won
        ? const Color(0xFF132C2B)
        : const Color(0xFF2A1B26);

    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 16,
        compact ? 12 : 16,
        compact ? 12 : 16,
        compact ? 11 : 14,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [surfaceTop, const Color(0xFF101C2B)],
        ),
        borderRadius: BorderRadius.circular(compact ? 20 : 24),
        border: Border.all(color: accent.withValues(alpha: .42)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: .10),
            blurRadius: compact ? 18 : 28,
            spreadRadius: -5,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: .42),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),'''
if old not in source:
    raise SystemExit('result card decoration anchor missing')
source = source.replace(old, new, 1)

old = '''        children: [
          const Icon(Icons.shield_rounded, color: Color(0xFFFFC94D), size: 48),
          const SizedBox(height: 4),
          Text('''
new = '''        children: [
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: LinearGradient(colors: [accent, accent2]),
            ),
          ),
          SizedBox(height: compact ? 9 : 12),
          Container(
            width: compact ? 48 : 56,
            height: compact ? 48 : 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: .07),
              border: Border.all(color: accent2.withValues(alpha: .45)),
            ),
            alignment: Alignment.center,
            child: Icon(
              draw
                  ? Icons.handshake_outlined
                  : won
                  ? Icons.emoji_events_rounded
                  : Icons.shield_outlined,
              color: accent2,
              size: compact ? 27 : 31,
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          Text('''
if old not in source:
    raise SystemExit('result hero anchor missing')
source = source.replace(old, new, 1)

source = source.replace('              fontSize: 28,\n', '              fontSize: compact ? 24 : 28,\n', 1)
source = source.replace(
    '              fontSize: 12,\n              fontWeight: FontWeight.w700,\n',
    '              fontSize: compact ? 10 : 12,\n              fontWeight: FontWeight.w700,\n',
    1,
)

old = '''          _ResultPlayers(
            localPlayer: localPlayer,
            opponent: opponent,
            localScore: localScore,
            opponentScore: opponentScore,
          ),'''
new = '''          _ResultPlayers(
            localPlayer: localPlayer,
            opponent: opponent,
            localScore: localScore,
            opponentScore: opponentScore,
            won: won,
            draw: draw,
          ),'''
if old not in source:
    raise SystemExit('result players call anchor missing')
source = source.replace(old, new, 1)

source = source.replace(
    '          const SizedBox(height: 12),\n          SizedBox(\n            width: double.infinity,\n            height: 48,',
    '          SizedBox(height: compact ? 10 : 12),\n          SizedBox(\n            width: double.infinity,\n            height: compact ? 44 : 48,',
    1,
)
source = source.replace(
    '                backgroundColor: const Color(0xFF20A968),',
    '                backgroundColor: won\n                    ? const Color(0xFF20A968)\n                    : const Color(0xFF2374B8),',
    1,
)
source = source.replace(
    '            height: 46,\n            child: OutlinedButton.icon(',
    '            height: compact ? 42 : 46,\n            child: OutlinedButton.icon(',
    1,
)
source = source.replace(
    '                  height: 44,\n                  child: OutlinedButton.icon(',
    '                  height: compact ? 40 : 44,\n                  child: OutlinedButton.icon(',
    2,
)

old = '''  const _ResultPlayers({
    required this.localPlayer,
    required this.opponent,
    required this.localScore,
    required this.opponentScore,
  });

  final OnlineDuelPlayer localPlayer;
  final OnlineDuelPlayer opponent;
  final int localScore;
  final int opponentScore;

  @override
  Widget build(BuildContext context) {
    return Container('''
new = '''  const _ResultPlayers({
    required this.localPlayer,
    required this.opponent,
    required this.localScore,
    required this.opponentScore,
    required this.won,
    required this.draw,
  });

  final OnlineDuelPlayer localPlayer;
  final OnlineDuelPlayer opponent;
  final int localScore;
  final int opponentScore;
  final bool won;
  final bool draw;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 390;
    final localAccent = draw
        ? const Color(0xFF8DA2BE)
        : won
        ? const Color(0xFF29D398)
        : const Color(0xFFFF7D73);
    final opponentAccent = draw
        ? const Color(0xFF8DA2BE)
        : won
        ? const Color(0xFF66C7FF)
        : const Color(0xFF29D398);
    return Container('''
if old not in source:
    raise SystemExit('result players class anchor missing')
source = source.replace(old, new, 1)
source = source.replace('      padding: const EdgeInsets.all(10),', '      padding: EdgeInsets.all(compact ? 8 : 10),', 1)
source = source.replace('              accent: const Color(0xFF29D398),', '              accent: localAccent,', 1)
source = source.replace('              accent: const Color(0xFF66C7FF),', '              accent: opponentAccent,', 1)
source = source.replace(
    '            padding: EdgeInsets.symmetric(horizontal: 7),',
    '            padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 7),',
    1,
)

idx = source.index('class _ResultPlayer extends StatelessWidget {')
sub = source[idx:]
old = '''  @override
  Widget build(BuildContext context) {
    final avatar = Container('''
new = '''  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 390;
    final avatar = Container('''
if old not in sub:
    raise SystemExit('result player build anchor missing')
sub = sub.replace(old, new, 1)
sub = sub.replace('        radius: 18,', '        radius: compact ? 16 : 18,', 1)
sub = sub.replace('              fontSize: 11,', '              fontSize: compact ? 10 : 11,', 1)
sub = sub.replace('              fontSize: 14,', '              fontSize: compact ? 13 : 14,', 1)
sub = sub.replace('              fontSize: 9,', '              fontSize: compact ? 8 : 9,', 1)
source = source[:idx] + sub

idx = source.index('class _ResultMetricRow extends StatelessWidget {')
sub = source[idx:]
old = '''  @override
  Widget build(BuildContext context) {
    return Padding('''
new = '''  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 390;
    return Padding('''
if old not in sub:
    raise SystemExit('metric row build anchor missing')
sub = sub.replace(old, new, 1)
sub = sub.replace('            width: 50,', '            width: compact ? 44 : 50,', 2)
sub = sub.replace('                fontSize: 12,', '                fontSize: compact ? 10 : 12,', 2)
sub = sub.replace('                    fontSize: 10,', '                    fontSize: compact ? 9 : 10,', 1)
source = source[:idx] + sub

path.write_text(source)
print('Result UI patch applied.')
