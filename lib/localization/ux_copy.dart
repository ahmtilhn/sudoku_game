import 'dart:ui';

import 'package:flutter/material.dart';

class UxCopy {
  const UxCopy._();

  static bool _isTurkish(BuildContext _) =>
      PlatformDispatcher.instance.locale.languageCode == 'tr';

  static String pause(BuildContext context) =>
      _isTurkish(context) ? 'Oyunu duraklat' : 'Pause game';

  static String pausedTitle(BuildContext context) =>
      _isTurkish(context) ? 'Oyun duraklatıldı' : 'Game paused';

  static String pausedBody(BuildContext context) => _isTurkish(context)
      ? 'Süre durdu ve tahta gizlendi. Hazır olduğunda devam et.'
      : 'The timer is stopped and the board is hidden. Continue when ready.';

  static String restartTitle(BuildContext context) =>
      _isTurkish(context) ? 'Bulmacayı yeniden başlat?' : 'Restart puzzle?';

  static String restartBody(BuildContext context) => _isTurkish(context)
      ? 'Bu oyundaki tüm hamlelerin ve süren silinecek.'
      : 'All moves and elapsed time for this game will be cleared.';

  static String fantasyTitle(BuildContext context) =>
      _isTurkish(context) ? 'Fantazi Modu · 16×16' : 'Fantasy Mode · 16×16';

  static String fantasySubtitle(BuildContext context) => _isTurkish(context)
      ? '4×4 bölgeler, 1–9 ve A–G sembolleriyle uzun oyun.'
      : 'A long game with 4×4 boxes and symbols 1–9 and A–G.';

  static String fantasyBadge(BuildContext context) =>
      _isTurkish(context) ? 'Çevrimdışı özel mod' : 'Offline special mode';

  static String genericError(BuildContext context) => _isTurkish(context)
      ? 'İşlem şu anda tamamlanamadı. Lütfen tekrar dene.'
      : 'The action could not be completed right now. Please try again.';

  static String connectionError(BuildContext context) => _isTurkish(context)
      ? 'Bağlantı kurulamadı. İnternetini kontrol edip tekrar dene.'
      : 'Could not connect. Check your internet connection and try again.';

  static String accountError(BuildContext context) => _isTurkish(context)
      ? 'Oyuncu hesabına şu anda ulaşılamıyor. Biraz sonra tekrar dene.'
      : 'Your player account is unavailable right now. Try again shortly.';

  static String serverBusy(BuildContext context) => _isTurkish(context)
      ? 'Sunucu şu anda yoğun. Kısa süre sonra tekrar dene.'
      : 'The service is busy right now. Try again shortly.';

  static String emptyProfile(BuildContext context) => _isTurkish(context)
      ? 'Profil bilgileri henüz hazır değil.'
      : 'Profile information is not ready yet.';

  static String connectedPlatform(BuildContext context) => _isTurkish(context)
      ? 'Google Play Games bağlı'
      : 'Google Play Games connected';

  static String platformNotConnected(BuildContext context) =>
      _isTurkish(context)
      ? 'Google Play Games bağlı değil'
      : 'Google Play Games not connected';

  static String overview(BuildContext context) =>
      _isTurkish(context) ? 'Genel bakış' : 'Overview';

  static String performance(BuildContext context) =>
      _isTurkish(context) ? 'Performans' : 'Performance';

  static String accountAndSocial(BuildContext context) =>
      _isTurkish(context) ? 'Hesap ve sosyal' : 'Account & social';

  static String totalMatches(BuildContext context) =>
      _isTurkish(context) ? 'Toplam maç' : 'Total matches';

  static String losses(BuildContext context) =>
      _isTurkish(context) ? 'Mağlubiyet' : 'Losses';

  static String draws(BuildContext context) =>
      _isTurkish(context) ? 'Beraberlik' : 'Draws';

  static String countryRank(BuildContext context) =>
      _isTurkish(context) ? 'Ülke sırası' : 'Country rank';

  static String achievements(BuildContext context) =>
      _isTurkish(context) ? 'Başarımlar' : 'Achievements';

  static String loading(BuildContext context) =>
      _isTurkish(context) ? 'Yükleniyor…' : 'Loading…';

  static String noData(BuildContext context) =>
      _isTurkish(context) ? 'Gösterilecek veri yok.' : 'No data to show.';
}
