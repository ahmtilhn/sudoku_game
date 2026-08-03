from __future__ import annotations

import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / 'lib'


def read(path: Path) -> str:
    return path.read_text(encoding='utf-8')


def write(path: Path, value: str) -> None:
    path.write_text(value, encoding='utf-8')


def replace(path: Path, old: str, new: str, required: bool = True) -> None:
    value = read(path)
    if old not in value:
        if required:
            raise RuntimeError(f'missing pattern in {path.relative_to(ROOT)}')
        return
    write(path, value.replace(old, new, 1))


def regex(path: Path, pattern: str, new: str, required: bool = True) -> None:
    value = read(path)
    result, count = re.subn(pattern, new, value, count=1, flags=re.S)
    if not count:
        if required:
            raise RuntimeError(f'missing regex in {path.relative_to(ROOT)}')
        return
    write(path, result)


def add_responsive_import(path: Path) -> None:
    value = read(path)
    target = LIB / 'widgets' / 'responsive_layout.dart'
    rel = os.path.relpath(target, path.parent).replace(os.sep, '/')
    line = f"import '{rel}';"
    if line in value:
        return
    marker = "import 'package:flutter/material.dart';"
    if marker not in value:
        raise RuntimeError(f'material import missing in {path.relative_to(ROOT)}')
    write(path, value.replace(marker, marker + '\n\n' + line, 1))


# Active modal surfaces share one keyboard, SafeArea and scrolling contract.
for relative in (
    'features/game/enhanced_game_screen.dart',
    'features/duel/matchmaking_screen.dart',
    'features/home/ux_root_screen.dart',
):
    path = LIB / relative
    value = read(path)
    if 'showModalBottomSheet' in value:
        write(path, value.replace('showModalBottomSheet', 'showAdaptiveBottomSheet'))
        add_responsive_import(path)


# Store product cards grow vertically instead of depending on a fragile ratio.
store = LIB / 'features/economy/coin_store_screen.dart'
replace(
    store,
    """                final columns = constraints.maxWidth >= 820
                    ? 3
                    : constraints.maxWidth >= 520
                    ? 2
                    : 1;
                return CustomScrollView(""",
    """                final columns = constraints.maxWidth >= 820
                    ? 3
                    : constraints.maxWidth >= 520
                    ? 2
                    : 1;
                final largeText =
                    MediaQuery.textScalerOf(context).scale(1) > 1.3;
                return CustomScrollView(""",
)
replace(
    store,
    '                            childAspectRatio: columns == 1 ? 2.2 : 1.12,',
    """                            mainAxisExtent: columns == 1
                                ? (largeText ? 238 : 194)
                                : (largeText ? 278 : 236),""",
)


# Compact home header and move old saved sessions onto the enhanced game UI.
home = LIB / 'features/home/ux_root_screen.dart'
replace(
    home,
    """    final name = profile?.displayName ?? 'Sudoku Player';
    return Row(""",
    """    final name = profile?.displayName ?? 'Sudoku Player';
    final metrics = ResponsiveMetrics.of(context);
    final compact = metrics.isTiny || metrics.hasLargeText;
    return Row(""",
)
regex(
    home,
    r"""                const SizedBox\(width: 8\),\n                Flexible\(\n                  child: Text\(\n                    name,\n                    maxLines: 1,\n                    overflow: TextOverflow\.ellipsis,\n                    style: const TextStyle\(\n                      color: Colors\.white,\n                      fontWeight: FontWeight\.w900,\n                    \),\n                  \),\n                \),""",
    """                if (!compact) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],""",
)
regex(
    home,
    r"""  Future<void> _resumeLegacy\(ActiveGameSessionMetadata metadata\) async \{.*?\n  \}\n\n  Future<void> _claimEligibleAchievements""",
    """  Future<void> _resumeLegacy(ActiveGameSessionMetadata metadata) async {
    final level = CareerCatalog.byId(metadata.puzzleId);
    if (level == null) {
      await _legacySessions.clearAll();
      return;
    }
    final puzzle = await Future<SudokuPuzzle>(
      () => CareerCatalog.puzzleFor(level),
    );
    if (!mounted) return;
    final wasCompleted = widget.store.isCompleted(level.id);
    await _legacySessions.clearAll();
    await Navigator.of(context).push<EnhancedGameExit>(
      MaterialPageRoute(
        builder: (gameContext) => EnhancedGameScreen(
          puzzle: puzzle,
          store: widget.store,
          completionTitle: gameContext.tr('level_title', <Object>[
            gameContext.strings.difficultyLabel(level.difficulty),
            level.number,
          ]),
          onCompleted:
              ({
                required seconds,
                required mistakes,
                required hints,
              }) async {
                await widget.store.recordResult(
                  puzzleId: level.id,
                  seconds: seconds,
                  mistakes: mistakes,
                  hints: hints,
                );
                if (!wasCompleted && level.hintReward > 0) {
                  await widget.store.addHints(level.hintReward);
                }
                await _claimEligibleAchievements();
              },
        ),
      ),
    );
  }

  Future<void> _claimEligibleAchievements""",
)
value = read(home)
for line in (
    "import '../../services/ads_service.dart';\n",
    "import '../game/game_screen.dart';\n",
    "import '../game/hint_economy.dart';\n",
):
    value = value.replace(line, '')
