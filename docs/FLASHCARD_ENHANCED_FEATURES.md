# Tanulókártya Kibővített Funkciók Dokumentáció

## Verzió: 1.0.1+7
**Utolsó frissítés**: 2025-10-29

---

## Áttekintés

A tanulókártya rendszer két különböző megközelítést támogat:

1. **Egyszerű Flashcard Paklik** - Gyors, szöveg alapú memorizálás
2. **Kibővített Kártya Paklik** - Multimédia-támogatással (HTML + Audio)

---

## 1. Egyszerű Flashcard Paklik (Eredeti Rendszer)

### Firestore Struktúra

**Kollekció**: `notes`  
**Dokumentum típus**: `type: "deck"`

```json
{
  "type": "deck",
  "title": "Farmakológia alapfogalmak",
  "category": "Farmakológia",
  "category_id": "abc123",
  "status": "Published",
  "flashcards": [
    {
      "front": "Mi a farmakokinetika?",
      "back": "A gyógyszer sorsának vizsgálata a szervezetben."
    },
    {
      "front": "Mi a farmakodinamika?", 
      "back": "A gyógyszer hatásának vizsgálata a szervezetre."
    }
  ],
  "tags": ["farmakológia", "alap"],
  "createdAt": "Timestamp",
  "modified": "Timestamp"
}
```

### Jellemzők

- ✅ **Gyors létrehozás** - Egyszerű szöveges előlap/hátlap párok
- ✅ **Tömeges kezelés** - Összes kártya egy dokumentumban
- ✅ **Flip animáció** - Kártya forgatás 3D effekttel
- ✅ **Spaced Repetition** - SM-2 algoritmus támogatás
- ✅ **Offline működés** - Firestore cache

### Megjelenítés a Mobilon

**Képernyő**: `flashcard_deck_view_screen.dart`, `flashcard_study_screen.dart`

```dart
// Pakli lekérése
final doc = await FirebaseFirestore.instance
    .collection('notes')
    .doc(deckId)
    .get();

final flashcards = List<Map<String, dynamic>>.from(
    doc.data()?['flashcards'] ?? []);

// Kártya megjelenítés
FlippableCard(
  frontText: flashcards[index]['front'],
  backText: flashcards[index]['back'],
)
```

---

## 2. Kibővített Kártya Paklik (ÚJ FUNKCIÓ)

### Koncepció

A kibővített kártya rendszer minden egyes kártyát **külön Firestore dokumentumként** tárol, lehetővé téve:

- **HTML formázott tartalmat** (képek, táblázatok, listák, színkódolás)
- **Hanganyag csatolást** (MP3 fájlok Firebase Storage-ból)
- **Richer szerkesztési lehetőségeket** (webes HTML editor)

### Firestore Struktúra

#### Pakli Dokumentum

**Kollekció**: `notes`  
**Dokumentum típus**: `type: "deck"` (ugyanaz, de `card_ids` mezővel)

```json
{
  "type": "deck",
  "title": "Anatómia - Kibővített",
  "category": "Anatómia",
  "category_id": "xyz789",
  "status": "Published",
  "card_ids": [
    "card_001_abc",
    "card_002_def",
    "card_003_ghi"
  ],
  "tags": ["anatómia", "multimedia"],
  "createdAt": "Timestamp",
  "modified": "Timestamp"
}
```

**Megjegyzés**: A `card_ids` lista határozza meg a kártyák **sorrendjét**. Az admin felületen drag-and-drop-pal átrendelhető.

#### Kártya Dokumentumok

**Kollekció**: `notes` (ugyanaz, külön dokumentumok)  
**Nincs explicit `type` mező** (vagy lehet `type: "card"`)

```json
{
  "title": "A szív anatómiai felépítése",
  "html": "<h2>A szív</h2><p>A szív egy <strong>négyüregű</strong> izomszerv...</p><ul><li>Jobb pitvar</li><li>Jobb kamra</li><li>Bal pitvar</li><li>Bal kamra</li></ul>",
  "audioUrl": "https://firebasestorage.googleapis.com/v0/b/orlomed-f8f9f.appspot.com/o/notes%2Fcard_001_abc%2Fsziv_anatomia.mp3?alt=media&token=...",
  "deckId": "deck_xyz_123",
  "createdAt": "Timestamp",
  "modified": "Timestamp"
}
```

