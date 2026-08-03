from __future__ import annotations

import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "lib"
CHANGED: list[str] = []


def save(path: Path, content: str) -> None:
    original = path.read_text(encoding="utf-8")
    if content == original:
        return
    path.write_text(content, encoding="utf-8")
    CHANGED.append(path.relative_to(ROOT).as_posix())


def replace_once(path: Path, old: str, new: str, *, required: bool = True) -> None:
    content = path.read_text(encoding="utf-8")
    if old not in content:
        if required:
            raise RuntimeError(f"Required text was not found in {path.relative_to(ROOT)}")
        return
    save(path, content.replace(old, new, 1))


def regex_once(path: Path, pattern: str, replacement: str, *, required: bool = True) -> None:
    content = path.read_text(encoding="utf-8")
    updated, count = re.subn(pattern, replacement, content, count=1, flags=re.S)
    if count == 0:
        if required:
            raise RuntimeError(f"Required pattern was not found in {path.relative_to(ROOT)}")
        return
    save(path, updated)


def ensure_responsive_import(path: Path) -> None:
    content = path.read_text(encoding="utf-8")
    target = LIB / "widgets" / "responsive_layout.dart"
    relative = os.path.relpath(target, path.parent).replace(os.sep, "/")
    import_line = f"import '{relative}';"
    if import_line in content:
        return
    flutter_import = "import 'package:flutter/material.dart';"
    if flutter_import not in content:
        raise RuntimeError(f"Flutter material import missing in {path.relative_to(ROOT)}")
    save(path, content.replace(flutter_import, f"{flutter_import}\n\n{import_line}", 1))


# Route every modal sheet through the shared scroll/SafeArea/keyboard-safe wrapper.
for dart_file in LIB.rglob("*.dart"):
    if dart_file.name == "responsive_layout.dart":
        continue
    content = dart_file.read_text(encoding="utf-8")
    if "showModalBottomSheet" not in content:
        continue
    save(dart_file, content.replace("showModalBottomSheet", "showAdaptiveBottomSheet"))
    ensure_responsive_import(dart_file)


# Career cards become taller and collapse to one column when accessibility text is large.
career = LIB / "features" / "career" / "career_hub_screen.dart"
replace_once(
    career,
    """            final maxWidth = constraints.maxWidth >= 840 ? 760.0 : 680.0;\n            return Center(""",
    """            final maxWidth = constraints.maxWidth >= 840 ? 760.0 : 680.0;\n            final largeText =\n                MediaQuery.textScalerOf(context).scale(1) > 1.3;\n            return Center(""",
)
replace_once(
    career,
    """                      gridDelegate:\n                          const SliverGridDelegateWithMaxCrossAxisExtent(\n                            maxCrossAxisExtent: 230,\n                            mainAxisExtent: 142,\n                            crossAxisSpacing: 10,\n                            mainAxisSpacing: 10,\n                          ),""",
    """                      gridDelegate:\n                          SliverGridDelegateWithMaxCrossAxisExtent(\n                            maxCrossAxisExtent: largeText ? 680 : 230,\n                            mainAxisExtent: largeText ? 190 : 150,\n                            crossAxisSpacing: 10,\n                            mainAxisSpacing: 10,\n                          ),""",
)


# Store cards use a fixed responsive height instead of a fragile aspect ratio.
store = LIB / "features" / "economy" / "coin_store_screen.dart"
replace_once(
    store,
    """                final columns = constraints.maxWidth >= 820\n                    ? 3\n                    : constraints.maxWidth >= 520\n                    ? 2\n                    : 1;""",
    """                final columns = constraints.maxWidth >= 820\n                    ? 3\n                    : constraints.maxWidth >= 520\n                    ? 2\n                    : 1;\n                final largeText =\n                    MediaQuery.textScalerOf(context).scale(1) > 1.3;""",
)
replace_once(
    store,
    """                            childAspectRatio: columns == 1 ? 2.2 : 1.12,""",
    """                            mainAxisExtent: columns == 1\n                                ? (largeText ? 230 : 190)\n                                : (largeText ? 270 : 230),""",
)


