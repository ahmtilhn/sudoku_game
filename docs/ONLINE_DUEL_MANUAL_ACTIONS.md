# Online Duel Manual Actions

## Cloudflare remote D1 migration

Neden gerekli:
Remote database schema local migration ile otomatik değişmez.

Nerede:
Cloudflare dashboard and `backend/social_worker`.

Adımlar:
1. Remote D1 backup al.
2. `wrangler d1 migrations list sudoku-duel-social --remote --config wrangler.toml` ile durumu kontrol et.
3. `wrangler d1 migrations apply sudoku-duel-social --remote --config wrangler.toml` çalıştır.
4. `matches`, `match_players`, `player_ratings`, `match_audit`, `ranked_queue`, `match_settlements` tablolarını doğrula.

Beklenen sonuç:
`0002_authoritative_online_duel.sql` remote DB'de applied görünür.

Doğrulama:
Remote D1 query ile tablolar ve indexler görünür.

Yapılmazsa:
Ranked matchmaking, settlement ve leaderboards çalışmaz.

## Durable Object deployment

Neden gerekli:
Canlı maç state'i `GameRoom` Durable Object içindedir.

Nerede:
`wrangler.toml` ve Cloudflare Workers.

Adımlar:
1. `GAME_ROOMS` binding'ini gerçek Worker config'e ekle.
2. `MATCHMAKING_QUEUE` binding'ini ekle.
3. Durable Object migration `new_sqlite_classes` kayıtlarını doğrula.
4. Önce staging deploy yap.
5. Staging iki cihaz testi bitmeden production deploy yapma.

Beklenen sonuç:
WebSocket upgrade `/v1/rooms/:roomId/connect` üzerinden DO'ya ulaşır.

Doğrulama:
Staging Worker logs, WebSocket 101 response, `connected` event.

Yapılmazsa:
Online duel room açılamaz.

## Worker secrets

Neden gerekli:
FCM ve Firebase doğrulamaları secret gerektirir.

Nerede:
Wrangler secrets.

Adımlar:
1. Minimum permission service account oluştur.
2. `wrangler secret put FCM_CLIENT_EMAIL`.
3. `wrangler secret put FCM_PRIVATE_KEY`.
4. Secret değerlerini Git'e, `.dev.vars` içine veya PR'a yazma.

Beklenen sonuç:
Challenge/result push gönderilebilir.

Doğrulama:
Staging cihazda push ve Worker logs.

Yapılmazsa:
Push bildirimleri atlanır.

## Staging Worker URL

Neden gerekli:
Flutter `SOCIAL_BACKEND_URL` olmadan production sosyal backend'e bağlanır.
Staging testi için URL açıkça verilmelidir.

Nerede:
Flutter build args and CI.

Adımlar:
1. HTTPS staging URL belirle.
2. WSS connect URL'sini doğrula.
3. `/health` endpointini kontrol et.
4. Testteki her cihazı aynı `--dart-define=SOCIAL_BACKEND_URL=...` ile build et.

Beklenen sonuç:
REST ve WebSocket aynı staging host'u kullanır.

Doğrulama:
İki test hesabı profil ve room connect yapabilir.

Yapılmazsa:
Online UI hata gösterir, offline oyun devam eder.

## Staging preflight araçları

Neden gerekli:
İki cihaz testine başlamadan önce local kod, config, health/version endpointleri,
puzzle bankası ve çeviriler aynı kapıdan doğrulanmalıdır.

Nerede:
`tool/online_duel_staging_preflight.ps1`

Adımlar:
1. Gerçek HTTPS staging Worker URL'sini hazırla.
2. `powershell -ExecutionPolicy Bypass -File .\tool\online_duel_staging_preflight.ps1 -BackendUrl "https://..."` çalıştır.
3. Placeholder uyarılarını gider.
4. `/health` ve `/version` sonuçlarını doğrula.

Beklenen sonuç:
Preflight secret değeri yazdırmadan tamamlanır.

Doğrulama:
Script backend tests, puzzle verify, localization quality, Flutter analyze/test
ve endpoint kontrollerini raporlar.

Yapılmazsa:
İki cihaz testine eksik config ile başlanabilir.

## Otomatik iki oyunculu smoke test