### Firestore Security Rules

```javascript
// Kártya dokumentumok olvasása
match /notes/{noteId} {
  allow get: if request.auth != null &&
                (isAdmin() ||
                 (resource.data.status in ['Published', 'Public'] && 
                  (resource.data.isFree == true || hasPremiumAccess())));
}
```

**Fontos**: A kártya dokumentumok ugyanúgy a `notes` kollekció részei, így ugyanazok a security rules vonatkoznak rájuk, mint a többi jegyzetre.

---

## Firebase Storage Struktúra (Hanganyagok)

### Tárolási Útvonal

```
notes/
  └── {cardId}/
        └── {fájlnév}.mp3
```

**Példa**:
```
notes/
  └── card_001_abc/
        └── sziv_anatomia.mp3
  └── card_002_def/
        └── verkeringes_rendszer.mp3
```

### Fájl Specifikációk

- **Formátum**: MP3 (audio/mpeg)
- **Maximális méret**: 10 MB
- **Kódolás**: Ajánlott: 128-192 kbps, 44.1 kHz
- **Tárolás**: Firebase Storage (CDN gyorsítótárazással)

### Upload Folyamat

```dart
// 1. Fájl kiválasztás (Admin felület - Web)
final file = await openFile(acceptedTypeGroups: [
  XTypeGroup(label: 'MP3', extensions: ['mp3'])
]);

// 2. Méret ellenőrzés
final bytes = await file.readAsBytes();
if (bytes.length > 10 * 1024 * 1024) {
  throw Exception('Max 10 MB MP3!');
}

// 3. Firebase Storage upload
final ref = FirebaseStorage.instance
    .ref('notes/${cardId}/${fileName}');
await ref.putData(bytes);

// 4. Download URL lekérése
final audioUrl = await ref.getDownloadURL();

// 5. Firestore frissítés
await FirebaseFirestore.instance
    .collection('notes')
    .doc(cardId)
    .update({'audioUrl': audioUrl});
```

---

## Admin Felület - Kártya Szerkesztés

### Képernyő: `flashcard_card_edit_screen.dart`

**Elérés**: `/flashcard-cards/edit/{cardId}`

### Funkciók

#### 1. Kártya Cím Szerkesztése
```dart
TextField(
  controller: _titleCtrl,
  decoration: InputDecoration(
    labelText: 'Kártya címe (admin felületen látszik)',
  ),
)
```

**Használat**: Adminisztratív azonosítás, a felhasználók nem látják.

#### 2. HTML Kód Szerkesztés

```dart
TextField(
  controller: _htmlCtrl,
  maxLines: 25,
  decoration: InputDecoration(
    border: OutlineInputBorder(),
    hintText: 'Illessze be a kártya teljes HTML kódját...',
  ),
)
```

**Támogatott HTML elemek**:
- Címsorok: `<h1>`, `<h2>`, `<h3>`
- Formázás: `<strong>`, `<em>`, `<u>`, `<mark>`
- Listák: `<ul>`, `<ol>`, `<li>`
- Táblázatok: `<table>`, `<tr>`, `<td>`, `<th>`
- Képek: `<img src="...">`
- Bekezdések: `<p>`, `<div>`, `<span>`
- Színek: inline `style="color: #FF5733"`

**Példa HTML**:
```html
<h2 style="color: #2563EB;">A vérkeringési rendszer</h2>
<p>A vérkeringés <strong>két nagy körre</strong> osztható:</p>
<ul>
  <li><mark>Nagy vérkör</mark> - Szisztémás keringés</li>
  <li><mark>Kis vérkör</mark> - Pulmonális keringés</li>
</ul>
<img src="https://example.com/verkor.png" width="400">
```

#### 3. Hanganyag Csatolása

