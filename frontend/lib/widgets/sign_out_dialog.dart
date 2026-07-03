import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'crisis_resources.dart';

/// A warm sign-out confirmation - not just "are you sure?", but a moment
/// that leaves the door open for support without assuming distress. Most
/// people signing out are just done for now, so this stays low-key and
/// never blocks or interrogates - the crisis-resources link is there for
/// whoever needs it, entirely optional for everyone else.
Future<bool> confirmSignOut(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sign out?', style: Theme.of(dialogContext).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(
              "Your check-ins and chats will be right here when you're back.",
              style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText, height: 1.5),
            ),
            const SizedBox(height: 16),
            Material(
              color: AppColors.tideLight,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => showCrisisResourcesDialog(dialogContext),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.favorite_border, size: 17, color: AppColors.tide),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Need to talk to someone before you go?',
                          style: TextStyle(color: AppColors.headingText, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 18, color: AppColors.tide),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Stay'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Sign out'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}
