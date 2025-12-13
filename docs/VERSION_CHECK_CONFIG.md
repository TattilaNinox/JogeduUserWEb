# Verzió Ellenőrzés Konfigurációs Útmutató

## Alapértelmezett Beállítások

| Paraméter | Érték | Leírás |
|-----------|-------|--------|
| Ellenőrzési gyakoriság | 5 perc | Milyen gyakran ellenőrzi az új verziót |
| Inaktivitási küszöb | 3 perc | Mennyi inaktivitás után frissít |
| Scroll utáni várakozás | 10 másodperc | Scroll esemény után meddig vár |

## Beállítások Módosítása

A beállítások a `lib/services/version_check_service.dart` fájl elején találhatók:

```dart
class VersionCheckService {
  static const String _currentVersion = '1.0.0+13'; // Jelenlegi verzió
  static const Duration _checkInterval = Duration(minutes: 5); // Ellenőrzési gyakoriság
  static const Duration _inactivityThreshold = Duration(minutes: 3); // Inaktivitás
  static const Duration _recentScrollThreshold = Duration(seconds: 10); // Scroll cooldown
  // ...
}
```

## Gyakori Módosítások

### Gyorsabb Frissítés (Agresszívebb)

**Használati eset**: Kritikus bugfix, azonnal kell a frissítés mindenkinél

```dart
static const Duration _checkInterval = Duration(minutes: 1); // 5 perc → 1 perc
static const Duration _inactivityThreshold = Duration(minutes: 1); // 3 perc → 1 perc
```

⚠️ **Figyelem**: Több szerver kérés, több sávszélesség használat!

### Lassabb Frissítés (Konzervatívabb)

**Használati eset**: Kis változások, nem sürgős

```dart
static const Duration _checkInterval = Duration(minutes: 10); // 5 perc → 10 perc
static const Duration _inactivityThreshold = Duration(minutes: 5); // 3 perc → 5 perc
```

✅ **Előny**: Kevesebb szerver kérés, felhasználóbarátabb

### Teszt Mód (Fejlesztéshez)

**Használati eset**: Verzió frissítés tesztelése

```dart
static const Duration _checkInterval = Duration(seconds: 30); // Gyors ellenőrzés
static const Duration _inactivityThreshold = Duration(seconds: 30); // Gyors frissítés
static const Duration _recentScrollThreshold = Duration(seconds: 3); // Rövid scroll cooldown
```

🧪 **Ne felejts el visszaállítani production-be deploy előtt!**

## Kritikus Útvonalak Módosítása

Jelenleg a következő útvonalakon NEM frissít az app:

```dart
final criticalRoutes = [
  '/deck/',     // Flashcard deck nézetek
  '/study',     // Flashcard tanulás
  '/quiz/',     // Kvíz
];
```

### Új Kritikus Útvonal Hozzáadása

Példa: Ne frissítsen a fiók (account) oldalon sem:

```dart
final criticalRoutes = [
  '/deck/',
  '/study',
  '/quiz/',
  '/account',  // ÚJ: Ne frissítsen a fiók oldalon
];
```

### Kritikus Útvonal Eltávolítása

Ha például a kvíz oldalon IS frissíthessen:

```dart
final criticalRoutes = [
  '/deck/',
  '/study',
  // '/quiz/', // ELTÁVOLÍTVA
];
```

## Aktivitás Események Testreszabása

Jelenleg figyelt események:

- `onMouseMove` - Egér mozgás
- `onKeyDown` - Billentyűzet
- `onScroll` - Görgetés
- `onTouchStart` - Érintés (mobil)
- `onClick` - Kattintás

### További Esemény Hozzáadása

Példa: Figyeljük a window focus változását is:

A `_setupActivityListeners()` metódusban:

```dart
void _setupActivityListeners() {
  // ... meglévő listenerek ...
  
  // Új: Window focus
  html.window.onFocus.listen((_) {
    _lastActivityTime = DateTime.now();
    debugPrint('[VersionCheck] Window focused - activity detected');
  });
}
```

