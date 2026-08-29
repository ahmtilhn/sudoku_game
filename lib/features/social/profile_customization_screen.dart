import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../localization/app_strings.dart';
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
          loadedCountry = await RankIdentityService.instance
              .loadCountryPreference();
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
        SnackBar(
          content: Text(context.tr('profile_server_unavailable_preview')),
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
        SnackBar(content: Text(context.tr('profile_settings_saved'))),
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 720;
              final tight = constraints.maxHeight < 610;
              final horizontal = constraints.maxWidth < 360 ? 10.0 : 16.0;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: DefaultTabController(
                    length: _showTitles ? 5 : 4,
                    child: Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            horizontal,
                            tight ? 2 : 6,
                            horizontal,
                            0,
                          ),
                          child: Column(
                            children: [
                              InPageHeader(
                                title: context.tr('profile_customization'),
                                padding: EdgeInsets.only(
                                  bottom: tight
                                      ? 2
                                      : compact
                                      ? 4
                                      : 8,
                                ),
                                actions: [
                                  IconButton(
                                    tooltip: context.tr('refresh_profile'),
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
                              _PreviewCard(
                                profile: _profile,
                                avatarKey: _avatarKey,
                                frameKey: _frameKey,
                                titleKey: _titleKey,
                                achievementIds: _achievementIds,
                                countryCode: _countryCode,
                                countryFlagVisible: _countryFlagVisible,
                                compact: compact,
                                tight: tight,
                              ),
                              if ((!_serverReady || _error != null) &&
                                  !tight) ...[
                                const SizedBox(height: 5),
                                _OfflineNotice(
                                  message:
                                      _error ??
                                      context.tr(
                                        'profile_reconnecting_preview',
                                      ),
                                  busy: _hydrating,
                                  onRetry: _hydrate,
                                  compact: compact,
                                ),
                              ],
                              SizedBox(height: tight ? 3 : 6),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: .18),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: .06),
                                  ),
                                ),
                                child: TabBar(
                                  isScrollable: false,
                                  tabAlignment: TabAlignment.fill,
                                  labelPadding: EdgeInsets.zero,
                                  tabs: [
                                    Tab(
                                      height: tight ? 43 : 52,
                                      icon: _CustomizationTabIcon(
                                        assetPath:
                                            'assets/profilecustomization/avatars.png',
                                        compact: tight,
                                      ),
                                      text: context.tr('avatars'),
                                    ),
                                    Tab(
                                      height: tight ? 43 : 52,
                                      icon: _CustomizationTabIcon(
                                        assetPath:
                                            'assets/profilecustomization/framers.png',
                                        compact: tight,
                                      ),
                                      text: context.tr('frames'),
                                    ),
                                    Tab(
                                      height: tight ? 43 : 52,
                                      icon: _CustomizationTabIcon(
                                        assetPath:
                                            'assets/profilecustomization/badges.png',
                                        compact: tight,
                                      ),
                                      text: context.tr('badges'),
                                    ),
                                    if (_showTitles)
                                      Tab(
                                        height: tight ? 43 : 52,
                                        icon: const Icon(Icons.title_rounded),
                                        text: context.tr('titles'),
                                      ),
                                    Tab(
                                      height: tight ? 43 : 52,
                                      icon: _CustomizationTabIcon(
                                        assetPath:
                                            'assets/profilecustomization/country.png',
                                        compact: tight,
                                      ),
                                      text: context.tr('country'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: tight ? 2 : 5),
                        Expanded(
                          child: TabBarView(
                            physics: const NeverScrollableScrollPhysics(),
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
                                onVisibilityChanged: (value) =>
                                    setState(() => _countryFlagVisible = value),
                              ),
                            ],
                          ),
                        ),
                        _SaveBar(
                          serverReady: _serverReady,
                          saving: _saving,
                          onSave: _save,
                          compact: compact,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
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
          SnackBar(content: Text(context.tr('max_three_frame_badges'))),
        );
        return;
      }
      _achievementIds.add(achievementId);
    });
  }
}

class _CustomizationTabIcon extends StatelessWidget {
  const _CustomizationTabIcon({required this.assetPath, required this.compact});

