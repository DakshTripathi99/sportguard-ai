import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'violation_detail_screen.dart';

class AssetViolationsScreen extends StatelessWidget {
  final String assetId;
  final String fileName;

  const AssetViolationsScreen({
    super.key,
    required this.assetId,
    required this.fileName,
  });

  Color _severityColor(String? severity, double score) {
    final s = severity?.toLowerCase() ?? '';
    if (s == 'high' || score >= 0.90) return Colors.red;
    if (s == 'medium' || score >= 0.70) return Colors.orange;
    return Colors.blue;
  }

  String _severityText(String? severity, double score) {
    if (severity != null && severity.isNotEmpty) return severity.toUpperCase();
    if (score >= 0.90) return 'HIGH';
    if (score >= 0.70) return 'MEDIUM';
    return 'LOW';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EEC9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF35858E),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Violations',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              fileName,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('violations')
            .where('assetId', isEqualTo: assetId)
            .orderBy('detectedAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF35858E)),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }

          final violations = snapshot.data?.docs ?? [];

          if (violations.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_user, color: Color(0xFF35858E), size: 80),
                  SizedBox(height: 16),
                  Text(
                    'No violations found for this asset!',
                    style: TextStyle(
                      color: Color(0xFF35858E),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // summary bar
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF35858E), Color(0xFF7DA78C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${violations.length} violation${violations.length == 1 ? '' : 's'} detected',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: violations.length,
                  itemBuilder: (ctx, i) {
                    final v = violations[i].data() as Map<String, dynamic>;
                    final docId = violations[i].id;
                    final score =
                        (v['similarityScore'] as num?)?.toDouble() ?? 0.0;
                    final scorePercent = (score * 100).round();
                    final color = _severityColor(v['severity'], score);
                    final detectedDate = v['detectedAt'] is Timestamp
                        ? (v['detectedAt'] as Timestamp)
                              .toDate()
                              .toString()
                              .split('.')[0]
                        : 'N/A';

                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ViolationDetailScreen(
                            violationId: docId,
                            data: v,
                          ),
                        ),
                      ),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border(
                            left: BorderSide(color: color, width: 5),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            v['matchDomain'] ??
                                                'Unknown domain',
                                            style: const TextStyle(
                                              color: Color(0xFF1E2A3A),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: Text(
                                            _severityText(v['severity'], score),
                                            style: TextStyle(
                                              color: color,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Detected: $detectedDate',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          'Similarity: $scorePercent%',
                                          style: TextStyle(
                                            color: scorePercent > 80
                                                ? Colors.red
                                                : Colors.orange,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: v['status'] == 'resolved'
                                                ? Colors.green.withValues(
                                                    alpha: 0.1,
                                                  )
                                                : Colors.orange.withValues(
                                                    alpha: 0.1,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Text(
                                            v['status'] ?? 'pending',
                                            style: TextStyle(
                                              color: v['status'] == 'resolved'
                                                  ? Colors.green
                                                  : Colors.orange,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.chevron_right,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
