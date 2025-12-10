import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/web_payment_service.dart';

/// Webes fizetési előzmények widget
///
/// Megjeleníti a felhasználó fizetési előzményeit real-time (StreamBuilder).
class WebPaymentHistory extends StatelessWidget {
  final Map<String, dynamic>? userData;
  final VoidCallback? onRefresh;

  const WebPaymentHistory({
    super.key,
    required this.userData,
    this.onRefresh,
  });

  // Import hozzáadása szükséges
  // import 'package:cloud_firestore/cloud_firestore.dart';

  @override
  Widget build(BuildContext context) {
    final userId = userData?['uid'] ?? userData?['id'];

    if (userId == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Center(
          child: Text('Felhasználói azonosító nem elérhető'),
        ),
      );
    }

    // StreamBuilder - automatikus frissítés!
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('web_payments')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              const Row(
                children: [
                  Icon(
                    Icons.history,
                    size: 24,
                    color: Color(0xFF1E3A8A),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Fizetési előzmények',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Content
              if (snapshot.connectionState == ConnectionState.waiting)
                _buildLoadingState()
              else if (snapshot.hasError)
                _buildErrorState(snapshot.error.toString())
              else if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                _buildEmptyState()
              else
                _buildPaymentsList(_convertToPaymentItems(snapshot.data!.docs)),
            ],
          ),
        );
      },
    );
  }

  List<PaymentHistoryItem> _convertToPaymentItems(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return docs.map((doc) {
      final data = doc.data();
      return PaymentHistoryItem(
        id: doc.id,
        orderRef: data['orderRef'] as String? ?? '',
        amount: data['amount'] as int? ?? 0,
        status: (data['status'] as String? ?? 'unknown').toLowerCase(),
        createdAt:
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        planId: data['planId'] as String? ?? '',
        transactionId: data['transactionId']?.toString(),
        simplePayTransactionId: data['simplePayTransactionId']?.toString(),
      );
    }).toList();
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Fizetési előzmények betöltése...'),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Colors.red[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Hiba történt az adatok betöltése során',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: TextStyle(
              fontSize: 14,
              color: Colors.red[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        children: [
          Icon(
            Icons.receipt_long,
            size: 48,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Még nincsenek fizetési előzmények',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Az első vásárlás után itt jelennek meg a részletek',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentsList(List<PaymentHistoryItem> payments) {
    return Column(
      children: [
        // Desktop table view
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth > 768) {
              return _buildDesktopTable(payments);
            } else {
              return _buildMobileList(payments);
            }
          },
        ),

        const SizedBox(height: 16),

        // Footer
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Text(
            '${payments.length} db megrendelés található',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopTable(List<PaymentHistoryItem> payments) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[200]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'Dátum',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Leírás',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Összeg',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'SimplePay ID',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Státusz',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Rows
          ...payments.map((payment) => _buildTableRow(payment)),
        ],
      ),
    );
  }

  Widget _buildTableRow(PaymentHistoryItem payment) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              _formatDate(payment.createdAt),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _getPlanName(payment.planId),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              payment.formattedAmount,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              payment.simplePayTransactionId ?? '-',
              style: TextStyle(
                fontSize: 14,
                color: payment.simplePayTransactionId != null
                    ? Colors.grey[800]
                    : Colors.grey[400],
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: _buildStatusChip(payment.status),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileList(List<PaymentHistoryItem> payments) {
    return Column(
      children: payments.map((payment) => _buildMobileCard(payment)).toList(),
    );
  }

  Widget _buildMobileCard(PaymentHistoryItem payment) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[200]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _getPlanName(payment.planId),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              _buildStatusChip(payment.status),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDate(payment.createdAt),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              Text(
                payment.formattedAmount,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (payment.simplePayTransactionId != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Text(
                    'SimplePay ID: ',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    payment.simplePayTransactionId!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[800],
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color backgroundColor;
    Color textColor;
    String text;

    switch (status) {
      case 'completed':
        backgroundColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        text = 'Sikeres';
        break;
      case 'pending':
        backgroundColor = Colors.yellow[100]!;
        textColor = Colors.yellow[800]!;
        text = 'Folyamatban';
        break;
      case 'failed':
        backgroundColor = Colors.red[100]!;
        textColor = Colors.red[800]!;
        text = 'Sikertelen';
        break;
      case 'cancelled':
        backgroundColor = Colors.grey[100]!;
        textColor = Colors.grey[800]!;
        text = 'Lemondva';
        break;
      default:
        backgroundColor = Colors.grey[100]!;
        textColor = Colors.grey[800]!;
        text = 'Ismeretlen';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return DateFormat('yyyy. MMMM dd. HH:mm', 'hu').format(date);
  }

  String _getPlanName(String planId) {
    switch (planId) {
      case 'monthly_premium_prepaid':
        return '30 napos előfizetés';
      case 'monthly_web':
        return '30 napos előfizetés';
      case 'yearly_web':
        return 'Éves előfizetés';
      default:
        return planId;
    }
  }
}
