import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shared delete confirmation - deleting a conversation is permanent (it
/// erases every message in it), so both the desktop "⋯" menu and the mobile
/// long-press sheet route through this before actually deleting.
Future<bool> confirmDeleteConversation(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Delete this chat?'),
      content: const Text("This permanently erases the whole conversation. This can't be undone."),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text('Delete', style: TextStyle(color: AppColors.alert)),
        ),
      ],
    ),
  );
  return result ?? false;
}
