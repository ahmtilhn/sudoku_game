# Manual Actions Required

Generated on 2026-07-26 for PR #21.

Current Google Play Console execution checklist:
`docs/GOOGLE_PLAY_CONSOLE_RELEASE_TASKS.md`.

## A. Google Play Internal Test

Neden gerekli:
- `versionCode 3` AAB, versionCode 2'deki WorkManager startup crash hotfix'ini doğrulamalı.

Nerede yapılacak:
- Google Play Console.

Adımlar:
1. `build/app/outputs/bundle/release/app-release.aab` dosyasını internal testing track'e yükle.
2. Yeni release oluştur ve tester grubuna dağıt.
3. Test cihazında eski uygulamayı kaldır.
4. Play Store internal test linkinden yeniden kur.
5. Uygulama bilgisi veya Play Console üzerinden `versionCode 3` olduğunu doğrula.
6. Cold start, Settings, Daily Sudoku, Career, Online Duel ve reklam/hint akışlarını aç.
7. Android Vitals ve pre-launch report sonuçlarını incele.
8. Crash olursa stack trace'i Crashlytics ve Play Console'dan indir.

Beklenen sonuç:
- Play'den kurulan versionCode 3 açılışta çökmez.

Doğrulama:
- Cold start başarılı, Android Vitals yeni startup crash göstermiyor.

Yapılmazsa etkisi:
- versionCode 2 crash fix'i gerçek Play dağıtımında kanıtlanmaz.

Gizlilik/güvenlik uyarısı:
- AAB dışında keystore, şifre veya `android/key.properties` yükleme/paylaşma.

## B. Firebase App Check

Neden gerekli:
- App Check kodda hazır, ancak enforcement otomatik açılmadı.

Nerede yapılacak:
- Firebase Console.

Adımlar:
1. Android app için Play Integrity provider'ı kontrol et.
2. Play App Signing SHA fingerprintlerini Firebase Android app'e ekle.
3. iOS için App Attest ve DeviceCheck yapılandırmasını tamamla.
4. Metrics ekranında geçerli token trafiğini birkaç gün izle.
5. Enforcement'ı hemen açma.
6. Yalnızca başarılı token oranı kabul edilebilir seviyedeyse kademeli enforcement planı uygula.

Beklenen sonuç:
- App Check tokenları production cihazlarda geçerli görünür.

Doğrulama:
- Firebase App Check metrics invalid oranı düşük.

Yapılmazsa etkisi:
- Backend/Firebase kaynakları abuse'a karşı daha zayıf kalır.

Gizlilik/güvenlik uyarısı:
- Apple `.p8` private key repoya girmemeli.

## C. Firebase Crashlytics

Neden gerekli:
- Startup crash fix'inin production telemetry ile izlenmesi gerekiyor.

Nerede yapılacak:
- Firebase Console.

Adımlar:
1. Internal test build'de kontrollü test crash akışı kullan.
2. Crashlytics dashboard'da event göründüğünü doğrula.
3. Release mapping/symbol durumunu kontrol et.
4. VersionCode 3 için crash-free startup oranını izle.

Beklenen sonuç:
- Crashlytics versionCode 3 eventlerini alır.

Doğrulama:
- Dashboard'da test crash ve build version bilgisi görünür.

Yapılmazsa etkisi:
- Play internal test crash'leri görünmeden kalabilir.

Gizlilik/güvenlik uyarısı:
- Crash loglarına kişisel veri veya secret yazdırma.

## D. Firebase Analytics

Neden gerekli:
- Settings'teki analytics consent switch'i gerçek event davranışıyla doğrulanmalı.

Nerede yapılacak:
- Firebase Console DebugView.

Adımlar:
1. Debug cihazda Analytics DebugView'i aç.
2. Settings > Analytics sharing switch'ini aç.
3. Uygulamada temel ekranları gez.
4. Switch'i kapat ve yeni event akışının durduğunu doğrula.

Beklenen sonuç:
- Kullanıcı consent'i event collection davranışını değiştirir.

Doğrulama:
- DebugView eventleri switch açıkken gelir, kapalıyken durur.

Yapılmazsa etkisi:
- Store data-safety beyanları kanıtlanamaz.

Gizlilik/güvenlik uyarısı:
- Analytics eventlerinde raw player ID, FCM token veya e-posta göndermeme.