Neden gerekli:
REST + WebSocket + settlement + leaderboard akışını gerçek staging backend'de
iki Firebase hesabıyla kanıtlar.

Nerede:
`backend/social_worker/scripts/two_player_duel_smoke.ts` ve
`backend/social_worker/scripts/ranked_duel_smoke.ts`

Adımlar:
1. `SOCIAL_BACKEND_URL` değerini staging Worker URL'si yap.
2. `PLAYER_A_ID_TOKEN` ve `PLAYER_B_ID_TOKEN` değerlerini güvenli shell
   environment olarak ver.
3. Varsa `PLAYER_A_APP_CHECK_TOKEN` ve `PLAYER_B_APP_CHECK_TOKEN` ekle.
4. Token değerlerini loglama.
5. `npm run smoke:two-player` çalıştır.
6. `npm run smoke:ranked` çalıştır.

Beklenen sonuç:
İki script de `PASS` ile biter; yalnız kısaltılmış match hash, revision ve
result yazar.

Doğrulama:
Exit code `0`, Worker logs ve D1 match/history/rating kayıtları tutarlı.

Yapılmazsa:
`READY FOR TWO-DEVICE STAGING TEST` kod kapısı geçilmiş olsa da staging ortamı
kanıtlanmış sayılmaz.

## App Check

Neden gerekli:
Custom backend abuse riskini azaltır.

Nerede:
Firebase Console and Worker config.

Adımlar:
1. Android/iOS App Check provider'larını yapılandır.
2. Staging'de `REQUIRE_APP_CHECK=false` bırak.
3. Metrics'te iki cihazın token gönderdiğini doğrula.
4. Backend token verification eşdeğerini staging'de test et.
5. Sonra production için `REQUIRE_APP_CHECK=true` değerlendir.

Beklenen sonuç:
Geçersiz App Check istekleri reddedilebilir.

Doğrulama:
Geçerli token geçer, eksik token 403 alır.

Yapılmazsa:
Auth devam eder ama app attestation production gate'i kapanmaz.

## Google Play internal test

Neden gerekli:
AAB fiziksel cihaz dağıtımı ve Play signing doğrulaması gerektirir.

Nerede:
Google Play Console.

Adımlar:
1. `versionCode 4` AAB yükle.
2. Internal tester grubuna iki farklı Google hesabı ekle.
3. İki fiziksel Android cihazda yükle.

Beklenen sonuç:
İki cihaz aynı staging backend'e bağlanır.

Doğrulama:
Challenge, ranked queue, reconnect ve result ekranı geçer.

Yapılmazsa:
Production-ready kararı verilemez.

## İki cihaz challenge testi

Neden gerekli:
Gerçek ağ, Auth, WebSocket, DO ve UI entegrasyonunu kanıtlar.

Nerede:
İki fiziksel Android cihaz.

Adımlar:
1. A ve B profil oluşturur.
2. Arkadaşlık kurulur.
3. A challenge gönderir.
4. B kabul eder.
5. İki taraf ready olur.
6. Doğru/yanlış hamle, timer, forfeit ve result denenir.

Beklenen sonuç:
İki cihaz aynı board/revision/result görür.

Doğrulama:
Worker logs ve UI sonuçları eşleşir.

Yapılmazsa:
Staging-ready sayılmaz.

## Öncelik tablosu

| Öncelik | Görev | Zorunlu | Tahmini süre | Blokladığı alan |
|---|---|---:|---:|---|
| P0 | Remote D1 migration | Evet | 30 dk | İki cihaz test |
| P0 | Staging Worker deploy | Evet | 45 dk | İki cihaz test |
| P0 | Staging preflight | Evet | 30 dk | İki cihaz test |
| P0 | Two-player smoke scripts | Evet | 30 dk | İki cihaz test |
| P0 | Staging URL ile AAB/internal test | Evet | 60 dk | İki cihaz test |
| P0 | İki cihaz challenge/ranked smoke | Evet | 90 dk | Staging-ready |
| P1 | App Check enforcement doğrulama | Evet | 60 dk | Production |
| P1 | Abuse ve settlement retry testleri | Evet | 90 dk | Production |
| P1 | Privacy/Data Safety güncellemesi | Evet | 60 dk | Production |
| P2 | Load/cost monitoring alerts | Hayır | 60 dk | Operasyon |

