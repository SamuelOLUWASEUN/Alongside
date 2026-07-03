import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'sign_out_dialog.dart';

/// A small profile dialog opened by tapping the account avatar (sidebar or
/// Settings). Keeps this to what's actually available right now - email and
/// sign out - rather than implying editable profile fields that don't exist
/// yet. Pass [onGoToSettings] to show a shortcut into the Settings tab (the
/// sidebar does this; Settings itself doesn't need to link to itself).
///
/// Centered like every other popup in the app (sign-out, crisis resources,
/// vault dialogs) rather than a bottom sheet, for consistency.
Future<void> showProfileSheet(BuildContext context, {VoidCallback? onGoToSettings}) async {
  final auth = context.read<AuthService>();
  await showDialog(
    context: context,
    builder: (dialogContext) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.tide,
              child: Text(
                (auth.email ?? '?').isNotEmpty ? auth.email![0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 14),
            Text(auth.email ?? '', style: Theme.of(dialogContext).textTheme.titleMedium),
            const SizedBox(height: 2),
            Text('Alongside account', style: Theme.of(dialogContext).textTheme.labelSmall),
            const SizedBox(height: 20),
            if (onGoToSettings != null) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    onGoToSettings();
                  },
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Go to settings'),
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  final confirmed = await confirmSignOut(context);
                  if (confirmed && context.mounted) {
                    context.read<AuthService>().logout();
                  }
                },
                icon: Icon(Icons.logout, size: 18, color: AppColors.alert),
                label: Text('Sign out', style: TextStyle(color: AppColors.alert)),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
            ),
          ],
        ),
      ),
    ),
  );
}
