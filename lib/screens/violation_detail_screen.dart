import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ViolationDetailScreen extends StatelessWidget {
  final String violationId;
  final Map<String, dynamic> data;

  const ViolationDetailScreen({
    super.key,
    required this.violationId,
    required this.data,
  });

  Future<void> _resolveViolation(BuildContext context) async {
    try {
      await FirebaseFirestore.instance
          .collection('violations')
          .doc(violationId)
          .update({
            'status': 'resolved',
            'resolvedAt': FieldValue.serverTimestamp(),
          });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Violation marked as resolved.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Color _severityColor(String? severity, double similarityScore) {
    String s = severity?.toLowerCase() ?? '';
    if (s.isEmpty) {
      if (similarityScore >= 0.90)
        s = 'high';
      else if (similarityScore >= 0.70)
        s = 'medium';
      else
        s = 'low';
    }
    switch (s) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _getSeverityText(String? severity, double similarityScore) {
    if (severity != null && severity.isNotEmpty) return severity.toUpperCase();
    if (similarityScore >= 0.90) return 'HIGH';
    if (similarityScore >= 0.70) return 'MEDIUM';
    return 'LOW';
  }

  @override
  Widget build(BuildContext context) {
    // Safe double parsing
    final similarityScore =
        (data['similarityScore'] as num?)?.toDouble() ?? 0.0;
    final score = (similarityScore * 100).round();

    // Safe timestamp parsing
    final timestamp = data['detectedAt'] is Timestamp
        ? (data['detectedAt'] as Timestamp).toDate().toString().split('.')[0]
        : 'Unknown time';

    // Safe match URL
    final matchUrl = data['matchUrl'] as String? ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFE6EEC9),
      appBar: AppBar(
        title: const Text(
          'Violation Details',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF35858E),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FDE6),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      data['matchDomain'] ?? 'No Domain Found',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF1E2A3A),
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '$score% Similarity Match',
                      style: const TextStyle(
                        color: Color(0xFF35858E),
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            _buildDetailRow('Reason', data['reason'] ?? 'N/A'),
            _buildDetailRow(
              'Severity',
              _getSeverityText(data['severity'], similarityScore),
              textColor: _severityColor(data['severity'], similarityScore),
            ),
            _buildDetailRow('Detected At', timestamp),
            if (matchUrl.isNotEmpty) _buildDetailRow('Match URL', matchUrl),

            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _resolveViolation(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF35858E),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Mark as Resolved',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? textColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF35858E),
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: textColor ?? Colors.black,
              fontSize: 16,
              height: 1.5,
              fontWeight: textColor != null
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
          const Divider(color: Colors.black12),
        ],
      ),
    );
  }
}
