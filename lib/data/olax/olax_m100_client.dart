import 'dart:convert';

import 'package:routspan/core/errors.dart';
import 'package:routspan/core/formatting.dart';
import 'package:routspan/core/sms_codec.dart';
import 'package:routspan/data/router_repository.dart';
import 'package:routspan/data/olax/zte_api_transport.dart';

/// OLAX M100 driver: the only [RouterRepository] implementation today.
///
/// Every command name and field below was VERIFIED on a real M100 (firmware
/// M100LSW1.1_..._V01.01.02P42U28_07) by reading the device's own JavaScript
/// and capturing live `/reqproc` responses. See `docs/olax-m100-api.md`.
class OlaxM100Client implements RouterRepository {
  OlaxM100Client({
    required String host,
    ZteConfig? config,
    ZteApiTransport? transport,
    // Test seams for the USSD poll loop so unit tests don't need to wait on
    // real wall-clock seconds. Not part of the public contract.
    Duration ussdPollInterval = const Duration(seconds: 1),
    int ussdPollMaxAttempts = 30,
  })  : _t = transport ??
            ZteApiTransport(host: host, config: config ?? ZteConfig.reqproc),
        _ussdPollInterval = ussdPollInterval,
        _ussdPollMaxAttempts = ussdPollMaxAttempts;

  final ZteApiTransport _t;
  final Duration _ussdPollInterval;
  final int _ussdPollMaxAttempts;

  // --- Read command names (cmd=) --------------------------------------------
  static const _statusCmds = [
    'network_type',
    'sub_network_type',
    'rssi',
    'lte_rsrp',
    'signalbar',
    'network_provider',
    'ppp_status',
    'modem_main_state', // SIM/modem readiness (sim_status is empty on this model)
    'simcard_roam', // "Home" | "Roaming"
    'battery_pers', // 0..4 bar LEVEL (NOT a percent) — drives the icon
    'battery_vol_percent', // true % if the model reports it (empty on M100)
    'battery_charging',
    'wan_ipaddr',
    'nv_rsrq',
    'nv_sinr',
    'lte_band',
    'cell_id',
    'sms_unread_num',
    'sta_count',
  ];
  static const _deviceInfoCmds = [
    'imei',
    'sim_imsi',
    'ziccid',
    'msisdn',
    'cr_version',
    'hw_version',
    'lan_ipaddr',
    'lan_netmask',
    'LocalDomain',
    'MAX_Access_num',
    'dhcpEnabled',
    'dhcpStart',
    'dhcpEnd',
    'dhcpLease_hour',
  ];
  static const _dataCmds = [
    'realtime_tx_bytes',
    'realtime_rx_bytes',
    'realtime_time',
    'realtime_tx_thrpt',
    'realtime_rx_thrpt',
    'monthly_tx_bytes',
    'monthly_rx_bytes',
    'monthly_time',
    'data_volume_limit_switch',
    'data_volume_limit_size',
    'data_volume_limit_unit', // "data" | "time" | "0" when off
    'data_volume_alert_percent',
  ];
  // WPAPSK1_encode is base64(password); WPAPSK1 is the plaintext fallback. The
  // older WPAPSK1_ENCRYPT field is always empty on this firmware. AuthMode +
  // EncrypType are read so a save preserves the existing security.
  static const _wifiCmds = [
    'SSID1',
    'WPAPSK1_encode',
    'WPAPSK1',
    'AuthMode',
    'EncrypType',
    'HideSSID',
    'm_ssid_enable',
    'MAX_Access_num',
    'wifi_band',
  ];

  @override
  Future<void> login(String password) => _t.login(password);

  @override
  Future<void> logout() => _t.set({'goformId': 'LOGOUT'}).then((_) {});

  @override
  Future<bool> isLoggedIn() => _t.isLoggedIn();

