# Sudoku Duel

Flutter ile geliştirilen sade Sudoku prototipi. İlk teslim online bağlantı eklemeden temel oyun döngüsünü doğrular.

## Hazır özellikler

- 4×4 etkileşimli başlangıç eğitimi
- Beş zorlukta 30 seviyelik kariyer
- Doğru çözümü doğrulanan ve dönüşümlerle çeşitlendirilen puzzle kataloğu
- Not alma, silme, geri alma ve ipucu
- Süre, hata, yıldız ve en iyi süre kaydı
- Her gün deterministik günlük Sudoku
- Aynı telefonda iki oyunculu düello
- Düelloda 10 saniyelik tur, doğru hamlede +10 ve yanlışta -5 puan
- Açık, koyu ve yüksek kontrast görünüm
- SharedPreferences ile local kariyer ve ayar kaydı
- Sudoku motoru ve ana ekran widget testleri

## Çalıştırma

```bash
flutter pub get
flutter run
```

## Doğrulama

Repo yapısını, importları ve puzzle/çözüm tutarlılığını Flutter SDK olmadan doğrulamak için:

```bash
python3 tool/validate_prototype.py
```

Tam Flutter doğrulaması için:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

## Sonraki faz

- Firebase Anonymous Auth
- Cloudflare Worker
- Matchmaker ve GameRoom Durable Objects
- WebSocket yeniden bağlantı
- Arkadaş odası ve hızlı eşleştirme

Detaylı sınırlar için `docs/ARCHITECTURE.md` dosyasına bakın.
