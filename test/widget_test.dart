import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:routspan/app.dart';

void main() {
  testWidgets('shows the router list (empty) on first launch', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: RouterApp()));
    await tester.pumpAndSettle();

    expect(find.text('My Routers'), findsOneWidget);
    expect(find.text('No routers yet'), findsOneWidget);
    expect(find.widgetWithText(FloatingActionButton, 'Add router'),
        findsOneWidget);
  });
}
