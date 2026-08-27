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

/// Presentation-only matchmaking arena.
///
/// Queue creation, polling, cancellation and room handoff remain owned by
/// MatchmakingScreen. This widget only renders the current queue state.
class MatchmakingStage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07111E),
      body: AppBackdrop(
        dim: .28,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 720;
              final veryCompact = constraints.maxHeight < 640;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      14,
                      compact ? 7 : 12,
                      14,
                      compact ? 10 : 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SearchTopBar(
                          onClose: onClose,
                          matched: matched,
                        ),
                        SizedBox(height: compact ? 10 : 16),
                        _SearchTitle(
                          matched: matched,
                          status: searchStatus,
                          compact: compact,
                        ),
                        SizedBox(height: compact ? 10 : 16),
                        Expanded(
                          child: _MatchSearchArena(
                            currentPlayer: currentPlayer,
                            opponent: opponent,
                            opponentReady: opponentReady,
                            opponentStatus: opponentStatus,
                            compact: compact,
                            veryCompact: veryCompact,
                          ),
                        ),
                        SizedBox(height: compact ? 8 : 12),
                        _QueueStatusBar(
                          matched: matched,
                          busy: actionBusy,
                          status: matched
                              ? (opponentStatus ?? context.tr('connected'))
                              : (searchStatus ??
                                    context.tr('searching_opponent_short')),
                        ),
                        SizedBox(height: compact ? 8 : 12),
                        _MatchmakingActionButton(
                          label: actionLabel,
                          icon: actionIcon,
                          busy: actionBusy,
                          onPressed: onAction,
                          matched: matched,
                        ),
                        if (floatingControl != null) ...[
                          SizedBox(height: compact ? 6 : 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: floatingControl!,
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
      height: 56,
      child: Row(
        children: [
          IconButton(
            tooltip: context.tr('cancel'),
            onPressed: onClose,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF132A3C).withValues(alpha: .92),
              foregroundColor: Colors.white,
              side: BorderSide(
                color: Colors.white.withValues(alpha: .10),
              ),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
                    letterSpacing: 1.45,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF102131).withValues(alpha: .92),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0xFF66C7FF).withValues(alpha: .16),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: matched
                        ? const Color(0xFF29D398)
                        : const Color(0xFF66C7FF),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (matched
                                ? const Color(0xFF29D398)
                                : const Color(0xFF66C7FF))
                            .withValues(alpha: .34),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  matched ? 'FOUND' : 'LIVE',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .72),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .8,
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

class _SearchTitle extends StatelessWidget {
  const _SearchTitle({
    required this.matched,
    required this.status,
    required this.compact,
  });

  final bool matched;
  final String? status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          matched ? context.tr('opponent_ready') : context.tr('searching_opponent'),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 21 : 25,
            fontWeight: FontWeight.w900,
            letterSpacing: -.35,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          status ??
              (matched
                  ? context.tr('connected')
                  : context.tr('searching_opponent_short')),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .55),
            fontSize: compact ? 11 : 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _MatchSearchArena extends StatelessWidget {
  const _MatchSearchArena({
    required this.currentPlayer,
    required this.opponent,
    required this.opponentReady,
    required this.opponentStatus,
    required this.compact,
    required this.veryCompact,
  });

  final MatchmakingVisualPlayer currentPlayer;
  final MatchmakingVisualPlayer? opponent;
  final bool opponentReady;
  final String? opponentStatus;
  final bool compact;
  final bool veryCompact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xF0122639), Color(0xF0091622)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: const Color(0xFF66C7FF).withValues(alpha: .18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .30),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(
              child: IgnorePointer(child: CustomPaint(painter: _ArenaGridPainter())),
            ),
            Positioned(
              left: -60,
              top: -50,
              child: _GlowOrb(
                size: 180,
                color: const Color(0xFF29D398),
              ),
            ),
            Positioned(
              right: -70,
              bottom: -60,
              child: _GlowOrb(
                size: 200,
                color: const Color(0xFFFFC94D),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 10 : 16,
                veryCompact ? 10 : (compact ? 14 : 20),
                compact ? 10 : 16,
                veryCompact ? 10 : (compact ? 14 : 20),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _PlayerSearchCard(
                      player: currentPlayer,
                      label: context.tr('you'),
                      accent: const Color(0xFF29D398),
                      compact: compact,
                    ),
                  ),
                  SizedBox(
                    width: compact ? 58 : 74,
                    child: _VersusCore(compact: compact),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: opponent == null
                          ? _SearchingCard(
                              key: const ValueKey<String>('searching-opponent-card'),
                              compact: compact,
                            )
                          : _PlayerSearchCard(
                              key: ValueKey<String>(
                                'matched-opponent-${opponent!.displayName}',
                              ),
                              player: opponent!,
                              label: context.tr('opponent'),
                              accent: const Color(0xFFFFC94D),
                              compact: compact,
                              status: opponentStatus,
                              ready: opponentReady,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerSearchCard extends StatelessWidget {
  const _PlayerSearchCard({
    super.key,
    required this.player,
    required this.label,
    required this.accent,
    required this.compact,
    this.status,
    this.ready = false,
  });

  final MatchmakingVisualPlayer player;
  final String label;
  final Color accent;
  final bool compact;
  final String? status;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final avatarRadius = compact ? 35.0 : 44.0;
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 8 : 12,
        compact ? 10 : 16,
        compact ? 8 : 12,
        compact ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1C2A).withValues(alpha: .78),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: .22)),
      ),
      child: Column(
        children: [
          _SideLabel(label: label, color: accent),
          SizedBox(height: compact ? 8 : 12),
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: accent.withValues(alpha: .72),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: .18),
                  blurRadius: 18,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: PlayerAvatar(
                displayName: player.displayName,
                avatarKey: player.avatarKey,
                remoteApprovedImageUrl: player.remoteApprovedImageUrl,
                radius: avatarRadius,
              ),
            ),
          ),
          SizedBox(height: compact ? 8 : 11),
          Text(
            player.displayName,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 14 : 17,
              fontWeight: FontWeight.w900,
              letterSpacing: -.2,
            ),
          ),
          const SizedBox(height: 4),
          _RankChip(
            rank: player.rankLabel,
            accent: accent,
            compact: compact,
          ),
          const Spacer(),
          _PlayerStats(player: player, compact: compact),
          if (status != null || ready) ...[
            SizedBox(height: compact ? 7 : 9),
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
                    status ?? context.tr('ready'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .62),
                      fontSize: compact ? 9 : 10,
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

class _SearchingCard extends StatelessWidget {
  const _SearchingCard({super.key, required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 8 : 12,
        compact ? 10 : 16,
        compact ? 8 : 12,
        compact ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1C2A).withValues(alpha: .72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFFFC94D).withValues(alpha: .18),
        ),
      ),
      child: Column(
        children: [
          const _SideLabel(label: 'OPPONENT', color: Color(0xFFFFC94D)),
          const Spacer(),
          SizedBox.square(
            dimension: compact ? 86 : 104,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  strokeWidth: compact ? 3 : 3.5,
                  backgroundColor: Colors.white.withValues(alpha: .06),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF66C7FF),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(9),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [Color(0xFF17344A), Color(0xFF0A1926)],
                      ),
                      border: Border.all(
                        color: const Color(0xFF66C7FF).withValues(alpha: .22),
                      ),
                    ),
                    child: Icon(
                      Icons.person_search_rounded,
                      color: const Color(0xFF8ED8FF),
                      size: compact ? 38 : 46,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: compact ? 10 : 14),
          Text(
            context.tr('searching_opponent'),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 13 : 16,
              height: 1.08,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _PulseDot(color: Color(0xFF66C7FF)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  context.tr('searching_opponent_short'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .50),
                    fontSize: compact ? 9 : 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          const _UnknownStats(compact: true),
        ],
      ),
    );
  }
}

