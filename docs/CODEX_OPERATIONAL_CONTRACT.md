# Codex Operasyon Sozlesmesi

Bu belge, Sudoku Duel kod tabaninda Codex veya baska bir otomasyon araci calisirken online servislerin, profil ayarlarinin, bayrak tercihlerinin, ELO/RP verilerinin ve Coin ekonomisinin tekrar tekrar bozulmasini onlemek icin zorunlu calisma kurallarini tanimlar.

Bu belge bir tercih degil, degisiklik kabul kapisidir. Bir adim tamamlanmadan sonraki adima gecilmez. Bir kontrol basarisizsa deploy yapilmaz ve hata gizlenmez.

## 1. Temel Ilkeler

- `staging` ve `production` hicbir zaman karistirilmaz.
- Flutter istemcisi hangi Worker'a baglanacaksa build sirasinda acikca `SOCIAL_BACKEND_URL` ile belirtilir.
- REST ve WebSocket ayni Worker hostunu kullanir.
- Firebase ID token kimlik icindir; Firebase App Check token attestation icindir. Birbirinin yerine kullanilmaz.
- App Check token yoksa istemci, sadece backend `REQUIRE_APP_CHECK=false` olan ortamlarda istegi App Check header'i olmadan gonderebilir. Bos header gonderilmez.
- Production'da `REQUIRE_APP_CHECK=true` olmadan promotion yapilmaz.
- D1 migration uygulanmadan Worker deploy edilmez.
- Worker deploy edilmeden o Worker'a baglanan Flutter release build dagitilmaz.
- Her online sonuc server tarafinda authoritative kabul edilir. ELO, RP, Coin, escrow, history ve leaderboard client tarafindan hesaplanmaz.
- Runtime schema guard gecici emniyet kemeridir; migration yerine kullanilmaz.
- Token, secret, private key, keystore, App Check token veya Firebase ID token dosyaya, git'e, log'a, issue'ya ya da chat'e yazilmaz.
- Kullanici tarafinda yapilmamis degisiklikler geri alinmaz. Dirty worktree varsa once durum kaydedilir ve degisiklikler korunur.

## 2. Ortam Sozlesmesi

### Staging

- Worker: `https://sudoku-duel-social-staging.ilhanahmet246.workers.dev`
- Config: `backend/social_worker/wrangler.staging.toml`
- D1: `sudoku-duel-social-staging`
- `ENVIRONMENT = "staging"`
- `REQUIRE_APP_CHECK = "false"` test kolayligi icin kabul edilir.
- `ALLOW_TEST_PURCHASE_GRANTS = "true"` sadece staging icin kabul edilir.
- Flutter debug/profile testleri staging URL'siyle build edilir.

### Production

- Worker: `https://sudoku-duel-social-production.ilhanahmet246.workers.dev`
- Config: `backend/social_worker/wrangler.production.toml`
- D1: `sudoku-duel-social-production`
- `ENVIRONMENT = "production"`
- `REQUIRE_APP_CHECK = "true"` zorunludur.
- `ALLOW_TEST_PURCHASE_GRANTS = "false"` zorunludur.
- `DEBUG_UNLIMITED_COINS = "false"` zorunludur.
- Production release build staging URL'si alamaz.

### Build ortami

Staging APK:

```powershell
flutter build apk --debug `
  --dart-define=APP_ENVIRONMENT=staging `
  --dart-define=SOCIAL_BACKEND_URL=https://sudoku-duel-social-staging.ilhanahmet246.workers.dev `
  --dart-define=BUILD_COMMIT=(git rev-parse HEAD)
```

Production AAB:

```powershell
flutter build appbundle --release `
  --dart-define=APP_ENVIRONMENT=production `
  --dart-define=SOCIAL_BACKEND_URL=https://sudoku-duel-social-production.ilhanahmet246.workers.dev `
  --dart-define=BUILD_COMMIT=(git rev-parse HEAD)
