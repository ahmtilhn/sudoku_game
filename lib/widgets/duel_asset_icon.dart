import 'package:flutter/material.dart';

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
}

class DuelAssetIcon extends StatelessWidget {
  const DuelAssetIcon(
    this.asset, {
    super.key,
    this.size = 24,
    this.color,
    this.semanticLabel,
  });

  final String asset;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      color: color,
      semanticLabel: semanticLabel,
      filterQuality: FilterQuality.high,
    );
  }
}