class _VersusCore extends StatelessWidget {
  const _VersusCore({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: compact ? 48 : 60,
          height: compact ? 48 : 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [Color(0xFF27435C), Color(0xFF0A1722)],
            ),
            border: Border.all(
              color: const Color(0xFFFFC94D).withValues(alpha: .42),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF66C7FF).withValues(alpha: .18),
                blurRadius: 18,
              ),
              BoxShadow(
                color: const Color(0xFFFFC94D).withValues(alpha: .12),
                blurRadius: 18,
              ),
            ],
          ),
          child: Icon(
            Icons.bolt_rounded,
            color: const Color(0xFFFFD66B),
            size: compact ? 28 : 34,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'VS',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .42),
            fontSize: compact ? 10 : 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _QueueStatusBar extends StatelessWidget {
  const _QueueStatusBar({
    required this.matched,
    required this.busy,
    required this.status,
  });

  final bool matched;
  final bool busy;
  final String status;

  @override
  Widget build(BuildContext context) {
    final accent = matched
        ? const Color(0xFF29D398)
        : const Color(0xFF66C7FF);
    return Container(
      minHeight: 48,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF102131).withValues(alpha: .92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: .16)),
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 24,
            child: busy || !matched
                ? CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: accent,
                    backgroundColor: Colors.white.withValues(alpha: .06),
                  )
                : Icon(Icons.check_circle_rounded, color: accent, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  matched ? 'Opponent found' : context.tr('searching_opponent'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
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
          const SizedBox(width: 8),
          Icon(
            matched ? Icons.link_rounded : Icons.travel_explore_rounded,
            color: accent.withValues(alpha: .72),
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _MatchmakingActionButton extends StatelessWidget {
  const _MatchmakingActionButton({
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
    final accent = matched
        ? const Color(0xFF29D398)
        : const Color(0xFFFF7A70);
    return SizedBox(
      height: 54,
      child: OutlinedButton.icon(
        key: const ValueKey<String>('matchmaking-stage-action'),
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 21),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          disabledForegroundColor: Colors.white54,
          backgroundColor: const Color(0xFF0D1B28).withValues(alpha: .90),
          side: BorderSide(color: accent.withValues(alpha: .40)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

class _SideLabel extends StatelessWidget {
  const _SideLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .16)),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color.withValues(alpha: .92),
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: .9,
        ),
      ),
    );
  }
}

class _RankChip extends StatelessWidget {
  const _RankChip({
    required this.rank,
    required this.accent,
    required this.compact,
  });

  final String? rank;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final value = rank?.trim();
    return Container(
      constraints: const BoxConstraints(maxWidth: 130),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: .17)),
      ),
      child: Text(
        value == null || value.isEmpty ? 'UNRANKED' : value.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withValues(alpha: .76),
          fontSize: compact ? 8 : 9,
          fontWeight: FontWeight.w900,
          letterSpacing: .45,
        ),
      ),
    );
  }
}

