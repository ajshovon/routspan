// Vendor-neutral domain models. Defined ONCE at the abstraction seam so every
// router driver maps its own wire format into these. No ZTE/vendor specifics
// belong here.

/// WAN link state. Named `WanState` (not `ConnectionState`) to avoid colliding
/// with Flutter's built-in `ConnectionState` enum.
enum WanState { connected, disconnected, connecting, disconnecting, unknown }

enum SimState { ready, absent, pinRequired, unknown }

class DeviceStatus {
  const DeviceStatus({
    required this.networkType,
    required this.signalBars,
    required this.operator,
    required this.roaming,
    required this.wan,
    required this.simState,
    this.rssiDbm,
    this.wanIp,
    this.batteryPercent,
    this.batteryLevel,
    this.batteryCharging,
    this.rsrp,
    this.rsrq,
    this.sinr,
    this.band,
    this.cellId,
    this.unreadSms = 0,
    this.connectedCount = 0,
  });

  /// e.g. "LTE", "5G", "WCDMA".
  final String networkType;

  /// 0..5 signal strength for the UI.
  final int signalBars;
  final int? rssiDbm;
  final String operator;
  final bool roaming;
  final WanState wan;
  final SimState simState;
  final String? wanIp;

  /// True battery percentage (0–100) — only when the model reports one
  /// (`battery_vol_percent`). Null on the OLAX M100, which leaves it empty.
  final int? batteryPercent;

  /// Battery bar level 0–[batteryLevelMax] from `battery_pers` (the firmware
  /// picks power_one/two/three/full/out from this). This is what the M100
  /// actually exposes — it is NOT a percentage.
  final int? batteryLevel;

  final bool? batteryCharging;

  /// Number of battery bars a full battery shows (firmware: power_full == 4).
  static const batteryLevelMax = 4;

  /// Best-effort percentage for display: the real reading when present, else an
  /// approximation from the 0–4 bar level (3/4 → ~75%).
  int? get batteryApproxPercent =>
      batteryPercent ??
      (batteryLevel == null
          ? null
          : (batteryLevel! * 100 / batteryLevelMax).round());

  // Detailed cellular signal (LTE).
  final int? rsrp;
  final int? rsrq;
  final int? sinr;
  final String? band;
  final String? cellId;

  // Live counts pulled from the same status poll (drive nav badges).
  final int unreadSms;
  final int connectedCount;

  static const empty = DeviceStatus(
    networkType: '—',
    signalBars: 0,
    operator: '—',
    roaming: false,
    wan: WanState.unknown,
    simState: SimState.unknown,
  );
}

/// Device identity + LAN details (the "About" screen). All optional because a
/// given model may leave some fields empty.
class DeviceInfo {
  const DeviceInfo({
    this.model,
    this.firmware,
    this.hardware,
    this.imei,
    this.imsi,
    this.iccid,
    this.phoneNumber,
    this.lanIp,
    this.lanNetmask,
    this.localDomain,
    this.maxDevices,
    this.dhcpEnabled,
    this.dhcpStart,
    this.dhcpEnd,
    this.dhcpLeaseHours,
  });

  final String? model;
  final String? firmware;
  final String? hardware;
  final String? imei;
  final String? imsi;
  final String? iccid;
  final String? phoneNumber;
  final String? lanIp;
  final String? lanNetmask;
  final String? localDomain;
  final int? maxDevices;
  final bool? dhcpEnabled;
  final String? dhcpStart;
  final String? dhcpEnd;
  final int? dhcpLeaseHours;
}

class DataUsage {
  const DataUsage({
    required this.sessionBytes,
    required this.monthlyBytes,
    this.sessionDuration,
    this.monthlyDuration,
    this.txThroughput = 0,
    this.rxThroughput = 0,
    this.limitEnabled = false,
    this.limitByTime = false,
    this.limitSize,
    this.alertPercent,
  });

  final int sessionBytes;
  final int monthlyBytes;
  final Duration? sessionDuration;

  /// Total connected time counted against this billing month.
  final Duration? monthlyDuration;

  /// Live upload/download rate in bytes per second.
  final int txThroughput;
  final int rxThroughput;

  /// Whether the device has a monthly usage cap configured
  /// (`data_volume_limit_switch`).
  final bool limitEnabled;

  /// True when the cap is a time budget rather than a data budget
  /// (`data_volume_limit_unit == "time"`).
  final bool limitByTime;

  /// The raw cap value the device stores (`data_volume_limit_size`) — bytes for
  /// a data cap, seconds for a time cap. Null when no cap is set.
  final int? limitSize;

  /// Alert threshold as a percentage of the cap (`data_volume_alert_percent`).
  final int? alertPercent;

  static const empty = DataUsage(sessionBytes: 0, monthlyBytes: 0);
}

