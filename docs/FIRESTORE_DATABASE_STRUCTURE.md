# Firestore Adatbázis Struktúra és API Specifikáció

## Áttekintés

Az alkalmazás Firebase Firestore NoSQL adatbázist használ. Az adatbázis két példányra van osztva:
- **Alapértelmezett adatbázis**: `orlomed-f8f9f` (fő alkalmazás adatok)
- **Publikus adatbázis**: `lomedu-publik` (csak olvasható publikus adatok)

A mobil alkalmazás és a webes admin felület ugyanabból a Firestore adatbázisból dolgozik.

## Főbb Kollekciók

### 1. `users` - Felhasználói Adatok

**Dokumentum ID**: `{userId}` (Firebase Auth UID)

**Struktúra**:
```json
{
  "email": "string",
  "userType": "normal | admin | test",
  "science": "string | null",
  "subscriptionStatus": "free | premium",
  "isSubscriptionActive": "boolean",
  "subscriptionEndDate": "Timestamp | null",
  "lastPaymentDate": "Timestamp | null",
  "freeTrialStartDate": "Timestamp | null",
  "freeTrialEndDate": "Timestamp | null",
  "deviceRegistrationDate": "Timestamp | null",
  "createdAt": "Timestamp",
  "updatedAt": "Timestamp"
}
```

**Alkolleciók**:

#### 1.1 `users/{userId}/categories/{categoryId}/learning/{cardId}`
**Dokumentum ID**: `{deckId}#{cardIndex}` (pl. `deck123#0`)

**Struktúra** (FlashcardLearningData):
```json
{
  "state": "NEW | LEARNING | REVIEW",
  "interval": "number (percben)",
  "easeFactor": "number (1.3-2.5)",
  "repetitions": "number",
  "lastReview": "Timestamp",
  "nextReview": "Timestamp",
  "lastRating": "Again | Hard | Good | Easy"
}
```

**Használat**: SM-2 alapú spaced repetition algoritmus tanulási adatai kártyánként.

#### 1.2 `users/{userId}/category_stats/{categoryId}`

**Struktúra** (CategoryStats):
```json
{
  "againCount": "number",
  "hardCount": "number",
  "updatedAt": "Timestamp"
}
```

**Használat**: Kategóriánkénti nehéz kártyák számlálása.

#### 1.3 `users/{userId}/deck_stats/{deckId}`

**Struktúra** (DeckStats):
```json
{
  "again": "number",
  "hard": "number",
  "good": "number",
  "easy": "number",
  "ratings": {
    "0": "Hard",
    "1": "Easy",
    "2": "Good"
  },
  "updatedAt": "Timestamp"
}
```

**Használat**: Pakli szintű statisztikák, kártyánkénti értékelések gyorsítótárazása.

#### 1.4 `users/{userId}/served_questions/{questionHash}`

**Struktúra** (ServedQuestion):
```json
{
  "lastServed": "Timestamp",
  "ttl": "Timestamp"
}
```

**Használat**: Dinamikus kvízek kérdés ismétlés elkerülése (1 órás TTL).

#### 1.5 `users/{userId}/user_learning_data/{cardId}` 
**LEGACY** - Új adatok már a `categories/{categoryId}/learning/` alatt tárolódnak.

#### 1.6 `users/{userId}/learning_states/{noteId}`
**LEGACY** - Régi tanulási állapotok.

---

### 2. `notes` - Jegyzet Dokumentumok (Minden Típus)

**Dokumentum ID**: Auto-generált Firestore ID

**Közös mezők**:
```json
{
  "title": "string",
  "category_id": "string (referencia categories kollekció)",
  "category": "string (denormalizált név)",
  "type": "text | interactive | deck | dynamic_quiz | source",
  "status": "Draft | Published | Public | Archived",
  "isFree": "boolean (freemium model)",
  "tags": ["string"],
  "createdAt": "Timestamp",
  "modified": "Timestamp",
  "deletedAt": "Timestamp | null (soft delete)",
  "is_selected_for_learning": "boolean (csak nem-admin felhasználók írhatják)"
}
```

#### 2.1 Típus: `deck` - Tanulókártya Pakli

**Specifikus mezők**:
```json
{
  "type": "deck",
  "flashcards": [
    {
      "front": "string",
      "back": "string"
    }
  ]
}
```

