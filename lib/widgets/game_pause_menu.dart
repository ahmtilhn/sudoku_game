import 'package:flutter/material.dart';

import 'duel_asset_icon.dart';

class GamePauseMenu extends StatelessWidget {
  const GamePauseMenu({
    super.key,
    required this.asset,
    required this.title,
    required this.subtitle,
    required this.variantLabel,
    required this.difficultyLabel,
    required this.timeLabel,
    required this.timeValue,
    required this.mistakesLabel,
    required this.mistakesValue,
    required this.hintsLabel,
    required this.hintsValue,
    required this.resumeLabel,
    required this.restartLabel,
    required this.menuLabel,
    required this.onResume,
    required this.onRestart,
    required this.onMenu,
  });

  final String asset;
  final String title;
  final String subtitle;
  final String variantLabel;
  final String difficultyLabel;
  final String timeLabel;
  final String timeValue;
  final String mistakesLabel;
  final String mistakesValue;
  final String hintsLabel;
  final String hintsValue;
  final String resumeLabel;
  final String restartLabel;
  final String menuLabel;
  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      child: Dialog(
        key: const ValueKey<String>('game-pause-menu'),
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF081522),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFF35D2FF).withValues(alpha: .38),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 30,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D2134),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .1),
                          ),
                        ),
                        child: DuelAssetIcon(asset, size: 54),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '$variantLabel · $difficultyLabel',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF35D2FF),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: const BoxDecoration(
                          color: Color(0xFF13283C),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.pause_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    subtitle,
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .68),
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _PauseMetric(
                          icon: Icons.timer_outlined,
                          label: timeLabel,
                          value: timeValue,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: _PauseMetric(
                          icon: Icons.error_outline_rounded,
                          label: mistakesLabel,
                          value: mistakesValue,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: _PauseMetric(
                          icon: Icons.lightbulb_outline_rounded,
                          label: hintsLabel,
                          value: hintsValue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const ValueKey<String>('pause-resume'),
                    onPressed: onResume,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      backgroundColor: const Color(0xFF29D398),
                      foregroundColor: const Color(0xFF07111E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(
                      resumeLabel,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey<String>('pause-restart'),
                          onPressed: onRestart,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: .22),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.restart_alt_rounded, size: 20),
                          label: Text(
                            restartLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextButton.icon(
                          key: const ValueKey<String>('pause-menu'),
                          onPressed: onMenu,
                          style: TextButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            foregroundColor: Colors.white70,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.home_outlined, size: 20),
                          label: Text(
                            menuLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
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

class _PauseMetric extends StatelessWidget {
  const _PauseMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF0D2134),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: Colors.white60),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
