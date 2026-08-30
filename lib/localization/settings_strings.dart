import 'package:flutter/material.dart';

class SettingsStrings {
  const SettingsStrings._();

  static String hapticsTitle(BuildContext context) =>
      _value(context, _hapticsTitle);

  static String hapticsSubtitle(BuildContext context) =>
      _value(context, _hapticsSubtitle);

  static String soundEffectsTitle(BuildContext context) =>
      _value(context, _soundEffectsTitle);

  static String soundEffectsSubtitle(BuildContext context) =>
      _value(context, _soundEffectsSubtitle);

  static String privacyPolicyTitle(BuildContext context) =>
      _value(context, _privacyPolicyTitle);

  static String privacyPolicySubtitle(BuildContext context) =>
      _value(context, _privacyPolicySubtitle);

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
    'en':
        'Vibrate for taps, correct moves, mistakes and important game actions.',
    'tr':
        'Dokunma, doğru hamle, hata ve önemli oyun işlemlerinde titreşim kullan.',
    'de':
        'Vibriert bei Tippen, richtigen Zügen, Fehlern und wichtigen Spielaktionen.',
    'fr': 'Vibre lors des appuis, bons coups, erreurs et actions importantes.',
    'es':
        'Vibra al tocar, acertar, equivocarte y realizar acciones importantes.',
    'pt': 'Vibra em toques, jogadas corretas, erros e ações importantes.',
    'it': 'Vibra per tocchi, mosse corrette, errori e azioni importanti.',
    'nl': 'Trilt bij tikken, juiste zetten, fouten en belangrijke spelacties.',
    'pl':
        'Wibruje przy dotknięciach, poprawnych ruchach, błędach i ważnych akcjach.',
    'ru': 'Вибрация при нажатиях, верных ходах, ошибках и важных действиях.',
    'uk':
        'Вібрація під час натискань, правильних ходів, помилок і важливих дій.',
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

  static const Map<String, String> _soundEffectsTitle = <String, String>{
    'en': 'Sound effects',
    'tr': 'Ses efektleri',
    'de': 'Soundeffekte',
    'fr': 'Effets sonores',
    'es': 'Efectos de sonido',
    'pt': 'Efeitos sonoros',
    'it': 'Effetti sonori',
    'nl': 'Geluidseffecten',
    'pl': 'Efekty dźwiękowe',
    'ru': 'Звуковые эффекты',
    'uk': 'Звукові ефекти',
    'ar': 'المؤثرات الصوتية',
    'hi': 'ध्वनि प्रभाव',
    'id': 'Efek suara',
    'ja': '効果音',
    'ko': '효과음',
    'zh': '音效',
    'th': 'เอฟเฟกต์เสียง',
    'vi': 'Hiệu ứng âm thanh',
    'bn': 'সাউন্ড ইফেক্ট',
    'ur': 'صوتی اثرات',
  };

  static const Map<String, String> _soundEffectsSubtitle = <String, String>{
    'en': 'Play sounds for moves, results, rewards and important game actions.',
    'tr': 'Hamleler, sonuçlar, ödüller ve önemli oyun işlemlerinde ses çal.',
    'de':
        'Sounds bei Zügen, Ergebnissen, Belohnungen und wichtigen Spielaktionen.',
    'fr':
        'Joue des sons pour les coups, résultats, récompenses et actions importantes.',
    'es':
        'Reproduce sonidos para movimientos, resultados, recompensas y acciones importantes.',
    'pt':
        'Reproduz sons em jogadas, resultados, recompensas e ações importantes.',
    'it':
        'Riproduce suoni per mosse, risultati, ricompense e azioni importanti.',
    'nl':
        'Speel geluiden bij zetten, resultaten, beloningen en belangrijke spelacties.',
    'pl': 'Odtwarza dźwięki ruchów, wyników, nagród i ważnych akcji w grze.',
    'ru': 'Звуки ходов, результатов, наград и важных игровых действий.',
    'uk': 'Звуки ходів, результатів, нагород і важливих ігрових дій.',
    'ar': 'تشغيل أصوات للحركات والنتائج والمكافآت وإجراءات اللعب المهمة.',
    'hi': 'चाल, परिणाम, इनाम और महत्वपूर्ण गेम क्रियाओं के लिए ध्वनि चलाएँ।',
    'id': 'Putar suara untuk langkah, hasil, hadiah, dan aksi game penting.',
    'ja': '手、結果、報酬、重要なゲーム操作で効果音を再生します。',
    'ko': '수, 결과, 보상 및 중요한 게임 동작에 효과음을 재생합니다.',
    'zh': '在落子、结果、奖励和重要游戏操作时播放音效。',
    'th': 'เล่นเสียงสำหรับการเดิน ผลลัพธ์ รางวัล และการกระทำสำคัญในเกม',
    'vi':
        'Phát âm thanh cho nước đi, kết quả, phần thưởng và thao tác quan trọng.',
    'bn': 'চাল, ফলাফল, পুরস্কার ও গুরুত্বপূর্ণ গেম অ্যাকশনে শব্দ চালান।',
    'ur': 'چالوں، نتائج، انعامات اور اہم گیم ایکشنز کے لیے آواز چلائیں۔',
  };

