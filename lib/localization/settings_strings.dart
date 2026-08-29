import 'package:flutter/material.dart';

class SettingsStrings {
  const SettingsStrings._();

  static String hapticsTitle(BuildContext context) =>
      _value(context, _hapticsTitle);

  static String hapticsSubtitle(BuildContext context) =>
      _value(context, _hapticsSubtitle);

  static String _value(BuildContext context, Map<String, String> values) {
    final locale = Localizations.localeOf(context);
    return values[locale.languageCode] ?? values['en']!;
  }

  static const Map<String, String> _hapticsTitle = <String, String>{
    'en': 'Vibration feedback',
    'tr': 'Titreşim geri bildirimi',
    'de': 'Vibrationsfeedback',
    'fr': 'Retour par vibration',
    'es': 'Respuesta por vibración',
    'pt': 'Feedback por vibração',
    'it': 'Feedback con vibrazione',
    'nl': 'Trilfeedback',
    'pl': 'Wibracje',
    'ru': 'Виброотклик',
    'uk': 'Вібровідгук',
    'ar': 'ردود الفعل بالاهتزاز',
    'hi': 'वाइब्रेशन फीडबैक',
    'id': 'Umpan balik getaran',
    'ja': '振動フィードバック',
    'ko': '진동 피드백',
    'zh': '振动反馈',
    'th': 'การตอบสนองด้วยการสั่น',
    'vi': 'Phản hồi rung',
    'bn': 'ভাইব্রেশন ফিডব্যাক',
    'ur': 'وائبریشن فیڈبیک',
  };

  static const Map<String, String> _hapticsSubtitle = <String, String>{
    'en': 'Vibrate for taps, correct moves, mistakes and important game actions.',
    'tr': 'Dokunma, doğru hamle, hata ve önemli oyun işlemlerinde titreşim kullan.',
    'de': 'Vibriert bei Tippen, richtigen Zügen, Fehlern und wichtigen Spielaktionen.',
    'fr': 'Vibre lors des appuis, bons coups, erreurs et actions importantes.',
    'es': 'Vibra al tocar, acertar, equivocarte y realizar acciones importantes.',
    'pt': 'Vibra em toques, jogadas corretas, erros e ações importantes.',
    'it': 'Vibra per tocchi, mosse corrette, errori e azioni importanti.',
    'nl': 'Trilt bij tikken, juiste zetten, fouten en belangrijke spelacties.',
    'pl': 'Wibruje przy dotknięciach, poprawnych ruchach, błędach i ważnych akcjach.',
    'ru': 'Вибрация при нажатиях, верных ходах, ошибках и важных действиях.',
    'uk': 'Вібрація під час натискань, правильних ходів, помилок і важливих дій.',
    'ar': 'اهتزاز عند اللمس والحركات الصحيحة والأخطاء والإجراءات المهمة.',
    'hi': 'टैप, सही चाल, गलती और महत्वपूर्ण गेम क्रियाओं पर वाइब्रेट करें।',
    'id': 'Bergetar saat ketukan, langkah benar, kesalahan, dan aksi penting.',
    'ja': 'タップ、正解、ミス、重要なゲーム操作で振動します。',
    'ko': '탭, 정답, 실수 및 중요한 게임 동작에서 진동합니다.',
    'zh': '点击、正确操作、错误和重要游戏操作时振动。',
    'th': 'สั่นเมื่อแตะ เล่นถูก ทำผิด และทำสิ่งสำคัญในเกม',
    'vi': 'Rung khi chạm, đi đúng, mắc lỗi và thực hiện thao tác quan trọng.',
    'bn': 'ট্যাপ, সঠিক চাল, ভুল এবং গুরুত্বপূর্ণ গেম অ্যাকশনে ভাইব্রেট করুন।',
    'ur': 'ٹیپ، درست چال، غلطی اور اہم گیم ایکشن پر وائبریٹ کریں۔',
  };
}
