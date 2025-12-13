# 🔒 Firebase Preview Channel - Privát Deployolás Útmutató

## Mi az a Firebase Preview Channel?

A Firebase Preview Channel lehetővé teszi, hogy **privát URL-t** generáljunk a buildhez, amit csak azok láthatnak, akik megkapják a linket. Ez ideális teszteléshez anélkül, hogy az éles verziót felülírná.

## Főbb Előnyök

- ✅ **Privát URL**: Csak linkkel elérhető, nem indexelhető keresőkben
- ✅ **Biztonságos**: Nem írja felül az éles verziót
- ✅ **Konfigurálható lejárat**: Alapértelmezetten 30 napig érvényes
- ✅ **Teljes funkcionalitás**: Minden funkció működik, mintha éles lenne
- ✅ **Könnyű megosztás**: Egyszerűen megoszthatod a linket tesztelőknek

## Hogyan Működik?

1. A script build-eli az alkalmazást (`flutter build web --release`)
2. Feltölti a Firebase Hosting Preview Channel-re
3. Firebase automatikusan generál egy privát URL-t, pl:
   ```
   https://lomedu-user-web--preview-abc123.web.app
   ```
4. Ez az URL csak akkor érhető el, ha valaki megkapja a linket

## Használat

### Kétféle Script Elérhető

1. **`deploy-preview.bat` / `deploy-preview.sh`**: Build + Deploy (teljes folyamat)
2. **`deploy-preview-only.bat` / `deploy-preview-only.sh`**: Csak Deploy (ha már buildeltél)

### Teljes Folyamat (Build + Deploy)

#### Windows

```bash
# Alapértelmezett channel névvel (preview)
.\deploy-preview.bat

# Egyedi channel névvel
.\deploy-preview.bat test-feature
.\deploy-preview.bat bugfix-123
.\deploy-preview.bat new-ui-design
```

#### Linux/Mac

```bash
# Alapértelmezett channel névvel (preview)
./deploy-preview.sh

# Egyedi channel névvel
./deploy-preview.sh test-feature
./deploy-preview.sh bugfix-123
./deploy-preview.sh new-ui-design
```

**Első használat esetén** (Linux/Mac):
```bash
chmod +x deploy-preview.sh
```

### Csak Deploy (Ha Már Buildeltél)

Ha már buildeltél (`flutter build web --release`), és csak deployolni szeretnél:

#### Windows

```bash
# Alapértelmezett channel névvel (preview)
.\deploy-preview-only.bat

# Egyedi channel névvel
.\deploy-preview-only.bat test-feature
.\deploy-preview-only.bat bugfix-123
```

#### Linux/Mac

```bash
# Alapértelmezett channel névvel (preview)
./deploy-preview-only.sh

# Egyedi channel névvel
./deploy-preview-only.sh test-feature
./deploy-preview-only.sh bugfix-123
```

**Első használat esetén** (Linux/Mac):
```bash
chmod +x deploy-preview-only.sh
```

**Előfeltétel**: A `build/web` mappának léteznie kell (futtasd először: `flutter build web --release`)

## Mi Történik a Deployment Során?

### Teljes Folyamat Script (`deploy-preview.bat` / `deploy-preview.sh`)

A script automatikusan végrehajtja ezeket a lépéseket:

1. **[1/4] Verzió frissítés**: Frissíti a `version.json` fájlt
2. **[2/4] Build**: Build-eli a Flutter web app-ot release módban
3. **[3/4] Verzió ellenőrzés**: Ellenőrzi, hogy a `version.json` benne van-e a build-ben
4. **[4/4] Deploy**: Feltölti a Firebase Preview Channel-re

### Csak Deploy Script (`deploy-preview-only.bat` / `deploy-preview-only.sh`)

Ez a script csak a deploy lépést végzi el (feltételezi, hogy már buildeltél):

1. **[1/2] Verzió ellenőrzés**: Ellenőrzi, hogy a `version.json` benne van-e a build-ben (ha nincs, másolja)
2. **[2/2] Deploy**: Feltölti a Firebase Preview Channel-re

**Előfeltétel**: A `build/web` mappának léteznie kell. Ha nincs, először futtasd: `flutter build web --release`

A deployment után mindkét script megjeleníti a generált privát URL-t.

## URL Megosztása

A deployment sikeres befejezése után a script megjeleníti a generált preview URL-t, pl:

```
========================================
  ✅ Preview deployment completed!
  The production version was NOT changed.
========================================

🔗 Preview URL:
https://lomedu-user-web--preview-abc123.web.app

📋 Copy this URL and share it with testers.
⏰ This preview will expire in 30 days.
========================================
```

Egyszerűen másold ki ezt az URL-t és oszd meg azokkal, akiknek tesztelniük kell.

## Lejárati Idő Beállítása

