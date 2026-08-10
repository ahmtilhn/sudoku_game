import 'dart:io';

import 'package:flutter/material.dart';

import '../../localization/app_strings.dart';
import '../../services/platform_game_services.dart';
import '../../services/platform_leaderboard_service.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';

class PlatformServicesScreen extends StatefulWidget {
  const PlatformServicesScreen({super.key});

  @override
  State<PlatformServicesScreen> createState() => _PlatformServicesScreenState();
}

class _PlatformServicesScreenState extends State<PlatformServicesScreen> {
  final PlatformGameServices _games = PlatformGameServices.instance;
  bool _busy = false;
  String? _error;

  String get _platformTitle =>
      Platform.isIOS ? 'Game Center' : 'Google Play Games';

  Future<bool> _authenticate() async {
    if (!await _games.isConfigured()) return false;
    var authenticated = await _games.refreshAuthentication();
    if (!authenticated) authenticated = await _games.authenticate();
    return authenticated;
  }

  Future<void> _run(Future<bool> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await _authenticate()) {
        throw const PlatformGameServicesException(
          'authentication_failed',
          'Platform authentication could not be completed.',
        );
      }
      final opened = await action();
      if (!opened) {
        throw const PlatformGameServicesException(
          'unavailable',
          'The requested platform screen is not available.',
        );
      }
    } on PlatformGameServicesException catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(_platformTitle),
      ),
      body: AppBackdrop(
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  if (_busy) const LinearProgressIndicator(),
                  if (_busy) const SizedBox(height: 12),
                  if (_error != null) ...[
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: ListTile(
                        leading: const Icon(Icons.error_outline),
                        title: Text(context.tr('online_account_unavailable')),
                        subtitle: Text(_error!),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    context.tr('leaderboards'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _tile(
                    context.tr('global_elo'),
                    const DuelAssetIcon(
                      DuelAsset.leaderboardCrownPro,
                      size: 28,
                    ),
                    () => _run(
                      () => PlatformLeaderboardService.instance.show(
                        PlatformLeaderboardScope.global,
                      ),
                    ),
                  ),
                  for (final item in <(String, PlatformLeaderboardScope)>[
                    (
                      context.tr('difficulty_beginner'),
                      PlatformLeaderboardScope.beginner,
                    ),
                    (
                      context.tr('difficulty_easy'),
                      PlatformLeaderboardScope.easy,
                    ),
                    (
                      context.tr('difficulty_medium'),
                      PlatformLeaderboardScope.medium,
                    ),
                    (
                      context.tr('difficulty_hard'),
                      PlatformLeaderboardScope.hard,
                    ),
                    (
                      context.tr('difficulty_expert'),
                      PlatformLeaderboardScope.expert,
                    ),
                  ])
                    _tile(
                      item.$1,
                      const DuelAssetIcon(DuelAsset.trophy, size: 28),
                      () => _run(
                        () => PlatformLeaderboardService.instance.show(item.$2),
                      ),
                    ),
                  const SizedBox(height: 14),
                  _tile(
                    context.tr('achievement_showcase'),
                    const DuelAssetIcon(DuelAsset.profilePro, size: 28),
                    () => _run(_games.showAchievements),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile(String title, Widget icon, VoidCallback onTap) {
    return Card(
      child: ListTile(
        minTileHeight: 58,
        leading: icon,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: _busy ? null : onTap,
      ),
    );
  }
}
