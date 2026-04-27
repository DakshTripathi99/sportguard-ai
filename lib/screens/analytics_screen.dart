import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  bool _loading = true;
  String? _error;

  // stats
  int _totalViolations = 0;
  int _resolvedViolations = 0;
  int _assetsProtected = 0;
  int _highSeverity = 0;

  // chart: index 0 = 6 days ago ... index 6 = today
  final List<double> _weeklyData = List.filled(7, 0);
  final List<String> _weekLabels = [];

  @override
  void initState() {
    super.initState();
    _buildWeekLabels();
    _loadAnalytics();
  }

  void _buildWeekLabels() {
    final now = DateTime.now();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    for (int i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      _weekLabels.add(days[d.weekday - 1]);
    }
  }

  Future<void> _loadAnalytics() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _loading = false;
          _error = 'Not logged in.';
        });
        return;
      }

      // Step 1: get user's asset IDs
      final assetsSnapshot = await FirebaseFirestore.instance
          .collection('assets')
          .where('orgId', isEqualTo: user.uid)
          .get();

      final assetIds = assetsSnapshot.docs
          .map((d) => d.data()['assetId'] as String? ?? d.id)
          .toList();

      _assetsProtected = assetIds.length;

      if (assetIds.isEmpty) {
        setState(() {
          _loading = false;
          _totalViolations = 0;
          _resolvedViolations = 0;
          _highSeverity = 0;
        });
        return;
      }

      // Step 2: fetch all violations for this user's assets
      // Firestore whereIn supports max 30 — chunk if needed
      final List<QueryDocumentSnapshot> allViolationDocs = [];
      for (int i = 0; i < assetIds.length; i += 30) {
        final chunk = assetIds.sublist(
          i,
          i + 30 > assetIds.length ? assetIds.length : i + 30,
        );
        final snap = await FirebaseFirestore.instance
            .collection('violations')
            .where('assetId', whereIn: chunk)
            .get();
        allViolationDocs.addAll(snap.docs);
      }

      // Step 3: compute stats
      int total = 0;
      int resolved = 0;
      int highSev = 0;
      final List<double> weekData = List.filled(7, 0);

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      for (final doc in allViolationDocs) {
        final v = doc.data() as Map<String, dynamic>;
        total++;

        // resolved count
        if (v['status'] == 'resolved') resolved++;

        // high severity
        final severity = (v['severity'] as String?)?.toLowerCase() ?? '';
        final score = (v['similarityScore'] as num?)?.toDouble() ?? 0.0;
        if (severity == 'high' || score >= 0.90) highSev++;

        // weekly chart
        if (v['detectedAt'] is Timestamp) {
          final detectedDate = (v['detectedAt'] as Timestamp).toDate();
          for (int i = 0; i < 7; i++) {
            final dayStart = todayStart.subtract(Duration(days: 6 - i));
            final dayEnd = dayStart.add(const Duration(days: 1));
            if (detectedDate.isAfter(dayStart) &&
                detectedDate.isBefore(dayEnd)) {
              weekData[i]++;
              break;
            }
          }
        }
      }

      setState(() {
        _totalViolations = total;
        _resolvedViolations = resolved;
        _highSeverity = highSev;
        for (int i = 0; i < 7; i++) {
          _weeklyData[i] = weekData[i];
        }
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  double get _maxY {
    final max = _weeklyData.reduce((a, b) => a > b ? a : b);
    return max < 4 ? 4 : (max + 2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EEC9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF35858E),
        centerTitle: true,
        title: InkWell(
          onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.security, color: Color(0xFFC2D099), size: 24),
              SizedBox(width: 8),
              Text(
                'SportGuard AI',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadAnalytics,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF35858E)),
            )
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadAnalytics,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF35858E),
                    ),
                    child: const Text(
                      'Retry',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadAnalytics,
              color: const Color(0xFF35858E),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Analytics Overview',
                          style: TextStyle(
                            color: Color(0xFF35858E),
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF35858E,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.circle, color: Colors.green, size: 8),
                              SizedBox(width: 4),
                              Text(
                                'Live',
                                style: TextStyle(
                                  color: Color(0xFF35858E),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // summary cards
                    Row(
                      children: [
                        _statCard(
                          label: 'Total Violations',
                          value: '$_totalViolations',
                          icon: Icons.warning_amber_rounded,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 12),
                        _statCard(
                          label: 'Resolved',
                          value: '$_resolvedViolations',
                          icon: Icons.check_circle_outline,
                          color: Colors.green,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _statCard(
                          label: 'Assets Protected',
                          value: '$_assetsProtected',
                          icon: Icons.shield_outlined,
                          color: const Color(0xFF35858E),
                        ),
                        const SizedBox(width: 12),
                        _statCard(
                          label: 'High Severity',
                          value: '$_highSeverity',
                          icon: Icons.priority_high_rounded,
                          color: Colors.orange,
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // resolution rate bar
                    if (_totalViolations > 0) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Resolution Rate',
                                  style: TextStyle(
                                    color: Color(0xFF1E2A3A),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  '${((_resolvedViolations / _totalViolations) * 100).toStringAsFixed(1)}%',
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: _resolvedViolations / _totalViolations,
                                backgroundColor: Colors.grey.withValues(
                                  alpha: 0.2,
                                ),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.green,
                                ),
                                minHeight: 10,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$_resolvedViolations of $_totalViolations violations resolved',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // weekly chart
                    const Text(
                      'Violations This Week',
                      style: TextStyle(
                        color: Color(0xFF1E2A3A),
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Daily violation detections over the last 7 days',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 220,
                      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: _weeklyData.every((v) => v == 0)
                          ? const Center(
                              child: Text(
                                'No violations detected this week.',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 14,
                                ),
                              ),
                            )
                          : LineChart(
                              LineChartData(
                                minY: 0,
                                maxY: _maxY,
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: false,
                                  getDrawingHorizontalLine: (value) => FlLine(
                                    color: Colors.grey.withValues(alpha: 0.15),
                                    strokeWidth: 1,
                                  ),
                                ),
                                titlesData: FlTitlesData(
                                  rightTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  topTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 24,
                                      interval: 1,
                                      getTitlesWidget: (value, meta) {
                                        final idx = value.toInt();
                                        if (idx < 0 ||
                                            idx >= _weekLabels.length) {
                                          return const SizedBox();
                                        }
                                        return SideTitleWidget(
                                          axisSide: meta.axisSide,
                                          child: Text(
                                            _weekLabels[idx],
                                            style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 11,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 28,
                                      interval: _maxY <= 4
                                          ? 1
                                          : (_maxY / 4).ceilToDouble(),
                                      getTitlesWidget: (value, meta) {
                                        if (value != value.roundToDouble())
                                          return const SizedBox();
                                        return SideTitleWidget(
                                          axisSide: meta.axisSide,
                                          child: Text(
                                            value.toInt().toString(),
                                            style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 11,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                borderData: FlBorderData(
                                  show: true,
                                  border: Border(
                                    bottom: BorderSide(
                                      color: Colors.grey.withValues(alpha: 0.2),
                                    ),
                                    left: BorderSide(
                                      color: Colors.grey.withValues(alpha: 0.2),
                                    ),
                                    right: BorderSide.none,
                                    top: BorderSide.none,
                                  ),
                                ),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: List.generate(
                                      7,
                                      (i) =>
                                          FlSpot(i.toDouble(), _weeklyData[i]),
                                    ),
                                    isCurved: true,
                                    color: const Color(0xFF35858E),
                                    barWidth: 3,
                                    dotData: FlDotData(
                                      show: true,
                                      getDotPainter:
                                          (spot, percent, bar, index) =>
                                              FlDotCirclePainter(
                                                radius: spot.y > 0 ? 5 : 3,
                                                color: spot.y > 0
                                                    ? const Color(0xFF35858E)
                                                    : Colors.grey.withValues(
                                                        alpha: 0.3,
                                                      ),
                                                strokeWidth: 2,
                                                strokeColor: Colors.white,
                                              ),
                                    ),
                                    belowBarData: BarAreaData(
                                      show: true,
                                      gradient: LinearGradient(
                                        colors: [
                                          const Color(
                                            0xFF35858E,
                                          ).withValues(alpha: 0.2),
                                          const Color(
                                            0xFF35858E,
                                          ).withValues(alpha: 0.0),
                                        ],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                    ),
                                  ),
                                ],
                                lineTouchData: LineTouchData(
                                  touchTooltipData: LineTouchTooltipData(
                                    getTooltipItems: (spots) => spots.map((s) {
                                      return LineTooltipItem(
                                        '${s.y.toInt()} violation${s.y != 1 ? 's' : ''}',
                                        const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ),
                    ),

                    const SizedBox(height: 24),

                    // pending violations callout
                    if (_totalViolations - _resolvedViolations > 0)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Colors.red,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${_totalViolations - _resolvedViolations} violation${(_totalViolations - _resolvedViolations) == 1 ? '' : 's'} still pending resolution.',
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _statCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
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
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