class SmsMessage {
  const SmsMessage({
    required this.id,
    required this.number,
    required this.content,
    required this.timestamp,
    required this.isRead,
    required this.isSent,
    this.isDraft = false,
  });

  final int id;
  final String number;
  final String content;
  final DateTime? timestamp;
  final bool isRead;
  final bool isSent;
  final bool isDraft;

  /// True for messages we received (as opposed to sent or drafted).
  bool get isIncoming => !isSent && !isDraft;
}

/// All messages exchanged with a single [number], newest last — the unit the
/// conversation UI renders. Built by [groupSmsIntoConversations]; not read from
/// the device (the firmware stores a flat list and the stock UI groups the same
/// way, by sender/recipient number).
class SmsConversation {
  const SmsConversation({required this.number, required this.messages});

  /// The other party — a phone number or an alphanumeric sender id ("Robi").
  final String number;

  /// Messages with this party, ordered oldest → newest.
  final List<SmsMessage> messages;

  SmsMessage get latest => messages.last;
  int get unreadCount =>
      messages.where((m) => !m.isRead && m.isIncoming).length;
  bool get hasUnread => unreadCount > 0;
  List<int> get unreadIds => [
        for (final m in messages)
          if (!m.isRead && m.isIncoming) m.id
      ];
  List<int> get allIds => [for (final m in messages) m.id];
}

/// Groups a flat SMS list into per-number conversations, most-recently-active
/// first. Ordering uses the message `id`, which the device increments over time.
List<SmsConversation> groupSmsIntoConversations(List<SmsMessage> messages) {
  final byNumber = <String, List<SmsMessage>>{};
  for (final m in messages) {
    (byNumber[m.number] ??= <SmsMessage>[]).add(m);
  }
  final convos = [
    for (final entry in byNumber.entries)
      SmsConversation(
        number: entry.key,
        messages: [...entry.value]..sort((a, b) => a.id.compareTo(b.id)),
      ),
  ];
  convos.sort((a, b) => b.latest.id.compareTo(a.latest.id));
  return convos;
}

/// SMS storage usage, split across device (NV) and SIM memory
/// (`sms_capacity_info`). Mirrors the stock UI's "Device SMS (7/20)" header.
class SmsCapacity {
  const SmsCapacity({
    required this.deviceUsed,
    required this.deviceTotal,
    required this.simUsed,
    required this.simTotal,
  });

  final int deviceUsed;
  final int deviceTotal;
  final int simUsed;
  final int simTotal;

  static const empty =
      SmsCapacity(deviceUsed: 0, deviceTotal: 0, simUsed: 0, simTotal: 0);
}

class WifiConfig {
  const WifiConfig({
    required this.ssid,
    required this.password,
    this.band,
    this.hidden = false,
    this.enabled = true,
    this.authMode,
    this.encryptType,
    this.maxDevices,
    this.guestEnabled = false,
  });

  final String ssid;
  final String password;

  /// e.g. "2.4GHz", "5GHz", "Auto" — null if the driver can't read it.
  final String? band;
  final bool hidden;
  final bool enabled;

  /// Security mode as the device reports it (e.g. "WPA2PSK", "OPEN"). Preserved
  /// so a save round-trips the existing security rather than downgrading it.
  final String? authMode;

  /// Cipher/encryption the device reports (e.g. "AES", "TKIP"). Drives the
  /// `cipher` write parameter.
  final String? encryptType;

  /// Max simultaneous WiFi clients (`MAX_Access_num`).
  final int? maxDevices;

  /// Whether the secondary/guest SSID is on (`m_ssid_enable`).
  final bool guestEnabled;

  WifiConfig copyWith({
    String? ssid,
    String? password,
    String? band,
    bool? hidden,
    bool? enabled,
    String? authMode,
    String? encryptType,
    int? maxDevices,
    bool? guestEnabled,
  }) {
    return WifiConfig(
      ssid: ssid ?? this.ssid,
      password: password ?? this.password,
      band: band ?? this.band,
      hidden: hidden ?? this.hidden,
      enabled: enabled ?? this.enabled,
      authMode: authMode ?? this.authMode,
      encryptType: encryptType ?? this.encryptType,
      maxDevices: maxDevices ?? this.maxDevices,
      guestEnabled: guestEnabled ?? this.guestEnabled,
    );
  }
}

class ConnectedDevice {
  const ConnectedDevice({
    required this.hostname,
    required this.ipAddress,
    required this.macAddress,
    this.deviceType,
    this.connectTime,
    this.ipType,
  });

  final String hostname;
  final String ipAddress;
  final String macAddress;

  /// e.g. "wifi" / "usb" / "rj45".
  final String? deviceType;
  final String? connectTime;
  final String? ipType;
}

class UssdResult {
  const UssdResult({required this.content});
  final String content;
}
