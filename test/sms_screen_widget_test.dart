import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:routspan/data/router_repository.dart';
import 'package:routspan/features/sms/sms_screen.dart';
import 'package:routspan/providers/session.dart';

/// Minimal in-memory repository so we can render the SMS UI without a device.
class FakeRepo implements RouterRepository {
  final List<SmsMessage> _messages = [
    SmsMessage(
        id: 1,
        number: 'Robi',
        content: 'Welcome to Robi',
        timestamp: DateTime(2026, 7, 11, 10, 0),
        isRead: true,
        isSent: false),
    SmsMessage(
        id: 2,
        number: 'Robi',
        content: 'Your balance is 9 TK',
        timestamp: DateTime(2026, 7, 11, 12, 0),
        isRead: false,
        isSent: false),
    SmsMessage(
        id: 3,
        number: '21209',
        content: 'OTP 680459',
        timestamp: DateTime(2026, 7, 10, 9, 0),
        isRead: true,
        isSent: false),
  ];

  final List<(String, String)> sent = [];

  @override
  Future<List<SmsMessage>> listSms() async => _messages;

  @override
  Future<SmsCapacity> getSmsCapacity() async => const SmsCapacity(
      deviceUsed: 3, deviceTotal: 20, simUsed: 0, simTotal: 50);

  @override
  Future<void> sendSms(String number, String message) async {
    sent.add((number, message));
  }

  @override
  Future<void> markSmsRead(List<int> ids) async {}

  @override
  Future<void> deleteSms(List<int> ids) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  Widget wrap(FakeRepo repo) => ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: SmsScreen()),
      );

  testWidgets('shows conversations grouped by number with capacity', (t) async {
    await t.pumpWidget(wrap(FakeRepo()));
    await t.pumpAndSettle();

    // One row per number (Robi + 21209), not one per message.
    expect(find.text('Robi'), findsOneWidget);
    expect(find.text('21209'), findsOneWidget);
    // Latest Robi message is the preview.
    expect(find.textContaining('Your balance is 9 TK'), findsOneWidget);
    // Capacity header.
    expect(find.textContaining('Device 3/20'), findsOneWidget);
  });

  testWidgets('tapping a conversation opens the chat thread', (t) async {
    await t.pumpWidget(wrap(FakeRepo()));
    await t.pumpAndSettle();

    await t.tap(find.text('Robi'));
    await t.pumpAndSettle();

    // Both messages in the thread are visible as bubbles.
    expect(find.text('Welcome to Robi'), findsOneWidget);
    expect(find.text('Your balance is 9 TK'), findsOneWidget);
    // Composer is present.
    expect(find.widgetWithText(TextField, 'Text message'), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);
  });

  testWidgets('composing sends to the thread number', (t) async {
    final repo = FakeRepo();
    await t.pumpWidget(wrap(repo));
    await t.pumpAndSettle();

    await t.tap(find.text('21209'));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), 'hi there');
    await t.tap(find.byIcon(Icons.send));
    await t.pumpAndSettle();

    expect(repo.sent, [('21209', 'hi there')]);
  });
}
