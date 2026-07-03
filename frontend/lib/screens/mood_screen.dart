import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class MoodScreen extends StatefulWidget {
  const MoodScreen({super.key});
  @override
  State<MoodScreen> createState() => _MoodScreenState();
}

class _MoodEntry {
  final DateTime time;
  final double score;
  _MoodEntry(this.time, this.score);
}

class _MoodScreenState extends State<MoodScreen> {
  double _score = 5;
  bool _saving = false;
  bool _loadingHistory = true;
  List<_MoodEntry> _history = [];

  static const _labels = {
    1: 'Really rough',
    2: 'Struggling',
    3: 'Low',
    4: 'A bit down',
    5: 'Okay',
    6: 'Steady',
    7: 'Good',
    8: 'Really good',
    9: 'Great',
    10: 'On top of the world',
  };

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final data = await ApiService.get('/mood/history?days=14') as List<dynamic>?;
      if (!mounted) return;
      final entries = (data ?? [])
          .map((e) => _MoodEntry(
                DateTime.parse(e['time'] as String).toLocal(),
                (e['score'] as num).toDouble(),
              ))
          .toList()
        ..sort((a, b) => a.time.compareTo(b.time)); // oldest first for the chart
      setState(() {
        _history = entries;
        _loadingHistory = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _logMood() async {
    setState(() => _saving = true);
    try {
      await ApiService.post('/mood/log', {'score': _score.round()});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check-in saved')));
      }
      await _loadHistory();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mood')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _CheckInCard(
            score: _score,
            label: _labels[_score.round()]!,
            saving: _saving,
            onChanged: (v) => setState(() => _score = v),
            onSave: _logMood,
          ),
          const SizedBox(height: 20),
          _TrendCard(loading: _loadingHistory, history: _history),
        ],
      ),
    );
  }
}

class _CheckInCard extends StatelessWidget {
  final double score;
  final String label;
  final bool saving;
  final ValueChanged<double> onChanged;
  final VoidCallback onSave;

  const _CheckInCard({
    required this.score,
    required this.label,
    required this.saving,
    required this.onChanged,
    required this.onSave,
  });

  Color _scoreColor() {
    // Warmer/redder toward low scores, tide-teal toward high - a quiet
    // signal rather than a jarring traffic-light red/green.
    if (score <= 3) return AppColors.alert;
    if (score <= 6) return AppColors.ember;
    return AppColors.tide;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How are you feeling right now?', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                score.round().toString(),
                style: Theme.of(context).textTheme.displayLarge?.copyWith(color: _scoreColor()),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 4),
                child: Text('/10', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText)),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _scoreColor(),
              inactiveTrackColor: AppColors.line,
              thumbColor: _scoreColor(),
              overlayColor: _scoreColor().withOpacity(0.15),
              trackHeight: 6,
            ),
            child: Slider(
              value: score,
              min: 1,
              max: 10,
              divisions: 9,
              onChanged: onChanged,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: saving ? null : onSave,
              child: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Text('Save check-in'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  final bool loading;
  final List<_MoodEntry> history;

  const _TrendCard({required this.loading, required this.history});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Last 14 days', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : history.isEmpty
                    ? Center(
                        child: Text(
                          'Your trend will appear here after a few check-ins.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      )
                    : _MoodLineChart(history: history),
          ),
        ],
      ),
    );
  }
}

class _MoodLineChart extends StatelessWidget {
  final List<_MoodEntry> history;
  const _MoodLineChart({required this.history});

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (int i = 0; i < history.length; i++) FlSpot(i.toDouble(), history[i].score),
    ];

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 10,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 2.5,
          getDrawingHorizontalLine: (_) => FlLine(color: AppColors.line, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 5,
              reservedSize: 26,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: (history.length / 4).clamp(1, double.infinity).roundToDouble(),
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= history.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    DateFormat('MMM d').format(history[i].time),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppColors.tide,
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) =>
                  FlDotCirclePainter(radius: 3, color: AppColors.tide, strokeWidth: 2, strokeColor: AppColors.surface),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [AppColors.tide.withOpacity(0.18), AppColors.tide.withOpacity(0.0)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
