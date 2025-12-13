# Cloud Functions Használati Dokumentáció

Ez a dokumentum felsorolja az összes Firebase Cloud Function-t a projektben, típusukat és azt, hogy melyik alkalmazás használja őket.

Utolsó frissítés: 2025-11-26

---

## Funkcióáttekintő Táblázat

| Funkció neve | Típus | Használó alkalmazás(ok) | Leírás |
|--------------|-------|-------------------------|---------|
| `requestDeviceChange` | callable | `lomedu_user_web` (Flutter) | Eszközváltási kód kérése email-ben (6-jegyű kód). |
| `verifyAndChangeDevice` | callable | `lomedu_user_web` (Flutter) | Eszközváltási kód ellenőrzése és új eszköz engedélyezése. |
| `sendSubscriptionReminder` | callable | `lomedu_user_web` (Flutter) | Előfizetési emlékeztető email küldése (manuális trigger). |
| `checkSubscriptionExpiry` | callable | `lomedu_user_web` (Flutter) | Előfizetés lejáratának ellenőrzése (manuális trigger). |
| `initiateWebPayment` | callable | `lomedu_user_web` (Flutter) | Webes fizetés indítása SimplePay v2 API-val. |
| `confirmWebPayment` | callable | Nincs közvetlen hívás | Fizetés lezárása SimplePay QUERY API-val (jelenleg nem használt közvetlenül). |
| `processWebPaymentWebhook` | callable | Nincs közvetlen hívás | SimplePay webhook feldolgozás (jelenleg nem használt közvetlenül, az `onWebPaymentWrite` trigger használatos helyette). |
| `checkSubscriptionExpiryScheduled` | scheduled (cron: `0 2 * * *`) | Automatikus (Firebase Scheduler) | Naponta 02:00-kor előfizetési emlékeztetők küldése. |
| `checkTrialExpiryScheduled` | scheduled (cron: `0 10 * * *`) | Automatikus (Firebase Scheduler) | Naponta 10:00-kor próbaidő lejárat emlékeztetők küldése. |
| `reconcileWebPaymentsScheduled` | scheduled (cron: `*/2 * * * *`) | Automatikus (Firebase Scheduler) | 2 percenként INITIATED státuszú web_payments rekordok lezárása SimplePay QUERY API-val. |
| `onWebPaymentWrite` | firestore trigger (`web_payments/{orderRef}`) | Automatikus (Firestore trigger) | Fizetés státuszváltozás esetén előfizetés aktiválása és SimplePay FINISH hívás. |
| `simplepayWebhook` | https (onRequest) | SimplePay (külső webhookból) | SimplePay webhook fogadása HTTP végponton, aláírás ellenőrzéssel. |
| `adminCleanupUserTokensBatch` | callable | Valószínűleg admin alkalmazás vagy külső script | Felhasználói tokenek törlése batch műveletként. |
| `adminCleanupUserTokensHttp` | https (onRequest) | Valószínűleg admin alkalmazás vagy külső script | Felhasználói tokenek törlése HTTP végponton keresztül. |
| `cleanupOldTokens` | callable | Valószínűleg admin alkalmazás vagy külső script | Régi tokenek tisztítása. |
| `cleanupUserTokens` | callable | `lomedu_user_web` (Flutter) - `AccountDeletionService` | Felhasználói tokenek tisztítása. |
| `fixExpiredSubscriptions` | callable | Valószínűleg admin alkalmazás vagy külső script | Lejárt előfizetések javítása. |
| `handlePlayRtdn` | callable | Valószínűleg `orlomed_mobil` (Android/iOS) | Google Play Real-time Developer Notifications (RTDN) kezelése. |
| `reconcileSubscriptions` | callable | Valószínűleg admin alkalmazás vagy külső script | Előfizetések összehangolása. |

---

## Részletes Funkció Leírások

### Eszközkezelés

#### `requestDeviceChange`
- **Típus:** callable
- **Használja:** `lomedu_user_web` (Flutter)
  - Fájl: `lib/services/device_change_service.dart`
  - Metódus: `DeviceChangeService.requestDeviceChange()`
- **Leírás:** Eszközváltási kérés indítása. Generál egy 6-jegyű kódot, eltárolja a Firestore-ban, és emailt küld a felhasználónak a kóddal.
- **Input:** `{ email: string }`
- **Output:** `{ ok: boolean }`

#### `verifyAndChangeDevice`
- **Típus:** callable
- **Használja:** `lomedu_user_web` (Flutter)
  - Fájl: `lib/services/device_change_service.dart`
  - Metódus: `DeviceChangeService.verifyAndChangeDevice()`
