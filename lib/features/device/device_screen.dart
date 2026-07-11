import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:routspan/core/app_info.dart';
import 'package:routspan/core/errors.dart';
import 'package:routspan/providers/features.dart';

/// Device / About: identity, SIM, LAN details, and app/legal info.
class DeviceScreen extends ConsumerWidget {
  const DeviceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(deviceInfoProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(deviceInfoProvider),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          ...info.when(
            data: (d) => [
              _section(context, 'Device', [
                _row('Model', d.model),
                _row('Firmware', d.firmware),
                _row('Hardware', d.hardware),
                _row('IMEI', d.imei),
              ]),
              _section(context, 'SIM', [
                _row('Phone number', d.phoneNumber),
                _row('IMSI', d.imsi),
                _row('ICCID', d.iccid),
              ]),
              _section(context, 'Network (LAN)', [
                _row('Router IP', d.lanIp),
                _row('Subnet mask', d.lanNetmask),
                _row('Local domain', d.localDomain),
                _row('Max devices', d.maxDevices?.toString()),
                _row(
                    'DHCP',
                    d.dhcpEnabled == null
                        ? null
                        : (d.dhcpEnabled! ? 'On' : 'Off')),
                if (d.dhcpEnabled == true)
                  _row(
                      'DHCP range',
                      (d.dhcpStart == null || d.dhcpEnd == null)
                          ? null
                          : '${d.dhcpStart} – ${d.dhcpEnd}'),
                if (d.dhcpEnabled == true)
                  _row(
                      'Lease',
                      d.dhcpLeaseHours == null
                          ? null
                          : '${d.dhcpLeaseHours} h'),
              ]),
            ],
            loading: () => const [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
            error: (e, _) => [
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(e is RouterException ? e.message : '$e')),
                      TextButton(
                        onPressed: () => ref.invalidate(deviceInfoProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          _aboutSection(context),
        ],
      ),
    );
  }

  Widget _aboutSection(BuildContext context) {
    final muted = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, size: 20),
                const SizedBox(width: 8),
                Text('About', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const Divider(height: 20),
            const Text('${AppInfo.name} ${AppInfo.version}',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(AppInfo.licenseSummary,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Text(AppInfo.trademarkNotice, style: muted),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.description_outlined),
                label: const Text('Open-source licenses'),
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: AppInfo.name,
                  applicationVersion: AppInfo.version,
                  applicationLegalese: AppInfo.legalese,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<_Row> rows) {
    final visible = rows.where((r) => r.value != null).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const Divider(height: 20),
            for (final r in visible)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(r.label,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                    Expanded(
                      child: SelectableText(
                        r.value!,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  _Row _row(String label, String? value) => _Row(label, value);
}

class _Row {
  const _Row(this.label, this.value);
  final String label;
  final String? value;
}
