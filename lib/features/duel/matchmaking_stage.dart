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

class MatchmakingStage extends StatefulWidget {
  const MatchmakingStage({
    super.key,
    required this.currentPlayer,
    required this.actionLabel,
    required this.actionIcon,
    this.opponent,
    this.searching = true,
    this.actionBusy = false,
    this.onAction,
    this.onClose,
    this.searchStatus,
    this.opponentStatus,
    this.opponentReady = false,
  });

  final MatchmakingVisualPlayer currentPlayer;
  final MatchmakingVisualPlayer? opponent;
  final bool searching;
  final bool actionBusy;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;
  final VoidCallback? onClose;
  final String? searchStatus;
  final String? opponentStatus;
  final bool opponentReady;

  bool get matched => opponent != null;

  @override
  State<MatchmakingStage> createState() => _MatchmakingStageState();
}

class _MatchmakingStageState extends State<MatchmakingStage>
    with TickerProviderStateMixin {
  late final AnimationController _introController;
  late final AnimationController _energyController;
  late final AnimationController _matchController;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 440),
    )..forward();
    _energyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2300),
    )..repeat();
    _matchController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
      value: widget.matched ? 1 : 0,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.of(context).disableAnimations;
    if (_reduceMotion == reduce) return;
    _reduceMotion = reduce;
    if (reduce) {
      _energyController.stop();
      _energyController.value = .18;
      if (_introController.isAnimating) _introController.value = 1;
      if (widget.matched) _matchController.value = 1;
    } else if (!_energyController.isAnimating) {
      _energyController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant MatchmakingStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.matched && widget.matched) {
      if (_reduceMotion) {
        _matchController.value = 1;
      } else {
        _matchController.forward(from: 0);
      }
    } else if (oldWidget.matched && !widget.matched) {
      _matchController.value = 0;
    }
  }

  @override
  void dispose() {
    _introController.dispose();
    _energyController.dispose();
    _matchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerEntrance = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0, .82, curve: Curves.easeOutCubic),
    );
    final opponentEntrance = CurvedAnimation(
      parent: _introController,
      curve: const Interval(.14, 1, curve: Curves.easeOutCubic),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF061424),
      body: AppBackdrop(
        dim: .24,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  final compact = size.height < 710;
                  final cardWidth = (size.width * .43).clamp(158.0, 244.0);
                  final cardHeight = compact ? 226.0 : 250.0;
                  final playerTop = compact
                      ? size.height * .105
                      : size.height * .13;
                  final opponentTop = compact
                      ? size.height * .43
                      : size.height * .47;
                  final horizontalInset = (size.width * .055).clamp(12.0, 34.0);

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: AnimatedBuilder(
                            animation: Listenable.merge(<Listenable>[
                              _energyController,
                              _matchController,
                              _introController,
                            ]),
                            builder: (context, _) {
                              return CustomPaint(
                                painter: _MatchmakingEnergyPainter(
                                  progress: _energyController.value,
                                  introProgress: _introController.value,
                                  matchProgress: _matchController.value,
                                  matched: widget.matched,
                                  reducedMotion: _reduceMotion,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      if (widget.onClose != null)
                        Positioned(
                          left: 12,
                          top: 6,
                          child: _CloseButton(onPressed: widget.onClose!),
                        ),
                      Positioned(
                        left: horizontalInset,
                        top: playerTop,
                        width: cardWidth,
                        height: cardHeight,
                        child: _EntranceMotion(
                          animation: playerEntrance,
                          from: const Offset(-12, -8),
                          child: _PlayerCard(
                            player: widget.currentPlayer,
                            semanticLabel: context.tr('you'),
                          ),
                        ),
                      ),
                      Positioned(
                        right: horizontalInset,
                        top: opponentTop,
                        width: cardWidth,
                        height: cardHeight,
                        child: _EntranceMotion(
                          animation: opponentEntrance,
                          from: const Offset(12, 8),
                          child: _OpponentCard(
                            opponent: widget.opponent,
                            matchAnimation: _matchController,
                            searchAnimation: _energyController,
                            searchStatus: widget.searchStatus,
                            opponentStatus: widget.opponentStatus,
                            opponentReady: widget.opponentReady,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 18,
                        right: 18,
                        bottom: compact ? 12 : 18,
                        child: FadeTransition(
                          opacity: CurvedAnimation(
                            parent: _introController,
                            curve: const Interval(.36, 1, curve: Curves.easeOut),
                          ),
                          child: _MatchmakingActionButton(
                            label: widget.actionLabel,
                            icon: widget.actionIcon,
                            busy: widget.actionBusy,
                            onPressed: widget.onAction,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EntranceMotion extends AnimatedWidget {
  const _EntranceMotion({
    required Animation<double> animation,
    required this.from,
    required this.child,
  }) : super(listenable: animation);

  final Offset from;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animation = listenable as Animation<double>;
    final t = animation.value;
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(from.dx * (1 - t), from.dy * (1 - t)),
        child: Transform.scale(
          scale: .97 + (.03 * t),
          child: child,
        ),
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({required this.player, required this.semanticLabel});

  final MatchmakingVisualPlayer player;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$semanticLabel, ${player.displayName}',
      child: _CardShell(
        child: Column(
          children: [
            _AvatarRing(player: player),
            const SizedBox(height: 9),
            Text(
              player.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: -.2,
              ),
            ),
            const SizedBox(height: 5),
            _RankLine(label: player.rankLabel),
            const Spacer(),
            Divider(color: Colors.white.withValues(alpha: .12), height: 1),
            const SizedBox(height: 10),
            _StatsRow(player: player),
          ],
        ),
      ),
    );
  }
}

class _OpponentCard extends StatelessWidget {
  const _OpponentCard({
    required this.opponent,
    required this.matchAnimation,
    required this.searchAnimation,
    required this.searchStatus,
    required this.opponentStatus,
    required this.opponentReady,
  });

  final MatchmakingVisualPlayer? opponent;
  final Animation<double> matchAnimation;
  final Animation<double> searchAnimation;
  final String? searchStatus;
  final String? opponentStatus;
  final bool opponentReady;

  @override
  Widget build(BuildContext context) {
    final matched = opponent != null;
    return Semantics(
      container: true,
      label: matched
          ? '${context.tr('opponent')}, ${opponent!.displayName}'
          : context.tr('searching_opponent'),
      child: _CardShell(
        child: AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[
            matchAnimation,
            searchAnimation,
          ]),
          builder: (context, _) {
            final reveal = matched
                ? Curves.easeOutCubic.transform(
                    ((matchAnimation.value - .24) / .76).clamp(0.0, 1.0),
                  )
                : 0.0;
            return Stack(
              fit: StackFit.expand,
              children: [
                IgnorePointer(
                  child: Opacity(
                    opacity: matched ? 1 - reveal : 1,
                    child: _SearchingOpponentContent(
                      animationValue: searchAnimation.value,
                      status: searchStatus,
                    ),
                  ),
                ),
                if (matched)
                  Opacity(
                    opacity: reveal,
                    child: Transform.translate(
                      offset: Offset(0, 6 * (1 - reveal)),
                      child: Transform.scale(
                        scale: .91 + (.09 * reveal),
                        child: _MatchedOpponentContent(
                          player: opponent!,
                          status: opponentStatus,
                          ready: opponentReady,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SearchingOpponentContent extends StatelessWidget {
  const _SearchingOpponentContent({
    required this.animationValue,
    required this.status,
  });

  final double animationValue;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final breathe = 1 + .025 * ((math.sin(animationValue * math.pi * 2) + 1) / 2);
    return Column(
      children: [
        Transform.scale(
          scale: breathe,
          child: Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0B1A31),
              border: Border.all(
                color: const Color(0xFF64B5FF).withValues(alpha: .78),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3A7BFF).withValues(alpha: .22),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(
              Icons.person_search_rounded,
              color: Color(0xFF8EB8FF),
              size: 38,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          context.tr('searching_opponent'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            height: 1.05,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        _SearchingStatus(
          animationValue: animationValue,
          status: status ?? context.tr('searching_opponent_short'),
        ),
        const Spacer(),
        Divider(color: Colors.white.withValues(alpha: .12), height: 1),
        const SizedBox(height: 10),
        const _UnknownStatsRow(),
      ],
    );
  }
}

class _MatchedOpponentContent extends StatelessWidget {
  const _MatchedOpponentContent({
    required this.player,
    required this.status,
    required this.ready,
  });

  final MatchmakingVisualPlayer player;
  final String? status;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _AvatarRing(player: player, cyan: true),
        const SizedBox(height: 9),
        Text(
          player.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: -.2,
          ),
        ),
        const SizedBox(height: 5),
        _RankLine(label: player.rankLabel, cyan: true),
        const Spacer(),
        Divider(color: Colors.white.withValues(alpha: .12), height: 1),
        const SizedBox(height: 10),
        _StatsRow(player: player),
        const SizedBox(height: 7),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              ready ? Icons.check_circle_rounded : Icons.link_rounded,
              color: ready
                  ? const Color(0xFF39D98A)
                  : const Color(0xFF66C7FF),
              size: 16,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                status ?? (ready ? context.tr('ready') : context.tr('connected')),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ready
                      ? const Color(0xFF39D98A)
                      : const Color(0xFF66C7FF),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF14233A).withValues(alpha: .94),
            const Color(0xFF071525).withValues(alpha: .95),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF63A9FF).withValues(alpha: .56),
          width: 1.15,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF238CFF).withValues(alpha: .13),
            blurRadius: 18,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: .30),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        child: child,
      ),
    );
  }
}

class _AvatarRing extends StatelessWidget {
  const _AvatarRing({required this.player, this.cyan = false});

  final MatchmakingVisualPlayer player;
  final bool cyan;

  @override
  Widget build(BuildContext context) {
    final accent = cyan ? const Color(0xFF61C8FF) : const Color(0xFF8A7DFF);
    return Container(
      width: 74,
      height: 74,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accent.withValues(alpha: .9), width: 2),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: .22),
            blurRadius: 15,
            spreadRadius: 1,
          ),
        ],
      ),
      child: PlayerAvatar(
        displayName: player.displayName,
        avatarKey: player.avatarKey,
        remoteApprovedImageUrl: player.remoteApprovedImageUrl,
        radius: 32,
        semanticLabel: context.tr(
          'player_avatar_semantics',
          <Object>[player.displayName],
        ),
      ),
    );
  }
}

class _RankLine extends StatelessWidget {
  const _RankLine({this.label, this.cyan = false});

  final String? label;
  final bool cyan;

  @override
  Widget build(BuildContext context) {
    final text = label?.trim();
    final accent = cyan ? const Color(0xFF69CCFF) : const Color(0xFF9B8DFF);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.diamond_rounded, size: 14, color: accent),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text == null || text.isEmpty ? context.tr('rank') : text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.player});

  final MatchmakingVisualPlayer player;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Stat(
            value: player.gamesPlayed?.toString() ?? '—',
            label: context.tr('match_type'),
          ),
        ),
        Expanded(
          child: _Stat(
            value: player.winRate == null
                ? '—'
                : '${(player.winRate!.clamp(0, 1) * 100).round()}%',
            label: context.tr('win_rate'),
          ),
        ),
        Expanded(
          child: _Stat(
            value: player.rating?.toString() ?? '—',
            label: 'RP',
            accent: const Color(0xFFB29AFF),
          ),
        ),
      ],
    );
  }
}

