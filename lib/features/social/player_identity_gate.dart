import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/local_progress_store.dart';
import '../../services/firebase_session_service.dart';
import '../../services/platform_game_services.dart';
import '../../services/player_profile_service.dart';
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
      await SocialApiClient.instance.ensureProfile();
      final profile = await PlayerProfileService.instance.load();
      if (!mounted || profile.profileConfirmed) return;

      PlatformPlayer? platformPlayer;
      final platform = PlatformGameServices.instance;
      try {
        if (await platform.isConfigured() &&
            await platform.refreshAuthentication()) {
          platformPlayer = await platform.getLocalPlayer();
        }
      } catch (_) {
        platformPlayer = null;
      }

      if (!mounted) return;
      final value = await _showIdentityDialog(profile, platformPlayer);
      if (value == null) return;
      await PlayerProfileService.instance.update(
        username: value.username,
        displayName: value.displayName,
        discoverable: true,
        nameSource: value.nameSource,
      );
    } catch (_) {
      // Online identity onboarding is retried from Settings/social screens and
      // must never block offline Sudoku play.
    }
  }

  Future<({String username, String displayName, String nameSource})?>
  _showIdentityDialog(
    PlayerProfilePreferences profile,
    PlatformPlayer? platformPlayer,
  ) async {
    final suggestedName = platformPlayer?.displayName.trim();
    final displayController = TextEditingController(
      text: suggestedName?.isNotEmpty == true ? suggestedName : '',
    );
    final usernameController = TextEditingController(
      text: _suggestUsername(suggestedName, profile.publicId),
    );
    var selectedSource = suggestedName?.isNotEmpty == true
        ? _platformSource()
        : 'custom';

    final result = await showDialog<
      ({String username, String displayName, String nameSource})
    >(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final valid = displayController.text.trim().length >= 2 &&
              RegExp(
                r'^[a-z0-9_]{3,20}$',
              ).hasMatch(usernameController.text.trim().toLowerCase());
          return AlertDialog(
            title: const Text('Create your player profile'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Your display name is shown in matches. Your unique username can be searched, while your permanent Friend ID never changes.',
                    ),
                    if (suggestedName?.isNotEmpty == true) ...[
                      const SizedBox(height: 14),
                      RadioListTile<String>(
                        value: _platformSource(),
                        groupValue: selectedSource,
                        contentPadding: EdgeInsets.zero,
                        title: Text(suggestedName!),
                        subtitle: const Text(
                          'Use your Google Play Games or Game Center name',
                        ),
                        onChanged: (value) {
                          setDialogState(() => selectedSource = value!);
                          displayController.text = suggestedName;
                          usernameController.text = _suggestUsername(
                            suggestedName,
                            profile.publicId,
                          );
                        },
                      ),
                    ],
                    RadioListTile<String>(
                      value: 'custom',
                      groupValue: selectedSource,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Use a custom profile'),
                      onChanged: (value) {
                        setDialogState(() => selectedSource = value!);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: displayController,
                      autofocus: suggestedName?.isNotEmpty != true,
                      maxLength: 24,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        selectedSource = 'custom';
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: usernameController,
                      maxLength: 20,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp('[a-zA-Z0-9_]'),
                        ),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Unique username',
                        helperText:
                            '3–20 lowercase letters, numbers or underscore',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Friend ID: ${profile.publicId}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              FilledButton(
                onPressed: !valid
                    ? null
                    : () => Navigator.of(dialogContext).pop((
                        username: usernameController.text.trim().toLowerCase(),
                        displayName: displayController.text.trim(),
                        nameSource: selectedSource,
                      )),
                child: const Text('Continue'),
              ),
            ],
          );
        },
      ),
    );
    displayController.dispose();
    usernameController.dispose();
    return result;
  }

  String _platformSource() {
    return Theme.of(context).platform == TargetPlatform.iOS
        ? 'game_center'
        : 'google_play_games';
  }

  String _suggestUsername(String? name, String publicId) {
    final normalized = (name ?? 'player')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final base = normalized.length >= 3 ? normalized : 'player';
    final suffix = publicId
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .padRight(4, '0')
        .substring(0, 4);
    final maxBaseLength = 20 - suffix.length - 1;
    final trimmed = base.length > maxBaseLength
        ? base.substring(0, maxBaseLength)
        : base;
    return '${trimmed}_$suffix';
  }
}
