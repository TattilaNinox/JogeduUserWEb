# Implementációs Terv: Dual Kvíz - "User Session Metadata" Megoldás

A felhasználói visszajelzés alapján ("metadata kollekció a betöltésre, egyedi módon minden felhasználóhoz") az alábbi módosított architektúrát valósítjuk meg. Ennek lényege, hogy a **Kérdésbank forrás (`question_banks`) érintetlen marad**, de a kiszolgálást egy felhasználó-specifikus "Session Metadata" rétegen keresztül optimalizáljuk.

## 1. Architektúra: "User Session Metadata"

A közvetlen `question_banks` olvasás helyett bevezetünk egy köztes réteget, amely a felhasználó aktuális kvíz munkamenetét (Session) tárolja.

### Adatmodell
- **Forrás (Master)**: `question_banks/{bankId}` (Marad változatlan, nagy dokumentum).
- **Session (Metadata)**: `users/{userId}/quiz_sessions/{bankId}`
    - Ez a dokumentum tárolja az aktuálisan kiválasztott, de még le nem játszott kérdéseket.
    - Tartalma:
        - `batch`: List<Question> (A következő pl. 20-30 kérdés adataival).
        - `lastUpdated`: Timestamp.
        - `servedHistory`: List<String> (A már feltett kérdések hash-ei a munkamenetben).

## 2. Működési Folyamat (QuestionBankService)

A service logikája az alábbiak szerint változik:

### A) Kvíz Indítása
1. **Check**: A rendszer megnézi a `users/{userId}/quiz_sessions/{bankId}` dokumentumot.
2. **Hit (Van aktív session)**: Ha a dokumentum létezik és a `batch` nem üres:
    - Kivesz 10 kérdést a `batch`-ből.
    - Frissíti a session dokumentumot (eltávolítja a kivett kérdéseket).
    - **Eredmény**: Azonnali betöltés, minimális adatforgalom (csak a session doc írás/olvasás).
3. **Miss (Nincs aktív session / Üres)**:
    - Letölti a `question_banks/{bankId}` forrásdokumentumot (Ez a "költséges" lépés).
    - **Batching**: Kiválaszt pl. **50 kérdést** (nem csak 10-et!) intelligens szűréssel (elmúlt 1 órában nem látott).
    - **Mentés**: Ezt az 50 kérdést elmenti a `users/{userId}/quiz_sessions/{bankId}` dokumentumba (`batch` mező).
    - Visszaadja az első 10-et.
    - **Eredmény**: Bár az első indítás lassabb/adatigényesebb, a következő **4 indítás ("Újra" gomb) azonnali és sávszélesség-kímélő lesz**, mivel a cache-ből dolgozik.

### B) Intelligencia (Személyre szabás)
- Mivel a Session dokumentum a felhasználó saját kollekciójában van (`users/{uid}/...`), a benne lévő `batch` már eleve személyre szabott.
- A `served_questions` (history) ellenőrzése a "Miss" ágon (generáláskor) történik meg.

## 3. Költség és Hatékonyság Elemzés

**Forgatókönyv**: 7000 felhasználó, 600 kérdéses bank (~300KB), napi 1 kvíz.

| Tényező | Jelenlegi (Minden indításnál teljes letöltés) | Javasolt (Session Cache, 5-ös ciklus) | Eredmény |
| :--- | :--- | :--- | :--- |
| **Hálózati Forgalom (Egress)** | 2.1 GB / nap | ~0.6 GB / nap | **~70% Csökkenés** (Jelentős!) |
| **Kliens Adathasználat** | 300 KB / kvíz | Átlag 80 KB / kvíz | **Gyorsabb mobil működés** |
| **Firestore Read (Olvasás)** | 1 db / kvíz | Átlag 1.2 db / kvíz | Minimális növekedés (+20%) |
| **Firestore Write (Írás)** | 0 db / kvíz | 1 db / kvíz | Növekedés (Állapotmentés ára) |

## 4. Perzisztencia (Adatmentés)

Mivel a "Session Metadata" (`quiz_sessions` kollekció) a **Firestore-ban (Felhőben) tárolódik**, a rendszer automatikusan biztosítja a folytathatóságot:

- **App bezárása**: Ha a felhasználó kilép az alkalmazásból, a Session **NEM VÉSZ EL**. A következő indításkor a rendszer megtalálja a létező dokumentumot, és onnan folytatja (vagy adja a következő adag kérdést), ahol abbahagyta.
- **Eszközváltás**: Ha a felhasználó mobilon kezd, majd desktopon folytatja, a Session szinkronizálódik, mivel ugyanahhoz a felhasználói fiókhoz (`users/{uid}`) kötődik az adat.

## 5. Megvalósítási Lépések

### Fázis 1: Service Réteg (`lib/services/question_bank_service.dart`)
- `getQuizSession(bankId)` metódus implementálása.
- Firestore logika a Session dokumentum írására/olvasására.
- Batch generáló logika (szűrés + randomizálás).

### Fázis 2: Kliens Oldali Bekötés
- **Mobil (`DynamicQuizViewScreen`)**: Átállás a `getQuizSession` használatra a direkt letöltés helyett.
- **Desktop (`NoteListTile`, `QuizViewerDual`)**: Átállás ugyanerre a service-re.

### Fázis 3: UI Feedback
- Ha a rendszer épp a "Nagy Letöltést" végzi (Miss ág), a felhasználónak egyértelmű "Kvíz előkészítése..." töltőképernyőt mutatunk, jelezve, hogy ez eltarthat pár másodpercig, de cserébe a következő körök gyorsak lesznek.