```dart
// Fájl kiválasztás gomb
ElevatedButton.icon(
  onPressed: _pickAudio,
  icon: Icon(Icons.attach_file),
  label: Text('Kiválasztás'),
)

// Hangfájl információ megjelenítése
Text(_audio?['name'] ?? 'Nincs hangfájl csatolva.')

// Eltávolítás gomb
IconButton(
  icon: Icon(Icons.delete, color: Colors.redAccent),
  onPressed: _removeAudio,
)
```

#### 4. Előnézet Funkció

```dart
void _showPreview() {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Előnézet'),
      content: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Html(data: _htmlCtrl.text),
            ),
          ),
          if (_audio != null)
            MiniAudioPlayer(audioUrl: _audio!['url']),
        ],
      ),
    ),
  );
}
```

**Funkció**: Valós idejű előnézet a HTML renderelésről és az audio lejátszásról mentés előtt.

#### 5. Mentés Logika

```dart
Future<void> _saveCard() async {
  // 1. Audio feltöltés (ha van új fájl)
  String? audioUrl;
  if (_audio != null && _audio!.containsKey('bytes')) {
    final ref = FirebaseStorage.instance
        .ref('notes/${widget.cardId}/${_audio!['name']}');
    await ref.putData(_audio!['bytes']);
    audioUrl = await ref.getDownloadURL();
  } else if (_audio!.containsKey('url')) {
    audioUrl = _audio!['url']; // Meglévő URL megtartása
  }

  // 2. Firestore frissítés
  await FirebaseFirestore.instance
      .collection('notes')
      .doc(widget.cardId)
      .update({
        'title': _titleCtrl.text.trim(),
        'html': _htmlCtrl.text.trim(),
        'audioUrl': audioUrl,
        'modified': Timestamp.now(),
      });
}
```

---

## Mobil Alkalmazás - Kártya Megjelenítés

### Képernyő: `deck_view_screen.dart`

**Navigáció**: 
```dart
if (noteData['type'] == 'deck' && noteData.containsKey('card_ids')) {
  context.go('/deck/${deckId}/view');
}
```

### Adatlekérés

#### 1. Pakli Metaadatok

```dart
final deckDoc = await FirebaseFirestore.instance
    .collection('notes')
    .doc(deckId)
    .get();

final data = deckDoc.data() as Map<String, dynamic>;
final cardIds = List<String>.from(data['card_ids'] ?? []);
```

#### 2. Kártya Dokumentumok (Batch)

```dart
if (cardIds.isNotEmpty) {
  final cardDocs = await FirebaseFirestore.instance
      .collection('notes')
      .where(FieldPath.documentId, whereIn: cardIds)
      .get();
  
  // Sorba rendezés a card_ids lista szerint
  _cards = cardDocs.docs
    ..sort((a, b) => 
        cardIds.indexOf(a.id).compareTo(cardIds.indexOf(b.id)));
}
```

**Optimalizáció**: Firestore `whereIn` max 30 elemet engedélyez. 30+ kártya esetén chunk-olni kell:

```dart
const chunkSize = 30;
final futures = <Future>[];
for (var i = 0; i < cardIds.length; i += chunkSize) {
  final chunk = cardIds.sublist(
      i, (i + chunkSize).clamp(0, cardIds.length));
  futures.add(FirebaseFirestore.instance
      .collection('notes')
      .where(FieldPath.documentId, whereIn: chunk)
      .get());
}
final results = await Future.wait(futures);
final allDocs = results.expand((snap) => snap.docs).toList();
```

### UI Komponensek

#### PageView - Lapozható Kártyák

```dart
PageView.builder(
  controller: _pageController,
  itemCount: _cards.length,
  onPageChanged: (index) => setState(() => _currentPage = index),
  itemBuilder: (context, index) {
    final cardData = _cards[index].data() as Map<String, dynamic>;
    final htmlContent = cardData['html'] ?? 'Nincs tartalom.';
    
    return Padding(
      padding: EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Html(data: htmlContent), // flutter_html csomag
      ),
    );
  },
)
```

#### Navigációs Sáv

