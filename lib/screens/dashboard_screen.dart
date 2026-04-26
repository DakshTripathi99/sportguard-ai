import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_ap/screens/violation_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Holds the assetIds belonging to the current user
  List<String> _userAssetIds = [];
  bool _loadingAssets = true;

  @override
  void initState() {
    super.initState();
    _fetchUserAssetIds();
  }

  /// Step 1: get all assetIds the user owns
  Future<void> _fetchUserAssetIds() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loadingAssets = false);
      return;
    }

    final snapshot = await FirebaseFirestore.instance
        .collection('assets')
        .where('ownerId', isEqualTo: user.uid)
        .get();

    setState(() {
      _userAssetIds = snapshot.docs
          .map((doc) => doc.data()['assetId'] as String? ?? doc.id)
          .toList();
      _loadingAssets = false;
    });
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
    if (_loadingAssets) {
      return const Scaffold(
        backgroundColor: Color(0xFFE6EEC9),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF35858E)),
        ),
      );
    }

    // User has no uploaded assets yet
    if (_userAssetIds.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFFE6EEC9),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shield_outlined, color: Color(0xFF35858E), size: 80),
              SizedBox(height: 16),
              Text(
                'No assets uploaded yet.',
                style: TextStyle(
                  color: Color(0xFF35858E),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFE6EEC9),
      body: StreamBuilder<QuerySnapshot>(
        // Step 2: only violations whose assetId matches one of the user's assets
        // Firestore whereIn supports up to 30 values
        stream: FirebaseFirestore.instance
            .collection('violations')
            .where('assetId', whereIn: _userAssetIds)
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
                  Icon(
                    Icons.shield_outlined,
                    color: Color(0xFF35858E),
                    size: 80,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No violations detected!',
                    style: TextStyle(
                      color: Color(0xFF35858E),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              _buildStatusBar(violations.length),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: violations.length,
                  itemBuilder: (ctx, i) {
                    final v = violations[i].data() as Map<String, dynamic>;
                    final docId = violations[i].id;
                    final score = ((v['similarityScore'] ?? 0) * 100).round();

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
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          border: Border(
                            left: BorderSide(
                              color: _severityColor(
                                v['severity'],
                                v['similarityScore']?.toDouble() ?? 0.0,
                              ),
                              width: 6,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    v['matchDomain'] ?? 'Unknown domain',
                                    style: const TextStyle(
                                      color: Color(0xFF1E2A3A),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _severityColor(
                                      v['severity'],
                                      v['similarityScore']?.toDouble() ?? 0.0,
                                    ).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    _getSeverityText(
                                      v['severity'],
                                      v['similarityScore']?.toDouble() ?? 0.0,
                                    ),
                                    style: TextStyle(
                                      color: _severityColor(
                                        v['severity'],
                                        v['similarityScore']?.toDouble() ?? 0.0,
                                      ),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Detected on: ${v['detectedAt']?.toDate()?.toString().split('.')[0] ?? 'N/A'}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Similarity: $score%',
                                  style: TextStyle(
                                    color: score > 80
                                        ? Colors.red
                                        : Colors.orange,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  v['status'] ?? 'pending',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
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

  Widget _buildStatusBar(int count) {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF35858E), Color(0xFF7DA78C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF35858E).withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.security, color: Colors.white, size: 32),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Active Monitoring',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              Text(
                '$count potential violations flagged',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
