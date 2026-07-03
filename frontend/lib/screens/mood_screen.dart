import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mood_face.dart';

enum _Tab { mood, sleep }

class MoodScreen extends StatefulWidget {
  const MoodScreen({super.key});
  @override
  State<MoodScreen> createState() => _MoodScreenState();
}

class _MoodEntry {
  final DateTime time;
  final double score;
  final String? note;
  _MoodEntry(this.time, this.score, this.note);
}

class _SleepEntry {
  final DateTime time;
  final double hours;
  final int quality;
  _SleepEntry(this.time, this.hours, this.quality);
}

class _MoodScreenState extends State<MoodScreen> {
  _Tab _tab = _Tab.mood;

  // Mood state
  double _score = 5;
  final _noteController = TextEditingController();
  bool _savingMood = false;
  bool _loadingMoodHistory = true;
  List<_MoodEntry> _moodHistory = [];

  // Sleep state
  double _hours = 7;
  double _quality = 3;
  bool _savingSleep = false;
  bool _loadingSleepHistory = true;
  List<_SleepEntry> _sleepHistory = [];

  static const _moodLabels = {
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

  static const _qualityLabels = {
    1: 'Restless',
    2: 'Poor',
    3: 'Okay',
    4: 'Good',
    5: 'Great sleep',
  };

  @override
  void initState() {
    super.initState();
    _loadMoodHistory();
    _loadSleepHistory();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadMoodHistory() async {
    setState(() => _loadingMoodHistory = true);
    try {
      final data =
          await ApiService.get('/mood/history?days=14') as List<dynamic>?;
      if (!mounted) return;
      final entries = (data ?? [])
          .map((e) => _MoodEntry(
                DateTime.parse(e['time'] as String).toLocal(),
                (e['score'] as num).toDouble(),
                (e['note'] as String?)?.trim().isNotEmpty == true
                    ? e['note'] as String
                    : null,
              ))
          .toList()
        ..sort((a, b) => a.time.compareTo(b.time));
      setState(() {
        _moodHistory = entries;
        _loadingMoodHistory = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMoodHistory = false);
    }
  }

  Future<void> _loadSleepHistory() async {
    setState(() => _loadingSleepHistory = true);
    try {
      final data =
          await ApiService.get('/sleep/history?days=14') as List<dynamic>?;
      if (!mounted) return;
      final entries = (data ?? [])
          .map((e) => _SleepEntry(
                DateTime.parse(e['time'] as String).toLocal(),
                (e['hours'] as num).toDouble(),
                (e['quality'] as num).toInt(),
              ))
          .toList()
        ..sort((a, b) => a.time.compareTo(b.time));
      setState(() {
        _sleepHistory = entries;
        _loadingSleepHistory = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingSleepHistory = false);
    }
  }

  Future<void> _logMood() async {
    setState(() => _savingMood = true);
    try {
      await ApiService.post('/mood/log', {
        'score': _score.round(),
        'note': _noteController.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Check-in saved')));
        _noteController.clear();
      }
      await _loadMoodHistory();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingMood = false);
    }
  }

  Future<void> _logSleep() async {
    setState(() => _savingSleep = true);
    try {
      await ApiService.post('/sleep/log', {
        'hours': _hours,
        'quality': _quality.round(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Sleep logged')));
      }
      await _loadSleepHistory();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingSleep = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final moodRecentFirst = _moodHistory.reversed.toList();
    final sleepRecentFirst = _sleepHistory.reversed.toList();

    return Scaffold(
      appBar: AppBar(title: Text(_tab == _Tab.mood ? 'Mood' : 'Sleep')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _TabSwitcher(
            tab: _tab,
            onChanged: (t) => setState(() => _tab = t),
          ),
          const SizedBox(height: 16),
          if (_tab == _Tab.mood) ...[
            _MoodCheckInCard(
              score: _score,
              label: _moodLabels[_score.round()]!,
              saving: _savingMood,
              noteController: _noteController,
              onChanged: (v) => setState(() => _score = v),
              onSave: _logMood,
            ),
            const SizedBox(height: 20),
            _TrendCard(
              title: 'Last 14 days',
              loading: _loadingMoodHistory,
              emptyText: 'Your trend will appear here after a few check-ins.',
              minY: 0,
              maxY: 10,
              interval: 5,
              spots: [
                for (int i = 0; i < _moodHistory.length; i++)
                  FlSpot(i.toDouble(), _moodHistory[i].score)
              ],
              dates: _moodHistory.map((e) => e.time).toList(),
            ),
            if (!_loadingMoodHistory && moodRecentFirst.isNotEmpty) ...[
              const SizedBox(height: 20),
              _RecentMoodCard(entries: moodRecentFirst.take(8).toList()),
            ],
          ] else ...[
            _SleepCheckInCard(
              hours: _hours,
              quality: _quality,
              qualityLabel: _qualityLabels[_quality.round()]!,
              saving: _savingSleep,
              onHoursChanged: (v) => setState(() => _hours = v),
              onQualityChanged: (v) => setState(() => _quality = v),
              onSave: _logSleep,
            ),
            const SizedBox(height: 20),
            _TrendCard(
              title: 'Last 14 days',
              loading: _loadingSleepHistory,
              emptyText: 'Your sleep trend will appear here after a few logs.',
              minY: 0,
              maxY: 12,
              interval: 3,
              spots: [
                for (int i = 0; i < _sleepHistory.length; i++)
                  FlSpot(i.toDouble(), _sleepHistory[i].hours)
              ],
              dates: _sleepHistory.map((e) => e.time).toList(),
            ),
            if (!_loadingSleepHistory && sleepRecentFirst.isNotEmpty) ...[
              const SizedBox(height: 20),
              _RecentSleepCard(
                  entries: sleepRecentFirst.take(8).toList(),
                  qualityLabels: _qualityLabels),
            ],
          ],
        ],
      ),
    );
  }
}

/// Small pill toggle switching between the Mood and Sleep tabs, instead of
/// a separate bottom-nav item (which would push the mobile nav back over
/// its comfortable 5-item width).
class _TabSwitcher extends StatelessWidget {
  final _Tab tab;
  final ValueChanged<_Tab> onChanged;
  const _TabSwitcher({required this.tab, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line)),
      child: Row(
        children: [
          Expanded(
              child: _TabButton(
                  label: 'Mood',
                  icon: Icons.insights_outlined,
                  selected: tab == _Tab.mood,
                  onTap: () => onChanged(_Tab.mood))),
          Expanded(
              child: _TabButton(
                  label: 'Sleep',
                  icon: Icons.bedtime_outlined,
                  selected: tab == _Tab.sleep,
                  onTap: () => onChanged(_Tab.sleep))),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _TabButton(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.tide : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: selected ? Colors.white : AppColors.mutedText),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                    color: selected ? Colors.white : AppColors.mutedText,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoodCheckInCard extends StatelessWidget {
  final double score;
  final String label;
  final bool saving;
  final TextEditingController noteController;
  final ValueChanged<double> onChanged;
  final VoidCallback onSave;

  const _MoodCheckInCard({
    required this.score,
    required this.label,
    required this.saving,
    required this.noteController,
    required this.onChanged,
    required this.onSave,
  });

  Color _scoreColor() {
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
          border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How are you feeling right now?',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              MoodFace(score: score, size: 56),
              const SizedBox(width: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(score.round().toString(),
                      style: Theme.of(context)
                          .textTheme
                          .displayLarge
                          ?.copyWith(color: _scoreColor())),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 4),
                    child: Text('/10',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.mutedText)),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(label,
                          style: Theme.of(context).textTheme.bodyMedium)),
                ],
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
                onChanged: onChanged),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: noteController,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Anything you want to add? (optional)',
                alignLabelWithHint: true),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: saving ? null : onSave,
              child: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white))
                  : const Text('Save check-in'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SleepCheckInCard extends StatelessWidget {
  final double hours;
  final double quality;
  final String qualityLabel;
  final bool saving;
  final ValueChanged<double> onHoursChanged;
  final ValueChanged<double> onQualityChanged;
  final VoidCallback onSave;

  const _SleepCheckInCard({
    required this.hours,
    required this.quality,
    required this.qualityLabel,
    required this.saving,
    required this.onHoursChanged,
    required this.onQualityChanged,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How did you sleep?',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                    color: AppColors.tideLight, shape: BoxShape.circle),
                child: Icon(Icons.bedtime, color: AppColors.tide, size: 26),
              ),
              const SizedBox(width: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    hours % 1 == 0
                        ? hours.toStringAsFixed(0)
                        : hours.toStringAsFixed(1),
                    style: Theme.of(context)
                        .textTheme
                        .displayLarge
                        ?.copyWith(color: AppColors.tide),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 4),
                    child: Text('hrs',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.mutedText)),
                  ),
                ],
              ),
            ],
          ),
          Slider(
              value: hours,
              min: 0,
              max: 12,
              divisions: 24,
              label: '${hours.toStringAsFixed(1)}h',
              onChanged: onHoursChanged),
          const SizedBox(height: 10),
          Text('Sleep quality',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          Slider(
              value: quality,
              min: 1,
              max: 5,
              divisions: 4,
              label: qualityLabel,
              onChanged: onQualityChanged),
          Align(
              alignment: Alignment.centerRight,
              child: Text(qualityLabel,
                  style: Theme.of(context).textTheme.labelSmall)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: saving ? null : onSave,
              child: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white))
                  : const Text('Save sleep log'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared line-chart trend card, reused for both mood scores and sleep
/// hours so the visual language stays identical between the two tabs.
class _TrendCard extends StatelessWidget {
  final String title;
  final bool loading;
  final String emptyText;
  final double minY;
  final double maxY;
  final double interval;
  final List<FlSpot> spots;
  final List<DateTime> dates;

  const _TrendCard({
    required this.title,
    required this.loading,
    required this.emptyText,
    required this.minY,
    required this.maxY,
    required this.interval,
    required this.spots,
    required this.dates,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : dates.isEmpty
                    ? Center(
                        child: Text(emptyText,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall))
                    : _LineChart(
                        minY: minY,
                        maxY: maxY,
                        interval: interval,
                        spots: spots,
                        dates: dates),
          ),
        ],
      ),
    );
  }
}