  static const Map<String, String> _privacyPolicyTitle = <String, String>{
    'en': 'Privacy policy',
    'tr': 'Gizlilik politikası',
    'de': 'Datenschutzerklärung',
    'fr': 'Politique de confidentialité',
    'es': 'Política de privacidad',
    'pt': 'Política de privacidade',
    'it': 'Informativa sulla privacy',
    'nl': 'Privacybeleid',
    'pl': 'Polityka prywatności',
    'ru': 'Политика конфиденциальности',
    'uk': 'Політика конфіденційності',
    'ar': 'سياسة الخصوصية',
    'hi': 'गोपनीयता नीति',
    'id': 'Kebijakan privasi',
    'ja': 'プライバシーポリシー',
    'ko': '개인정보 처리방침',
    'zh': '隐私政策',
    'th': 'นโยบายความเป็นส่วนตัว',
    'vi': 'Chính sách quyền riêng tư',
    'bn': 'গোপনীয়তা নীতি',
    'ur': 'رازداری کی پالیسی',
  };

  static const Map<String, String> _privacyPolicySubtitle = <String, String>{
    'en': 'See how Sudoku Duel collects, uses and protects data.',
    'tr':
        'Sudoku Duel verilerinin nasıl toplandığını, kullanıldığını ve korunduğunu gör.',
    'de': 'Erfahre, wie Sudoku Duel Daten erhebt, verwendet und schützt.',
    'fr':
        'Découvrez comment Sudoku Duel collecte, utilise et protège les données.',
    'es': 'Consulta cómo Sudoku Duel recopila, usa y protege los datos.',
    'pt': 'Veja como o Sudoku Duel coleta, usa e protege dados.',
    'it': 'Scopri come Sudoku Duel raccoglie, usa e protegge i dati.',
    'nl': 'Bekijk hoe Sudoku Duel gegevens verzamelt, gebruikt en beschermt.',
    'pl': 'Zobacz, jak Sudoku Duel zbiera, wykorzystuje i chroni dane.',
    'ru': 'Узнайте, как Sudoku Duel собирает, использует и защищает данные.',
    'uk': 'Дізнайтеся, як Sudoku Duel збирає, використовує та захищає дані.',
    'ar': 'اطّلع على كيفية جمع Sudoku Duel للبيانات واستخدامها وحمايتها.',
    'hi': 'देखें कि Sudoku Duel डेटा कैसे एकत्र, उपयोग और सुरक्षित करता है।',
    'id':
        'Lihat cara Sudoku Duel mengumpulkan, menggunakan, dan melindungi data.',
    'ja': 'Sudoku Duel がデータを収集・利用・保護する方法を確認します。',
    'ko': 'Sudoku Duel이 데이터를 수집, 사용 및 보호하는 방법을 확인하세요.',
    'zh': '查看 Sudoku Duel 如何收集、使用和保护数据。',
    'th': 'ดูว่า Sudoku Duel เก็บ ใช้ และปกป้องข้อมูลอย่างไร',
    'vi': 'Xem cách Sudoku Duel thu thập, sử dụng và bảo vệ dữ liệu.',
    'bn': 'Sudoku Duel কীভাবে ডেটা সংগ্রহ, ব্যবহার ও সুরক্ষিত করে তা দেখুন।',
    'ur': 'دیکھیں کہ Sudoku Duel ڈیٹا کیسے جمع، استعمال اور محفوظ کرتا ہے۔',
  };
}
