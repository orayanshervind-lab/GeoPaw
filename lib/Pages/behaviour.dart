import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../services/pet_provider.dart';

class BehaviourScreen extends StatefulWidget {
  const BehaviourScreen({super.key});

  @override
  State<BehaviourScreen> createState() => _BehaviourScreenState();
}

class _BehaviourScreenState extends State<BehaviourScreen> {
  List<Map<String, dynamic>> _dailyData = [];
  bool _isLoading = true;
  String _selectedMetric = 'totalDistance';

  String get _petId =>
      context.read<PetProvider>().selectedPet?.id ??
      FirebaseAuth.instance.currentUser?.uid ??
      'demo';

  final Map<String, String> _metricLabels = {
    'totalDistance': 'Daily Distance (m)',
    'avgSpeed': 'Avg Speed (m/s)',
    'activeTimePct': 'Active Time (%)',
    'anomalyScore': 'Anomaly Score',
  };

  @override
  void initState() {
    super.initState();
    _loadBehaviourData();
  }

  /// Normalizes whatever date representation comes back from Firebase
  /// (ISO strings, timestamps, or plain keys) into a short "d/M" label
  /// so the x-axis never has to render long strings.
  String _formatDate(dynamic rawDate, String fallbackKey) {
    try {
      final source = rawDate?.toString() ?? fallbackKey;
      final dt = DateTime.parse(source);
      return '${dt.day}/${dt.month}';
    } catch (_) {
      // Fallback: if it's not parseable, just trim to something short
      final raw = rawDate?.toString() ?? fallbackKey;
      return raw.length > 6 ? raw.substring(raw.length - 5) : raw;
    }
  }

  /// True only if the most recent record we have is actually from today.
  /// If the device was off / never synced today, this is false, and the
  /// UI should NOT claim the last known distance is "today's".
  bool get _hasTodayData {
    if (_dailyData.isEmpty) return false;
    final now = DateTime.now();
    final todayLabel = '${now.day}/${now.month}';
    return _dailyData.last['date'] == todayLabel;
  }

