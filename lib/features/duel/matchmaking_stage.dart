import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../localization/app_strings.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/player_avatar.dart';

class MatchmakingVisualPlayer {
  const MatchmakingVisualPlayer({
    required this.displayName,
    this.avatarKey = 'default',
    this.remoteApprovedImageUrl,
    this.rankLabel,
    this.gamesPlayed,
    this.winRate,
    this.rating,
  });

  final String displayName;
  final String avatarKey;
  final String? remoteApprovedImageUrl;
  final String? rankLabel;
  final int? gamesPlayed;
  final double? winRate;
  final int? rating;

  MatchmakingVisualPlayer copyWith({
    String? displayName,
    String? avatarKey,
    String? remoteApprovedImageUrl,
    String? rankLabel,
    int? gamesPlayed,
    double? winRate,
    int? rating,
  }) {
    return MatchmakingVisualPlayer(
      displayName: displayName ?? this.displayName,
      avatarKey: avatarKey ?? this.avatarKey,
      remoteApprovedImageUrl:
          remoteApprovedImageUrl ?? this.remoteApprovedImageUrl,
      rankLabel: rankLabel ?? this.rankLabel,
      gamesPlayed: gamesPlayed ?? this.gamesPlayed,
      winRate: winRate ?? this.winRate,
      rating: rating ?? this.rating,
    );
  }
}

/// Presentation-only opponent-search stage.
///
/// Queue creation, polling, matching, cancellation and room handoff remain
/// owned by MatchmakingScreen. This widget only renders those states.
class MatchmakingStage extends StatefulWidget {
  const MatchmakingStage({
    super.key,
    required this.currentPlayer,
    required this.actionLabel,
    required this.actionIcon,
    this.difficultyLabel = 'Easy',
    this.opponent,
    this.searching = true,
    this.actionBusy = false,
    this.onAction,
    this.onClose,
    this.searchStatus,
    this.opponentStatus,
    this.opponentReady = false,
    this.floatingControl,
  });

  final MatchmakingVisualPlayer currentPlayer;
  final MatchmakingVisualPlayer? opponent;
  final String difficultyLabel;
  final bool searching;
  final bool actionBusy;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;
  final VoidCallback? onClose;
  final String? searchStatus;
  final String? opponentStatus;
  final bool opponentReady;
  final Widget? floatingControl;

  bool get matched => opponent != null;

  @override
  State<MatchmakingStage> createState() => _MatchmakingStageState();
}

