#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
path = ROOT / 'lib/features/game/game_screen.dart'
text = path.read_text(encoding='utf-8')

old = """            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 24),
              child: Center(
                child: SizedBox(
                  width: width,
                  child: Column(
                    children: [
                      if (!_sessionReady) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                      ],
                      InPageHeader(
                        title: context.strings.puzzleTitle(widget.puzzle),
                        actions: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: ValueListenableBuilder<int>(
                              valueListenable: _elapsedNotifier,
                              builder: (context, seconds, _) => Text(
                                formatDuration(seconds),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Chip(
                            avatar: const Icon(Icons.error_outline, size: 18),
                            label: Text(mistakeLabel),
                          ),
                          const SizedBox(width: 8),
                          Chip(
                            avatar: const Icon(
                              Icons.lightbulb_outline,
                              size: 18,
                            ),
                            label: Text(
                              context.tr('hints_count', <Object>[
                                availableHints ?? _hintsUsed,
                              ]),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            context.strings.difficultyLabel(
                              widget.puzzle.difficulty,
                            ),
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SudokuBoard(
                        puzzle: widget.puzzle,
                        board: _board,
                        selectedIndex: _selectedIndex,
                        notes: _notes,
                        errorIndex: _errorIndex,
                        hintedIndexes: _hintedIndexes,
                        enabled: controlsEnabled,
                        onCellTap: _selectCell,
                      ),
                    ],
                  ),
                ),
              ),
            );"""
new = """            final compact = constraints.maxHeight < 760;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                10,
                compact ? 3 : 6,
                10,
                compact ? 4 : 10,
              ),
              child: Center(
                child: SizedBox(
                  width: width,
                  height: constraints.maxHeight,
                  child: Column(
                    children: [
                      if (!_sessionReady) ...[
                        const LinearProgressIndicator(),
                        SizedBox(height: compact ? 3 : 6),
                      ],
                      InPageHeader(
                        title: context.strings.puzzleTitle(widget.puzzle),
                        padding: EdgeInsets.only(bottom: compact ? 3 : 6),
                        actions: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: ValueListenableBuilder<int>(
                              valueListenable: _elapsedNotifier,
                              builder: (context, seconds, _) => Text(
                                formatDuration(seconds),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                        height: compact ? 38 : 44,
                        child: Row(
                          children: [
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Chip(
                                  avatar: const Icon(
                                    Icons.error_outline,
                                    size: 18,
                                  ),
                                  label: Text(mistakeLabel),
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.center,
                                child: Chip(
                                  avatar: const Icon(
                                    Icons.lightbulb_outline,
                                    size: 18,
                                  ),
                                  label: Text(
                                    context.tr('hints_count', <Object>[
                                      availableHints ?? _hintsUsed,
                                    ]),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                context.strings.difficultyLabel(
                                  widget.puzzle.difficulty,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: compact ? 4 : 8),
                      Expanded(
                        child: Center(
                          child: SudokuBoard(
                            puzzle: widget.puzzle,
                            board: _board,
                            selectedIndex: _selectedIndex,
                            notes: _notes,
                            errorIndex: _errorIndex,
                            hintedIndexes: _hintedIndexes,
                            enabled: controlsEnabled,
                            onCellTap: _selectCell,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );"""

count = text.count(old)
if count != 1:
    raise SystemExit(f'game_screen: expected one scroll body, got {count}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
