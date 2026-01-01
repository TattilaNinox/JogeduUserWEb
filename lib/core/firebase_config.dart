import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// A Firebase konfigurációért és inicializálásáért felelős osztály.
///
/// Ez az osztály egyetlen statikus metódust tartalmaz, amely az alkalmazás
/// indításakor szükséges a Firebase szolgáltatásokkal való kapcsolat
/// létrehozásához. A konfigurációs adatok (API kulcsok stb.) itt vannak
/// keményen kódolva.
class FirebaseConfig {
  // A fő (alapértelmezett) Firebase alkalmazás
  static FirebaseApp? _defaultApp;

  static Future<void> initialize() async {
    const defaultOptions = FirebaseOptions(
      apiKey: "AIzaSyCWkH2x7ujj3xc8M1fhJAMphWo7pLBhV_k",
      authDomain: "orlomed-f8f9f.firebaseapp.com",
      projectId: "orlomed-f8f9f",
      storageBucket: "orlomed-f8f9f.firebasestorage.app",
      messagingSenderId: "673799768268",
      appId: "1:673799768268:web:2313db56d5226e17c6da69",
    );

    // Alapértelmezett, név nélküli alkalmazás inicializálása
    _defaultApp = await Firebase.initializeApp(
      options: defaultOptions,
    );

    // OPTIMALIZÁLÁS: Firestore cache engedélyezése
    // - persistenceEnabled: offline cache, ismételt betöltések gyorsítása
    // - cacheSizeBytes: UNLIMITED a webes platformon
    // Várható költségcsökkentés: +50% (cache-ből szolgál ki ismételt kéréseket)
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  // Getter a fő (alapértelmezett) Firestore adatbázishoz
  static FirebaseFirestore get firestore {
    return FirebaseFirestore.instance;
  }

  // Getter a nyilvános Firestore adatbázishoz
  static FirebaseFirestore get publicFirestore {
    // A Firestore.instanceFor segítségével hivatkozunk a másik adatbázisra
    // a MEGLÉVŐ alapértelmezett app kontextusában.
    if (_defaultApp == null) {
      throw Exception("Firebase default app not initialized");
    }
    return FirebaseFirestore.instanceFor(
        app: _defaultApp!, databaseId: 'lomedu-publik');
  }
}
