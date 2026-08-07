import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class DuelAsset {
  const DuelAsset._();

  static const arrowForward = 'assets/images/ui/arrow_forward.png';
  static const avatar = 'assets/images/ui/avatar.png';
  static const back = 'assets/images/ui/back.png';
  static const careerBook = 'assets/images/ui/career_book.png';
  static const cart = 'assets/images/ui/cart.png';
  static const check = 'assets/images/ui/check.png';
  static const close = 'assets/images/ui/close.png';
  static const cloud = 'assets/images/ui/cloud.png';
  static const coin = 'assets/images/ui/coin.png';
  static const diamond = 'assets/images/ui/diamond.png';
  static const gift = 'assets/images/ui/gift.png';
  static const grid = 'assets/images/ui/grid.png';
  static const home = 'assets/images/ui/home.png';
  static const homeCareerRelic = 'assets/images/ui/home_career_relic.png';
  static const homeDuelEmblem = 'assets/images/ui/home_duel_emblem.png';
  static const homeProfileCrest = 'assets/images/ui/home_profile_crest.png';
  static const homeStoreChest = 'assets/images/ui/home_store_chest.png';
  static const lightbulb = 'assets/images/ui/lightbulb.png';
  static const lock = 'assets/images/ui/lock.png';
  static const mail = 'assets/images/ui/mail.png';
  static const notes = 'assets/images/ui/notes.png';
  static const people = 'assets/images/ui/people.png';
  static const plus = 'assets/images/ui/plus.png';
  static const profile = 'assets/images/ui/profile.png';
  static const refresh = 'assets/images/ui/refresh.png';
  static const search = 'assets/images/ui/search.png';
  static const settings = 'assets/images/ui/settings.png';
  static const shield = 'assets/images/ui/shield.png';
  static const store = 'assets/images/ui/store.png';
  static const swords = 'assets/images/ui/swords.png';
  static const target = 'assets/images/ui/target.png';
  static const timer = 'assets/images/ui/timer.png';
  static const trophy = 'assets/images/ui/trophy.png';
  static const undo = 'assets/images/ui/undo.png';
  static const video = 'assets/images/ui/video.png';
  static const wifi = 'assets/images/ui/wifi.png';

  static const quickPlayPro = 'assets/images/ui/pro/mode_quick_play.svg';
  static const careerPro = 'assets/images/ui/pro/mode_career.svg';
  static const onlineDuelPro = 'assets/images/ui/pro/mode_online_duel.svg';
  static const friendsPro = 'assets/images/ui/pro/mode_friends.svg';
  static const storePro = 'assets/images/ui/pro/mode_store.svg';
  static const profilePro = 'assets/images/ui/pro/mode_profile.svg';
  static const board9Pro = 'assets/images/ui/pro/board_9x9.svg';
  static const board16Pro = 'assets/images/ui/pro/board_16x16.svg';
  static const statusErrorPro = 'assets/images/ui/pro/status_error.svg';
  static const statusSuccessPro = 'assets/images/ui/pro/status_success.svg';
  static const statusWarningPro = 'assets/images/ui/pro/status_warning.svg';
  static const statusOfflinePro = 'assets/images/ui/pro/status_offline.svg';

  static const homePlayScene = 'assets/images/ui/home_play.png';
  static const homeDuelScene = 'assets/images/ui/home_online_duel.png';
  static const homeCareerScene = 'assets/images/ui/home_career.png';
  static const homeFriendsScene = 'assets/images/ui/home_friends.png';
  static const homeStoreScene = 'assets/images/ui/home_coin_store.png';
  static const homeProfileScene = 'assets/images/ui/home_profile.png';

  // Production economy artwork. These aliases intentionally point at the
  // latest user-provided standalone assets instead of the legacy stack/reward
  // scenes so updates to coin.png, gift.png and shield.png are visible in UI.
  static const dailyRewardPro = gift;
  static const walletCoinStackPro = coin;
  static const coinStoreBalancePro = coin;
  static const removeAdsPro = shield;

  static const resultVictoryTrophyPro = 'assets/images/ui/victory_trophy.png';
  static const resultDefeatTrophyPro = 'assets/images/ui/defeat_trophy.png';
  static const leaderboardCrownPro = 'assets/images/ui/leaderboard.png';
}

class DuelAssetIcon extends StatelessWidget {
  const DuelAssetIcon(
    this.asset, {
    super.key,
    this.size = 24,
    this.color,
    this.semanticLabel,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
  });

  final String asset;
  final double size;
  final Color? color;
  final String? semanticLabel;
  final BoxFit fit;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    if (asset.toLowerCase().endsWith('.svg')) {
      return SvgPicture.asset(
        asset,
        width: size,
        height: size,
        fit: fit,
        alignment: alignment,
        semanticsLabel: semanticLabel,
        colorFilter: color == null
            ? null
            : ColorFilter.mode(color!, BlendMode.srcIn),
      );
    }
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: fit,
      alignment: alignment,
      color: color,
      semanticLabel: semanticLabel,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
    );
  }
}