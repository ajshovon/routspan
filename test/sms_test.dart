import 'package:flutter_test/flutter_test.dart';

import 'package:routspan/data/models.dart';
import 'package:routspan/data/olax/olax_m100_client.dart';

import 'olax_m100_client_test.dart' show FakeTransport;

SmsMessage _msg(int id, String number,
    {bool read = true, bool sent = false, bool draft = false}) {
  return SmsMessage(
    id: id,
    number: number,
    content: 'm$id',
    timestamp: DateTime(2026, 7, 11).add(Duration(minutes: id)),
    isRead: read,
    isSent: sent,
    isDraft: draft,
  );
}

void main() {
  group('groupSmsIntoConversations', () {
    test('groups by number, most-recent conversation first', () {
      final convos = groupSmsIntoConversations([
        _msg(10, 'Robi'),
        _msg(5, '1213'),
        _msg(4, 'Robi'),
        _msg(2, '21209'),
        _msg(1, 'Robi'),
      ]);
      expect(convos.map((c) => c.number).toList(), ['Robi', '1213', '21209']);
      // Robi thread ordered oldest -> newest by id.
      expect(convos.first.messages.map((m) => m.id).toList(), [1, 4, 10]);
      expect(convos.first.latest.id, 10);
    });

    test('unread count only counts incoming unread, not sent/draft', () {
      final convo = groupSmsIntoConversations([
        _msg(1, 'X', read: false), // incoming unread
        _msg(2, 'X', read: false, sent: true), // sent (not counted)
        _msg(3, 'X', read: false, draft: true), // draft (not counted)
        _msg(4, 'X', read: true), // read
      ]).single;
      expect(convo.hasUnread, isTrue);
      expect(convo.unreadCount, 1);
      expect(convo.unreadIds, [1]);
      expect(convo.allIds, [1, 2, 3, 4]);
    });

    test('empty input yields no conversations', () {
      expect(groupSmsIntoConversations(const []), isEmpty);
    });
  });

  group('getSmsCapacity', () {
    test('sums device + SIM used across rev/send/draft boxes', () async {
      final t = FakeTransport({
        'sms_nv_total': '20',
        'sms_nv_rev_total': '10',
        'sms_nv_send_total': '2',
        'sms_nv_draftbox_total': '1',
        'sms_sim_total': '50',
        'sms_sim_rev_total': '0',
        'sms_sim_send_total': '0',
        'sms_sim_draftbox_total': '0',
      });
      final client = OlaxM100Client(host: 'x', transport: t);
      final cap = await client.getSmsCapacity();
      expect(cap.deviceUsed, 13);
      expect(cap.deviceTotal, 20);
      expect(cap.simUsed, 0);
      expect(cap.simTotal, 50);
    });
  });

  group('markSmsRead', () {
    test('joins ids into a semicolon list; no-op when empty', () async {
      final t = FakeTransport({});
      final client = OlaxM100Client(host: 'x', transport: t);

      await client.markSmsRead([]);
      expect(t.posts, isEmpty);

      await client.markSmsRead([4, 9, 10]);
      expect(t.lastPost['goformId'], 'SET_MSG_READ');
      expect(t.lastPost['msg_id'], '4;9;10;');
      expect(t.lastPost['tag'], '0');
    });
  });
}
