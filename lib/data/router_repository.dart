import 'package:routspan/data/models.dart';

export 'package:routspan/data/models.dart';

/// The abstraction seam. Every router driver implements this vendor-neutral
/// interface; the UI and providers only ever talk to this type.
///
/// Today there is exactly one implementation (`OlaxM100Client`). When a second
/// router is added, introduce a small factory that returns the right
/// [RouterRepository] for a saved connection profile — that is the "refactor
/// later" step, and it is cheap precisely because this seam already exists.
///
/// Methods throw [RouterException] subclasses (see `core/errors.dart`) on
/// failure. `Future<void>` methods complete on success.
abstract class RouterRepository {
  /// Authenticate. Must be called (and succeed) before any other call.
  Future<void> login(String password);

  Future<void> logout();

  /// Cheap check used to decide whether a re-login is needed.
  Future<bool> isLoggedIn();

  Future<DeviceStatus> getStatus();

  /// Device identity + LAN details for the "About" screen.
  Future<DeviceInfo> getDeviceInfo();

  Future<DataUsage> getDataUsage();

  Future<List<SmsMessage>> listSms();

  /// SMS storage usage (device + SIM), for the inbox capacity indicator.
  Future<SmsCapacity> getSmsCapacity();

  Future<void> sendSms(String number, String message);

  Future<void> deleteSms(List<int> ids);

  /// Mark one or more messages as read (`tag=0`).
  Future<void> markSmsRead(List<int> ids);

  Future<WifiConfig> getWifi();

  Future<void> setWifi(WifiConfig config);

  Future<List<ConnectedDevice>> getConnectedDevices();

  /// Rename a connected device in the router's host list (`EDIT_HOSTNAME`).
  Future<void> renameDevice(String mac, String hostname);

  Future<UssdResult> sendUssd(String code);

  /// Bring the cellular WAN up or down (`CONNECT_NETWORK`/`DISCONNECT_NETWORK`).
  /// This is the "mobile data on/off" switch — it does not affect the LAN/WiFi
  /// the app is talking over.
  Future<void> setMobileData(bool enabled);

  Future<void> reboot();

  /// Power the device off (`TURN_OFF_DEVICE`). It must be turned back on by hand.
  Future<void> powerOff();

  /// Restore factory defaults (`RESTORE_FACTORY_SETTINGS`). Wipes all settings.
  Future<void> factoryReset();

  /// Release any underlying resources (HTTP client, cookie jar).
  void dispose();
}
