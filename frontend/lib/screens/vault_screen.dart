import 'package:flutter/material.dart';
import '../services/encryption_service.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// Vault UI: enter a passphrase once per note (in a production build you'd
/// derive/cache this behind a biometric unlock instead of retyping it every
/// time — see docs/e2e-encryption.md), encrypt client-side, and send only
/// ciphertext to the server.
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});
  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final _passphraseController = TextEditingController();
  final _noteController = TextEditingController();
  bool _loading = false;
  List<dynamic> _items = [];
  bool _loadingItems = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() => _loadingItems = true);
    try {
      final data = await ApiService.get('/vault');
      if (mounted) setState(() => _items = (data as List<dynamic>?) ?? []);
    } catch (e) {
      // Show what went wrong instead of silently leaving the list stale -
      // a swallowed error here previously made successful deletes/saves
      // look like they'd failed, since the list just never refreshed.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not refresh notes: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingItems = false);
    }
  }

  Future<void> _addNote() async {
    final passphrase = _passphraseController.text.trim();
    final plaintext = _noteController.text.trim();
    if (passphrase.isEmpty || plaintext.isEmpty) return;

    setState(() => _loading = true);
    // Let Flutter actually paint the "Encrypting..." state before we run
    // the blocking PBKDF2/AES-GCM work below - without this the UI thread
    // goes straight from setState into the heavy computation and never
    // gets a chance to render the loading indicator first.
    await Future<void>.delayed(Duration.zero);

    try {
      final encryptedPayload = EncryptionService.encrypt(plaintext, passphrase);
      await ApiService.post('/vault', {
        'label': 'My Note',
        'encrypted_data': encryptedPayload,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note saved securely')));
        _noteController.clear();
      }
      await _loadItems();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decryptAndShow(String encryptedData) async {
    final passphrase = _passphraseController.text.trim();
    if (passphrase.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your passphrase above first')),
      );
      return;
    }
    try {
      final plaintext = EncryptionService.decrypt(encryptedData, passphrase);
      if (!mounted) return;
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
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: AppColors.tideLight, shape: BoxShape.circle),
                      child: Icon(Icons.lock_open_rounded, size: 18, color: AppColors.tide),
                    ),
                    const SizedBox(width: 12),
                    Text('Decrypted note', style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 16),
                Text(plaintext, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5)),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wrong passphrase or corrupted note')),
      );
    }
  }

  Future<void> _deleteItem(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete note?'),
        content: const Text('This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: AppColors.alert)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.delete('/vault/$id');
      await _loadItems();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  void dispose() {
    _passphraseController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vault')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: AppColors.tideLight, shape: BoxShape.circle),
                      child: Icon(Icons.lock_outline, size: 17, color: AppColors.tide),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text('A private space, just for you', style: Theme.of(context).textTheme.titleMedium)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Notes here are encrypted on this device before they ever leave it. '
                  'We only ever store the scrambled version - not even we can read it '
                  'without your passphrase, so keep it somewhere you\'ll remember.',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _passphraseController,
                  enabled: !_loading,
                  decoration: const InputDecoration(labelText: 'Passphrase', border: OutlineInputBorder()),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _noteController,
                  enabled: !_loading,
                  decoration: const InputDecoration(labelText: 'Write something private...', border: OutlineInputBorder()),
                  maxLines: 4,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _addNote,
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.lock, size: 17),
                    label: Text(_loading ? 'Encrypting...' : 'Encrypt & save'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Saved notes', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          if (_loadingItems)
            const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator()))
          else if (_items.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.line),
              ),
              child: Center(
                child: Text(
                  'Nothing saved yet. Anything you write above stays private to you.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            )
          else
            ...List.generate(_items.length, (i) {
              final item = _items[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _decryptAndShow(item['encrypted_data'] as String),
                    child: Container(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Icon(Icons.note_alt_outlined, size: 20, color: AppColors.tide),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item['label'] ?? 'Note', style: Theme.of(context).textTheme.bodyMedium),
                                const SizedBox(height: 2),
                                Text('Tap to decrypt', style: Theme.of(context).textTheme.labelSmall),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline, size: 19, color: AppColors.mutedText),
                            tooltip: 'Delete',
                            onPressed: () => _deleteItem(item['id'] as String),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
