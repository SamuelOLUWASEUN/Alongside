import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/arc_motif.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _consentMoodTracking = true;
  bool _consentAiJournal = true;
  bool _isLogin = true;
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    final auth = context.read<AuthService>();
    try {
      if (_isLogin) {
        await auth.login(_emailController.text.trim(), _passwordController.text);
      } else {
        await auth.register(_emailController.text.trim(), _passwordController.text);
        await auth.login(_emailController.text.trim(), _passwordController.text);
        // Record the consent choices made on this screen. Fire-and-forget:
        // consent logging shouldn't block getting into the app.
        unawaited(ApiService.post('/consent/grant', {'type': 'mood_tracking', 'granted': _consentMoodTracking}));
        unawaited(ApiService.post('/consent/grant', {'type': 'ai_journal', 'granted': _consentAiJournal}));
      }
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(Object e) {
    final text = e.toString();
    if (text.contains('401')) return "That email and password don't match.";
    if (text.contains('409')) return 'An account already exists with that email.';
    return "Something didn't go through. Check your connection and try again.";
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  const Center(child: ArcMotif(size: 96, strokeWidth: 7)),
                  const SizedBox(height: 28),
                  Text(
                    _isLogin ? 'Welcome back' : 'A quiet place\nto check in',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isLogin
                        ? "Glad you're here. Sign in to pick up where you left off."
                        : 'Track how you feel, talk it through, and keep what matters to yourself private.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
                  ),
                  const SizedBox(height: 36),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (!_isLogin) ...[
                    const SizedBox(height: 28),
                    _ConsentRow(
                      title: 'Mood tracking',
                      subtitle: "Let Alongside remember your check-ins so you can see patterns over time.",
                      value: _consentMoodTracking,
                      onChanged: (v) => setState(() => _consentMoodTracking = v),
                    ),
                    const SizedBox(height: 10),
                    _ConsentRow(
                      title: 'AI journal',
                      subtitle: 'Let your coach conversations inform gentle, personalized check-ins.',
                      value: _consentAiJournal,
                      onChanged: (v) => setState(() => _consentAiJournal = v),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.alertTint,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(color: AppColors.alert, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                            )
                          : Text(_isLogin ? 'Sign in' : 'Create account'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: TextButton(
                      onPressed: _loading ? null : () => setState(() => _isLogin = !_isLogin),
                      child: Text(_isLogin ? "New here? Create an account" : 'Already have an account? Sign in'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConsentRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ConsentRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
