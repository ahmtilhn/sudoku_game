#!/usr/bin/env python3
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
path = ROOT / 'lib/features/career/career_hub_screen.dart'
text = path.read_text(encoding='utf-8')

practice = r'''  Widget _practiceTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 650;
        final maxWidth = constraints.maxWidth >= 840 ? 760.0 : 680.0;
        final columns = constraints.maxWidth >= 560 ? 2 : 1;
        final rows = compact ? 2 : 3;
        final pageSize = columns * rows;
        final options = <Widget>[
          _PracticeCard(
            icon: Icons.today_rounded,
            title: context.tr('daily_sudoku'),
            subtitle: _practiceSubtitle(
              context,
              progress: widget.store.progressFor(
                PuzzleCatalog.dailyPuzzle(DateTime.now()).id,
              ),
              fallback: context.tr('daily_subtitle'),
            ),
            accent: const Color(0xFF29D398),
            loading: _generatingDaily,
            onTap: _busy ? null : _openDaily,
          ),
          _PracticeCard(
            icon: Icons.dashboard_customize_rounded,
            title: context.tr('samurai_sudoku'),
            subtitle: context.tr('samurai_subtitle'),
            accent: const Color(0xFFE8794F),
            loading: _generatingSamurai,
            onTap: _busy ? null : _openSamurai,
          ),
          for (final difficulty in SudokuDifficulty.values)
            _PracticeCard(
              icon: Icons.grid_4x4_rounded,
              title: context.strings.difficultyLabel(difficulty),
              subtitle: _practiceSubtitle(
                context,
                progress: widget.store.progressFor(
                  'practice-${difficulty.name}',
                ),
                fallback: context.tr('random_clue_count', <Object>[
                  PuzzleCatalog.targetClueCount(difficulty),
                ]),
              ),
              accent: _difficultyAccent(difficulty),
              loading: _generatingPractice == difficulty,
              onTap: _busy ? null : () => _openPractice(difficulty),
            ),
        ];
        final pageCount = (options.length / pageSize).ceil();
        final page = _practicePage.clamp(0, pageCount - 1);
        final startIndex = page * pageSize;
        final endIndex = (startIndex + pageSize).clamp(0, options.length);
        final visible = options.sublist(startIndex, endIndex);

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                constraints.maxWidth < 360 ? 10 : 16,
                compact ? 5 : 10,
                constraints.maxWidth < 360 ? 10 : 16,
                compact ? 6 : 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!compact) ...[
                    _HeroPanel(
                      title: context.tr('practice'),
                      subtitle: context.tr('career_random_intro'),
                      icon: DuelAsset.grid,
                    ),
                    const SizedBox(height: 8),
                  ],
                  Expanded(
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: visible.length,
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: columns == 1
                                ? compact
                                      ? 3.25
                                      : 2.8
                                : compact
                                ? 1.65
                                : 1.45,
                          ),
                      itemBuilder: (context, index) => visible[index],
                    ),
                  ),
                  if (pageCount > 1)
                    _CareerPager(
                      page: page,
                      pageCount: pageCount,
                      onPrevious: page > 0
                          ? () => setState(() => _practicePage = page - 1)
                          : null,
                      onNext: page < pageCount - 1
                          ? () => setState(() => _practicePage = page + 1)
                          : null,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
'''

pattern = r"  Widget _practiceTab\(\) \{.*?\n  \}\n\n  String _practiceSubtitle"
text, count = re.subn(
    pattern,
    practice + '\n  String _practiceSubtitle',
    text,
    count=1,
    flags=re.S,
)
if count != 1:
    raise SystemExit(f'career practice replacement count: {count}')

helpers = r'''
class _CompactCareerSummary extends StatelessWidget {
  const _CompactCareerSummary({
    required this.completed,
    required this.total,
    required this.stars,
    required this.nextLevel,
    required this.busy,
    required this.onPlay,
  });

  final int completed;
  final int total;
  final int stars;
  final CareerLevel nextLevel;
  final bool busy;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$completed/$total  ·  ★ $stars',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FilledButton.tonalIcon(
              onPressed: busy ? null : onPlay,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text(
                context.tr('level_title', <Object>[
                  context.strings.difficultyLabel(nextLevel.difficulty),
                  nextLevel.number,
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CareerChapterBar extends StatelessWidget {
  const _CareerChapterBar({
    required this.chapter,
    required this.page,
    required this.pageCount,
    required this.onPreviousChapter,
    required this.onNextChapter,
    required this.onPreviousPage,
    required this.onNextPage,
  });

  final int chapter;
  final int page;
  final int pageCount;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: MaterialLocalizations.of(context).previousPageTooltip,
            onPressed: onPreviousChapter,
            icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).previousPageTooltip,
            onPressed: onPreviousPage,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Text(
              '${context.tr('career')} · $chapter   ${page + 1}/$pageCount',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).nextPageTooltip,
            onPressed: onNextPage,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          IconButton.filledTonal(
            tooltip: MaterialLocalizations.of(context).nextPageTooltip,
            onPressed: onNextChapter,
            icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _CareerPager extends StatelessWidget {
  const _CareerPager({
    required this.page,
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final int pageCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).previousPageTooltip,
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Text(
              '${page + 1} / $pageCount',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).nextPageTooltip,
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

'''
marker = 'class _CareerHeaderControls'
if text.count(marker) != 1:
    raise SystemExit('career helper marker mismatch')
text = text.replace(marker, helpers + marker, 1)
path.write_text(text, encoding='utf-8')