# Home top bar hides the name only at the narrowest widths and legacy games reopen in the enhanced screen.
home = LIB / "features" / "home" / "ux_root_screen.dart"
replace_once(
    home,
    """    final name = profile?.displayName ?? 'Sudoku Player';\n    return Row(""",
    """    final name = profile?.displayName ?? 'Sudoku Player';\n    final metrics = ResponsiveMetrics.of(context);\n    final compact = metrics.isTiny || metrics.hasLargeText;\n    return Row(""",
)
regex_once(
    home,
    r"""                const SizedBox\(width: 8\),\n                Flexible\(\n                  child: Text\(\n                    name,\n                    maxLines: 1,\n                    overflow: TextOverflow\.ellipsis,\n                    style: const TextStyle\(\n                      color: Colors\.white,\n                      fontWeight: FontWeight\.w900,\n                    \),\n                  \),\n                \),""",
    """                if (!compact) ...[\n                  const SizedBox(width: 8),\n                  Flexible(\n                    child: Text(\n                      name,\n                      maxLines: 1,\n                      overflow: TextOverflow.ellipsis,\n                      style: const TextStyle(\n                        color: Colors.white,\n                        fontWeight: FontWeight.w900,\n                      ),\n                    ),\n                  ),\n                ],""",
)
regex_once(
    home,
    r"""  Future<void> _resumeLegacy\(ActiveGameSessionMetadata metadata\) async \{.*?\n  \}\n\n  Future<void> _claimEligibleAchievements""",
    """  Future<void> _resumeLegacy(ActiveGameSessionMetadata metadata) async {\n    final level = CareerCatalog.byId(metadata.puzzleId);\n    if (level == null) {\n      await _legacySessions.clearAll();\n      return;\n    }\n    final puzzle = await Future<SudokuPuzzle>(\n      () => CareerCatalog.puzzleFor(level),\n    );\n    if (!mounted) return;\n    final wasCompleted = widget.store.isCompleted(level.id);\n    await _legacySessions.clearAll();\n    await Navigator.of(context).push<EnhancedGameExit>(\n      MaterialPageRoute(\n        builder: (gameContext) => EnhancedGameScreen(\n          puzzle: puzzle,\n          store: widget.store,\n          completionTitle: gameContext.tr('level_title', <Object>[\n            gameContext.strings.difficultyLabel(level.difficulty),\n            level.number,\n          ]),\n          onCompleted:\n              ({\n                required seconds,\n                required mistakes,\n                required hints,\n              }) async {\n                await widget.store.recordResult(\n                  puzzleId: level.id,\n                  seconds: seconds,\n                  mistakes: mistakes,\n                  hints: hints,\n                );\n                if (!wasCompleted && level.hintReward > 0) {\n                  await widget.store.addHints(level.hintReward);\n                }\n                await _claimEligibleAchievements();\n              },\n        ),\n      ),\n    );\n  }\n\n  Future<void> _claimEligibleAchievements""",
)
home_content = home.read_text(encoding="utf-8")
for unused_import in (
    "import '../../services/ads_service.dart';\n",
    "import '../game/game_screen.dart';\n",
    "import '../game/hint_economy.dart';\n",
):
    home_content = home_content.replace(unused_import, "")
save(home, home_content)


# Account mode selector switches to vertically stacked radio tiles on tiny/large-text layouts.
account = LIB / "features" / "settings" / "account_protection_screen.dart"
regex_once(
    account,
    r"""            SegmentedButton<bool>\(.*?            const SizedBox\(height: 16\),""",
    """            LayoutBuilder(\n              builder: (context, constraints) {\n                final compact =\n                    constraints.maxWidth < 390 ||\n                    MediaQuery.textScalerOf(context).scale(1) > 1.3;\n                void selectMode(bool value) {\n                  setState(() {\n                    _signInMode = value;\n                    _error = null;\n                    _notice = null;\n                    _confirm.clear();\n                  });\n                }\n                if (compact) {\n                  return Column(\n                    children: [\n                      RadioListTile<bool>(\n                        contentPadding: EdgeInsets.zero,\n                        value: false,\n                        groupValue: _signInMode,\n                        onChanged: _busy\n                            ? null\n                            : (value) => selectMode(value ?? false),\n                        secondary: const Icon(Icons.shield_outlined),\n                        title: const Text('Protect current'),\n                      ),\n                      RadioListTile<bool>(\n                        contentPadding: EdgeInsets.zero,\n                        value: true,\n                        groupValue: _signInMode,\n                        onChanged: _busy\n                            ? null\n                            : (value) => selectMode(value ?? true),\n                        secondary: const Icon(Icons.login_outlined),\n                        title: const Text('Sign in'),\n                      ),\n                    ],\n                  );\n                }\n                return SegmentedButton<bool>(\n                  segments: const [\n                    ButtonSegment(\n                      value: false,\n                      icon: Icon(Icons.shield_outlined),\n                      label: Text('Protect current'),\n                    ),\n                    ButtonSegment(\n                      value: true,\n                      icon: Icon(Icons.login_outlined),\n                      label: Text('Sign in'),\n                    ),\n                  ],\n                  selected: <bool>{_signInMode},\n                  onSelectionChanged: _busy\n                      ? null\n                      : (values) => selectMode(values.first),\n                );\n              },\n            ),\n            const SizedBox(height: 16),""",
)