```dart
Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    IconButton(
      icon: Icon(Icons.arrow_back_ios),
      onPressed: _currentPage > 0 ? () {
        _pageController.previousPage(
          duration: Duration(milliseconds: 300),
          curve: Curves.ease,
        );
      } : null,
    ),
    Text('Kártya ${_currentPage + 1} / ${_cards.length}'),
    IconButton(
      icon: Icon(Icons.arrow_forward_ios),
      onPressed: _currentPage < _cards.length - 1 ? () {
        _pageController.nextPage(
          duration: Duration(milliseconds: 300),
          curve: Curves.ease,
        );
      } : null,
    ),
  ],
)
```

#### HTML Renderelés

**Csomag**: `flutter_html: ^3.0.0-beta.2`

```dart
Html(
  data: htmlContent,
  style: {
    "body": Style(
      fontSize: FontSize(16),
      lineHeight: LineHeight(1.6),
    ),
    "h2": Style(
      color: Color(0xFF1E3A8A),
      fontWeight: FontWeight.bold,
    ),
    "strong": Style(
      fontWeight: FontWeight.bold,
      color: Colors.black87,
    ),
    "mark": Style(
      backgroundColor: Colors.yellow.shade200,
    ),
  },
)
```

---

## Audio Lejátszás - Kibővített Kártyákon

### Widget: `MiniAudioPlayer`

**Használat**:
```dart
if (currentCardData['audioUrl'] != null &&
    currentCardData['audioUrl'].toString().isNotEmpty) {
  Container(
    padding: EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      border: Border(top: BorderSide(color: Colors.grey.shade300)),
    ),
    child: MiniAudioPlayer(audioUrl: currentCardData['audioUrl']),
  ),
}
```

### Audio Kontrollok

- **▶️ Play/Pause** - Lejátszás indítása/szüneteltetése
- **⏪ -10s** - 10 másodperc visszaugrás
- **⏩ +10s** - 10 másodperc előreugrás
- **⏹️ Stop** - Megállítás és pozíció nullázása
- **🔁 Loop** - Folyamatos ismétlés (opcionális)
- **⏱️ Időjelző** - Hátralévő idő megjelenítése (pl. `02:35`)

### Lazy Loading Optimalizáció

```dart
MiniAudioPlayer(
  audioUrl: audioUrl,
  deferInit: true, // Csak kattintásra inicializál
  compact: false,  // Teljes kontroller megjelenítése
)
```

**Előnyök**:
- Lista nézetekben nem tölti be az összes audiót egyszerre
- Hálózati sávszélesség megtakarítás
- Gyorsabb oldal betöltés

### Offline Cache

Az `audioplayers` csomag automatikusan cache-eli a lejátszott fájlokat:

```dart
await _audioPlayer.setSource(UrlSource(
  audioUrl,
  mimeType: 'audio/mpeg',
));
```

**Cache viselkedés**:
- Első lejátszás: Letöltés Firebase Storage CDN-ről
- Második lejátszás: Helyi cache használata
- Cache méret: Operációs rendszer kezeli (általában 50-100 MB)

---

## Különbségek a Két Rendszer Között

| Jellemző | Egyszerű Flashcard | Kibővített Kártya |
|----------|-------------------|-------------------|
| **Firestore struktúra** | 1 dokumentum, `flashcards` tömb | Pakli + külön kártya dokumentumok |
| **Tartalom típus** | Csak szöveg (front/back) | HTML + Audio |
| **Formázás** | Nincs | Teljes HTML (színek, képek, táblázatok) |
| **Audio támogatás** | ❌ Nincs | ✅ MP3 fájlok Firebase Storage-ból |
| **Szerkesztési felület** | Egyszerű TextField | HTML editor + fájl feltöltő |
| **Megjelenítés** | FlippableCard widget (flip animáció) | PageView + Html widget + AudioPlayer |
| **Offline működés** | ✅ Teljes (Firestore cache) | ✅ Részleges (HTML cache-elve, audio stream) |
| **Spaced Repetition** | ✅ Teljes SM-2 támogatás | ⚠️ Jelenleg nincs (jövőbeli feature) |
| **Használati eset** | Gyors memorizálás, definíciók | Részletes tananyag, előadás jegyzetek |
| **Teljesítmény** | ⚡ Nagyon gyors (1 query) | 🐢 Lassabb (1 + N query, ahol N = kártyák száma) |
| **Tárolási költség** | Alacsony | Magasabb (Storage + Firestore reads) |

