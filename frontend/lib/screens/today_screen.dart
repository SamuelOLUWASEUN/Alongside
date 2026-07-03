import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/arc_motif.dart';
import '../widgets/centered_page.dart';
import '../widgets/mood_face.dart';

/// The new landing screen after login - a warm overview instead of dropping
/// straight into an empty chat. Ties together a greeting, today's mood (or
/// a quick way to log one), and a way straight into chat.
class TodayScreen extends StatefulWidget {
  final double? latestMoodScore;
  final DateTime? latestMoodTime;
  final bool loadingMood;
  final int streak;
  final VoidCallback onMoodLogged;
  final ValueChanged<int> onNavigate; // 1=Chat, 2=Mood, 3=Vault

  const TodayScreen({
    super.key,
    required this.latestMoodScore,
    required this.latestMoodTime,
    required this.loadingMood,
    required this.streak,
    required this.onMoodLogged,
    required this.onNavigate,
  });

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  double _quickScore = 5;
  bool _logging = false;

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 5) return 'Still up?';
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  bool get _checkedInToday {
    final t = widget.latestMoodTime;
    if (t == null) return false;
    final now = DateTime.now();
    return now.year == t.year && now.month == t.month && now.day == t.day;
  }

  Future<void> _quickLog() async {
    setState(() => _logging = true);
    try {
      await ApiService.post('/mood/log', {'score': _quickScore.round()});
      widget.onMoodLogged();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Check-in saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _logging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Today')),
      body: CenteredPage(
        children: [
          Row(
            children: [
              const ArcMotif(size: 40, strokeWidth: 5),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_greeting(),
                        style: Theme.of(context).textTheme.displayMedium),
                    const SizedBox(height: 2),
                    Text("Here's your space for today.",
                        style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ),
              if (widget.streak >= 2)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.tideLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 5),
                      Text(
                        '${widget.streak}-day streak',
                        style: TextStyle(
                            color: AppColors.tide,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.line),
            ),
            child: widget.loadingMood
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _checkedInToday
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Today's check-in",
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              MoodFace(
                                  score: widget.latestMoodScore!, size: 48),
                              const SizedBox(width: 14),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    widget.latestMoodScore!.toStringAsFixed(0),
                                    style: Theme.of(context)
                                        .textTheme
                                        .displayLarge
                                        ?.copyWith(color: AppColors.tide),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        bottom: 8, left: 4),
                                    child: Text(
                                      '/10',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                              color: AppColors.mutedText),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: () => widget.onNavigate(2),
                            child: const Text('View your trend'),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text('How are you feeling right now?',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                              ),
                              MoodFace(score: _quickScore, size: 40),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Slider(
                            value: _quickScore,
                            min: 1,
                            max: 10,
                            divisions: 9,
                            label: _quickScore.round().toString(),
                            onChanged: (v) => setState(() => _quickScore = v),
                          ),
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: ElevatedButton(
                              onPressed: _logging ? null : _quickLog,
                              child: _logging
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('Save check-in'),
                            ),
                          ),
                        ],
                      ),
          ),
          const SizedBox(height: 16),
          Material(
            color: AppColors.harbor,
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => widget.onNavigate(1),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const BreathingArc(size: 30),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Talk to your coach',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: Colors.white)),
                          const SizedBox(height: 3),
                          Text(
                            "Whenever you're ready, I'm here.",
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_rounded,
                        color: Colors.white70),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _QuickAction(
                      icon: Icons.lock_outline,
                      label: 'Vault',
                      onTap: () => widget.onNavigate(3))),
              const SizedBox(width: 12),
              Expanded(
                  child: _QuickAction(
                      icon: Icons.insights_outlined,
                      label: 'Mood trend',
                      onTap: () => widget.onNavigate(2))),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.line)),
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            children: [
              Icon(icon, color: AppColors.tide, size: 22),
              const SizedBox(height: 8),
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
