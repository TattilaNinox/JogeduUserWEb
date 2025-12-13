# Automatikus Verziófrissítés Útmutató

## Áttekintés

Az alkalmazás automatikusan ellenőrzi és frissíti magát új verziók esetén, anélkül, hogy a felhasználónak manuálisan kellene F5-öt nyomnia.

## Hogyan Működik?

1. **Verzió ellenőrzés**: Az alkalmazás 5 percenként ellenőrzi a `/version.json` fájlt a szerverről
2. **Aktivitás figyelés**: Folyamatosan figyeli a felhasználói aktivitást (egér, billentyűzet, scroll)
3. **Intelligens frissítés**: Ha új verzió érhető el ÉS a felhasználó 3 perce inaktív, automatikusan újratölti az oldalt
4. **Biztonságos frissítés**: Nem frissít kritikus műveletek (kvíz, flashcard tanulás) közben vagy űrlap kitöltése során

## Deployment Folyamat

### 1. Verzió növelés

Módosítsd a verziót a `pubspec.yaml` fájlban:

```yaml
version: 1.0.0+14  # Növeld a verziószámot
```

### 2. Version.json frissítése

Futtasd a version update scriptet:

```bash
dart tools/update_version.dart
```

Ez automatikusan frissíti:
- `web/version.json`
- `build/web/version.json` (ha már létezik)

### 3. Build

```bash
flutter build web --release
```

### 4. Deploy Firebase Hosting-ra

```bash
firebase deploy --only hosting
```

### Teljes Folyamat (Ajánlott)

```bash
# 1. Verzió frissítése pubspec.yaml-ban (manuálisan)
# 2. Version.json generálása
dart tools/update_version.dart

# 3. Build
flutter build web --release

# 4. Version.json másolása build mappába (már megtörtént a script által)
# 5. Deploy
firebase deploy --only hosting
```

## Automatizált Script Példa

Létrehozhatsz egy `deploy.sh` vagy `deploy.bat` fájlt:

**deploy.sh** (Linux/Mac):
```bash
#!/bin/bash
set -e

echo "🚀 Starting deployment..."

# Version update
echo "📦 Updating version.json..."
dart tools/update_version.dart

# Build
echo "🔨 Building web app..."
flutter build web --release

# Deploy
echo "☁️  Deploying to Firebase..."
firebase deploy --only hosting

echo "✅ Deployment completed!"
```

**deploy.bat** (Windows):
```batch
@echo off
echo 🚀 Starting deployment...

echo 📦 Updating version.json...
dart tools/update_version.dart

echo 🔨 Building web app...
flutter build web --release

echo ☁️  Deploying to Firebase...
firebase deploy --only hosting

echo ✅ Deployment completed!
```

## Működés Részletei

### Verzió Ellenőrzés Időzítés

- **Első ellenőrzés**: 1 perc az alkalmazás indulása után
- **Periodikus ellenőrzés**: 5 percenként
- **Cache bypass**: Minden kéréshez timestamp paraméter (`?t=...`)

### Inaktivitás Detektálás

Az alábbi események nullázzák az inaktivitás számlálót:
- Egér mozgás
- Billentyűzet lenyomás
- Scroll
- Touch (mobil)
- Kattintás

**Inaktivitási küszöb**: 3 perc

### Biztonságos Frissítés Feltételek

Az alkalmazás **NEM** frissít ha:
- Flashcard tanulás aktív (`/deck/*/study`)
- Kvíz folyamatban (`/quiz/*`)
- Input mezőben van fókusz
- Scroll esemény történt az elmúlt 10 másodpercben
- Felhasználó aktív volt az elmúlt 3 percben

## Cache Stratégia (Firebase Hosting)

A `firebase.json` optimalizált header konfigurációja:

- **version.json**: `no-cache` (mindig friss)
- **index.html**: `no-cache` (mindig friss)
- **flutter_service_worker.js**: `no-cache` (mindig friss)
- **JS/CSS fájlok**: `1 év cache` (hash-elt fájlnevek miatt)
- **Képek**: `1 nap cache`
- **Egyéb**: `1 óra cache`

## Tesztelés

### Manuális Verzió Ellenőrzés

A fejlesztői konzolon keresztül tesztelheted:

```javascript
// Böngésző Developer Tools Console-ban
// Jelenleg nem érhető el public API, de a service automatikusan fut
```

### Verzió Frissítés Szimulálása

1. Módosítsd a `web/version.json` fájlt másik verzióra
2. Deploy-old Firebase-re
3. Várj 5 percet vagy frissítsd a böngésző developer tools-ban a Network tab-ot
4. Az alkalmazás észlelni fogja az új verziót
5. 3 perc inaktivitás után automatikusan újratölt

### Debug Naplók

A böngésző konzolon láthatod a verzió ellenőrzés folyamatát:

```
[VersionCheck] Service started with version: 1.0.0+13
[VersionCheck] Checking version from: /version.json?t=1234567890
[VersionCheck] Version up to date: 1.0.0+13
```

Vagy ha új verzió van:

```
[VersionCheck] New version available: 1.0.0+14 (current: 1.0.0+13)
[VersionCheck] Reloading application - new version detected and user inactive for 3 minutes
```

## Hibaelhárítás

### A verzió nem frissül

1. **Ellenőrizd a cache-t**: Nyomj Ctrl+Shift+R (hard reload)
2. **Ellenőrizd a version.json-t**: Látogass el `https://lomedu-user-web.web.app/version.json` URL-re
3. **Ellenőrizd a Firebase headers-t**: Nézd meg a Network tab-ban a válasz headereket

### A frissítés túl gyakori

Növeld az inaktivitási küszöböt a `lib/services/version_check_service.dart` fájlban:

```dart
static const Duration _inactivityThreshold = Duration(minutes: 5); // 3-ról 5-re
```

### A frissítés túl ritka

Csökkentsd a verzió ellenőrzés intervallumát:

```dart
static const Duration _checkInterval = Duration(minutes: 3); // 5-ről 3-ra
```

## Konfigurációs Opciók

A `lib/services/version_check_service.dart` fájlban módosíthatók:

```dart
static const String _currentVersion = '1.0.0+13'; // Jelenlegi verzió
static const Duration _checkInterval = Duration(minutes: 5); // Ellenőrzési gyakoriság
static const Duration _inactivityThreshold = Duration(minutes: 3); // Inaktivitás küszöb
static const Duration _recentScrollThreshold = Duration(seconds: 10); // Scroll utáni várakozás
```

## Megjegyzések

- A verzió frissítés csak web platformon működik (Flutter web)
- A service automatikusan indul az alkalmazás indulásakor
- Nincs szükség manuális konfigurációra a felhasználói oldalon
- A felhasználó nem kap értesítést a frissítésről (automatikus háttérfrissítés)