---

## Hogyan Jelenik Meg a Hátoldalon a Kibővített Tartalom?

### Egyszerű Flashcard (Hagyományos)

A **hátoldal** a `FlippableCard` widget-ben jelenik meg:

```dart
FlippableCard(
  frontText: 'Mi a farmakokinetika?',
  backText: 'A gyógyszer sorsának vizsgálata a szervezetben.',
)
```

**Megjelenítés**:
1. Felhasználó megérinti a kártyát
2. 500ms flip animáció (3D forgatás Y tengely körül)
3. Hátoldal megjelenik: egyszerű szöveg, középre igazítva, `fontSize: 16`

**Hátoldal stílus**:
```dart
Text(
  backText,
  textAlign: TextAlign.center,
  style: TextStyle(
    color: Color(0xFF2D3748),
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.6, // sormagasság
  ),
)
```

---

### Kibővített Kártya (HTML + Audio)

A **teljes kártya** egy `PageView` oldalként jelenik meg (nincs külön előlap/hátlap):

#### HTML Tartalom Renderelése

```dart
SingleChildScrollView(
  child: Html(
    data: cardData['html'],
    style: {
      "body": Style(
        margin: Margins.all(0),
        padding: HtmlPaddings.all(16),
      ),
      "h1": Style(
        fontSize: FontSize(24),
        fontWeight: FontWeight.bold,
        color: Color(0xFF1E3A8A),
      ),
      "h2": Style(
        fontSize: FontSize(20),
        fontWeight: FontWeight.bold,
        color: Color(0xFF2563EB),
      ),
      "p": Style(
        fontSize: FontSize(16),
        lineHeight: LineHeight(1.6),
        margin: Margins.only(bottom: 12),
      ),
      "ul": Style(
        margin: Margins.only(left: 20, bottom: 12),
      ),
      "li": Style(
        margin: Margins.only(bottom: 8),
      ),
      "strong": Style(
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
      "mark": Style(
        backgroundColor: Colors.yellow.shade200,
        padding: HtmlPaddings.symmetric(horizontal: 4),
      ),
      "table": Style(
        border: Border.all(color: Colors.grey),
        margin: Margins.only(bottom: 16),
      ),
      "td": Style(
        border: Border.all(color: Colors.grey.shade300),
        padding: HtmlPaddings.all(8),
      ),
    },
  ),
)
```

#### Audio Lejátszó Megjelenítése

Az audio lejátszó a kártya tartalma **alatt** jelenik meg, rögzített sávban:

```dart
Column(
  children: [
    // Kártya tartalom (HTML)
    Expanded(
      child: SingleChildScrollView(
        child: Html(data: htmlContent),
      ),
    ),
    
    // Audio lejátszó sáv (ha van audioUrl)
    if (cardData['audioUrl'] != null &&
        cardData['audioUrl'].toString().isNotEmpty)
      Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          border: Border(
            top: BorderSide(
              color: Colors.grey.shade300,
              width: 1,
            ),
          ),
        ),
        child: MiniAudioPlayer(
          audioUrl: cardData['audioUrl'],
          deferInit: true,
          compact: false,
        ),
      ),
  ],
)
```

**Vizuális elrendezés**:
```
┌─────────────────────────────────┐
│                                 │
│    [HTML Tartalom]              │
│    - Címsor                     │
│    - Bekezdések                 │
│    - Listák                     │
│    - Képek                      │
│                                 │  ← Scrollable
│                                 │
│                                 │
├─────────────────────────────────┤
│ ⏪ ▶️ ⏩ ⏹️ 🔁      02:35    │  ← Fixed
└─────────────────────────────────┘
```

---

## Hová Menti az Új Adatokat?

### 1. Firestore - `notes` Kollekció

