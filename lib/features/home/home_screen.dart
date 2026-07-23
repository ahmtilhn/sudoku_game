import 'package:flutter/material.dart';

import '../../data/local_progress_store.dart';
import '../../widgets/menu_card.dart';
import '../career/career_screen.dart';
import '../daily/daily_screen.dart';
import '../duel/duel_screen.dart';
import '../settings/settings_screen.dart';
import '../tutorial/tutorial_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.store});

  final LocalProgressStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sudoku Duel'),
        actions: [
          IconButton(
            tooltip: 'Ayarlar',
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
              icon: Icons.route_outlined,
              title: 'Kariyer',
              subtitle: 'Başlangıçtan uzman seviyesine ilerle',
              trailing: Text('${store.completedLevelCount}/30', style: const TextStyle(fontWeight: FontWeight.w800)),
              onTap: () => _open(context, CareerScreen(store: store)),
            ),
            const SizedBox(height: 12),
            MenuCard(
              icon: Icons.sports_esports_outlined,
              title: 'Yerel Düello',
              subtitle: 'Aynı telefonda 10 saniyelik sıra savaşı',
              onTap: () => _open(context, const DuelScreen()),
            ),
            const SizedBox(height: 12),
            MenuCard(
              icon: Icons.today_outlined,
              title: 'Günlük Sudoku',
              subtitle: 'Her gün değişen tek bir sade bulmaca',
              onTap: () => _open(context, const DailyScreen()),
            ),
            const SizedBox(height: 12),
            MenuCard(
              icon: Icons.school_outlined,
              title: 'Nasıl oynanır?',
              subtitle: store.tutorialCompleted ? 'Eğitimi tekrar aç' : '4×4 mini tahta ile birkaç dakikada öğren',
              onTap: () => _open(context, TutorialScreen(store: store)),
            ),
            const SizedBox(height: 20),
            Text(
              'Online düello altyapısı sonraki fazda bu yerel düello motoruna bağlanacak.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
        gradient: LinearGradient(colors: [scheme.primaryContainer, scheme.secondaryContainer]),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            store.tutorialCompleted ? 'Bir tur Sudoku?' : 'Sudoku bilmek zorunda değilsin.',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 8),
          Text(
            store.tutorialCompleted
                ? 'Kaldığın yerden devam et veya yanındaki biriyle düello yap.'
                : 'Mini eğitimle kuralları öğren, sonra kariyere geç.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onPrimaryContainer),
          ),
        ],
      ),
    );
  }
}