  @override
  Future<DeviceStatus> getStatus() async {
    final d = await _t.withReloginRetry(() => _t.getMulti(_statusCmds));
    final sub = d['sub_network_type']?.toString() ?? '';
    final net = d['network_type']?.toString() ?? '—';
    return DeviceStatus(
      networkType: sub.isNotEmpty ? sub.replaceAll('_', ' ') : net,
      signalBars: parseIntSafe(d['signalbar']).clamp(0, 5),
      rssiDbm: parseIntOrNull(d['rssi']),
      operator: d['network_provider']?.toString() ?? '—',
      roaming: d['simcard_roam']?.toString() == 'Roaming',
      wan: _wanState(d['ppp_status']?.toString()),
      simState: _simState(d['modem_main_state']?.toString()),
      wanIp: d['wan_ipaddr']?.toString(),
      batteryPercent: parseIntOrNull(d['battery_vol_percent']),
      batteryLevel: _batteryLevel(d['battery_pers']),
      batteryCharging: d['battery_charging']?.toString() == '1',
      rsrp: parseIntOrNull(d['lte_rsrp']),
      rsrq: parseIntOrNull(d['nv_rsrq']),
      sinr: parseIntOrNull(d['nv_sinr']),
      band: _lteBand(d['lte_band']?.toString()),
      cellId: (d['cell_id']?.toString().isNotEmpty ?? false)
          ? d['cell_id'].toString()
          : null,
      unreadSms: parseIntSafe(d['sms_unread_num']),
      connectedCount: parseIntSafe(d['sta_count']),
    );
  }

  @override
  Future<DeviceInfo> getDeviceInfo() async {
    final d = await _t.withReloginRetry(() => _t.getMulti(_deviceInfoCmds));
    String? s(String k) {
      final v = d[k]?.toString();
      return (v == null || v.isEmpty) ? null : v;
    }

    return DeviceInfo(
      model: 'OLAX M100',
      firmware: s('cr_version'),
      hardware: s('hw_version'),
      imei: s('imei'),
      imsi: s('sim_imsi'),
      iccid: s('ziccid'),
      phoneNumber: s('msisdn'),
      lanIp: s('lan_ipaddr'),
      lanNetmask: s('lan_netmask'),
      localDomain: s('LocalDomain'),
      maxDevices: parseIntOrNull(d['MAX_Access_num']),
      dhcpEnabled: d['dhcpEnabled']?.toString() == '1',
      dhcpStart: s('dhcpStart'),
      dhcpEnd: s('dhcpEnd'),
      dhcpLeaseHours: parseIntOrNull(d['dhcpLease_hour']),
    );
  }

  @override
  Future<DataUsage> getDataUsage() async {
    final d = await _t.withReloginRetry(() => _t.getMulti(_dataCmds));
    final secs = parseIntSafe(d['realtime_time']);
    final monthSecs = parseIntSafe(d['monthly_time']);
    return DataUsage(
      sessionBytes: parseIntSafe(d['realtime_tx_bytes']) +
          parseIntSafe(d['realtime_rx_bytes']),
      monthlyBytes: parseIntSafe(d['monthly_tx_bytes']) +
          parseIntSafe(d['monthly_rx_bytes']),
      sessionDuration: secs > 0 ? Duration(seconds: secs) : null,
      monthlyDuration: monthSecs > 0 ? Duration(seconds: monthSecs) : null,
      txThroughput: parseIntSafe(d['realtime_tx_thrpt']),
      rxThroughput: parseIntSafe(d['realtime_rx_thrpt']),
      limitEnabled: d['data_volume_limit_switch']?.toString() == '1',
      limitByTime: d['data_volume_limit_unit']?.toString() == 'time',
      limitSize: parseIntOrNull(d['data_volume_limit_size']),
      alertPercent: parseIntOrNull(d['data_volume_alert_percent']),
    );
  }

