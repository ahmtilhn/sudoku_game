from pathlib import Path


def read(path: str) -> str:
    return Path(path).read_text(encoding='utf-8')


def write(path: str, text: str) -> None:
    Path(path).write_text(text, encoding='utf-8')


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    if old not in text:
        raise SystemExit(f'pattern not found in {path}: {old[:180]!r}')
    write(path, text.replace(old, new, 1))


def replace_section(path: str, start: str, end: str, replacement: str) -> None:
    text = read(path)
    i = text.find(start)
    if i < 0:
        raise SystemExit(f'start marker not found in {path}: {start!r}')
    j = text.find(end, i + len(start))
    if j < 0:
        raise SystemExit(f'end marker not found in {path}: {end!r}')
    write(path, text[:i] + replacement + text[j:])


screen = 'lib/features/duel/online_duel_screen.dart'
replace_once(
    screen,
    '              top: compact ? 12 : 14,\n              bottom: compact ? 11 : 13,',
    '              top: compact ? 15 : 14,\n              bottom: compact ? 11 : 13,',
)
replace_section(
    screen,
    'class _DuelPlayerPlate extends StatelessWidget {',
    'class _AvatarRing extends StatelessWidget {',
    '''class _DuelPlayerPlate extends StatelessWidget {
  const _DuelPlayerPlate({
    required this.snapshot,
    required this.seat,
    required this.compact,
    this.alignEnd = false,
  });

  final OnlineDuelSnapshot snapshot;
  final OnlineDuelSeat seat;
  final bool compact;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final player = snapshot.players[seat]!;
    final active = snapshot.currentTurnSeat == seat;
    final isLocalPlayer = snapshot.youSeat == seat;
    final scheme = Theme.of(context).colorScheme;
    final accent = seat == OnlineDuelSeat.a ? scheme.primary : scheme.tertiary;
    final displayName = isLocalPlayer ? context.tr('you') : player.displayName;
    final score = snapshot.scores[seat] ?? 0;
    final avatarRadius = compact ? 18.0 : 24.0;
    final seatKey = seat == OnlineDuelSeat.a ? 'A' : 'B';

    final avatar = KeyedSubtree(
      key: ValueKey<String>('duel-avatar-$seatKey'),
      child: _AvatarRing(
        color: accent,
        active: active,
        child: PlayerAvatar(
          displayName: player.displayName,
          avatarKey: player.avatarKey,
          radius: avatarRadius,
          semanticLabel: context.tr('player_avatar_semantics', <Object>[
            displayName,
          ]),
        ),
      ),
    );

    final nameAndPresence = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            displayName,
            key: ValueKey<String>('duel-name-$seatKey'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 13.5 : 16.5,
              fontWeight: FontWeight.w900,
              letterSpacing: .1,
            ),
          ),
        ),
        SizedBox(width: compact ? 4 : 6),
        DuelAssetIcon(
          player.connected ? DuelAsset.wifi : DuelAsset.cloud,
          size: compact ? 12 : 14,
          color: player.connected ? accent : scheme.error,
        ),
      ],
    );

    final scoreValue = _ScoreValue(
      key: ValueKey<String>('duel-score-$seatKey'),
      score: score,
      compact: compact,
      color: accent,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 11,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: Colors.transparent,
        boxShadow: active
            ? [BoxShadow(color: accent.withValues(alpha: .18), blurRadius: 14)]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          avatar,
          SizedBox(height: compact ? 3 : 5),
          Row(
            children: alignEnd
                ? [
                    scoreValue,
                    SizedBox(width: compact ? 7 : 11),
                    Expanded(child: nameAndPresence),
                  ]
                : [
                    Expanded(child: nameAndPresence),
                    SizedBox(width: compact ? 7 : 11),
                    scoreValue,
                  ],
          ),
        ],
      ),
    );
  }
}

''',
)

challenge_test = 'test/challenge_client_hardening_test.dart'
replace_once(
    challenge_test,
    "  test('online duel exposes surrender and waits for settlement', () {",
    "  test('online duel exposes surrender without trapping navigation', () {",
)
replace_once(
    challenge_test,
    "    expect(prematch, contains('controller.forfeit();'));\n    expect(prematch, contains('snapshot.coinSettlement != null'));\n    expect(prematch, contains('await controller.dispose();'));",
    "    expect(prematch, contains('controller?.forfeit();'));\n    expect(prematch, contains('Duration(milliseconds: 180)'));\n    expect(prematch, contains('await controller?.dispose();'));\n    expect(prematch, contains('Navigator.of(context).pop();'));",
)