class _PlayerStats extends StatelessWidget {
  const _PlayerStats({required this.player, required this.compact});

  final MatchmakingVisualPlayer player;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final winRate = player.winRate;
    final rate = winRate == null ? '—' : '${(winRate * 100).round()}%';
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 6,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: .055)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _MiniStat(
              value: player.rating?.toString() ?? '—',
              label: 'RP',
              compact: compact,
            ),
          ),
          _MiniDivider(compact: compact),
          Expanded(
            child: _MiniStat(
              value: player.gamesPlayed?.toString() ?? '—',
              label: 'GAMES',
              compact: compact,
            ),
          ),
          _MiniDivider(compact: compact),
          Expanded(
            child: _MiniStat(
              value: rate,
              label: 'WIN',
              compact: compact,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnknownStats extends StatelessWidget {
  const _UnknownStats({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 6,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .025),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: .045)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            Expanded(
              child: _MiniStat(
                value: '—',
                label: i == 0 ? 'RP' : (i == 1 ? 'GAMES' : 'WIN'),
                compact: compact,
              ),
            ),
            if (i < 2) _MiniDivider(compact: compact),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.value,
    required this.label,
    required this.compact,
  });

  final String value;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 10 : 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .34),
            fontSize: compact ? 6 : 7,
            fontWeight: FontWeight.w900,
            letterSpacing: .45,
          ),
        ),
      ],
    );
  }
}

class _MiniDivider extends StatelessWidget {
  const _MiniDivider({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: compact ? 22 : 26,
      color: Colors.white.withValues(alpha: .06),
    );
  }
}

class _PulseDot extends StatelessWidget {
  const _PulseDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 8,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: .30), blurRadius: 7),
          ],
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: .10), Colors.transparent],
          ),
        ),
      ),
    );
  }
}

class _ArenaGridPainter extends CustomPainter {
  const _ArenaGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white.withValues(alpha: .025)
      ..strokeWidth = 1;
    const divisions = 7;
    for (var i = 1; i < divisions; i++) {
      final x = size.width * i / divisions;
      final y = size.height * i / divisions;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }

    final centerLine = Paint()
      ..color = const Color(0xFF66C7FF).withValues(alpha: .035)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(size.width / 2, 14),
      Offset(size.width / 2, size.height - 14),
      centerLine,
    );
  }

  @override
  bool shouldRepaint(covariant _ArenaGridPainter oldDelegate) => false;
}
