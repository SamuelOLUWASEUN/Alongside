import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/crisis_resources.dart';
import '../widgets/sign_out_dialog.dart';
import '../widgets/profile_sheet.dart';
import '../services/theme_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _exporting = false;

  Future<void> _exportData() async {
    setState(() => _exporting = true);
    try {
      final data = await ApiService.get('/export') as Map<String, dynamic>;
      final moods = (data['moods'] as List<dynamic>?) ?? [];

      int? avg;
      DateTime? earliest, latest;
      if (moods.isNotEmpty) {
        final scores = moods.map((m) => (m['score'] as num).toInt()).toList();
        avg = (scores.reduce((a, b) => a + b) / scores.length).round();
        final times = moods
            .map((m) => DateTime.tryParse(m['time'] as String))
            .whereType<DateTime>()
            .toList()
          ..sort();
        if (times.isNotEmpty) {
          earliest = times.first;
          latest = times.last;
        }
      }

      if (!mounted) return;
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
                Text('Your data at a glance', style: Theme.of(dialogContext).textTheme.headlineSmall),
                const SizedBox(height: 16),
                if (moods.isEmpty)
                  Text(
                    "You haven't logged any check-ins yet.",
                    style: Theme.of(dialogContext).textTheme.bodyMedium,
                  )
                else ...[
                  _ExportStatRow(label: 'Mood check-ins', value: '${moods.length}'),
                  if (avg != null) _ExportStatRow(label: 'Average mood', value: '$avg / 10'),
                  if (earliest != null && latest != null)
                    _ExportStatRow(
                      label: 'Date range',
                      value: '${DateFormat('MMM d, y').format(earliest.toLocal())} – ${DateFormat('MMM d, y').format(latest.toLocal())}',
                    ),
                ],
                const SizedBox(height: 8),
                Text(
                  'This covers your mood check-ins. Vault notes stay encrypted and aren\'t '
                  'included here even in summary form.',
                  style: Theme.of(dialogContext).textTheme.labelSmall,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final pretty = const JsonEncoder.withIndent('  ').convert(data);
                      await Clipboard.setData(ClipboardData(text: pretty));
                      if (dialogContext.mounted) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(content: Text('Raw data (JSON) copied to clipboard')),
                        );
                      }
                    },
                    icon: const Icon(Icons.code, size: 16),
                    label: const Text('Copy raw data (JSON)'),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not export: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _handleSignOut() async {
    final confirmed = await confirmSignOut(context);
    if (confirmed && mounted) {
      context.read<AuthService>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final theme = context.watch<ThemeController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Account
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => showProfileSheet(context),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.tide,
                    child: Text(
                      (auth.email ?? '?').isNotEmpty ? auth.email![0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(auth.email ?? '', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text('Signed in · tap to view', style: Theme.of(context).textTheme.labelSmall),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppColors.mutedText, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          _SectionLabel('Appearance'),
          _SettingsCard(
            children: [
              _SettingsRow(
                icon: theme.isDark ? Icons.dark_mode : Icons.light_mode_outlined,
                title: 'Dark mode',
                subtitle: theme.isDark ? 'On' : 'Off',
                trailing: Switch(
                  value: theme.isDark,
                  onChanged: (v) => context.read<ThemeController>().setDark(v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          _SectionLabel('Privacy & security'),
          _SettingsCard(
            children: [
              _SettingsRow(
                icon: Icons.fingerprint,
                title: 'Biometric lock',
                subtitle: 'Coming soon',
                trailing: Switch(value: false, onChanged: null),
              ),
              const _RowDivider(),
              _SettingsRow(
                icon: Icons.download_outlined,
                title: 'Export my data',
                subtitle: 'See a summary of what Alongside has stored for you',
                trailing: _exporting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.chevron_right, color: AppColors.mutedText, size: 20),
                onTap: _exporting ? null : _exportData,
              ),
            ],
          ),
          const SizedBox(height: 20),

          _SectionLabel('Support'),
          _SettingsCard(
            children: [
              _SettingsRow(
                icon: Icons.favorite_border,
                title: 'Crisis resources',
                subtitle: 'Helplines and immediate support',
                trailing: Icon(Icons.chevron_right, color: AppColors.mutedText, size: 20),
                onTap: () => showCrisisResourcesDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 20),

          _SectionLabel('Account'),
          _SettingsCard(
            children: [
              _SettingsRow(
                icon: Icons.logout,
                title: 'Sign out',
                iconColor: AppColors.alert,
                titleColor: AppColors.alert,
                onTap: _handleSignOut,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExportStatRow extends StatelessWidget {
  final String label;
  final String value;
  const _ExportStatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText)),
          Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(color: AppColors.mutedText, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(children: children),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();
  @override
  Widget build(BuildContext context) => const Divider(height: 1, indent: 54);
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? titleColor;

  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor ?? AppColors.tide),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: titleColor, fontWeight: FontWeight.w600),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: Theme.of(context).textTheme.labelSmall),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