**Mobil lekérés**:
```dart
// 1. Pakli adatok lekérése
final doc = await FirebaseFirestore.instance
    .collection('notes')
    .doc(deckId)
    .get();

final data = doc.data();
final flashcards = List<Map<String, dynamic>>.from(data?['flashcards'] ?? []);
final categoryId = data?['category'] as String? ?? 'default';

// 2. Tanulási adatok batch lekérése (30-as chunk-okban, párhuzamosan)
final allCardIds = List.generate(flashcards.length, (i) => '${deckId}#$i');
const chunkSize = 30; // Firestore whereIn limit

final futures = <Future>[];
for (var i = 0; i < allCardIds.length; i += chunkSize) {
  final chunk = allCardIds.sublist(i, (i + chunkSize).clamp(0, allCardIds.length));
  futures.add(FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .collection('categories')
      .doc(categoryId)
      .collection('learning')
      .where(FieldPath.documentId, whereIn: chunk)
      .get());
}

final results = await Future.wait(futures);
```

**Tanulási adat mentés**:
```dart
await FirebaseFirestore.instance
    .collection('users')
    .doc(userId)
    .collection('categories')
    .doc(categoryId)
    .collection('learning')
    .doc('${deckId}#${cardIndex}')
    .set({
      'state': 'LEARNING',
      'interval': 10,
      'easeFactor': 2.5,
      'repetitions': 0,
      'lastReview': FieldValue.serverTimestamp(),
      'nextReview': Timestamp.fromMillisecondsSinceEpoch(...),
      'lastRating': 'Good'
    });
```

#### 2.2 Típus: `dynamic_quiz` - Dinamikus Kvíz

**Specifikus mezők**:
```json
{
  "type": "dynamic_quiz",
  "question_bank_id": "string (referencia question_banks kollekció)",
  "quiz_config": {
    "questionCount": "number",
    "shuffleQuestions": "boolean",
    "shuffleOptions": "boolean",
    "showExplanations": "boolean"
  }
}
```

#### 2.3 Típus: `text` - Szöveges Jegyzet

**Specifikus mezők**:
```json
{
  "type": "text",
  "content": "string (HTML/markdown)"
}
```

#### 2.4 Típus: `interactive` - Interaktív Jegyzet

**Specifikus mezők**:
```json
{
  "type": "interactive",
  "sections": [
    {
      "type": "text | image | video | quiz",
      "content": "mixed"
    }
  ]
}
```

#### 2.5 Típus: `source` - Forrás/Irodalom

**Specifikus mezők**:
```json
{
  "type": "source",
  "author": "string",
  "publicationYear": "number",
  "publisher": "string",
  "isbn": "string",
  "url": "string"
}
```

---

### 3. `categories` - Kategóriák

**Dokumentum ID**: Auto-generált Firestore ID

**Struktúra**:
```json
{
  "name": "string",
  "icon": "string",
  "color": "string",
  "science_id": "string (referencia sciences kollekció)",
  "order": "number",
  "createdAt": "Timestamp",
  "updatedAt": "Timestamp"
}
```

**Mobil lekérés**:
```dart
final categories = await FirebaseFirestore.instance
    .collection('categories')
    .orderBy('order')
    .get();
```

---

### 4. `sciences` - Tudományterületek

**Dokumentum ID**: Auto-generált Firestore ID

**Struktúra**:
```json
{
  "name": "string",
  "description": "string",
  "icon": "string",
  "order": "number",
  "createdAt": "Timestamp"
}
```

---

### 5. `bundles` - Jegyzet Csomagok

**Dokumentum ID**: Auto-generált Firestore ID

**Struktúra**:
```json
{
  "title": "string",
  "description": "string",
  "noteIds": ["string"],
  "categoryId": "string",
  "science": "string",
  "isPremium": "boolean",
  "price": "number",
  "createdAt": "Timestamp",
  "updatedAt": "Timestamp"
}
```

---

### 6. `question_banks` - Kérdésbankok

**Dokumentum ID**: Auto-generált Firestore ID

**Struktúra**:
```json
{
  "title": "string",
  "categoryId": "string",
  "questions": [
    {
      "question": "string",
      "options": [
        {
          "text": "string",
          "isCorrect": "boolean",
          "rationale": "string"
        }
      ],
      "tag": "string | null",
      "noteId": "string | null",
      "noteStatus": "string | null"
    }
  ],
  "createdAt": "Timestamp",
  "updatedAt": "Timestamp"
}
```

**Mobil lekérés (személyre szabva)**:
```dart
// 1. Kérdésbank lekérése
final doc = await FirebaseFirestore.instance
    .collection('question_banks')
    .doc(questionBankId)
    .get();

// 2. Nemrég kiszolgált kérdések lekérése
final servedDocs = await FirebaseFirestore.instance
    .collection('users')
    .doc(userId)
    .collection('served_questions')
    .where('ttl', isGreaterThan: Timestamp.now())
    .get();

// 3. Kérdések szűrése (kliens oldal)
final availableQuestions = questions
    .where((q) => !servedHashes.contains(q.hash))
    .toList();
availableQuestions.shuffle();

// 4. Kiszolgált kérdések mentése
await FirebaseFirestore.instance
    .collection('users')
    .doc(userId)
    .collection('served_questions')
    .doc(questionHash)
    .set({
      'lastServed': FieldValue.serverTimestamp(),
      'ttl': Timestamp.fromMillisecondsSinceEpoch(
          DateTime.now().add(Duration(hours: 1)).millisecondsSinceEpoch)
    });
```

