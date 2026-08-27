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
    this.floatingControl,
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
  final Widget? floatingControl;

  bool get matched => opponent != null;

  @override
  State<MatchmakingStage> createState() => _MatchmakingStageState();
}

class _MatchmakingStageState extends State<MatchmakingStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scanController;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _scanController.stop();
      _scanController.value = .35;
    } else if (!_scanController.isAnimating) {
      _scanController.repeat();
    }
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06111F),
      body: AppBackdrop(
        dim: .20,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 720;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      12,
                      compact ? 6 : 10,
                      12,
                      compact ? 8 : 12,
                    ),
                    child: Column(
                      children: [
                        _SearchTopBar(
                          onClose: widget.onClose,
                          matched: widget.matched,
                        ),
                        SizedBox(height: compact ? 8 : 12),
                        Text(
                          widget.matched
                              ? 'OPPONENT FOUND'
                              : context.tr('searching_opponent').toUpperCase(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .6,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.searchStatus ??
                              (widget.matched
                                  ? context.tr('connected')
                                  : context.tr('searching_opponent_short')),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .54),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: compact ? 8 : 12),
                        Expanded(
                          child: _SearchArena(
                            currentPlayer: widget.currentPlayer,
                            opponent: widget.opponent,
                            opponentReady: widget.opponentReady,
                            opponentStatus: widget.opponentStatus,
                            scanAnimation: _scanController,
                            compact: compact,
                          ),
                        ),
                        SizedBox(height: compact ? 8 : 11),
                        _SearchStatusBand(
                          matched: widget.matched,
                          busy: widget.actionBusy,
                          status: widget.matched
                              ? (widget.opponentStatus ?? context.tr('connected'))
                              : (widget.searchStatus ??
                                    context.tr('searching_opponent_short')),
                        ),
                        SizedBox(height: compact ? 8 : 10),
                        _SearchActionButton(
                          label: widget.actionLabel,
                          icon: widget.actionIcon,
                          busy: widget.actionBusy,
                          onPressed: widget.onAction,
                          matched: widget.matched,
                        ),
                        if (widget.floatingControl != null) ...[
                          const SizedBox(height: 7),
                          Align(
                            alignment: Alignment.centerRight,
                            child: widget.floatingControl!,
                          ),
                        ],
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
}

class _SearchTopBar extends StatelessWidget {
  const _SearchTopBar({required this.onClose, required this.matched});

  final VoidCallback? onClose;
  final bool matched;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          IconButton(
            tooltip: context.tr('cancel'),
            onPressed: onClose,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xD9142A3C),
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: .10)),
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 25),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('online_duel').toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  matched ? 'MATCH FOUND' : 'MATCHMAKING',
                  style: TextStyle(
                    color: (matched
                            ? const Color(0xFF29D398)
                            : const Color(0xFF66C7FF))
                        .withValues(alpha: .88),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
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

class _SearchArena extends StatelessWidget {
  const _SearchArena({
    required this.currentPlayer,
    required this.opponent,
    required this.opponentReady,
    required this.opponentStatus,
    required this.scanAnimation,
    required this.compact,
  });

  final MatchmakingVisualPlayer currentPlayer;
  final MatchmakingVisualPlayer? opponent;
  final bool opponentReady;
  final String? opponentStatus;
  final Animation<double> scanAnimation;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(painter: _SearchEnergyPainter()),
        ),
        Align(
          alignment: const Alignment(-.68, -.62),
          child: FractionallySizedBox(
            widthFactor: .43,
            heightFactor: compact ? .69 : .72,
            child: _SearchPlayerCard(
              player: currentPlayer,
              accent: const Color(0xFF3AA9FF),
              label: context.tr('you'),
              compact: compact,
            ),
          ),
        ),
        Align(
          alignment: const Alignment(.68, .54),
          child: FractionallySizedBox(
            widthFactor: .43,
            heightFactor: compact ? .69 : .72,
            child: opponent == null
                ? _OpponentScanningCard(
                    animation: scanAnimation,
                    compact: compact,
                  )
                : _SearchPlayerCard(
                    player: opponent!,
                    accent: const Color(0xFFFFC94D),
                    label: context.tr('opponent'),
                    compact: compact,
                    status: opponentStatus,
                    ready: opponentReady,
                  ),
          ),
        ),
        Align(
          alignment: Alignment.center,
          child: _VersusCore(
            matched: opponent != null,
            animation: scanAnimation,
            compact: compact,
          ),
        ),
      ],
    );
  }
}

class _SearchPlayerCard extends StatelessWidget {
  const _SearchPlayerCard({
    required this.player,
    required this.accent,
    required this.label,
    required this.compact,
    this.status,
    this.ready = false,
  });