  void _loadBehaviourData() {
    setState(() => _isLoading = true);
    final ref = FirebaseDatabase.instance.ref('behaviour/$_petId');
    ref.orderByChild('date').limitToLast(14).onValue.listen((event) {
      final data = event.snapshot.value;
      final List<Map<String, dynamic>> loaded = [];
      if (data != null && data is Map) {
        data.forEach((key, value) {
          if (value is Map) {
            loaded.add({
              'date': _formatDate(value['date'], key.toString()),
              'totalDistance':
                  (value['totalDistance'] as num?)?.toDouble() ?? 0,
              'avgSpeed': (value['avgSpeed'] as num?)?.toDouble() ?? 0,
              'activeTimePct':
                  (value['activeTimePct'] as num?)?.toDouble() ?? 0,
              'anomalyScore':
                  (value['anomalyScore'] as num?)?.toDouble() ?? 0,
            });
          }
        });
        loaded.sort((a, b) => a['date'].compareTo(b['date']));
      }
      if (mounted) {
        setState(() {
          _dailyData = loaded.isEmpty ? _demoData() : loaded;
          _isLoading = false;
        });
      }
    });

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _isLoading) {
        setState(() {
          if (_dailyData.isEmpty) _dailyData = _demoData();
          _isLoading = false;
        });
      }
    });
  }

  List<Map<String, dynamic>> _demoData() {
    final now = DateTime.now();
    return List.generate(14, (i) {
      final day = now.subtract(Duration(days: 13 - i));
      final label = '${day.day}/${day.month}';
      final isAnomaly = i == 10;
      return {
        'date': label,
        'totalDistance': isAnomaly ? 180.0 : 800.0 + (i * 20) % 300,
        'avgSpeed': isAnomaly ? 0.2 : 0.8 + (i % 3) * 0.15,
        'activeTimePct': isAnomaly ? 10.0 : 45.0 + (i % 4) * 5,
        'anomalyScore': isAnomaly ? 0.82 : 0.05 + (i % 5) * 0.04,
      };
    });
  }

  double get _maxY {
    if (_dailyData.isEmpty) return 100;
    final vals = _dailyData
        .map((d) => (d[_selectedMetric] as num).toDouble());
    return (vals.reduce((a, b) => a > b ? a : b) * 1.3).ceilToDouble();
  }

  Color _barColor(double value) {
    if (_selectedMetric == 'anomalyScore') {
      if (value > 0.45) return Colors.red;
      if (value > 0.3) return Colors.orange;
      return Colors.teal;
    }
    return Theme.of(context).colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final selectedPet = context.watch<PetProvider>().selectedPet;
    final pets = context.watch<PetProvider>().pets;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          selectedPet != null
              ? '${selectedPet.name}\'s Behaviour'
              : 'Behaviour Patterns',
        ),
        actions: [
          if (pets.length > 1)
            _PetSwitcherButton(onChanged: _loadBehaviourData),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SummaryCards(data: _dailyData, hasTodayData: _hasTodayData),
                  const SizedBox(height: 20),

                  Text('Select metric',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _metricLabels.entries.map((entry) {
                        final selected = _selectedMetric == entry.key;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(entry.value),
                            selected: selected,
                            onSelected: (_) => setState(
                                () => _selectedMetric = entry.key),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Text(
                    _metricLabels[_selectedMetric] ?? '',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text('Last 14 days',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),

                  SizedBox(
                    height: 220,
                    child: BarChart(
                      BarChartData(
                        maxY: _maxY,
                        minY: 0,
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              final d = _dailyData[groupIndex];
                              return BarTooltipItem(
                                '${d['date']}\n${rod.toY.toStringAsFixed(2)}',
                                const TextStyle(
                                    color: Colors.white, fontSize: 12),
                              );
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (val, meta) => Text(
                                val.toInt().toString(),
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 28,
                              // NOTE: `interval` here does nothing useful for a
                              // manually-drawn getTitlesWidget on a category
                              // axis like this — it only affects
                              // auto-generated numeric ticks. We skip labels
                              // manually below instead.
                              getTitlesWidget: (val, meta) {
                                final i = val.toInt();
                                if (i >= _dailyData.length || i < 0) {
                                  return const SizedBox();
                                }
                                // Only show every 2nd label to avoid the
                                // dates overlapping/smashing together.
                                if (i % 2 != 0) {
                                  return const SizedBox();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    _dailyData[i]['date'],
                                    style: const TextStyle(fontSize: 9),
                                  ),
                                );
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                        ),
                        gridData: const FlGridData(show: true),
                        borderData: FlBorderData(show: false),
                        barGroups: List.generate(_dailyData.length, (i) {
                          final val =
                              (_dailyData[i][_selectedMetric] as num)
                                  .toDouble();
                          return BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: val,
                                color: _barColor(val),
                                width: 14,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4)),
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  Text('Anomaly Score Trend',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    'Red line = alert threshold (0.45). '
                    'Spikes display unusual behaviour.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    height: 180,
                    child: LineChart(
                      LineChartData(
                        minY: 0,
                        maxY: 1,
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipItems: (spots) => spots.map((s) {
                              return LineTooltipItem(
                                'Score: ${s.y.toStringAsFixed(2)}',
                                const TextStyle(
                                    color: Colors.white, fontSize: 12),
                              );
                            }).toList(),
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 36,
                              getTitlesWidget: (val, meta) => Text(
                                val.toStringAsFixed(1),
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ),
                          bottomTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                        ),
                        gridData: const FlGridData(show: true),
                        borderData: FlBorderData(show: false),
                        extraLinesData: ExtraLinesData(
                          horizontalLines: [
                            HorizontalLine(
                              y: 0.4,
                              color: Colors.red,
                              strokeWidth: 1.5,
                              dashArray: [6, 4],
                              label: HorizontalLineLabel(
                                show: true,
                                labelResolver: (_) => 'Alert threshold',
                                style: const TextStyle(
                                    color: Colors.red, fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: List.generate(
                              _dailyData.length,
                              (i) => FlSpot(
                                i.toDouble(),
                                (_dailyData[i]['anomalyScore'] as num)
                                    .toDouble(),
                              ),
                            ),
                            isCurved: true,
                            color: Theme.of(context).colorScheme.primary,
                            barWidth: 2.5,
                            dotData: FlDotData(
                              getDotPainter: (spot, _, __, ___) =>
                                  FlDotCirclePainter(
                                radius: spot.y > 0.45 ? 6 : 3,
                                color: spot.y > 0.45
                                    ? Colors.red
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            belowBarData: BarAreaData(
                              show: true,
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class _PetSwitcherButton extends StatelessWidget {
  final VoidCallback onChanged;
  const _PetSwitcherButton({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PetProvider>();
    final selected = provider.selectedPet;

    return PopupMenuButton<String>(
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            selected == null
                ? '🐾'
                : selected.species == 'Dog'
                    ? '🐶'
                    : selected.species == 'Cat'
                        ? '🐱'
                        : '🐾',
            style: const TextStyle(fontSize: 18),
          ),
          const Icon(Icons.arrow_drop_down, size: 18),
        ],
      ),
      onSelected: (petId) {
        final pet = provider.pets.firstWhere((p) => p.id == petId);
        provider.selectPet(pet);
        onChanged();
      },
      itemBuilder: (_) => provider.pets
          .map(
            (pet) => PopupMenuItem(
              value: pet.id,
              child: Row(
                children: [
                  Text(
                    pet.species == 'Dog'
                        ? '🐶'
                        : pet.species == 'Cat'
                            ? '🐱'
                            : '🐾',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(pet.name),
                  if (provider.selectedPet?.id == pet.id) ...[
                    const Spacer(),
                    Icon(Icons.check,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary),
                  ],
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final bool hasTodayData;
  const _SummaryCards({required this.data, required this.hasTodayData});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox();
    final latest = data.last;
    final avgDist = data
            .map((d) => (d['totalDistance'] as num).toDouble())
            .reduce((a, b) => a + b) /
        data.length;
    final anomalies = data
        .where((d) => (d['anomalyScore'] as num).toDouble() > 0.45)
        .length;

    // Only call it "today's distance" if the most recent record actually
    // is from today. Otherwise be upfront that it's stale data, so an
    // idle/off device doesn't get mislabeled as active today.
    final distanceLabel = hasTodayData
        ? 'Today\'s distance'
        : 'Last recorded (${latest['date']})';

    return Row(
      children: [
        _StatCard(
          label: distanceLabel,
          value: '${(latest['totalDistance'] as num).toInt()} m',
          icon: Icons.straighten,
          color: Colors.teal,
        ),
        const SizedBox(width: 10),
        _StatCard(
          label: '14-day avg',
          value: '${avgDist.toInt()} m',
          icon: Icons.show_chart,
          color: Colors.blue,
        ),
        const SizedBox(width: 10),
        _StatCard(
          label: 'Anomalies',
          value: '$anomalies days',
          icon: Icons.warning_amber,
          color: anomalies > 0 ? Colors.orange : Colors.green,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 8),
              Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}