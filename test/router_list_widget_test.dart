import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:routspan/data/profile_store.dart';
import 'package:routspan/data/router_profile.dart';
import 'package:routspan/features/routers/router_list_screen.dart';
import 'package:routspan/providers/profiles.dart';

import 'profiles_test.dart' show MemSecretStore;

Widget _app(MemSecretStore secrets) => ProviderScope(
      overrides: [
        profileStoreProvider.overrideWithValue(ProfileStore(secrets: secrets)),
      ],
      child: const MaterialApp(home: RouterListScreen()),
    );

void main() {
  testWidgets('lists saved routers with the default starred', (t) async {
    SharedPreferences.setMockInitialValues({
      'router_profiles': RouterProfile.encodeList(const [
        RouterProfile(id: '1', name: 'Home OLAX', host: '192.168.8.1'),
        RouterProfile(id: '2', name: 'Office', host: '192.168.0.1'),
      ]),
      'default_profile_id': '1',
    });

    await t.pumpWidget(_app(MemSecretStore()));
    await t.pumpAndSettle();

    expect(find.text('Home OLAX'), findsOneWidget);
    expect(find.text('192.168.8.1'), findsOneWidget);
    expect(find.text('Office'), findsOneWidget);
    // Default indicator present.
    expect(find.byIcon(Icons.star), findsOneWidget);
  });

  testWidgets('tapping a router with no saved password prompts for it',
      (t) async {
    SharedPreferences.setMockInitialValues({
      'router_profiles': RouterProfile.encodeList(const [
        RouterProfile(id: '1', name: 'Home OLAX', host: '192.168.8.1'),
      ]),
      'default_profile_id': '1',
    });

    // No password stored, so connecting must ask for one.
    await t.pumpWidget(_app(MemSecretStore()));
    await t.pumpAndSettle();

    await t.tap(find.byType(ListTile).first);
    await t.pumpAndSettle();

    expect(find.text('Password for Home OLAX'), findsOneWidget);
    expect(find.text('Save password'), findsOneWidget);
  });
}