  final MatchmakingVisualPlayer player;
  final Color accent;
  final String label;
  final bool compact;
  final String? status;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 13,
        compact ? 12 : 16,
        compact ? 10 : 13,
        compact ? 10 : 13,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF0162940), Color(0xF10A1624)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: .78), width: 1.35),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: .18), blurRadius: 22),
          BoxShadow(
            color: Colors.black.withValues(alpha: .36),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                color: accent.withValues(alpha: .78),
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accent, width: 2),
              boxShadow: [
                BoxShadow(color: accent.withValues(alpha: .28), blurRadius: 16),
              ],
            ),
            child: PlayerAvatar(
              displayName: player.displayName,
              avatarKey: player.avatarKey,
              remoteApprovedImageUrl: player.remoteApprovedImageUrl,
              radius: compact ? 30 : 36,
            ),
          ),
          SizedBox(height: compact ? 8 : 11),
          Text(
            player.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 14 : 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            player.rankLabel ?? '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFC3A8FF),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          Divider(color: Colors.white.withValues(alpha: .15), height: 1),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _SearchStat(
                  value: '${player.gamesPlayed ?? 0}',
                  label: 'Matches',
                ),
              ),
              Expanded(
                child: _SearchStat(
                  value: '${(((player.winRate ?? 0) * 100).round())}%',
                  label: 'Win rate',
                ),
              ),
              Expanded(
                child: _SearchStat(
                  value: '${player.rating ?? 0}',
                  label: 'RP',
                  accent: true,
                ),
              ),
            ],
          ),
          if (status != null || ready) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  ready ? Icons.check_circle_rounded : Icons.link_rounded,
                  color: ready ? const Color(0xFF29D398) : accent,
                  size: 14,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    status ?? context.tr('connected'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .62),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _OpponentScanningCard extends StatelessWidget {
  const _OpponentScanningCard({
    required this.animation,
    required this.compact,
  });

  final Animation<double> animation;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final wave = (math.sin(animation.value * math.pi * 2) + 1) / 2;
        return Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xF0152637), Color(0xF1091622)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFFFFC94D).withValues(alpha: .38 + wave * .28),
              width: 1.3,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFC94D).withValues(alpha: .08 + wave * .11),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  context.tr('opponent').toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFFFFD66B),
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const Spacer(),
              Transform.scale(
                scale: .96 + wave * .06,
                child: Container(
                  width: compact ? 70 : 82,
                  height: compact ? 70 : 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF0B1A2B),
                    border: Border.all(
                      color: const Color(0xFF66C7FF).withValues(alpha: .70),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3AA9FF).withValues(alpha: .18 + wave * .12),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.person_search_rounded,
                    color: Color(0xFF8ED8FF),
                    size: 38,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                context.tr('searching_opponent'),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF66C7FF).withValues(
                          alpha: .28 + (((animation.value * 3 - i).abs() < .7) ? .65 : 0),
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Divider(color: Colors.white.withValues(alpha: .12), height: 1),
              const SizedBox(height: 8),
              Text(
                '—   ·   —   ·   —',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .34),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VersusCore extends StatelessWidget {
  const _VersusCore({
    required this.matched,
    required this.animation,
    required this.compact,
  });

  final bool matched;
  final Animation<double> animation;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final glow = .18 + .14 * ((math.sin(animation.value * math.pi * 2) + 1) / 2);
        return Container(
          width: compact ? 62 : 72,
          height: compact ? 62 : 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [Color(0xFF27435C), Color(0xFF0A1722)],
            ),
            border: Border.all(
              color: const Color(0xFFFFC94D).withValues(alpha: .52),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3AA9FF).withValues(alpha: glow),
                blurRadius: 22,
                offset: const Offset(-8, 0),
              ),
              BoxShadow(
                color: const Color(0xFFFFC94D).withValues(alpha: glow),
                blurRadius: 22,
                offset: const Offset(8, 0),
              ),
            ],
          ),
          child: matched
              ? const Text(
                  'VS',
                  style: TextStyle(
                    color: Color(0xFFFFD66B),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                )
              : const Icon(
                  Icons.bolt_rounded,
                  color: Color(0xFFFFD66B),
                  size: 34,
                ),
        );
      },
    );
  }
}

class _SearchStat extends StatelessWidget {
  const _SearchStat({required this.value, required this.label, this.accent = false});

  final String value;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: accent ? const Color(0xFFC3A8FF) : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .48),
            fontSize: 8,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SearchStatusBand extends StatelessWidget {
  const _SearchStatusBand({
    required this.matched,
    required this.busy,
    required this.status,
  });

  final bool matched;
  final bool busy;
  final String status;

  @override
  Widget build(BuildContext context) {
    final accent = matched ? const Color(0xFF29D398) : const Color(0xFF66C7FF);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xD9102030),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: .22)),
      ),
      child: Row(
        children: [
          if (busy || !matched)
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: accent),
            )
          else
            Icon(Icons.check_circle_rounded, color: accent, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchActionButton extends StatelessWidget {
  const _SearchActionButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
    required this.matched,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onPressed;
  final bool matched;

  @override
  Widget build(BuildContext context) {
    final danger = !matched;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton.icon(
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 22),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: danger ? const Color(0xFFFFA9A3) : const Color(0xFF29D398),
          side: BorderSide(
            color: (danger ? const Color(0xFFFF6B62) : const Color(0xFF29D398))
                .withValues(alpha: .62),
          ),
          backgroundColor: const Color(0xC90B1924),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
      ),
    );
  }
}

class _SearchEnergyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final blue = Paint()
      ..color = const Color(0xFF3AA9FF).withValues(alpha: .13)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;
    final gold = Paint()
      ..color = const Color(0xFFFFC94D).withValues(alpha: .12)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < 4; i++) {
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: size.width * (.34 + i * .13),
          height: size.height * (.20 + i * .10),
        ),
        i.isEven ? blue : gold,
      );
    }

    final bolt = Path()
      ..moveTo(center.dx - 5, size.height * .22)
      ..lineTo(center.dx + 14, size.height * .39)
      ..lineTo(center.dx - 10, size.height * .50)
      ..lineTo(center.dx + 12, size.height * .68)
      ..lineTo(center.dx - 3, size.height * .79);
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF3AA9FF), Color(0xFFFFC94D)],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(bolt, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
