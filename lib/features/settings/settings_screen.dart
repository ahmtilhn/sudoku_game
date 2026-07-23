import 'package:flutter/material.dart';

import '../../data/local_progress_store.dart';
import '../../localization/app_strings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store});
  final LocalProgressStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings'))),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Text(
              context.tr('appearance'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<ThemeMode>(
<<<<<<< HEAD
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('Sistem'),
                          icon: Icon(Icons.settings_brightness),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('Açık'),
                          icon: Icon(Icons.light_mode_outlined),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('Koyu'),
                          icon: Icon(Icons.dark_mode_outlined),
=======
                      segments: [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text(context.tr('system')),
                          icon: const Icon(Icons.settings_brightness),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text(context.tr('light')),
                          icon: const Icon(Icons.light_mode_outlined),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text(context.tr('dark')),
                          icon: const Icon(Icons.dark_mode_outlined),
>>>>>>> 8fe6ccd91d5db3ce3d8e23617e404a1b183eb2fe
                        ),
                      ],
                      selected: <ThemeMode>{store.themeMode},
                      onSelectionChanged: (values) =>
                          store.setThemeMode(values.first),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: store.highContrast,
                      onChanged: store.setHighContrast,
<<<<<<< HEAD
                      title: const Text('Yüksek kontrast'),
                      subtitle: const Text(
                        'Tahta ve metin ayrımını güçlendirir.',
=======
                      title: Text(context.tr('high_contrast')),
                      subtitle: Text(
                        context.tr('high_contrast_subtitle'),
>>>>>>> 8fe6ccd91d5db3ce3d8e23617e404a1b183eb2fe
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              context.tr('data'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.delete_outline),
<<<<<<< HEAD
                title: const Text('Kariyer ilerlemesini temizle'),
                subtitle: Text(
                  '${store.completedLevelCount} tamamlanan seviye',
=======
                title: Text(context.tr('clear_career_progress')),
                subtitle: Text(
                  context.tr(
                    'completed_levels',
                    <Object>[store.completedLevelCount],
                  ),
>>>>>>> 8fe6ccd91d5db3ce3d8e23617e404a1b183eb2fe
                ),
                onTap: () => _confirmClear(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
<<<<<<< HEAD
        title: const Text('İlerleme temizlensin mi?'),
        content: const Text(
          'Tamamlanan kariyer seviyeleri ve rekorlar kaldırılacak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Temizle'),
=======
        title: Text(context.tr('clear_progress_title')),
        content: Text(context.tr('clear_progress_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.tr('clear')),
>>>>>>> 8fe6ccd91d5db3ce3d8e23617e404a1b183eb2fe
          ),
        ],
      ),
    );
    if (approved == true) await store.clearProgress();
  }
}