- **Leírás:** Eszközváltási kód ellenőrzése. Ha a kód helyes, frissíti a felhasználó `authorizedDeviceFingerprint` mezőjét az új eszköz ujjlenyomatával, és revokálja a refresh tokeneket.
- **Input:** `{ email: string, code: string, fingerprint: string }`
- **Output:** `{ ok: boolean }`

---

### Előfizetéskezelés

#### `sendSubscriptionReminder`
- **Típus:** callable
- **Használja:** `lomedu_user_web` (Flutter)
  - Fájl: `lib/services/email_notification_service.dart`
  - Metódusok: `EmailNotificationService.sendExpiryWarning()`, `EmailNotificationService.sendExpiredNotification()`
- **Leírás:** Előfizetési emlékeztető email küldése (lejárat előtt vagy után). Duplikátum védelemmel rendelkezik (lastReminder mező).
- **Input:** `{ userId: string, reminderType: 'expiry_warning' | 'expired', daysLeft?: number }`
- **Output:** `{ success: boolean, message: string, skipped?: boolean }`

#### `checkSubscriptionExpiry`
- **Típus:** callable
- **Használja:** `lomedu_user_web` (Flutter)
  - Fájl: `lib/services/email_notification_service.dart`
  - Metódus: `EmailNotificationService.checkAllSubscriptions()`
- **Leírás:** Előfizetés lejáratának manuális ellenőrzése és emlékeztetők küldése.
- **Input:** -
- **Output:** `{ success: boolean, emailsSent: number }`

#### `checkSubscriptionExpiryScheduled`
- **Típus:** scheduled (cron: `0 2 * * *`)
- **Használja:** Automatikus (Firebase Scheduler)
- **Leírás:** Naponta 02:00-kor (Europe/Budapest) automatikusan ellenőrzi az előfizetések lejáratát és küld emlékeztetőket. Duplikátum védelemmel rendelkezik.
- **Input:** -
- **Output:** -

#### `checkTrialExpiryScheduled`
- **Típus:** scheduled (cron: `0 10 * * *`)
- **Használja:** Automatikus (Firebase Scheduler)
- **Leírás:** Naponta 10:00-kor (Europe/Budapest) automatikusan ellenőrzi a **próbaidő** lejáratát.
  - 3 nappal lejárat előtt figyelmeztetést küld.
  - A lejárat napján értesítést küld a lejáratról.
  - Csak azoknak küld, akiknek nincs aktív előfizetése.
  - Duplikátum védelemmel rendelkezik (`lastReminder.trial_expiry_warning`, `lastReminder.trial_expired`).
- **Input:** -
- **Output:** -

---

### Webes Fizetés (SimplePay v2)

#### `initiateWebPayment`
- **Típus:** callable
- **Használja:** `lomedu_user_web` (Flutter)
  - Fájl: `lib/services/web_payment_service.dart`
  - Metódus: `WebPaymentService.initiatePayment()`
- **Leírás:** Webes fizetés indítása SimplePay v2 API-val. Létrehoz egy `web_payments` rekordot és visszaadja a SimplePay fizetési URL-t.
- **Input:** `{ planId: string, userId: string }`
- **Output:** `{ success: boolean, paymentUrl: string, orderRef: string }`

#### `confirmWebPayment`
- **Típus:** callable
- **Használja:** Nincs közvetlen hívás a `lomedu_user_web` kódban
- **Leírás:** Fizetés megerősítése SimplePay QUERY API-val. Jelenleg nem használt közvetlenül, mert az `onWebPaymentWrite` trigger és a `reconcileWebPaymentsScheduled` funkció átvették a szerepét.
- **Input:** `{ orderRef: string }`
- **Output:** `{ success: boolean, status: string }`

#### `processWebPaymentWebhook`
- **Típus:** callable
- **Használja:** Nincs közvetlen hívás a `lomedu_user_web` kódban
- **Leírás:** SimplePay webhook feldolgozás callable funkcióként. Jelenleg nem használt közvetlenül, mert a `simplepayWebhook` HTTP endpoint használatos helyette.
- **Input:** `{ orderRef: string, transactionId: string, orderId: string, status: string, ... }`
- **Output:** `{ success: boolean }`

#### `simplepayWebhook`
- **Típus:** https (onRequest)
- **Használja:** SimplePay (külső webhook, server-to-server)
- **Leírás:** SimplePay webhook HTTP végpont. Fogadja a SimplePay IPN/webhook értesítéseket, ellenőrzi az aláírást (HMAC-SHA384), és feldolgozza a sikeres fizetéseket.
- **URL:** `https://europe-west1-orlomed-f8f9f.cloudfunctions.net/simplepayWebhook`

