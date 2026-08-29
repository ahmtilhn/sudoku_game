#!/usr/bin/env python3
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
path = ROOT / 'lib/features/social/profile_hub_screen.dart'
text = path.read_text(encoding='utf-8')

build = r'''  @override
  Widget build(BuildContext context) {
    final tabs = _tabs(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      body: AppBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 700;
              final horizontal = constraints.maxWidth < 360 ? 10.0 : 16.0;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 740),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      compact ? 4 : 6,
                      horizontal,
                      compact ? 7 : 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        InPageHeader(
                          title: context.tr('profile'),
                          padding: EdgeInsets.only(bottom: compact ? 4 : 8),
                          actions: [
                            IconButton(
                              tooltip: context.tr('refresh'),
                              onPressed: _loading ? null : _load,
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                          ],
                        ),
                        if (_loading && _profile == null)
                          const Expanded(
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else ...[
                          if (_profile != null)
                            RankIdentitySummaryCard(
                              profile: _profile!,
                              onCustomize: _openCustomization,
                            ),
                          if (_error != null) ...[
                            SizedBox(height: compact ? 5 : 8),
                            _ProfileNotice(message: _error!, onRetry: _load),
                          ],
                          SizedBox(height: compact ? 6 : 10),
                          Expanded(
                            child: _ProfileActionGrid(
                              tabs: tabs,
                              selected: _selectedTab,
                              onSelected: (value) =>
                                  setState(() => _selectedTab = value),
                            ),
                          ),
                          if (_profile != null && !compact) ...[
                            const SizedBox(height: 8),
                            _IdentityPolicyNote(profile: _profile!),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
'''
pattern = r"  @override\n  Widget build\(BuildContext context\) \{.*?\n  \}\n\n  List<_ProfileTabData> _tabs"
text, count = re.subn(
    pattern,
    build + '\n  List<_ProfileTabData> _tabs',
    text,
    count=1,
    flags=re.S,
)
if count != 1:
    raise SystemExit(f'profile hub build replacement count: {count}')

grid_and_card = r'''class _ProfileActionGrid extends StatelessWidget {
  const _ProfileActionGrid({
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });

  final List<_ProfileTabData> tabs;
  final _ProfileTab selected;
  final ValueChanged<_ProfileTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: tabs.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: constraints.maxHeight < 250 ? 1.8 : 1.25,
          ),
          itemBuilder: (context, index) {
            final tab = tabs[index];
            return _ProfileActionCard(
              tab: tab,
              selected: selected == tab.tab,
              onSelected: () => onSelected(tab.tab),
            );
          },
        );
      },
    );
  }
}

class _ProfileActionCard extends StatelessWidget {
  const _ProfileActionCard({
    required this.tab,
    required this.selected,
    required this.onSelected,
  });

  final _ProfileTabData tab;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 220;
        final fillArtwork =
            tab.tab == _ProfileTab.customize || tab.tab == _ProfileTab.emotes;
        final artworkSize = narrow ? 34.0 : 42.0;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              onSelected();
              tab.onOpen();
            },
            borderRadius: BorderRadius.circular(15),
            child: Ink(
              padding: EdgeInsets.all(narrow ? 7 : 10),
              decoration: BoxDecoration(
                color: tab.accent.withValues(alpha: selected ? .10 : .06),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: tab.accent.withValues(alpha: selected ? .36 : .16),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox.square(
                    dimension: artworkSize,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: DuelAssetIcon(
                        tab.asset,
                        size: artworkSize,
                        fit: fillArtwork ? BoxFit.cover : BoxFit.contain,
                      ),
                    ),
                  ),
                  SizedBox(height: narrow ? 4 : 7),
                  Text(
                    tab.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: narrow ? 11 : 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (!narrow) ...[
                    const SizedBox(height: 2),
                    Text(
                      tab.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .55),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    tab.metric,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: tab.accent,
                      fontSize: narrow ? 9 : 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
'''
pattern = r"class _ProfileActionGrid extends StatelessWidget \{.*\Z"
text, count = re.subn(pattern, grid_and_card, text, count=1, flags=re.S)
if count != 1:
    raise SystemExit(f'profile hub action grid replacement count: {count}')

path.write_text(text, encoding='utf-8')
