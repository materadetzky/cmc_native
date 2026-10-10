# CMC.CENTER Native Mobile App (Android & iOS)

Hivatalos natív mobilalkalmazás a **CMC.CENTER** rendszerhez ([center.cisztermedia-szfvar.hu](https://center.cisztermedia-szfvar.hu)).

Flutter keretrendszerre épülő, modern, sötét glassmorphic dizájnnal és fejlett WebView motorral ellátott hibrid natív kliens Android és iOS eszközökre.

---

## 📱 Főbb Funkciók (Key Features)

- **Hardveres & WebRTC Kamera Támogatás**:
  - Teljes körű kamerakezelés és engedélyezés a **Face ID arcfelismeréshez** és a **Leltár QR-kódos eszközolvasáshoz**.
  - Mikrofon és médiajogosultságok kezelése (`permission_handler` és natív `WebChromeClient` / `WKWebView`).
- **Beépített Letisztult Betöltő & Glassmorphic Hibakezelés**:
  - Dinamikusan pulzáló CMC.CENTER embléma és betöltési folyamatjelző.
  - Vészhelyzeti offline és kapcsolathiba képernyő azonnali egykattintásos újracsatlakozási lehetőséggel.
- **Kézreálló Mobil Ergonómia**:
  - **Pull-to-Refresh**: Lehúzással indítható azonnali lapfrissítés.
  - **Hardveres Vissza gomb (Android PopScope)**: Történeti visszalépés a belső oldalak között, véletlen kilépés elleni megerősítés a főoldalon.
  - **Külső Linkek Kezelése**: Telefonszámok (`tel:`), e-mailek (`mailto:`), SMS-ek közvetlen átadása a natív rendszeralkalmazásoknak.
- **Perzisztens Rendszer Stílus**:
  - Átlátszó állapotsor és sötét rendszer navigációs sáv a CMC.CENTER `#0d1117` arculatával összhangban.

---

## 🛠️ Architektúra & Követelmények

- **Flutter SDK**: `^3.47.0` (Dart 3.x)
- **Csomagok**:
  - `webview_flutter`: 4.x
  - `webview_flutter_android`: 4.x
  - `webview_flutter_wkwebview`: 3.x
  - `permission_handler`: 13.x
  - `url_launcher`: 6.x
- **Android célverziók**:
  - Min SDK: `21` (Android 5.0+)
  - Target SDK: `34+`
- **iOS célverziók**:
  - iOS 12.0+

---

## 🚀 Fejlesztés & Helyi Futtatás

```bash
# Függőségek letöltése
flutter pub get

# Statikus analízis ellenőrzése
flutter analyze

# Futtatás csatlakoztatott eszközön vagy emulátoron
flutter run

# Android APK építése
flutter build apk --release

# Android App Bundle (.aab) építése Google Play-hez
flutter build appbundle --release

# iOS futtató építése (macOS környezetben)
flutter build ios --release --no-codesign
```

---

## ⚙️ GitHub Actions CI/CD Automatikus Build

A `.github/workflows/build.yml` munkafolyamat minden `main` ágra történő commit/push vagy kézi indítás (`workflow_dispatch`) esetén automatikusan lefordul:

1. **Android**:
   - `cmc-center-android-apk`: Telepíthető Release APK fájl (`app-release.apk`)
   - `cmc-center-android-bundle`: Google Play áruházi App Bundle (`app-release.aab`)
2. **iOS**:
   - `cmc-center-ios-unsigned-ipa`: Telepíthető / sideloadolható iOS IPA csomag
