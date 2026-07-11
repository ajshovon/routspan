import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:routspan/core/errors.dart';
import 'package:routspan/core/formatting.dart';
import 'package:routspan/data/models.dart';
import 'package:routspan/providers/session.dart';

/// M1/M2 screen: proves the whole stack by showing live authenticated reads.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Timer? _timer;

  /// True while a CONNECT/DISCONNECT_NETWORK request is in flight — pauses the
  /// switch so the poll and the pending action don't fight each other.
  bool _dataBusy = false;

  @override
  void initState() {
    super.initState();
    // Poll every 5s while this screen is mounted (skip while a toggle is busy).
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_dataBusy) return;
      ref.invalidate(statusProvider);
      ref.invalidate(dataUsageProvider);
    });
  }

  Future<void> _toggleMobileData(bool enabled) async {
    setState(() => _dataBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(repositoryProvider).setMobileData(enabled);
      // Give the modem a moment to change ppp_status, then refresh.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      ref.invalidate(statusProvider);
      ref.invalidate(dataUsageProvider);
    } on RouterException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _dataBusy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(statusProvider);
    final usage = ref.watch(dataUsageProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(statusProvider);
        ref.invalidate(dataUsageProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _mobileDataCard(status),
          const SizedBox(height: 12),
          status.when(
            data: _statusCard,
            error: (e, _) => _errorCard(context, '$e'),
            loading: () => const _LoadingCard(label: 'Reading status…'),
          ),
          const SizedBox(height: 12),
          usage.when(
            data: _usageCard,
            error: (e, _) => _errorCard(context, '$e'),
            loading: () => const _LoadingCard(label: 'Reading data usage…'),
          ),
        ],
      ),
    );
  }

  Widget _mobileDataCard(AsyncValue<DeviceStatus> status) {
    final wan = status.valueOrNull?.wan ?? WanState.unknown;
    final on = wan == WanState.connected;
    final transitioning = _dataBusy ||
        wan == WanState.connecting ||
        wan == WanState.disconnecting;

    final subtitle = switch (wan) {
      WanState.connected => 'Connected',
      WanState.disconnected => 'Disconnected',
      WanState.connecting => 'Connecting…',
      WanState.disconnecting => 'Disconnecting…',
      WanState.unknown => status.hasError ? 'Unavailable' : 'Checking…',
    };

    return Card(
      child: ListTile(
        leading: Icon(
          on ? Icons.cloud_done : Icons.cloud_off,
          color: on ? Theme.of(context).colorScheme.primary : null,
        ),
        title: const Text('Mobile data'),
        subtitle: Text(subtitle),
        trailing: transitioning
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Switch(
                value: on,
                // Don't allow toggling until we know the real state.
                onChanged:
                    (status.valueOrNull == null || wan == WanState.unknown)
                        ? null
                        : _toggleMobileData,
              ),
      ),
    );
  }

  Widget _statusCard(DeviceStatus s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  s.wan == WanState.connected
                      ? Icons.signal_cellular_alt
                      : Icons.signal_cellular_off,
                ),
                const SizedBox(width: 8),
                Text(s.networkType,
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                _SignalBars(bars: s.signalBars),
              ],
            ),
            const Divider(height: 24),
            _kv('Operator', s.operator),
            _kv('Connection', s.wan.name),
            _kv('SIM', s.simState.name),
            if (s.roaming) _kv('Roaming', 'Yes'),
            if (s.band != null) _kv('Band', s.band!),
            if (s.rssiDbm != null) _kv('RSSI', '${s.rssiDbm} dBm'),
            if (s.rsrp != null) _kv('RSRP', '${s.rsrp} dBm'),
            if (s.rsrq != null) _kv('RSRQ', '${s.rsrq} dB'),
            if (s.sinr != null) _kv('SINR', '${s.sinr} dB'),
            if (s.cellId != null) _kv('Cell ID', s.cellId!),
            if (s.wanIp != null && s.wanIp!.isNotEmpty) _kv('WAN IP', s.wanIp!),
            if (_batteryText(s) != null) _kv('Battery', _batteryText(s)!),
          ],
        ),
      ),
    );
  }

  Widget _usageCard(DataUsage u) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Data usage', style: Theme.of(context).textTheme.titleMedium),
            const Divider(height: 24),
            _kv('This session', formatBytes(u.sessionBytes)),
            _kv('This month', formatBytes(u.monthlyBytes)),
            _kv('Live speed',
                '↓ ${formatBytes(u.rxThroughput)}/s   ↑ ${formatBytes(u.txThroughput)}/s'),
            if (u.sessionDuration != null)
              _kv('Session time', _fmtDuration(u.sessionDuration!)),
            if (u.monthlyDuration != null)
              _kv('Month time', _fmtDuration(u.monthlyDuration!)),
            if (u.limitEnabled)
              _kv(
                'Monthly ${u.limitByTime ? 'time' : 'data'} limit',
                u.limitByTime
                    ? (u.limitSize == null
                        ? 'On'
                        : _fmtDuration(Duration(seconds: u.limitSize!)))
                    : (u.limitSize == null ? 'On' : formatBytes(u.limitSize!)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(BuildContext context, String message) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error_outline),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: Theme.of(context).textTheme.bodyMedium),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return '${h}h ${m}m';
  }

  /// The M100 only reports a 0–4 bar level (`battery_pers`), not a true percent,
  /// so show the bars plus an approximation. Models that expose a real percent
  /// show that instead.
  String? _batteryText(DeviceStatus s) {
    final suffix = s.batteryCharging == true ? ' · charging' : '';
    if (s.batteryPercent != null) return '${s.batteryPercent}%$suffix';
    if (s.batteryLevel != null) {
      return '~${s.batteryApproxPercent}%  (${s.batteryLevel}/${DeviceStatus.batteryLevelMax})$suffix';
    }
    return s.batteryCharging == true ? 'Charging' : null;
  }
}

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.bars});
  final int bars;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final active = i < bars;
        return Container(
          width: 5,
          height: 8.0 + i * 3,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: active
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).disabledColor,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(label),
          ],
        ),
      ),
    );
  }
}