#### Pakli Dokumentum
**Dokumentum ID**: Auto-generált (pl. `deck_2025_xyz`)

```javascript
{
  type: "deck",
  title: "Anatómia - Szív és Érrendszer",
  category: "Anatómia",
  category_id: "cat_anatomia_123",
  status: "Published",
  isFree: false, // Freemium modell
  card_ids: [
    "card_sziv_001",
    "card_erk_002",
    "card_verk_003"
  ],
  tags: ["anatómia", "szív", "érrendszer"],
  createdAt: Timestamp(2025, 10, 29, ...),
  modified: Timestamp(2025, 10, 29, ...),
  deletedAt: null
}
```

**Útvonal**: `/notes/{deck_2025_xyz}`

#### Kártya Dokumentumok (3 db példa)

**Kártya 1**: `/notes/card_sziv_001`
```javascript
{
  title: "A szív anatómiája",
  html: "<h2>A szív felépítése</h2><p>A szív egy <strong>négyüregű</strong>...</p>",
  audioUrl: "https://firebasestorage.googleapis.com/.../card_sziv_001/sziv_eloadas.mp3",
  deckId: "deck_2025_xyz",
  createdAt: Timestamp(...),
  modified: Timestamp(...)
}
```

**Kártya 2**: `/notes/card_erk_002`
```javascript
{
  title: "Artériák és vénák",
  html: "<h2>Érrendszer típusai</h2><ul><li><mark>Artériák</mark>...</li></ul>",
  audioUrl: "https://firebasestorage.googleapis.com/.../card_erk_002/erek_eloadas.mp3",
  deckId: "deck_2025_xyz",
  createdAt: Timestamp(...),
  modified: Timestamp(...)
}
```

**Kártya 3**: `/notes/card_verk_003`
```javascript
{
  title: "Nagy és kis vérkör",
  html: "<h2>Vérkeringés</h2><table><tr><th>Kör</th><th>Útvonal</th></tr>...</table>",
  audioUrl: null, // Ez a kártya nem tartalmaz audiót
  deckId: "deck_2025_xyz",
  createdAt: Timestamp(...),
  modified: Timestamp(...)
}
```

---

### 2. Firebase Storage - Audio Fájlok

#### Tárolási Struktúra

```
gs://orlomed-f8f9f.appspot.com/
  └── notes/
        ├── card_sziv_001/
        │     └── sziv_eloadas.mp3          (5.2 MB)
        ├── card_erk_002/
        │     └── erek_eloadas.mp3          (3.8 MB)
        └── card_verk_003/
              (üres - nincs audio)
```

#### Download URL Generálás

A Firebase Storage automatikusan generál egy **egyedi, tokenizált URL-t**:

```
https://firebasestorage.googleapis.com/v0/b/orlomed-f8f9f.appspot.com/o/notes%2Fcard_sziv_001%2Fsziv_eloadas.mp3?alt=media&token=abc123def456...
```

**URL komponensek**:
- `v0/b/orlomed-f8f9f.appspot.com` - Bucket azonosító
- `o/notes%2Fcard_sziv_001%2Fsziv_eloadas.mp3` - Fájl útvonal (URL-encoded)
- `?alt=media` - Direct download mode
- `&token=...` - Hozzáférési token (security)

**Token tulajdonságok**:
- ✅ Publikus (nem kell Firebase Auth)
- ✅ CDN cache-elés
- ✅ Nincs lejárat (addig érvényes, amíg nem generálsz újat)
- ⚠️ Bárki hozzáfér, aki ismeri az URL-t (nem secret!)

---

### 3. Firestore Security Rules Hatása

#### Kártya Dokumentumok Olvasása

```javascript
match /notes/{noteId} {
  allow get: if request.auth != null &&
                (isAdmin() ||
                 (resource.data.status in ['Published', 'Public'] && 
                  (resource.data.isFree == true || hasPremiumAccess())));
}
```

**Következmények**:
- ✅ Publikus kártyák: Minden bejelentkezett felhasználó hozzáfér
- 🔒 Prémium kártyák: Csak aktív előfizetők (vagy `isFree: true`)
- ❌ Draft kártyák: Csak admin