```

Build commit'i Worker `/version` cevabindaki `buildCommit` ile eslesmiyorsa build test edilmiyor kabul edilir.

## 3. Codex'in Her Islemden Once Yapacagi Kontrol

1. `git status --short` ile kullanici degisikliklerini gor.
2. Ilgili dosyayi ve en yakin test/call-site'i oku.
3. Tek bir falsifiable hipotez yaz: hangi kod yolu davranisi kontrol ediyor ve hangi ucuz test hipotezi curutebilir?
4. Ortam secimini belirle: staging mi production mi? Varsayim yapilmaz.
5. Production'a etkisi olan bir degisiklikse config, migration, Worker route ve istemci build parametrelerini birlikte incele.
6. Migration veya deploy gerekiyorsa uygulanacak komutu, hedef database'i ve beklenen sonucu onceden belirle.
7. Secret veya token gerekiyorsa degeri istemez, loglamaz ve dosyaya yazmaz. Kullanici terminalde kendisi saglamalidir.

## 4. Codex'in Her Degisiklikten Sonra Yapacagi Kontrol

Ilk editten hemen sonra en dar executable kontrol calistirilir:

- Dart degisikligi: ilgili `flutter analyze` veya ilgili test.
- Worker degisikligi: `npm run typecheck` veya ilgili Vitest.
- Migration degisikligi: local schema/migration kontrolu.
- UI degisikligi: ilgili widget/regression testi.
- Matchmaking degisikligi: client queue testi ve backend matchmaking testleri.
- ELO/settlement degisikligi: ELO, settlement ve smoke testleri.

Sonra:

```powershell
git diff --check
```

Unrelated test failure ile ilgili degisiklik birbirinden ayrilir. Basarisiz test susturulmaz, silinmez veya `skip` edilmez. Test gercekten eski sozlesmeyi kontrol ediyorsa test guncellenir; davranis degismisse kod duzeltilir.

## 5. D1 Migration Protokolu

Yeni bir server tablo/kolon/index/trigger kullaniyorsa:

1. `backend/social_worker/migrations/` altina sirali, append-only SQL migration eklenir.
2. Daha once uygulanmis migration dosyasi degistirilmez.
3. SQL local D1'e uygulanir.
4. Typecheck ve Worker testleri calisir.
5. Staging remote migration listesi kontrol edilir.
6. Pending migration'lar staging'e uygulanir.
7. Staging Worker deploy edilir.
8. Staging endpoint ve schema tekrar kontrol edilir.
9. Iki cihaz ve smoke testleri basarili olmadan production migration uygulanmaz.
10. Production migration uygulanir.
11. Production Worker ayni kod commit'iyle deploy edilir.
12. Production `/health` ve `/version` kontrol edilir.

Komut semasi:

```powershell
cd backend/social_worker
npx wrangler d1 migrations list sudoku-duel-social-staging --remote --config wrangler.staging.toml
npx wrangler d1 migrations apply sudoku-duel-social-staging --remote --config wrangler.staging.toml
npx wrangler deploy --config wrangler.staging.toml
```

Production icin ayni sirada `production` database/config kullanilir. Migration uygulanmadan deploy etmek yasaktir.

Zorunlu online tablolar en az sunlardir:

- `players`
- `ranked_queue`
- `matches`
- `match_players`
- `match_settlements`
- `player_variant_ratings`
- `player_rank_progression`
- `rank_progression_settlements`
- `rank_reward_grants`
- `player_country_preferences`
- `match_coin_escrow`
- `match_coin_settlements`

## 6. Matchmaking Kabul Kriterleri

Bir matchmaking degisikligi ancak asagidakilerin tamami dogruysa kabul edilir:

- Iki farkli Firebase hesabi ayni Worker hostuna baglanir.
- Iki oyuncu ayni `variant` ve ayni `difficulty` ile queue'ya girer.
- Ilk oyuncu `status=queued` alir.
- Ikinci oyuncu `status=matched` ve `roomId` alir.
- Ilk oyuncunun polling istegi ayni queue kaydini yeniler ve `matched` gorur.
- `ranked_queue` eslesmis kayitlari `room_id IS NOT NULL` olarak isaretlenir veya cleanup migration'i ile secilemez durumda kalir.
- Ayni oyuncu aktif match varken ikinci room'a alinmaz.
- Queue stale kayitlari yeni oyuncuyu ghost oyuncuyla eslestiremez.
- Room ID URI encode/decode edilir.
- Iki socket `connected`, `game_screen_loaded`, `ready`, `match_started` olaylarini alir.
- Forfeit veya tamamlanma sonrasinda rating, history, Coin ve settlement tekil kalir.
- Polling timeout veya 4xx/5xx kullaniciya gorunur hata verir; sonsuz sessiz spinner kabul edilmez.

Client kurallari:

- App Check alma gecikmesi queue istegini 15 saniye bloklamaz; kisa timeout ile bos token'a doner.
- Bos `x-firebase-appcheck` header'i gonderilmez.
- ID token alinamiyorsa queue istegi gonderilmez ve auth hatasi gosterilir.
- 4xx hatalari retry durumuna cevrilmez; kullaniciya neden gosterilir.
- Polling sadece `queued` cevabindan sonra baslar.
- Cancel sirasinda in-flight queue request sonucu kontrol edilir; gec gelen `matched` sonucu kaybedilmez.

Zorunlu komutlar:

```powershell
cd backend/social_worker
npm run typecheck
npm test
npm run smoke:two-player
npm run smoke:ranked
```

Smoke tokenlari sadece gecici process environment olarak verilir ve degerleri yazdirilmaz.

## 7. Profil, Avatar, Frame ve Bayrak Kabul Kriterleri

### Avatar

- Secilebilir avatar key catalog ile sinirlidir: `preset_001` ... `preset_040`.
- Server yalnizca izin verilen preset key'lerini kabul eder.
- PUT `/v1/me/rank-profile` basariliysa 200 JSON profil doner.
- Response tekrar okununca secilen avatar ayni key ile gelir.
- Avatar kaydi basarisizsa eski profil local state'e kalici olarak yazilmaz.

### Frame ve badge

- Frame `auto` veya kullanici rank'i ile acilmis bir tier olmalidir.
- Kilitli frame secimi 409 `frame_locked` ile reddedilir.
- En fazla uc unlocked badge kaydedilir.
- Locked badge, duplicate badge veya dorduncu badge kabul edilmez.
- PUT `/v1/me/rank-profile` avatar/frame/title/badge secimlerini tutarli bir istek olarak gonderir.
- DB update sonrasi composite avatar tekrar uretilir.

### Bayrak

- Bayrak tercihi ayri endpoint'tir: `PUT /v1/me/rank-country`.
- `countryCode` iki harfli ISO kodu veya bos deger olmalidir.
- `countryFlagVisible` boolean olmalidir.
- `player_country_preferences` tablosu migration ile mevcut olmalidir; runtime guard sadece geri uyumluluk icindir.
- Bayrak kaydindan sonra GET ayni `countryCode` ve gorunurluk degerini donmelidir.
- Gizli bayrak leaderboard/public profile cevabinda `null` donmelidir.
- Avatar kaydi basarili, bayrak kaydi basarisizsa UI bunu tek bir belirsiz “server error” olarak gizlemez; hangi adimin basarisiz oldugunu belirtir.

Profil debug sirasi:

1. Firebase ID token var mi?
2. Worker URL staging mi production mi?
3. App Check eksik mi, yoksa invalid mi?
4. `/v1/me/rank-profile` response status/code nedir?
5. `/v1/me/rank-country` response status/code nedir?
6. D1'de `player_rank_progression`, `players.country_code` ve `player_country_preferences` var mi?
7. Server response 200 olduktan sonra UI response modelini uyguluyor mu?

## 8. ELO, RP ve Leaderboard Sozlesmesi

- Matchmaking rating sinyali `player_variant_ratings` tablosundan gelir.
- Ranked settlement global ve difficulty/variant rating satirlarini gunceller.
- Friendly veya cancelled match ELO degistirmez.
- `match_settlements` exactly-once korumasidir.
- Gorunur RP `player_rank_progression` ve `rank_progression_settlements` tarafinda tutulur.
- RP, authoritative match settlement tamamlandiktan sonra reconcile edilir.
- Rank rewards `rank_reward_grants` primary key'i ve idempotent trigger ile bir kez verilir.
- ELO leaderboard ve RP leaderboard birbirine karistirilmaz.
- UI hangi puani gosteriyorsa endpoint ve model adi bunu acikca belirtir.
- Leaderboard bos ise bunun nedeni network, auth, schema veya gercekten bos veri olarak ayrilir; hepsi “empty” diye yutulmaz.

## 9. Deploy Kapilari

### Staging deploy oncesi

- `git diff --check` basarili.
- Flutter ilgili analyzer/test basarili.
- Worker typecheck/test basarili.
- Tum pending D1 migration'lar listelenmis.
- Staging config staging database ve staging URL kullaniyor.
- Worker dry-run basarili.

### Staging deploy sonrasi

- `/health` 200 ve `ok=true`.
- `/version` environment `staging`.
- `/version` build commit beklenen commit.
- Authsiz endpoint beklenen 401/403 verir; 404/500 vermez.
- Iki token ranked smoke `PASS`.
- Iki fiziksel cihaz ayni staging AAB/APK ile test edilir.

### Production promotion oncesi

- Production config `REQUIRE_APP_CHECK=true`.
- Production config test grant ve unlimited coin kapali.
- Production config staging host/DB icermiyor.
- Production D1 tum migration'lari uygulamis.
- Staging iki cihaz testi basarili.
- Ranked WebSocket smoke basarili.
- Production dry-run basarili.
- Production App Check token metrikleri incelenmis.
- Production deploy, migration ve health/version ayni release commit'ini gosteriyor.

Production promotion icin mevcut kapı kullanilir:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\promote_production.ps1 `
  -BackendUrl "https://sudoku-duel-social-production.ilhanahmet246.workers.dev" `
  -BuildCommit (git rev-parse HEAD)
```

