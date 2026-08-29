#!/usr/bin/env python3
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
path = ROOT / 'lib/features/career/career_hub_screen.dart'
text = path.read_text(encoding='utf-8')

field = 'bool _generatingSamurai = false;'
if text.count(field) != 1:
    raise SystemExit('career: state marker mismatch')
text = text.replace(
    field,
    field + '\n  int _careerPage = 0;\n  int _practicePage = 0;',
    1,
)

old_tabs = """child: TabBarView(
                  controller: _tabs,
                  children: [_careerTab(), _practiceTab()],
                ),"""
new_tabs = """child: TabBarView(
                  controller: _tabs,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [_careerTab(), _practiceTab()],
                ),"""
if text.count(old_tabs) != 1:
    raise SystemExit('career: tab view marker mismatch')
text = text.replace(old_tabs, new_tabs, 1)

method = r'''  Widget _careerTab() {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final variant = _careerVariant;
        final nextNumber = widget.store.nextCareerLevelNumberFor(variant);
        final nextLevel = CareerCatalog.levelAt(nextNumber);
        final chapterStart = (_chapter - 1) * _chapterSize + 1;
        final levels = List<CareerLevel>.generate(
          _chapterSize,
          (index) => CareerCatalog.levelAt(chapterStart + index),
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 650;
            final veryCompact = constraints.maxHeight < 440;
            final maxWidth = constraints.maxWidth >= 840 ? 760.0 : 680.0;
            final columns = constraints.maxWidth >= 620 ? 3 : 2;
            final rows = constraints.maxWidth >= 620 && !compact ? 2 : 1;
            final pageSize = columns * rows;
            final pageCount = (levels.length / pageSize).ceil();
            final page = _careerPage.clamp(0, pageCount - 1);
            final startIndex = page * pageSize;
            final endIndex = (startIndex + pageSize).clamp(0, levels.length);
            final visibleLevels = levels.sublist(startIndex, endIndex);
            final completed = widget.store.completedCareerLevelCountFor(
              variant,
            );
            final designedCompleted = completed
                .clamp(0, CareerCatalog.designedLevelCount)
                .toInt();
            final starsThrough = nextNumber > CareerCatalog.designedLevelCount
                ? nextNumber - 1
                : CareerCatalog.designedLevelCount;
            final totalStars = CareerCatalog.levelsThrough(starsThrough)
                .fold<int>(
                  0,
                  (total, level) =>
                      total +
                      (widget.store
                              .progressForCareerLevel(
                                level.number,
                                variant: variant,
                              )
                              ?.stars ??
                          0),
                );

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
                      if (!compact)
                        _CareerProgressPanel(
                          completed: designedCompleted,
                          total: CareerCatalog.designedLevelCount,
                          stars: totalStars,
                          totalCompleted: completed,
                          variant: variant,
                          nextLevel: nextLevel,
                        )
                      else
                        _CompactCareerSummary(
                          completed: designedCompleted,
                          total: CareerCatalog.designedLevelCount,
                          stars: totalStars,
                          nextLevel: nextLevel,
                          busy: _busy,
                          onPlay: () => _openCareer(nextLevel),
                        ),
                      if (!veryCompact) ...[
                        SizedBox(height: compact ? 5 : 10),
                        _NextLevelCard(
                          level: nextLevel,
                          progress: widget.store.progressForCareerLevel(
                            nextLevel.number,
                            variant: variant,
                          ),
                          variant: variant,
                          loading: _generatingLevel == nextLevel.number,
                          onTap: _busy ? null : () => _openCareer(nextLevel),
                        ),
                      ],
                      SizedBox(height: compact ? 4 : 8),
                      _CareerChapterBar(
                        chapter: _chapter,
                        page: page,
                        pageCount: pageCount,
                        onPreviousChapter: _chapter <= 1 || _busy
                            ? null
                            : () => setState(() {
                                _chapter--;
                                _careerPage = 0;
                              }),
                        onNextChapter: _busy
                            ? null
                            : () => setState(() {
                                _chapter++;
                                _careerPage = 0;
                              }),
                        onPreviousPage: page > 0
                            ? () => setState(() => _careerPage = page - 1)
                            : null,
                        onNextPage: page < pageCount - 1
                            ? () => setState(() => _careerPage = page + 1)
                            : null,
                      ),
                      SizedBox(height: compact ? 4 : 7),
                      Expanded(
                        child: GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.zero,
                          itemCount: visibleLevels.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: compact ? 1.0 : .92,
                              ),
                          itemBuilder: (context, index) {
                            final level = visibleLevels[index];
                            final unlocked = widget.store
                                .isCareerLevelUnlocked(
                                  level.number,
                                  variant: variant,
                                );
                            return _LevelCard(
                              level: level,
                              progress: widget.store.progressForCareerLevel(
                                level.number,
                                variant: variant,
                              ),
                              unlocked: unlocked,
                              current: level.number == nextNumber,
                              loading: _generatingLevel == level.number,
                              onTap: unlocked && !_busy
                                  ? () => _openCareer(level)
                                  : null,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
'''
pattern = r"  Widget _careerTab\(\) \{.*?\n  \}\n\n  Widget _practiceTab\(\)"
updated, count = re.subn(pattern, method + '\n  Widget _practiceTab()', text, count=1, flags=re.S)
if count != 1:
    raise SystemExit(f'career: method replacement count {count}')
path.write_text(updated, encoding='utf-8')
