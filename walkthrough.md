# Dual Kvíz Optimalizálás: Walkthrough

Ez a dokumentum bemutatja az elkészült fejlesztés részleteit és a tesztelési lépéseket.

## 1. Változások Összegzése

### Implementált Architektúra: "Session Metadata"
A rendszer mostantól nem tölti le minden egyes kvíz indításnál a teljes Kérdésbankot. Helyette:
1.  **Session Cache**: A felhasználó saját kollekciójába (`users/{uid}/quiz_sessions/{bankId}`) mentünk egy 50 kérdésből álló "csomagot".
2.  **Lazy Loading**: Indításkor innen veszünk ki 10 kérdést (azonnali betöltés).
3.  **Adatforgalom**: Csak akkor töltjük le a nagy bankot, ha a Session kiürült (kb. minden 5. alkalommal).
4.  **Perzisztencia**: Ha kilép az appból, a Session megmarad a felhőben, és onnan folytatódik (nem kezdődik elölről a sorrend).

### Érintett Fájlok
- `lib/models/quiz_models.dart`: Új `QuizSession` modell.
- `lib/services/question_bank_service.dart`: Új `getQuizSession` logika (generálás, mentés, fogyasztás).
- `lib/screens/dynamic_quiz_view_screen.dart`: Mobil nézet átállítása az új service-re.
- `lib/widgets/note_list_tile.dart`: Desktop listanézet átállítása az új service-re.

## 2. Tesztelési Útmutató

### A) Indítási Teszt (Első alkalom)
1.  Nyiss meg egy Dual Kvízt a listából.
2.  Látnod kell egy rövid "Kvíz előkészítése..." üzenetet (Snackbar) - Ez jelzi a "Cache Miss" állapotot, amikor a nagy bankot tölti.
3.  A kvíz elindul 10 kérdéssel.

### B) Sebesség Teszt (Második alkalom)
1.  Fejezd be a kvízt vagy zárd be.
2.  Nyisd meg **újra UGYANAZT** a kvízt.
3.  Most **AZONNAL** indulnia kell, töltés nélkül. Ez jelzi, hogy a cache-ből dolgozik.
4.  Ismételd meg ezt még 3-szor. Mindegyiknek gyorsnak kell lennie.

### C) Perzisztencia Teszt
1.  Nyiss meg egy kvízt.
2.  Ne töltsd ki, hanem lépj ki az alkalmazásból (vagy frissítsd a böngészőt).
3.  Lépj vissza és nyisd meg újra.
4.  Nem a "regenerálás" (lassú) ágnak kell futnia, hanem a gyors (cache) ágnak. (Ellenőrizhető a hálózati forgalmon is).

### D) Eszközváltás (Opcionális)
1.  Nyisd meg mobilon, majd zárd be.
2.  Nyisd meg asztali gépen ugyanazt. Gyorsnak kell lennie, mert a mobilon generált session már ott van a felhőben.
