import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:routspan/data/router_profile.dart';

/// Small seam over per-key secret persistence so it can be faked in tests and
/// so a platform failure (e.g. a locked keychain) degrades gracefully instead
/// of crashing.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Default [SecretStore] backed by the platform keychain/keystore. All calls are
/// wrapped so a secure-storage failure just means "no saved password".
///
/// On macOS we use the legacy login keychain (`useDataProtectionKeyChain:
/// false`); the default data-protection keychain needs a `keychain-access-groups`
/// entitlement, which requires a paid Apple developer certificate. Android/iOS
/// are unaffected by this option.
class SecureSecretStore implements SecretStore {
  const SecureSecretStore([
    this._storage = const FlutterSecureStorage(
      mOptions: MacOsOptions(useDataProtectionKeyChain: false),
    ),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      // Ignore — the profile is still saved; the user re-enters the password.
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
  }
}

/// Persists the list of [RouterProfile]s and the default id in
/// SharedPreferences, and each profile's password in [SecretStore].
class ProfileStore {
  ProfileStore({SecretStore? secrets})
      : _secrets = secrets ?? const SecureSecretStore();

  final SecretStore _secrets;

  static const _kProfiles = 'router_profiles';
  static const _kDefaultId = 'default_profile_id';
  static const _pwPrefix = 'router_pw_';

  Future<({List<RouterProfile> profiles, String? defaultId})> load() async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = RouterProfile.decodeList(prefs.getString(_kProfiles));
    final defaultId = prefs.getString(_kDefaultId);
    final valid = (defaultId != null && profiles.any((p) => p.id == defaultId))
        ? defaultId
        : null;
    return (profiles: profiles, defaultId: valid);
  }

  Future<void> saveProfiles(List<RouterProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProfiles, RouterProfile.encodeList(profiles));
  }

  Future<void> saveDefaultId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_kDefaultId);
    } else {
      await prefs.setString(_kDefaultId, id);
    }
  }

  Future<String?> readPassword(String id) => _secrets.read('$_pwPrefix$id');
  Future<void> writePassword(String id, String pw) =>
      _secrets.write('$_pwPrefix$id', pw);
  Future<void> deletePassword(String id) => _secrets.delete('$_pwPrefix$id');
}