# Challenge economy metrics reflow vertically on narrow screens and at large text scales.
challenge = LIB / "features" / "social" / "ux_challenge_invitation_screen.dart"
replace_once(
    challenge,
    """                Card(\n                  color: Colors.black.withValues(alpha: .22),\n                  child: Padding(\n                    padding: const EdgeInsets.all(14),\n                    child: Row(\n                      children: [\n                        Expanded(\n                          child: _CoinValue(\n                            label: context.tr('current_balance'),\n                            value: _economy.balance,\n                          ),\n                        ),\n                        Expanded(\n                          child: _CoinValue(\n                            label: context.tr('entry_fee'),\n                            value: _entryFee,\n                          ),\n                        ),\n                        Expanded(\n                          child: _CoinValue(\n                            label: context.tr('winner_pot'),\n                            value: _entryFee * 2,\n                          ),\n                        ),\n                      ],\n                    ),\n                  ),\n                ),""",
    """                Card(\n                  color: Colors.black.withValues(alpha: .22),\n                  child: Padding(\n                    padding: const EdgeInsets.all(14),\n                    child: LayoutBuilder(\n                      builder: (context, constraints) {\n                        final compact =\n                            constraints.maxWidth < 420 ||\n                            MediaQuery.textScalerOf(context).scale(1) > 1.3;\n                        final values = [\n                          _CoinValue(\n                            label: context.tr('current_balance'),\n                            value: _economy.balance,\n                          ),\n                          _CoinValue(\n                            label: context.tr('entry_fee'),\n                            value: _entryFee,\n                          ),\n                          _CoinValue(\n                            label: context.tr('winner_pot'),\n                            value: _entryFee * 2,\n                          ),\n                        ];\n                        if (compact) {\n                          return Column(\n                            children: [\n                              for (var index = 0;\n                                  index < values.length;\n                                  index++) ...[\n                                if (index > 0) const Divider(height: 18),\n                                values[index],\n                              ],\n                            ],\n                          );\n                        }\n                        return Row(\n                          children: [\n                            for (final value in values) Expanded(child: value),\n                          ],\n                        );\n                      },\n                    ),\n                  ),\n                ),""",
)


# Matchmaking search composition falls back to a scrollable vertical arrangement on short/large-text screens.
matchmaking = LIB / "features" / "duel" / "matchmaking_screen.dart"
replace_once(matchmaking, "known ? '1000' : '?'", "'?'")
regex_once(
    matchmaking,
    r"""                        final top = constraints\.maxHeight < 560 \? 18\.0 : 28\.0;\n                        final bottom = top;\n                        return Stack\(\n                          children: \[.*?                          \],\n                        \);""",
    """                        final top = constraints.maxHeight < 560 ? 18.0 : 28.0;\n                        final bottom = top;\n                        final compact =\n                            constraints.maxHeight < 390 ||\n                            MediaQuery.textScalerOf(context).scale(1) > 1.3;\n                        if (compact) {\n                          return SingleChildScrollView(\n                            child: Column(\n                              children: [\n                                _SearchPreviewCard(\n                                  title: context.tr('you'),\n                                  known: true,\n                                ),\n                                const SizedBox(height: 12),\n                                const _SearchOrb(),\n                                const SizedBox(height: 12),\n                                _SearchPreviewCard(\n                                  title: context.tr('searching_opponent_short'),\n                                  known: false,\n                                ),\n                              ],\n                            ),\n                          );\n                        }\n                        return Stack(\n                          children: [\n                            Positioned(\n                              left: side,\n                              top: top,\n                              width: cardWidth,\n                              child: _SearchPreviewCard(\n                                title: context.tr('you'),\n                                known: true,\n                              ),\n                            ),\n                            Positioned(\n                              right: side,\n                              bottom: bottom,\n                              width: cardWidth,\n                              child: _SearchPreviewCard(\n                                title: context.tr('searching_opponent_short'),\n                                known: false,\n                              ),\n                            ),\n                            const Center(child: _SearchOrb()),\n                          ],\n                        );""",
)
replace_once(
    matchmaking,
    """                  Text(\n                    context.tr('searching_similar_opponents'),\n                    style: TextStyle(""",
    """                  Text(\n                    context.tr('searching_similar_opponents'),\n                    textAlign: TextAlign.center,\n                    maxLines: 3,\n                    overflow: TextOverflow.ellipsis,\n                    style: TextStyle(""",
)


