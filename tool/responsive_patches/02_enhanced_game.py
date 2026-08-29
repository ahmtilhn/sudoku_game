#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
path = ROOT / 'lib/features/game/enhanced_game_screen.dart'
text = path.read_text(encoding='utf-8')

old = """              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  10,
                  compact ? 4 : 7,
                  10,
                  compact ? 12 : 22,
                ),
                child: Center(
                  child: SizedBox(
                    width: width,
                    child: Column(
                      children: [
                        if (!_ready) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: const LinearProgressIndicator(minHeight: 3),
                          ),
                          const SizedBox(height: 8),
                        ],
                        InPageHeader(
                          title: context.strings.puzzleTitle(widget.puzzle),
                          padding: EdgeInsets.only(bottom: compact ? 6 : 9),
                          actions: [
                            IconButton(
                              key: const ValueKey<String>('action-pause'),
                              tooltip: context.tr('pause'),
                              onPressed: enabled ? _showPauseSheet : null,
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(
                                  0xFF142738,
                                ).withValues(alpha: .88),
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.pause_rounded),
                            ),
                          ],
                        ),
                        ValueListenableBuilder<int>(
                          valueListenable: _elapsedNotifier,
                          builder: (context, seconds, _) => _SoloGameHud(
                            time: formatDuration(seconds),
                            mistakes: mistakes,
                            hints: '${widget.store.hints}',
                            difficulty: difficulty,
                            compact: compact,
                          ),
                        ),
                        SizedBox(height: compact ? 8 : 12),
                        _SoloBoardFrame(
                          enabled: enabled,
                          child: SudokuBoard(
                            puzzle: widget.puzzle,
                            board: _board,
                            selectedIndex: _selectedIndex,
                            notes: _notes,
                            errorIndex: _errorIndex,
                            hintedIndexes: _hintedIndexes,
                            enabled: enabled,
                            onCellTap: _selectCell,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );"""
new = """              return Padding(
                padding: EdgeInsets.fromLTRB(
                  10,
                  compact ? 3 : 7,
                  10,
                  compact ? 4 : 10,
                ),
                child: Center(
                  child: SizedBox(
                    width: width,
                    height: constraints.maxHeight,
                    child: Column(
                      children: [
                        if (!_ready) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: const LinearProgressIndicator(minHeight: 3),
                          ),
                          SizedBox(height: compact ? 3 : 6),
                        ],
                        InPageHeader(
                          title: context.strings.puzzleTitle(widget.puzzle),
                          padding: EdgeInsets.only(bottom: compact ? 4 : 7),
                          actions: [
                            IconButton(
                              key: const ValueKey<String>('action-pause'),
                              tooltip: context.tr('pause'),
                              onPressed: enabled ? _showPauseSheet : null,
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(
                                  0xFF142738,
                                ).withValues(alpha: .88),
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.pause_rounded),
                            ),
                          ],
                        ),
                        ValueListenableBuilder<int>(
                          valueListenable: _elapsedNotifier,
                          builder: (context, seconds, _) => _SoloGameHud(
                            time: formatDuration(seconds),
                            mistakes: mistakes,
                            hints: '${widget.store.hints}',
                            difficulty: difficulty,
                            compact: compact,
                          ),
                        ),
                        SizedBox(height: compact ? 5 : 9),
                        Expanded(
                          child: Center(
                            child: _SoloBoardFrame(
                              enabled: enabled,
                              child: SudokuBoard(
                                puzzle: widget.puzzle,
                                board: _board,
                                selectedIndex: _selectedIndex,
                                notes: _notes,
                                errorIndex: _errorIndex,
                                hintedIndexes: _hintedIndexes,
                                enabled: enabled,
                                onCellTap: _selectCell,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );"""

if text.count(old) != 1:
    raise SystemExit(f'enhanced_game: expected one scroll body, got {text.count(old)}')
text = text.replace(old, new, 1)
old_compact = 'final compact = constraints.maxHeight < 720;'
if text.count(old_compact) != 1:
    raise SystemExit('enhanced_game: compact marker mismatch')
text = text.replace(old_compact, 'final compact = constraints.maxHeight < 760;', 1)
path.write_text(text, encoding='utf-8')
