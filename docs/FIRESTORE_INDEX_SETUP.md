# Firestore Index Setup for Pagination (ABC Sorrend)

## Indexek hozzáadása manuálisan

Menj a Firebase Console-ra és add hozzá ezeket az indexeket:

**Firebase Console URL:** https://console.firebase.google.com/project/YOUR_PROJECT_ID/firestore/indexes

---

## 1. Notes Collection Indexek

### Index 1: Basic Pagination (ABC sorrend)
- **Collection:** `notes`
- **Fields:**
  1. `science` - Ascending
  2. `status` - Ascending
  3. `title` - **Ascending** (ABC sorrend)
- **Query scope:** Collection

### Index 2: Category Filter + Pagination (ABC sorrend)
- **Collection:** `notes`
- **Fields:**
  1. `science` - Ascending
  2. `status` - Ascending
  3. `category` - Ascending
  4. `title` - **Ascending** (ABC sorrend)
- **Query scope:** Collection

### Index 3: Tag Filter + Pagination
- **Collection:** `notes`
- **Fields:**
  1. `science` - Ascending
  2. `status` - Ascending
  3. `tags` - **Array-contains**
  4. `modified` - **Descending**
- **Query scope:** Collection

### Index 4: Type Filter + Pagination
- **Collection:** `notes`
- **Fields:**
  1. `science` - Ascending
  2. `status` - Ascending
  3. `type` - Ascending
  4. `modified` - **Descending**
- **Query scope:** Collection

---

## 2. Memoriapalota_allomasok Collection Indexek

### Index 5: Basic Pagination
- **Collection:** `memoriapalota_allomasok`
- **Fields:**
  1. `science` - Ascending
  2. `status` - Ascending
  3. `modified` - **Descending**
- **Query scope:** Collection

### Index 6: Category Filter + Pagination
- **Collection:** `memoriapalota_allomasok`
- **Fields:**
  1. `science` - Ascending
  2. `status` - Ascending
  3. `category` - Ascending
  4. `modified` - **Descending**
- **Query scope:** Collection

### Index 7: Tag Filter + Pagination
- **Collection:** `memoriapalota_allomasok`
- **Fields:**
  1. `science` - Ascending
  2. `status` - Ascending
  3. `tags` - **Array-contains**
  4. `modified` - **Descending**
- **Query scope:** Collection

---

## 3. Dialogus_fajlok Collection Indexek

### Index 8: Basic Pagination
- **Collection:** `dialogus_fajlok`
- **Fields:**
  1. `science` - Ascending
  2. `status` - Ascending
  3. `modified` - **Descending**
- **Query scope:** Collection

### Index 9: Tag Filter + Pagination
- **Collection:** `dialogus_fajlok`
- **Fields:**
  1. `science` - Ascending
  2. `status` - Ascending
  3. `tags` - **Array-contains**
  4. `modified` - **Descending**
- **Query scope:** Collection

---

## Hogyan add hozzá az indexeket?

### Módszer 1: Firebase Console (Ajánlott)

1. Menj a Firebase Console-ra: https://console.firebase.google.com
2. Válaszd ki a projektet
3. Firestore Database → Indexes tab
4. Kattints a **"Create Index"** gombra
5. Add meg a fenti adatokat minden indexhez
6. Várj 2-5 percet amíg az index létrejön (státusz: "Building" → "Enabled")

### Módszer 2: Firebase CLI (Automatikus)

Ha van Firebase CLI telepítve:

```bash
firebase deploy --only firestore:indexes
```

Ez a `firestore.indexes.json` fájlt használja (ha létezik a projekt gyökerében).

---

## Miután az indexek létrejöttek

1. **Frissítsd a kódot** hogy használja az `orderBy`-t:

```dart
// note_card_grid.dart - 3 helyen módosítsd:

// Notes query
query = query.orderBy('modified', descending: true).limit(_currentLimit);

// Memoriapalota_allomasok query
allomasQuery = allomasQuery.orderBy('modified', descending: true).limit(_currentLimit);

// Dialogus_fajlok query
dialogusQuery = dialogusQuery.orderBy('modified', descending: true).limit(_currentLimit);
```

2. **Hot reload** (r) vagy **Hot restart** (R) az alkalmazásban

3. **Teszteld** hogy a jegyzetek időrendi sorrendben jelennek meg (legújabb először)

---

## Ellenőrzés

Az indexek létrejöttét ellenőrizheted:
- Firebase Console → Firestore → Indexes tab
- Státusz: **"Enabled"** (zöld pipa)
- Ha "Building" látszik, várj még 2-5 percet

---

## Miért jobb ez?

**Előtte (orderBy nélkül):**
- Jegyzetek random sorrendben (document ID szerint)
- Nehéz megtalálni a legújabb tartalmakat

**Utána (orderBy-val):**
- Jegyzetek időrendi sorrendben (legújabb először)
- Könnyebb navigáció
- Jobb UX

---

## Költség

Az indexek **INGYENESEK**! Nem számítanak bele a Firestore költségekbe.
Csak a lekérdezések (reads) kerülnek pénzbe, az indexek nem.
