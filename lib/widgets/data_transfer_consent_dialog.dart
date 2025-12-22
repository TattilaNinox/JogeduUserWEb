import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// SimplePay adattovábbítási nyilatkozat dialog
///
/// Minden előfizetés indítás előtt meg kell jeleníteni.
/// A felhasználónak el kell fogadnia a nyilatkozatot a fizetés indítása előtt.
class DataTransferConsentDialog extends StatefulWidget {
  const DataTransferConsentDialog({super.key});

  /// Megjeleníti a consent dialogot
  ///
  /// Visszatérési érték:
  /// - `true`: a felhasználó elfogadta a nyilatkozatot
  /// - `false`: a felhasználó nem fogadta el vagy bezárta a dialogot
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // csak a gombokkal lehet bezárni
      builder: (context) => const DataTransferConsentDialog(),
    );
    return result ?? false;
  }

  @override
  State<DataTransferConsentDialog> createState() =>
      _DataTransferConsentDialogState();
}

class _DataTransferConsentDialogState extends State<DataTransferConsentDialog> {
  bool _accepted = false;
  bool _withdrawalAccepted = false;

  Future<void> _launchSimplePayUrl() async {
    final uri = Uri.parse('https://simplepay.hu/adatkezelesi-tajekoztatok/');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nem sikerült megnyitni a linket'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reszponzív méretek
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;
    final dialogHeight = isMobile
        ? screenSize.height *
            0.4 // Mobil: 40% (kisebb, hogy kiférjen a 2 checkbox)
        : (screenSize.height * 0.5).clamp(200.0, 450.0);
    final fontSize = isMobile ? 11.0 : 13.0;
    final titleSize = isMobile ? 13.0 : 15.0;

    return AlertDialog(
      title: Text(
        'Adattovábbítási nyilatkozat',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: isMobile ? 16 : 18,
        ),
      ),
      contentPadding: EdgeInsets.all(isMobile ? 12 : 24),
      content: SizedBox(
        width: isMobile ? screenSize.width * 0.9 : double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A fizetés folytatásához el kell fogadnia az adattovábbítási nyilatkozatot:',
              style: TextStyle(fontSize: fontSize, color: Colors.black87),
            ),
            SizedBox(height: isMobile ? 8 : 12),
            // Scrollozható tartalom - RESZPONZÍV magasság
            Container(
              height: dialogHeight,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isMobile ? 8 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHungarianConsent(isMobile, fontSize, titleSize),
                    SizedBox(height: isMobile ? 16 : 32),
                    const Divider(),
                    SizedBox(height: isMobile ? 16 : 32),
                    _buildEnglishConsent(isMobile, fontSize, titleSize),
                  ],
                ),
              ),
            ),
            SizedBox(height: isMobile ? 8 : 16),
            // Checkbox 1 - Adattovábbítás
            CheckboxListTile(
              value: _accepted,
              onChanged: (value) {
                setState(() {
                  _accepted = value ?? false;
                });
              },
              title: Text(
                'Elfogadom az adattovábbítási nyilatkozatot',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: isMobile ? 12 : 14,
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            // Checkbox 2 - Elállási jog
            CheckboxListTile(
              value: _withdrawalAccepted,
              onChanged: (value) {
                setState(() {
                  _withdrawalAccepted = value ?? false;
                });
              },
              title: Text(
                'Kérem a szolgáltatás azonnali megkezdését, és tudomásul veszem, hogy ezzel elveszítem a 14 napos elállási jogomat.',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: isMobile ? 12 : 14,
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Mégse', style: TextStyle(fontSize: isMobile ? 13 : 14)),
        ),
        ElevatedButton(
          onPressed: (_accepted && _withdrawalAccepted)
              ? () => Navigator.of(context).pop(true)
              : null,
          child:
              Text('Elfogadom', style: TextStyle(fontSize: isMobile ? 13 : 14)),
        ),
      ],
    );
  }

  Widget _buildHungarianConsent(
      bool isMobile, double fontSize, double titleSize) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Magyar nyelvű nyilatkozat',
          style: TextStyle(
            fontSize: titleSize + 1,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        SizedBox(height: isMobile ? 8 : 16),
        Text(
          'Adattovábbítási nyilatkozat',
          style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: isMobile ? 6 : 12),
        Text(
          'Tudomásul veszem, hogy a(z) Oak Quality Kft. 2113 Erdőkertes, Bocskai utca 13. adatkezelő által a(z) Lomedu.hu felhasználói adatbázisában tárolt alábbi személyes adataim átadásra kerülnek a SimplePay Zrt., mint adatfeldolgozó részére.',
          style: TextStyle(fontSize: fontSize),
        ),
        SizedBox(height: isMobile ? 8 : 12),
        Text(
          'Az adatkezelő által továbbított adatok köre az alábbi:',
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: isMobile ? 4 : 8),
        Text(
          '• Email cím',
          style: TextStyle(fontSize: fontSize),
        ),
        Text(
          '• Megrendelési azonosító',
          style: TextStyle(fontSize: fontSize),
        ),
        Text(
          '• Vásárolt termék/szolgáltatás neve',
          style: TextStyle(fontSize: fontSize),
        ),
        Text(
          '• Vásárolt termék/szolgáltatás leírása',
          style: TextStyle(fontSize: fontSize),
        ),
        Text(
          '• Vásárolt termék/szolgáltatás ára',
          style: TextStyle(fontSize: fontSize),
        ),
        Text(
          '• Vásárolt termék/szolgáltatás mennyisége',
          style: TextStyle(fontSize: fontSize),
        ),
        SizedBox(height: isMobile ? 8 : 12),
        Text(
          'Az adatfeldolgozó által végzett adatfeldolgozási tevékenység jellege és célja a SimplePay Adatkezelési tájékoztatóban, az alábbi linken tekinthető meg:',
          style: TextStyle(fontSize: fontSize),
        ),
        SizedBox(height: isMobile ? 6 : 8),
        _buildClickableLink(fontSize),
        SizedBox(height: isMobile ? 8 : 16),
        Text(
          'A Szolgáltató azonosító adatai',
          style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: isMobile ? 4 : 8),
        _buildDataRow('Név:', 'Oak Quality Kft.', isMobile, fontSize),
        _buildDataRow('Székhely:', '2113 Erdőkertes, Bocskai utca 13.',
            isMobile, fontSize),
        _buildDataRow('Cégjegyzékszám:', '13 09 084075', isMobile, fontSize),
        _buildDataRow('Adószám:', '11803010-2-13', isMobile, fontSize),
        _buildDataRow('E-mail:', 'support@lomedu.hu', isMobile, fontSize),
        SizedBox(height: isMobile ? 8 : 16),
        Text(
          '7. Elállási jog és annak elvesztése',
          style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: isMobile ? 6 : 12),
        Text(
          '7.1. A 14 napos elállási jog alapszabálya',
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
        ),
        Text(
          'A fogyasztót a 45/2014. (II. 26.) Korm. rendelet 20. §-a alapján főszabály szerint megilletné a 14 napos indokolás nélküli elállási jog.',
          style: TextStyle(fontSize: fontSize),
        ),
        SizedBox(height: isMobile ? 4 : 8),
        Text(
          '7.2. Kivétel: Az elállási jog elvesztése',
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
        ),
        Text(
          'A Korm. rendelet 29. § (1) bekezdés m) pontja alapján a fogyasztó nem gyakorolhatja elállási jogát a nem tárgyi adathordozón nyújtott digitális adattartalom (jelen Webalkalmazás) tekintetében, ha a vállalkozás a fogyasztó kifejezett, előzetes beleegyezésével kezdte meg a teljesítést, és a fogyasztó e beleegyezésével egyidejűleg nyilatkozott annak tudomásulvételéről, hogy a teljesítés megkezdését követően elveszíti elállási jogát.',
          style: TextStyle(fontSize: fontSize),
        ),
        SizedBox(height: isMobile ? 4 : 8),
        Text(
          'A Felhasználó a fizetési folyamat során a jelölőnégyzet bepipálásával kifejezetten kéri a szolgáltatás azonnali megkezdését, és tudomásul veszi, hogy ezzel a sikeres fizetés pillanatától kezdve elveszíti a 14 napos elállási (pénzvisszafizetési) jogát.',
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildEnglishConsent(
      bool isMobile, double fontSize, double titleSize) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'English Declaration',
          style: TextStyle(
            fontSize: titleSize + 1,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        SizedBox(height: isMobile ? 8 : 16),
        Text(
          'Data Transfer Declaration',
          style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: isMobile ? 6 : 8),
        Text(
          'I acknowledge that the following personal data stored in the Lomedu.hu user database by Oak Quality Kft. (2113 Erdőkertes, Bocskai utca 13.) as data controller will be transferred to SimplePay Plc. as data processor.',
          style: TextStyle(fontSize: fontSize),
        ),
        SizedBox(height: isMobile ? 8 : 12),
        Text(
          'Data transferred by the merchant:',
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: isMobile ? 4 : 8),
        Text(
          '• Email address',
          style: TextStyle(fontSize: fontSize),
        ),
        Text(
          '• Order reference number',
          style: TextStyle(fontSize: fontSize),
        ),
        Text(
          '• Name of purchased product/service',
          style: TextStyle(fontSize: fontSize),
        ),
        Text(
          '• Description of purchased product/service',
          style: TextStyle(fontSize: fontSize),
        ),
        Text(
          '• Price of purchased product/service',
          style: TextStyle(fontSize: fontSize),
        ),
        Text(
          '• Quantity of purchased product/service',
          style: TextStyle(fontSize: fontSize),
        ),
        SizedBox(height: isMobile ? 8 : 12),
        Text(
          'The nature and purpose of data processing activities performed by the data processor can be viewed in the SimplePay Data Processing Information at the following link:',
          style: TextStyle(fontSize: fontSize),
        ),
        SizedBox(height: isMobile ? 6 : 8),
        _buildClickableLink(fontSize),
        SizedBox(height: isMobile ? 8 : 16),
        Text(
          'Service Provider Information',
          style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: isMobile ? 4 : 8),
        _buildDataRow('Name:', 'Oak Quality Kft.', isMobile, fontSize),
        _buildDataRow('Headquarters:', '2113 Erdőkertes, Bocskai u. 13.',
            isMobile, fontSize),
        _buildDataRow('Registration:', '13 09 084075', isMobile, fontSize),
        _buildDataRow('Tax number:', '11803010-2-13', isMobile, fontSize),
        _buildDataRow('Email:', 'support@lomedu.hu', isMobile, fontSize),
        SizedBox(height: isMobile ? 8 : 16),
        Text(
          '7. Right of withdrawal and its loss',
          style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: isMobile ? 6 : 12),
        Text(
          '7.1. General rule of the 14-day right of withdrawal',
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
        ),
        Text(
          'Based on Section 20 of Gov. Decree 45/2014 (II. 26.), the consumer is generally entitled to a 14-day right of withdrawal without justification.',
          style: TextStyle(fontSize: fontSize),
        ),
        SizedBox(height: isMobile ? 4 : 8),
        Text(
          '7.2. Exception: Loss of right of withdrawal',
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
        ),
        Text(
          'Based on Section 29 (1) m) of the Gov. Decree, the consumer may not exercise their right of withdrawal with respect to digital content provided on a non-tangible medium (this Web Application) if the business has commenced performance with the consumer\'s express, prior consent, and the consumer has acknowledged, simultaneously with this consent, that they will lose their right of withdrawal after the commencement of performance.',
          style: TextStyle(fontSize: fontSize),
        ),
        SizedBox(height: isMobile ? 4 : 8),
        Text(
          'By checking the checkbox during the payment process, the User expressly requests the immediate commencement of the service and acknowledges that they lose their 14-day right of withdrawal (refund) from the moment of successful payment.',
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildClickableLink(double fontSize) {
    return InkWell(
      onTap: _launchSimplePayUrl,
      child: Text(
        'https://simplepay.hu/adatkezelesi-tajekoztatok/',
        style: TextStyle(
          fontSize: fontSize - 1,
          color: Colors.blue,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  Widget _buildDataRow(
      String label, String value, bool isMobile, double fontSize) {
    // Mobilon column layout, asztali nézetben row
    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(fontSize: fontSize),
            ),
          ],
        ),
      );
    }

    // Asztali nézet - row layout
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: fontSize),
            ),
          ),
        ],
      ),
    );
  }
}