class _MatchmakingStageState extends State<MatchmakingStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ambientController;

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5600),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _ambientController
        ..stop()
        ..value = .24;
    } else if (!_ambientController.isAnimating) {
      _ambientController.repeat();
    }
  }

  @override
  void dispose() {
    _ambientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050E18),
      body: AppBackdrop(
        dim: .50,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x8F04101C), Color(0xB805101A)],
            ),
          ),
          child: SafeArea(
            minimum: const EdgeInsets.only(top: 2, bottom: 2),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = constraints.maxHeight;
                final horizontalScale = (width / 390).clamp(.84, 1.10).toDouble();
                final verticalScale = (height / 800).clamp(.76, 1.06).toDouble();
                final scale = math.min(horizontalScale, verticalScale).toDouble();
                final sidePadding = (18 * horizontalScale)
                    .clamp(13.0, 22.0)
                    .toDouble();

                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        sidePadding,
                        5 * scale,
                        sidePadding,
                        7 * scale,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SearchHeader(
                            difficultyLabel: widget.difficultyLabel,
                            onBack: widget.onClose,
                            scale: scale,
                            onHelp: _showSearchInfo,
                          ),
                          SizedBox(height: 8 * scale),
                          _SearchStateLine(
                            matched: widget.matched,
                            busy: widget.actionBusy,
                            status: widget.searchStatus,
                            animation: _ambientController,
                            scale: scale,
                          ),
                          SizedBox(height: 14 * scale),
                          Expanded(
                            child: RepaintBoundary(
                              child: _ResponsiveDuelArena(
                                currentPlayer: widget.currentPlayer,
                                opponent: widget.opponent,
                                opponentReady: widget.opponentReady,
                                opponentStatus: widget.opponentStatus,
                                animation: _ambientController,
                                scale: scale,
                              ),
                            ),
                          ),
                          SizedBox(height: 13 * scale),
                          _RankSearchStatus(
                            matched: widget.matched,
                            busy: widget.actionBusy,
                            animation: _ambientController,
                            scale: scale,
                          ),
                          SizedBox(height: 12 * scale),
                          _MatchmakingActionButton(
                            label: widget.actionLabel,
                            icon: widget.actionIcon,
                            busy: widget.actionBusy,
                            matched: widget.matched,
                            onPressed: widget.onAction,
                            scale: scale,
                          ),
                          if (widget.floatingControl != null) ...[
                            SizedBox(height: 8 * scale),
                            Align(
                              alignment: Alignment.centerRight,
                              child: widget.floatingControl!,
                            ),
                          ],
                          SizedBox(height: 10 * scale),
                          _SearchTip(scale: scale),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSearchInfo() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .64),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Material(
          color: const Color(0xFF0B1825),
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Opponent search',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'We look for an available player close to your competitive level. Keep this screen open while matchmaking is active.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .68),
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.difficultyLabel,
    required this.onBack,
    required this.onHelp,
    required this.scale,
  });

  final String difficultyLabel;
  final VoidCallback? onBack;
  final VoidCallback onHelp;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final buttonSize = (46 * scale).clamp(40.0, 50.0).toDouble();
    return SizedBox(
      height: (52 * scale).clamp(46.0, 56.0).toDouble(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _HeaderButton(
              size: buttonSize,
              tooltip: context.tr('cancel'),
              onTap: onBack,
              icon: Icons.arrow_back_ios_new_rounded,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  difficultyLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: (21 * scale).clamp(18.0, 23.0).toDouble(),
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.35,
                  ),
                ),
              ),
              SizedBox(width: 5 * scale),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white.withValues(alpha: .82),
                size: (22 * scale).clamp(19.0, 24.0).toDouble(),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: _HeaderButton(
              size: buttonSize,
              tooltip: 'Matchmaking info',
              onTap: onHelp,
              icon: Icons.question_mark_rounded,
              iconSize: (19 * scale).clamp(17.0, 20.0).toDouble(),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.size,
    required this.tooltip,
    required this.onTap,
    required this.icon,
    this.iconSize = 23,
  });

  final double size;
  final String tooltip;
  final VoidCallback? onTap;
  final IconData icon;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xD60A1724),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(size * .34),
          side: BorderSide(
            color: const Color(0xFF2FB6FF).withValues(alpha: .20),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(size * .34),
          child: SizedBox.square(
            dimension: size,
            child: Icon(icon, color: Colors.white, size: iconSize),
          ),
        ),
      ),
    );
  }
}

class _SearchStateLine extends StatelessWidget {
  const _SearchStateLine({
    required this.matched,
    required this.busy,
    required this.status,
    required this.animation,
    required this.scale,
  });

