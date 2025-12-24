import 'package:cloud_firestore/cloud_firestore.dart';

class StudyBoardColumn {
  final String id;
  final String title;
  final int order;

  const StudyBoardColumn({
    required this.id,
    required this.title,
    required this.order,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'order': order,
      };

  static StudyBoardColumn fromMap(Map<String, dynamic> map) {
    return StudyBoardColumn(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      order: (map['order'] is num) ? (map['order'] as num).toInt() : 0,
    );
  }
}

class StudyBoard {
  final String id;
  final String ownerUid;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<StudyBoardColumn> columns;

  const StudyBoard({
    required this.id,
    required this.ownerUid,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.columns,
  });

  static DateTime _ts(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static StudyBoard fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final cols = (data['columns'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(StudyBoardColumn.fromMap)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return StudyBoard(
      id: doc.id,
      ownerUid: (data['ownerUid'] ?? '').toString(),
      title: (data['title'] ?? '').toString(),
      createdAt: _ts(data['createdAt']),
      updatedAt: _ts(data['updatedAt']),
      columns: cols,
    );
  }
}

class StudyCard {
  final String id;
  final String title;
  final String? description;
  final String columnId;
  final double order;
  final DateTime createdAt;
  final DateTime updatedAt;

  const StudyCard({
    required this.id,
    required this.title,
    required this.description,
    required this.columnId,
    required this.order,
    required this.createdAt,
    required this.updatedAt,
  });

  static DateTime _ts(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static double _num(Object? v) {
    if (v is num) return v.toDouble();
    return 0;
  }

  static StudyCard fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return StudyCard(
      id: doc.id,
      title: (data['title'] ?? '').toString(),
      description: data['description']?.toString(),
      columnId: (data['columnId'] ?? '').toString(),
      order: _num(data['order']),
      createdAt: _ts(data['createdAt']),
      updatedAt: _ts(data['updatedAt']),
    );
  }
}

class StudyItemRef {
  final String contentType;
  final String contentId;

  const StudyItemRef({required this.contentType, required this.contentId});

  @override
  String toString() => '$contentType:$contentId';
}

class StudyCardItem {
  final String id;
  final StudyItemRef ref;
  final double order;
  final String? titleSnapshot;
  final String? categorySnapshot;

  const StudyCardItem({
    required this.id,
    required this.ref,
    required this.order,
    required this.titleSnapshot,
    required this.categorySnapshot,
  });

  static double _num(Object? v) {
    if (v is num) return v.toDouble();
    return 0;
  }

  static StudyCardItem fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return StudyCardItem(
      id: doc.id,
      ref: StudyItemRef(
        contentType: (data['contentType'] ?? '').toString(),
        contentId: (data['contentId'] ?? '').toString(),
      ),
      order: _num(data['order']),
      titleSnapshot: data['titleSnapshot']?.toString(),
      categorySnapshot: data['categorySnapshot']?.toString(),
    );
  }
}
