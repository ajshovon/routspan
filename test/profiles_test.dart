import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:routspan/data/profile_store.dart';
import 'package:routspan/data/router_profile.dart';
import 'package:routspan/providers/profiles.dart';

/// In-memory secret store so tests don't touch the platform keychain.
class MemSecretStore implements SecretStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
}

ProviderContainer _container(MemSecretStore secrets) {
  final c = ProviderContainer(overrides: [
    profileStoreProvider.overrideWithValue(ProfileStore(secrets: secrets)),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('RouterProfile json', () {
    test('round-trips through encode/decode', () {
      final list = [
        const RouterProfile(id: '1', name: 'Home', host: '192.168.8.1'),
        const RouterProfile(
            id: '2', name: 'Work', host: '10.0.0.1', reqproc: false),
      ];
      final decoded = RouterProfile.decodeList(RouterProfile.encodeList(list));
      expect(decoded.length, 2);
      expect(decoded[1].name, 'Work');
      expect(decoded[1].reqproc, isFalse);
    });

    test('decode tolerates junk', () {
      expect(RouterProfile.decodeList(null), isEmpty);
      expect(RouterProfile.decodeList('not json'), isEmpty);
    });
  });

  group('ProfilesController', () {
    test('first added router becomes default and stores its password',
        () async {
      final secrets = MemSecretStore();
      final c = _container(secrets);
      final ctrl = c.read(profilesControllerProvider.notifier);
      await c.read(profilesControllerProvider.future);

      final p = await ctrl.add(
          name: 'Home', host: '192.168.8.1', reqproc: true, password: 'secret');

      final s = c.read(profilesControllerProvider).value!;
      expect(s.profiles.single.name, 'Home');
      expect(s.defaultId, p.id);
      expect(await ctrl.passwordFor(p.id), 'secret');
    });

    test('setDefault moves the default; add(makeDefault) overrides', () async {
      final c = _container(MemSecretStore());
      final ctrl = c.read(profilesControllerProvider.notifier);
      await c.read(profilesControllerProvider.future);

      final a = await ctrl.add(name: 'A', host: '1.1.1.1', reqproc: true);
      final b = await ctrl.add(
          name: 'B', host: '2.2.2.2', reqproc: true, makeDefault: true);

      expect(c.read(profilesControllerProvider).value!.defaultId, b.id);
      await ctrl.setDefault(a.id);
      expect(c.read(profilesControllerProvider).value!.defaultId, a.id);
    });

    test('remove deletes profile + password and clears default', () async {
      final secrets = MemSecretStore();
      final c = _container(secrets);
      final ctrl = c.read(profilesControllerProvider.notifier);
      await c.read(profilesControllerProvider.future);

      final p = await ctrl.add(
          name: 'Home', host: '192.168.8.1', reqproc: true, password: 'pw');
      await ctrl.remove(p.id);

      final s = c.read(profilesControllerProvider).value!;
      expect(s.profiles, isEmpty);
      expect(s.defaultId, isNull);
      expect(await ctrl.passwordFor(p.id), isNull);
    });

    test('state persists across a fresh controller (SharedPreferences)',
        () async {
      final secrets = MemSecretStore();
      final c1 = _container(secrets);
      final ctrl1 = c1.read(profilesControllerProvider.notifier);
      await c1.read(profilesControllerProvider.future);
      await ctrl1.add(
          name: 'Home', host: '192.168.8.1', reqproc: true, password: 'pw');

      // New container = simulates app restart; SharedPreferences is shared.
      final c2 = _container(secrets);
      final s2 = await c2.read(profilesControllerProvider.future);
      expect(s2.profiles.single.name, 'Home');
      expect(s2.defaultProfile, isNotNull);
      expect(
          await c2
              .read(profilesControllerProvider.notifier)
              .passwordFor(s2.profiles.single.id),
          'pw');
    });
  });
}
