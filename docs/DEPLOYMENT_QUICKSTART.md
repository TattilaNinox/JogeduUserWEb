# 🚀 Deployment Gyors Útmutató

## Új Verzió Kiadása (3 Lépés)

### 1️⃣ Verzió Frissítése (MANUÁLISAN - FONTOS!)

Frissítsd a verziószámot **MINDKÉT** helyen:

**`pubspec.yaml`** (3. sor):
```yaml
version: 1.0.0+14  # Növeld a +számot vagy a verziót
```

**`lib/services/version_check_service.dart`** (17. sor):
```dart
static const String _currentVersion = '1.0.0+14';  // UGYANAZ mint pubspec.yaml!
```

### 2️⃣ Deployment Script Futtatása

**Windows:**
```bash
deploy.bat
```

**Linux/Mac:**
```bash
chmod +x deploy.sh  # Első alkalommal
./deploy.sh
```

### 3️⃣ Kész! ✅

Az alkalmazás automatikusan frissülni fog a felhasználóknál 3-8 perc után (amikor inaktívak).

---

## Mit Csinál a Deployment Script?

1. ✅ Frissíti a `version.json` fájlt
2. ✅ Build-eli a Flutter web app-ot (`flutter build web --release`)
3. ✅ Deploy-olja Firebase Hosting-ra (`firebase deploy --only hosting`)

---

## Hogyan Frissül a Felhasználóknál?

🔄 **Automatikusan**, NINCS szükség F5-re!

1. ⏱️ Az app 5 percenként ellenőrzi az új verziót
2. 👤 Ha a felhasználó **3 perce inaktív** (nem mozgatja az egeret, nem ír, nem scrolloz)
3. ✅ ÉS nincs kvíz/flashcard/űrlap kitöltés folyamatban
4. 🔄 → Automatikusan újratölti az oldalt az új verzióval

**Eredmény**: A felhasználó mindig a legfrissebb verziót használja, anélkül hogy bármit kellene tennie!

---

## Manuális Deployment (Részletesen)

Ha nem használod a deploy script-et:

```bash
# 1. Verzió frissítése (lásd fent)

# 2. Version.json generálása
dart tools/update_version.dart

# 3. Build
flutter build web --release

# 4. Deploy
firebase deploy --only hosting
```

---

## Tesztelés Lokálisan

```bash
# Build
flutter build web --release

# Lokális szerver indítása
cd build/web
python -m http.server 8000

# Böngészőben: http://localhost:8000
```

---

## ⚠️ GYAKORI HIBÁK

### ❌ "A felhasználók nem kapják meg az új verziót"

**Ok**: Elfelejtetted frissíteni a verzió számot a `version_check_service.dart` fájlban.

**Megoldás**: Frissítsd mindkét helyen (lásd 1️⃣ lépés).

### ❌ "Túl sokáig tart a frissítés"

**Ok**: Az app 5 percenként ellenőriz + kell 3 perc inaktivitás.

**Normális**: Max 8 perc alatt mindenki frissül (5 perc ellenőrzés + 3 perc inaktivitás).

### ❌ "Build hiba"

**Ok**: Szintaxis hiba vagy hiányzó függőség.

**Megoldás**: 
```bash
flutter pub get
flutter clean
flutter build web --release
```

---

## 🔒 Privát Preview Deployolás

Ha szeretnél privát URL-t generálni teszteléshez (amit csak linkkel lehet elérni):

### Teljes Folyamat (Build + Deploy)

**Windows:**
```bash
.\deploy-preview.bat [channel-name]
```

**Linux/Mac:**
```bash
./deploy-preview.sh [channel-name]
```

### Csak Deploy (Ha Már Buildeltél)

**Windows:**
```bash
.\deploy-preview-only.bat [channel-name]
```

**Linux/Mac:**
```bash
./deploy-preview-only.sh [channel-name]
```

**Előfeltétel**: `flutter build web --release` már lefutott

Részletes útmutató: [PREVIEW_DEPLOYMENT_GUIDE.md](PREVIEW_DEPLOYMENT_GUIDE.md)

---

## 📚 Részletes Dokumentáció

- **Teljes útmutató**: [docs/AUTO_VERSION_UPDATE_GUIDE.md](docs/AUTO_VERSION_UPDATE_GUIDE.md)
- **Implementáció részletek**: [AUTO_VERSION_UPDATE_SUMMARY.md](AUTO_VERSION_UPDATE_SUMMARY.md)
- **Preview Deployment**: [PREVIEW_DEPLOYMENT_GUIDE.md](PREVIEW_DEPLOYMENT_GUIDE.md)

---

## 🎯 Gyors Ellenőrző Lista Deployment Előtt

- [ ] Verziószám frissítve a `pubspec.yaml`-ban
- [ ] Verziószám frissítve a `lib/services/version_check_service.dart`-ban (currentVersion)
- [ ] Mindkét verzió **EGYEZIK**
- [ ] `deploy.bat` vagy `deploy.sh` futtatása
- [ ] Firebase deploy sikeres (zöld üzenet)
- [ ] Ellenőrzés: `https://lomedu-user-web.web.app/version.json` mutatja az új verziót
- [ ] Ellenőrzés: Login oldalon bal alsó sarokban látszik az új verzió (v1.0.0+XX)

---

**Kérdések?** Nézd meg a [részletes útmutatót](docs/AUTO_VERSION_UPDATE_GUIDE.md)! 📖

