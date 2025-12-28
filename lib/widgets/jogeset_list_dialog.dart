import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_html/flutter_html.dart';
import '../models/jogeset_models.dart';
import '../services/jogeset_service.dart';
import '../core/firebase_config.dart';

/// Dialog widget, ami megjeleníti egy dokumentum összes jogesetét ExpansionTile-okban.
///
/// A dialog a dokumentum ID alapján betölti az összes jogesetet és megjeleníti őket
/// ExpansionTile-okban. Minden jogeset kinyitható, és tartalmazza:
/// - Eredeti jogszabály szövegét (opcionális, lenyitható)
/// - Tények
/// - Kérdés (világoskék háttérrel)
/// - Megoldás (világoszöld háttérrel)
/// - Törlés gomb (admin esetén)
class JogesetListDialog extends StatefulWidget {
  final String documentId;
  final String? category; // Opcionális kategória szűréshez

  const JogesetListDialog({
    super.key,
    required this.documentId,
    this.category,
  });

  @override
  State<JogesetListDialog> createState() => _JogesetListDialogState();
}

class _JogesetListDialogState extends State<JogesetListDialog> {
  JogesetDocument? _document;
  bool _isLoading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _checkAdminStatus();
    _loadDocument();
  }

  Future<void> _checkAdminStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isAdmin = false);
      return;
    }

    try {
      final userDoc = await FirebaseConfig.firestore
          .collection('users')
          .doc(user.uid)
          .get();

      final userData = userDoc.data() ?? {};
      final userType = (userData['userType'] as String? ?? '').toLowerCase();
      final isAdminEmail = user.email == 'tattila.ninox@gmail.com';
      final isAdminBool = userData['isAdmin'] == true;

      if (mounted) {
        setState(() {
          _isAdmin = userType == 'admin' || isAdminEmail || isAdminBool;
        });
      }
    } catch (e) {
      debugPrint('🔴 Hiba az admin státusz ellenőrzésekor: $e');
      if (mounted) setState(() => _isAdmin = false);
    }
  }

  Future<void> _loadDocument() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final document = await JogesetService.getJogesetDocument(
        widget.documentId,
        isAdmin: _isAdmin,
      );

      if (mounted) {
        setState(() {
          _document = document;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Hiba a dokumentum betöltésekor: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteJogeset(Jogeset jogeset) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Jogeset törlése'),
        content: Text(
            'Biztosan törölni szeretnéd ezt a jogesetet?\n\n${jogeset.cim}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Mégse'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Törlés'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final docRef = FirebaseConfig.firestore
          .collection('jogesetek')
          .doc(widget.documentId);

      final docSnapshot = await docRef.get();
      if (!docSnapshot.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('A dokumentum nem található.')),
          );
        }
        return;
      }

      final data = docSnapshot.data()!;
      final jogesetekList =
          List<Map<String, dynamic>>.from(data['jogesetek'] ?? []);

      // Töröljük a jogesetet az ID alapján
      jogesetekList.removeWhere((j) => (j['id'] as int?) == jogeset.id);

      await docRef.update({'jogesetek': jogesetekList});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Jogeset sikeresen törölve.')),
        );
        _loadDocument(); // Újratöltjük a dokumentumot
      }
    } catch (e) {
      debugPrint('Hiba a jogeset törlésekor: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hiba történt: $e')),
        );
      }
    }
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Dialog(
      insetPadding: EdgeInsets.all(isMobile ? 16 : 32),
      child: Container(
        width: isMobile ? double.infinity : 800,
        height: MediaQuery.of(context).size.height * 0.9,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fejléc
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _document?.displayTitle ??
                        JogesetService.denormalizeParagrafus(widget.documentId),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            // Tartalom
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _document == null || _document!.jogesetek.isEmpty
                      ? const Center(
                          child: Text(
                              'Nincs elérhető jogeset ebben a dokumentumban.'),
                        )
                      : ListView.builder(
                          itemCount: _document!.jogesetek.length,
                          itemBuilder: (context, index) {
                            final jogeset = _document!.jogesetek[index];
                            return _buildJogesetExpansionTile(jogeset);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJogesetExpansionTile(Jogeset jogeset) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).primaryColor,
          child: Text(
            '${jogeset.id}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          jogeset.cim,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Komplexitás: ${jogeset.komplexitas}'),
            Text('Kategória: ${jogeset.category}'),
            if (jogeset.model != null) Text('Modell: ${jogeset.model}'),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Eredeti jogszabály szöveg (opcionális, lenyitható)
                if (jogeset.eredetiJogszabalySzoveg != null &&
                    jogeset.eredetiJogszabalySzoveg!.isNotEmpty) ...[
                  ExpansionTile(
                    title: const Text(
                      'Eredeti jogszabály szöveg',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Html(
                          data:
                              '<div style="text-align: justify;">${_escapeHtml(jogeset.eredetiJogszabalySzoveg!)}</div>',
                          style: {
                            "div": Style(
                              fontSize: FontSize(14),
                              color: const Color(0xFF555555),
                              fontStyle: FontStyle.italic,
                            ),
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                // Fikció
                const Text(
                  'Fikció:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Html(
                  data:
                      '<div style="text-align: justify;">${_escapeHtml(jogeset.tenyek)}</div>',
                  style: {
                    "div": Style(
                      fontSize: FontSize(14),
                      color: const Color(0xFF444444),
                      lineHeight: const LineHeight(1.6),
                    ),
                  },
                ),
                const SizedBox(height: 16),
                // Kérdés (világoskék háttérrel)
                const Text(
                  'Kérdés:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Html(
                    data:
                        '<div style="text-align: justify;">${_escapeHtml(jogeset.kerdes)}</div>',
                    style: {
                      "div": Style(
                        fontSize: FontSize(14),
                        color: const Color(0xFF444444),
                        lineHeight: const LineHeight(1.6),
                      ),
                    },
                  ),
                ),
                const SizedBox(height: 16),
                // Megoldás (világoszöld háttérrel)
                const Text(
                  'Megoldás:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Html(
                    data:
                        '<div style="text-align: justify;">${_escapeHtml(jogeset.megoldas)}</div>',
                    style: {
                      "div": Style(
                        fontSize: FontSize(14),
                        color: const Color(0xFF444444),
                        lineHeight: const LineHeight(1.6),
                      ),
                    },
                  ),
                ),
                // Törlés gomb (admin esetén)
                if (_isAdmin) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => _deleteJogeset(jogeset),
                    icon: const Icon(Icons.delete, color: Colors.red),
                    label: const Text(
                      'Jogeset törlése',
                      style: TextStyle(color: Colors.red),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
