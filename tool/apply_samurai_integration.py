#!/usr/bin/env python3
"""Apply the Samurai mode entry point and synchronized localization keys."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CAREER = ROOT / "lib" / "features" / "career" / "career_hub_screen.dart"
APP_STRINGS = ROOT / "lib" / "localization" / "app_strings.dart"
ANDROID_STRINGS = (
    ROOT / "android" / "app" / "src" / "main" / "res" / "values" / "strings.xml"
)
IOS_CATALOG = ROOT / "assets" / "localization" / "Localizable.xcstrings"


def replace_once(path: Path, old: str, new: str) -> None:
    source = path.read_text(encoding="utf-8")
    count = source.count(old)
    if count != 1:
        raise RuntimeError(
            f"Expected exactly one integration marker in {path}: {old!r}; found {count}"
        )
    path.write_text(source.replace(old, new, 1), encoding="utf-8")


def integrate_career() -> None:
    replace_once(
        CAREER,
        "import '../../domain/sudoku.dart';\n",
        "import '../../domain/samurai_sudoku.dart';\n"
        "import '../../domain/sudoku.dart';\n",
    )
    replace_once(
        CAREER,
        "import '../game/enhanced_game_screen.dart';\n",
        "import '../game/enhanced_game_screen.dart';\n"
        "import '../game/samurai_game_screen.dart';\n",
    )
    replace_once(
        CAREER,
        "  bool _generatingDaily = false;\n",
        "  bool _generatingDaily = false;\n"
        "  bool _generatingSamurai = false;\n",
    )
    replace_once(
        CAREER,
        "      _generatingPractice != null ||\n"
        "      _generatingDaily;\n",
        "      _generatingPractice != null ||\n"
        "      _generatingDaily ||\n"
        "      _generatingSamurai;\n",
    )
    replace_once(
        CAREER,
        "                for (final difficulty in SudokuDifficulty.values) ...[\n",
        "                _PracticeCard(\n"
        "                  icon: Icons.dashboard_customize_rounded,\n"
        "                  title: context.tr('samurai_sudoku'),\n"
        "                  subtitle: context.tr('samurai_subtitle'),\n"
        "                  accent: const Color(0xFFE8794F),\n"
        "                  loading: _generatingSamurai,\n"
        "                  onTap: _busy ? null : _openSamurai,\n"
        "                ),\n"
        "                const SizedBox(height: 10),\n"
        "                for (final difficulty in SudokuDifficulty.values) ...[\n",
    )
    replace_once(
        CAREER,
        "  Future<void> _openDaily() async {\n",
        "  Future<void> _openSamurai() async {\n"
        "    final difficulty = await showModalBottomSheet<SudokuDifficulty>(\n"
        "      context: context,\n"
        "      useSafeArea: true,\n"
        "      showDragHandle: true,\n"
        "      builder: (sheetContext) => Padding(\n"
        "        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),\n"
        "        child: Column(\n"
        "          mainAxisSize: MainAxisSize.min,\n"
        "          crossAxisAlignment: CrossAxisAlignment.stretch,\n"
        "          children: <Widget>[\n"
        "            Text(\n"
        "              sheetContext.tr('samurai_choose_difficulty'),\n"
        "              textAlign: TextAlign.center,\n"
        "              style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(\n"
        "                    fontWeight: FontWeight.w900,\n"
        "                  ),\n"
        "            ),\n"
        "            const SizedBox(height: 12),\n"
        "            for (final value in SudokuDifficulty.values)\n"
        "              ListTile(\n"
        "                leading: Icon(\n"
        "                  Icons.dashboard_customize_rounded,\n"
        "                  color: _difficultyAccent(value),\n"
        "                ),\n"
        "                title: Text(\n"
        "                  sheetContext.strings.difficultyLabel(value),\n"
        "                  style: const TextStyle(fontWeight: FontWeight.w900),\n"
        "                ),\n"
        "                trailing: const Icon(Icons.chevron_right_rounded),\n"
        "                onTap: () => Navigator.of(sheetContext).pop(value),\n"
        "              ),\n"
        "          ],\n"
        "        ),\n"
        "      ),\n"
        "    );\n"
        "    if (!mounted || difficulty == null) return;\n"
        "\n"
        "    setState(() => _generatingSamurai = true);\n"
        "    final puzzle = await Future<SamuraiPuzzle>(\n"
        "      () => SamuraiEngine.generate(difficulty: difficulty),\n"
        "    );\n"
        "    if (!mounted) return;\n"
        "    setState(() => _generatingSamurai = false);\n"
        "\n"
        "    await Navigator.of(context).push<SamuraiGameExit>(\n"
        "      MaterialPageRoute(\n"
        "        builder: (_) => SamuraiGameScreen(\n"
        "          puzzle: puzzle,\n"
        "          store: widget.store,\n"
        "          onCompleted:\n"
        "              ({\n"
        "                required seconds,\n"
        "                required mistakes,\n"
        "                required hints,\n"
        "              }) async {\n"
        "                await widget.store.recordResult(\n"
        "                  puzzleId: 'practice-samurai-${difficulty.name}',\n"
        "                  seconds: seconds,\n"
        "                  mistakes: mistakes,\n"
        "                  hints: hints,\n"
        "                );\n"
        "                await _claimEligibleAchievements();\n"
        "              },\n"
        "        ),\n"
        "      ),\n"
        "    );\n"
        "    if (mounted) setState(() {});\n"
        "  }\n"
        "\n"
        "  Future<void> _openDaily() async {\n",
    )


def integrate_dart_strings() -> None:
    marker = "    'three_mistake_rule': 'Career rule: the round ends after 3 wrong moves.',\n"
    entries = (
        "    'samurai_sudoku': 'Samurai Sudoku',\n"
        "    'samurai_subtitle': 'Five overlapping 9×9 boards in one challenge',\n"
        "    'samurai_choose_difficulty': 'Choose Samurai difficulty',\n"
        "    'samurai_zoom_hint':\n"
        "        'Pinch to zoom and drag to move across the five linked boards.',\n"
        "    'samurai_pause_body':\n"
        "        'Your five linked boards are paused. Continue when ready.',\n"
        "    'samurai_completed_title': 'Samurai completed!',\n"
        "    'samurai_completed_body':\n"
        "        'You solved all five linked Sudoku boards.',\n"
    )
    replace_once(APP_STRINGS, marker, entries + marker)


def integrate_android_strings() -> None:
    marker = "    <string name=\"three_mistake_rule\">Career rule: the round ends after 3 wrong moves.</string>\n"
    entries = (
        "    <string name=\"samurai_sudoku\">Samurai Sudoku</string>\n"
        "    <string name=\"samurai_subtitle\">Five overlapping 9×9 boards in one challenge</string>\n"
        "    <string name=\"samurai_choose_difficulty\">Choose Samurai difficulty</string>\n"
        "    <string name=\"samurai_zoom_hint\">Pinch to zoom and drag to move across the five linked boards.</string>\n"
        "    <string name=\"samurai_pause_body\">Your five linked boards are paused. Continue when ready.</string>\n"
        "    <string name=\"samurai_completed_title\">Samurai completed!</string>\n"
        "    <string name=\"samurai_completed_body\">You solved all five linked Sudoku boards.</string>\n"
    )
    replace_once(ANDROID_STRINGS, marker, entries + marker)


def string_unit(value: str) -> dict[str, object]:
    return {
        "stringUnit": {
            "state": "translated",
            "value": value,
        }
    }


def integrate_ios_catalog() -> None:
    catalog = json.loads(IOS_CATALOG.read_text(encoding="utf-8"))
    strings = catalog.get("strings")
    if not isinstance(strings, dict):
        raise RuntimeError("Localizable.xcstrings has no strings object")

    values = {
        "samurai_sudoku": (
            "Samurai Sudoku",
            "Samuray Sudoku",
        ),
        "samurai_subtitle": (
            "Five overlapping 9×9 boards in one challenge",
            "Tek mücadelede birbiriyle kesişen beş 9×9 tahta",
        ),
        "samurai_choose_difficulty": (
            "Choose Samurai difficulty",
            "Samuray zorluğunu seç",
        ),
        "samurai_zoom_hint": (
            "Pinch to zoom and drag to move across the five linked boards.",
            "Beş bağlantılı tahtada gezinmek için yakınlaştırın ve sürükleyin.",
        ),
        "samurai_pause_body": (
            "Your five linked boards are paused. Continue when ready.",
            "Beş bağlantılı tahta duraklatıldı. Hazır olduğunuzda devam edin.",
        ),
        "samurai_completed_title": (
            "Samurai completed!",
            "Samuray tamamlandı!",
        ),
        "samurai_completed_body": (
            "You solved all five linked Sudoku boards.",
            "Birbirine bağlı beş Sudoku tahtasının tamamını çözdünüz.",
        ),
    }
    for key, (english, turkish) in values.items():
        if key in strings:
            raise RuntimeError(f"Localization key already exists: {key}")
        strings[key] = {
            "localizations": {
                "en": string_unit(english),
                "tr": string_unit(turkish),
            }
        }

    IOS_CATALOG.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    integrate_career()
    integrate_dart_strings()
    integrate_android_strings()
    integrate_ios_catalog()
    print("Samurai mode entry point and localization sources integrated.")


if __name__ == "__main__":
    main()
