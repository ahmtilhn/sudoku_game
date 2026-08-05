#!/usr/bin/env python3
"""Integrate Samurai ranked matchmaking and online rendering in Flutter."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / 'lib/services/online_duel_models.dart'
SOCIAL = ROOT / 'lib/services/social_api_client.dart'
MATCHMAKING = ROOT / 'lib/features/duel/matchmaking_screen.dart'
ONLINE = ROOT / 'lib/features/duel/online_duel_screen.dart'
DART_STRINGS = ROOT / 'lib/localization/app_strings.dart'
ANDROID_STRINGS = ROOT / 'android/app/src/main/res/values/strings.xml'
IOS_CATALOG = ROOT / 'assets/localization/Localizable.xcstrings'


def replace_once(path: Path, old: str, new: str) -> None:
    source = path.read_text(encoding='utf-8')
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f'Expected one marker in {path}: {old!r}; found {count}')
    path.write_text(source.replace(old, new, 1), encoding='utf-8')


def patch_models() -> None:
    replace_once(
        MODELS,
        'enum OnlineDuelStatus {\n',
        "import '../domain/samurai_sudoku.dart';\n\n"
        'enum OnlineDuelStatus {\n',
    )
    replace_once(
        MODELS,
        '    required this.mode,\n    required this.difficulty,\n',
        "    required this.mode,\n    this.variant = 'classic',\n    required this.difficulty,\n",
    )
    replace_once(
        MODELS,
        '  final String mode;\n  final String difficulty;\n',
        '  final String mode;\n  final String variant;\n  final String difficulty;\n',
    )
    replace_once(
        MODELS,
        '      mode: mode,\n      difficulty: difficulty,\n',
        '      mode: mode,\n      variant: variant,\n      difficulty: difficulty,\n',
    )
    replace_once(
        MODELS,
        "    final puzzle = _intList(json['puzzle']);\n"
        "    final board = _intList(json['board']);\n"
        '    _validateSnapshotShape(puzzle: puzzle, board: board);\n',
        "    final puzzle = _intList(json['puzzle']);\n"
        "    final board = _intList(json['board']);\n"
        "    final variant = json['variant']?.toString() ?? 'classic';\n"
        '    _validateSnapshotShape(\n'
        '      puzzle: puzzle,\n'
        '      board: board,\n'
        '      variant: variant,\n'
        '    );\n',
    )
    replace_once(
        MODELS,
        "      mode: json['mode']?.toString() ?? 'friendly',\n"
        "      difficulty: json['difficulty']?.toString() ?? 'easy',\n",
        "      mode: json['mode']?.toString() ?? 'friendly',\n"
        '      variant: variant,\n'
        "      difficulty: json['difficulty']?.toString() ?? 'easy',\n",
    )
    replace_once(
        MODELS,
        'void _validateSnapshotShape({\n'
        '  required List<int> puzzle,\n'
        '  required List<int> board,\n'
        '}) {\n',
        'void _validateSnapshotShape({\n'
        '  required List<int> puzzle,\n'
        '  required List<int> board,\n'
        '  required String variant,\n'
        '}) {\n',
    )
    marker = (
        "  final size = switch (puzzle.length) {\n"
        '    16 => 4,\n'
        '    81 => 9,\n'
        '    _ => 0,\n'
        '  };\n'
    )
    samurai_validation = (
        "  if (variant == 'samurai') {\n"
        '    if (puzzle.length != SamuraiTopology.canvasCellCount) {\n'
        '      throw FormatException(\n'
        "        'Unsupported Samurai duel board length: ${puzzle.length}.',\n"
        '      );\n'
        '    }\n'
        '    for (var index = 0; index < puzzle.length; index++) {\n'
        '      final clue = puzzle[index];\n'
        '      final value = board[index];\n'
        '      if (!SamuraiTopology.isActiveIndex(index)) {\n'
        '        if (clue != SamuraiTopology.inactiveCell ||\n'
        '            value != SamuraiTopology.inactiveCell) {\n'
        "          throw FormatException('Invalid inactive Samurai cell at $index.');\n"
        '        }\n'
        '        continue;\n'
        '      }\n'
        '      if (clue < 0 || clue > 9 || value < 0 || value > 9) {\n'
        "        throw FormatException('Invalid Samurai duel cell at $index.');\n"
        '      }\n'
        '      if (clue != 0 && value != clue) {\n'
        "        throw FormatException('Samurai duel changed a clue at $index.');\n"
        '      }\n'
        '    }\n'
        '    return;\n'
        '  }\n'
    )
    replace_once(MODELS, marker, samurai_validation + marker)


def patch_social() -> None:
    replace_once(
        SOCIAL,
        '    required this.id,\n    required this.difficulty,\n    required this.status,\n',
        "    required this.id,\n    this.variant = 'classic',\n    required this.difficulty,\n    required this.status,\n",
    )
    replace_once(
        SOCIAL,
        '  final String id;\n  final String difficulty;\n  final String status;\n',
        '  final String id;\n  final String variant;\n  final String difficulty;\n  final String status;\n',
    )
    replace_once(
        SOCIAL,
        "      id: json['id']?.toString() ?? '',\n"
        "      difficulty: json['difficulty']?.toString() ?? 'easy',\n",
        "      id: json['id']?.toString() ?? '',\n"
        "      variant: json['variant']?.toString() ?? 'classic',\n"
        "      difficulty: json['difficulty']?.toString() ?? 'easy',\n",
    )
    replace_once(
        SOCIAL,
        '    required this.status,\n    required this.difficulty,\n    this.roomId,\n',
        "    required this.status,\n    this.variant = 'classic',\n    required this.difficulty,\n    this.roomId,\n",
    )
    replace_once(
        SOCIAL,
        '  final String status;\n  final String difficulty;\n  final String? roomId;\n',
        '  final String status;\n  final String variant;\n  final String difficulty;\n  final String? roomId;\n',
    )
    replace_once(
        SOCIAL,
        "      status: json['status']?.toString() ?? 'queued',\n"
        "      difficulty: json['difficulty']?.toString() ?? 'easy',\n",
        "      status: json['status']?.toString() ?? 'queued',\n"
        "      variant: json['variant']?.toString() ?? 'classic',\n"
        "      difficulty: json['difficulty']?.toString() ?? 'easy',\n",
    )
    replace_once(
        SOCIAL,
        '  Future<SocialChallenge> createChallenge({\n'
        '    required String recipientPublicId,\n'
        '    required String difficulty,\n'
        '  }) async {\n',
        '  Future<SocialChallenge> createChallenge({\n'
        '    required String recipientPublicId,\n'
        '    required String difficulty,\n'
        "    String variant = 'classic',\n"
        '  }) async {\n',
    )
    replace_once(
        SOCIAL,
        "        'recipientPublicId': recipientPublicId,\n"
        "        'difficulty': difficulty,\n",
        "        'recipientPublicId': recipientPublicId,\n"
        "        'variant': variant,\n"
        "        'difficulty': difficulty,\n",
    )
    replace_once(
        SOCIAL,
        '  Future<MatchmakingResult> joinRankedQueue({\n'
        '    required String difficulty,\n'
        '  }) async {\n',
        '  Future<MatchmakingResult> joinRankedQueue({\n'
        '    required String difficulty,\n'
        "    String variant = 'classic',\n"
        '  }) async {\n',
    )
    replace_once(
        SOCIAL,
        "      body: <String, Object>{'difficulty': difficulty},\n",
        "      body: <String, Object>{\n"
        "        'variant': variant,\n"
        "        'difficulty': difficulty,\n"
        '      },\n',
    )


def patch_matchmaking() -> None:
    replace_once(
        MATCHMAKING,
        'class MatchmakingScreen extends StatefulWidget {\n'
        '  const MatchmakingScreen({super.key, this.initialDifficulty});\n\n'
        '  final SudokuDifficulty? initialDifficulty;\n',
        'class MatchmakingScreen extends StatefulWidget {\n'
        '  const MatchmakingScreen({\n'
        '    super.key,\n'
        '    this.initialDifficulty,\n'
        "    this.initialVariant = 'classic',\n"
        '  });\n\n'
        '  final SudokuDifficulty? initialDifficulty;\n'
        '  final String initialVariant;\n',
    )
    replace_once(
        MATCHMAKING,
        '  late SudokuDifficulty _difficulty;\n  bool _searching = false;\n',
        "  late SudokuDifficulty _difficulty;\n  late String _variant;\n  bool _searching = false;\n",
    )
    replace_once(
        MATCHMAKING,
        '    _difficulty = widget.initialDifficulty ?? SudokuDifficulty.easy;\n',
        "    _difficulty = widget.initialDifficulty ?? SudokuDifficulty.easy;\n"
        "    _variant = widget.initialVariant == 'samurai' ? 'samurai' : 'classic';\n",
    )
    replace_once(
        MATCHMAKING,
        '                      _EntrySummary(economy: _economy, difficulty: _difficulty),\n'
        '                      const SizedBox(height: 16),\n'
        '                      Text(\n'
        "                        context.tr('choose_duel_difficulty'),\n",
        '                      _EntrySummary(economy: _economy, difficulty: _difficulty),\n'
        '                      const SizedBox(height: 16),\n'
        '                      Text(\n'
        "                        context.tr('choose_duel_variant'),\n"
        '                        style: const TextStyle(\n'
        '                          color: Colors.white,\n'
        '                          fontSize: 20,\n'
        '                          fontWeight: FontWeight.w900,\n'
        '                        ),\n'
        '                      ),\n'
        '                      const SizedBox(height: 10),\n'
        '                      SegmentedButton<String>(\n'
        '                        segments: <ButtonSegment<String>>[\n'
        '                          ButtonSegment<String>(\n'
        "                            value: 'classic',\n"
        '                            icon: const Icon(Icons.grid_3x3_rounded),\n'
        "                            label: Text(context.tr('duel_variant_classic')),\n"
        '                          ),\n'
        '                          ButtonSegment<String>(\n'
        "                            value: 'samurai',\n"
        '                            icon: const Icon(Icons.dashboard_customize_rounded),\n'
        "                            label: Text(context.tr('samurai_sudoku')),\n"
        '                          ),\n'
        '                        ],\n'
        '                        selected: <String>{_variant},\n'
        '                        onSelectionChanged: _searching\n'
        '                            ? null\n'
        '                            : (selection) => setState(\n'
        '                                  () => _variant = selection.first,\n'
        '                                ),\n'
        '                      ),\n'
        '                      const SizedBox(height: 8),\n'
        '                      Text(\n'
        "                        context.tr('same_variant_match'),\n"
        '                        style: TextStyle(\n'
        '                          color: Colors.white.withValues(alpha: .72),\n'
        '                          fontWeight: FontWeight.w600,\n'
        '                        ),\n'
        '                      ),\n'
        '                      const SizedBox(height: 16),\n'
        '                      Text(\n'
        "                        context.tr('choose_duel_difficulty'),\n",
    )
    replace_once(
        MATCHMAKING,
        '      final result = await SocialApiClient.instance.joinRankedQueue(\n'
        '        difficulty: _difficulty.name,\n'
        '      );\n',
        '      final result = await SocialApiClient.instance.joinRankedQueue(\n'
        '        difficulty: _difficulty.name,\n'
        '        variant: _variant,\n'
        '      );\n',
    )
    replace_once(
        MATCHMAKING,
        '        final refreshed = await SocialApiClient.instance.joinRankedQueue(\n'
        '          difficulty: _difficulty.name,\n'
        '        );\n',
        '        final refreshed = await SocialApiClient.instance.joinRankedQueue(\n'
        '          difficulty: _difficulty.name,\n'
        '          variant: _variant,\n'
        '        );\n',
    )


def patch_online() -> None:
    replace_once(
        ONLINE,
        "import '../../domain/sudoku.dart';\n",
        "import '../../domain/samurai_sudoku.dart';\n"
        "import '../../domain/sudoku.dart';\n",
    )
    replace_once(
        ONLINE,
        "import '../../widgets/player_avatar.dart';\n"
        "import '../../widgets/sudoku_board.dart';\n",
        "import '../../widgets/player_avatar.dart';\n"
        "import '../../widgets/samurai_board.dart';\n"
        "import '../../widgets/sudoku_board.dart';\n",
    )
    replace_once(
        ONLINE,
        '          MaterialPageRoute(builder: (_) => const MatchmakingScreen()),\n',
        '          MaterialPageRoute(\n'
        '            builder: (_) => MatchmakingScreen(\n'
        '              initialDifficulty: _difficulty(snapshot.difficulty),\n'
        '              initialVariant: snapshot.variant,\n'
        '            ),\n'
        '          ),\n',
    )
    replace_once(
        ONLINE,
        '                      completedValues: completedSudokuNumbers(\n'
        '                        board: snapshot.board,\n'
        '                        maxValue: 9,\n'
        '                      ),\n',
        "                      completedValues: snapshot.variant == 'samurai'\n"
        '                          ? const <int>{}\n'
        '                          : completedSudokuNumbers(\n'
        '                              board: snapshot.board,\n'
        '                              maxValue: 9,\n'
        '                            ),\n',
    )
    replace_once(
        ONLINE,
        "    final puzzle = SudokuPuzzle(\n"
        "      id: 'online-${snapshot.matchId}',\n"
        "      title: 'Online Duel',\n"
        '      difficulty: _difficulty(snapshot.difficulty),\n'
        '      puzzle: snapshot.puzzle,\n'
        '      solution: List<int>.filled(81, 1),\n'
        '    );\n',
        "    final puzzle = SudokuPuzzle(\n"
        "      id: 'online-${snapshot.matchId}',\n"
        "      title: 'Online Duel',\n"
        '      difficulty: _difficulty(snapshot.difficulty),\n'
        '      puzzle: snapshot.variant == \'samurai\'\n'
        '          ? const <int>[]\n'
        '          : snapshot.puzzle,\n'
        '      solution: List<int>.filled(81, 1),\n'
        '    );\n'
        '    final samuraiPuzzle = SamuraiPuzzle(\n'
        "      id: 'online-${snapshot.matchId}',\n"
        "      title: 'Online Samurai Duel',\n"
        '      difficulty: _difficulty(snapshot.difficulty),\n'
        '      puzzle: snapshot.puzzle,\n'
        '      solution: snapshot.board,\n'
        '    );\n',
    )
    old_board = (
        '        final board = RepaintBoundary(\n'
        '          child: IgnorePointer(\n'
        '            ignoring: snapshot.isFinished || !snapshot.isLocalTurn,\n'
        '            child: SudokuBoard(\n'
        '              puzzle: puzzle,\n'
        '              board: snapshot.board,\n'
        '              selectedIndex: _selectedIndex,\n'
        '              errorIndex: _feedbackCell,\n'
        '              localMoveIndexes: _localMoveIndexes,\n'
        '              opponentMoveIndexes: _opponentMoveIndexes,\n'
        '              enabled: !snapshot.isFinished && snapshot.isLocalTurn,\n'
        '              onCellTap: _selectCell,\n'
        '            ),\n'
        '          ),\n'
        '        );\n'
    )
    new_board = (
        "        final board = snapshot.variant == 'samurai'\n"
        '            ? RepaintBoundary(\n'
        '                child: IgnorePointer(\n'
        '                  ignoring: snapshot.isFinished || !snapshot.isLocalTurn,\n'
        '                  child: SamuraiBoard(\n'
        '                    puzzle: samuraiPuzzle,\n'
        '                    board: snapshot.board,\n'
        '                    selectedIndex: _selectedIndex,\n'
        '                    errorIndex: _feedbackCell,\n'
        '                    enabled: !snapshot.isFinished && snapshot.isLocalTurn,\n'
        '                    onCellTap: _selectCell,\n'
        '                  ),\n'
        '                ),\n'
        '              )\n'
        '            : RepaintBoundary(\n'
        '                child: IgnorePointer(\n'
        '                  ignoring: snapshot.isFinished || !snapshot.isLocalTurn,\n'
        '                  child: SudokuBoard(\n'
        '                    puzzle: puzzle,\n'
        '                    board: snapshot.board,\n'
        '                    selectedIndex: _selectedIndex,\n'
        '                    errorIndex: _feedbackCell,\n'
        '                    localMoveIndexes: _localMoveIndexes,\n'
        '                    opponentMoveIndexes: _opponentMoveIndexes,\n'
        '                    enabled: !snapshot.isFinished && snapshot.isLocalTurn,\n'
        '                    onCellTap: _selectCell,\n'
        '                  ),\n'
        '                ),\n'
        '              );\n'
    )
    replace_once(ONLINE, old_board, new_board)


def patch_localizations() -> None:
    marker = "    'samurai_sudoku': 'Samurai Sudoku',\n"
    additions = (
        "    'duel_variant_classic': 'Classic Sudoku',\n"
        "    'choose_duel_variant': 'Choose game type',\n"
        "    'same_variant_match':\n"
        "        'You will only be matched with the same game type.',\n"
    )
    replace_once(DART_STRINGS, marker, marker + additions)

    xml_marker = '    <string name="samurai_sudoku">Samurai Sudoku</string>\n'
    xml_additions = (
        '    <string name="duel_variant_classic">Classic Sudoku</string>\n'
        '    <string name="choose_duel_variant">Choose game type</string>\n'
        '    <string name="same_variant_match">You will only be matched with the same game type.</string>\n'
    )
    replace_once(ANDROID_STRINGS, xml_marker, xml_marker + xml_additions)

    catalog = json.loads(IOS_CATALOG.read_text(encoding='utf-8'))
    strings = catalog['strings']
    values = {
        'duel_variant_classic': ('Classic Sudoku', 'Klasik Sudoku'),
        'choose_duel_variant': ('Choose game type', 'Oyun türünü seç'),
        'same_variant_match': (
            'You will only be matched with the same game type.',
            'Yalnızca aynı oyun türünü seçen oyuncularla eşleşirsiniz.',
        ),
    }
    for key, (english, turkish) in values.items():
        if key in strings:
            raise RuntimeError(f'Localization key already exists: {key}')
        strings[key] = {
            'localizations': {
                'en': {'stringUnit': {'state': 'translated', 'value': english}},
                'tr': {'stringUnit': {'state': 'translated', 'value': turkish}},
            }
        }
    IOS_CATALOG.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + '\n',
        encoding='utf-8',
    )


def main() -> None:
    patch_models()
    patch_social()
    patch_matchmaking()
    patch_online()
    patch_localizations()
    print('Online Samurai Flutter client integrated.')


if __name__ == '__main__':
    main()