  @override
  Future<List<SmsMessage>> listSms() async {
    // cmd=sms_data_total returns { messages: [ {id, number, content(hex),
    // tag, date, draft_group_id} ] }. tags=10 requests all boxes.
    final d = await _t.withReloginRetry(() => _t.getWithParams({
          'cmd': 'sms_data_total',
          'page': '0',
          'data_per_page': '500',
          'mem_store': '1',
          'tags': '10',
          'order_by': 'order by id desc',
        }));
    final raw = d['messages'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((m) {
      final tag =
          parseIntSafe(m['tag']); // 0 read,1 unread,2 sent,3 draft,4 fail
      return SmsMessage(
        id: parseIntSafe(m['id']),
        number: m['number']?.toString() ?? '',
        content: decodeUcs2Hex(m['content']?.toString() ?? ''),
        timestamp: _parseZteDate(m['date']?.toString()),
        isRead: tag != 1,
        isSent: tag == 2,
        isDraft: tag == 3,
      );
    }).toList();
  }

  @override
  Future<SmsCapacity> getSmsCapacity() async {
    final d = await _t.withReloginRetry(() => _t.get('sms_capacity_info'));
    return SmsCapacity(
      deviceUsed: parseIntSafe(d['sms_nv_rev_total']) +
          parseIntSafe(d['sms_nv_send_total']) +
          parseIntSafe(d['sms_nv_draftbox_total']),
      deviceTotal: parseIntSafe(d['sms_nv_total']),
      simUsed: parseIntSafe(d['sms_sim_rev_total']) +
          parseIntSafe(d['sms_sim_send_total']) +
          parseIntSafe(d['sms_sim_draftbox_total']),
      simTotal: parseIntSafe(d['sms_sim_total']),
    );
  }

  @override
  Future<void> sendSms(String number, String message) async {
    final res = await _t.set({
      'goformId': 'SEND_SMS',
      'notCallback': 'true',
      'Number': number,
      'sms_time': _zteNow(),
      'MessageBody': encodeUcs2Hex(message),
      'ID': '-1',
      'encode_type': 'UNICODE',
    });
    _ensureOk(res, 'send SMS');
  }

  @override
  Future<void> deleteSms(List<int> ids) async {
    final res = await _t.set({
      'goformId': 'DELETE_SMS',
      'msg_id': '${ids.join(';')};',
      'notCallback': 'true',
    });
    _ensureOk(res, 'delete SMS');
  }

  @override
  Future<void> markSmsRead(List<int> ids) async {
    if (ids.isEmpty) return;
    final res = await _t.set({
      'goformId': 'SET_MSG_READ',
      'msg_id': '${ids.join(';')};',
      'tag': '0',
    });
    _ensureOk(res, 'mark SMS read');
  }

  @override
  Future<WifiConfig> getWifi() async {
    final d = await _t.withReloginRetry(() => _t.getMulti(_wifiCmds));
    return WifiConfig(
      ssid: d['SSID1']?.toString() ?? '',
      password: _decodeWifiPassword(
        d['WPAPSK1_encode']?.toString(),
        d['WPAPSK1']?.toString(),
      ),
      band: _bandLabel(d['wifi_band']?.toString()),
      hidden: d['HideSSID']?.toString() == '1',
      enabled: true, // SSID1 is the always-on primary radio
      authMode: d['AuthMode']?.toString(),
      encryptType: d['EncrypType']?.toString(),
      maxDevices: parseIntOrNull(d['MAX_Access_num']),
      guestEnabled: d['m_ssid_enable']?.toString() == '1',
    );
  }

  @override
  Future<void> setWifi(WifiConfig config) async {
    // SET_WIFI_SSID1_SETTINGS carries the whole SSID1 config, INCLUDING the
    // password — the firmware reads it from `passphrase` (base64), and needs
    // `security_shared_mode` set alongside `cipher` for WPA modes. (The older
    // `WPAPSK1` param this app used to send is silently ignored, which is why
    // password changes never took effect.) Replicates the stock web UI's write.
    // Note: changing SSID/password disconnects clients joined over WiFi.
    final authMode =
        (config.authMode?.isNotEmpty ?? false) ? config.authMode! : 'WPA2PSK';
    final cipher = _cipherFor(config.encryptType);
    final form = <String, String>{
      'goformId': 'SET_WIFI_SSID1_SETTINGS',
      'ssid': config.ssid,
      'broadcastSsidEnabled': config.hidden ? '0' : '1',
      'MAX_Access_num': (config.maxDevices ?? 5).toString(),
      'security_mode': authMode,
      'cipher': cipher,
      'NoForwarding': '0',
      'show_qrcode_flag': '1',
    };
    if (_wpaModes.contains(authMode)) {
      form['security_shared_mode'] = cipher;
      form['passphrase'] = base64.encode(utf8.encode(config.password));
    }
    final res = await _t.set(form);
    _ensureOk(res, 'update WiFi');
  }

  @override
  Future<List<ConnectedDevice>> getConnectedDevices() async {
    // `station_list` reports the DHCP hostname; names edited via EDIT_HOSTNAME
    // are stored separately in `hostNameList` (keyed by MAC). Read both and let
    // the custom name win, matching the stock UI.
    final (stations, hosts) = await _t.withReloginRetry(() async {
      final s = await _t.get('station_list');
      final h = await _t.get('hostNameList');
      return (s, h);
    });

    final customNames = <String, String>{};
    final hostRaw = hosts['hostNameList'] ?? hosts['devices'];
    if (hostRaw is List) {
      for (final h in hostRaw.whereType<Map>()) {
        final mac = h['mac']?.toString();
        final name = h['hostname']?.toString();
        if (mac != null && mac.isNotEmpty && name != null && name.isNotEmpty) {
          customNames[mac.toUpperCase()] = name;
        }
      }
    }

    final raw = stations['station_list'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((m) {
      final mac = m['mac_addr']?.toString() ?? '';
      final dhcpName = m['hostname']?.toString() ?? '';
      final custom = customNames[mac.toUpperCase()];
      return ConnectedDevice(
        hostname: (custom != null && custom.isNotEmpty)
            ? custom
            : (dhcpName.isNotEmpty ? dhcpName : (mac.isNotEmpty ? mac : '—')),
        ipAddress: m['ip_addr']?.toString() ?? '',
        macAddress: mac,
        deviceType: m['dev_type']?.toString(),
        connectTime: m['connect_time']?.toString(),
        ipType: m['ip_type']?.toString(),
      );
    }).toList();
  }

  @override
  Future<void> renameDevice(String mac, String hostname) async {
    final res = await _t.set({
      'goformId': 'EDIT_HOSTNAME',
      'mac': mac,
      'hostname': hostname,
    });
    _ensureOk(res, 'rename device');
  }

  @override
  Future<void> setMobileData(bool enabled) async {
    // CONNECT_NETWORK / DISCONNECT_NETWORK reply {"result":"success"}. This only
    // toggles the cellular WAN; the LAN we're talking over stays up.
    final res = await _t.set({
      'goformId': enabled ? 'CONNECT_NETWORK' : 'DISCONNECT_NETWORK',
      'notCallback': 'true',
    });
    _ensureOk(res, enabled ? 'connect mobile data' : 'disconnect mobile data');
  }

  @override
  Future<UssdResult> sendUssd(String code) async {
    final res = await _t.set({
      'goformId': 'USSD_PROCESS',
      'USSD_operator': 'ussd_send',
      'USSD_send_number': code,
      'notCallback': 'true',
    });
    _ensureOk(res, 'send USSD');

    // Poll `ussd_write_flag` ALONE. Verified live: the reply fields
    // (`ussd_data`/`ussd_action`/`ussd_dcs`) only populate when `ussd_data_info`
    // is queried by itself — combining it with `ussd_write_flag` in one
    // multi-read (what this used to do) always comes back empty, so a real
    // reply was silently missed and every call fell through to "(no response)".
    // "15" means still waiting on the carrier; every other value is terminal
    // (firmware's own USSD page logic — see docs/olax-m100-api.md).
    for (var i = 0; i < _ussdPollMaxAttempts; i++) {
      await Future<void>.delayed(_ussdPollInterval);
      final flag =
          (await _t.get('ussd_write_flag'))['ussd_write_flag']?.toString();
      if (flag == '15') continue;
      if (flag == '16') {
        final d = await _t.get('ussd_data_info');
        return UssdResult(
            content: decodeUcs2Hex(d['ussd_data']?.toString() ?? ''));
      }
      throw CommandFailedException(_ussdFailureMessage(flag), result: flag);
    }
    throw const CommandFailedException(
        'USSD request timed out waiting for a reply.');
  }

  String _ussdFailureMessage(String? flag) {
    switch (flag) {
      case '1':
        return 'No USSD service available. Check signal and try again.';
      case '4':
      case '3':
      case 'unknown':
        return 'USSD request timed out.';
      case '10':
        return 'USSD session busy — try again in a moment.';
      case '99':
        // Confirmed on a real M100: the device's own firmware config ships
        // HAS_USSD:false, and its stock web UI has no USSD page at all — this
        // is a device/firmware limitation, not a transient carrier response.
        return "This router's firmware does not support USSD codes "
            '(confirmed unsupported by the device itself, not just this code).';
      case '41':
        return 'Operation not supported by the SIM/network.';
      case '2':
        return 'USSD session was terminated by the network.';
      default:
        return 'USSD failed (code $flag).';
    }
  }

  @override
  Future<void> reboot() async {
    final res = await _t.set({'goformId': 'REBOOT_DEVICE'});
    _ensureOk(res, 'reboot');
  }

  @override
  Future<void> powerOff() async {
    final res = await _t.set({'goformId': 'TURN_OFF_DEVICE'});
    _ensureOk(res, 'power off');
  }

  @override
  Future<void> factoryReset() async {
    final res = await _t.set({'goformId': 'RESTORE_FACTORY_SETTINGS'});
    _ensureOk(res, 'factory reset');
  }

  @override
  void dispose() => _t.dispose();

  // --- helpers --------------------------------------------------------------

  // WPA-family security modes that carry a passphrase (vs. OPEN/SHARED/WEP).
  static const _wpaModes = {
    'WPAPSK',
    'WPA2PSK',
    'WPAPSKWPA2PSK',
    'WPA3Personal',
    'WPA2WPA3',
  };

  /// Maps the device's `EncrypType` to the `cipher` write value the firmware
  /// expects: TKIP→0, AES→1, anything else (TKIP+AES)→2.
  String _cipherFor(String? encryptType) {
    switch (encryptType) {
      case 'TKIP':
        return '0';
      case 'AES':
        return '1';
      default:
        return '2';
    }
  }

  /// The primary WiFi key. `WPAPSK1_encode` is base64 of the passphrase; fall
  /// back to the plaintext `WPAPSK1`, then to empty (masked by the device).
  String _decodeWifiPassword(String? encoded, String? plain) {
    final e = encoded?.trim() ?? '';
    if (e.isNotEmpty) {
      try {
        return utf8.decode(base64.decode(e));
      } on FormatException {
        // Not valid base64 — fall through to the plaintext field.
      }
    }
    return plain ?? '';
  }

  void _ensureOk(Map<String, dynamic> res, String action) {
    final result = res['result']?.toString();
    if (result != null && result != '0' && result != 'success') {
      throw CommandFailedException('Failed to $action', result: result);
    }
  }

  String? _bandLabel(String? v) {
    switch (v) {
      case 'b':
      case 'g':
      case 'n':
      case 'bg':
      case 'bgn':
        return '2.4 GHz';
      case 'a':
      case 'ac':
      case 'an':
        return '5 GHz';
      default:
        return v;
    }
  }

  String? _lteBand(String? v) {
    if (v == null || v.isEmpty) return null;
    return 'B$v'; // e.g. "3" -> "B3"
  }

  /// `battery_pers` is a 0..4 bar level (firmware: 1=power_one … 4=power_full,
  /// 0/empty=power_out). Clamp into range; null if unreadable.
  int? _batteryLevel(Object? v) {
    final n = parseIntOrNull(v);
    if (n == null) return null;
    return n.clamp(0, DeviceStatus.batteryLevelMax);
  }

  WanState _wanState(String? v) {
    switch (v) {
      case 'ppp_connected':
      case 'ipv4_ipv6_connected':
        return WanState.connected;
      case 'ppp_disconnected':
        return WanState.disconnected;
      case 'ppp_connecting':
        return WanState.connecting;
      case 'ppp_disconnecting':
        return WanState.disconnecting;
      default:
        return WanState.unknown;
    }
  }

  SimState _simState(String? v) {
    switch (v) {
      case 'modem_sim_undetected':
      case 'modem_undetected':
      case 'modem_no_sim':
        return SimState.absent;
      case 'modem_waitpin':
      case 'modem_waitpuk':
        return SimState.pinRequired;
      case 'modem_init_complete':
        return SimState.ready;
      default:
        return SimState.unknown;
    }
  }

  DateTime? _parseZteDate(String? s) {
    if (s == null || s.isEmpty) return null;
    // "yy,MM,dd,HH,mm,ss,+tz" (tz in 15-min units). Best-effort local parse.
    final parts = s.split(',');
    if (parts.length < 6) return null;
    int p(int i) => int.tryParse(parts[i].trim()) ?? 0;
    return DateTime(2000 + p(0), p(1), p(2), p(3), p(4), p(5));
  }

  String _zteNow() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final tzQuarters = (n.timeZoneOffset.inMinutes ~/ 15);
    return '${n.year % 100};${two(n.month)};${two(n.day)};'
        '${two(n.hour)};${two(n.minute)};${two(n.second)};'
        '${tzQuarters >= 0 ? '+' : '-'}${tzQuarters.abs()}';
  }
}