class _LineChart extends StatelessWidget {
  final double minY;
  final double maxY;
  final double interval;
  final List<FlSpot> spots;
  final List<DateTime> dates;
  const _LineChart(
      {required this.minY,
      required this.maxY,
      required this.interval,
      required this.spots,
      required this.dates});

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: AppColors.line, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: interval,
              reservedSize: 26,
              getTitlesWidget: (value, meta) => Text(value.toInt().toString(),
                  style: Theme.of(context).textTheme.labelSmall),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval:
                  (dates.length / 4).clamp(1, double.infinity).roundToDouble(),
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= dates.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(DateFormat('MMM d').format(dates[i]),
                      style: Theme.of(context).textTheme.labelSmall),
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
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                  radius: 3,
                  color: AppColors.tide,
                  strokeWidth: 2,
                  strokeColor: AppColors.surface),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  AppColors.tide.withOpacity(0.18),
                  AppColors.tide.withOpacity(0.0)
                ],
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

class _RecentMoodCard extends StatelessWidget {
  final List<_MoodEntry> entries;
  const _RecentMoodCard({required this.entries});

  Color _scoreColor(double score) {
    if (score <= 3) return AppColors.alert;
    if (score <= 6) return AppColors.ember;
    return AppColors.tide;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text('Recent check-ins',
                  style: Theme.of(context).textTheme.titleMedium)),
          ...List.generate(entries.length, (i) {
            final e = entries[i];
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: _scoreColor(e.score).withOpacity(0.12),
                        shape: BoxShape.circle),
                    child: Text(e.score.round().toString(),
                        style: TextStyle(
                            color: _scoreColor(e.score),
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(DateFormat('MMM d, HH:mm').format(e.time),
                            style: Theme.of(context).textTheme.labelSmall),
                        if (e.note != null) ...[
                          const SizedBox(height: 3),
                          Text(e.note!,
                              style: Theme.of(context).textTheme.bodyMedium)
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _RecentSleepCard extends StatelessWidget {
  final List<_SleepEntry> entries;
  final Map<int, String> qualityLabels;
  const _RecentSleepCard({required this.entries, required this.qualityLabels});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text('Recent nights',
                  style: Theme.of(context).textTheme.titleMedium)),
          ...List.generate(entries.length, (i) {
            final e = entries[i];
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: AppColors.tideLight, shape: BoxShape.circle),
                    child: Icon(Icons.bedtime, size: 15, color: AppColors.tide),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${e.hours.toStringAsFixed(1)} hrs · ${qualityLabels[e.quality] ?? ''}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(DateFormat('MMM d, HH:mm').format(e.time),
                            style: Theme.of(context).textTheme.labelSmall),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