## Debug Módok

### Részletes Naplózás

Minden egyes aktivitás eseménynél log:

```dart
html.window.onMouseMove.listen((_) {
  _lastActivityTime = DateTime.now();
  debugPrint('[VersionCheck] Mouse activity at ${_lastActivityTime}'); // ÚJ sor
});
```

### Verzió Ellenőrzés Disable-elése

Teszteléshez vagy debug-oláshoz:

A `lib/main.dart` fájlban:

```dart
@override
void initState() {
  super.initState();
  // if (kIsWeb) {  // Kommenteld ki ezt
  //   _versionCheckService.start();
  //   debugPrint('[App] Version check service started');
  // }
}
```

## Verzió Formátum

A verzió formátum: `MAJOR.MINOR.PATCH+BUILD`

Példák:
- `1.0.0+1` - Első verzió
- `1.0.0+13` - Ugyanaz a verzió, 13. build
- `1.1.0+14` - Minor verzió változás
- `2.0.0+1` - Major verzió változás

**Tipp**: Általában csak a `+BUILD` számot növeld minden deployment-nél.

## Manuális Verzió Ellenőrzés Trigger

Ha szeretnél egy gombot, ami manuálisan ellenőriz:

```dart
// Például egy debug gomb
ElevatedButton(
  onPressed: () async {
    final service = VersionCheckService();
    await service.checkNow();
  },
  child: Text('Verzió ellenőrzés most'),
)
```

## Cache Headers Testreszabása

A `firebase.json` fájlban:

```json
{
  "source": "/version.json",
  "headers": [
    { "key": "Cache-Control", "value": "no-store, no-cache, must-revalidate, max-age=0" },
    { "key": "Pragma", "value": "no-cache" },
    { "key": "Expires", "value": "0" }
  ]
}
```

**Ne módosítsd** a version.json cache beállításait, különben nem fog frissülni!

## Telemetria / Analytics Hozzáadása

Ha szeretnéd követni a verzió frissítéseket:

```dart
void _performReload() {
  // Analytics esemény küldése
  // analytics.logEvent(name: 'app_auto_update', parameters: {
  //   'from_version': _currentVersion,
  //   'to_version': serverVersion,
  // });
  
  html.window.location.reload();
}
```

## Produkciós Best Practices

1. **Mindig teszteld** lokálisan deployment előtt
2. **Ne módosítsd gyakran** a beállításokat production-ben
3. **Dokumentáld** a változtatásokat
4. **Vedd figyelembe** a felhasználói élményt (ne túl gyakori frissítés)
5. **Monitorozd** a szerver terhelést (ha sok ellenőrzés van)

## Hibaelhárítás

### "Túl gyakran frissül"
→ Növeld az `_inactivityThreshold` értékét

### "Túl ritkán frissül"
→ Csökkentsd a `_checkInterval` értékét

### "Kritikus művelet közben frissül"
→ Add hozzá az útvonalat a `criticalRoutes` listához

### "Version.json nem frissül"
→ Ellenőrizd a Firebase headers beállításokat

## Jelenlegi Optimális Beállítás (Production)

```dart
// ✅ Javasolt production beállítások
static const Duration _checkInterval = Duration(minutes: 5);
static const Duration _inactivityThreshold = Duration(minutes: 3);
static const Duration _recentScrollThreshold = Duration(seconds: 10);

final criticalRoutes = ['/deck/', '/study', '/quiz/'];
```

Ez biztosítja:
- ✅ Nem túl gyakori szerver kérések
- ✅ Felhasználóbarát frissítés
- ✅ Biztonságos működés kritikus területeken
- ✅ Max 8 perc alatt mindenki frissül

---

**További kérdések?** Nézd meg a [teljes útmutatót](AUTO_VERSION_UPDATE_GUIDE.md)!

