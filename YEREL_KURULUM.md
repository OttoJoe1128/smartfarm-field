# SmartFarm Field – Yerel bilgisayarda kurulum ve test

Hepsi **kendi bilgisayarında**: Android Studio, Flutter, backend, emülatör, APK. IDX kullanılmıyor.

---

## 1. Gereksinimler (bir kez kur)

- **Android Studio** (içinde Android SDK + emülatör gelir)  
  https://developer.android.com/studio  
  Kurarken: Android SDK, Android Virtual Device (AVD) seçili olsun.

- **Flutter** (Android Studio dışında ayrı kurulacak)  
  https://docs.flutter.dev/get-started/install  
  Kurulum sonrası: `flutter doctor` ile Android toolchain ve Android Studio eklentisinin yeşil olduğundan emin ol.

- **Python 3** (backend için)  
  Sisteminde `python3` veya `python` ile 3.x sürümü yüklü olsun.

---

## 2. Projeyi aç

- **Android Studio:** File → Open → `farm` klasörünü değil, **içindeki `smartfarm_field`** klasörünü seç (Flutter projesi bu).
- Veya terminalde proje kökü: `farm/smartfarm_field` (içinde `pubspec.yaml` olan klasör).

---

## 3. Backend’i çalıştır

Terminalde (farm repo’nun olduğu yerde):

```bash
cd farm/backend
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements-backend.txt
./start.sh
```

Backend 8000 portunda açık kalsın. Tarayıcıda `http://127.0.0.1:8000/docs` ile kontrol et.

---

## 4. Uygulamayı çalıştır (yerel)

**Seçenek A – Android Studio**

- `smartfarm_field` projesini açtıysan: üstten cihaz olarak emülatör veya bağlı telefonu seç, Run (yeşil oynat) ile çalıştır.

**Seçenek B – Terminal**

```bash
cd farm/smartfarm_field
flutter pub get
flutter devices
flutter run
```

Emülatör yoksa: Android Studio → Tools → Device Manager → Create Device → bir cihaz seç, sistem imajı indir, AVD oluştur, başlat. Sonra `flutter run`.

---

## 5. APK üret (yerel)

```bash
cd farm/smartfarm_field
flutter build apk --release
```

APK burada oluşur (artık her şey yerel):

- **Linux/macOS:**  
  `farm/smartfarm_field/build/app/outputs/flutter-apk/app-release.apk`
- **Windows:**  
  `farm\smartfarm_field\build\app\outputs\flutter-apk\app-release.apk`

Bu dosyayı telefona atıp kurabilir veya paylaşabilirsin.

---

## Kısa özet

| Adım | Ne yapıyorsun |
|------|----------------|
| 1 | Bilgisayara Android Studio + Flutter + Python kur |
| 2 | Projeyi `smartfarm_field` olarak aç (Android Studio veya VS Code) |
| 3 | Backend’i `backend` klasöründen başlat (venv + start.sh) |
| 4 | Emülatör veya telefon seçip `flutter run` veya Studio’dan Run |
| 5 | `flutter build apk --release` → APK yerel klasörde, istediğin yere kopyala |

IDX veya bulut yok; hepsi bu bilgisayarda.
