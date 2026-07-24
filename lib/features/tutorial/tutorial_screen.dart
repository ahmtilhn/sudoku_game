import 'package:flutter/material.dart';

import '../../data/local_progress_store.dart';
import '../../data/puzzle_catalog.dart';
import '../../localization/app_strings.dart';
import '../game/game_screen.dart';

class TutorialScreen extends StatelessWidget {
  const TutorialScreen({super.key, required this.store});
  final LocalProgressStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('tutorial_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _RuleCard(
            number: '1',
            title: context.tr('rule_rows_title'),
            description: context.tr('rule_rows_description'),
            icon: Icons.view_stream_outlined,
          ),
          const SizedBox(height: 12),
          _RuleCard(
            number: '2',
            title: context.tr('rule_columns_title'),
            description: context.tr('rule_columns_description'),
            icon: Icons.view_column_outlined,
          ),
          const SizedBox(height: 12),
          _RuleCard(
            number: '3',
            title: context.tr('rule_boxes_title'),
            description: context.tr('rule_boxes_description'),
            icon: Icons.grid_view_outlined,
          ),
          const SizedBox(height: 24),
          Text(
            context.tr('tutorial_ready'),
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () async {
              final completed = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => GameScreen(
                    puzzle: PuzzleCatalog.tutorialPuzzle,
                    completionTitle: context.tr('tutorial_completed'),
                    onCompleted:
                        ({
                          required seconds,
                          required mistakes,
                          required hints,
                        }) => store.markTutorialComplete(),
                  ),
                ),
              );
              if (context.mounted && completed == true) {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.play_arrow),
            label: Text(context.tr('start_mini_tutorial')),
          ),
        ],
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
  });

  final String number;
  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              child: Text(
                number,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(description),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
