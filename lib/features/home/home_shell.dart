import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:routspan/features/advanced/advanced_screen.dart';
import 'package:routspan/features/dashboard/dashboard_screen.dart';
import 'package:routspan/features/device/device_screen.dart';
import 'package:routspan/features/sms/sms_screen.dart';
import 'package:routspan/features/wifi/wifi_screen.dart';
import 'package:routspan/providers/features.dart';
import 'package:routspan/providers/session.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _pages = [
    DashboardScreen(),
    SmsScreen(),
    WifiScreen(),
    AdvancedScreen(),
    DeviceScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final label = ref.watch(sessionControllerProvider.select((s) => s.label));
    // The dashboard keeps statusProvider warm; reuse its unread count for the badge.
    final unread = ref.watch(statusProvider).valueOrNull?.unreadSms ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(label),
        actions: [
          IconButton(
            tooltip: 'Disconnect',
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(sessionControllerProvider.notifier).disconnect(),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.dashboard), label: 'Status'),
          NavigationDestination(
            icon: Badge(
              label: Text('$unread'),
              isLabelVisible: unread > 0,
              child: const Icon(Icons.sms),
            ),
            label: 'SMS',
          ),
          NavigationDestination(
            icon: Badge(
              backgroundColor: Theme.of(context).colorScheme.primary,
              textColor: Theme.of(context).colorScheme.onPrimary,
              label: Text(
                '${ref.watch(connectedDevicesProvider).valueOrNull?.length ?? 0}',
              ),
              isLabelVisible:
                  (ref.watch(connectedDevicesProvider).valueOrNull?.length ?? 0) > 0,
              child: const Icon(Icons.wifi),
            ),
            label: 'WiFi',
          ),
          const NavigationDestination(
              icon: Icon(Icons.tune), label: 'Advanced'),
          const NavigationDestination(
              icon: Icon(Icons.info_outline), label: 'Device'),
        ],
      ),
    );
  }
}
