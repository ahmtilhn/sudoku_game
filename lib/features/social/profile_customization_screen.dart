import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../models/avatar_preset_catalog.dart';
import '../../models/rank_identity_models.dart';
import '../../services/platform_game_services.dart';
import '../../services/rank_identity_service.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/in_page_header.dart';
import '../../widgets/player_avatar.dart';

class ProfileCustomizationScreen extends StatefulWidget {
  const ProfileCustomizationScreen({super.key});

  @override
  State<ProfileCustomizationScreen> createState() =>
      _ProfileCustomizationScreenState();
}

class _ProfileCustomizationScreenState
    extends State<ProfileCustomizationScreen> {
  RankIdentityProfile? _profile;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _avatarKey = 'default';
  String _frameKey = 'auto';
  String _titleKey = '';
  List<String> _achievementIds = <String>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await RankIdentityService.instance.refresh();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _avatarKey = profile.selectedAvatarKey;
        _frameKey = profile.selectedFrameKey;
        _titleKey = profile.selectedTitleKey;
        _achievementIds = List<String>.from(
          profile.selectedDecorationAchievementIds,
        );
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = UserSafeError.message(context, error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _profile == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final profile = await RankIdentityService.instance.save(
        avatarKey: _avatarKey,
        frameKey: _frameKey,
        titleKey: _titleKey,
        achievementIds: _achievementIds,
      );
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _avatarKey = profile.selectedAvatarKey;
        _frameKey = profile.selectedFrameKey;
        _titleKey = profile.selectedTitleKey;
        _achievementIds = List<String>.from(
          profile.selectedDecorationAchievementIds,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile style saved.')),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = UserSafeError.message(context, error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildLoaded(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoaded(BuildContext context) {
    final profile = _profile;
    if (profile == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const InPageHeader(title: 'Profile customization'),
          const SizedBox(height: 24),
          _ErrorCard(message: _error ?? 'Profile could not be loaded.', onRetry: _load),
        ],
      );
    }
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Column(
              children: [
                const InPageHeader(title: 'Profile customization'),
                const SizedBox(height: 10),
                _PreviewCard(
                  profile: profile,
                  avatarKey: _avatarKey,
                  frameKey: _frameKey,
                  titleKey: _titleKey,
                  achievementIds: _achievementIds,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  _InlineError(message: _error!),
                ],
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .06),
                    ),
                  ),
                  child: const TabBar(
                    isScrollable: true,
                    tabs: [
                      Tab(icon: Icon(Icons.face_rounded), text: 'Avatars'),
                      Tab(icon: Icon(Icons.shield_rounded), text: 'Frames'),
                      Tab(icon: Icon(Icons.workspace_premium_rounded), text: 'Badges'),
                      Tab(icon: Icon(Icons.title_rounded), text: 'Titles'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              children: [
                _AvatarTab(
                  selectedKey: _avatarKey,
                  onSelected: (key) => setState(() => _avatarKey = key),
                ),
                _FrameTab(
                  profile: profile,
                  selectedKey: _frameKey,
                  onSelected: (key) => setState(() => _frameKey = key),
                ),
                _DecorationTab(
                  profile: profile,
                  selectedAchievementIds: _achievementIds,
                  onToggle: _toggleDecoration,
                ),
                _TitleTab(
                  profile: profile,
                  selectedKey: _titleKey,
                  onSelected: (key) => setState(() => _titleKey = key),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1215).withValues(alpha: .96),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: .06)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Rank frames and achievement badges are earned, not purchased.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .56),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(_saving ? 'Saving' : 'Save'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggleDecoration(String achievementId) {
    setState(() {
      if (_achievementIds.contains(achievementId)) {
        _achievementIds.remove(achievementId);
        return;
      }
      if (_achievementIds.length >= 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You can equip up to 3 frame badges.')),
        );
        return;
      }
      _achievementIds.add(achievementId);
    });
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.profile,
    required this.avatarKey,
    required this.frameKey,
    required this.titleKey,
    required this.achievementIds,
  });

  final RankIdentityProfile profile;
  final String avatarKey;
  final String frameKey;
  final String titleKey;
  final List<String> achievementIds;

  @override
  Widget build(BuildContext context) {
    final decorations = <String>[];
    for (final id in achievementIds) {
      for (final decoration in profile.decorations) {
        if (decoration.achievementId == id) {
          decorations.add(decoration.decorationKey);
          break;
        }
      }
    }
    final effectiveFrame = frameKey == 'auto' ? profile.rankKey : frameKey;
    final identity = RankIdentityKey(
      avatarKey: avatarKey,
      frameKey: effectiveFrame,
      decorationKeys: decorations,
    ).encode();
    final platform = PlatformGameServices.instance.localPlayer.value;
    final previewBaseKey = RankIdentityKey.parse(identity).avatarKey;
    final usePlatformAvatar = previewBaseKey.startsWith('home-profile-');
    final title = profile.unlockedTitles
        .where((item) => item.key == titleKey)
        .map((item) => item.label)
        .firstOrNull;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .075)),
      ),
      child: Row(
        children: [
          PlayerAvatar(
            displayName: profile.displayName,
            avatarKey: identity,
            localAvatarBytes: usePlatformAvatar ? platform?.avatarBytes : null,
            remoteApprovedImageUrl:
                usePlatformAvatar ? platform?.avatarUrl : null,
            radius: 39,
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${profile.rankName} · ${profile.rankPoints} RP',
                  style: const TextStyle(
                    color: Color(0xFF66C7FF),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (title != null && title.isNotEmpty)
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .62),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '${achievementIds.length}/3',
            style: TextStyle(
              color: Colors.white.withValues(alpha: .48),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarTab extends StatelessWidget {
  const _AvatarTab({required this.selectedKey, required this.onSelected});

  final String selectedKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final platform = PlatformGameServices.instance.localPlayer.value;
    final choices = <String>[
      'default',
      if (platform != null) 'home-profile-platform',
      ...AvatarPresetCatalog.all.map((preset) => preset.key),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700
            ? 7
            : constraints.maxWidth >= 500
            ? 6
            : 4;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: .85,
          ),
          itemCount: choices.length,
          itemBuilder: (context, index) {
            final key = choices[index];
            final preset = AvatarPresetCatalog.byKey(key);
            final label = key == 'default'
                ? 'Initials'
                : key == 'home-profile-platform'
                ? 'Platform'
                : preset?.label ?? key;
            final selected = selectedKey == key;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelected(key),
                borderRadius: BorderRadius.circular(16),
                child: Ink(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF3AA9FF).withValues(alpha: .12)
                        : Colors.black.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF66C7FF)
                          : Colors.white.withValues(alpha: .06),
                      width: selected ? 1.6 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PlayerAvatar(
                        displayName: platform?.effectiveDisplayName ?? 'Player',
                        avatarKey: key,
                        localAvatarBytes: key == 'home-profile-platform'
                            ? platform?.avatarBytes
                            : null,
                        remoteApprovedImageUrl: key == 'home-profile-platform'
                            ? platform?.avatarUrl
                            : null,
                        radius: 25,
                      ),
                      const SizedBox(height: 7),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: selected ? .94 : .64),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _FrameTab extends StatelessWidget {
  const _FrameTab({
    required this.profile,
    required this.selectedKey,
    required this.onSelected,
  });

  final RankIdentityProfile profile;
  final String selectedKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final platform = PlatformGameServices.instance.localPlayer.value;
    final selectedBaseKey = RankIdentityKey.parse(
      profile.selectedAvatarKey,
    ).avatarKey;
    final usePlatformAvatar = selectedBaseKey.startsWith('home-profile-');
    final rewards = <String, RankRewardState>{
      for (final reward in profile.rankRewards) reward.rankKey: reward,
    };
    final frames = <String>['auto', ...rankTierCatalog.map((tier) => tier.key)];
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      itemCount: frames.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _RewardBanner(total: profile.totalLifetimeRankReward);
        }
        final key = frames[index - 1];
        final auto = key == 'auto';
        final tier = auto ? rankTierForKey(profile.rankKey) : rankTierForKey(key);
        final unlocked = auto || profile.unlockedFrameKeys.contains(key);
        final selected = selectedKey == key;
        final reward = rewards[tier.key];
        final previewKey = auto ? profile.rankKey : key;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: unlocked ? () => onSelected(key) : null,
            borderRadius: BorderRadius.circular(17),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF3AA9FF).withValues(alpha: .11)
                    : Colors.black.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF66C7FF).withValues(alpha: .75)
                      : Colors.white.withValues(alpha: .06),
                ),
              ),
              child: Row(
                children: [
                  PlayerAvatar(
                    displayName: profile.displayName,
                    avatarKey: RankIdentityKey(
                      avatarKey: profile.selectedAvatarKey,
                      frameKey: previewKey,
                    ).encode(),
                    localAvatarBytes:
                        usePlatformAvatar ? platform?.avatarBytes : null,
                    remoteApprovedImageUrl:
                        usePlatformAvatar ? platform?.avatarUrl : null,
                    radius: 29,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auto ? 'Auto · current rank' : tier.label,
                          style: TextStyle(
                            color: unlocked
                                ? Colors.white
                                : Colors.white.withValues(alpha: .42),
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          auto
                              ? 'Frame follows your current rank automatically.'
                              : unlocked
                              ? 'Permanently unlocked at ${tier.minPoints} RP.'
                              : 'Unlock by reaching ${tier.minPoints} RP.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .48),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (reward != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: reward.claimed
                            ? const Color(0xFF29D398).withValues(alpha: .10)
                            : const Color(0xFFFFC94D).withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${reward.amount} Coin${reward.claimed ? ' ✓' : ''}',
                        style: TextStyle(
                          color: reward.claimed
                              ? const Color(0xFF69E5BA)
                              : const Color(0xFFFFD86A),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  const SizedBox(width: 7),
                  Icon(
                    unlocked
                        ? selected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded
                        : Icons.lock_rounded,
                    color: unlocked
                        ? const Color(0xFF66C7FF)
                        : Colors.white.withValues(alpha: .28),
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

class _DecorationTab extends StatelessWidget {
  const _DecorationTab({
    required this.profile,
    required this.selectedAchievementIds,
    required this.onToggle,
  });

  final RankIdentityProfile profile;
  final List<String> selectedAchievementIds;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      itemCount: profile.decorations.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _InfoCard(
            icon: Icons.workspace_premium_rounded,
            title: 'Up to 3 achievement badges',
            body:
                'Badges are attached directly to your frame. They are earned by gameplay and remain visible anywhere your in-game avatar is shown.',
          );
        }
        final decoration = profile.decorations[index - 1];
        final selected = selectedAchievementIds.contains(decoration.achievementId);
        final enabled = decoration.unlocked;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? () => onToggle(decoration.achievementId) : null,
            borderRadius: BorderRadius.circular(17),
            child: Ink(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFFB7A9FF).withValues(alpha: .11)
                    : Colors.black.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: selected
                      ? const Color(0xFFB7A9FF).withValues(alpha: .62)
                      : Colors.white.withValues(alpha: .06),
                ),
              ),
              child: Row(
                children: [
                  PlayerAvatar(
                    displayName: profile.displayName,
                    avatarKey: RankIdentityKey(
                      avatarKey: 'preset_001',
                      frameKey: profile.rankKey,
                      decorationKeys: [decoration.decorationKey],
                    ).encode(),
                    radius: 27,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                decoration.title,
                                style: TextStyle(
                                  color: enabled
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: .40),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            _RarityPill(rarity: decoration.rarity),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          decoration.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .48),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    !enabled
                        ? Icons.lock_rounded
                        : selected
                        ? Icons.check_circle_rounded
                        : Icons.add_circle_outline_rounded,
                    color: !enabled
                        ? Colors.white.withValues(alpha: .25)
                        : selected
                        ? const Color(0xFFB7A9FF)
                        : Colors.white.withValues(alpha: .55),
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

class _TitleTab extends StatelessWidget {
  const _TitleTab({
    required this.profile,
    required this.selectedKey,
    required this.onSelected,
  });

  final RankIdentityProfile profile;
  final String selectedKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = <RankTitleOption>[
      const RankTitleOption(key: '', label: 'No title'),
      ...profile.unlockedTitles,
    ];
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      itemCount: options.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          return const _InfoCard(
            icon: Icons.title_rounded,
            title: 'Prestige titles',
            body:
                'Master titles are permanent account unlocks. Your current competitive rank is always displayed separately, so an old title can never hide your actual rank.',
          );
        }
        final option = options[index - 1];
        final selected = selectedKey == option.key;
        return ListTile(
          onTap: () => onSelected(option.key),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: selected
                  ? const Color(0xFFD9A5FF).withValues(alpha: .62)
                  : Colors.white.withValues(alpha: .06),
            ),
          ),
          tileColor: selected
              ? const Color(0xFFD9A5FF).withValues(alpha: .09)
              : Colors.black.withValues(alpha: .14),
          leading: Icon(
            option.key.isEmpty
                ? Icons.remove_circle_outline_rounded
                : Icons.workspace_premium_rounded,
            color: selected
                ? const Color(0xFFD9A5FF)
                : Colors.white.withValues(alpha: .55),
          ),
          title: Text(
            option.label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          trailing: selected
              ? const Icon(Icons.check_circle_rounded, color: Color(0xFFD9A5FF))
              : null,
        );
      },
    );
  }
}

class _RewardBanner extends StatelessWidget {
  const _RewardBanner({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      icon: Icons.paid_rounded,
      title: '$total lifetime Rank Coins',
      body:
          'Each division reward is granted automatically only the first time you reach it. Dropping and climbing back cannot farm the reward.',
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF3AA9FF).withValues(alpha: .075),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3AA9FF).withValues(alpha: .17)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF66C7FF)),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .55),
                    fontSize: 11,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RarityPill extends StatelessWidget {
  const _RarityPill({required this.rarity});

  final String rarity;

  @override
  Widget build(BuildContext context) {
    final color = switch (rarity) {
      'legendary' => const Color(0xFFFFD66B),
      'epic' => const Color(0xFFB99CFF),
      'rare' => const Color(0xFF66C7FF),
      _ => const Color(0xFF9DB3BF),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        rarity.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: .4,
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: .22)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
