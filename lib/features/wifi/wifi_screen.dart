import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:routspan/data/router_repository.dart';
import 'package:routspan/features/common/async_view.dart';
import 'package:routspan/providers/features.dart';
import 'package:routspan/providers/session.dart';

/// M4 — WiFi settings + connected devices.
class WifiScreen extends ConsumerWidget {
  const WifiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wifi = ref.watch(wifiProvider);
    final devices = ref.watch(connectedDevicesProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(wifiProvider);
        ref.invalidate(connectedDevicesProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AsyncView<WifiConfig>(
            value: wifi,
            onRetry: () => ref.invalidate(wifiProvider),
            builder: (w) => _WifiCard(config: w),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Connected devices',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 6),
              devices.maybeWhen(
                data: (list) => Text('(${list.length})',
                    style: Theme.of(context).textTheme.bodySmall),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AsyncView<List<ConnectedDevice>>(
            value: devices,
            onRetry: () => ref.invalidate(connectedDevicesProvider),
            builder: (list) => list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No devices connected'),
                  )
                : Column(
                    children: [
                      for (final d in list) _deviceTile(context, ref, d),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _deviceTile(BuildContext context, WidgetRef ref, ConnectedDevice d) =>
      Card(
        child: ListTile(
          leading: Icon(_iconFor(d.deviceType)),
          title: Text(d.hostname),
          subtitle: Text('${d.ipAddress}\n${d.macAddress}'),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'rename') _renameDevice(context, ref, d);
            },
            itemBuilder: (_) => [
              if (d.macAddress.isNotEmpty)
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
              if (d.deviceType != null)
                PopupMenuItem(
                  enabled: false,
                  child: Text(d.deviceType!),
                ),
            ],
          ),
        ),
      );

  Future<void> _renameDevice(
      BuildContext context, WidgetRef ref, ConnectedDevice d) async {
    final ctl = TextEditingController(text: d.hostname);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename device'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runAction(
      context,
      ref,
      () => ref
          .read(repositoryProvider)
          .renameDevice(d.macAddress, ctl.text.trim()),
      success: 'Device renamed',
      refresh: connectedDevicesProvider,
    );
  }

  IconData _iconFor(String? type) {
    switch (type) {
      case 'usb':
        return Icons.usb;
      case 'rj45':
        return Icons.settings_ethernet;
      default:
        return Icons.wifi;
    }
  }
}

class _WifiCard extends ConsumerStatefulWidget {
  const _WifiCard({required this.config});
  final WifiConfig config;

  @override
  ConsumerState<_WifiCard> createState() => _WifiCardState();
}

class _WifiCardState extends ConsumerState<_WifiCard> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wifi),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(config.ssid,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Edit WiFi',
                  onPressed: () => _edit(context, ref),
                ),
              ],
            ),
            const Divider(height: 20),
            if (config.band != null) _kv(context, 'Band', config.band!),
            if (config.authMode != null && config.authMode!.isNotEmpty)
              _kv(context, 'Security', _securityLabel(config)),
            _kv(context, 'Hidden', config.hidden ? 'Yes' : 'No'),
            if (config.maxDevices != null)
              _kv(context, 'Max devices', '${config.maxDevices}'),
            if (config.guestEnabled) _kv(context, 'Guest network', 'On'),
            _passwordRow(context, config.password),
          ],
        ),
      ),
    );
  }

  Widget _passwordRow(BuildContext context, String password) {
    final hasPassword = password.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Text('Password'),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              !hasPassword
                  ? '•••••• (hidden by device)'
                  : (_revealed ? password : '•' * password.length.clamp(1, 12)),
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontFamily: 'monospace'),
            ),
          ),
          if (hasPassword) ...[
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: _revealed ? 'Hide' : 'Reveal',
              icon: Icon(_revealed ? Icons.visibility_off : Icons.visibility,
                  size: 20),
              onPressed: () => setState(() => _revealed = !_revealed),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Copy',
              icon: const Icon(Icons.copy, size: 20),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: password));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password copied')),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  String _securityLabel(WifiConfig c) {
    final mode = c.authMode ?? '';
    final enc = (c.encryptType == null || c.encryptType!.isEmpty)
        ? ''
        : ' · ${c.encryptType}';
    return '$mode$enc';
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k),
            Flexible(
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final config = widget.config;
    final ssidCtl = TextEditingController(text: config.ssid);
    final passCtl = TextEditingController(text: config.password);
    var hidden = config.hidden;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Edit WiFi'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ssidCtl,
                decoration:
                    const InputDecoration(labelText: 'Network name (SSID)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passCtl,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hide network'),
                value: hidden,
                onChanged: (v) => setLocal(() => hidden = v),
              ),
              Text(
                'Saving disconnects devices currently on this WiFi (including this app if it is joined over WiFi).',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await runAction(
      context,
      ref,
      () => ref.read(repositoryProvider).setWifi(
            config.copyWith(
              ssid: ssidCtl.text.trim(),
              password: passCtl.text,
              hidden: hidden,
            ),
          ),
      success: 'WiFi updated',
      refresh: wifiProvider,
    );
  }
}