## E. Firebase Cloud Messaging

Neden gerekli:
- Challenge push opt-in/opt-out uçtan uca test edilmeli.

Nerede yapılacak:
- Firebase Console, Cloudflare Worker, Android/iOS test cihazları.

Adımlar:
1. `SOCIAL_BACKEND_URL` ile build/run yap.
2. Online challenge notifications switch'ini aç.
3. Permission prompt'u kabul et.
4. Backend'de token kaydını doğrula.
5. Foreground challenge notification test et.
6. Background ve terminated state test et.
7. Switch'i kapat.
8. Worker'da token `enabled = 0` olduğunu doğrula.
9. Token refresh sonrası yeni token kaydını test et.

Beklenen sonuç:
- Opt-in olmadan token backend'e gitmez, opt-out eski tokenı disable eder.

Doğrulama:
- `DELETE /v1/me/devices/current` `{ ok: true }` döner.

Yapılmazsa etkisi:
- Kullanıcı kapattığı halde challenge push alabilir veya hiç push alamayabilir.

Gizlilik/güvenlik uyarısı:
- FCM token public payloadlarda dönmemeli.

## F. Cloudflare

Neden gerekli:
- Sosyal backend deploy edilmeden online social/challenge akışı production çalışmaz.

Nerede yapılacak:
- Cloudflare dashboard ve Wrangler CLI.

Adımlar:
1. `cd backend/social_worker`.
2. `npx wrangler login`.
3. D1 database oluştur.
4. `wrangler.example.toml` temel alınarak local `wrangler.toml` hazırla.
5. `npm run db:remote` ile migration uygula.
6. FCM secrets ekle.
7. `npm run deploy`.
8. `/health` endpointini test et.
9. Flutter build/run komutuna `--dart-define=SOCIAL_BACKEND_URL=https://...` ekle.
10. İki Firebase anonymous kullanıcı ile friend/challenge akışını test et.

Beklenen sonuç:
- Worker health endpoint `{ ok: true }` döner ve authenticated endpointler çalışır.

Doğrulama:
- Search, friend request, challenge, token register/disable endpointleri başarılı.

Yapılmazsa etkisi:
- Online social UI backend unavailable durumda kalır.

Gizlilik/güvenlik uyarısı:
- `wrangler.toml` içinde secret varsa commit etme; `.dev.vars` commit etme.

## G. FCM Service Account

Neden gerekli:
- Worker'ın FCM HTTP v1 mesajı göndermesi için server credential gerekir.

Nerede yapılacak:
- Google Cloud IAM ve Cloudflare secrets.

Adımlar:
1. Minimum yetkili service account oluştur.
2. Firebase Messaging gönderim yetkisini ver.
3. Private key JSON indir.
4. Sadece `FCM_CLIENT_EMAIL` ve `FCM_PRIVATE_KEY` olarak Wrangler secret gir.
5. JSON dosyasını local güvenli alanda tut veya imha et.

Beklenen sonuç:
- Worker FCM access token alıp challenge bildirimi gönderebilir.

Doğrulama:
- Challenge create sonrası alıcı cihaza FCM gelir.

Yapılmazsa etkisi:
- Pending challenge kaydı oluşur ama remote push gitmez.

Gizlilik/güvenlik uyarısı:
- Service account JSON ve private key repoya kesinlikle girmemeli.

## H. Google Play Games

Neden gerekli:
- Play Games temel project/web client ayarları localde var; leaderboard/achievement store ürünleri eksik.

Nerede yapılacak:
- Google Play Console ve Google Cloud Console.

Adımlar:
1. Play Games Services configuration'ı aç.
2. Android OAuth client için package `com.devoviastudio.sudoku` ve SHA fingerprintlerini doğrula.
3. Web OAuth client'ı game server credential olarak bağla.
4. Test users ekle.
5. Global rating leaderboard oluştur.
6. First online win achievement oluştur.
7. Oluşan ID'leri `android/app/src/main/res/values/services.xml` ve iOS xcconfig dosyalarına gir.
8. PGS config'i testers'a publish et.
9. Sign-in, leaderboard, achievement ve server auth code testlerini yap.

Beklenen sonuç:
- PGS sign-in ve native UI'lar test track build'inde çalışır.

Doğrulama:
- `requestServerAuthCode` non-empty one-time code döndürür.

