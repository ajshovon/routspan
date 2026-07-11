import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:routspan/data/models.dart';
import 'package:routspan/data/olax/olax_m100_client.dart';
import 'package:routspan/data/olax/zte_api_transport.dart';

/// Records every write and answers reads from a canned map, so we can assert
/// the exact goformId + params the OLAX driver sends without a real device.
class FakeTransport extends ZteApiTransport {
  FakeTransport(this.reads)
      : super(host: '127.0.0.1', config: ZteConfig.reqproc);

  final Map<String, dynamic> reads;
  final List<Map<String, String>> posts = [];

  Map<String, String> get lastPost => posts.last;

  @override
  Future<T> withReloginRetry<T>(Future<T> Function() action) => action();

  @override
  Future<Map<String, dynamic>> getMulti(List<String> cmds) async {
    return {for (final c in cmds) c: reads[c] ?? ''};
  }

  // Single-cmd reads whose device response is a whole object (e.g.
  // sms_capacity_info, station_list) — return the canned response as-is.
  @override
  Future<Map<String, dynamic>> get(String cmd) async =>
      Map<String, dynamic>.from(reads);

  @override
  Future<Map<String, dynamic>> getWithParams(
          Map<String, String> params) async =>
      reads;

  @override
  Future<Map<String, dynamic>> set(Map<String, String> form,
      {bool withAd = true}) async {
    posts.add(form);
    return {'result': 'success'};
  }
}

void main() {
  group('OlaxM100Client WiFi', () {
    test('getWifi decodes WPAPSK1_encode (base64) into the plaintext key',
        () async {
      // base64("TestPass1234") == "VGVzdFBhc3MxMjM0" (fixture values, not a real device).
      final t = FakeTransport({
        'SSID1': 'TestNetwork',
        'WPAPSK1_encode': 'VGVzdFBhc3MxMjM0',
        'WPAPSK1': 'TestPass1234',
        'AuthMode': 'WPA2PSK',
        'EncrypType': 'AES',
        'HideSSID': '0',
        'MAX_Access_num': '5',
        'wifi_band': 'b',
      });
      final client = OlaxM100Client(host: 'x', transport: t);

      final wifi = await client.getWifi();
      expect(wifi.ssid, 'TestNetwork');
      expect(wifi.password, 'TestPass1234');
      expect(wifi.authMode, 'WPA2PSK');
      expect(wifi.band, '2.4 GHz');
      expect(wifi.maxDevices, 5);
    });

    test('setWifi sends passphrase(base64) + security_shared_mode, not WPAPSK1',
        () async {
      final t = FakeTransport({});
      final client = OlaxM100Client(host: 'x', transport: t);

      await client.setWifi(const WifiConfig(
        ssid: 'NewNet',
        password: 'hunter2!',
        authMode: 'WPA2PSK',
        encryptType: 'AES',
        maxDevices: 5,
      ));

      final post = t.lastPost;
      expect(post['goformId'], 'SET_WIFI_SSID1_SETTINGS');
      expect(post['ssid'], 'NewNet');
      expect(post['security_mode'], 'WPA2PSK');
      expect(post['cipher'], '1'); // AES -> 1
      expect(post['security_shared_mode'], '1');
      expect(post['passphrase'], base64.encode(utf8.encode('hunter2!')));
      // The old, ignored parameter must not be sent.
      expect(post.containsKey('WPAPSK1'), isFalse);
    });
  });

  group('OlaxM100Client actions', () {
    test('setMobileData maps to CONNECT / DISCONNECT_NETWORK', () async {
      final t = FakeTransport({});
      final client = OlaxM100Client(host: 'x', transport: t);

      await client.setMobileData(true);
      expect(t.posts.last['goformId'], 'CONNECT_NETWORK');

      await client.setMobileData(false);
      expect(t.posts.last['goformId'], 'DISCONNECT_NETWORK');
    });

    test('renameDevice sends EDIT_HOSTNAME with mac + hostname', () async {
      final t = FakeTransport({});
      final client = OlaxM100Client(host: 'x', transport: t);

      await client.renameDevice('AA:BB:CC:DD:EE:FF', 'Laptop');
      expect(t.lastPost['goformId'], 'EDIT_HOSTNAME');
      expect(t.lastPost['mac'], 'AA:BB:CC:DD:EE:FF');
      expect(t.lastPost['hostname'], 'Laptop');
    });

    test('powerOff / factoryReset map to their goformIds', () async {
      final t = FakeTransport({});
      final client = OlaxM100Client(host: 'x', transport: t);

      await client.powerOff();
      expect(t.lastPost['goformId'], 'TURN_OFF_DEVICE');

      await client.factoryReset();
      expect(t.lastPost['goformId'], 'RESTORE_FACTORY_SETTINGS');
    });
  });

  group('OlaxM100Client battery', () {
    test(
        'battery_pers is a 0-4 bar level, not a percent; approx% derives from it',
        () async {
      final t = FakeTransport({'battery_pers': '3', 'battery_charging': '0'});
      final client = OlaxM100Client(host: 'x', transport: t);

      final s = await client.getStatus();
      expect(s.batteryLevel, 3); // 3 of 4 bars = "1 less than full"
      expect(s.batteryPercent, isNull); // battery_vol_percent empty on M100
      expect(s.batteryApproxPercent, 75);
    });

    test('a real battery_vol_percent takes priority when present', () async {
      final t =
          FakeTransport({'battery_pers': '4', 'battery_vol_percent': '82'});
      final client = OlaxM100Client(host: 'x', transport: t);

      final s = await client.getStatus();
      expect(s.batteryPercent, 82);
      expect(s.batteryApproxPercent, 82);
    });
  });

  group('OlaxM100Client connected devices', () {
    test(
        'edited hostNameList name overrides station_list DHCP name (by MAC, '
        'case-insensitive); falls back to DHCP name otherwise', () async {
      final t = FakeTransport({
        'station_list': [
          {
            'mac_addr': 'DE:AD:BE:EF:00:01',
            'hostname': 'Laptop', // DHCP name
            'ip_addr': '192.168.8.101',
            'dev_type': 'wifi',
            'ip_type': 'DHCP',
          },
          {
            'mac_addr': 'AA:BB:CC:00:11:22',
            'hostname': 'phone',
            'ip_addr': '192.168.8.102',
            'dev_type': 'wifi',
          },
        ],
        // Custom name set via EDIT_HOSTNAME (note lower-case MAC).
        'devices': [
          {'mac': 'de:ad:be:ef:00:01', 'hostname': 'My-Custom-Name'},
        ],
      });
      final client = OlaxM100Client(host: 'x', transport: t);

      final devs = await client.getConnectedDevices();
      expect(devs[0].hostname, 'My-Custom-Name'); // custom wins
      expect(devs[1].hostname, 'phone'); // no custom -> DHCP name
    });
  });
}
