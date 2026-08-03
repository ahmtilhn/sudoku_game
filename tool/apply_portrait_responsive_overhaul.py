from __future__ import annotations

import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "lib"
CHANGED: list[str] = []


def save(path: Path, content: str) -> None:
    original = path.read_text(encoding="utf-8") if path.exists() else ""
    if content == original:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    CHANGED.append(path.relative_to(ROOT).as_posix())


def ensure_responsive_import(path: Path, content: str) -> str:
    target = LIB / "widgets" / "responsive_layout.dart"
    relative = os.path.relpath(target, path.parent).replace(os.sep, "/")
    import_line = f"import '{relative}';"
    if import_line in content:
        return content
    material = "import 'package:flutter/material.dart';"
    if material not in content:
        raise RuntimeError(f"Material import missing in {path.relative_to(ROOT)}")
    return content.replace(material, f"{material}\n\n{import_line}", 1)


def replace_if_present(content: str, old: str, new: str) -> str:
    return content.replace(old, new, 1) if old in content else content


# All product sheets share one SafeArea, keyboard-aware and scroll-safe wrapper.
for dart_file in LIB.rglob("*.dart"):
    if dart_file.name == "responsive_layout.dart":
        continue
    content = dart_file.read_text(encoding="utf-8")
    if "showModalBottomSheet" not in content:
        continue
    content = content.replace("showModalBottomSheet", "showAdaptiveBottomSheet")
    content = ensure_responsive_import(dart_file, content)
    save(dart_file, content)


# Pre-match tablet row must not request an infinite cross-axis inside a scroll view.
pre_match = LIB / "features" / "duel" / "pre_match_ready_screen.dart"
content = pre_match.read_text(encoding="utf-8")
content = content.replace(
    "crossAxisAlignment:\n                                            CrossAxisAlignment.stretch,",
    "crossAxisAlignment:\n                                            CrossAxisAlignment.center,",
    1,
)
save(pre_match, content)


# Home: compact header, scroll-safe rematch and legacy-session migration.
home = LIB / "features" / "home" / "ux_root_screen.dart"
content = home.read_text(encoding="utf-8")
content = replace_if_present(
    content,
    "    final name = profile?.displayName ?? 'Sudoku Player';\n    return Row(",
    "    final name = profile?.displayName ?? 'Sudoku Player';\n"
    "    final metrics = ResponsiveMetrics.of(context);\n"
    "    final compact = metrics.isTiny || metrics.hasLargeText;\n"
    "    return Row(",
)
content = replace_if_present(
    content,
    """                const SizedBox(width: 8),
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
                ),""",
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
legacy_pattern = re.compile(
    r"  Future<void> _resumeLegacy\(ActiveGameSessionMetadata metadata\) async \{.*?\n  \}\n\n  Future<void> _claimEligibleAchievements",
    re.S,
)
legacy_replacement = """  Future<void> _resumeLegacy(ActiveGameSessionMetadata metadata) async {
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

  Future<void> _claimEligibleAchievements"""
content, _ = legacy_pattern.subn(legacy_replacement, content, count=1)
for unused in (
    "import '../../services/ads_service.dart';\n",
    "import '../game/game_screen.dart';\n",
    "import '../game/hint_economy.dart';\n",
):
    content = content.replace(unused, "")
content = ensure_responsive_import(home, content)
save(home, content)


# Store grid and product content use predictable heights instead of aspect ratios.
store = LIB / "features" / "economy" / "coin_store_screen.dart"
content = store.read_text(encoding="utf-8")
content = replace_if_present(
    content,
    """                final columns = constraints.maxWidth >= 820
                    ? 3
                    : constraints.maxWidth >= 520
                    ? 2
                    : 1;""",
    """                final columns = constraints.maxWidth >= 820
                    ? 3
                    : constraints.maxWidth >= 520
                    ? 2
                    : 1;
                final largeText =
                    MediaQuery.textScalerOf(context).scale(1) > 1.3;""",
)
content = replace_if_present(
    content,
    "childAspectRatio: columns == 1 ? 2.2 : 1.12,",
    """mainAxisExtent: columns == 1
                                ? (largeText ? 260 : 200)
                                : (largeText ? 310 : 240),""",
)
content = replace_if_present(
    content,
    """            SizedBox(
              width: 360,
              child: Row(""",
    """            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Row(""",
)
# Allow store product names to use a second line.
content = content.replace(
    """                    product.title,
                    maxLines: 1,""",
    """                    product.title,
                    maxLines: 2,""",
    1,
)
save(store, content)


# Matchmaking search composition reflows when height or text scale is constrained.
matchmaking = LIB / "features" / "duel" / "matchmaking_screen.dart"
content = matchmaking.read_text(encoding="utf-8")
content = content.replace("known ? '1000' : '?'", "'?'")
search_pattern = re.compile(
    r"                        final top = constraints\.maxHeight < 560 \? 18\.0 : 28\.0;\n"
    r"                        final bottom = top;\n"
    r"                        return Stack\(\n"
    r"                          children: \[.*?"
    r"                          \],\n"
    r"                        \);",
    re.S,
)
search_replacement = """                        final top = constraints.maxHeight < 560 ? 18.0 : 28.0;
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
                        );"""
content, _ = search_pattern.subn(search_replacement, content, count=1)
content = replace_if_present(
    content,
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
save(matchmaking, content)


# Extend the existing duel regression matrix to the accessibility maximum.
online_test = ROOT / "test" / "online_duel_screen_test.dart"
content = online_test.read_text(encoding="utf-8")
marker = """      _ViewportVariant(
        label: 'text scale 1.3 390x844',
        size: Size(390, 844),
        brightness: Brightness.dark,
        textScale: 1.3,
      ),"""
addition = marker + """
      _ViewportVariant(
        label: 'text scale 2.0 390x844',
        size: Size(390, 844),
        brightness: Brightness.dark,
        textScale: 2,
      ),"""
if "text scale 2.0 390x844" not in content:
    content = replace_if_present(content, marker, addition)
save(online_test, content)


# Shared responsive primitives are exercised across all supported portrait sizes.
responsive_test = ROOT / "test" / "portrait_responsive_widgets_test.dart"
save(
    responsive_test,
    """import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/widgets/responsive_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      testWidgets('adaptive actions fit ${size.width}x${size.height} at $scale', (
        tester,
      ) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
              ),
              child: const Scaffold(
                body: Padding(
                  padding: EdgeInsets.all(12),
                  child: AdaptiveActionGroup(
                    children: [
                      FilledButton(onPressed: null, child: Text('Primary action')),
                      OutlinedButton(onPressed: null, child: Text('Secondary action')),
                      TextButton(onPressed: null, child: Text('Another action')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Primary action'), findsOneWidget);
      });
    }
  }

  testWidgets('adaptive bottom sheet scrolls at 320x568 with 2x text', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(2),
          ),
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showAdaptiveBottomSheet<void>(
                    context: context,
                    builder: (_) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(
                        14,
                        (index) => ListTile(title: Text('Action $index')),
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
""",
)

print("Changed files:")
for item in CHANGED:
    print(f"- {item}")
if not CHANGED:
    raise SystemExit("No responsive changes generated")