---

### 7. `user_2fa` - Kétfaktoros Hitelesítés

**Dokumentum ID**: `{userId}`

**Struktúra**:
```json
{
  "secret": "string (base32 encoded)",
  "enabled": "boolean",
  "backupCodes": ["string"],
  "createdAt": "Timestamp",
  "lastUsed": "Timestamp"
}
```

---

### 8. Fizetési és Előfizetési Kollekciók

#### 8.1 `web_payments` - Webes Fizetések (SimplePay)
**Cloud Functions által írható, felhasználó csak olvashat.**

**Struktúra**:
```json
{
  "userId": "string",
  "amount": "number",
  "currency": "HUF",
  "status": "pending | completed | failed",
  "transactionId": "string",
  "provider": "simplepay",
  "createdAt": "Timestamp",
  "completedAt": "Timestamp | null"
}
```

#### 8.2 `play_purchase_tokens` - Google Play Tokenek
**Cloud Functions által kezelve.**

#### 8.3 `verification_queue` - Előfizetés Ellenőrzési Sor
**Cloud Functions által kezelve.**

#### 8.4 `device_change_codes` - Eszközcsere Kódok
**Cloud Functions által generált.**

---

## Firestore Security Rules Összefoglalás

### Általános Szabályok

```javascript
// Admin ellenőrzés
function isAdmin() {
  return request.auth != null &&
         request.auth.token.email in ['tattila.ninox@gmail.com'];
}

// Prémium hozzáférés
function hasPremiumAccess() {
  let userData = get(/databases/$(database)/documents/users/$(request.auth.uid)).data;
  let now = request.time;
  
  // Próbaidő ellenőrzése
  if (userData.freeTrialEndDate != null && userData.freeTrialEndDate > now) {
    return true;
  }
  
  // Előfizetés ellenőrzése
  if (userData.isSubscriptionActive == true) {
    // Ha van subscriptionEndDate, azt is ellenőrizni kell
    if (userData.subscriptionEndDate != null) {
      return userData.subscriptionEndDate > now;
    }
    // Ha nincs subscriptionEndDate, akkor az isSubscriptionActive dönt (visszafelé kompatibilitás)
    return true;
  }
  
  return false;
}
```

### Kollekciók Hozzáférési Szabályai

| Kollekció | Olvasás | Írás |
|-----------|---------|------|
| `users/{userId}` | Saját + admin | Saját + admin |
| `users/{userId}/categories/{catId}/learning/{docId}` | Saját + admin | Saját + admin |
| `users/{userId}/category_stats/{catId}` | Saját + admin | Saját + admin |
| `users/{userId}/deck_stats/{deckId}` | Saját + admin | Saját + admin |
| `users/{userId}/served_questions/{qId}` | Saját + admin | Saját + admin |
| `notes/{noteId}` | LIST: auth, GET: auth + (isFree OR premium) | Admin |
| `categories/{categoryId}` | Auth | Admin |
| `sciences/{scienceId}` | Auth | Admin |
| `bundles/{bundleId}` | Auth | Admin |
| `question_banks/{bankId}` | Auth | Admin |
| `user_2fa/{userId}` | Saját + admin | Saját + admin |
| `web_payments/{paymentId}` | Saját + admin | Cloud Functions |
| `play_purchase_tokens/*` | Admin | Cloud Functions |
| `verification_queue/*` | Admin | Cloud Functions |
| `device_change_codes/{codeId}` | Saját + admin | Cloud Functions |

**Speciális szabály** - `notes` frissítés:
- Admin: minden mező
- Felhasználó: csak `is_selected_for_learning` mező

---

## Optimalizációs Stratégiák

### 1. Batch Query Párhuzamosítás
A Firestore `whereIn` operátor max 30 elemet engedélyez. Nagy paklik esetén:

```dart
const chunkSize = 30;
final futures = <Future>[];
for (var i = 0; i < allCardIds.length; i += chunkSize) {
  final chunk = allCardIds.sublist(i, (i + chunkSize).clamp(0, allCardIds.length));
  futures.add(firestore.collection(...).where(FieldPath.documentId, whereIn: chunk).get());
}
final results = await Future.wait(futures); // Párhuzamos végrehajtás
```

**Sebesség**: Akár 10x gyorsabb mint szekvenciális lekérés.

