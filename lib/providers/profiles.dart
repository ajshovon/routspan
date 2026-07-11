import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:routspan/data/profile_store.dart';
import 'package:routspan/data/router_profile.dart';

class ProfilesState {
  const ProfilesState({this.profiles = const [], this.defaultId});

  final List<RouterProfile> profiles;
  final String? defaultId;

  RouterProfile? get defaultProfile {
    for (final p in profiles) {
      if (p.id == defaultId) return p;
    }
    return null;
  }
}

/// Overridable in tests to inject a fake [SecretStore]/store.
final profileStoreProvider = Provider<ProfileStore>((ref) => ProfileStore());

/// Owns the saved-router list, the default selection, and password access.
class ProfilesController extends AsyncNotifier<ProfilesState> {
  ProfileStore get _store => ref.read(profileStoreProvider);

  @override
  Future<ProfilesState> build() async {
    final loaded = await _store.load();
    return ProfilesState(
        profiles: loaded.profiles, defaultId: loaded.defaultId);
  }

  ProfilesState get _s => state.valueOrNull ?? const ProfilesState();

  Future<RouterProfile> add({
    required String name,
    required String host,
    required bool reqproc,
    String? password,
    bool makeDefault = false,
  }) async {
    final id = _newId();
    final profile =
        RouterProfile(id: id, name: name, host: host, reqproc: reqproc);
    final list = [..._s.profiles, profile];
    await _store.saveProfiles(list);
    if (password != null && password.isNotEmpty) {
      await _store.writePassword(id, password);
    }
    // First-ever router becomes the default automatically.
    var defId = _s.defaultId;
    if (makeDefault || list.length == 1) {
      defId = id;
      await _store.saveDefaultId(id);
    }
    state = AsyncData(ProfilesState(profiles: list, defaultId: defId));
    return profile;
  }

  Future<void> edit(
    RouterProfile profile, {
    String? password,
    bool makeDefault = false,
  }) async {
    final list = [
      for (final p in _s.profiles)
        if (p.id == profile.id) profile else p,
    ];
    await _store.saveProfiles(list);
    if (password != null && password.isNotEmpty) {
      await _store.writePassword(profile.id, password);
    }
    var defId = _s.defaultId;
    if (makeDefault) {
      defId = profile.id;
      await _store.saveDefaultId(defId);
    }
    state = AsyncData(ProfilesState(profiles: list, defaultId: defId));
  }

  Future<void> remove(String id) async {
    final list = [
      for (final p in _s.profiles)
        if (p.id != id) p,
    ];
    await _store.saveProfiles(list);
    await _store.deletePassword(id);
    var defId = _s.defaultId;
    if (defId == id) {
      defId = null;
      await _store.saveDefaultId(null);
    }
    state = AsyncData(ProfilesState(profiles: list, defaultId: defId));
  }

  Future<void> setDefault(String? id) async {
    await _store.saveDefaultId(id);
    state = AsyncData(ProfilesState(profiles: _s.profiles, defaultId: id));
  }

  Future<void> forgetPassword(String id) => _store.deletePassword(id);

  Future<String?> passwordFor(String id) => _store.readPassword(id);

  Future<void> savePassword(String id, String pw) =>
      _store.writePassword(id, pw);

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_s.profiles.length}';
}

final profilesControllerProvider =
    AsyncNotifierProvider<ProfilesController, ProfilesState>(
        ProfilesController.new);

/// One-shot guard so the app auto-connects to the default router only once per
/// launch (not again after a manual disconnect).
final autoConnectAttemptedProvider = StateProvider<bool>((ref) => false);