#### `onWebPaymentWrite`
- **Típus:** firestore trigger (`web_payments/{orderRef}`)
- **Használja:** Automatikus (Firestore trigger)
- **Leírás:** Amikor egy `web_payments` dokumentum módosul, ellenőrzi a státuszt. Ha INITIATED, megpróbálja lezárni a fizetést SimplePay QUERY API-val (10 próbálkozás, 1 mp-es poll). Ha SUCCESS/COMPLETED, aktiválja a felhasználó előfizetését.

#### `reconcileWebPaymentsScheduled`
- **Típus:** scheduled (cron: `*/2 * * * *`)
- **Használja:** Automatikus (Firebase Scheduler)
- **Leírás:** 2 percenként ellenőrzi az INITIATED státuszú `web_payments` rekordokat (amelyek 90s-nél régebbiek), és megpróbálja őket lezárni SimplePay QUERY API-val.

---

### Admin Funkciók és Token Kezelés

#### `adminCleanupUserTokensBatch`
- **Típus:** callable
- **Használja:** Valószínűleg admin alkalmazás vagy külső script
- **Leírás:** Felhasználói tokenek batch törlése. Jelenleg placeholder implementáció.

#### `adminCleanupUserTokensHttp`
- **Típus:** https (onRequest)
- **Használja:** Valószínűleg admin alkalmazás vagy külső script
- **Leírás:** Felhasználói tokenek HTTP törlése. Jelenleg placeholder implementáció.

#### `cleanupOldTokens`
- **Típus:** callable
- **Használja:** Valószínűleg admin alkalmazás vagy külső script
- **Leírás:** Régi tokenek tisztítása. Jelenleg placeholder implementáció.

#### `cleanupUserTokens`
- **Típus:** callable
- **Használja:** `lomedu_user_web` (Flutter)
  - Fájl: `lib/services/account_deletion_service.dart`
  - Metódus: `AccountDeletionService.deleteAccount()`
- **Leírás:** Felhasználói tokenek tisztítása. Jelenleg placeholder implementáció.

#### `fixExpiredSubscriptions`
- **Típus:** callable
- **Használja:** Valószínűleg admin alkalmazás vagy külső script
- **Leírás:** Lejárt előfizetések javítása. Jelenleg placeholder implementáció.

#### `reconcileSubscriptions`
- **Típus:** callable
- **Használja:** Valószínűleg admin alkalmazás vagy külső script
- **Leírás:** Előfizetések összehangolása. Jelenleg placeholder implementáció.

---

### Mobil Alkalmazás Funkciók

#### `handlePlayRtdn`
- **Típus:** callable
- **Használja:** Valószínűleg `orlomed_mobil` (Android/iOS)
- **Leírás:** Google Play Real-time Developer Notifications (RTDN) kezelése. Jelenleg placeholder implementáció.

---

## Használat Alkalmazásonként

### `lomedu_user_web` (Flutter Web - Felhasználói Alkalmazás)

**Eszközkezelés:**
- `requestDeviceChange` - eszközváltási kód kérése
- `verifyAndChangeDevice` - eszközváltási kód ellenőrzése

**Előfizetéskezelés:**
- `sendSubscriptionReminder` - emlékeztető email küldése
- `checkSubscriptionExpiry` - előfizetés lejárat ellenőrzése

**Fizetés:**
- `initiateWebPayment` - webes fizetés indítása

**Fiók kezelés:**
- `cleanupUserTokens` - felhasználói tokenek tisztítása (fiók törléskor)

### `orlomed_mobil` (Android/iOS - Mobil Alkalmazás)

**Előfizetéskezelés:**
- `handlePlayRtdn` - Google Play Real-time Developer Notifications kezelése (valószínűleg)

### Admin Alkalmazás / Külső Script

**Token kezelés:**
- `adminCleanupUserTokensBatch` - felhasználói tokenek batch törlése
- `adminCleanupUserTokensHttp` - felhasználói tokenek HTTP törlése
- `cleanupOldTokens` - régi tokenek tisztítása

**Előfizetés karbantartás:**
- `fixExpiredSubscriptions` - lejárt előfizetések javítása
- `reconcileSubscriptions` - előfizetések összehangolása

### Automatikus (Firebase Scheduler & Triggers)

**Scheduled funkciók:**
- `checkSubscriptionExpiryScheduled` - naponta 02:00-kor előfizetés lejárat ellenőrzés
- `checkTrialExpiryScheduled` - naponta 10:00-kor próbaidő lejárat ellenőrzés
- `reconcileWebPaymentsScheduled` - 2 percenként INITIATED fizetések lezárása

