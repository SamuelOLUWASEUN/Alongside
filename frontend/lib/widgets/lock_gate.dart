import 'package:flutter/material.dart';
import '../services/lock_service.dart';
import '../theme/app_theme.dart';
import 'arc_motif.dart';

/// Wraps the authenticated part of the app. If a PIN lock is set, shows a
/// full-screen unlock prompt on first launch and again whenever the app
/// returns from the background - covering the sensitive content underneath
/// until the correct PIN (or, where available, biometrics) is entered.
class LockGate extends StatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool _locked = true;
  bool _checkedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLockState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkLockState() async {
    final enabled = await LockService.isEnabled();
    if (!mounted) return;
    setState(() {
      _locked = enabled;
      _checkedOnce = true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLockState();
    } else if (state == AppLifecycleState.paused) {
      // Re-lock proactively on the way out, so coming back to the app
      // never shows a stale unlocked frame even for a split second.
      LockService.isEnabled().then((enabled) {
        if (enabled && mounted) setState(() => _locked = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checkedOnce) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Stack(
      children: [
        widget.child,
        if (_locked)
          _LockScreen(onUnlocked: () => setState(() => _locked = false)),
      ],
    );
  }
}

class _LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const _LockScreen({required this.onUnlocked});

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  final _pinController = TextEditingController();
  String? _error;
  bool _checkingBiometrics = true;
  bool _biometricsAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _checkBiometrics() async {
    final available = await LockService.canUseBiometrics();
    if (!mounted) return;
    setState(() {
      _biometricsAvailable = available;
      _checkingBiometrics = false;
    });
    // On a device that actually supports it, try biometrics immediately so
    // most unlocks need zero taps - the PIN field is still right there for
    // whenever it's declined or fails.
    if (available) _tryBiometrics();
  }

  Future<void> _tryBiometrics() async {
    final success = await LockService.authenticateWithBiometrics();
    if (success && mounted) widget.onUnlocked();
  }

  Future<void> _submitPin() async {
    final ok = await LockService.verifyPin(_pinController.text.trim());
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() => _error = 'Incorrect PIN');
      _pinController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.harbor,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ArcMotif(size: 56, strokeWidth: 6),
                const SizedBox(height: 20),
                Text('Enter your PIN',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(color: Colors.white)),
                const SizedBox(height: 24),
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _pinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    autofocus: true,
                    maxLength: 6,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 22, letterSpacing: 8),
                    decoration: InputDecoration(
                      counterText: '',
                      errorText: _error,
                      enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white38)),
                      focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white)),
                    ),
                    onChanged: (_) => setState(() => _error = null),
                    onSubmitted: (_) => _submitPin(),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                    width: 200,
                    child: ElevatedButton(
                        onPressed: _submitPin, child: const Text('Unlock'))),
                if (!_checkingBiometrics && _biometricsAvailable) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _tryBiometrics,
                    icon: const Icon(Icons.fingerprint, color: Colors.white70),
                    label: const Text('Use biometrics',
                        style: TextStyle(color: Colors.white70)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