Bu kapı basarisizsa elle `wrangler deploy` ile kapatilamaz.

## 10. Hata Siniflandirma

- `401`: Firebase ID token eksik/gecersiz veya profil bulunamadi.
- `403`: App Check zorunlu ve token eksik/gecersiz; production enforcement sorunu.
- `409`: Coin yetersiz, frame locked, invalid badge, aktif match veya baska is kuralı.
- `422`: Gecersiz payload/variant/country/avatar.
- `503`: Worker, D1 schema veya gecici servis arizasi.
- Timeout: network/App Check provider/Worker gecikmesi. Retry sadece idempotent operation icin yapilir.

Hata loglama:

- Status code, route adi ve safe error code yazilabilir.
- Token, Authorization header, App Check header, request body icindeki secret yazilmaz.
- Server exception stack'i production kullaniciya gosterilmez ama Worker observability loglarinda correlation id ile izlenir.
- UI “server hatasi” demeden once response `code` degerini kullanir.

## 11. Rollback ve Kesinti Proseduru

1. Yeni release'te sorun varsa yeni client dagitimi durdurulur.
2. Worker onceki bilinen iyi commit'e geri alinabilir; D1 migration geri alinmaz, ileri uyumlu kodla kullanilir.
3. Yeni migration destructive degilse eski Worker'in yeni tabloyu gormemesi saglanir.
4. Migration destructive veya geriye uyumsuz ise backup ve explicit insan onayi olmadan islem yapilmaz.
5. Production App Check'i kapatmak kalici cozum degildir; sadece onayli incident prosedurunda gecici olarak yapilir.
6. Production config tekrar `REQUIRE_APP_CHECK=true`, test grant false ve unlimited coin false olmadan incident kapanmis sayilmaz.
7. Kesinti sonrasi D1 match, queue, rating, settlement ve coin ledger tutarlilik sorgulari calistirilir.