**Firestore triggerek:**
- `onWebPaymentWrite` - `web_payments` dokumentum változáskor előfizetés aktiválás

### Külső Szolgáltatások

**SimplePay:**
- `simplepayWebhook` - SimplePay IPN/webhook fogadása (server-to-server)

---

## Nem Használt / Placeholder Funkciók

Az alábbi funkciók jelenleg placeholder implementációval rendelkeznek (csak console.log és success response):

- `adminCleanupUserTokensBatch`
- `adminCleanupUserTokensHttp`
- `cleanupOldTokens`
- `cleanupUserTokens`
- `fixExpiredSubscriptions`
- `reconcileSubscriptions`
- `handlePlayRtdn`
- `confirmWebPayment` (részben működik, de nem hívott közvetlenül)
- `processWebPaymentWebhook` (részben működik, de nem hívott közvetlenül)

**Megjegyzés:** Ezek a funkciók valószínűleg más alkalmazások (pl. `orlomed_mobil`, admin web app) vagy külső scriptek által használtak, vagy a jövőbeli fejlesztésekhez lettek fenntartva.

---

## Firestore Triggerek Részletei

### `onWebPaymentWrite`
- **Trigger:** `web_payments/{orderRef}` dokumentum írása/módosítása
- **Működés:**
  - Ha a státusz INITIATED, megpróbálja lezárni a fizetést SimplePay QUERY API-val (10 próbálkozás, 1 mp-es poll).
  - Ha a státusz SUCCESS vagy COMPLETED-re vált, aktiválja a felhasználó előfizetését.

---

## Scheduled Funkciók Részletei

### `checkSubscriptionExpiryScheduled`
- **Ütemezés:** Naponta 02:00-kor (Europe/Budapest)
- **Timeout:** 540 másodperc (9 perc)
- **Működés:**
  - Megkeresi az 1-3 napon belül lejáró előfizetéseket → `expiry_warning` email.
  - Megkeresi a már lejárt előfizetéseket → `expired` email.
  - Duplikátum védelem: csak egyszer küld emailt minden típusból (lastReminder mező).

### `checkTrialExpiryScheduled`
- **Ütemezés:** Naponta 10:00-kor (Europe/Budapest)
- **Timeout:** 540 másodperc (9 perc)
- **Működés:**
  - 3 nappal a próbaidő lejárta előtt figyelmeztető email (`trial_expiry_warning`).
  - A próbaidő lejártának napján értesítő email (`trial_expired`).
  - Csak akkor küld emailt, ha nincs aktív előfizetés (`isSubscriptionActive == false`).

### `reconcileWebPaymentsScheduled`
- **Ütemezés:** 2 percenként
- **Timeout:** 240 másodperc (4 perc)
- **Működés:**
  - Megkeresi az INITIATED státuszú `web_payments` rekordokat, amelyek 90s-nél régebbiek.
  - Megpróbálja lezárni őket SimplePay QUERY API-val (10 próbálkozás, 1 mp-es poll).
  - Ha sikeres, aktiválja a felhasználó előfizetését és COMPLETED státuszra váltja a rekordot.

---

## Megjegyzések

- **Régió:** Minden funkció az `europe-west1` régióban van deployolva.
- **Runtime:** A legtöbb funkció Node.js 20-on fut, kivéve az `ext-firestore-send-email-processqueue` extension, ami Node.js 22-n fut.
- **CORS:** A `simplepayWebhook` HTTP endpoint explicit CORS headereket küld (`Access-Control-Allow-Origin: *`).
- **Secrets:** Bizonyos funkciók (SimplePay-hez kapcsolódók) használnak Firebase Secret Manager-t a konfiguráció tárolására (pl. `SIMPLEPAY_MERCHANT_ID`, `SIMPLEPAY_SECRET_KEY`, `NEXTAUTH_URL`).

---

## Firebase Extensions

### `ext-firestore-send-email-processqueue`
- **Típus:** Firestore extension trigger
- **Régió:** europe-central2
- **Leírás:** Firebase hivatalos "Trigger Email from Firestore" extension, amely automatikusan emailt küld, ha egy dokumentum íródik a megadott Firestore kollekciókba.
- **Használat:** Valószínűleg admin funkcionalitáshoz vagy automatikus emailek küldéséhez használatos.

---

## Jövőbeli Fejlesztések

Ha új Cloud Function-t adsz hozzá, vagy új alkalmazást fejlesztesz, kérlek, frissítsd ezt a dokumentumot, hogy naprakész maradjon a funkciók használata.

---

**Verzió:** 1.1  
**Létrehozva:** 2025-10-20  
**Frissítve:** 2025-11-26
**Projekt:** orlomed-f8f9f