write(home, value)


# Matchmaking search uses a vertical scrollable composition for large text.
matchmaking = LIB / 'features/duel/matchmaking_screen.dart'
replace(matchmaking, "known ? '1000' : '?'", "'?'")
replace(
    matchmaking,
    """                  Text(
                    context.tr('searching_similar_opponents'),
                    style: TextStyle(""",
    """                  Text(
                    context.tr('searching_similar_opponents'),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(""",
)
regex(
    matchmaking,
    r"""                        final top = constraints\.maxHeight < 560 \? 18\.0 : 28\.0;\n                        final bottom = top;\n                        return Stack\(\n                          children: \[.*?\n                          \],\n                        \);""",
    """                        final top = constraints.maxHeight < 560 ? 18.0 : 28.0;
                        final bottom = top;
                        final compact =
                            constraints.maxHeight < 390 ||
                            MediaQuery.textScalerOf(context).scale(1) > 1.3;
                        if (compact) {
                          return SingleChildScrollView(
                            child: Column(
                              children: [
                                _SearchPreviewCard(
                                  title: context.tr('you'),
                                  known: true,
                                ),
                                const SizedBox(height: 12),
                                const _SearchOrb(),
                                const SizedBox(height: 12),
                                _SearchPreviewCard(
                                  title: context.tr('searching_opponent_short'),
                                  known: false,
                                ),
                              ],
                            ),
                          );
                        }
                        return Stack(
                          children: [
                            Positioned(
                              left: side,
                              top: top,
                              width: cardWidth,
                              child: _SearchPreviewCard(
                                title: context.tr('you'),
                                known: true,
                              ),
                            ),
                            Positioned(
                              right: side,
                              bottom: bottom,
                              width: cardWidth,
                              child: _SearchPreviewCard(
                                title: context.tr('searching_opponent_short'),
                                known: false,
                              ),
                            ),
                            const Center(child: _SearchOrb()),
                          ],
                        );""",
)


# Shared portrait matrix: phones, portrait tablets and accessibility text.
test = ROOT / 'test' / 'portrait_responsive_widgets_test.dart'
write(test, """import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/widgets/responsive_layout.dart';

void main() {
  const sizes = <Size>[
    Size(320, 568),
    Size(360, 640),
    Size(390, 844),
    Size(412, 915),
    Size(600, 960),
    Size(768, 1024),
    Size(820, 1180),
  ];

  for (final size in sizes) {
    for (final scale in <double>[1, 1.3, 2]) {
      testWidgets('portrait ${size.width}x${size.height} at ${scale}x',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: SafeArea(
              child: AdaptiveActionGroup(children: [
                OutlinedButton(
                  onPressed: () {},
                  child: const Text('Decline request'),
                ),
                FilledButton(
                  onPressed: () {},
                  child: const Text('Accept challenge'),
                ),
              ]),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('bottom sheet scrolls at 320x568 with 2x text', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => showAdaptiveBottomSheet<void>(
              context: context,
              builder: (_) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 12; i++)
                    ListTile(title: Text('Responsive action $i')),
                ],
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
""")

# The transformer is intentionally one-shot and must not ship.
for temporary in (
    ROOT / 'tool' / 'apply_portrait_responsive_overhaul.py',
    ROOT / '.github' / 'workflows' / 'apply_portrait_responsive_overhaul.yml',
):
    if temporary.exists():
        temporary.unlink()