  final String assetPath;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 21.0 : 26.0;
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      cacheWidth: 96,
      cacheHeight: 96,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => SizedBox.square(dimension: size),
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
    required this.compact,
    required this.tight,
  });

  final RankIdentityProfile profile;
  final String avatarKey;
  final String frameKey;
  final String titleKey;
  final List<String> achievementIds;
  final String? countryCode;
  final bool countryFlagVisible;
  final bool compact;
  final bool tight;

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
      padding: EdgeInsets.all(
        tight
            ? 8
            : compact
            ? 10
            : 14,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .075)),
      ),
      child: Row(
        children: [
          PlayerAvatar(
            displayName: profile.displayName,
            avatarKey: identity,
            radius: tight
                ? 25
                : compact
                ? 31
                : 39,
          ),
          SizedBox(width: tight ? 9 : 13),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (flag.isNotEmpty) ...[
                      Text(
                        flag,
                        style: TextStyle(fontSize: tight ? 14 : 18, height: 1),
                        semanticsLabel: context.tr('country_flag'),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Expanded(
                      child: Text(
                        profile.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: tight
                              ? 14
                              : compact
                              ? 16
                              : 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  context.tr('rank_points_format', <Object>[
                    profile.rankName,
                    profile.rankPoints,
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF66C7FF),
                    fontSize: tight ? 10 : 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (!tight && title != null)
                  Text(
                    context.tr(title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .62),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: tight ? 6 : 9,
              vertical: tight ? 4 : 6,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFB7A9FF).withValues(alpha: .10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${achievementIds.length}/3',
              style: TextStyle(
                color: const Color(0xFFD7CCFF),
                fontSize: tight ? 10 : 12,
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

class _AvatarTab extends StatefulWidget {
  const _AvatarTab({required this.selectedKey, required this.onSelected});

  final String selectedKey;
  final ValueChanged<String> onSelected;

  @override
  State<_AvatarTab> createState() => _AvatarTabState();
}

class _AvatarTabState extends State<_AvatarTab> {
  int _page = 0;

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
        final rows = constraints.maxHeight < 250
            ? 1
            : constraints.maxHeight < 390
            ? 2
            : 3;
        final pageSize = columns * rows;
        final pageCount = (choices.length / pageSize).ceil();
        final page = _page.clamp(0, pageCount - 1);
        final start = page * pageSize;
        final end = (start + pageSize).clamp(0, choices.length);
        final visible = choices.sublist(start, end);

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Column(
            children: [
              Expanded(
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 7,
                    crossAxisSpacing: 7,
                    childAspectRatio: constraints.maxHeight < 300 ? .95 : .84,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final avatar = visible[index];
                    final selected = widget.selectedKey == avatar.key;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => widget.onSelected(avatar.key),
                        borderRadius: BorderRadius.circular(14),
                        child: Ink(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF3AA9FF).withValues(alpha: .12)
                                : Colors.black.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(14),
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
                              Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: PlayerAvatar(
                                    displayName: context.tr('sudoku_player'),
                                    avatarKey: avatar.key,
                                    radius: 27,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                context.tr('avatar_number', <Object>[
                                  avatar.number.toString().padLeft(2, '0'),
                                ]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(
                                    alpha: selected ? .94 : .64,
                                  ),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (pageCount > 1)
                _Pager(
                  page: page,
                  pageCount: pageCount,
                  onPrevious: page > 0
                      ? () => setState(() => _page = page - 1)
                      : null,
                  onNext: page < pageCount - 1
                      ? () => setState(() => _page = page + 1)
                      : null,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FrameTab extends StatefulWidget {
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
  State<_FrameTab> createState() => _FrameTabState();
}

class _FrameTabState extends State<_FrameTab> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final rewards = <String, RankRewardState>{
      for (final reward in widget.profile.rankRewards) reward.rankKey: reward,
    };
    final frames = <String>['auto', ...rankTierCatalog.map((tier) => tier.key)];

    return LayoutBuilder(
      builder: (context, constraints) {
        final pageSize = constraints.maxHeight < 300
            ? 2
            : constraints.maxHeight < 430
            ? 3
            : 4;
        final pageCount = (frames.length / pageSize).ceil();
        final page = _page.clamp(0, pageCount - 1);
        final start = page * pageSize;
        final end = (start + pageSize).clamp(0, frames.length);
        final visible = frames.sublist(start, end);

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Column(
            children: [
              if (constraints.maxHeight >= 390) ...[
                _InfoCard(
                  icon: Icons.paid_rounded,
                  title: context.tr('lifetime_rank_coins', <Object>[
                    widget.profile.totalLifetimeRankReward,
                  ]),
                  body: context.tr('rank_frames_info'),
                  compact: true,
                ),
                const SizedBox(height: 6),
              ],
              Expanded(
                child: Column(
                  children: [
                    for (var index = 0; index < visible.length; index++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: index == visible.length - 1 ? 0 : 6,
                          ),
                          child: _FrameTile(
                            keyValue: visible[index],
                            profile: widget.profile,
                            avatarKey: widget.avatarKey,
                            selectedKey: widget.selectedKey,
                            reward:
                                rewards[rankTierForKey(
                                  visible[index] == 'auto'
                                      ? widget.profile.rankKey
                                      : visible[index],
                                ).key],
                            onSelected: widget.onSelected,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (pageCount > 1)
                _Pager(
                  page: page,
                  pageCount: pageCount,
                  onPrevious: page > 0
                      ? () => setState(() => _page = page - 1)
                      : null,
                  onNext: page < pageCount - 1
                      ? () => setState(() => _page = page + 1)
                      : null,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FrameTile extends StatelessWidget {
  const _FrameTile({
    required this.keyValue,
    required this.profile,
    required this.avatarKey,
    required this.selectedKey,
    required this.reward,
    required this.onSelected,
  });

  final String keyValue;
  final RankIdentityProfile profile;
  final String avatarKey;
  final String selectedKey;
  final RankRewardState? reward;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final auto = keyValue == 'auto';
    final tier = auto
        ? rankTierForKey(profile.rankKey)
        : rankTierForKey(keyValue);
    final unlocked = auto || profile.unlockedFrameKeys.contains(tier.key);
    final selected = selectedKey == keyValue;
    final previewFrame = auto ? profile.rankKey : tier.key;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: unlocked ? () => onSelected(keyValue) : null,
        borderRadius: BorderRadius.circular(15),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF3AA9FF).withValues(alpha: .11)
                : Colors.black.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(15),
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
                radius: 24,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auto ? context.tr('auto_current_rank') : tier.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: unlocked
                            ? Colors.white
                            : Colors.white.withValues(alpha: .42),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      auto
                          ? context.tr('frame_follows_current_rank')
                          : unlocked
                          ? context.tr('permanently_unlocked_rp', <Object>[
                              tier.minPoints,
                            ])
                          : context.tr('unlock_reaching_rp', <Object>[
                              tier.minPoints,
                            ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .48),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (reward != null && reward!.amount > 0) ...[
                const SizedBox(width: 5),
                _CoinPill(reward: reward!),
              ],
              const SizedBox(width: 5),
              Icon(
                unlocked
                    ? selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded
                    : Icons.lock_rounded,
                size: 20,
                color: unlocked
                    ? const Color(0xFF66C7FF)
                    : Colors.white.withValues(alpha: .28),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DecorationTab extends StatefulWidget {
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
  State<_DecorationTab> createState() => _DecorationTabState();
}

class _DecorationTabState extends State<_DecorationTab> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final decorations = widget.profile.decorations;
    return LayoutBuilder(
      builder: (context, constraints) {
        final pageSize = constraints.maxHeight < 300
            ? 2
            : constraints.maxHeight < 430
            ? 3
            : 4;
        final pageCount = decorations.isEmpty
            ? 1
            : (decorations.length / pageSize).ceil();
        final page = _page.clamp(0, pageCount - 1);
        final start = page * pageSize;
        final end = (start + pageSize).clamp(0, decorations.length);
        final visible = decorations.sublist(start, end);

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Column(
            children: [
              if (constraints.maxHeight >= 390) ...[
                _InfoCard(
                  icon: Icons.workspace_premium_rounded,
                  title: context.tr('three_achievement_slots'),
                  body: context.tr('achievement_badges_info'),
                  compact: true,
                ),
                const SizedBox(height: 6),
              ],
              Expanded(
                child: visible.isEmpty
                    ? const SizedBox.shrink()
                    : Column(
                        children: [
                          for (var index = 0; index < visible.length; index++)
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  bottom: index == visible.length - 1 ? 0 : 6,
                                ),
                                child: _DecorationTile(
                                  decoration: visible[index],
                                  profile: widget.profile,
                                  avatarKey: widget.avatarKey,
                                  selected: widget.selectedAchievementIds
                                      .contains(visible[index].achievementId),
                                  onToggle: widget.onToggle,
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              if (pageCount > 1)
                _Pager(
                  page: page,
                  pageCount: pageCount,
                  onPrevious: page > 0
                      ? () => setState(() => _page = page - 1)
                      : null,
                  onNext: page < pageCount - 1
                      ? () => setState(() => _page = page + 1)
                      : null,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DecorationTile extends StatelessWidget {
  const _DecorationTile({
    required this.decoration,
    required this.profile,
    required this.avatarKey,
    required this.selected,
    required this.onToggle,
  });

  final RankDecoration decoration;
  final RankIdentityProfile profile;
  final String avatarKey;
  final bool selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final enabled = decoration.unlocked;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? () => onToggle(decoration.achievementId) : null,
        borderRadius: BorderRadius.circular(15),
        child: Ink(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFB7A9FF).withValues(alpha: .11)
                : Colors.black.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(15),
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
                radius: 23,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.tr(decoration.title),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: enabled
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: .46),
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        _RarityPill(rarity: decoration.rarity),
                      ],
                    ),
                    Text(
                      context.tr(decoration.description),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .50),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                !enabled
                    ? Icons.lock_rounded
                    : selected
                    ? Icons.check_circle_rounded
                    : Icons.add_circle_outline_rounded,
                size: 20,
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
  }
}

class _TitleTab extends StatefulWidget {
  const _TitleTab({
    required this.profile,
    required this.selectedKey,
    required this.onSelected,
  });

  final RankIdentityProfile profile;
  final String selectedKey;
  final ValueChanged<String> onSelected;

  @override
  State<_TitleTab> createState() => _TitleTabState();
}

class _TitleTabState extends State<_TitleTab> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final options = <RankTitleOption>[
      const RankTitleOption(key: '', label: 'no_title'),
      ...widget.profile.unlockedTitles,
    ];

    return _SimplePagedList<RankTitleOption>(
      items: options,
      page: _page,
      onPageChanged: (value) => setState(() => _page = value),
      itemBuilder: (context, option) {
        final selected = widget.selectedKey == option.key;
        return ListTile(
          dense: true,
          onTap: () => widget.onSelected(option.key),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
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
          ),
          title: Text(
            context.tr(option.label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: selected ? const Icon(Icons.check_circle_rounded) : null,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 320;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!compact) ...[
                _InfoCard(
                  icon: Icons.public_rounded,
                  title: context.tr('country_flag'),
                  body: context.tr('country_flag_info'),
                  compact: true,
                ),
                const SizedBox(height: 7),
              ],
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _chooseCountry(context),
                  borderRadius: BorderRadius.circular(15),
                  child: Ink(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .06),
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 38,
                          child: Text(
                            selected?.flag ?? '🌐',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selected == null
                                    ? context.tr('choose_country')
                                    : context.tr(
                                        'country_name_${selected.code.toLowerCase()}',
                                      ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                selected == null
                                    ? context.tr('no_country_flag_until_chosen')
                                    : context.tr('flag_before_player_name'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .48),
                                  fontSize: 10,
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
              if (selected != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => onCountryChanged(null),
                    icon: const Icon(Icons.close_rounded, size: 17),
                    label: Text(context.tr('clear_country')),
                  ),
                ),
              const SizedBox(height: 3),
              SwitchListTile.adaptive(
                dense: compact,
                value: flagVisible,
                onChanged: selected == null ? null : onVisibilityChanged,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(color: Colors.white.withValues(alpha: .06)),
                ),
                tileColor: Colors.black.withValues(alpha: .14),
                secondary: Icon(
                  Icons.flag_rounded,
                  color: selected == null
                      ? Colors.white.withValues(alpha: .28)
                      : const Color(0xFF66C7FF),
                ),
                title: Text(
                  context.tr('show_flag_ranked_ladder'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                subtitle: Text(
                  selected == null
                      ? context.tr('choose_country_first')
                      : flagVisible
                      ? context.tr('flag_only_before_name')
                      : context.tr('country_saved_flag_hidden'),
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .50),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final choices = query.isEmpty
        ? countryOptions
        : countryOptions
              .where(
                (country) => context
                    .tr('country_name_${country.code.toLowerCase()}')
                    .toLowerCase()
                    .contains(query),
              )
              .toList(growable: false);

    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pageSize = constraints.maxHeight < 500 ? 4 : 6;
          final pageCount = choices.isEmpty
              ? 1
              : (choices.length / pageSize).ceil();
          final page = _page.clamp(0, pageCount - 1);
          final start = page * pageSize;
          final end = (start + pageSize).clamp(0, choices.length);
          final visible = choices.sublist(start, end);

          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.tr('choose_country'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                TextField(
                  autofocus: true,
                  onChanged: (value) => setState(() {
                    _query = value;
                    _page = 0;
                  }),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: context.tr('search_country'),
                    prefixIcon: const Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 7),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Text(
                            context.tr('no_country_found'),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .55),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            for (var index = 0; index < visible.length; index++)
                              Expanded(
                                child: _CountryChoiceTile(
                                  country: visible[index],
                                ),
                              ),
                          ],
                        ),
                ),
                if (pageCount > 1)
                  _Pager(
                    page: page,
                    pageCount: pageCount,
                    onPrevious: page > 0
                        ? () => setState(() => _page = page - 1)
                        : null,
                    onNext: page < pageCount - 1
                        ? () => setState(() => _page = page + 1)
                        : null,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CountryChoiceTile extends StatelessWidget {
  const _CountryChoiceTile({required this.country});

  final CountryOption country;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      onTap: () => Navigator.of(context).pop(country),
      leading: SizedBox(
        width: 34,
        child: Text(
          country.flag,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22),
        ),
      ),
      title: Text(
        context.tr('country_name_${country.code.toLowerCase()}'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
    );
  }
}

class _SimplePagedList<T> extends StatelessWidget {
  const _SimplePagedList({
    required this.items,
    required this.page,
    required this.onPageChanged,
    required this.itemBuilder,
  });

  final List<T> items;
  final int page;
  final ValueChanged<int> onPageChanged;
  final Widget Function(BuildContext context, T item) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pageSize = constraints.maxHeight < 300 ? 2 : 4;
        final pageCount = items.isEmpty ? 1 : (items.length / pageSize).ceil();
        final safePage = page.clamp(0, pageCount - 1);
        final start = safePage * pageSize;
        final end = (start + pageSize).clamp(0, items.length);
        final visible = items.sublist(start, end);
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  children: [
                    for (var index = 0; index < visible.length; index++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: index == visible.length - 1 ? 0 : 6,
                          ),
                          child: itemBuilder(context, visible[index]),
                        ),
                      ),
                  ],
                ),
              ),
              if (pageCount > 1)
                _Pager(
                  page: safePage,
                  pageCount: pageCount,
                  onPrevious: safePage > 0
                      ? () => onPageChanged(safePage - 1)
                      : null,
                  onNext: safePage < pageCount - 1
                      ? () => onPageChanged(safePage + 1)
                      : null,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final int pageCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).previousPageTooltip,
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Text(
              '${page + 1} / $pageCount',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).nextPageTooltip,
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
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
    required this.compact,
  });

  final bool serverReady;
  final bool saving;
  final VoidCallback onSave;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, compact ? 5 : 8, 12, compact ? 6 : 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1215).withValues(alpha: .96),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: .06)),
        ),
      ),
      child: Row(
        children: [
          if (!compact)
            Expanded(
              child: Text(
                serverReady
                    ? context.tr('profile_save_ready_info')
                    : context.tr('profile_preview_reconnect'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .56),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 8),
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
                  ? context.tr('saving')
                  : serverReady
                  ? context.tr('save')
                  : context.tr('preview'),
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
    required this.compact,
  });

  final String message;
  final bool busy;
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 11,
        vertical: compact ? 6 : 9,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB454).withValues(alpha: .09),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: const Color(0xFFFFB454).withValues(alpha: .22),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            color: Color(0xFFFFC66B),
            size: 18,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .72),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: context.tr('retry'),
            onPressed: busy ? null : onRetry,
            icon: busy
                ? const SizedBox.square(
                    dimension: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 19),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.compact,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 8 : 13),
      decoration: BoxDecoration(
        color: const Color(0xFF3AA9FF).withValues(alpha: .075),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF3AA9FF).withValues(alpha: .17),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF66C7FF), size: compact ? 19 : 24),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  body,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .55),
                    fontSize: 9,
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: reward.claimed
            ? const Color(0xFF29D398).withValues(alpha: .10)
            : const Color(0xFFFFC94D).withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${context.tr('coin_amount', <Object>[reward.amount])}${reward.claimed ? ' ✓' : ''}',
        maxLines: 1,
        style: TextStyle(
          color: reward.claimed
              ? const Color(0xFF69E5BA)
              : const Color(0xFFFFD86A),
          fontSize: 8,
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        context.tr('rarity_${rarity.toLowerCase()}'),
        maxLines: 1,
        style: TextStyle(
          color: color,
          fontSize: 7,
          fontWeight: FontWeight.w900,
          letterSpacing: .3,
        ),
      ),
    );
  }
}
