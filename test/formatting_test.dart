import 'package:flutter_test/flutter_test.dart';

import 'package:routspan/core/formatting.dart';

void main() {
  group('formatBytes', () {
    test('handles zero and negatives', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(-5), '0 B');
    });

    test('bytes below 1KB have no decimals', () {
      expect(formatBytes(500), '500 B');
    });

    test('scales to KB/MB/GB', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(1024 * 1024 * 1024), '1.0 GB');
    });
  });

  group('parseIntSafe', () {
    test('parses strings, nums, and null', () {
      expect(parseIntSafe('42'), 42);
      expect(parseIntSafe(42), 42);
      expect(parseIntSafe(42.9), 42);
      expect(parseIntSafe(null), 0);
      expect(parseIntSafe('not a number', fallback: -1), -1);
    });
  });
}
