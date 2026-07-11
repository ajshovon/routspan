// Headless end-to-end check of the OLAX driver against a real device.
// Usage: dart run tool/smoke_check.dart <host> <password> [ussd_code]
// The optional 3rd arg sends a real USSD request (a live, carrier-side write —
// omit it for a read-only run).
// (Dev tool only — password is passed as an arg, never hard-coded.)
// ignore_for_file: avoid_print
import 'package:routspan/core/errors.dart';
import 'package:routspan/data/models.dart';
import 'package:routspan/data/olax/olax_m100_client.dart';
import 'package:routspan/data/olax/zte_api_transport.dart';

Future<void> main(List<String> args) async {
  final host = args.isNotEmpty ? args[0] : '192.168.8.1';
  final pw = args.length > 1 ? args[1] : '';
  final ussdCode = args.length > 2 ? args[2] : null;
  final client = OlaxM100Client(host: host, config: ZteConfig.reqproc);
  try {
    print('→ login to $host …');
    await client.login(pw);
    print('✓ login OK');

    final s = await client.getStatus();
    print('✓ status: net=${s.networkType} bars=${s.signalBars} '
        'rssi=${s.rssiDbm} op=${s.operator} wan=${s.wanIp} '
        'sim=${s.simState.name} link=${s.wan.name} '
        'batt=lvl${s.batteryLevel}/${DeviceStatus.batteryLevelMax}'
        '(~${s.batteryApproxPercent}%)${s.batteryCharging == true ? '+chg' : ''}');

    final u = await client.getDataUsage();
    print('✓ usage: session=${u.sessionBytes}B monthly=${u.monthlyBytes}B '
        'time=${u.sessionDuration?.inSeconds}s ↑${u.txThroughput} ↓${u.rxThroughput} B/s '
        'limit=${u.limitEnabled ? (u.limitByTime ? 'time' : 'data') : 'off'}');

    print(
        '✓ signal: band=${s.band} rsrp=${s.rsrp} rsrq=${s.rsrq} sinr=${s.sinr} '
        'cell=${s.cellId} unread=${s.unreadSms} devices=${s.connectedCount}');

    final info = await client.getDeviceInfo();
    String mask(String? v) =>
        (v == null || v.length < 4) ? '$v' : '••••${v.substring(v.length - 4)}';
    print(
        '✓ device: model=${info.model} fw=${info.firmware} hw=${info.hardware} '
        'imei=${mask(info.imei)} phone=${mask(info.phoneNumber)} '
        'iccid=${mask(info.iccid)} lan=${info.lanIp} dhcp=${info.dhcpStart}-${info.dhcpEnd}');

    final w = await client.getWifi();
    print('✓ wifi: ssid=${w.ssid} band=${w.band} hidden=${w.hidden} '
        'sec=${w.authMode}/${w.encryptType} max=${w.maxDevices} '
        'pass=${w.password.isEmpty ? '(masked)' : 'len${w.password.length}'}');

    final devs = await client.getConnectedDevices();
    final devList = devs.map((d) => '${d.hostname}(${d.ipAddress})').join(', ');
    print('✓ devices: ${devs.length}${devs.isEmpty ? '' : ' — $devList'}');

    final sms = await client.listSms();
    print('✓ sms: ${sms.length} messages');
    for (final m in sms.take(3)) {
      final preview =
          m.content.length > 48 ? '${m.content.substring(0, 48)}…' : m.content;
      print('    [${m.id}] ${m.number} ${m.isRead ? '' : '(unread) '}$preview');
    }

    if (ussdCode != null) {
      print('→ sending USSD $ussdCode …');
      try {
        final u = await client.sendUssd(ussdCode);
        print('✓ ussd reply: ${u.content}');
      } on RouterException catch (e) {
        print('✗ ussd FAILED: ${e.message}');
      }
    }
  } on RouterException catch (e) {
    print('✗ FAILED: ${e.message}');
  } finally {
    client.dispose();
  }
}
