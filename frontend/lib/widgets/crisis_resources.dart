import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// Shared "you're not alone" crisis-resources dialog, used from Settings
/// and from the sign-out flow so support is never more than a tap away.
Future<void> showCrisisResourcesDialog(BuildContext context) async {
  String helpline = 'https://findahelpline.com';
  try {
    final data = await ApiService.get('/crisis/helplines', auth: false);
    if (data != null && data['helpline'] != null) helpline = data['helpline'] as String;
  } catch (_) {
    // fall back to the default above
  }
  if (!context.mounted) return;
  showDialog(
    context: context,
    builder: (_) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.alertTint, shape: BoxShape.circle),
              child: Icon(Icons.favorite, color: AppColors.alert, size: 20),
            ),
            const SizedBox(height: 14),
            Text("You're not alone", style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(helpline, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5)),
            const SizedBox(height: 6),
            Text(
              "If you're in immediate danger, please contact emergency services.",
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ),
          ],
        ),
      ),
    ),
  );
}
