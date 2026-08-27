from pathlib import Path

path = Path('lib/features/duel/online_duel_screen.dart')
source = path.read_text()

sheet_old = """        constraints: const BoxConstraints(maxWidth: 560),
        builder: (sheetContext) => _OnlineResultSheet(snapshot: snapshot),
"""
sheet_new = """        constraints: const BoxConstraints(maxWidth: 460),
        builder: (sheetContext) => FractionallySizedBox(
          heightFactor: MediaQuery.sizeOf(sheetContext).height < 720 ? .98 : .94,
          child: _OnlineResultSheet(snapshot: snapshot),
        ),
"""
if sheet_old not in source:
    raise SystemExit('result bottom-sheet anchor missing')
source = source.replace(sheet_old, sheet_new, 1)

start = source.index('class _ResultCard extends StatelessWidget {')
end = source.index('class _InlineRematch extends StatelessWidget {', start)

replacement = r'''class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.title,
    required this.subtitle,
    required this.won,
    required this.draw,
    required this.localPlayer,
    required this.opponent,
    required this.localScore,
    required this.opponentScore,
    required this.metrics,
    required this.rankResult,
    required this.rankLoading,
    required this.showRank,
    required this.statusMessage,
    required this.invitation,
    required this.invitationSeconds,
    required this.canPlay,
    required this.busy,
    required this.onInvitationDecline,
    required this.onInvitationAccept,
    required this.onNewMatch,
    required this.onRematch,
    required this.onAddFriend,
    required this.onMenu,
    required this.onStore,
  });

  static const _cupAsset = 'assets/ELO_rating_icons/cup.png';

  final String title;
  final String subtitle;
  final bool won;
  final bool draw;
  final OnlineDuelPlayer localPlayer;
  final OnlineDuelPlayer opponent;
  final int localScore;
  final int opponentScore;
  final List<_ResultMetric> metrics;
  final RankMatchResult? rankResult;
  final bool rankLoading;
  final bool showRank;
  final String? statusMessage;
  final RematchInvitation? invitation;
  final int invitationSeconds;
  final bool canPlay;
  final bool busy;
  final VoidCallback? onInvitationDecline;
  final VoidCallback? onInvitationAccept;
  final VoidCallback onNewMatch;
  final VoidCallback onRematch;
  final VoidCallback? onAddFriend;
  final VoidCallback onMenu;
  final VoidCallback onStore;

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final compact = viewport.width < 380 || viewport.height < 760;
    final accent = draw
        ? const Color(0xFF9AA9BA)
        : won
        ? const Color(0xFF38E09E)
        : const Color(0xFFFF6B62);
    final headline = title.trim().endsWith('!')
        ? title.toUpperCase()
        : '${title.toUpperCase()}!';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 12,
        compact ? 8 : 10,
        compact ? 10 : 12,
        compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF102237), Color(0xFF0A1624)],
        ),
        borderRadius: BorderRadius.circular(compact ? 20 : 23),
        border: Border.all(
          color: const Color(0xFF5C8FB8).withValues(alpha: .36),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .46),
            blurRadius: 28,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ResultHero(
            asset: _cupAsset,
            title: headline,
            subtitle: subtitle,
            accent: accent,
            compact: compact,
            muted: !draw && !won,
          ),
          SizedBox(height: compact ? 7 : 9),
          _ResultPlayers(
            localPlayer: localPlayer,
            opponent: opponent,
            localScore: localScore,
            opponentScore: opponentScore,
            won: won,
            draw: draw,
            compact: compact,
          ),
          SizedBox(height: compact ? 7 : 9),
          _ResultStatsTable(
            metrics: metrics,
            won: won,
            draw: draw,
            compact: compact,
          ),
          if (showRank) ...[
            SizedBox(height: compact ? 7 : 9),
            _ResultRankPanel(result: rankResult, loading: rankLoading),
          ],
          if (statusMessage != null) ...[
            SizedBox(height: compact ? 6 : 8),
            Text(
              statusMessage!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: accent,
                fontSize: compact ? 9 : 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
          if (invitation != null && invitation!.status == 'pending') ...[
            SizedBox(height: compact ? 7 : 9),
            _InlineRematch(
              invitation: invitation!,
              seconds: invitationSeconds,
              busy: busy,
              canPlay: canPlay,
              onDecline: onInvitationDecline,
              onAccept: onInvitationAccept,
            ),
          ],
          SizedBox(height: compact ? 8 : 10),
          SizedBox(
            width: double.infinity,
            height: compact ? 42 : 46,
            child: FilledButton(
              onPressed: busy || !canPlay ? null : onNewMatch,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF20B875),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF20B875).withValues(alpha: .26),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              child: _ResultButtonLabel(
                icon: Icons.swap_horiz_rounded,
                label: context.tr('find_new_match'),
                compact: compact,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: compact ? 40 : 44,
            child: OutlinedButton(
              onPressed: busy || !canPlay || invitation?.status == 'pending'
                  ? null
                  : onRematch,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(
                  color: const Color(0xFF83B5D8).withValues(alpha: .42),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              child: _ResultButtonLabel(
                icon: Icons.refresh_rounded,
                label: context.tr('challenge_again'),
                compact: compact,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _ResultFooterAction(
                  height: compact ? 38 : 42,
                  icon: Icons.person_add_alt_1_rounded,
                  label: context.tr('add_friend'),
                  onPressed: busy ? null : onAddFriend,
                  compact: compact,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _ResultFooterAction(
                  height: compact ? 38 : 42,
                  icon: Icons.home_outlined,
                  label: context.tr('main_menu'),
                  onPressed: busy ? null : onMenu,
                  compact: compact,
                ),
              ),
            ],
          ),
          if (!canPlay) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              height: compact ? 38 : 42,
              child: OutlinedButton(
                onPressed: busy ? null : onStore,
                child: _ResultButtonLabel(
                  icon: Icons.storefront_outlined,
                  label: context.tr('open_coin_store'),
                  compact: compact,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultHero extends StatelessWidget {
  const _ResultHero({
    required this.asset,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.compact,
    required this.muted,
  });

  final String asset;
  final String title;
  final String subtitle;
  final Color accent;
  final bool compact;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: muted ? .78 : 1,
          child: Image.asset(
            asset,
            width: compact ? 62 : 72,
            height: compact ? 62 : 72,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -3),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: accent,
              fontSize: compact ? 25 : 29,
              height: 1,
              fontWeight: FontWeight.w900,
              letterSpacing: .2,
              shadows: [
                Shadow(color: accent.withValues(alpha: .25), blurRadius: 12),
              ],
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .88),
            fontSize: compact ? 10 : 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ResultPlayers extends StatelessWidget {
  const _ResultPlayers({
    required this.localPlayer,
    required this.opponent,
    required this.localScore,
    required this.opponentScore,
    required this.won,
    required this.draw,
    required this.compact,
  });

  final OnlineDuelPlayer localPlayer;
  final OnlineDuelPlayer opponent;
  final int localScore;
  final int opponentScore;
  final bool won;
  final bool draw;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final localAccent = draw
        ? const Color(0xFF9AA9BA)
        : won
        ? const Color(0xFF38E09E)
        : const Color(0xFFFF746C);
    final opponentAccent = draw
        ? const Color(0xFF9AA9BA)
        : won
        ? const Color(0xFF79C8FF)
        : const Color(0xFF38E09E);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _ResultPlayerPanel(
            player: opponent,
            score: opponentScore,
            accent: opponentAccent,
            compact: compact,
            isLocal: false,
          ),
        ),
        SizedBox(width: compact ? 5 : 7),
        Center(
          child: Container(
            width: compact ? 30 : 34,
            height: compact ? 30 : 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0B1826),
              border: Border.all(
                color: const Color(0xFFFFC94D).withValues(alpha: .50),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFC94D).withValues(alpha: .10),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Text(
              'VS',
              style: TextStyle(
                color: const Color(0xFFFFC94D),
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        SizedBox(width: compact ? 5 : 7),
        Expanded(
          child: _ResultPlayerPanel(
            player: localPlayer,
            score: localScore,
            accent: localAccent,
            compact: compact,
            isLocal: true,
          ),
        ),
      ],
    );
  }
}

class _ResultPlayerPanel extends StatelessWidget {
  const _ResultPlayerPanel({
    required this.player,
    required this.score,
    required this.accent,
    required this.compact,
    required this.isLocal,
  });

  final OnlineDuelPlayer player;
  final int score;
  final Color accent;
  final bool compact;
  final bool isLocal;

  @override
  Widget build(BuildContext context) {
    final name = isLocal ? context.tr('you') : player.displayName;
    final username = player.username.isEmpty ? '' : '@${player.username}';
    final avatar = Container(
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accent.withValues(alpha: .92), width: 1.4),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: .13), blurRadius: 10),
        ],
      ),
      child: PlayerAvatar(
        displayName: player.displayName,
        avatarKey: player.avatarKey,
        radius: compact ? 18 : 21,
        semanticLabel: player.displayName,
      ),
    );

    return Container(
      constraints: BoxConstraints(minHeight: compact ? 73 : 82),
      padding: EdgeInsets.fromLTRB(
        compact ? 6 : 8,
        compact ? 7 : 8,
        compact ? 6 : 8,
        compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF14263A).withValues(alpha: .92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: .24)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            textDirection: isLocal ? TextDirection.rtl : TextDirection.ltr,
            children: [
              avatar,
              SizedBox(width: compact ? 5 : 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: isLocal
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 10 : 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (username.isNotEmpty)
                      Text(
                        username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .50),
                          fontSize: compact ? 7.5 : 8.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 2 : 3),
          Text(
            '$score',
            style: TextStyle(
              color: accent,
              fontSize: compact ? 16 : 18,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultStatsTable extends StatelessWidget {
  const _ResultStatsTable({
    required this.metrics,
    required this.won,
    required this.draw,
    required this.compact,
  });

  final List<_ResultMetric> metrics;
  final bool won;
  final bool draw;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2031).withValues(alpha: .94),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6B9BBD).withValues(alpha: .18)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < metrics.length; index++) ...[
            _ResultMetricRow(
              metric: metrics[index],
              won: won,
              draw: draw,
              compact: compact,
            ),
            if (index != metrics.length - 1)
              Divider(
                height: 1,
                thickness: .6,
                color: Colors.white.withValues(alpha: .075),
              ),
          ],
        ],
      ),
    );
  }
}

class _ResultMetricRow extends StatelessWidget {
  const _ResultMetricRow({
    required this.metric,
    required this.won,
    required this.draw,
    required this.compact,
  });

  final _ResultMetric metric;
  final bool won;
  final bool draw;
  final bool compact;

  Color _valueColor(String value, Color fallback) {
    final trimmed = value.trim();
    if (trimmed.startsWith('+')) return const Color(0xFF38E09E);
    if (trimmed.startsWith('-')) return const Color(0xFFFF6B62);
    if (trimmed.toUpperCase().contains('N/A')) {
      return const Color(0xFF8E9EAD);
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final localAccent = draw
        ? const Color(0xFFD6E0E8)
        : won
        ? const Color(0xFF38E09E)
        : const Color(0xFFFF746C);
    final opponentAccent = draw
        ? const Color(0xFFD6E0E8)
        : won
        ? const Color(0xFFD6E0E8)
        : const Color(0xFF38E09E);

    return SizedBox(
      height: compact ? 25 : 29,
      child: Row(
        children: [
          SizedBox(
            width: compact ? 46 : 52,
            child: Text(
              metric.opponentValue,
              textAlign: TextAlign.left,
              maxLines: 1,
              style: TextStyle(
                color: _valueColor(metric.opponentValue, opponentAccent),
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(metric.icon, color: const Color(0xFFFFC94D), size: compact ? 13 : 14),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    metric.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .84),
                      fontSize: compact ? 8.5 : 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: compact ? 46 : 52,
            child: Text(
              metric.localValue,
              textAlign: TextAlign.right,
              maxLines: 1,
              style: TextStyle(
                color: _valueColor(metric.localValue, localAccent),
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultRankPanel extends StatelessWidget {
  const _ResultRankPanel({required this.result, required this.loading});

  static const _cupAsset = 'assets/ELO_rating_icons/cup.png';

  final RankMatchResult? result;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 380 ||
        MediaQuery.sizeOf(context).height < 760;

    if (loading) {
      return Container(
        height: compact ? 68 : 76,
        decoration: _panelDecoration(),
        alignment: Alignment.center,
        child: const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final value = result;
    if (value == null || !value.rated || !value.settled) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 9 : 11),
        decoration: _panelDecoration(),
        child: Row(
          children: [
            Image.asset(_cupAsset, width: compact ? 22 : 25, height: compact ? 22 : 25),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Rank Points will update automatically.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .65),
                  fontSize: compact ? 9 : 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final afterTier = rankTierForPoints(value.rpAfter);
    final nextIndex = rankTierCatalog.indexWhere((tier) => tier.key == afterTier.key);
    final next = nextIndex >= 0 && nextIndex < rankTierCatalog.length - 1
        ? rankTierCatalog[nextIndex + 1]
        : null;
    final progress = next == null
        ? 1.0
        : ((value.rpAfter - afterTier.minPoints) /
                  (next.minPoints - afterTier.minPoints))
              .clamp(0.0, 1.0)
              .toDouble();
    final deltaColor = value.rpDelta >= 0
        ? const Color(0xFF38E09E)
        : const Color(0xFFFF6B62);
    final pointsToNext = next == null
        ? null
        : (next.minPoints - value.rpAfter).clamp(0, next.minPoints);

    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 9 : 11,
        compact ? 8 : 9,
        compact ? 9 : 11,
        compact ? 7 : 8,
      ),
      decoration: _panelDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              Image.asset(
                _cupAsset,
                width: compact ? 22 : 25,
                height: compact ? 22 : 25,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Rank Points',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${value.rpDelta >= 0 ? '+' : ''}${value.rpDelta} RP',
                style: TextStyle(
                  color: deltaColor,
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 5 : 7),
          Row(
            children: [
              Text(
                '${value.rpBefore}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .58),
                  fontSize: compact ? 8.5 : 9.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: compact ? 7 : 8,
                    backgroundColor: Colors.white.withValues(alpha: .10),
                    valueColor: AlwaysStoppedAnimation<Color>(deltaColor),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                '${value.rpAfter} RP',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 9.5 : 10.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 4 : 5),
          Row(
            children: [
              Expanded(
                child: Text(
                  value.rankAfterName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFFC9A9FF),
                    fontSize: compact ? 8.5 : 9.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (next != null && pointsToNext != null)
                Flexible(
                  child: Text(
                    '$pointsToNext RP to ${next.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .48),
                      fontSize: compact ? 7.5 : 8.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          if (value.abandonmentPenalty > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Includes -${value.abandonmentPenalty} RP leave penalty.',
              textAlign: TextAlign.center,
              style: _noticeStyle(compact),
            ),
          ] else if (value.repeatPercent < 100 && value.rpDelta > 0) ...[
            const SizedBox(height: 4),
            Text(
              value.repeatPercent == 0
                  ? 'Repeat-opponent protection: no farmable RP this match.'
                  : 'Repeat-opponent protection reduced positive RP.',
              textAlign: TextAlign.center,
              style: _noticeStyle(compact),
            ),
          ],
        ],
      ),
    );
  }

  BoxDecoration _panelDecoration() => BoxDecoration(
        color: const Color(0xFF0F2031).withValues(alpha: .96),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFFC94D).withValues(alpha: .24),
        ),
      );

  TextStyle _noticeStyle(bool compact) => TextStyle(
        color: Colors.white.withValues(alpha: .43),
        fontSize: compact ? 7.2 : 8.2,
        fontWeight: FontWeight.w700,
      );
}

class _ResultButtonLabel extends StatelessWidget {
  const _ResultButtonLabel({
    required this.icon,
    required this.label,
    required this.compact,
  });

  final IconData icon;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 16 : 17),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultFooterAction extends StatelessWidget {
  const _ResultFooterAction({
    required this.height,
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.compact,
  });

  final double height;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(
            color: const Color(0xFF83B5D8).withValues(alpha: .34),
          ),
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: _ResultButtonLabel(
          icon: icon,
          label: label,
          compact: compact,
        ),
      ),
    );
  }
}
'''

source = source[:start] + replacement + '\n\n' + source[end:]
path.write_text(source)
print('Applied result mockup v2 UI patch.')
