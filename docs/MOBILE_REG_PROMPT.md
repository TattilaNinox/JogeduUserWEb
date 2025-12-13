### Feladatprompt – Mobil regisztráció Firestore mentéssel

#### Cél
Sikeres Firebase Auth regisztráció után hozz létre (vagy idempotensen egészíts ki) egy `users/{uid}` dokumentumot a Firestore-ban. A webes admin listázáshoz a `createdAt` mező KÖTELEZŐ.

#### Tárolás
- Gyűjtemény: `users`
- Dokumentum ID: a bejelentkezett felhasználó `uid`

#### Idempotencia
- Ha a dokumentum már létezik, NE írd felül a korábbi értékeket; csak a hiányzókat töltsd fel, és mindig frissítsd az `updatedAt` mezőt.

#### Időbélyegek
- MINDEN dátumhoz `FieldValue.serverTimestamp()`-ot használj (ne kliens-időt), így konzisztens és időzóna-független lesz.

#### Mentendő mezők (név – típus – kötelező – megjegyzés)
- **email** – string – kötelező – Auth e-mail
- **userType** – string – kötelező – alap: `normal` (lehet: `normal|admin|test`)
- **science** – string/null – ajánlott – ha nincs választás: "Alap"
- **subscriptionStatus** – string – kötelező – alap: `free` (lehet: `free|premium`)
- **isSubscriptionActive** – bool – kötelező – alap: `false`
- **subscriptionEndDate** – Timestamp/null – opcionális
- **lastPaymentDate** – Timestamp/null – opcionális
- **freeTrialStartDate** – Timestamp/null – opcionális
- **freeTrialEndDate** – Timestamp/null – opcionális
- **deviceRegistrationDate** – Timestamp/null – opcionális; első eszközregisztráció ideje
- **createdAt** – Timestamp – kötelező – létrehozáskor `FieldValue.serverTimestamp()`
- **updatedAt** – Timestamp – kötelező – MINDEN írásnál `FieldValue.serverTimestamp()`

Megjegyzés: a kétfaktoros hitelesítés adatai NEM itt vannak, hanem `user_2fa/{uid}` alatt.

#### Elfogadási kritériumok
- Regisztráció után a `users/{uid}` dokumentum létezik, `createdAt` és `updatedAt` nem null.
- Alapértékek beállítva: `email`, `userType=normal`, `subscriptionStatus=free`, `isSubscriptionActive=false`.
- Ha nincs választott tudomány, `science="Alap"` értéket kap.
- Ismételt mentés (merge) nem veszít el korábbi adatot, csak frissít és pótol.

#### Példa payload (első létrehozás)
```json
{
  "email": "user@example.com",
  "userType": "normal",
  "science": "Alap",
  "subscriptionStatus": "free",
  "isSubscriptionActive": false,
  "subscriptionEndDate": null,
  "lastPaymentDate": null,
  "freeTrialStartDate": null,
  "freeTrialEndDate": null,
  "deviceRegistrationDate": { "serverTimestamp": true },
  "createdAt": { "serverTimestamp": true },
  "updatedAt": { "serverTimestamp": true }
}
```

#### Flutter (Dart) minta – létrehozás/idempotens frissítés
```dart
final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
  email: email.trim(),
  password: password.trim(),
);
final uid = cred.user!.uid;

final users = FirebaseFirestore.instance.collection('users');
final docRef = users.doc(uid);
final snap = await docRef.get();

// Alapértékek
final base = {
  'email': email.trim(),
  'userType': 'normal',
  'science': (selectedScience ?? 'Alap'),
  'subscriptionStatus': 'free',
  'isSubscriptionActive': false,
  'subscriptionEndDate': null,
  'lastPaymentDate': null,
  'freeTrialStartDate': null,
  'freeTrialEndDate': null,
  'deviceRegistrationDate': FieldValue.serverTimestamp(),
};

if (!snap.exists) {
  await docRef.set({
    ...base,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
} else {
  final data = snap.data()!;
  await docRef.set({
    ...base,
    if (data['createdAt'] == null) 'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}
```

#### Visszamenőleges pótlás (egyszeri futtatás)
```dart
final qs = await FirebaseFirestore.instance.collection('users').get();
for (final d in qs.docs) {
  final data = d.data() as Map<String, dynamic>;
  if (data['createdAt'] == null) {
    await d.reference.update({
      'createdAt': data['updatedAt'] ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
```

#### Biztonsági szabály kompatibilitás
Feltételezés: a felhasználó írhatja a saját dokumentumát.
```
match /users/{userId} {
  allow read, write: if isAdmin() || (request.auth != null && request.auth.uid == userId);
}
```



















