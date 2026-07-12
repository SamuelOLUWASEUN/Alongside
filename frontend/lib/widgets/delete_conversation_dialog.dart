import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shared delete confirmation - deleting a conversation is permanent (it
/// erases every message in it), so both the desktop "⋯" menu and the mobile
/// long-press sheet route through this before actually deleting.
///
/// The actual delete runs *inside* this dialog (via onConfirmDelete) rather
/// than the caller firing it off separately after the dialog closes. That
/// matters if the request is slow (a cold backend, a network hiccup): the
/// dialog stays open showing "Deleting..." for as long as it actually takes,
/// so a slow response reads as "still working" rather than looking like the
/// tap did nothing - which was previously causing people to tap Delete a
/// second time, unsure if the first one registered.
Future<bool> confirmDeleteConversation(
  BuildContext context,
  Future<void> Function() onConfirmDelete,
) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) =>
        _DeleteConversationDialog(onConfirmDelete: onConfirmDelete),
  );
  return result ?? false;
}

class _DeleteConversationDialog extends StatefulWidget {
  final Future<void> Function() onConfirmDelete;
  const _DeleteConversationDialog({required this.onConfirmDelete});

  @override
  State<_DeleteConversationDialog> createState() =>
      _DeleteConversationDialogState();
}

class _DeleteConversationDialogState extends State<_DeleteConversationDialog> {
  bool _deleting = false;
  String? _error;

  Future<void> _confirm() async {
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await widget.onConfirmDelete();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _deleting = false;
          _error =
              "Couldn't delete that chat. Check your connection and try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Delete this chat?'),
      content: _deleting
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 14),
                  Text('Deleting...'),
                ],
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    "This permanently erases the whole conversation. This can't be undone."),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(color: AppColors.alert, fontSize: 13)),
                ],
              ],
            ),
      actions: _deleting
          ? const []
          : [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              TextButton(
                onPressed: _confirm,
                child: Text('Delete', style: TextStyle(color: AppColors.alert)),
              ),
            ],
    );
  }
}