header_test = 'test/online_duel_screen_test.dart'
replace_once(
    header_test,
    "  testWidgets('active header aligns timer with both avatars and puts score before names', (tester) async {",
    "  testWidgets('active header aligns timer, puts names below avatars and scores inward', (tester) async {",
)
replace_once(
    header_test,
    "    expect(\n      tester.getCenter(find.byKey(const ValueKey<String>('duel-score-A'))).dx,\n      lessThan(tester.getCenter(find.byKey(const ValueKey<String>('duel-name-A'))).dx),\n    );\n    expect(\n      tester.getCenter(find.byKey(const ValueKey<String>('duel-score-B'))).dx,\n      lessThan(tester.getCenter(find.byKey(const ValueKey<String>('duel-name-B'))).dx),\n    );",
    "    final nameACenter = tester.getCenter(\n      find.byKey(const ValueKey<String>('duel-name-A')),\n    );\n    final nameBCenter = tester.getCenter(\n      find.byKey(const ValueKey<String>('duel-name-B')),\n    );\n    expect(nameACenter.dy, greaterThan(avatarACenter.dy));\n    expect(nameBCenter.dy, greaterThan(avatarBCenter.dy));\n    expect(\n      tester.getCenter(find.byKey(const ValueKey<String>('duel-score-A'))).dx,\n      greaterThan(nameACenter.dx),\n    );\n    expect(\n      tester.getCenter(find.byKey(const ValueKey<String>('duel-score-B'))).dx,\n      lessThan(nameBCenter.dx),\n    );",
)

backend = 'backend/social_worker/src/index.ts'
replace_once(
    backend,
    "    for (const socket of this.state.getWebSockets(playerId)) {\n      try {\n        socket.close(4001, 'Replaced by a newer connection.');\n      } catch {\n        // Closed sockets are ignored by the hibernation runtime.\n      }\n    }\n\n    const pair = new WebSocketPair();\n    const client = pair[0];\n    const server = pair[1];\n    this.state.acceptWebSocket(server, [playerId]);",
    "    const replacedSockets = this.state.getWebSockets(playerId);\n    const pair = new WebSocketPair();\n    const client = pair[0];\n    const server = pair[1];\n    this.state.acceptWebSocket(server, [playerId]);\n\n    for (const socket of replacedSockets) {\n      try {\n        socket.close(4001, 'Replaced by a newer connection.');\n      } catch {\n        // Closed sockets are ignored by the hibernation runtime.\n      }\n    }",
)
replace_once(
    backend,
    "    const seat = this.seatForPlayer(duel, playerId);\n    if (!seat) return;\n    const event = markDisconnected(duel, seat, Date.now());",
    "    const seat = this.seatForPlayer(duel, playerId);\n    if (!seat) return;\n    const hasReplacementSocket = this.state\n      .getWebSockets(playerId)\n      .some((candidate) => candidate !== socket && candidate.readyState === 1);\n    if (hasReplacementSocket) return;\n    const event = markDisconnected(duel, seat, Date.now());",
)

Path('backend/social_worker/test/websocket_replacement.test.ts').write_text(
    """import { readFileSync } from 'node:fs';\nimport { describe, expect, it } from 'vitest';\n\ndescribe('durable object websocket replacement', () => {\n  it('accepts the new socket before closing stale sockets', () => {\n    const source = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');\n    const capture = source.indexOf('const replacedSockets = this.state.getWebSockets(playerId);');\n    const accept = source.indexOf('this.state.acceptWebSocket(server, [playerId]);');\n    const closeLoop = source.indexOf('for (const socket of replacedSockets)');\n    expect(capture).toBeGreaterThanOrEqual(0);\n    expect(accept).toBeGreaterThan(capture);\n    expect(closeLoop).toBeGreaterThan(accept);\n  });\n\n  it('does not mark a player disconnected when a replacement socket is open', () => {\n    const source = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');\n    expect(source).toContain('const hasReplacementSocket = this.state');\n    expect(source).toContain('candidate !== socket && candidate.readyState === 1');\n    expect(source).toContain('if (hasReplacementSocket) return;');\n  });\n});\n""",
    encoding='utf-8',
)