### 2. Tanulási Adatok Cache
```dart
static final Map<String, List<int>> _dueCardsCache = {};
static final Map<String, DateTime> _cacheTimestamps = {};
static const Duration _cacheValidity = Duration(minutes: 5);
```

### 3. Timeout Védelem
```dart
final learningDataMap = await _getBatchLearningData(...)
    .timeout(Duration(seconds: 30));
```

Timeout esetén alapértelmezett adatokkal tér vissza.

### 4. Denormalizáció
- `notes` dokumentumban a `category` név denormalizálva (nem csak `category_id`)
- `deck_stats` kártyánkénti értékelések cache-elése

---

## Migráció Legacy Rendszerből

Az alkalmazás támogatja a fokozatos migrációt:

**Legacy útvonal**: `users/{userId}/user_learning_data/{cardId}`  
**Új útvonal**: `users/{userId}/categories/{categoryId}/learning/{cardId}`

**Migrációs logika**:
1. Új adat mentésekor: új útvonalra írás + legacy törlése
2. Olvasáskor: 
   - Elsőként új útvonal ellenőrzése
   - Ha nincs adat, legacy útvonal ellenőrzése
   - Alapértelmezett adatok visszaadása ha egyik sem található

---

## Spaced Repetition Algoritmus Konfiguráció

```dart
class SpacedRepetitionConfig {
  static const learningSteps = [1, 10, 1440]; // 1p, 10p, 1 nap
  static const lapseSteps = [10]; // Felejtett kártya
  static const easyBonus = 1.3;
  static const newCardLimit = 20;
  static const minEaseFactor = 1.3;
  static const maxEaseFactor = 2.5;
  static const maxInterval = 60 * 24 * 60; // 60 nap percben
}
```

**Állapotgép**:
- `NEW` → `LEARNING` → `REVIEW`
- Értékelések: `Again`, `Hard`, `Good`, `Easy`
- SM-2 alapú intervallum számítás

---

## Offline Támogatás

Firestore automatikus offline cache:
```dart
await FirebaseFirestore.instance
    .enablePersistence()
    .catchError((err) {
      if (err.code == 'failed-precondition') {
        // Multiple tabs open
      } else if (err.code == 'unimplemented') {
        // Browser doesn't support
      }
    });
```

A mobil app automatikusan cache-eli a lekért adatokat.

---

## API Referencia - Főbb Service Osztályok

### `LearningService`
- `updateUserLearningData(cardId, rating, categoryId)` - Tanulási adat frissítése
- `getDueFlashcardIndicesForDeck(deckId)` - Esedékes kártyák lekérése
- `resetDeckProgress(deckId, cardCount)` - Pakli előrehaladás törlése
- `getDeckStats(deckId)` - Pakli statisztikák (NEW/LEARNING/REVIEW/DUE számlálók)

### `QuestionBankService`
- `getQuestionBank(questionBankId)` - Kérdésbank lekérése
- `getPersonalizedQuestions(questionBankId, userId, maxQuestions)` - Személyre szabott kérdések

### `NoteContentService`
- `getNoteContent(noteId)` - Jegyzet tartalom lekérése (freemium ellenőrzés)

---

## Freemium Model Implementáció

**Jegyzet hozzáférés**:
1. `list` művelet: Minden bejelentkezett felhasználó látja a jegyzeteket (lock ikon jelzéssel)
2. `get` művelet: 
   - Ha `isFree == true` → mindenki hozzáfér
   - Ha `isFree == false` → csak `hasPremiumAccess()` felhasználók

**Prémium ellenőrzés**:
```javascript
userData.isSubscriptionActive == true || 
(userData.freeTrialEndDate != null && userData.freeTrialEndDate > now)
```

---

## Verziókezelés és Kompatibilitás

- Firestore rules verzió: `rules_version = '2'`
- Minden időbélyeg: `FieldValue.serverTimestamp()` (időzóna független)
- Legacy kompatibilitás: Fokozatos migráció támogatása
- Soft delete: `deletedAt` mező használata (nem fizikai törlés)

---

## Teljesítmény Metrikák

| Művelet | Optimalizáció Előtt | Optimalizáció Után |
|---------|---------------------|-------------------|
| 100 kártya batch query | ~3000ms | ~300ms (10x) |
| Esedékes kártyák kalkuláció | ~2000ms | ~400ms (5x cache) |
| Kategória statisztika frissítés | ~500ms | ~100ms (transaction) |

---

## Verzió Információ
- **Utolsó frissítés**: 2025-10-29
- **Adatbázis verzió**: v2.0 (category-based learning paths)
- **API kompatibilitás**: Flutter 3.x + firebase_core 2.x


