import 'package:flutter_test/flutter_test.dart';

import 'package:routspan/core/errors.dart';
import 'package:routspan/data/olax/olax_m100_client.dart';
import 'package:routspan/data/olax/zte_api_transport.dart';

/// Answers `get('ussd_write_flag')` with successive values from [flagSequence]
/// (repeating the last one once exhausted) and `get('ussd_data_info')` with
/// [dataInfo] — lets us script the real poll-then-fetch flow the firmware
/// uses, which the shared `FakeTransport` (a single static response map)
/// can't represent.
class _UssdTransport extends ZteApiTransport {
  _UssdTransport({required this.flagSequence, this.dataInfo = const {}})
      : super(host: '127.0.0.1', config: ZteConfig.reqproc);

  final List<String> flagSequence;
  final Map<String, dynamic> dataInfo;
  int _flagCalls = 0;
  int getCalls = 0;

  @override
  Future<T> withReloginRetry<T>(Future<T> Function() action) => action();

  @override
  Future<Map<String, dynamic>> get(String cmd) async {
    getCalls++;
    if (cmd == 'ussd_write_flag') {
      final i = _flagCalls < flagSequence.length
          ? _flagCalls
          : flagSequence.length - 1;
      _flagCalls++;
      return {'ussd_write_flag': flagSequence[i]};
    }
    if (cmd == 'ussd_data_info') return dataInfo;
    return {};
  }

  @override
  Future<Map<String, dynamic>> getMulti(List<String> cmds) async =>
      {for (final c in cmds) c: ''};

  @override
  Future<Map<String, dynamic>> getWithParams(
          Map<String, String> params) async =>
      {};

  @override
  Future<Map<String, dynamic>> set(Map<String, String> form,
      {bool withAd = true}) async {
    return {'result': 'success'};
  }
}

void main() {
  group('OlaxM100Client USSD', () {
    test(
        'polls ussd_write_flag ALONE while "15", then fetches ussd_data_info '
        'alone and decodes ussd_data on "16" (regression: used to combine '
        'these into one multi-read that always came back empty)', () async {
      final t = _UssdTransport(
        flagSequence: ['15', '15', '16'],
        // "Balance: 10 BDT" UTF-16BE hex.
        dataInfo: {
          'ussd_action': '0',
          'ussd_dcs': '0',
          'ussd_data':
              '00420061006C0061006E00630065003A00200031003000200042004400540020',
        },
      );
      final client = OlaxM100Client(
        host: 'x',
        transport: t,
        ussdPollInterval: Duration.zero,
      );

      final result = await client.sendUssd('*123#');
      expect(result.content, 'Balance: 10 BDT ');
      expect(t.getCalls, 4); // 3x write_flag poll + 1x data_info fetch
    });

    test('surfaces the real firmware failure code instead of "(no response)"',
        () async {
      final t = _UssdTransport(flagSequence: ['99']);
      final client = OlaxM100Client(
        host: 'x',
        transport: t,
        ussdPollInterval: Duration.zero,
      );

      await expectLater(
        client.sendUssd('*123#'),
        throwsA(isA<CommandFailedException>().having(
          (e) => e.message,
          'message',
          "This router's firmware does not support USSD codes "
              '(confirmed unsupported by the device itself, not just this code).',
        )),
      );
    });

    test('maps each known firmware flag to a distinct message', () async {
      final cases = {
        '1': 'No USSD service available. Check signal and try again.',
        '3': 'USSD request timed out.',
        '4': 'USSD request timed out.',
        'unknown': 'USSD request timed out.',
        '10': 'USSD session busy — try again in a moment.',
        '41': 'Operation not supported by the SIM/network.',
        '2': 'USSD session was terminated by the network.',
        '77':
            'USSD failed (code 77).', // unmapped code still surfaces, not silent
      };
      for (final entry in cases.entries) {
        final t = _UssdTransport(flagSequence: [entry.key]);
        final client = OlaxM100Client(
          host: 'x',
          transport: t,
          ussdPollInterval: Duration.zero,
        );
        await expectLater(
          client.sendUssd('*123#'),
          throwsA(isA<CommandFailedException>()
              .having((e) => e.message, 'message', entry.value)),
          reason: 'flag ${entry.key}',
        );
      }
    });

    test('gives up after ussdPollMaxAttempts if flag never resolves', () async {
      final t = _UssdTransport(flagSequence: ['15']); // never settles
      final client = OlaxM100Client(
        host: 'x',
        transport: t,
        ussdPollInterval: Duration.zero,
        ussdPollMaxAttempts: 3,
      );

      await expectLater(
        client.sendUssd('*123#'),
        throwsA(isA<CommandFailedException>().having(
          (e) => e.message,
          'message',
          'USSD request timed out waiting for a reply.',
        )),
      );
      expect(t.getCalls, 3);
    });
  });
}
