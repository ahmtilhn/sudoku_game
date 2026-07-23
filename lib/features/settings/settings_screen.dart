import 'package:flutter/material.dart';

import '../../data/local_progress_store.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store});
  final LocalProgressStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Text('Görünüm', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(value: ThemeMode.system, label: Text('Sistem'), icon: Icon(Icons.settings_brightness)),
                        ButtonSegment(value: ThemeMode.light, label: Text('Açık'), icon: Icon(Icons.light_mode_outlined)),
                        ButtonSegment(value: ThemeMode.dark, label: Text('Koyu'), icon: Icon(Icons.dark_mode_outlined)),
                      ],
                      selected: <ThemeMode>{store.themeMode},
                      onSelectionChanged: (values) => store.setThemeMode(values.first),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: store.highContrast,
                      onChanged: store.setHighContrast,
                      title: const Text('Yüksek kontrast'),
                      subtitle: const Text('Tahta ve metin ayrımını güçlendirir.'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text('Veriler', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Kariyer ilerlemesini temizle'),
                subtitle: Text('${store.completedLevelCount} tamamlanan seviye'),
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
        title: const Text('İlerleme temizlensin mi?'),
        content: const Text('Tamamlanan kariyer seviyeleri ve rekorlar kaldırılacak.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Temizle')),
        ],
      ),
    );
    if (approved == true) await store.clearProgress();
  }
}
