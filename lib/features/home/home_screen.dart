import 'package:flutter/material.dart';

import '../../data/local_progress_store.dart';
import '../../localization/app_strings.dart';
import '../../widgets/menu_card.dart';
import '../career/career_screen.dart';
import '../daily/daily_screen.dart';
import '../duel/matchmaking_screen.dart';
import '../settings/settings_screen.dart';
import '../tutorial/tutorial_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.store});

  final LocalProgressStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('app_name')),
        actions: [
          AnimatedBuilder(
            animation: store,
            builder: (context, _) => Row(
              children: [
                Chip(
                  avatar: const Icon(Icons.lightbulb_outline, size: 18),
                  label: Text('${store.hints}'),
                ),
                const SizedBox(width: 4),
                Chip(
                  avatar: const Icon(Icons.monetization_on_outlined, size: 18),
                  label: Text('${store.coins}'),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: context.tr('settings'),
            onPressed: () => _open(context, SettingsScreen(store: store)),
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _WelcomePanel(store: store),
            const SizedBox(height: 18),
            MenuCard(
              icon: Icons.casino_outlined,
              title: context.tr('career'),
              subtitle: context.tr('career_random_subtitle'),
              trailing: Text(
                context.tr('coins_count', <Object>[store.coins]),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              onTap: () => _open(context, CareerScreen(store: store)),
            ),
            const SizedBox(height: 12),
            MenuCard(
              icon: Icons.public,
              title: context.tr('online_duel'),
              subtitle: context.tr('online_duel_subtitle'),
              onTap: () => _open(context, const MatchmakingScreen()),
            ),
            const SizedBox(height: 12),
            MenuCard(
              icon: Icons.today_outlined,
              title: context.tr('daily_sudoku'),
              subtitle: context.tr('daily_subtitle'),
              onTap: () => _open(context, DailyScreen(store: store)),
            ),
            const SizedBox(height: 12),
            MenuCard(
              icon: Icons.school_outlined,
              title: context.tr('how_to_play'),
              subtitle: store.tutorialCompleted
                  ? context.tr('tutorial_repeat')
                  : context.tr('tutorial_new'),
              onTap: () => _open(context, TutorialScreen(store: store)),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel({required this.store});

  final LocalProgressStore store;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primaryContainer, scheme.secondaryContainer],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            store.tutorialCompleted
                ? context.tr('welcome_returning_title')
                : context.tr('welcome_new_title'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: scheme.onPrimaryContainer,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            store.tutorialCompleted
                ? context.tr('welcome_returning_body')
                : context.tr('welcome_new_body'),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: scheme.onPrimaryContainer,
                ),
          ),
        ],
      ),
    );
  }
}
