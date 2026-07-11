import 'package:flutter_test/flutter_test.dart';

import 'package:routspan/core/crypto.dart';

void main() {
  group('crypto helpers', () {
    test('sha256Hex is 64 lowercase hex chars', () {
      final h = sha256Hex('admin');
      expect(h.length, 64);
      expect(h, equals(h.toLowerCase()));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(h), isTrue);
    });

    test('sha256HexUpper is upper-cased', () {
      expect(sha256HexUpper('admin'), equals(sha256Hex('admin').toUpperCase()));
    });

    test('md5Hex is 32 hex chars', () {
      expect(md5Hex('x').length, 32);
    });

    test('base64Password matches known vector', () {
      expect(base64Password('admin'), 'YWRtaW4=');
    });

    test('zteLoginDigest is deterministic, upper-cased, 64 chars', () {
      final a = zteLoginDigest('admin', 'ABCD1234');
      final b = zteLoginDigest('admin', 'ABCD1234');
      expect(a, equals(b));
      expect(a.length, 64);
      expect(a, equals(a.toUpperCase()));
      // Different LD -> different digest.
      expect(zteLoginDigest('admin', 'ZZZZ'), isNot(equals(a)));
    });

    test('zteAd derivation is deterministic and case-configurable', () {
      final lower = zteAd('1.0', '2.0', 'RD123');
      final upper = zteAd('1.0', '2.0', 'RD123', upper: true);
      expect(lower.length, 32);
      expect(upper, equals(lower.toUpperCase()));
    });
  });
}
