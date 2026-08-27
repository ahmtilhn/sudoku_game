import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../models/avatar_preset_catalog.dart';
import '../../models/country_catalog.dart';
import '../../models/rank_identity_fallback.dart';
import '../../models/rank_identity_models.dart';
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
  // Titles stay implemented and can be re-enabled later without rebuilding the
  // tab. A getter keeps the hidden branch analyzer-visible without dead code.
  static bool get _showTitles => false;

  late RankIdentityProfile _profile;
  bool _hydrating = false;
  bool _saving = false;
  bool _serverReady = false;
  String? _error;
  String _avatarKey = AvatarPresetCatalog.firstKey;
  String _frameKey = 'auto';
  String _titleKey = '';
  List<String> _achievementIds = <String>[];
  String? _countryCode;
  bool _countryFlagVisible = true;

  @override
  void initState() {
    super.initState();
    final cached = RankIdentityService.instance.current.value;
    _profile = cached ?? buildRankIdentityFallback();
    _applyProfile(_profile);
    unawaited(_hydrate());
  }

  void _applyProfile(RankIdentityProfile profile) {
    _profile = profile;
    _avatarKey = AvatarPresetCatalog.normalizeKey(profile.selectedAvatarKey);
    _frameKey = profile.selectedFrameKey;
    _titleKey = profile.selectedTitleKey;
    _achievementIds = List<String>.from(
      profile.selectedDecorationAchievementIds,
    );
  }

  Future<void> _hydrate() async {
    if (_hydrating) return;
    if (mounted) {
      setState(() {
        _hydrating = true;
        _error = null;
      });
    }

    Object? firstError;
    RankIdentityProfile? loadedProfile;
    RankCountryPreference? loadedCountry;

    await Future.wait<void>([
      () async {
        try {
          loadedProfile = await RankIdentityService.instance.refresh();
        } catch (error) {
          firstError ??= error;
        }
      }(),
      () async {
        try {
          loadedCountry =
              await RankIdentityService.instance.loadCountryPreference();
        } catch (error) {
          firstError ??= error;
        }
      }(),
    ]);

    if (!mounted) return;
    setState(() {
      if (loadedProfile != null) _applyProfile(loadedProfile!);
      if (loadedCountry != null) {
        _countryCode = loadedCountry!.countryCode;
        _countryFlagVisible = loadedCountry!.flagVisible;
      }
      _serverReady = loadedProfile != null && loadedCountry != null;
      if (firstError != null) {
        _error = UserSafeError.message(context, firstError!);
      }
      _hydrating = false;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_serverReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Profile server is unavailable. Preview is local until reconnect.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final profile = await RankIdentityService.instance.save(
        avatarKey: AvatarPresetCatalog.normalizeKey(_avatarKey),
        frameKey: _frameKey,
        titleKey: _titleKey,
        achievementIds: _achievementIds,
      );
      final country = await RankIdentityService.instance.saveCountryPreference(
        countryCode: _countryCode,
        flagVisible: _countryFlagVisible,
      );
      if (!mounted) return;
      setState(() {
        _serverReady = true;
        _applyProfile(profile);
        _countryCode = country.countryCode;
        _countryFlagVisible = country.flagVisible;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile settings saved.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _serverReady = false;
        _error = UserSafeError.message(context, error);
      });
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
              constraints: const BoxConstraints(maxWidth: 860),
              child: DefaultTabController(
                length: _showTitles ? 5 : 4,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                      child: Column(
                        children: [
                          InPageHeader(
                            title: 'Profile customization',
                            actions: [
                              IconButton(
                                tooltip: 'Refresh profile',
                                onPressed: _hydrating ? null : _hydrate,
                                icon: _hydrating
                                    ? const SizedBox.square(
                                        dimension: 19,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.refresh_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _PreviewCard(
                            profile: _profile,
                            avatarKey: _avatarKey,
                            frameKey: _frameKey,
                            titleKey: _titleKey,
                            achievementIds: _achievementIds,
                            countryCode: _countryCode,
                            countryFlagVisible: _countryFlagVisible,
                          ),
                          if (!_serverReady || _error != null) ...[
                            const SizedBox(height: 8),
                            _OfflineNotice(
                              message:
                                  _error ??
                                  'Online profile is reconnecting. All profile options remain previewable.',
                              busy: _hydrating,
                              onRetry: _hydrate,
                            ),
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
                            child: TabBar(
                              isScrollable: false,
                              tabAlignment: TabAlignment.fill,
                              labelPadding: EdgeInsets.zero,
                              tabs: [
                                const Tab(
                                  icon: _CustomizationTabIcon(
                                    assetPath:
                                        'assets/profilecustomization/avatars.png',
                                  ),
                                  text: 'Avatars',
                                ),
                                const Tab(
                                  icon: _CustomizationTabIcon(
                                    assetPath:
                                        'assets/profilecustomization/framers.png',
                                  ),
                                  text: 'Frames',
                                ),
                                const Tab(
                                  icon: _CustomizationTabIcon(
                                    assetPath:
                                        'assets/profilecustomization/badges.png',
                                  ),
                                  text: 'Badges',
                                ),
                                if (_showTitles)
                                  const Tab(
                                    icon: Icon(Icons.title_rounded),
                                    text: 'Titles',
                                  ),
                                const Tab(
                                  icon: _CustomizationTabIcon(
                                    assetPath:
                                        'assets/profilecustomization/country.png',
                                  ),
                                  text: 'Country',
                                ),
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
                            onSelected: (key) =>
                                setState(() => _avatarKey = key),
                          ),
                          _FrameTab(
                            profile: _profile,
                            avatarKey: _avatarKey,
                            selectedKey: _frameKey,
                            onSelected: (key) =>
                                setState(() => _frameKey = key),
                          ),
                          _DecorationTab(
                            profile: _profile,
                            avatarKey: _avatarKey,
                            selectedAchievementIds: _achievementIds,
                            onToggle: _toggleDecoration,
                          ),
                          if (_showTitles)
                            _TitleTab(
                              profile: _profile,
                              selectedKey: _titleKey,
                              onSelected: (key) =>
                                  setState(() => _titleKey = key),
                            ),
                          _CountryTab(
                            countryCode: _countryCode,
                            flagVisible: _countryFlagVisible,
                            onCountryChanged: (code) =>
                                setState(() => _countryCode = code),
                            onVisibilityChanged: (value) => setState(
                              () => _countryFlagVisible = value,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _SaveBar(
                      serverReady: _serverReady,
                      saving: _saving,
                      onSave: _save,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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

class _CustomizationTabIcon extends StatelessWidget {
  const _CustomizationTabIcon({required this.assetPath});

  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: 28,
      height: 28,
      fit: BoxFit.contain,
      cacheWidth: 96,
      cacheHeight: 96,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const SizedBox.square(dimension: 28),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.profile,
    required this.avatarKey,
    required this.frameKey,
    required this.titleKey,
    required this.achievementIds,
    required this.countryCode,
    required this.countryFlagVisible,
  });

  final RankIdentityProfile profile;
  final String avatarKey;
  final String frameKey;
  final String titleKey;
  final List<String> achievementIds;
  final String? countryCode;
  final bool countryFlagVisible;

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
      avatarKey: AvatarPresetCatalog.normalizeKey(avatarKey),
      frameKey: effectiveFrame,
      decorationKeys: decorations,
    ).encode();
    final title = _titleLabel(profile, titleKey);
    final flag = countryFlagVisible ? countryFlagEmoji(countryCode) : '';

    return Container(
      width: double.infinity,
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
            radius: 39,
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (flag.isNotEmpty) ...[
                      Text(
                        flag,
                        style: const TextStyle(fontSize: 18, height: 1),
                        semanticsLabel: 'Country flag',
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        profile.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${profile.rankName} · ${profile.rankPoints} RP',
                  style: const TextStyle(
                    color: Color(0xFF66C7FF),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (title != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .62),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFB7A9FF).withValues(alpha: .10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${achievementIds.length}/3',
              style: const TextStyle(
                color: Color(0xFFD7CCFF),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _titleLabel(RankIdentityProfile profile, String key) {
    if (key.isEmpty) return null;
    for (final title in profile.unlockedTitles) {
      if (title.key == key) return title.label;
    }
    return null;
  }
}

class _AvatarTab extends StatelessWidget {
  const _AvatarTab({required this.selectedKey, required this.onSelected});

  final String selectedKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final choices = AvatarPresetCatalog.all;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720
            ? 7
            : constraints.maxWidth >= 520
            ? 6
            : constraints.maxWidth >= 360
            ? 4
            : 3;

        return GridView.builder(
          key: const PageStorageKey<String>('profile-avatar-grid'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: .84,
          ),
          itemCount: choices.length,
          itemBuilder: (context, index) {
            final avatar = choices[index];
            final selected = selectedKey == avatar.key;

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelected(avatar.key),
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
                        displayName: 'Sudoku Player',
                        avatarKey: avatar.key,
                        radius: 27,
                      ),
                      const SizedBox(height: 7),
                      Text(
                        avatar.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(
                            alpha: selected ? .94 : .64,
                          ),
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
    required this.avatarKey,
    required this.selectedKey,
    required this.onSelected,
  });

  final RankIdentityProfile profile;
  final String avatarKey;
  final String selectedKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final rewards = <String, RankRewardState>{
      for (final reward in profile.rankRewards) reward.rankKey: reward,
    };
    final frames = <String>['auto', ...rankTierCatalog.map((tier) => tier.key)];

    return ListView.separated(
      key: const PageStorageKey<String>('profile-frame-list'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      itemCount: frames.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _InfoCard(
            icon: Icons.paid_rounded,
            title: '${profile.totalLifetimeRankReward} lifetime Rank Coins',
            body:
                'Every division has its own frame. Rank rewards are first-time-only and cannot be farmed by dropping and climbing again.',
          );
        }

        final key = frames[index - 1];
        final auto = key == 'auto';
        final tier = auto
            ? rankTierForKey(profile.rankKey)
            : rankTierForKey(key);
        final unlocked = auto || profile.unlockedFrameKeys.contains(tier.key);
        final selected = selectedKey == key;
        final reward = rewards[tier.key];
        final previewFrame = auto ? profile.rankKey : tier.key;

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
                      avatarKey: AvatarPresetCatalog.normalizeKey(avatarKey),
                      frameKey: previewFrame,
                    ).encode(),
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
                  if (reward != null && reward.amount > 0) ...[
                    const SizedBox(width: 8),
                    _CoinPill(reward: reward),
                  ],
                  const SizedBox(width: 8),
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
    required this.avatarKey,
    required this.selectedAchievementIds,
    required this.onToggle,
  });

  final RankIdentityProfile profile;
  final String avatarKey;
  final List<String> selectedAchievementIds;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const PageStorageKey<String>('profile-badge-list'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      itemCount: profile.decorations.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          return const _InfoCard(
            icon: Icons.workspace_premium_rounded,
            title: '3 achievement slots',
            body:
                'Earned badges can be attached directly to your frame. Locked badges stay visible here so you always know what can be earned.',
          );
        }

        final decoration = profile.decorations[index - 1];
        final selected = selectedAchievementIds.contains(
          decoration.achievementId,
        );
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
                      avatarKey: AvatarPresetCatalog.normalizeKey(avatarKey),
                      frameKey: profile.rankKey,
                      decorationKeys: <String>[decoration.decorationKey],
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
                                      : Colors.white.withValues(alpha: .46),
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
                            color: Colors.white.withValues(alpha: .50),
                            fontSize: 11,
                            height: 1.25,
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

// Kept intentionally for future re-enablement. Titles remain supported by the
// profile model and save flow, but the user-facing tab is hidden for now.
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
      key: const PageStorageKey<String>('profile-title-list'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      itemCount: options.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          return const _InfoCard(
            icon: Icons.title_rounded,
            title: 'Prestige titles',
            body:
                'Master and Master I titles are permanent account unlocks. Your actual current rank is always shown separately.',
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
              ? const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFFD9A5FF),
                )
              : null,
        );
      },
    );
  }
}

class _CountryTab extends StatelessWidget {
  const _CountryTab({
    required this.countryCode,
    required this.flagVisible,
    required this.onCountryChanged,
    required this.onVisibilityChanged,
  });

  final String? countryCode;
  final bool flagVisible;
  final ValueChanged<String?> onCountryChanged;
  final ValueChanged<bool> onVisibilityChanged;

  @override
  Widget build(BuildContext context) {
    final selected = countryOptionForCode(countryCode);
    return ListView(
      key: const PageStorageKey<String>('profile-country-list'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        const _InfoCard(
          icon: Icons.public_rounded,
          title: 'Country flag',
          body:
              'Choose the country you want to represent. It appears before your name in Ranked Ladder and is never inferred from your location.',
        ),
        const SizedBox(height: 10),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _chooseCountry(context),
            borderRadius: BorderRadius.circular(17),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: Colors.white.withValues(alpha: .06)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 42,
                    child: Text(
                      selected?.flag ?? '🌐',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 27),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selected?.name ?? 'Choose country',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          selected == null
                              ? 'No country flag will be shown until you choose one.'
                              : 'Your flag can be shown before your player name.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .48),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white54,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (selected != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => onCountryChanged(null),
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Clear country'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          value: flagVisible,
          onChanged: selected == null ? null : onVisibilityChanged,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
            side: BorderSide(color: Colors.white.withValues(alpha: .06)),
          ),
          tileColor: Colors.black.withValues(alpha: .14),
          secondary: Icon(
            Icons.flag_rounded,
            color: selected == null
                ? Colors.white.withValues(alpha: .28)
                : const Color(0xFF66C7FF),
          ),
          title: const Text(
            'Show flag on Ranked Ladder',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Text(
            selected == null
                ? 'Choose a country first.'
                : flagVisible
                ? 'Only the flag appears before your name. No country abbreviation is shown.'
                : 'Your country stays saved, but the flag is hidden from the ladder.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: .50),
              fontSize: 11,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _chooseCountry(BuildContext context) async {
    final value = await showModalBottomSheet<CountryOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101A20),
      showDragHandle: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: .86,
        child: _CountryPickerSheet(),
      ),
    );
    if (value != null) onCountryChanged(value.code);
  }
}

class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet();

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final choices = query.isEmpty
        ? countryOptions
        : countryOptions
              .where((country) => country.name.toLowerCase().contains(query))
              .toList(growable: false);

    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose country',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  autofocus: true,
                  onChanged: (value) => setState(() => _query = value),
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Search country',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: choices.isEmpty
                ? Center(
                    child: Text(
                      'No country found.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .55),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : ListView.separated(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
                    itemCount: choices.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: .045),
                    ),
                    itemBuilder: (context, index) {
                      final country = choices[index];
                      return ListTile(
                        onTap: () => Navigator.of(context).pop(country),
                        leading: SizedBox(
                          width: 34,
                          child: Text(
                            country.flag,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 23),
                          ),
                        ),
                        title: Text(
                          country.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white38,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.serverReady,
    required this.saving,
    required this.onSave,
  });

  final bool serverReady;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
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
              serverReady
                  ? 'Avatars come only from the bundled avatar collection. Rank cosmetics are earned.'
                  : 'Preview mode · reconnect to save changes.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: .56),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: saving ? null : onSave,
            icon: saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    serverReady ? Icons.check_rounded : Icons.cloud_off_rounded,
                  ),
            label: Text(
              saving
                  ? 'Saving'
                  : serverReady
                  ? 'Save'
                  : 'Preview',
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice({
    required this.message,
    required this.busy,
    required this.onRetry,
  });

  final String message;
  final bool busy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB454).withValues(alpha: .09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFFB454).withValues(alpha: .22),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            color: Color(0xFFFFC66B),
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .72),
                fontSize: 11,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Retry',
            onPressed: busy ? null : onRetry,
            icon: busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
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
        border: Border.all(
          color: const Color(0xFF3AA9FF).withValues(alpha: .17),
        ),
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

class _CoinPill extends StatelessWidget {
  const _CoinPill({required this.reward});

  final RankRewardState reward;

  @override
  Widget build(BuildContext context) {
    return Container(
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
