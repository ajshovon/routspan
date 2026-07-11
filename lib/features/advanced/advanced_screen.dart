import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:routspan/core/errors.dart';
import 'package:routspan/features/common/async_view.dart';
import 'package:routspan/providers/session.dart';

/// M5 — USSD codes + reboot.
class AdvancedScreen extends ConsumerStatefulWidget {
  const AdvancedScreen({super.key});

  @override
  ConsumerState<AdvancedScreen> createState() => _AdvancedScreenState();
}

class _AdvancedScreenState extends ConsumerState<AdvancedScreen> {
  final _ussdCtl = TextEditingController(text: '*123#');
  String? _ussdResult;
  bool _ussdBusy = false;

  @override
  void dispose() {
    _ussdCtl.dispose();
    super.dispose();
  }

  Future<void> _sendUssd() async {
    setState(() {
      _ussdBusy = true;
      _ussdResult = null;
    });
    try {
      final res =
          await ref.read(repositoryProvider).sendUssd(_ussdCtl.text.trim());
      if (mounted) setState(() => _ussdResult = res.content);
    } on RouterException catch (e) {
      if (mounted) setState(() => _ussdResult = 'Error: ${e.message}');
    } finally {
      if (mounted) setState(() => _ussdBusy = false);
    }
  }

  Future<void> _reboot() async {
    final ok = await _confirm(
      title: 'Reboot router?',
      body:
          'The router will restart and all devices will lose connection for a minute or two.',
      action: 'Reboot',
    );
    if (ok != true || !mounted) return;
    await runAction(
      context,
      ref,
      () => ref.read(repositoryProvider).reboot(),
      success: 'Reboot command sent',
    );
  }

  Future<void> _powerOff() async {
    final ok = await _confirm(
      title: 'Power off router?',
      body:
          'The router will shut down. You will need to press its power button to turn it back on.',
      action: 'Power off',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    await runAction(
      context,
      ref,
      () => ref.read(repositoryProvider).powerOff(),
      success: 'Power-off command sent',
    );
  }

  Future<void> _factoryReset() async {
    final ok = await _confirm(
      title: 'Restore factory settings?',
      body:
          'This erases ALL settings — WiFi name/password, APN, and this admin password — and reboots the router. This cannot be undone.',
      action: 'Reset',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    await runAction(
      context,
      ref,
      () => ref.read(repositoryProvider).factoryReset(),
      success: 'Factory reset command sent',
    );
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                    foregroundColor: Theme.of(ctx).colorScheme.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('USSD code',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Run a carrier code, e.g. a balance check. Support depends on the '
                  "router's firmware — some models/builds don't allow USSD at all, "
                  "in which case you'll get a clear \"not supported\" message.",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ussdCtl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _ussdBusy ? null : _sendUssd,
                      child: _ussdBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Send'),
                    ),
                  ],
                ),
                if (_ussdBusy) ...[
                  const SizedBox(height: 12),
                  Text(
                      'Waiting for a reply from the network… this can take up to 30s.',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
                if (_ussdResult != null) ...[
                  const Divider(height: 24),
                  SelectableText(_ussdResult!),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.restart_alt),
                title: const Text('Reboot router'),
                subtitle: const Text('Restart the device'),
                onTap: _reboot,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.power_settings_new),
                title: const Text('Power off'),
                subtitle: const Text('Shut the device down'),
                onTap: _powerOff,
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.settings_backup_restore,
                    color: Theme.of(context).colorScheme.error),
                title: const Text('Factory reset'),
                subtitle: const Text('Erase all settings and reboot'),
                onTap: _factoryReset,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