**Fontos**: A `card_ids` listában szereplő kártya dokumentumoknak is meg kell felelniük a security rules-oknak!

#### Firebase Storage Security Rules

```javascript
match /notes/{cardId}/{fileName} {
  allow read: if request.auth != null;
  allow write: if false; // Csak admin (Firebase Admin SDK-n keresztül)
}
```

**Következmény**: Az audio URL publikusan hozzáférhető bárki számára, aki ismeri az URL-t (a token miatt). Ezért fontos, hogy a Firestore rules védjék a kártya dokumentumokat.

---

## Használati Példa - Teljes Folyamat

### 1. Admin Létrehoz Egy Kibővített Paklit

```
1. Admin navigál: /flashcard-decks
2. "Új Pakli" gomb → Kitölti a form-ot:
   - Cím: "Farmakológia 101"
   - Kategória: "Farmakológia"
   - Típus: "Kibővített kártya pakli" (opció)
3. Pakli létrejön Firestore-ban:
   /notes/{deckId} - type: "deck", card_ids: []
```

### 2. Admin Hozzáad Egy Kártyát

```
1. Pakli szerkesztő nézetben: "Új Kártya" gomb
2. Új kártya dokumentum létrejön:
   /notes/{cardId} - title: "Névtelen kártya"
3. Admin átnavigál: /flashcard-cards/edit/{cardId}
4. Kitölti a form-ot:
   - Cím: "ACE inhibitorok"
   - HTML: "<h2>ACE inhibitorok</h2><p>Az ACE gátlók...</p>"
   - Hangfájl: Feltölt egy 8.5 MB-os "ace_inhibitorok.mp3" fájlt
5. "Mentés" gomb:
   a. Hangfájl upload:
      - Útvonal: notes/{cardId}/ace_inhibitorok.mp3
      - Download URL: https://firebasestorage.googleapis.com/.../ace_inhibitorok.mp3?token=...
   b. Firestore update:
      - /notes/{cardId} → html: "...", audioUrl: "https://..."
   c. Pakli frissítése:
      - /notes/{deckId} → card_ids: [{cardId}]
6. Visszanavigál a pakli szerkesztőbe
```

### 3. Felhasználó Megtekinti a Paklit Mobilon

```
1. Felhasználó bejelentkezik
2. Jegyzetek lista → "Farmakológia 101" pakli
3. Rákattint → Navigáció: /deck/{deckId}/view
4. App lekéri a pakli adatokat:
   a. GET /notes/{deckId}
      → Válasz: { title: "...", card_ids: [{cardId}] }
   b. GET /notes WHERE __name__ IN [{cardId}]
      → Válasz: [{ html: "...", audioUrl: "https://..." }]
5. PageView megjelenítés:
   - Kártya 1/1
   - HTML renderelés (címsor, bekezdések, listák)
   - Audio lejátszó sáv alul
6. Felhasználó megnyomja a Play gombot:
   - AudioPlayer lekéri az MP3-at: https://firebasestorage.googleapis.com/.../ace_inhibitorok.mp3
   - Lejátszás indul, 02:45 időtartam
7. Felhasználó lapoz a következő kártyára:
   - Swipe jobbra → PageController.nextPage()
   - Előző audio automatikusan megáll (dispose)
   - Új kártya HTML-je renderelődik
```

---

## Jövőbeli Továbbfejlesztési Lehetőségek

### 1. Spaced Repetition Integráció Kibővített Kártyákhoz

```dart
// Tanulási adat mentése külön kártya dokumentumokhoz
await FirebaseFirestore.instance
    .collection('users')
    .doc(userId)
    .collection('categories')
    .doc(categoryId)
    .collection('learning')
    .doc(cardId) // Nem {deckId}#{index}, hanem közvetlenül {cardId}
    .set({
      'state': 'LEARNING',
      'interval': 10,
      // ... stb.
    });
```

**Kihívás**: Jelenleg a learning rendszer `{deckId}#{cardIndex}` formátumot használ, ami az egyszerű flashcard paklikra van optimalizálva.