A script alapértelmezetten **30 napra** állítja be a lejáratot. Ha szeretnéd módosítani, szerkeszd a script fájlt:

**Windows (`deploy-preview.bat`):**
```batch
firebase hosting:channel:deploy %CHANNEL_NAME% --expires 7d   # 7 nap
firebase hosting:channel:deploy %CHANNEL_NAME% --expires 14d  # 14 nap
firebase hosting:channel:deploy %CHANNEL_NAME% --expires 30d  # 30 nap (alapértelmezett)
firebase hosting:channel:deploy %CHANNEL_NAME% --expires 60d  # 60 nap
```

**Linux/Mac (`deploy-preview.sh`):**
```bash
firebase hosting:channel:deploy "$CHANNEL_NAME" --expires 7d   # 7 nap
firebase hosting:channel:deploy "$CHANNEL_NAME" --expires 14d  # 14 nap
firebase hosting:channel:deploy "$CHANNEL_NAME" --expires 30d  # 30 nap (alapértelmezett)
firebase hosting:channel:deploy "$CHANNEL_NAME" --expires 60d  # 60 nap
```

## Channel Név Használata

A channel név segít különböző preview verziókat kezelni:

- **`preview`** (alapértelmezett): Általános preview teszteléshez
- **`test-feature`**: Egy konkrét feature teszteléséhez
- **`bugfix-123`**: Egy konkrét bugfix teszteléséhez
- **`new-ui-design`**: UI változtatások teszteléséhez

Minden channel névhez külön URL generálódik, így egyszerre több preview verziót is karbantarthatsz.

## Éles vs Preview Verzió

| Tulajdonság | Éles Verzió | Preview Channel |
|------------|-------------|-----------------|
| URL | `https://lomedu-user-web.web.app` | `https://lomedu-user-web--preview-abc123.web.app` |
| Elérhetőség | Nyilvános, mindenki | Csak linkkel |
| Keresőben indexelhető | Igen | Nem |
| Éles verziót felülírja | Igen | Nem |
| Lejárat | Nincs | 30 nap (beállítható) |

## Gyakori Használati Esetek

### 1. Új Feature Tesztelése
```bash
deploy-preview.bat new-feature
```
Oszd meg a generált URL-t a tesztelőkkel, hogy próbálják ki az új funkciót.

### 2. Bugfix Ellenőrzése
```bash
deploy-preview.bat bugfix-456
```
Teszteld a javítást anélkül, hogy az éles verziót módosítanád.

### 3. UI Változtatások Megjelenítése
```bash
deploy-preview.bat ui-redesign
```
Mutasd meg az új dizájnt a csapatnak vagy ügyfeleknek.

### 4. Teljesítmény Tesztelés
```bash
deploy-preview.bat performance-test
```
Teszteld a teljesítményt éles környezetben, de biztonságosan.

## Tippek és Best Practices

1. **Használj beszédes channel neveket**: `bugfix-123` jobb, mint `test1`
2. **Töröld a régi channel-eket**: A Firebase Console-ban törölheted a nem használt preview channel-eket
3. **Közöld a lejárati dátumot**: Tájékoztasd a tesztelőket, hogy meddig érhető el a preview
4. **Ne használd éles adatokkal**: A preview verzió is éles Firebase-t használ, legyen óvatos!
5. **Teszteld minden funkciót**: A preview verzió ugyanúgy működik, mint az éles, teszteld át!

## Hibaelhárítás

### ❌ "Channel deploy failed"

**Ok**: Firebase CLI nincs telepítve vagy nincs bejelentkezve.

**Megoldás**:
```bash
# Telepítsd a Firebase CLI-t
npm install -g firebase-tools

# Jelentkezz be
firebase login
```

### ❌ "Build failed"

**Ok**: Flutter build hiba vagy hiányzó függőség.

**Megoldás**:
```bash
flutter pub get
flutter clean
flutter build web --release
```

### ❌ "Preview URL nem jelenik meg"

**Ok**: A Firebase CLI output nem tartalmazza az URL-t vagy a script nem tudja kinyerni.

**Megoldás**: Nézd meg a Firebase CLI teljes output-ját, az URL mindig benne van. A script most már automatikusan megjeleníti.

## További Információk

- **Firebase Hosting Dokumentáció**: [https://firebase.google.com/docs/hosting](https://firebase.google.com/docs/hosting)
- **Preview Channels**: [https://firebase.google.com/docs/hosting/channels](https://firebase.google.com/docs/hosting/channels)
- **Éles Deployment**: Lásd [DEPLOYMENT_QUICKSTART.md](DEPLOYMENT_QUICKSTART.md)

---

**Kérdések?** Nézd meg a [Deployment Gyors Útmutatót](DEPLOYMENT_QUICKSTART.md) vagy a Firebase dokumentációt! 📖

