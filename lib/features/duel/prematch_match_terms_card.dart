import 'package:flutter/material.dart';

import '../../localization/app_strings.dart';
import '../../widgets/duel_asset_icon.dart';

class PrematchMatchTermsCard extends StatelessWidget {
  const PrematchMatchTermsCard({
    super.key,
    required this.entryFee,
    required this.winnerPot,
    required this.scale,
    this.difficultyAdjustmentLabel,
  });

  final int entryFee;
  final int winnerPot;
  final double scale;
  final String? difficultyAdjustmentLabel;

  @override
  Widget build(BuildContext context) {
    final adjustment = difficultyAdjustmentLabel?.trim();
    final showAdjustment = adjustment != null && adjustment.isNotEmpty;

    return Container(
      padding: EdgeInsets.fromLTRB(
        (11 * scale).clamp(9.0, 13.0).toDouble(),
        (8 * scale).clamp(7.0, 10.0).toDouble(),
        (11 * scale).clamp(9.0, 13.0).toDouble(),
        (8 * scale).clamp(7.0, 10.0).toDouble(),
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFFC73D).withValues(alpha: .09),
            const Color(0xE00B1A28),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF29D398).withValues(alpha: .28),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showAdjustment) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.tune_rounded,
                  color: const Color(0xFF66C7FF),
                  size: (14 * scale).clamp(12.0, 15.0).toDouble(),
                ),
                SizedBox(width: 5 * scale),
                Flexible(
                  child: Text(
                    adjustment,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: const Color(0xFF8FD8FF),
                      fontSize: (10 * scale).clamp(9.0, 11.0).toDouble(),
                      fontWeight: FontWeight.w900,
                      letterSpacing: .15,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 5 * scale),
            Divider(
              height: 1,
              color: Colors.white.withValues(alpha: .08),
            ),
            SizedBox(height: 5 * scale),
          ],
          Row(
            children: [
              DuelAssetIcon(
                DuelAsset.coin,
                size: (31 * scale).clamp(27.0, 34.0).toDouble(),
              ),
              SizedBox(width: 7 * scale),
              Expanded(
                child: _TermValue(
                  label: context.tr('entry_fee'),
                  value: context.tr('coin_amount', <Object>[entryFee]),
                  color: const Color(0xFFFFC73D),
                  scale: scale,
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 5 * scale),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white.withValues(alpha: .34),
                  size: (17 * scale).clamp(15.0, 18.0).toDouble(),
                ),
              ),
              Expanded(
                child: _TermValue(
                  label: context.tr('winner_pot'),
                  value: context.tr('coin_amount', <Object>[winnerPot]),
                  color: const Color(0xFF29D398),
                  scale: scale,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TermValue extends StatelessWidget {
  const _TermValue({
    required this.label,
    required this.value,
    required this.color,
    required this.scale,
  });

  final String label;
  final String value;
  final Color color;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .52),
            fontSize: (8.5 * scale).clamp(8.0, 9.5).toDouble(),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: (11 * scale).clamp(10.0, 12.0).toDouble(),
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