### 2. Kártya Státusz Jelzők

```dart
// Mobil nézetben jelezzük, mely kártyákat tanulta már
PageView.builder(
  itemBuilder: (context, index) {
    final isCompleted = learningData[cardIds[index]]?.state == 'REVIEW';
    return Stack(
      children: [
        Html(data: htmlContent),
        if (isCompleted)
          Positioned(
            top: 8,
            right: 8,
            child: Icon(Icons.check_circle, color: Colors.green),
          ),
      ],
    );
  },
)
```

### 3. Kártya Keresés és Szűrés

```dart
// Keresés a HTML tartalomban
final results = allCards.where((card) {
  final html = card['html'] as String;
  return html.toLowerCase().contains(searchQuery.toLowerCase());
}).toList();
```

### 4. Offline Mód Javítása

```dart
// Audio előre letöltése offline használatra
await _audioPlayer.setSource(UrlSource(audioUrl));
await _audioPlayer.preload(); // Cache-eli a teljes fájlt
```

### 5. Video Támogatás

```json
{
  "videoUrl": "https://firebasestorage.googleapis.com/.../demo_video.mp4",
  "videoThumbnail": "https://firebasestorage.googleapis.com/.../thumbnail.jpg"
}
```

```dart
VideoPlayer(
  controller: VideoPlayerController.network(cardData['videoUrl']),
)
```

### 6. Interaktív Kvíz Elemek HTML-ben

```html
<div class="quiz-question">
  <p>Hány kamrája van a szívnek?</p>
  <button onclick="checkAnswer('4')">4</button>
  <button onclick="checkAnswer('2')">2</button>
</div>
<script>
  function checkAnswer(answer) {
    if (answer === '4') {
      alert('Helyes!');
    } else {
      alert('Hibás válasz!');
    }
  }
</script>
```

**Megjegyzés**: A `flutter_html` csomag korlátozott JavaScript támogatással rendelkezik. WebView használata szükséges teljes interaktivitáshoz.

---

## Összefoglalás

### Egyszerű Flashcard Paklik
- ✅ **Gyors és egyszerű** memorizáláshoz
- ✅ **Spaced Repetition** algoritmus teljes támogatással
- ✅ **Offline működés** Firestore cache-sel
- ❌ Nincs multimédia támogatás

### Kibővített Kártya Paklik (ÚJ)
- ✅ **HTML formázás** (címsorok, listák, táblázatok, képek)
- ✅ **Audio támogatás** (MP3 fájlok Firebase Storage-ból)
- ✅ **Richer tartalom** előadás jegyzetek, részletes magyarázatok
- ⚠️ Spaced Repetition még nincs implementálva
- ⚠️ Nagyobb hálózati igény (több Firestore read, audio streaming)

**Választás**:
- **Egyszerű paklik**: Definíciók, nyelvtanulás, gyors felidézés
- **Kibővített paklik**: Előadás anyagok, részletes jegyz etek, audiokönyvek

---

## Kapcsolódó Fájlok

### Admin (Web)
- `lib/screens/flashcard_card_edit_screen.dart` - Kártya szerkesztő
- `lib/screens/deck_edit_screen.dart` - Pakli szerkesztő (egyszerű)
- `lib/widgets/mini_audio_player.dart` - Audio lejátszó widget

### Mobil
- `lib/screens/deck_view_screen.dart` - Kibővített pakli megjelenítő
- `lib/screens/flashcard_deck_view_screen.dart` - Egyszerű pakli megjelenítő
- `lib/screens/flashcard_study_screen.dart` - Tanulás mód (spaced repetition)
- `lib/widgets/flippable_card.dart` - Forgó kártya widget
- `lib/widgets/audio_preview_player.dart` - Audio lejátszó (egyéb jegyzetekhez)

### Adatbázis
- `firestore.rules` - Security rules
- `docs/FIRESTORE_DATABASE_STRUCTURE.md` - Teljes adatbázis séma

---

**Verzió**: 1.0.1+7  
**Dokumentáció készült**: 2025-10-29  
**Készítette**: AI Assistant (Claude Sonnet 4.5)