class _UnknownStatsRow extends StatelessWidget {
  const _UnknownStatsRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _Stat(value: '—', label: context.tr('match_type'))),
        Expanded(child: _Stat(value: '—', label: context.tr('win_rate'))),
        const Expanded(child: _Stat(value: '—', label: 'RP')),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.accent});

  final String value;
  final String label;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              color: accent ?? Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .58),
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SearchingStatus extends StatelessWidget {
  const _SearchingStatus({required this.animationValue, required this.status});

  final double animationValue;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 3; i++) ...[
          Opacity(
            opacity: _dotOpacity(animationValue, i),
            child: const Text(
              '•',
              style: TextStyle(
                color: Color(0xFF59C7FF),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (i != 2) const SizedBox(width: 1),
        ],
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            status,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF65C9FF),
              fontSize: 10.5,
              height: 1.1,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  double _dotOpacity(double t, int index) {
    final phase = (t + index * .18) % 1;
    return .22 + .78 * ((math.sin(phase * math.pi * 2) + 1) / 2);
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: MaterialLocalizations.of(context).closeButtonTooltip,
      child: IconButton(
        onPressed: onPressed,
        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFF10304D).withValues(alpha: .92),
          foregroundColor: Colors.white,
          fixedSize: const Size(52, 52),
          shape: const CircleBorder(),
        ),
        icon: const Icon(Icons.close_rounded, size: 30),
      ),
    );
  }
}