  final bool matched;
  final bool busy;
  final String? status;
  final Animation<double> animation;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final wave = (math.sin(animation.value * math.pi * 2) + 1) / 2;
        final text = busy
            ? 'Cancelling search...'
            : matched
            ? 'Opponent found'
            : (status?.trim().isNotEmpty == true
                  ? status!.trim()
                  : 'Searching for opponent...');
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: (8 * scale).clamp(7.0, 9.0).toDouble(),
              height: (8 * scale).clamp(7.0, 9.0).toDouble(),
              decoration: BoxDecoration(
                color: const Color(0xFF29D398).withValues(
                  alpha: .58 + wave * .42,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF29D398).withValues(
                      alpha: .10 + wave * .12,
                    ),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            SizedBox(width: 8 * scale),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .82),
                  fontSize: (13 * scale).clamp(11.0, 14.0).toDouble(),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ResponsiveDuelArena extends StatelessWidget {
  const _ResponsiveDuelArena({
    required this.currentPlayer,
    required this.opponent,
    required this.opponentReady,
    required this.opponentStatus,
    required this.animation,
    required this.scale,
  });

  final MatchmakingVisualPlayer currentPlayer;
  final MatchmakingVisualPlayer? opponent;
  final bool opponentReady;
  final String? opponentStatus;
  final Animation<double> animation;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final arenaWidth = constraints.maxWidth;
        final arenaHeight = constraints.maxHeight;
        final visualHeight = math
            .min(arenaHeight, (352 * scale).clamp(286.0, 382.0))
            .toDouble();
        final centerGap = (arenaWidth * .05).clamp(14.0, 24.0).toDouble();
        final cardWidth = ((arenaWidth - centerGap) / 2)
            .clamp(132.0, 236.0)
            .toDouble();

        return Center(
          child: SizedBox(
            width: arenaWidth,
            height: visualHeight,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                const Positioned.fill(
                  child: CustomPaint(painter: _MatchmakingEnergyPainter()),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: cardWidth,
                    height: visualHeight,
                    child: _PlayerSearchCard(
                      player: currentPlayer,
                      scale: scale,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: cardWidth,
                    height: visualHeight,
                    child: _OpponentCard(
                      opponent: opponent,
                      opponentReady: opponentReady,
                      opponentStatus: opponentStatus,
                      animation: animation,
                      scale: scale,
                    ),
                  ),
                ),
                _VersusBadge(animation: animation, scale: scale),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlayerSearchCard extends StatelessWidget {
  const _PlayerSearchCard({required this.player, required this.scale});

  final MatchmakingVisualPlayer player;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return _DuelCardShell(
      accent: const Color(0xFF2FB6FF),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dense = constraints.maxHeight < 315;
          final veryDense = constraints.maxHeight < 270;
          final avatarRadius = math
              .min(
                constraints.maxWidth * .255,
                (43 * scale).clamp(35.0, 47.0),
              )
              .toDouble();

          return Padding(
            padding: EdgeInsets.fromLTRB(
              (12 * scale).clamp(9.0, 14.0).toDouble(),
              (18 * scale).clamp(12.0, 20.0).toDouble(),
              (12 * scale).clamp(9.0, 14.0).toDouble(),
              (15 * scale).clamp(10.0, 17.0).toDouble(),
            ),
            child: Column(
              children: [
                Spacer(flex: veryDense ? 1 : 2),
                _AvatarHalo(
                  player: player,
                  accent: const Color(0xFF2FB6FF),
                  radius: avatarRadius,
                ),
                SizedBox(height: veryDense ? 5 : 9 * scale),
                Text(
                  context.tr('you'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: veryDense
                        ? 14
                        : dense
                        ? 16
                        : (19 * scale).clamp(17.0, 20.0).toDouble(),
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.25,
                  ),
                ),
                SizedBox(height: veryDense ? 2 : 4),
                _RankLine(
                  rank: player.rankLabel,
                  scale: scale,
                  dense: dense,
                ),
                SizedBox(height: veryDense ? 2 : 4),
                _RpLine(
                  value: player.rating,
                  scale: scale,
                  dense: dense,
                ),
                Spacer(flex: veryDense ? 1 : 2),
                Divider(
                  color: const Color(0xFF47BCFF).withValues(alpha: .36),
                  height: 1,
                ),
                SizedBox(height: veryDense ? 6 : dense ? 8 : 12 * scale),
                Row(
                  children: [
                    Expanded(
                      child: _StatBlock(
                        value: '${player.gamesPlayed ?? 0}',
                        label: 'Matches',
                        scale: scale,
                        dense: dense,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: veryDense ? 25 : 34 * scale,
                      color: Colors.white.withValues(alpha: .12),
                    ),
                    Expanded(
                      child: _StatBlock(
                        value: '${(((player.winRate ?? 0) * 100).round())}%',
                        label: 'Win rate',
                        scale: scale,
                        dense: dense,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OpponentCard extends StatelessWidget {
  const _OpponentCard({
    required this.opponent,
    required this.opponentReady,
    required this.opponentStatus,
    required this.animation,
    required this.scale,
  });

  final MatchmakingVisualPlayer? opponent;
  final bool opponentReady;
  final String? opponentStatus;
  final Animation<double> animation;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 340),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: .985, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: opponent == null
          ? _ScanningOpponentCard(
              key: const ValueKey<String>('opponent-searching'),
              animation: animation,
              scale: scale,
            )
          : _FoundOpponentCard(
              key: ValueKey<String>('opponent-${opponent!.displayName}'),
              player: opponent!,
              ready: opponentReady,
              status: opponentStatus,
              scale: scale,
            ),
    );
  }
}

class _ScanningOpponentCard extends StatelessWidget {
  const _ScanningOpponentCard({
    super.key,
    required this.animation,
    required this.scale,
  });

  final Animation<double> animation;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return _DuelCardShell(
      accent: const Color(0xFFFFC94D),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dense = constraints.maxHeight < 315;
          final veryDense = constraints.maxHeight < 270;
          final radarSize = math
              .min(
                constraints.maxWidth * .60,
                (112 * scale).clamp(86.0, 120.0),
              )
              .toDouble();

          return Padding(
            padding: EdgeInsets.fromLTRB(
              (11 * scale).clamp(8.0, 13.0).toDouble(),
              (16 * scale).clamp(11.0, 18.0).toDouble(),
              (11 * scale).clamp(8.0, 13.0).toDouble(),
              (15 * scale).clamp(10.0, 17.0).toDouble(),
            ),
            child: Column(
              children: [
                Spacer(flex: veryDense ? 1 : 2),
                SizedBox.square(
                  dimension: radarSize,
                  child: _SearchRadar(animation: animation),
                ),
                SizedBox(height: veryDense ? 6 : dense ? 9 : 14 * scale),
                Text(
                  'Searching\nfor opponent',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: veryDense
                        ? 11
                        : dense
                        ? 13
                        : (16 * scale).clamp(14.0, 17.0).toDouble(),
                    height: 1.20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Spacer(flex: veryDense ? 1 : 2),
                Divider(
                  color: const Color(0xFFFFC94D).withValues(alpha: .30),
                  height: 1,
                ),
                SizedBox(height: veryDense ? 6 : dense ? 8 : 12 * scale),
                Row(
                  children: [
                    Expanded(
                      child: _StatBlock(
                        value: '--',
                        label: 'Matches',
                        scale: scale,
                        dense: dense,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: veryDense ? 25 : 34 * scale,
                      color: Colors.white.withValues(alpha: .12),
                    ),
                    Expanded(
                      child: _StatBlock(
                        value: '--',
                        label: 'Win rate',
                        scale: scale,
                        dense: dense,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FoundOpponentCard extends StatelessWidget {
  const _FoundOpponentCard({
    super.key,
    required this.player,
    required this.ready,
    required this.status,
    required this.scale,
  });

  final MatchmakingVisualPlayer player;
  final bool ready;
  final String? status;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return _DuelCardShell(
      accent: const Color(0xFFFFC94D),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dense = constraints.maxHeight < 315;
          final veryDense = constraints.maxHeight < 270;
          final avatarRadius = math
              .min(
                constraints.maxWidth * .255,
                (43 * scale).clamp(35.0, 47.0),
              )
              .toDouble();

          return Padding(
            padding: EdgeInsets.fromLTRB(
              (12 * scale).clamp(9.0, 14.0).toDouble(),
              (18 * scale).clamp(12.0, 20.0).toDouble(),
              (12 * scale).clamp(9.0, 14.0).toDouble(),
              (15 * scale).clamp(10.0, 17.0).toDouble(),
            ),
            child: Column(
              children: [
                Spacer(flex: veryDense ? 1 : 2),
                _AvatarHalo(
                  player: player,
                  accent: const Color(0xFFFFC94D),
                  radius: avatarRadius,
                ),
                SizedBox(height: veryDense ? 5 : 9 * scale),
                Text(
                  player.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: veryDense
                        ? 13
                        : dense
                        ? 15
                        : (18 * scale).clamp(16.0, 19.0).toDouble(),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: veryDense ? 2 : 4),
                _RankLine(rank: player.rankLabel, scale: scale, dense: dense),
                SizedBox(height: veryDense ? 2 : 4),
                _RpLine(value: player.rating, scale: scale, dense: dense),
                if (!veryDense) ...[
                  SizedBox(height: dense ? 3 : 6 * scale),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        ready ? Icons.check_circle_rounded : Icons.link_rounded,
                        color: const Color(0xFF29D398),
                        size: dense ? 12 : 14,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          status ?? context.tr('connected'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .58),
                            fontSize: dense ? 8 : 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                Spacer(flex: veryDense ? 1 : 2),
                Divider(
                  color: const Color(0xFFFFC94D).withValues(alpha: .30),
                  height: 1,
                ),
                SizedBox(height: veryDense ? 6 : dense ? 8 : 12 * scale),
                Row(
                  children: [
                    Expanded(
                      child: _StatBlock(
                        value: '${player.gamesPlayed ?? 0}',
                        label: 'Matches',
                        scale: scale,
                        dense: dense,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: veryDense ? 25 : 34 * scale,
                      color: Colors.white.withValues(alpha: .12),
                    ),
                    Expanded(
                      child: _StatBlock(
                        value: '${(((player.winRate ?? 0) * 100).round())}%',
                        label: 'Win rate',
                        scale: scale,
                        dense: dense,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DuelCardShell extends StatelessWidget {
  const _DuelCardShell({required this.accent, required this.child});

  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0C2134), Color(0xFF07131F)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: accent.withValues(alpha: .82), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: .15),
            blurRadius: 22,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: .44),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _AvatarHalo extends StatelessWidget {
  const _AvatarHalo({
    required this.player,
    required this.accent,
    required this.radius,
  });

  final MatchmakingVisualPlayer player;
  final Color accent;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accent.withValues(alpha: .94), width: 1.7),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: .22),
            blurRadius: 15,
          ),
        ],
      ),
      child: PlayerAvatar(
        displayName: player.displayName,
        avatarKey: player.avatarKey,
        remoteApprovedImageUrl: player.remoteApprovedImageUrl,
        radius: radius,
      ),
    );
  }
}

class _RankLine extends StatelessWidget {
  const _RankLine({required this.rank, required this.scale, required this.dense});

  final String? rank;
  final double scale;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.diamond_rounded,
          color: const Color(0xFFB894FF),
          size: dense ? 12 : (14 * scale).clamp(12.0, 15.0).toDouble(),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            rank ?? '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: const Color(0xFFC3A8FF),
              fontSize: dense ? 10 : (12 * scale).clamp(10.0, 13.0).toDouble(),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _RpLine extends StatelessWidget {
  const _RpLine({required this.value, required this.scale, required this.dense});

  final int? value;
  final double scale;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    // label: 'RP' is the visible competitive metric label.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.emoji_events_rounded,
          color: const Color(0xFF29D398),
          size: dense ? 12 : (14 * scale).clamp(12.0, 15.0).toDouble(),
        ),
        const SizedBox(width: 4),
        Text(
          '${value ?? 0} RP',
          style: TextStyle(
            color: const Color(0xFF29D398),
            fontSize: dense ? 10 : (13 * scale).clamp(11.0, 14.0).toDouble(),
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({
    required this.value,
    required this.label,
    required this.scale,
    required this.dense,
  });

  final String value;
  final String label;
  final double scale;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: dense ? 12 : (16 * scale).clamp(13.0, 17.0).toDouble(),
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: dense ? 1 : 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .56),
            fontSize: dense ? 7 : (9 * scale).clamp(8.0, 10.0).toDouble(),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SearchRadar extends StatelessWidget {
  const _SearchRadar({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final wave = (math.sin(animation.value * math.pi * 2) + 1) / 2;
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.rotate(
              angle: animation.value * math.pi * 2,
              child: const CustomPaint(
                painter: _RadarPainter(),
                child: SizedBox.expand(),
              ),
            ),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF081721).withValues(alpha: .96),
                border: Border.all(
                  color: const Color(0xFF29D398).withValues(
                    alpha: .24 + wave * .12,
                  ),
                ),
              ),
              child: const Icon(
                Icons.search_rounded,
                color: Colors.white,
                size: 27,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 3; i++) {
      final ringRadius = radius * (.42 + i * .22);
      base
        ..strokeWidth = i == 2 ? 1.1 : 1.6
        ..color = const Color(0xFF29D398).withValues(alpha: .15 + i * .05);
      canvas.drawCircle(center, ringRadius, base);
    }

    final rect = Rect.fromCircle(center: center, radius: radius * .82);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.1
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [
          Color(0x0029D398),
          Color(0xFF29D398),
          Color(0x0029D398),
        ],
        stops: [0, .5, 1],
      ).createShader(rect);
    canvas.drawArc(rect, -.7, 1.55, false, arc);

    final secondRect = Rect.fromCircle(center: center, radius: radius * .57);
    final second = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF29D398).withValues(alpha: .72);
    canvas.drawArc(secondRect, 2.2, .95, false, second);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _VersusBadge extends StatelessWidget {
  const _VersusBadge({required this.animation, required this.scale});

  final Animation<double> animation;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final wave = (math.sin(animation.value * math.pi * 2) + 1) / 2;
        final size = (58 * scale).clamp(48.0, 62.0).toDouble();
        return Transform.scale(
          scale: 1 + wave * .010,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Color(0xFF1D354A), Color(0xFF07131E)],
              ),
              border: Border.all(
                color: const Color(0xFFFFC94D).withValues(alpha: .80),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2FB6FF).withValues(
                    alpha: .12 + wave * .035,
                  ),
                  blurRadius: 17,
                  offset: const Offset(-6, 0),
                ),
                BoxShadow(
                  color: const Color(0xFFFFC94D).withValues(
                    alpha: .12 + wave * .035,
                  ),
                  blurRadius: 17,
                  offset: const Offset(6, 0),
                ),
              ],
            ),
            child: Text(
              'VS',
              style: TextStyle(
                color: const Color(0xFFFFD66B),
                fontSize: (20 * scale).clamp(17.0, 21.0).toDouble(),
                fontWeight: FontWeight.w900,
                letterSpacing: .2,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RankSearchStatus extends StatelessWidget {
  const _RankSearchStatus({
    required this.matched,
    required this.busy,
    required this.animation,
    required this.scale,
  });

  final bool matched;
  final bool busy;
  final Animation<double> animation;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final wave = (math.sin(animation.value * math.pi * 2) + 1) / 2;
        final title = busy
            ? 'Cancelling search'
            : matched
            ? 'Opponent found'
            : 'Looking for a player near your rank';
        final subtitle = busy
            ? 'Leaving the matchmaking queue...'
            : matched
            ? 'Preparing the duel...'
            : 'This may take a few seconds.';

        return Container(
          constraints: BoxConstraints(
            minHeight: (66 * scale).clamp(58.0, 72.0).toDouble(),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: (13 * scale).clamp(11.0, 15.0).toDouble(),
            vertical: (10 * scale).clamp(8.0, 12.0).toDouble(),
          ),
          decoration: BoxDecoration(
            color: const Color(0xE00A1825),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF2FB6FF).withValues(alpha: .20),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: (42 * scale).clamp(36.0, 44.0).toDouble(),
                height: (42 * scale).clamp(36.0, 44.0).toDouble(),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF0E2438),
                  border: Border.all(
                    color: const Color(0xFF2FB6FF).withValues(alpha: .35),
                  ),
                ),
                child: const Icon(
                  Icons.group_rounded,
                  color: Colors.white,
                  size: 23,
                ),
              ),
              SizedBox(width: 11 * scale),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: (13 * scale).clamp(11.0, 14.0).toDouble(),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3 * scale),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .56),
                        fontSize: (10 * scale).clamp(9.0, 11.0).toDouble(),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8 * scale),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: const Color(0xFF29D398).withValues(
                    alpha: .58 + wave * .42,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF29D398).withValues(
                        alpha: .12 + wave * .13,
                      ),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MatchmakingActionButton extends StatefulWidget {
  const _MatchmakingActionButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.matched,
    required this.onPressed,
    required this.scale,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final bool matched;
  final VoidCallback? onPressed;
  final double scale;

  @override
  State<_MatchmakingActionButton> createState() =>
      _MatchmakingActionButtonState();
}

class _MatchmakingActionButtonState extends State<_MatchmakingActionButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final danger = !widget.matched;
    final accent = danger ? const Color(0xFFFF5D55) : const Color(0xFF29D398);
    return Listener(
      onPointerDown: widget.busy || widget.onPressed == null
          ? null
          : (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? .992 : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: SizedBox(
          width: double.infinity,
          height: (54 * widget.scale).clamp(48.0, 58.0).toDouble(),
          child: OutlinedButton.icon(
            onPressed: widget.busy ? null : widget.onPressed,
            icon: widget.busy
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  )
                : Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: accent.withValues(alpha: .80)),
                    ),
                    alignment: Alignment.center,
                    child: Icon(widget.icon, size: 19),
                  ),
            label: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: (14 * widget.scale).clamp(12.0, 15.0).toDouble(),
                fontWeight: FontWeight.w900,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: accent,
              backgroundColor: const Color(0xEA07131D),
              side: BorderSide(
                color: accent.withValues(alpha: .86),
                width: 1.2,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchTip extends StatelessWidget {
  const _SearchTip({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.lightbulb_outline_rounded,
          color: const Color(0xFFFFC94D),
          size: (16 * scale).clamp(14.0, 17.0).toDouble(),
        ),
        SizedBox(width: 6 * scale),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Tip: ',
                  style: TextStyle(
                    color: Color(0xFFFFC94D),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextSpan(
                  text: 'Keep this screen open while we search.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .56),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: (10 * scale).clamp(9.0, 11.0).toDouble(),
            ),
          ),
        ),
      ],
    );
  }
}

/// Background glows only. The approved reference has no vertical separator
/// between the two cards, so this painter intentionally draws no center line.
class _MatchmakingEnergyPainter extends CustomPainter {
  const _MatchmakingEnergyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;

    final blueGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF2FB6FF).withValues(alpha: .075),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * .30, centerY),
          radius: size.width * .31,
        ),
      );
    canvas.drawRect(Offset.zero & size, blueGlow);

    final goldGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFC94D).withValues(alpha: .070),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * .70, centerY),
          radius: size.width * .31,
        ),
      );
    canvas.drawRect(Offset.zero & size, goldGlow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