## 12. Codex'in Islem Sonu Raporu

Her degisiklik sonunda rapor su basliklari icermelidir:

1. Kök neden.
2. Degisen dosyalar ve davranis.
3. Migration/deploy yapildi mi, hangi ortamda?
4. Calistirilan testler ve sonuc.
5. Bilinen kalan hatalar ve scope disi nedenleri.
6. Kullanici cihazi icin kullanilacak build yolu ve backend URL.
7. Production'a gecis icin kalan manuel adimlar.

“Duzeldi” demek tek basina yeterli degildir. En az bir executable validation ve, server degisikliginde, health/version veya smoke kaniti raporlanir.

## 13. Son Kabul Matrisi

| Alan | Kod | Backend | D1 | Cihaz | Kabul |
|---|---|---|---|---|---|
| Matchmaking | queue/poll/cancel | Worker + DO | ranked_queue | 2 hesap | queued -> matched |
| Room | WebSocket | GameRoom | matches | 2 cihaz | connected -> started |
| ELO | settlement | GameRoom | player_variant_ratings | result screen | rating degisir |
| RP | reconciliation | rank routes | player_rank_progression | profile | RP degisir |
| Leaderboard | API/UI | leaderboard route | rating/RP rows | screen | entry + current rank |
| Avatar | PUT profile | rank profile route | progression/players | customization | GET ayni key |
| Frame/badge | PUT profile | validation route | progression/showcase | customization | locked reddedilir |
| Bayrak | PUT country | rank country route | players/preference | customization | GET ayni tercih |
| Coin | escrow/reward | economy/settlement | ledger/escrow | wallet | exactly once |

Bu tabloda bir satir gecmiyorsa release online-ready degildir.
