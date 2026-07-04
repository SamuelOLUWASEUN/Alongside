import 'package:flutter/material.dart';
import '../services/lock_service.dart';
import '../theme/app_theme.dart';

/// Two-step PIN entry (enter, then confirm) shown when turning app lock on.
/// Returns true once a PIN was successfully set.
Future<bool> showPinSetupDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => const _PinSetupDialog(),
  );
  return result ?? false;
}

class _PinSetupDialog extends StatefulWidget {
  const _PinSetupDialog();
  @override
  State<_PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<_PinSetupDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  bool _confirming = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _submitFirst() {
    final pin = _first.text.trim();
    if (pin.length < 4) {
      setState(() => _error = 'Use at least 4 digits');
      return;
    }
    setState(() {
      _confirming = true;
      _error = null;
    });
  }

  Future<void> _submitSecond() async {
    if (_second.text.trim() != _first.text.trim()) {
      setState(() {
        _error = "PINs don't match";
        _second.clear();
      });
      return;
    }
    await LockService.setPin(_first.text.trim());
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_confirming ? 'Confirm your PIN' : 'Set a PIN',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              _confirming
                  ? "Enter it once more to make sure it's right."
                  : "You'll need this to open Alongside. Choose 4-6 digits.",
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.mutedText),
            ),
            const SizedBox(height: 18),
            TextField(
              key: ValueKey(_confirming),
              controller: _confirming ? _second : _first,
              obscureText: _obscure,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              decoration: InputDecoration(
                labelText: _confirming ? 'Confirm PIN' : 'New PIN',
                counterText: '',
                errorText: _error,
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) =>
                  _confirming ? _submitSecond() : _submitFirst(),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                const SizedBox(width: 8),
                ElevatedButton(
                    onPressed: _confirming ? _submitSecond : _submitFirst,
                    child: Text(_confirming ? 'Confirm' : 'Next')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when turning app lock off - requires the current PIN before
/// disabling, so it can't be casually switched off with a single tap.
Future<bool> showPinConfirmDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => const _PinConfirmDialog(),
  );
  return result ?? false;
}

class _PinConfirmDialog extends StatefulWidget {
  const _PinConfirmDialog();
  @override
  State<_PinConfirmDialog> createState() => _PinConfirmDialogState();
}

class _PinConfirmDialogState extends State<_PinConfirmDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ok = await LockService.verifyPin(_controller.text.trim());
    if (ok) {
      if (mounted) Navigator.pop(context, true);
    } else {
      setState(() {
        _error = 'Incorrect PIN';
        _controller.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter your PIN to turn off app lock',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              obscureText: _obscure,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'PIN',
                counterText: '',
                errorText: _error,
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                const SizedBox(width: 8),
                ElevatedButton(
                    onPressed: _submit, child: const Text('Turn off')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
