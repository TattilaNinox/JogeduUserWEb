import 'package:cloud_firestore/cloud_firestore.dart';

/// Egy jogeset adatait reprezentáló modell osztály.
///
/// A jogeset egy jogi esetet tartalmaz tényállással, kérdéssel és megoldással.
/// A jogesetek egy dokumentumban (paragrafusban) vannak tárolva tömbként.
class Jogeset {
  final int id;
  final String title;
  final String cim;
  final String tenyek;
  final String kerdes;
  final String alkalmazandoJogszabaly;
  final String megoldas;
  final String komplexitas; // "egyszerű" | "közepes" | "komplex"
  final String category;
  final List<String> tags;
  final String status; // "Draft" | "Published" | "Archived"
  final bool isFree;
  final DateTime generaltDatum;
  final String? science;
  final String? model;
  final String? eredetiJogszabalySzoveg;

  const Jogeset({
    required this.id,
    required this.title,
    required this.cim,
    required this.tenyek,
    required this.kerdes,
    required this.alkalmazandoJogszabaly,
    required this.megoldas,
    required this.komplexitas,
    required this.category,
    required this.tags,
    required this.status,
    required this.isFree,
    required this.generaltDatum,
    this.science,
    this.model,
    this.eredetiJogszabalySzoveg,
  });

  /// Factory konstruktor Firestore dokumentumból való létrehozáshoz
  factory Jogeset.fromMap(Map<String, dynamic> map) {
    return Jogeset(
      id: map['id'] as int? ?? 0,
      title: map['title'] as String? ?? '',
      cim: map['cim'] as String? ?? '',
      tenyek: map['tenyek'] as String? ?? '',
      kerdes: map['kerdes'] as String? ?? '',
      alkalmazandoJogszabaly: map['alkalmazando_jogszabaly'] as String? ?? '',
      megoldas: map['megoldas'] as String? ?? '',
      komplexitas: map['komplexitas'] as String? ?? 'közepes',
      category: map['category'] as String? ?? '',
      tags: map['tags'] != null ? List<String>.from(map['tags'] as List) : [],
      status: map['status'] as String? ?? 'Draft',
      isFree: map['isFree'] as bool? ?? false,
      generaltDatum: map['generalt_datum'] != null
          ? (map['generalt_datum'] as Timestamp).toDate()
          : DateTime.now(),
      science: map['science'] as String?,
      model: map['model'] as String?,
      eredetiJogszabalySzoveg: map['eredeti_jogszabaly_szoveg'] as String?,
    );
  }

  /// Konvertálás Map-pé Firestore-ba való mentéshez
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'cim': cim,
      'tenyek': tenyek,
      'kerdes': kerdes,
      'alkalmazando_jogszabaly': alkalmazandoJogszabaly,
      'megoldas': megoldas,
      'komplexitas': komplexitas,
      'category': category,
      'tags': tags,
      'status': status,
      'isFree': isFree,
      'generalt_datum': Timestamp.fromDate(generaltDatum),
      if (science != null) 'science': science,
      if (model != null) 'model': model,
      if (eredetiJogszabalySzoveg != null)
        'eredeti_jogszabaly_szoveg': eredetiJogszabalySzoveg,
    };
  }

  /// Komplexitás szín lekérése
  /// - "egyszerű": zöld
  /// - "közepes": narancs
  /// - "komplex": piros
  String get komplexitasColor {
    switch (komplexitas.toLowerCase()) {
      case 'egyszerű':
        return '#4CAF50'; // zöld
      case 'közepes':
        return '#FF9800'; // narancs
      case 'komplex':
        return '#F44336'; // piros
      default:
        return '#FF9800'; // alapértelmezett: narancs
    }
  }
}

/// Egy dokumentum (paragrafus) összes jogesetét tartalmazó modell osztály.
///
/// A Firestore-ban egy dokumentum ID egy normalizált paragrafus szám (pl. "6_519"),
/// és a dokumentum tartalmazza az összes jogesetet egy tömbben.
class JogesetDocument {
  final String documentId;
  final List<Jogeset> jogesetek;

  const JogesetDocument({
    required this.documentId,
    required this.jogesetek,
  });

  /// Factory konstruktor Firestore dokumentumból való létrehozáshoz
  factory JogesetDocument.fromMap(Map<String, dynamic> map, String documentId) {
    final jogesetekList = map['jogesetek'] as List<dynamic>? ?? [];
    final jogesetek = jogesetekList
        .map((item) => Jogeset.fromMap(item as Map<String, dynamic>))
        .toList();

    return JogesetDocument(
      documentId: documentId,
      jogesetek: jogesetek,
    );
  }

  /// Konvertálás Map-pé Firestore-ba való mentéshez
  Map<String, dynamic> toMap() {
    return {
      'jogesetek': jogesetek.map((jogeset) => jogeset.toMap()).toList(),
    };
  }

  /// Paragrafus szám visszaalakítása dokumentum ID-ból
  /// Példa: "6_519" -> "6:519. §"
  String get paragrafusDisplay {
    final normalized = documentId.replaceAll('_', ':');
    return '$normalized. §';
  }
}
