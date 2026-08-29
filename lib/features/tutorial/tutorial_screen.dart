import 'package:flutter/material.dart';

import '../../data/local_progress_store.dart';
import '../../data/puzzle_catalog.dart';
import '../../localization/app_strings.dart';
import '../../widgets/in_page_header.dart';
import '../game/game_screen.dart';

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key, required this.store});

  final LocalProgressStore store;

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  int _ruleIndex = 0;

  @override
  Widget build(BuildContext context) {
    final rules = <_RuleData>[
      _RuleData(
        number: '1',
        title: context.tr('rule_rows_title'),
        description: context.tr('rule_rows_description'),
        icon: Icons.view_stream_outlined,
      ),
      _RuleData(
        number: '2',
        title: context.tr('rule_columns_title'),
        description: context.tr('rule_columns_description'),
        icon: Icons.view_column_outlined,
      ),
      _RuleData(
        number: '3',
        title: context.tr('rule_boxes_title'),
        description: context.tr('rule_boxes_description'),
        icon: Icons.grid_view_outlined,
      ),
    ];
    final rule = rules[_ruleIndex];
    final lastRule = _ruleIndex == rules.length - 1;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 650;
            final horizontal = constraints.maxWidth < 360 ? 12.0 : 16.0;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    compact ? 4 : 8,
                    horizontal,
                    compact ? 8 : 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InPageHeader(
                        title: context.tr('tutorial_title'),
                        padding: EdgeInsets.only(bottom: compact ? 4 : 10),
                      ),
                      _TutorialProgress(
                        current: _ruleIndex,
                        count: rules.length,
                        compact: compact,
                      ),
                      SizedBox(height: compact ? 8 : 14),
                      Expanded(
                        child: Center(
                          child: _RuleCard(
                            number: rule.number,
                            title: rule.title,
                            description: rule.description,
                            icon: rule.icon,
                            compact: compact,
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 8 : 14),
                      if (lastRule)
                        FilledButton.icon(
                          onPressed: _startTutorial,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(
                            context.tr('start_mini_tutorial'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      else
                        Row(
                          children: [
                            if (_ruleIndex > 0) ...[
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      setState(() => _ruleIndex--),
                                  icon: const Icon(Icons.chevron_left_rounded),
                                  label: Text(
                                    MaterialLocalizations.of(
                                      context,
                                    ).backButtonTooltip,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => setState(() => _ruleIndex++),
                                icon: const Icon(Icons.chevron_right_rounded),
                                label: Text(
                                  MaterialLocalizations.of(
                                    context,
                                  ).nextPageTooltip,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      if (lastRule && _ruleIndex > 0) ...[
                        const SizedBox(height: 6),
                        TextButton.icon(
                          onPressed: () => setState(() => _ruleIndex--),
                          icon: const Icon(Icons.chevron_left_rounded),
                          label: Text(
                            MaterialLocalizations.of(context).backButtonTooltip,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _startTutorial() async {
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GameScreen(
          puzzle: PuzzleCatalog.tutorialPuzzle,
          completionTitle: context.tr('tutorial_completed'),
          onCompleted:
              ({required seconds, required mistakes, required hints}) =>
                  widget.store.markTutorialComplete(),
        ),
      ),
    );
    if (mounted && completed == true) {
      Navigator.of(context).pop();
    }
  }
}

class _RuleData {
  const _RuleData({
    required this.number,
    required this.title,
    required this.description,
    required this.icon,
  });

  final String number;
  final String title;
  final String description;
  final IconData icon;
}

class _TutorialProgress extends StatelessWidget {
  const _TutorialProgress({
    required this.current,
    required this.count,
    required this.compact,
  });

  final int current;
  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(
        count,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: index == current ? (compact ? 24 : 30) : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: index == current
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.number,
    required this.title,
    required this.description,
    required this.icon,
    required this.compact,
  });

  final String number;
  final String title;
  final String description;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.all(compact ? 14 : 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: compact ? 25 : 30,
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  number,
                  style: TextStyle(
                    fontSize: compact ? 18 : 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              SizedBox(height: compact ? 10 : 16),
              Icon(icon, size: compact ? 30 : 38),
              SizedBox(height: compact ? 8 : 12),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: compact ? 18 : null,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: compact ? 6 : 10),
              Text(
                description,
                textAlign: TextAlign.center,
                maxLines: compact ? 4 : 6,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: compact ? 13 : null,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