Yapılmazsa etkisi:
- Leaderboard/achievement fonksiyonları `not_configured` döner.

Gizlilik/güvenlik uyarısı:
- OAuth client secret uygulamaya veya repoya eklenmemeli.

## I. AdMob

Neden gerekli:
- Kodda test AdMob App ID ve rewarded unit kullanılıyor.

Nerede yapılacak:
- AdMob, Google Play Console.

Adımlar:
1. Gerçek Android App ID oluştur.
2. Rewarded ad unit oluştur.
3. Test device tanımla.
4. UMP form ve GDPR/EEA akışını test et.
5. Privacy options gerekliliğini Settings'te doğrula.
6. Meta/Unity mediation app ve placement ayarlarını tamamla.
7. `app-ads.txt` yayınla.
8. Production reklam ID'lerini güvenli build-time config olarak ver.

Beklenen sonuç:
- Test ortamında test reklamları, production ortamında doğru gerçek ID'ler kullanılır.

Doğrulama:
- UMP consent reddedilince uygulama çökmez ve reklam request davranışı beklenen olur.

Yapılmazsa etkisi:
- Monetization production'a hazır olmaz.

Gizlilik/güvenlik uyarısı:
- Gerçek reklam kimliklerini test build'inde yanlışlıkla kullanma.

## J. Google Play Policy

Neden gerekli:
- Firebase, Cloudflare, AdMob, push ve social graph veri beyanı gerektirir.

Nerede yapılacak:
- Google Play Console.

Adımlar:
1. Data Safety formunu gerçek veri akışına göre doldur.
2. Privacy Policy yayınla.
3. Notification disclosure metnini doğrula.
4. Firebase/Cloudflare/AdMob data collection maddelerini ekle.
5. Account deletion gereksinimi için plan ve URL hazırla.
6. Test credentials gerekiyorsa Play review alanına ekle.

Beklenen sonuç:
- Play policy review için data beyanları kodla uyumlu olur.

Doğrulama:
- Store listing ve privacy policy aynı veri türlerini söyler.

Yapılmazsa etkisi:
- Release review reddedilebilir.

Gizlilik/güvenlik uyarısı:
- Kullanıcıya kapatma imkanı sunduğun veri toplama tercihlerini doğru beyan et.

## K. Release Signing

Neden gerekli:
- Release build debug key'e fallback yapmıyor; upload keystore güvenli yönetilmeli.

Nerede yapılacak:
- Local secure storage, Google Play Console, Firebase.

Adımlar:
1. Upload keystore yedeğini güvenli ortamda sakla.
2. Şifreleri password manager'a kaydet.
3. Play App Signing certificate SHA-1/SHA-256 değerlerini Firebase'e ekle.
4. Upload certificate SHA değerini doğrula.
5. Key kaybolursa Play key reset sürecini belgeye ekle.

Beklenen sonuç:
- Release AAB upload key ile imzalanır.

Doğrulama:
- `keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab`.

Yapılmazsa etkisi:
- AAB Play'e yüklenemez veya Firebase/PGS sign-in çalışmayabilir.

Gizlilik/güvenlik uyarısı:
- `android/key.properties`, `.jks`, `.keystore` commit edilmemeli.

## L. R8

Neden gerekli:
- Version 3 hotfix minify/shrink kapalı; kalıcı çözüm için R8 geri açılmalı.

Nerede yapılacak:
- Ayrı internal test branch/build.

Adımlar:
1. Version 3 stabil olduktan sonra ayrı build'de minify aç.
2. Mapping upload et.
3. WorkManager/Room cold start doğrula.
4. Gerekirse küçük keep rules ekle.
5. Sonra resource shrink'i ayrı build'de test et.

Beklenen sonuç:
- Minified build Play internal testte çökmez.

Doğrulama:
- Crashlytics/Android Vitals startup crash göstermiyor.

Yapılmazsa etkisi:
- APK/AAB boyutu ve obfuscation production için eksik kalır.

Gizlilik/güvenlik uyarısı:
- Mapping dosyalarını public paylaşma.

## M. iOS

Neden gerekli:
- iOS Firebase config var, ancak Apple hesap/capability işleri manuel.

Nerede yapılacak:
- Apple Developer, App Store Connect, Firebase Console, AdMob.

