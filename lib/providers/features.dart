import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:routspan/data/router_repository.dart';
import 'package:routspan/providers/session.dart';

/// SMS inbox (all boxes). Invalidate to refresh after send/delete/mark-read.
final smsListProvider = FutureProvider.autoDispose<List<SmsMessage>>((ref) {
  return ref.watch(repositoryProvider).listSms();
});

/// The inbox grouped into per-number conversations, derived from
/// [smsListProvider] so both share a single fetch. Invalidate [smsListProvider]
/// to refresh.
final smsConversationsProvider =
    Provider.autoDispose<AsyncValue<List<SmsConversation>>>((ref) {
  return ref.watch(smsListProvider).whenData(groupSmsIntoConversations);
});

/// A single conversation by number, tracked live so a thread view updates after
/// sending/deleting. Returns null once the conversation has no messages left.
final smsConversationProvider = Provider.autoDispose
    .family<AsyncValue<SmsConversation?>, String>((ref, number) {
  return ref.watch(smsConversationsProvider).whenData((convos) {
    for (final c in convos) {
      if (c.number == number) return c;
    }
    return null;
  });
});

/// SMS storage usage for the capacity indicator.
final smsCapacityProvider = FutureProvider.autoDispose<SmsCapacity>((ref) {
  return ref.watch(repositoryProvider).getSmsCapacity();
});

/// Primary WiFi configuration.
final wifiProvider = FutureProvider.autoDispose<WifiConfig>((ref) {
  return ref.watch(repositoryProvider).getWifi();
});

/// Devices currently connected to the router.
final connectedDevicesProvider =
    FutureProvider.autoDispose<List<ConnectedDevice>>((ref) {
  return ref.watch(repositoryProvider).getConnectedDevices();
});

/// Device identity + LAN details for the About screen.
final deviceInfoProvider = FutureProvider.autoDispose<DeviceInfo>((ref) {
  return ref.watch(repositoryProvider).getDeviceInfo();
});
