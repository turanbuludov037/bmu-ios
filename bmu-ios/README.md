# BMU Mobil — iOS (Swift + SwiftUI, Liquid Glass)

Mac olmadan iOS tətbiqi: kod burada, build-i GitHub-ın Mac serveri edir (public repoda pulsuz).

## 1. GitHub-a yüklə
1. github.com → sağ yuxarıda **+** → **New repository**
2. Ad: `bmu-ios`, **Public** seç (Mac build-ləri yalnız public repoda limitsiz pulsuzdur). README əlavə ETMƏ → **Create repository**
3. Açılan səhifədə **"uploading an existing file"** linkinə bas
4. Bu zip-i aç, içindəki HAMISINI (`BMU` qovluğu, `.github` qovluğu, `project.yml`, `.gitignore`, `README.md`) brauzerə sürüklə
   - `.github` qovluğu görünmürsə: Windows Explorer → **Görünüş → Gizli elementlər** işarələ
5. Aşağıda **Commit changes**

> `.github` yüklənməyibsə: repoda **Add file → Create new file**, ad yerinə `.github/workflows/ios.yml` yaz,
> zip-dəki `ios.yml`-in məzmununu yapışdır → **Commit changes**.

## 2. Build-i izlə
1. Repoda yuxarıda **Actions** tab-ı → **iOS build** (yükləyən kimi özü başlayır, ~10–15 dəq)
2. Yaşıl ✓ → build-ə daxil ol → aşağıda **Artifacts → BMU-ipa** → endir (zip-dir, içində `BMU.ipa`)
3. Qırmızı ✗ → səhifədəki xəta sətirlərini (və ya `build-log`) Claude-a göndər, düzəltsin

## 3. iPhone-a qoy (pulsuz, Sideloadly ilə)
1. Kompüterə **iTunes** (Apple saytından, Microsoft Store versiyası yox) və **Sideloadly** (sideloadly.io) qur
2. iPhone-u kabellə qoş, telefonda **"Bu kompüterə etibar et"**
3. Sideloadly: `BMU.ipa`-nı sürüklə → Apple ID yaz → **Start**
4. iPhone: **Parametrlər → Ümumi → VPN və cihaz idarəetməsi** → öz Apple ID-ni seç → **Etibar et**
5. iPhone: **Parametrlər → Məxfilik və təhlükəsizlik → Developer Mode** → aç (telefon yenidən başlayır)

Pulsuz Apple ID ilə tətbiq **7 gün** işləyir, sonra Sideloadly ilə yenidən qoymaq lazımdır.
99$/il Apple Developer hesabı ilə bu məhdudiyyət yoxdur və App Store / TestFlight açılır.

## Nə var (1-ci mərhələ)
- Giriş (my.beu.edu.az), "Məni xatırla" — şifrə iPhone Keychain-də
- Ana səhifə: profil, şəkil, bu gün və sabahın dərsləri ("İndi" nişanı)
- Cədvəl: həftə zolağı, sürüşdürərək gün dəyişmə
- Qiymətlər: semestr seçimi, giriş balı, hərf, "imtahandan nə qədər lazımdır"
- Jurnal: qaib faizi, limit xəbərdarlığı
- Profil: bütün məlumatlar, çıxış
- Dizayn: iOS 26 Liquid Glass (köhnə iOS-da buzlu şüşə)