class _MatchmakingActionButton extends StatefulWidget {
  const _MatchmakingActionButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  State<_MatchmakingActionButton> createState() =>
      _MatchmakingActionButtonState();
}

class _MatchmakingActionButtonState extends State<_MatchmakingActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: AnimatedScale(
        scale: _pressed && enabled ? .975 : 1,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTapUp: enabled
              ? (_) {
                  setState(() => _pressed = false);
                  widget.onPressed?.call();
                }
              : null,
          child: AnimatedOpacity(
            opacity: enabled ? 1 : .62,
            duration: const Duration(milliseconds: 160),
            child: Container(
              height: 66,
              constraints: const BoxConstraints(maxWidth: 620),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF372064).withValues(alpha: .66),
                    const Color(0xFF10213D).withValues(alpha: .90),
                  ],
                ),
                borderRadius: BorderRadius.circular(19),
                border: Border.all(
                  color: const Color(0xFF8F67FF).withValues(alpha: .92),
                  width: 1.6,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7C48FF).withValues(alpha: .28),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: const Color(0xFF268BFF).withValues(alpha: .14),
                    blurRadius: 22,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: Container(
                      key: ValueKey<Object>(widget.busy ? 'busy' : widget.icon),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF87A8FF).withValues(alpha: .92),
                          width: 1.5,
                        ),
                      ),
                      child: widget.busy
                          ? const Padding(
                              padding: EdgeInsets.all(9),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF8FCBFF),
                              ),
                            )
                          : Icon(widget.icon, color: const Color(0xFFA9C5FF), size: 22),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Flexible(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        widget.label,
                        key: ValueKey<String>(widget.label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MatchmakingEnergyPainter extends CustomPainter {
  const _MatchmakingEnergyPainter({
    required this.progress,
    required this.introProgress,
    required this.matchProgress,
    required this.matched,
    required this.reducedMotion,
  });

  final double progress;
  final double introProgress;
  final double matchProgress;
  final bool matched;
  final bool reducedMotion;

  static const List<double> _zig = <double>[
    0,
    .42,
    -.22,
    .52,
    -.48,
    .18,
    -.30,
    .44,
    -.16,
    .28,
    0,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final intro = Curves.easeOutCubic.transform(
      ((introProgress - .26) / .74).clamp(0.0, 1.0),
    );
    if (intro <= 0) return;

    final start = Offset(size.width * .43, size.height * .34);
    final end = Offset(size.width * .57, size.height * .58);
    final delta = end - start;
    final length = math.max(1.0, delta.distance);
    final normal = Offset(-delta.dy / length, delta.dx / length);
    final jitter = reducedMotion ? 0.0 : (matched ? 1.1 : 3.0);
    final flash = math.sin(matchProgress.clamp(0, 1) * math.pi);
    final path = Path();
    final points = <Offset>[];

    for (var i = 0; i < _zig.length; i++) {
      final t = i / (_zig.length - 1);
      final base = Offset.lerp(start, end, t)!;
      final fixed = normal * (_zig[i] * 18);
      final animated = normal *
          (math.sin(progress * math.pi * 2 + i * 1.37) * jitter);
      final point = base + fixed + animated;
      points.add(point);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }

    final brightness = .76 + .16 * ((math.sin(progress * math.pi * 2) + 1) / 2);
    final visible = intro.clamp(0.0, 1.0);
    final outer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 13 + flash * 5
      ..color = const Color(0xFF7B42FF).withValues(
        alpha: (.12 + flash * .10) * visible,
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    final middle = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 5.2 + flash * 1.8
      ..color = Color.lerp(
        const Color(0xFF7247FF),
        const Color(0xFF4EA8FF),
        .46,
      )!.withValues(alpha: (.54 + flash * .18) * brightness * visible)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.2);
    final core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 1.8 + flash * 1.0
      ..color = const Color(0xFFE7F5FF).withValues(
        alpha: (.86 + flash * .14) * visible,
      );

    canvas.drawPath(path, outer);
    canvas.drawPath(path, middle);
    canvas.drawPath(path, core);

    if (!reducedMotion) {
      _drawBranches(canvas, points, normal, visible, flash);
      _drawParticles(canvas, start, delta, normal, visible);
    }

    final center = Offset.lerp(start, end, .5)! + normal * -1.5;
    _drawCore(canvas, center, visible, flash);
    _drawRings(canvas, center, visible, flash);
  }

  void _drawBranches(
    Canvas canvas,
    List<Offset> points,
    Offset normal,
    double visible,
    double flash,
  ) {
    const indices = <int>[2, 4, 7, 8];
    for (var j = 0; j < indices.length; j++) {
      final index = indices[j];
      final flicker = math.pow(
        ((math.sin(progress * math.pi * 4 + j * 2.1) + 1) / 2),
        5,
      ).toDouble();
      final alpha = (.08 + flicker * .44 + flash * .12) * visible;
      if (alpha < .10) continue;
      final anchor = points[index];
      final sign = j.isEven ? 1.0 : -1.0;
      final end = anchor + normal * (sign * (14 + j * 3)) + Offset(4 * sign, -7);
      final p = Path()
        ..moveTo(anchor.dx, anchor.dy)
        ..lineTo(end.dx, end.dy);
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.1
          ..color = const Color(0xFFB8D8FF).withValues(alpha: alpha),
      );
    }
  }

  void _drawParticles(
    Canvas canvas,
    Offset start,
    Offset delta,
    Offset normal,
    double visible,
  ) {
    final count = matched ? 8 : 14;
    for (var i = 0; i < count; i++) {
      final t = (i / count + progress * .075) % 1;
      final base = start + delta * t;
      final drift = math.sin(i * 1.73 + progress * math.pi * 2) * (8 + (i % 3) * 3);
      final point = base + normal * drift + Offset(math.sin(i * 2.2) * 5, 0);
      final pulse = .35 + .65 * ((math.sin(progress * math.pi * 2 + i) + 1) / 2);
      canvas.drawCircle(
        point,
        i % 4 == 0 ? 1.4 : .8,
        Paint()
          ..color = (i.isEven
                  ? const Color(0xFF79BFFF)
                  : const Color(0xFFB077FF))
              .withValues(alpha: .45 * pulse * visible),
      );
    }
  }

  void _drawCore(Canvas canvas, Offset center, double visible, double flash) {
    final breathing = .88 + .12 * ((math.sin(progress * math.pi * 2) + 1) / 2);
    final radius = (5.5 + flash * 8) * breathing;
    canvas.drawCircle(
      center,
      radius * 3.2,
      Paint()
        ..color = const Color(0xFF5E7DFF).withValues(
          alpha: (.08 + flash * .12) * visible,
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13),
    );
    canvas.drawCircle(
      center,
      radius * 1.6,
      Paint()
        ..color = const Color(0xFF6CC7FF).withValues(
          alpha: (.22 + flash * .16) * visible,
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFFF4FBFF).withValues(
          alpha: (.88 + flash * .12) * visible,
        ),
    );
  }

  void _drawRings(Canvas canvas, Offset center, double visible, double flash) {
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final cycles = reducedMotion ? 1 : 3;
    for (var i = 0; i < cycles; i++) {
      final phase = reducedMotion ? .36 : (progress + i / cycles) % 1;
      final radius = 14 + phase * 42 + flash * 12;
      ringPaint.color = const Color(0xFF6FAEFF).withValues(
        alpha: (1 - phase) * .25 * visible + flash * .10 * visible,
      );
      canvas.drawCircle(center, radius, ringPaint);
    }
    if (flash > .01) {
      final shockRadius = 18 + matchProgress * 74;
      canvas.drawCircle(
        center,
        shockRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0xFFA783FF).withValues(
            alpha: (1 - matchProgress) * .48 * visible,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MatchmakingEnergyPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.introProgress != introProgress ||
        oldDelegate.matchProgress != matchProgress ||
        oldDelegate.matched != matched ||
        oldDelegate.reducedMotion != reducedMotion;
  }
}
