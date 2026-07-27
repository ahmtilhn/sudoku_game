import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/local_progress_store.dart';
import '../../services/firebase_session_service.dart';
import '../../services/platform_game_services.dart';
import '../../services/social_api_client.dart';
import '../home/home_screen.dart';

class PlayerIdentityGate extends StatefulWidget {
  const PlayerIdentityGate({super.key, required this.store});

  final LocalProgressStore store;

  @override
  State<PlayerIdentityGate> createState() => _PlayerIdentityGateState();
}

class _PlayerIdentityGateState extends State<PlayerIdentityGate> {
  bool _promptScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkIdentity());
    });
  }

  @override
  Widget build(BuildContext context) => HomeScreen(store: widget.store);

  Future<void> _checkIdentity() async {
    if (_promptScheduled || !SocialApiClient.instance.configured) return;
    _promptScheduled = true;
    try {
      await FirebaseSessionService.ensureAnonymousSession();
      final profile = await SocialApiClient.instance.ensureProfile();
      if (!mounted || profile.displayName != 'Sudoku Player') return;

      String? platformName;
      final platform = PlatformGameServices.instance;
      try {
        if (await platform.isConfigured() &&
            await platform.refreshAuthentication()) {
          platformName = (await platform.getLocalPlayer())?.displayName.trim();
          if (platformName?.isEmpty == true) platformName = null;
        }
      } catch (_) {
        platformName = null;
      }

      if (!mounted) return;
      final name = await _showNameDialog(platformName);
      if (name == null || name.trim().length < 2) return;
      await SocialApiClient.instance.ensureProfile(displayName: name.trim());
    } catch (_) {
      // Online identity onboarding is retried from Settings/social screens and
      // must never block offline Sudoku play.
    }
  }

  Future<String?> _showNameDialog(String? platformName) async {
    final controller = TextEditingController(text: platformName ?? '');
    String? selectedSource = platformName == null ? 'custom' : 'platform';
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Choose your player name'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'This name is shown to opponents, friends and challenge invitations. Your permanent Friend ID stays unchanged.',
                ),
                if (platformName != null) ...[
                  const SizedBox(height: 14),
                  RadioListTile<String>(
                    value: 'platform',
                    groupValue: selectedSource,
                    contentPadding: EdgeInsets.zero,
                    title: Text(platformName),
                    subtitle: const Text('Use your platform game profile name'),
                    onChanged: (value) {
                      setDialogState(() => selectedSource = value);
                      controller.text = platformName!;
                    },
                  ),
                ],
                RadioListTile<String>(
                  value: 'custom',
                  groupValue: selectedSource,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use a custom name'),
                  onChanged: (value) {
                    setDialogState(() => selectedSource = value);
                    if (controller.text == platformName) controller.clear();
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  autofocus: platformName == null,
                  enabled: selectedSource == 'custom',
                  maxLength: 24,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Player name',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                  onSubmitted: (value) {
                    if (value.trim().length >= 2) {
                      Navigator.of(dialogContext).pop(value.trim());
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: controller.text.trim().length < 2
                  ? null
                  : () => Navigator.of(
                      dialogContext,
                    ).pop(controller.text.trim()),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }
}