Adımlar:
1. APNs `.p8` key oluştur ve Firebase'e yükle.
2. Push Notifications capability aç.
3. Provisioning profiles yenile.
4. Game Center capability ve products oluştur.
5. App Check DeviceCheck/App Attest ayarlarını tamamla.
6. TestFlight build al.
7. AdMob iOS App ID ve rewarded unit gir.
8. ATT açıklaması ve privacy manifest'i doğrula.
9. Physical device push/Game Center/ads testi yap.

Beklenen sonuç:
- iOS TestFlight build Firebase, push, Game Center ve ads açısından çalışır.

Doğrulama:
- Physical device foreground/background push testi.

Yapılmazsa etkisi:
- iOS release hazır olmaz.

Gizlilik/güvenlik uyarısı:
- APNs `.p8` private key repoya girmemeli.

## N. Online Ranked Duel

Neden gerekli:
- Mevcut Durable Object transport authoritative ranked game engine değildir.

Nerede yapılacak:
- Backend implementation.

Adımlar:
1. Server-side puzzle generation ekle.
2. Shared seed ve board state tut.
3. Move validation server-side yap.
4. Reconnect snapshot, timeout, forfeit ve settlement ekle.
5. Rating/stat/recent opponent yazımlarını server-derived hale getir.
6. Anti-cheat ve audit log ekle.

Beklenen sonuç:
- Ranked sonuçlar istemci iddiasına bağlı olmaz.

Doğrulama:
- Modified client invalid move/win claim kabul edilmez.

Yapılmazsa etkisi:
- Ranked mode production'a güvenli çıkamaz.

Gizlilik/güvenlik uyarısı:
- Platform ID'leri ve private player data public payloadlara dönmemeli.

## O. PR #21

Neden gerekli:
- PR merge edilmeden önce final review ve store/cloud manuel doğrulamaları tamamlanmalı.

Nerede yapılacak:
- GitHub.

Adımlar:
1. PR checks ve bu raporu incele.
2. Internal test AAB yükleme sonucunu bekle.
3. Cloudflare deploy ve FCM uçtan uca test sonuçlarını ekle.
4. Draft'tan çıkarma şartlarını karşıla.
5. Merge öncesi main ile güncel olduğundan emin ol.
6. Merge sonrası main'de `flutter analyze`, `flutter test`, release build doğrula.

Beklenen sonuç:
- PR merge edildiğinde main release hazırlığı bozulmaz.

Doğrulama:
- PR #21 clean, test/build sonuçları güncel.

Yapılmazsa etkisi:
- Eksik cloud/store işleri production release'i bloklar.

Gizlilik/güvenlik uyarısı:
- PR'a secret, keystore veya private key ekleme.

| Öncelik | Görev | Zorunlu mu | Tahmini süre | Blokladığı alan |
|---|---|---:|---:|---|
| P0 Kritik | Google Play internal test versionCode 3 | Evet | 1-2 saat | Android release |
| P0 Kritik | Cloudflare deploy + FCM secrets | Evet | 1-2 saat | Online challenge push |
| P0 Kritik | Release signing backup and fingerprint verification | Evet | 30 dk | Play upload, Firebase/PGS |
| P1 Yayın öncesi | Firebase App Check metrics | Evet | 1-3 gün izleme | Enforcement |
| P1 Yayın öncesi | Crashlytics test crash | Evet | 30 dk | Release monitoring |
| P1 Yayın öncesi | Analytics DebugView consent test | Evet | 30 dk | Data Safety |
| P1 Yayın öncesi | FCM foreground/background/terminated test | Evet | 1 saat | Notifications |
| P1 Yayın öncesi | Google Play policy forms | Evet | 1-2 saat | Store review |
| P1 Yayın öncesi | AdMob production setup | Evet | 1-2 saat | Monetization |
| P1 Yayın öncesi | Play Games leaderboard/achievement IDs | Evet | 1 saat | PGS features |
| P2 Sonraki geliştirme | iOS TestFlight setup | Evet, iOS için | 1 gün | iOS release |
| P2 Sonraki geliştirme | Online ranked authoritative server | Evet, ranked için | Çok gün | Ranked production |
| P3 Teknik borç | R8 re-enable experiment | Hayır, hotfix sonrası | 1-2 gün | Optimization/obfuscation |