# Add a reusable portrait test matrix for shared responsive primitives.
test_file = ROOT / "test" / "portrait_responsive_widgets_test.dart"
test_file.write_text(
    """import 'package:flutter/material.dart';\nimport 'package:flutter_test/flutter_test.dart';\nimport 'package:sudoku_game/widgets/responsive_layout.dart';\n\nvoid main() {\n  const sizes = <Size>[\n    Size(320, 568),\n    Size(360, 640),\n    Size(390, 844),\n    Size(412, 915),\n    Size(600, 960),\n    Size(768, 1024),\n    Size(820, 1180),\n  ];\n\n  for (final size in sizes) {\n    for (final scale in <double>[1, 1.3, 2]) {\n      testWidgets(\n        'adaptive actions avoid overflow at ${size.width}x${size.height} and ${scale}x text',\n        (tester) async {\n          tester.view.devicePixelRatio = 1;\n          tester.view.physicalSize = size;\n          addTearDown(tester.view.resetPhysicalSize);\n          addTearDown(tester.view.resetDevicePixelRatio);\n\n          await tester.pumpWidget(\n            MaterialApp(\n              builder: (context, child) => MediaQuery(\n                data: MediaQuery.of(context).copyWith(\n                  size: size,\n                  textScaler: TextScaler.linear(scale),\n                ),\n                child: child!,\n              ),\n              home: Scaffold(\n                body: SafeArea(\n                  child: Align(\n                    alignment: Alignment.topCenter,\n                    child: SizedBox(\n                      width: size.width,\n                      child: AdaptiveActionGroup(\n                        children: [\n                          OutlinedButton(\n                            onPressed: () {},\n                            child: const Text('Decline request'),\n                          ),\n                          FilledButton(\n                            onPressed: () {},\n                            child: const Text('Accept challenge'),\n                          ),\n                        ],\n                      ),\n                    ),\n                  ),\n                ),\n              ),\n            ),\n          );\n\n          await tester.pumpAndSettle();\n          expect(tester.takeException(), isNull);\n        },\n      );\n    }\n  }\n\n  testWidgets('adaptive bottom sheet remains scrollable with 2x text', (tester) async {\n    tester.view.devicePixelRatio = 1;\n    tester.view.physicalSize = const Size(320, 568);\n    addTearDown(tester.view.resetPhysicalSize);\n    addTearDown(tester.view.resetDevicePixelRatio);\n\n    await tester.pumpWidget(\n      MaterialApp(\n        builder: (context, child) => MediaQuery(\n          data: MediaQuery.of(context).copyWith(\n            textScaler: const TextScaler.linear(2),\n          ),\n          child: child!,\n        ),\n        home: Builder(\n          builder: (context) => Scaffold(\n            body: Center(\n              child: FilledButton(\n                onPressed: () => showAdaptiveBottomSheet<void>(\n                  context: context,\n                  builder: (_) => Column(\n                    mainAxisSize: MainAxisSize.min,\n                    children: [\n                      for (var index = 0; index < 12; index++)\n                        ListTile(title: Text('Responsive action $index')),\n                    ],\n                  ),\n                ),\n                child: const Text('Open'),\n              ),\n            ),\n          ),\n        ),\n      ),\n    );\n\n    await tester.tap(find.text('Open'));\n    await tester.pumpAndSettle();\n    expect(find.byType(SingleChildScrollView), findsWidgets);\n    expect(tester.takeException(), isNull);\n  });\n}\n""",
    encoding="utf-8",
)
CHANGED.append(test_file.relative_to(ROOT).as_posix())

# Remove the one-time transformer and its workflow from the resulting branch.
for temporary in (
    ROOT / "tool" / "apply_portrait_responsive_overhaul.py",
    ROOT / ".github" / "workflows" / "apply_portrait_responsive_overhaul.yml",
):
    if temporary.exists():
        temporary.unlink()
        CHANGED.append(temporary.relative_to(ROOT).as_posix())

print("Responsive overhaul changed:")
for item in sorted(set(CHANGED)):
    print(f" - {item}")
