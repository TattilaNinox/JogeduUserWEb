# Feladatleírás: 2-Válaszos Dinamikus Kvíz (``dynamic_quiz_dual``)

Ez a dokumentum **kiegészíti** a meglévő _Dinamikus Kvíz_ (``dynamic_quiz`` – 1 helyes válasz) specifikációt. Itt kizárólag azokat a pontokat részletezzük, **amelyek eltérnek vagy kiegészülnek** az egy helyes válaszos változathoz képest. Minden, ami itt nem szerepel, az megegyezik a korábbi implementációval és UX-sel.

---
## 1. Összefoglaló összehasonlítás
| Tulajdonság | ``dynamic_quiz`` (1 helyes) | ``dynamic_quiz_dual`` (2 helyes) |
|-------------|-----------------------------|-----------------------------------|
| Helyes opciók száma kérdésenként | **1** | **2** |
| Kiválasztható opciók száma | 1 (rádiógomb-viselkedés) | Pontosan 2 (checkbox-viselkedés) |
| Ellenőrzés gomb aktiválása | Azonnal, ha választott | Csak, ha **pontosan 2** opció kijelölve |
| Pontszám növelése | +1, ha a kiválasztott = helyes | +1, ha **mindkét** kijelölt opció helyes |
| Kártyafordítás (indoklás) | Kiválasztott opcióra koppintva | **Mindkét** kijelölt opcióra koppintva |

---
## 2. Adatmodell-változások
```jsonc
// question_banks.questions[*].options elem minta
{
  "text": "N. olfactorius (I)",
  "isCorrect": true,
  "rationale": "Tisztán szagló ideg."
}
```
* Kötelező szabály: **pontosan 2** `isCorrect: true` opció kérdésenként.
* Minden egyéb mező változatlan (``rationale`` továbbra is opcionális).

---
## 3. Mobilos logikai módosítások
1. **Kiválasztás kezelése**
   * ``Set<int> selectedIndices`` – max. 2 elem.
   * Új tap esetén:
     * Ha benne van → töröld.
     * Ha még <2 kiválasztva → add hozzá.
2. **Ellenőrzés**
```dart
if (selectedIndices.length != 2) return; // gomb disabled
correct = options.indexWhere((o) => o.isCorrect);
// Pontszám
if (selectedIndices.containsAll(correctIndices)) score += 1;
```
3. **Kártyafordítás animáció** – ugyanaz a flip mechanika, de csak a kijelölt kártyákra engedélyezett az ellenőrzés után.

---
## 4. Felhasználói élmény (UX-összegzés)
* Felirat a kérdés fölött: _„Jelöld ki a **KÉT** helyes választ!”_
* Checkbox-stílus jelölőnégyzet a kártya bal oldalán.
* Ellenőrzés után:
  * Helyes: zöld háttér, ✔️ ikon.
  * Rossz, de kijelölt: piros háttér, ❌ ikon.
* Koppintás a kiválasztott kártyára → flip, indoklás (`rationale`) jelenik meg.

---
## 5. Hibakezelés – csak az új szituációk
| Eset | Reakció |
|------|---------|
| Kiválasztott opciók száma ≠ 2, de „Ellenőrzés” gomb megnyomása | A gomb disabled, így nem történhet meg. |
| Felhasználó >2 opcióra próbál kattintani | A 3. kattintás nem változtat állapotot. |

---
## 6. Firestore szabályok
Változatlanok a single-answer kvízhez képest. Továbbra is csak **olvasási** jogosultság szükséges a ``question_banks`` kollekcióhoz.

---
## 7. Tesztelési mátrix (összefoglaló)
| Szituáció | Várt eredmény |
|-----------|---------------|
| 2 helyes választ jelöl | +1 pont, zöld hátterek |
| 1 helyes + 1 rossz | 0 pont, zöld + piros háttér |
| 2 rossz | 0 pont, piros háttér mindkettő |
| <2 választás → Ellenőrzés | gomb disabled |
| Ellenőrzés után kártya flip | rationale jelenik meg |

---
## 8. Bevezetés a rendszerbe
1. Admin felületen új menüpont: **„Új 2-válaszos Dinamikus Kvíz”** → útvonal: `/dynamic-quiz-dual/create`.
2. Szerkesztés: `/quiz-dual/edit/:noteId`.
3. Az admin felület már validálja, hogy minden kérdésnél **pontosan 2** helyes válasz legyen – mobilon már tiszta adatot kapunk.

---
### Összefoglalás
A ``dynamic_quiz_dual`` egy **bővített kihívás** a felhasználóknak: egyszerre két helyes opciót kell felismerniük. A mobilos implementáció 90 %-ban megegyezik az egy válaszos változattal – a lényegi eltérések a kiválasztás logikájában, az ellenőrzés feltételeiben és a vizuális visszajelzésben vannak.

A fenti instrukciók alapján a fejlesztő gyorsan integrálhatja az új jegyzettípust a meglévő jegyzet-megjelenítő modulba.
