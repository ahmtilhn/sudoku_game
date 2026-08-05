#!/usr/bin/env python3
"""Wire persisted Samurai sessions into the game screen and home resume card."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCREEN = ROOT / "lib/features/game/samurai_game_screen.dart"
HOME = ROOT / "lib/features/home/ux_root_screen.dart"


def replace_once(path: Path, old: str, new: str) -> None:
    source = path.read_text(encoding="utf-8")
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one marker in {path}: {old!r}; found {count}")
    path.write_text(source.replace(old, new, 1), encoding="utf-8")


def patch_screen() -> None:
    replace_once(
        SCREEN,
        "import '../../data/local_progress_store.dart';\n",
        "import '../../data/local_progress_store.dart';\n"
        "import '../../data/samurai_game_session_store.dart';\n",
    )
    replace_once(
        SCREEN,
        "    this.onCompleted,\n    this.mistakeLimit = 3,\n",
        "    this.onCompleted,\n"
        "    this.initialSession,\n"
        "    this.mistakeLimit = 3,\n",
    )
    replace_once(
        SCREEN,
        "  final SamuraiGameCompleted? onCompleted;\n  final int? mistakeLimit;\n",
        "  final SamuraiGameCompleted? onCompleted;\n"
        "  final SamuraiGameSession? initialSession;\n"
        "  final int? mistakeLimit;\n",
    )
    replace_once(
        SCREEN,
        "  final Set<int> _hintedIndexes = <int>{};\n\n  late List<int> _board;\n  Timer? _clockTimer;\n",
        "  final Set<int> _hintedIndexes = <int>{};\n"
        "  final SamuraiGameSessionStore _sessionStore =\n"
        "      SamuraiGameSessionStore.instance;\n\n"
        "  late List<int> _board;\n"
        "  Timer? _clockTimer;\n"
        "  Timer? _saveTimer;\n",
    )
    replace_once(
        SCREEN,
        "  int _elapsedSeconds = 0;\n",
        "  int _elapsedSeconds = 0;\n  int _elapsedOffsetSeconds = 0;\n",
    )
    replace_once(
        SCREEN,
        "    _board = List<int>.from(widget.puzzle.puzzle);\n    _startClock();\n",
        "    final restored = widget.initialSession;\n"
        "    if (restored != null && restored.puzzle.id == widget.puzzle.id) {\n"
        "      _board = List<int>.from(restored.board);\n"
        "      _notes.addAll(<int, Set<int>>{\n"
        "        for (final entry in restored.notes.entries)\n"
        "          entry.key: Set<int>.from(entry.value),\n"
        "      });\n"
        "      _hintedIndexes.addAll(restored.hintedIndexes);\n"
        "      _elapsedSeconds = restored.elapsedSeconds;\n"
        "      _elapsedOffsetSeconds = restored.elapsedSeconds;\n"
        "      _mistakes = restored.mistakes;\n"
        "      _hintsUsed = restored.hintsUsed;\n"
        "      _notesMode = restored.notesMode;\n"
        "    } else {\n"
        "      _board = List<int>.from(widget.puzzle.puzzle);\n"
        "    }\n"
        "    _startClock();\n"
        "    _schedulePersist();\n",
    )
    replace_once(
        SCREEN,
        "    } else {\n      _pauseClock();\n    }\n",
        "    } else {\n"
        "      _pauseClock();\n"
        "      unawaited(_persistNow());\n"
        "    }\n",
    )
    replace_once(
        SCREEN,
        "    _pauseClock();\n    super.dispose();\n",
        "    _pauseClock();\n"
        "    _saveTimer?.cancel();\n"
        "    unawaited(_persistNow());\n"
        "    super.dispose();\n",
    )
    replace_once(
        SCREEN,
        "      final seconds = _stopwatch.elapsed.inSeconds;\n",
        "      final seconds =\n"
        "          _elapsedOffsetSeconds + _stopwatch.elapsed.inSeconds;\n",
    )
    replace_once(
        SCREEN,
        "  void _selectCell(int index) {\n",
        "  void _schedulePersist() {\n"
        "    if (_completed || _lost) return;\n"
        "    _saveTimer?.cancel();\n"
        "    _saveTimer = Timer(\n"
        "      const Duration(milliseconds: 250),\n"
        "      () => unawaited(_persistNow()),\n"
        "    );\n"
        "  }\n\n"
        "  Future<void> _persistNow() async {\n"
        "    if (_completed || _lost) return;\n"
        "    await _sessionStore.save(\n"
        "      SamuraiGameSession(\n"
        "        puzzle: widget.puzzle,\n"
        "        board: List<int>.from(_board),\n"
        "        notes: <int, Set<int>>{\n"
        "          for (final entry in _notes.entries)\n"
        "            entry.key: Set<int>.from(entry.value),\n"
        "        },\n"
        "        hintedIndexes: Set<int>.from(_hintedIndexes),\n"
        "        elapsedSeconds: _elapsedSeconds,\n"
        "        mistakes: _mistakes,\n"
        "        hintsUsed: _hintsUsed,\n"
        "        notesMode: _notesMode,\n"
        "        updatedAt: DateTime.now().toUtc(),\n"
        "      ),\n"
        "    );\n"
        "  }\n\n"
        "  void _selectCell(int index) {\n",
    )
    replace_once(
        SCREEN,
        "        if (values.isEmpty) _notes.remove(index);\n      });\n      return;\n",
        "        if (values.isEmpty) _notes.remove(index);\n"
        "      });\n"
        "      _schedulePersist();\n"
        "      return;\n",
    )
    replace_once(
        SCREEN,
        "      setState(() {\n        _mistakes++;\n        _errorIndex = index;\n      });\n      if (widget.mistakeLimit != null &&\n",
        "      setState(() {\n"
        "        _mistakes++;\n"
        "        _errorIndex = index;\n"
        "      });\n"
        "      _schedulePersist();\n"
        "      if (widget.mistakeLimit != null &&\n",
    )
    replace_once(
        SCREEN,
        "      _errorIndex = null;\n    });\n    unawaited(_checkCompletion());\n",
        "      _errorIndex = null;\n"
        "    });\n"
        "    _schedulePersist();\n"
        "    unawaited(_checkCompletion());\n",
    )
    replace_once(
        SCREEN,
        "      _notes.remove(index);\n      _errorIndex = null;\n    });\n  }\n\n  void _undo()",
        "      _notes.remove(index);\n"
        "      _errorIndex = null;\n"
        "    });\n"
        "    _schedulePersist();\n"
        "  }\n\n"
        "  void _undo()",
    )
    replace_once(
        SCREEN,
        "      _errorIndex = null;\n    });\n  }\n\n  void _toggleNotes()",
        "      _errorIndex = null;\n"
        "    });\n"
        "    _schedulePersist();\n"
        "  }\n\n"
        "  void _toggleNotes()",
    )
    replace_once(
        SCREEN,
        "    setState(() => _notesMode = !_notesMode);\n",
        "    setState(() => _notesMode = !_notesMode);\n"
        "    _schedulePersist();\n",
    )
    replace_once(
        SCREEN,
        "        _hintsUsed++;\n      });\n      await _checkCompletion();\n",
        "        _hintsUsed++;\n"
        "      });\n"
        "      _schedulePersist();\n"
        "      await _checkCompletion();\n",
    )
    replace_once(
        SCREEN,
        "    setState(() {\n      _paused = true;\n      _dialogVisible = true;\n    });\n\n    final action = await",
        "    setState(() {\n"
        "      _paused = true;\n"
        "      _dialogVisible = true;\n"
        "    });\n"
        "    await _persistNow();\n\n"
        "    final action = await",
    )
    replace_once(
        SCREEN,
        "    setState(() {\n      _lost = true;\n      _dialogVisible = true;\n    });\n\n    final action = await",
        "    setState(() {\n"
        "      _lost = true;\n"
        "      _dialogVisible = true;\n"
        "    });\n"
        "    await _sessionStore.clear();\n\n"
        "    final action = await",
    )
    replace_once(
        SCREEN,
        "    _pauseClock();\n    setState(() => _completed = true);\n    await widget.onCompleted?.call(\n",
        "    _pauseClock();\n"
        "    setState(() => _completed = true);\n"
        "    await _sessionStore.clear();\n"
        "    await widget.onCompleted?.call(\n",
    )
    replace_once(
        SCREEN,
        "    _stopwatch.reset();\n    setState(() {\n",
        "    _stopwatch.reset();\n"
        "    _elapsedOffsetSeconds = 0;\n"
        "    setState(() {\n",
    )
    replace_once(
        SCREEN,
        "    _startClock();\n  }\n\n  void _exitToMenu()",
        "    _startClock();\n"
        "    _schedulePersist();\n"
        "  }\n\n"
        "  void _exitToMenu()",
    )
    replace_once(
        SCREEN,
        "    _pauseClock();\n    setState(() => _allowExit = true);\n    Navigator.of(context).pop(SamuraiGameExit.menu);\n",
        "    _pauseClock();\n"
        "    unawaited(_persistNow());\n"
        "    setState(() => _allowExit = true);\n"
        "    Navigator.of(context).pop(SamuraiGameExit.menu);\n",
    )


def patch_home() -> None:
    replace_once(
        HOME,
        "import '../../data/local_progress_store.dart';\n",
        "import '../../data/local_progress_store.dart';\n"
        "import '../../data/samurai_game_session_store.dart';\n",
    )
    replace_once(
        HOME,
        "import '../game/enhanced_game_screen.dart';\n",
        "import '../game/enhanced_game_screen.dart';\n"
        "import '../game/samurai_game_screen.dart';\n",
    )
    replace_once(
        HOME,
        "  final GameSessionStore _legacySessions = GameSessionStore.instance;\n\n"
        "  PlayerProfilePreferences? _profile;\n",
        "  final GameSessionStore _legacySessions = GameSessionStore.instance;\n"
        "  final SamuraiGameSessionStore _samuraiSessions =\n"
        "      SamuraiGameSessionStore.instance;\n\n"
        "  PlayerProfilePreferences? _profile;\n",
    )
    replace_once(
        HOME,
        "  ActiveGameSessionMetadata? _legacySession;\n",
        "  ActiveGameSessionMetadata? _legacySession;\n"
        "  SamuraiGameSession? _samuraiSession;\n",
    )
    replace_once(
        HOME,
        "    _legacySessions.activeSession.addListener(_legacySessionChanged);\n",
        "    _legacySessions.activeSession.addListener(_legacySessionChanged);\n"
        "    _samuraiSessions.activeSession.addListener(_samuraiSessionChanged);\n",
    )
    replace_once(
        HOME,
        "    unawaited(_legacySessions.latest());\n",
        "    unawaited(_legacySessions.latest());\n"
        "    unawaited(_samuraiSessions.initialize());\n",
    )
    replace_once(
        HOME,
        "    _legacySessions.activeSession.removeListener(_legacySessionChanged);\n",
        "    _legacySessions.activeSession.removeListener(_legacySessionChanged);\n"
        "    _samuraiSessions.activeSession.removeListener(_samuraiSessionChanged);\n",
    )
    replace_once(
        HOME,
        "  Future<void> _loadProfile() async {\n",
        "  void _samuraiSessionChanged() {\n"
        "    if (mounted) {\n"
        "      setState(() => _samuraiSession = _samuraiSessions.activeSession.value);\n"
        "    }\n"
        "  }\n\n"
        "  Future<void> _loadProfile() async {\n",
    )
    replace_once(
        HOME,
        "      _legacySessions.latest().then((_) {}),\n",
        "      _legacySessions.latest().then((_) {}),\n"
        "      _samuraiSessions.initialize(),\n",
    )
    replace_once(
        HOME,
        "      if (session != null) {\n        await _resumeUxSession(session);\n      } else if (_legacySession != null) {\n",
        "      if (session != null) {\n"
        "        await _resumeUxSession(session);\n"
        "      } else if (_samuraiSession != null) {\n"
        "        await _resumeSamurai(_samuraiSession!);\n"
        "      } else if (_legacySession != null) {\n",
    )
    replace_once(
        HOME,
        "  Future<void> _resumeLegacy(ActiveGameSessionMetadata metadata) async {\n",
        "  Future<void> _resumeSamurai(SamuraiGameSession session) async {\n"
        "    await Navigator.of(context).push<SamuraiGameExit>(\n"
        "      MaterialPageRoute(\n"
        "        builder: (_) => SamuraiGameScreen(\n"
        "          puzzle: session.puzzle,\n"
        "          initialSession: session,\n"
        "          store: widget.store,\n"
        "          onCompleted:\n"
        "              ({\n"
        "                required seconds,\n"
        "                required mistakes,\n"
        "                required hints,\n"
        "              }) async {\n"
        "                await widget.store.recordResult(\n"
        "                  puzzleId:\n"
        "                      'practice-samurai-${session.puzzle.difficulty.name}',\n"
        "                  seconds: seconds,\n"
        "                  mistakes: mistakes,\n"
        "                  hints: hints,\n"
        "                );\n"
        "                await _claimEligibleAchievements();\n"
        "              },\n"
        "        ),\n"
        "      ),\n"
        "    );\n"
        "  }\n\n"
        "  Future<void> _resumeLegacy(ActiveGameSessionMetadata metadata) async {\n",
    )
    replace_once(
        HOME,
        "    final legacyLevel = _legacySession == null\n",
        "    final samurai = _samuraiSession;\n"
        "    final legacyLevel = _legacySession == null\n",
    )
    replace_once(
        HOME,
        "                        if (resume != null || legacyLevel != null) ...[\n"
        "                          _ResumeCard(\n"
        "                            title: resume == null\n"
        "                                ? context.tr('level_title', <Object>[\n"
        "                                    context.strings.difficultyLabel(\n"
        "                                      legacyLevel!.difficulty,\n"
        "                                    ),\n"
        "                                    legacyLevel.number,\n"
        "                                  ])\n"
        "                                : _sessionTitle(context, resume),\n"
        "                            elapsed:\n"
        "                                resume?.elapsedSeconds ??\n"
        "                                _legacySession!.elapsedSeconds,\n",
        "                        if (resume != null ||\n"
        "                            samurai != null ||\n"
        "                            legacyLevel != null) ...[\n"
        "                          _ResumeCard(\n"
        "                            title: resume != null\n"
        "                                ? _sessionTitle(context, resume)\n"
        "                                : samurai != null\n"
        "                                    ? '${context.tr('samurai_sudoku')} · ${context.strings.difficultyLabel(samurai.puzzle.difficulty)}'\n"
        "                                    : context.tr('level_title', <Object>[\n"
        "                                        context.strings.difficultyLabel(\n"
        "                                          legacyLevel!.difficulty,\n"
        "                                        ),\n"
        "                                        legacyLevel.number,\n"
        "                                      ]),\n"
        "                            elapsed: resume?.elapsedSeconds ??\n"
        "                                samurai?.elapsedSeconds ??\n"
        "                                _legacySession!.elapsedSeconds,\n",
    )


def main() -> None:
    patch_screen()
    patch_home()
    print("Samurai resume flow integrated.")


if __name__ == "__main__":
    main()
